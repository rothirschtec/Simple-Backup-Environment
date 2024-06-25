#!/bin/bash

cd "$(dirname "$0")" || exit
hdir="$PWD/"
cd .. || exit
mdir="$PWD/"

logs=$([[ "$@" =~ "--logs" ]] && echo 1 || echo 0)

# Update scripts
getlatest() {
    echo "Getting latest version"
    git pull &>/dev/null
    bash "${hdir}tools/update_scripts.sh"
}

[[ $1 == "update" ]] && { getlatest; exit 0; }

while :; do
    # Parse config
    if [ -f "${mdir}.env" ]; then
        source "${mdir}.env"
    else
        echo "You have to configure .env first. Copy from env.example to .env and configure it."
        exit 1
    fi

    # Parse backup.xml
    if [ -f "${hdir}backup.xml" ]; then
        xmllint --noout --schema "${hdir}tools/backup.xsd" "${hdir}backup.xml" || exit 2
        echo "XML valid"

        b_dirs=($(grep -oP '(?<=<backupdirectory>).*?(?=</backupdirectory>)' "${hdir}backup.xml"))
        b_invs=($(grep -oP '(?<=<intervall>).*?(?=</intervall>)' "${hdir}backup.xml"))
        b_dats=($(grep -oP '(?<=<date>).*?(?=</date>)' "${hdir}backup.xml"))
        b_type=($(grep -oP '(?<=<type>).*?(?=</type>)' "${hdir}backup.xml"))
    else
        message="backup.xml does not exist"
        echo "$message"
        echo -e "Subject: $message\n\nNew message from SBE\nDir: $hdir\nb_invs: ${b_invs[*]}" | $sendmail $mail
        cp "${hdir}tools/backup.xml-example" "${hdir}backup.xml"
        echo "Please configure your backup.xml file first"
    fi

    # Start backups
    for ((x = 0; x < ${#b_dirs[@]}; x++)); do
        dobackup=(0 0 0)

        if [[ $1 == "now" ]]; then
            dobackup=(1 1 1)
        else
            case "${b_invs[$x]}" in
                *[hH]) 
                    b_invs[x]="${b_invs[$x]%[hH]}"
                    b_date=$(date +"%H")
                    dobackup[2]=1
                    ;;
                *[mM])
                    b_invs[x]="${b_invs[$x]%[mM]}"
                    b_date=$(date +"%M")
                    dobackup[2]=2
                    ;;
                [0-9][0-9]:[0-9][0-9])
                    b_date=$(date +"%H:%M")
                    dobackup[2]=3
                    ;;
                *)
                    echo "Unknown configuration: ${b_invs[$x]}"
                    exit 1
                    ;;
            esac

            b_date_cleaned="${b_date/#0/}"

            if [ ${dobackup[2]} -eq 1 ] && ((b_date_cleaned % ${b_invs[$x]} == 0)) && [[ $(date +"%M") == "00" ]]; then
                dobackup[0]=1
            elif [ ${dobackup[2]} -eq 2 ] && ((b_date_cleaned % ${b_invs[$x]} == 0)); then
                dobackup[0]=1
            elif [[ "${b_invs[$x]}" == "$b_date" ]]; then
                dobackup[0]=1
            else
                [ $logs -eq 1 ] && echo "Not valid ${b_invs[$x]} =~ $b_date"
            fi

            case "${b_dats[$x]}" in
                [0-9][0-9]) b_dat=$(date +"%m") ;;
                [0-9]) 
                    b_dats[x]="0${b_dats[$x]}"
                    b_dat=$(date +"%m")
                    ;;
                [A-Za-z]*)
                    b_dat=$(date +"%A")
                    ;;
                [A-Za-z][a-z][a-z])
                    b_dat=$(date +"%a")
                    ;;
                *)
                    echo "Unknown configuration: ${b_dats[$x]}"
                    exit 1
                    ;;
            esac

            if [[ "${b_dats[$x]}" == *"$b_dat"* ]]; then
                dobackup[1]=1
            else
                [ $logs -eq 1 ] && echo "Not valid ${b_dats[$x]} =~ $b_dat"
            fi
        fi

        if [ ${dobackup[0]} -eq 1 ] && [ ${dobackup[1]} -eq 1 ]; then
            if [ -f "${hdir}${b_dirs[$x]}/backup_server.sh" ]; then
                echo "Backup ${b_dirs[$x]}"
                bash "${hdir}${b_dirs[$x]}/backup_server.sh" "--${b_type[$x]}" &
                message="Backup for ${b_dirs[$x]} under way..."
            else
                message="Backup directory (${b_dirs[$x]}) doesn't exist"
                echo "$message"
                echo -e "Subject: $message\n\nNew message from SBE" | $sendmail $mail
            fi
        fi
    done

    currentTime=$(date +"%H%M")
    if [ "$currentTime" -eq "1800" ]; then
        bash "${hdir}tools/checker.sh"
    fi

    sleep 60
done

exit 0

