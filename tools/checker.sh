#!/bin/bash

cd $(dirname $0)
tools="$PWD/"
cd ..
hdir="$PWD/"
echo

# Declare Variante
rm -f ${hdir}.backups-done; touch ${hdir}.backups-done

# # #
# Parse config
if [ -f ${hdir}config ]; then
    source ${hdir}config
else
    source ${hdir}tools/config_example
fi


# # #
# Check done file
if [ ! -f ${reports}SBE-done ]; then
    echo "No backups done"
    echo -e "Subject: WARNING: Backup problem on $HOSTNAME\n\n There's no SBE-done file" | $(which sendmail) $mail
    exit 2
fi

# # #
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



# Clean backup operations
rm -f ${hdir}.backup.operations; touch ${hdir}.backup.operations;


for (( x=0; x < ${#b_dirs[@]}; x++ ))
do


    # # #
    # Dismantle hours
    if [[ "${b_invs[$x]}" =~ ^[0-9][hH]$ ]] || [[ "${b_invs[$x]}" =~ ^[0-9][0-9][hH]$ ]]; then

        hours=$(sed 's/[hH]//g' <<< ${b_invs[$x]})
        minloop=$(( 24 / $hours ))
        for (( hl=1; hl <= $minloop; hl++ ))
        do
            echo "<server>"                                                 >> ${hdir}.backup.operations
            echo "  <backupdirectory>${b_dirs[$x]}</backupdirectory>"       >> ${hdir}.backup.operations

            hour=$(( $hl *  $hours ))
            if [[ "${hour}" =~ ^[0-9]$ ]]; then
                echo "  <intervall>0$hour:00</intervall>"                   >> ${hdir}.backup.operations
            else
                echo "  <intervall>$hour:00</intervall>"                    >> ${hdir}.backup.operations
            fi

            echo "  <date>${b_dats[$x]}</date>"                             >> ${hdir}.backup.operations
            echo "  <type>${b_type[$x]}</type>"                             >> ${hdir}.backup.operations
            echo "</server>"                                                >> ${hdir}.backup.operations
        done


    # # #
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
			echo "<server>"                                                 >> ${hdir}.backup.operations
			echo "  <backupdirectory>${b_dirs[$x]}</backupdirectory>"       >> ${hdir}.backup.operations

			if [[ "${hours}" =~ ^[0-9]$ ]]; then
			    hour="0${hours}"
			else
			    hour="${hours}"
			fi
			if [[ "${minute}" =~ ^[0-9]$ ]]; then
			    echo "  <intervall>${hour}:0${minute}</intervall>"        >> ${hdir}.backup.operations
			else
			    echo "  <intervall>${hour}:${minute}</intervall>"         >> ${hdir}.backup.operations
			fi


			echo "  <date>${b_dats[$x]}</date>"                             >> ${hdir}.backup.operations
			echo "  <type>${b_type[$x]}</type>"                             >> ${hdir}.backup.operations
			echo "</server>"                                                >> ${hdir}.backup.operations
		fi
           
            done 
        done

    # # #
    # Rest
    else

        echo "<server>"                                                         >> ${hdir}.backup.operations
        echo "  <backupdirectory>${b_dirs[$x]}</backupdirectory>"               >> ${hdir}.backup.operations
        echo "  <intervall>${b_invs[$x]}</intervall>"                           >> ${hdir}.backup.operations
        echo "  <date>${b_dats[$x]}</date>"                                     >> ${hdir}.backup.operations
        echo "  <type>${b_type[$x]}</type>"                                     >> ${hdir}.backup.operations
        echo "</server>"                                                        >> ${hdir}.backup.operations

    fi
                        
done


# # #
# Parse .backup.operations
b_dirs=($(grep -oP '(?<=<backupdirectory>).*?(?=</backupdirectory>)' ${hdir}.backup.operations))
b_invs=($(grep -oP '(?<=<intervall>).*?(?=</intervall>)' ${hdir}.backup.operations))
b_dats=($(grep -oP '(?<=<date>).*?(?=</date>)' ${hdir}.backup.operations))
b_type=($(grep -oP '(?<=<type>).*?(?=</type>)' ${hdir}.backup.operations))



echo There are ${#b_dirs[@]} entries


# # #
# bugfix for qnap NAS
# -d '1 day' or -d 'yesterday' or -d '1 day ago' doesn't work
# w_day=$(date -d '1 day' +'%a')
# bugfix uses seconds
today=`date +"%s"`
yesterday=`expr $today - 86400`
w_day=`date --date="@${yesterday}" +"%a"`




# # #
# Find uniqe daynames from .backup.operations and execute if there is one day like the current day
find_dat=$(sed 's/,/ /g ' <<< ${b_dats[@]})
find_dat=$(echo "${find_dat[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' ')
if [[ ${find_dat[@]} =~ $w_day ]]; then

    # Loop through servernames from .backup.operations
    for (( x=0; x < ${#b_dirs[@]}; x++ ))
    do

        # Loop through backup logs
	cat ${reports}SBE-done | grep ${b_dirs[$x]} | while read -r logline ; do

            time=$(awk -F";" '{print $2}' <<< $logline)
            b_day=$(awk -F" " '{print $1}' <<< $time)
            b_tim=$(awk -F" " '{print $4}' <<< $time)
            daycount=$(echo ${b_dats[$x]} | grep ',' | wc -l)

            if [[ $b_day == $w_day ]]; then
     
                if [[ $b_tim =~ ${b_invs[$x]} ]]; then
                    
                    echo $logline
                    echo $logline >> ${hdir}.backups-done

                fi

            fi

        done
    done

fi


occurrence=$(cat ${hdir}.backups-done | wc -l)
daycount=$(grep -o -i $w_day <<< ${b_dats[@]} | wc -l)

if [[ $daycount == $occurrence ]]; then
    echo "All $daycount backups successfull ($occurrence)"
    echo
else
    echo "Backup problem: $daycount backups configured, $occurrence executed"
    echo -e "Subject: WARNING: Backup problem on $HOSTNAME\n\n There should've been $daycount backup operations but $occurrence operations are recognized" | $(which sendmail) $mail
fi
