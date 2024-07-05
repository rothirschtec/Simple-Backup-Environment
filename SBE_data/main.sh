#!/bin/bash

cd "$(dirname "$0")" || exit
hdir="$PWD/"
cd .. || exit
mdir="$PWD/"
overwriteRun=0

logs=$([[ "$@" =~ "--logs" ]] && echo 1 || echo 0)

# Wait until the start of the next minute
printf "Waiting for the start of the next minute...\n"
while [ "$(date +%S)" -ne "00" ]; do
    sleep 1
done

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

    if [ $overwriteRun -eq 0 ]; then
        echo "" > ${reports}SBE-queue-run
        overwriteRun=1
    fi

    # Parse backup.xml
    if [ -f "${hdir}backup.xml" ]; then
        xmllint --noout --schema "${hdir}tools/backup.xsd" "${hdir}backup.xml"
        if [ $? -ne 0 ]; then 
            echo "Invalid XML format"
            exit 2
        fi
        echo "XML valid"

        backup_xml="${hdir}backup.xml"
        b_dirs=()
        while IFS= read -r line; do
            b_dirs+=("$line")
        done < <(grep -oP '(?<=<backupdirectory>).*?(?=</backupdirectory>)' "$backup_xml")

        b_invs=()
        while IFS= read -r line; do
            b_invs+=("$line")
        done < <(grep -oP '(?<=<intervall>).*?(?=</intervall>)' "$backup_xml")

        b_dats=()
        while IFS= read -r line; do
            b_dats+=("$line")
        done < <(grep -oP '(?<=<date>).*?(?=</date>)' "$backup_xml")

        b_type=()
        while IFS= read -r line; do
            b_type+=("$line")
        done < <(grep -oP '(?<=<type>).*?(?=</type>)' "$backup_xml")
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
        
        # Debug information
        echo "Checking backup for: ${b_dirs[$x]}"
        echo "Intervall: ${b_invs[$x]}"
        echo "Date: ${b_dats[$x]}"

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

            # Enhanced date matching logic
            case "${b_dats[$x]}" in
                [0-9]|[0-2][0-9]|3[0-1])  # Numeric day, e.g., "20"
                    b_dat=$(date +"%d") 
                    if ((10#$b_dat == 10#${b_dats[$x]})); then dobackup[1]=1; fi
                    ;;
                [A-Za-z][a-z][a-z]|[A-Z][a-z]*)  # Day name, e.g., "Mon" or "Monday"
                    b_day_short=$(date +"%a")
                    b_day_full=$(date +"%A")
                    if [[ ",${b_dats[$x]}," == *",$b_day_short,"* ]] || [[ ",${b_dats[$x]}," == *",$b_day_full,"* ]]; then dobackup[1]=1; fi
                    ;;
                *)
                    echo "Unknown configuration: ${b_dats[$x]}"
                    exit 1
                    ;;
            esac

            if [ ${dobackup[1]} -ne 1 ]; then
                [ $logs -eq 1 ] && echo "Not valid ${b_dats[$x]} =~ $b_dat/$b_day_short/$b_day_full"
            fi

        fi

        if [ ${dobackup[0]} -eq 1 ] && [ ${dobackup[1]} -eq 1 ]; then
            echo "Conditions met for backup: ${b_dirs[$x]}"
            if [ -f "${hdir}${b_dirs[$x]}/backup_server.sh" ]; then
                echo "Backup ${b_dirs[$x]} started"
                bash "${hdir}${b_dirs[$x]}/backup_server.sh" "--${b_type[$x]}" &
                message="Backup for ${b_dirs[$x]} under way..."
            else
                message="Backup directory (${b_dirs[$x]}) doesn't exist"
                echo "$message"
                echo -e "Subject: $message\n\nNew message from SBE" | $sendmail $mail
            fi
        else
            echo "Conditions not met for backup: ${b_dirs[$x]}"
        fi
    done

    currentTime=$(date +"%H%M")
    if [ "$currentTime" -eq "1800" ]; then
        bash "${hdir}tools/checker.sh"
    fi

    sleep 60
done

exit 0