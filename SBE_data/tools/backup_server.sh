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
    if cmp -s "${sdir}/master_backup_unique_code.txt" "${sdir}/remote_backup_unique_code.txt"; then
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

# backup via rsync
rsync_backup () {

  # The --whole-file parameter deters the remote server to dismember files for network traffic
  # Maybe this prevents the heavy loads on the server side
  if [[ $WHOLEFILE -eq 1 ]]; then
    rsync --whole-file -e "ssh -p ${PORT}" "${roption[@]}" ${USER}@${SERVER}:${SHARE} ${bdir}
  else
    rsync -e "ssh -p ${PORT}" "${roption[@]}" ${USER}@${SERVER}:${SHARE} ${bdir}
  fi

  # If additional rsync commands exist
  if declare -p rsyncadd >/dev/null 2>&1; then
    rsyncsize=${#rsyncadd[@]}
    for radd in "${rsyncadd[@]}"
    do
      eval ${radd}
    done
    return 0
  fi

}

notify_success () {
    echo -e "Subject: Backup Success with $sname on $HOSTNAME\n\n $(<${sdir}bac.log)" | $sendmail $mail
}

notify_failure () {
    echo -e "Subject: Backup Error with $sname on $HOSTNAME\n\n $(<${sdir}err.log)" | $sendmail $mail
}

# Check if there already exists a backup process for the given server and PERIOD
avoid_duplicates_in_queue () {

  # Create directory if it does not exist
  [ -d $reports ] || mkdir -p $reports


  # Check if the PID used in queue file is active (Delete old entries)
  for fqueue in ${reports}SBE-queue ${reports}SBE-queue-run
  do
    if [ -f ${fqueue} ]; then
      while read rline
      do
        runq=$(awk -F";" '{print $1}' <<< $rline)
        if [ ! -e /proc/${runq} -a /proc/${runq}/exe ]; then
          sed -i "/^$runq;.*$/d" ${fqueue}
        fi
      done < ${fqueue}
      sed -i '/^$/d' ${fqueue}
    else
      touch ${fqueue}
    fi
  done

  # Check queue
  if cat ${reports}SBE-queue | grep ${sname} | grep ${PERIOD} &> /dev/null; then

    return 1

  else

    # Add the remote server to the queue if the PID does not exist
    if [ ! -f ${reports}SBE-queue ]; then
      echo "$$; ${START_DATE}; ${sname}; ${PERIOD};" >> ${reports}SBE-queue
    else
      if ! cat ${reports}SBE-queue | grep $$ &> /dev/null; then
        echo "$$; ${START_DATE}; ${sname}; ${PERIOD};" >> ${reports}SBE-queue
      fi
    fi

    return 0

  fi


}


manage_queue () {

  # Manage queue - To avoid heavy loads
    st=$(($stmax+1))
    sti=1

  while [ "$st" -ge "$stmax" ]
    do

    # Check if SBE-queue-run exists. If not, backup should start immediately
    if [ -f ${reports}SBE-queue-run ]; then

      #  Delete empty lines in queue files
      sed -i '/^$/d' ${reports}SBE-queue-run

      # Pick next in queue
      queue=$(sed -n ${sti}p ${reports}SBE-queue);

      # Check if there's already a backup process for the remote server in queue-run. If so, use next entry in queue
      if ! cat ${reports}SBE-queue-run | grep ${sname} &> /dev/null; then

        # End loop if queue pid exists and queue run count is less then stmax
        if [[ $queue =~ "$$;" ]]; then
          st=$(cat ${reports}SBE-queue-run | wc -l)
        fi

        # Wait for 2 seconds if
        if [ $st -ge $stmax ]; then
          sleep 2
        fi

        sti=1

      else

        # Increment queue id
        if [ $(cat ${reports}SBE-queue | wc -l) -gt 1 ]; then
          (( sti++ ))
        fi

      fi

    else
          st=$(($stmax-1))
    fi

    done

}


write_to_queue () {

  cID=$$
  echo "$cID; ${START_DATE}; ${sname};" >> ${reports}SBE-queue-run
  sed -i "/^$cID;.*$/d" ${reports}SBE-queue

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

    avoid_duplicates_in_queue || exit 2 && [[ "$@" =~ "--log" ]] && echo "Backup added to queue"

    manage_queue && [[ "$@" =~ "--log" ]] && echo "Managed queue"


    (
        echo "Starting Backup: $(date +"%y-%m-%d %H:%M")"

        write_to_queue && [[ "$@" =~ "--log" ]] && echo "Added backup to queue"
        
        remote_server_up || { echo "Server is down"; exit 1; }

        fetch_remote_unique_code_file || { echo "Failed to fetch remote unique code file"; exit 1; }

        compare_unique_code_files

        mount_backup_directory || exit 4 && [[ "$@" =~ "--log" ]] && echo "Backup directory mounted"
        
        create_backup_directory || { echo "Failed to create backup directory"; exit 1; }
        
        rsync_backup || { echo "Failed to perform rsync backup"; exit 1; }
       
        umount_backup_directory && [[ "$@" =~ "--log" ]] && echo "Backup directory unmounted" 

        echo "Successful backup: $(date +"%y-%m-%d %H:%M")"

        sed -i "/^$cID;.*$/d" ${reports}SBE-queue-run

    ) >> ${sdir}bac.log | tee ${rdir}all.log 2> ${sdir}err.log | tee ${rdir}all.log

    if [ -s "${sdir}err.log" ]; then
        notify_failure
        exit 1
    else
        notify_success
        exit 0
    fi
fi

exit 0
