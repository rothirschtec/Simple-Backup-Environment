#!/bin/bash
#
# You can copy your ssh key to the remote server if you want
# backup_server.sh --sshCopy
# Dependencies:
# - sendmail
# - cryptsetup

# Set variables

# Directories
cd $(dirname $0)
source ../tools/lib/*
sdir="$PWD"
sname=${sdir##*/}
sdir="${sdir}/"

cd ..
rdir="$PWD/"
cd ../
mdir="$PWD/"

error=false

# Backup Directory
bdir="none"
# Backup mounted loop device
bdisk="none"
# loop device mount location
bmount="none"

# Dates and types
BDAYS=1
BWEEKS=1
BMONTHS=1

# Rsync WHOLEFILE option. If not in server.config set to 0
WHOLEFILE=0


# Load configuration files

# Default configuration can be changed in config file
mail=root
reports=/tmp/

if [ -f ${mdir}.env ]; then
    source ${mdir}.env
else
    echo "You have to configure .env first. Copy from env.example to .env and configure it."
    exit 1
fi
if [ -f ${sdir}server.config ]; then
    source ${sdir}server.config
else
    echo "No server.config found!!!"
    exit 6
fi

re='^[0-9]+$'
if [[ $MBAST =~ $re ]]; then
	stmax=$MBAST
else
	stmax=2
fi

# Define shares
mou="${sdir}${SHARE}"
mdir="${sdir}${SHARE}/"
# Remove old logs
rm -f ${sdir}err.log
rm -f ${sdir}bac.log

CURRENT_DAY=$((10#$(date +%j)))
CURRENT_WEEK=$((10#$(date +%V)))
CURRENT_MONTH=$((10#$(date +%m)))
START_DATE=$(date)

if [[ $@ =~ "--weekly" ]]; then
  [[ $BWEEKS -eq 0 ]] && echo "BWEEKS is set to 0 in server.config" && exit 6
  BID=$(( CURRENT_WEEK % BWEEKS ))
  PERIOD="weekly"
elif [[ $@ =~ "--monthly" ]]; then
  [[ $BMONTHS -eq 0 ]] && echo "BMONTHS is set to 0 in server.config" && exit 6
  BID=$(( CURRENT_MONTH % BMONTHS ))
  PERIOD="monthly"
elif [[ $@ =~ "--latest" ]]; then
  PERIOD="latest"
else
  [[ $BDAYS -eq 0 ]] && echo "BDAYS is set to 0 in server.config" && exit 6
  BID=$(( CURRENT_DAY % BDAYS ))
  PERIOD="daily"
fi


# FUNCTIONS

# Check if remote server is availabe for backup operations
remote_server_up () {
	ssh ${USER}@$SERVER -p $PORT "echo 2>&1" && return 0 || return 1
}

find_duplicates () {
  local n=0
  if [ -d ${bmount}${PERIOD} ]; then
    while read -r -d ''; do
      ((n++))
    done < <(find ${bmount}${PERIOD}/ -maxdepth 1 -name $"${BID}_*" -print0)
  fi
  echo $n

}

# Create backup directory
create_backup_directory () {

  if [[ $PERIOD != "latest" ]]; then

    bdir="${bmount}${PERIOD}/${BID}_$(date +"%Y-%m-%d_%H%M%S")"

    n=$(find_duplicates)

    if [ $n -eq 1 ]; then
      olddir=$(echo ${bmount}${PERIOD}/${BID}_*)
      mv $olddir $bdir
    elif [ $n -eq 0 ]; then
      mkdir -p ${bdir}
    fi

    n=$(find_duplicates)

    if [ $n -gt 1 ]; then
      echo "There are multiple backups with same BID (Backup ID). Related name $sname"
      echo -e "Subject: There are multiple backups with same BID (Backup ID). Related name $sname on $HOSTNAME\n\n" | $sendmail $mail
      exit 4
    fi

  else

    bdir="${bmount}${PERIOD}"
    mkdir -p ${bdir}

  fi

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

# Notify admin user
notify () {

  [[ "$@" =~ "--log" ]] || echo -e "Subject: Backup Success with $sname on $HOSTNAME\n\n $(cat ${sdir}bac.log)" | $sendmail $mail

  if [ $(cat ${sdir}err.log | wc -w | awk '{ print $1 }') -gt 0 ]; then
    echo "Script stopped: $(date +"%y-%m-%d %H:%M")" >> ${sdir}err.log
    echo -e "Subject: Backup Error with $sname on $HOSTNAME\n\n $(cat ${sdir}err.log)" | $sendmail $mail
    exit 1
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

# Backup to a network share
share_backup () {
  sudo mount.cifs //${SERVER}/${SHARE} -o username=${USER},password=''${PASS}'' ${sdir}mnt/
  if sudo mount | grep ${sdir}mnt; then
      rsync "${roption[@]}" ${sdir}mnt/ ${bdir}
      sleep 5
      if ! sudo umount ${sdir}mnt/; then
        >&2 echo "Problem with unmounting filesystem"
      else
        echo "Successfully umounted device"
      fi
  fi
}

# MAIN

if [[ $@ =~ "--sshCopy" ]]; then

  [[ "$@" =~ "--log" ]] && echo "Copy ssh public key"

  ssh-copy-id -i ~/.ssh/id_rsa.pub -p $PORT $USER@$SERVER

elif [ $BACKUP -eq 1 ]; then

  [[ "$@" =~ "--log" ]] && echo "Backup process started"

  avoid_duplicates_in_queue || exit 2 && [[ "$@" =~ "--log" ]] && echo "Backup added to queue"

  manage_queue && [[ "$@" =~ "--log" ]] && echo "Managed queue"

  # Backup process
  (

    echo "Starting Backup: $(date +"%y-%m-%d %H:%M")"
    echo "Backup Directory: $bdir"
    echo ""

    write_to_queue && [[ "$@" =~ "--log" ]] && echo "Added backup to queue"

    remote_server_up || exit 1 && [[ "$@" =~ "--log" ]] && echo "Server is up"

    mount_backup_directory || exit 4 && [[ "$@" =~ "--log" ]] && echo "Backup directory mounted"

    create_backup_directory || exit 5 && [[ "$@" =~ "--log" ]] && echo "Backup directory created"

    tc=0
    [[ "$@" =~ "--log" ]] && echo "Starting backup type: $TYPE"
    [[ $TYPE == "rsync" ]] && rsync_backup; tc=1
    [[ $TYPE == "share" ]] && share_backup; tc=1
    [ $tc -eq 1 ] || exit 3

    umount_backup_directory && [[ "$@" =~ "--log" ]] && echo "Backup directory unmounted"

    echo "Successfull backup: $(date +"%y-%m-%d %H:%M")"
    sed -i "/^$cID;.*$/d" ${reports}SBE-queue-run

    echo "$cID; ${START_DATE}; ${sname}; ${PERIOD}; $(date);" >> ${reports}SBE-done

  ) >> ${sdir}bac.log | tee ${rdir}all.log 2> ${sdir}err.log | tee ${rdir}all.log


  [[ "$@" =~ "--log" ]] && echo "Backup done"

  notify; [[ "$@" =~ "--log" ]] && echo "Notify"

fi

exit 0
