#!/bin/bash

cd $(dirname $0)
hdir="$PWD/"
tdir="/tmp/SBE/$RANDOM/"
mkdir -p $tdir



if [ -f ${hdir}backup.xml ]; then


    b_dirs=($(grep -oP '(?<=<backupdirectory>).*?(?=</backupdirectory>)' ${hdir}backup.xml))
    b_invs=($(grep -oP '(?<=<intervall>).*?(?=</intervall>)' ${hdir}backup.xml))
    b_dats=($(grep -oP '(?<=<date>).*?(?=</date>)' ${hdir}backup.xml))
    b_type=($(grep -oP '(?<=<type>).*?(?=</type>)' ${hdir}backup.xml))

else
    cp ${hdir}tools/backup.xml-example ${hdir}backup.xml
    echo "Please configure your backup.xml file first"
fi


function getlatest() {
    echo "Getting latest version"
    git pull &>/dev/null
    bash ${hdir}tools/update_scripts.sh
}
getlatest

if [ -f ${hdir}config ]; then
    source ${hdir}config
else
    source ${hdir}tools/config_example
fi

echo "Backup"
for (( x=0; x < ${#b_dirs[@]}; x++ ))
do

    dobackup[0]=0
    dobackup[1]=0

    # Possible things
    # 9h 
    # 15h
    # 9m 
    # 15m
    # 12:13
    # 22
    if [[ "${b_invs[$x]}" =~ ^[0-9][hH]$ ]]; then
        b_invs[x]="0$(sed 's/[hH]//g' <<< ${b_invs[$x]})"
        b_hour=$(date +"%H")
    elif [[ "${b_invs[$x]}" =~ ^[0-9][0-9][hH]$ ]]; then
        b_invs[x]=$(sed 's/[hH]//g' <<< ${b_invs[$x]})
        b_hour=$(date +"%H")
    elif [[ "${b_invs[$x]}" =~ ^[0-9][0-9][mM]$ ]]; then
        b_invs[x]=$(sed 's/[mM]//g' <<< ${b_invs[$x]})
        b_hour=$(date +"%M")
    elif [[ "${b_invs[$x]}" =~ ^[0-9][mM]$ ]]; then
        b_invs[x]="0$(sed 's/[mM]//g' <<< ${b_invs[$x]})"
        b_hour=$(date +"%M")
    elif [[ "${b_invs[$x]}" =~ ^[0-9][0-9]":"[0-9][0-9]$ ]]; then
        b_hour=$(date +"%H:%M")
    else
        echo "Unknown configuration: ${b_invs[$x]}"
        exit 1
    fi

    if [[ "${b_invs[$x]}" =~ "$b_hour" ]]; then
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


    if [ ${dobackup[0]} -eq 1 ] && [ ${dobackup[1]} -eq 1 ]; then

        if [ -f ${hdir}${b_dirs[$x]}/backup_server.sh ]; then
    
            echo bash "${hdir}${b_dirs[$x]}/backup_server.sh" "--${b_type[$x]}" &
            echo "Backup for ${b_dirs[$x]} under way..."

        fi
    fi
done

rm -rf $tdir
exit 0
