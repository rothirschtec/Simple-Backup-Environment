#!/bin/bash

cd $(dirname $0)
tools="$PWD/"
cd ..
hdir="$PWD/"
echo

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


# # #
# Parse config
if [ -f ${hdir}config ]; then
    source ${hdir}config
else
    source ${hdir}tools/config_example
fi


echo There are ${#b_dirs[@]} entries
w_day=$(date +%a)
occurrence=0


find_dat=$(sed 's/,/ /g ' <<< ${b_dats[@]})
find_dat=$(echo "${find_dat[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' ')
if [[ ${find_dat[@]} =~ $w_day ]]; then

    echo Backup from today

    for (( x=0; x < ${#b_dirs[@]}; x++ ))
    do
        while read p 
        do
            if [[ $p =~ ${b_dirs[$x]} ]]; then

                time=$(awk -F";" '{print $2}' <<< $p)
                b_day=$(awk -F" " '{print $1}' <<< $time)
                b_tim=$(awk -F" " '{print $5}' <<< $time)
                daycount=$(echo ${b_dats[$x]} | grep ',' | wc -l)

                for (( y=1; y <= $(( ${daycount} + 1 )); y++ ))
                do

                    day=$(awk -F"," '{print $'${y}'}' <<< ${b_dats[$x]})
                    if [[ $b_day =~ ${day} ]] && [[ $b_day == $w_day ]]; then
               
                        if [[ $b_tim =~ ${b_invs[$x]} ]]; then
                            
                            echo $p 
                            (( occurrence++ ))
                        fi
                    fi
                done
            fi
        done < ${reports}SBE-done
    done

fi


daycount=$(grep -o -i $w_day <<< ${b_dats[@]} | wc -l)

if [[ $daycount == $occurrence ]]; then
    echo "All backups successfull"
    echo
fi
