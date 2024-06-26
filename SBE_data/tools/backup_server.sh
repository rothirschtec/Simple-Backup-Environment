#!/bin/bash

# Dependencies: sendmail, cryptsetup, ssh, rsync

# Set directories and variables
cd "$(dirname "$0")"
source ../tools/lib/* || exit 1

sdir="$PWD"
sname="${sdir##*/}"
sdir="$sdir/"

cd ..
rdir="$PWD/"
cd ..
mdir="$PWD/"

error=false

# Default variables
bdir="none"
bmount="none"
BDAYS=1
BWEEKS=1
BMONTHS=1
WHOLEFILE=0
mail=root
reports=/tmp/

# Load configuration files
if [ -f "${mdir}.env" ]; then
    source "${mdir}.env"
else
    echo "You have to configure .env first. Copy from env.example to .env and configure it."
    exit 1
fi

if [ -f "${sdir}server.config" ]; then
    source "${sdir}server.config"
else
    echo "No server.config found!!!"
    exit 6
fi

re='^[0-9]+$'
stmax=${MBAST//[^0-9]/}  # Ensure stmax is numeric
stmax=${stmax:-2}

mou="${sdir}${SHARE}"
mdir="${sdir}${SHARE}/"

CURRENT_DAY=$((10#$(date +%j)))
CURRENT_WEEK=$((10#$(date +%V)))
CURRENT_MONTH=$((10#$(date +%m)))
START_DATE=$(date)

case "$@" in
  *--weekly*) [[ $BWEEKS -eq 0 ]] && { echo "BWEEKS is set to 0 in server.config"; exit 6; }
              BID=$(( CURRENT_WEEK % BWEEKS ))
              PERIOD="weekly";;
  *--monthly*) [[ $BMONTHS -eq 0 ]] && { echo "BMONTHS is set to 0 in server.config"; exit 6; }
               BID=$(( CURRENT_MONTH % BMONTHS ))
               PERIOD="monthly";;
  *--latest*) PERIOD="latest";;
  *) [[ $BDAYS -eq 0 ]] && { echo "BDAYS is set to 0 in server.config"; exit 6; }
     BID=$(( CURRENT_DAY % BDAYS ))
     PERIOD="daily";;
esac

# FUNCTIONS

remote_server_up () {
    ssh ${USER}@${SERVER} -p $PORT "echo 2>&1" && return 0 || return 1
}

create_remote_unique_code_file () {
    local unique_code=$1
    ssh ${USER}@${SERVER} -p $PORT "echo '$unique_code' > ${SHARE}.sbe_code.txt"
}

fetch_remote_unique_code_file () {
    scp -P $PORT ${USER}@${SERVER}:${SHARE}.sbe_code.txt "${sdir}remote_backup_unique_code.txt"
}

compare_unique_code_files () {
    if ! cmp -s "${sdir}/master_backup_unique_code.txt" "${sdir}/remote_backup_unique_code.txt"; then
        echo "Unique codes match. Backup will proceed."
        return 0
    fi
    echo "Unique codes do not match. Is something corrupt?"
    exit 0
}

generate_unique_code () {
    openssl rand -hex 32 
}

update_unique_code_files () {
    local unique_code=$1
    echo "$unique_code" > "${sdir}master_backup_unique_code.txt"
    create_remote_unique_code_file "$unique_code"
}

create_backup_directory () {
  if [[ $PERIOD != "latest" ]]; then
    bdir="${bmount}${PERIOD}/${BID}_$(date +"%Y-%m-%d_%H%M%S")"
    mkdir -p "$bdir"
  else
    bdir="${bmount}${PERIOD}"
    mkdir -p "$bdir"
  fi
}

rsync_backup () {
    rsync_opts=("--whole-file -e" "ssh -p ${PORT}" "${roption[@]}" "${USER}@${SERVER}:${SHARE}" "$bdir")
    [[ $WHOLEFILE -ne 1 ]] && unset rsync_opts[0]
    rsync "${rsync_opts[@]}"
}

notify_success () {
    echo -e "Subject: Backup Success with $sname on $HOSTNAME\n\n $(<${sdir}bac.log)" | $sendmail $mail
}

notify_failure () {
    echo -e "Subject: Backup Error with $sname on $HOSTNAME\n\n $(<${sdir}err.log)" | $sendmail $mail
}

# MAIN

if [[ "$@" =~ "--set-code" ]]; then

    unique_code=$(generate_unique_code)
    update_unique_code_files "$unique_code" || exit 1
    echo "Unique code files created and updated successfully."
    exit 0

elif [[ "$@" =~ "--sshCopy" ]]; then
    ssh-copy-id -i ~/.ssh/id_rsa.pub -p "$PORT" "$USER@$SERVER"

elif [ "$BACKUP" -eq 1 ]; then
    rm -f "${sdir}err.log" "${sdir}bac.log"
    
    (
        echo "Starting Backup: $(date +"%y-%m-%d %H:%M")"
        
        remote_server_up || { echo "Server is down"; exit 1; }

        fetch_remote_unique_code_file || { echo "Failed to fetch remote unique code file"; exit 1; }

        compare_unique_code_files
        
        create_backup_directory || { echo "Failed to create backup directory"; exit 1; }
        
        rsync_backup || { echo "Failed to perform rsync backup"; exit 1; }
        
        echo "Successful backup: $(date +"%y-%m-%d %H:%M")"
    ) >> "${sdir}bac.log" 2> "${sdir}err.log"

    if [ -s "${sdir}err.log" ]; then
        notify_failure
        exit 1
    else
        notify_success
        exit 0
    fi
fi

exit 0