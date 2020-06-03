#!/bin/bash

cd $(dirname $0)
hdir="$PWD/"


# # #
# Update scripts
function getlatest() {
    echo "Getting latest version"
    git pull &>/dev/null
    bash ${hdir}tools/update_scripts.sh
}

if [[ $1 == "update" ]]; then
    getlatest
    exit 0
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


# # #
# Parse config
if [ -f ${hdir}config ]; then
    source ${hdir}config
else
    source ${hdir}tools/config_example
fi


# # #
# Start backups
for (( x=0; x < ${#b_dirs[@]}; x++ ))
do

    if [[ $1 == "now" ]]; then

        if [[ ! "${didbackup[@]}" =~ "${b_dirs[$x]}" ]]; then
            didbackup[$x]=${b_dirs[$x]}
            dobackup[0]=1
            dobackup[1]=1
            dobackup[2]=1
        else
            dobackup[0]=0
            dobackup[1]=0
            dobackup[2]=0
        fi


    else

        dobackup[0]=0
        dobackup[1]=0
        dobackup[2]=0

        # Possible things
        # 9h 
        # 15h
        # 9m 
        # 15m
        # 12:13
        # 22
        if [[ "${b_invs[$x]}" =~ ^[0-9][hH]$ ]]; then
            b_invs[x]="$(sed 's/[hH]//g' <<< ${b_invs[$x]})"
            b_hour=$(date +"%H")
            dobackup[2]=1
        elif [[ "${b_invs[$x]}" =~ ^[0-9][0-9][hH]$ ]]; then
            b_invs[x]=$(sed 's/[hH]//g' <<< ${b_invs[$x]})
            b_hour=$(date +"%H")
            dobackup[2]=1
        elif [[ "${b_invs[$x]}" =~ ^[0-9][0-9][mM]$ ]]; then
            b_invs[x]=$(sed 's/[mM]//g' <<< ${b_invs[$x]})
            b_hour=$(date +"%M")
            dobackup[2]=2
        elif [[ "${b_invs[$x]}" =~ ^[0-9][mM]$ ]]; then
            b_invs[x]="$(sed 's/[mM]//g' <<< ${b_invs[$x]})"
            b_hour=$(date +"%M")
            dobackup[2]=2
        elif [[ "${b_invs[$x]}" =~ ^[0-9][0-9]":"[0-9][0-9]$ ]]; then
            b_hour=$(date +"%H:%M")
        else
            echo "Unknown configuration: ${b_invs[$x]}"
            exit 1
        fi

        b_hour_cleaned=$( sed 's/^0//g'  <<< $b_hour)
        if [ ${dobackup[2]} -eq 1 ] && (( $b_hour_cleaned % ${b_invs[$x]} == 0 )); then
            if [[ $(date +"%M") == "00" ]]; then
                dobackup[0]=1
            fi
        elif [ ${dobackup[2]} -eq 2 ] && (( $b_hour_cleaned % ${b_invs[$x]} == 0 )); then
            dobackup[0]=1
        elif [[ "${b_invs[$x]}" =~ "$b_hour" ]]; then
            dobackup[0]=1
        else
            echo "Not valid ${b_invs[$x]} =~ $b_hour"
        fi

        # Possible things
        # Monday 
        # Monday,Tuesday
        # Mo
        # Mo,We,Fr
        # 22
        if [[ "${b_dats[$x]}" =~ ^[0-9][0-9]$ ]]; then
            b_hour=$(date +"%m")
        elif [[ "${b_dats[$x]}" =~ ^[0-9]$ ]]; then
            b_dats[x]="0${b_dats[$x]}"
            b_hour=$(date +"%m")
        elif [[ "${b_dats[$x]}" =~ ^[A-Z][a-z][a-z][a-z][a-z]* ]]; then
            b_hour=$(date +"%A")
        elif [[ "${b_dats[$x]}" =~ ^[A-Z][a-z][a-z]$ ]]; then
            b_hour=$(date +"%a")
        elif [[ "${b_dats[$x]}" =~ ^[A-Z][a-z][a-z]","* ]]; then
            b_hour=$(date +"%a")
        else
            echo "Unknown configuration: ${b_dats[$x]}"
            exit 1
        fi

        if [[ "${b_dats[$x]}" =~ "$b_hour" ]]; then
            dobackup[1]=1
        else
            echo "Not valid ${b_dats[$x]} =~ $b_hour"
        fi

    fi

    if [ ${dobackup[0]} -eq 1 ] && [ ${dobackup[1]} -eq 1 ]; then

        if [ -f ${hdir}${b_dirs[$x]}/backup_server.sh ]; then
    
            bash "${hdir}${b_dirs[$x]}/backup_server.sh" "--${b_type[$x]}" &
            echo "Backup for ${b_dirs[$x]} under way..."

        else
        
            echo "Backup directory doesn't exist"
            exit 1

        fi
    fi
done

exit 0
