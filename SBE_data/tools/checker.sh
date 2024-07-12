#!/bin/bash

# Runs through backup.xml - recognizes intervals and creates a file named .backup-operations
# This file contains each backup execution defined by intervals

# Declare directories
cd "$(dirname "$0")"
tools="$PWD/"
cd ..
hdir="$PWD/"
cd ..
mdir="$PWD/"

# Clean template files
: > "${hdir}.backups-executed-yesterday"
: > "${hdir}.backup-operations"

# Parse config
if [ -f "${mdir}.env" ]; then
    source "${mdir}.env"
else
    echo "You have to configure .env first. Copy from env.example to .env and configure it."
    exit 1
fi

# Check done file
if [ ! -f "${reports}SBE-done" ]; then
    echo "No backups done"
    echo -e "Subject: WARNING: Backup problem on $HOSTNAME\n\nThere's no SBE-done file" | /usr/sbin/sendmail "$mail"
    exit 2
fi

# Parse backup.xml
if [ -f "${hdir}backup.xml" ]; then
    b_dirs=($(grep -oP '(?<=<backupdirectory>).*?(?=</backupdirectory>)' "${hdir}backup.xml"))
    b_invs=($(grep -oP '(?<=<intervall>).*?(?=</intervall>)' "${hdir}backup.xml"))
    b_dats=($(grep -oP '(?<=<date>).*?(?=</date>)' "${hdir}backup.xml"))
    b_type=($(grep -oP '(?<=<type>).*?(?=</type>)' "${hdir}backup.xml"))
else
    cp "${hdir}tools/backup.xml-example" "${hdir}backup.xml"
    echo "Please configure your backup.xml file first"
    exit 1
fi

# Loop through intervals in backup.xml
for ((x=0; x < ${#b_dirs[@]}; x++)); do
    interval="${b_invs[$x]}"
    
    # Dismantle hours
    if [[ "$interval" =~ ^[0-9]{1,2}[hH]$ ]]; then
        hours=${interval%[hH]}
        minloop=$(( 24 / hours ))
        for ((hl=1; hl <= minloop; hl++)); do
            hour=$(( hl * hours ))
            printf "<server>\n  <backupdirectory>%s</backupdirectory>\n  <intervall>%02d:00</intervall>\n  <date>%s</date>\n  <type>%s</type>\n</server>\n" \
                "${b_dirs[$x]}" "$hour" "${b_dats[$x]}" "${b_type[$x]}" >> "${hdir}.backup-operations"
        done
    elif [[ "$interval" =~ ^[0-9]{1,2}[mM]$ ]]; then
        minutes=${interval%[mM]}
        minloop=$(( 60 / minutes ))
        for ((hours=0; hours < 24; hours++)); do
            for ((hl=1; hl <= minloop; hl++)); do
                minute=$(( hl * minutes ))
                printf "<server>\n  <backupdirectory>%s</backupdirectory>\n  <intervall>%02d:%02d</intervall>\n  <date>%s</date>\n  <type>%s</type>\n</server>\n" \
                    "${b_dirs[$x]}" "$hours" "$minute" "${b_dats[$x]}" "${b_type[$x]}" >> "${hdir}.backup-operations"
            done
        done
    else
        printf "<server>\n  <backupdirectory>%s</backupdirectory>\n  <intervall>%s</intervall>\n  <date>%s</date>\n  <type>%s</type>\n</server>\n" \
            "${b_dirs[$x]}" "$interval" "${b_dats[$x]}" "${b_type[$x]}" >> "${hdir}.backup-operations"
    fi
done

# Parse .backup-operations
readarray -t b_dirs < <(grep -oP '(?<=<backupdirectory>).*?(?=</backupdirectory>)' "${hdir}.backup-operations")
readarray -t b_invs < <(grep -oP '(?<=<intervall>).*?(?=</intervall>)' "${hdir}.backup-operations")
readarray -t b_dats < <(grep -oP '(?<=<date>).*?(?=</date>)' "${hdir}.backup-operations")
readarray -t b_type < <(grep -oP '(?<=<type>).*?(?=</type>)' "${hdir}.backup-operations")

echo -e "\nA total of ${#b_dirs[@]} backup operations are configured"

# Define period of backups to check
today=$(date +"%s")
yesterday=$(( today - 86400 ))
w_day=$(date --date="@$yesterday" +"%a")
w_day_num=$(date --date="@$yesterday" +"%-d")
w_year=$(date --date="@$yesterday" +"%Y")
w_month=$(date --date="@$yesterday" +"%b")

: > "${hdir}.backups-executed-yesterday"

# Write all executed lines from yesterday to .backups-executed-yesterday
awk -F";" '{print $3, $2}' "${reports}SBE-done" | grep "$w_month" | grep "$w_year" | grep "$w_day_num" | grep "$w_day" | \
while read -r logline; do
    awk -F" " '{print $1, $2, $3, $4, $7}' <<< "$logline" >> "${hdir}.backups-executed-yesterday"
done

if [ -f "${hdir}.backups-executed-yesterday" ]; then
    occurrence=$(wc -l < "${hdir}.backups-executed-yesterday")
    dc1=$(grep -o -i "$w_day" <<< "${b_dats[@]}" | wc -l)
    dc2=$(grep -o -i "$w_day_num" <<< "${b_dats[@]}" | wc -l)
    daycount=$(( dc1 + dc2 ))
    echo "$daycount of them are meant to be executed yesterday"
    echo "Count of executed backups is $occurrence"
    echo "This executions are as following:"
    servers=($(printf "%s\n" "${b_dirs[@]}" | sort -u))

    for server in "${servers[@]}"; do
        scount=$(grep -c "$server" "${hdir}.backups-executed-yesterday")
        echo "$server: $scount"
    done

    if [[ $daycount == $occurrence ]]; then
        echo -e "Subject: SUCCESS: Backup on $HOSTNAME\n\n($daycount) done" | /usr/sbin/sendmail "$mail"
    else
        echo -e "Subject: WARNING: Backup problem on $HOSTNAME\n\nThere should've been $daycount backup operations but $occurrence operations are recognized" | /usr/sbin/sendmail "$mail"
    fi
else
    echo -e "Subject: WARNING: Backup problem on $HOSTNAME\n\nThere are no backups inside done log from yesterday" | /usr/sbin/sendmail "$mail"
fi