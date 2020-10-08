#!/bin/bash

# Runs through backup.xml - recognizes intervalls and creates a file named .backup-operations
# in this file you can find each backup execution defined by intervalls

# Declare variables
cd $(dirname $0); tools="$PWD/"; cd ..; hdir="$PWD/";

# Clean template files
rm -f ${hdir}.backups-executed-yesterday; touch ${hdir}.backups-executed-yesterday
rm -f ${hdir}.backup-operations; touch ${hdir}.backup-operations;

# Parse config
if [ -f ${hdir}config ]; then
    source ${hdir}config
else
    source ${hdir}tools/config_example
fi

# Check done file
if [ ! -f ${reports}SBE-done ]; then
    echo "No backups done"
    echo -e "Subject: WARNING: Backup problem on $HOSTNAME\n\n There's no SBE-done file" | /usr/sbin/sendmail $mail
    exit 2
fi

# Parse backup.xml
if [ -f ${hdir}backup.xml ]; then

    b_dirs=($(grep -oP '(?<=<backupdirectory>).*?(?=</backupdirectory>)' ${hdir}backup.xml))
    b_invs=($(grep -oP '(?<=<intervall>).*?(?=</intervall>)' ${hdir}backup.xml))
    b_dats=($(grep -oP '(?<=<date>).*?(?=</date>)' ${hdir}backup.xml))
    b_type=($(grep -oP '(?<=<type>).*?(?=</type>)' ${hdir}backup.xml))

else

    cp ${hdir}tools/backup.xml-example ${hdir}backup.xml
    echo "Please configure your backup.xml file first"

fi

# Loop through backup.xml an recognize intervalls
for (( x=0; x < ${#b_dirs[@]}; x++ ))
do

    # Dismantle hours
    if [[ "${b_invs[$x]}" =~ ^[0-9][hH]$ ]] || [[ "${b_invs[$x]}" =~ ^[0-9][0-9][hH]$ ]]; then

        hours=$(sed 's/[hH]//g' <<< ${b_invs[$x]})
        minloop=$(( 24 / $hours ))
        for (( hl=1; hl <= $minloop; hl++ ))
        do
            echo "<server>"                                                 >> ${hdir}.backup-operations
            echo "  <backupdirectory>${b_dirs[$x]}</backupdirectory>"       >> ${hdir}.backup-operations

            hour=$(( $hl *  $hours ))
            if [[ "${hour}" =~ ^[0-9]$ ]]; then
                echo "  <intervall>0$hour:00</intervall>"                   >> ${hdir}.backup-operations
            else
                echo "  <intervall>$hour:00</intervall>"                    >> ${hdir}.backup-operations
            fi

            echo "  <date>${b_dats[$x]}</date>"                             >> ${hdir}.backup-operations
            echo "  <type>${b_type[$x]}</type>"                             >> ${hdir}.backup-operations
            echo "</server>"                                                >> ${hdir}.backup-operations
        done

    # Dismantle minutes
    elif [[ "${b_invs[$x]}" =~ ^[0-9][0-9][mM]$ ]] || [[ "${b_invs[$x]}" =~ ^[0-9][mM]$ ]]; then

        for (( hours=0; hours < 24; hours++ ))
        do
            minutes=$(sed 's/[mM]//g' <<< ${b_invs[$x]})
            minloop=$(( 60 / $minutes ))
            for (( hl=1; hl <= $minloop; hl++ ))
            do

            minute=$(( $hl *  $minutes ))
            if [[ $minute < 60 ]]; then
                echo "<server>"                                             >> ${hdir}.backup-operations
                echo "  <backupdirectory>${b_dirs[$x]}</backupdirectory>"   >> ${hdir}.backup-operations

                if [[ "${hours}" =~ ^[0-9]$ ]]; then
                    hour="0${hours}"
                else
                    hour="${hours}"
                fi
                if [[ "${minute}" =~ ^[0-9]$ ]]; then
                    echo "  <intervall>${hour}:0${minute}</intervall>"      >> ${hdir}.backup-operations
                else
                    echo "  <intervall>${hour}:${minute}</intervall>"       >> ${hdir}.backup-operations
                fi


                echo "  <date>${b_dats[$x]}</date>"                         >> ${hdir}.backup-operations
                echo "  <type>${b_type[$x]}</type>"                         >> ${hdir}.backup-operations
                echo "</server>"                                            >> ${hdir}.backup-operations
            fi
           
            done 
        done

    # Rest
    else

        echo "<server>"                                                     >> ${hdir}.backup-operations
        echo "  <backupdirectory>${b_dirs[$x]}</backupdirectory>"           >> ${hdir}.backup-operations
        echo "  <intervall>${b_invs[$x]}</intervall>"                       >> ${hdir}.backup-operations
        echo "  <date>${b_dats[$x]}</date>"                                 >> ${hdir}.backup-operations
        echo "  <type>${b_type[$x]}</type>"                                 >> ${hdir}.backup-operations
        echo "</server>"                                                    >> ${hdir}.backup-operations

    fi
                        
done

# Parse .backup-operations
b_dirs=($(grep -oP '(?<=<backupdirectory>).*?(?=</backupdirectory>)' ${hdir}.backup-operations))
b_invs=($(grep -oP '(?<=<intervall>).*?(?=</intervall>)' ${hdir}.backup-operations))
b_dats=($(grep -oP '(?<=<date>).*?(?=</date>)' ${hdir}.backup-operations))
b_type=($(grep -oP '(?<=<type>).*?(?=</type>)' ${hdir}.backup-operations))

echo; echo " a total of ${#b_dirs[@]} backup operations are configured"

# Define period of backups to check
# bugfix for qnap NAS
# -d '1 day' or -d 'yesterday' or -d '1 day ago' doesn't work
# w_day=$(date -d '1 day' +'%a')
# bugfix uses seconds
today=`date +"%s"`
yesterday=`expr $today - 86400`
w_day=`date --date="@${yesterday}" +"%a"`           # Day of week short name
w_day_num=`date --date="@${yesterday}" +"%-d"`      # Day of month as number
w_year=`date --date="@${yesterday}" +"%Y"`          # Year
w_month=`date --date="@${yesterday}" +"%b"`         # Month as 3 sign short name

# Loop through servernames from .backup-operations and write all executed lines from yesterday to .backups-executed-yesterday file
cat ${reports}SBE-done | awk -F";" '{print $3, $2}' | while read -r logline ; do

    echo $logline | awk -F" " '{print $1, $2, $3, $4, $7}' | grep $w_day | grep $w_month | grep $w_day_num | grep $w_year > ${hdir}.backups-executed-yesterday 

done

# Count backups and display
occurrence=$(cat ${hdir}.backups-executed-yesterday | wc -l)
dc1=$(grep -o -i $w_day <<< ${b_dats[@]} | wc -l) 
dc2=$(grep -o -i $w_day_num <<< ${b_dats[@]} | wc -l)
daycount=$(( ${dc1} + ${dc2} ))
echo " $daycount of them are meant to be executed yesterday"
echo " count of executed backups is $occurrence"; echo

echo " This executions are as following:"
servers=($(echo "${b_dirs[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
for server in ${servers[@]}
do
    scount=$(cat ${hdir}.backups-executed-yesterday | grep $server | wc -l)
    echo " $server: $scount"
done


if [[ $daycount == $occurrence ]]; then
    echo -e "Subject: SUCCESS: Backup on $HOSTNAME\n\n ($daycount) done" | /usr/sbin/sendmail $mail
else
    echo -e "Subject: WARNING: Backup problem on $HOSTNAME\n\n There should've been $daycount backup operations but $occurrence operations are recognized" | /usr/sbin/sendmail $mail
fi
