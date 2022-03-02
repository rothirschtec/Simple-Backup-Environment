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

if [ -f ${rdir}config ]; then
    source ${rdir}config
else
    source ${rdir}tools/config_example
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
elif [[ $@ =~ "--archive" ]]; then
  BID=$(( CURRENT_WEEK % BWEEKS ))
  PERIOD="archive"
  TYPE="tar"
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

# Create backup directory
create_backup_directory () {

  bdir="${bmount}${PERIOD}/${BID}_$(date +"%Y-%m-%d_%H%M%S")"

  n=0
  if [ -d ${bmount}${PERIOD} ]; then
    while read -r -d ''; do
      ((n++))
    done < <(find ${bmount}${PERIOD}/ -maxdepth 1 -name $"${BID}_*" -print0)
  fi


  if [ $n -gt 1 ]; then
    echo "There are multiple backups with same BID (Backup ID). Related name $sname"
    echo -e "Subject: There are multiple backups with same BID (Backup ID). Related name $sname on $HOSTNAME\n\n" | $sendmail $mail
    exit 4
  elif [ $n -eq 1 ]; then
    olddir=$(echo ${bmount}${PERIOD}/${BID}_*)
    mv $olddir $bdir
  else
    mkdir -p ${bdir}
  fi

}

# Check if there already exists a backup process for the given server and PERIOD
process_in_queue () {

  # Create directory if it does not exist
  [ -d $reports ] || mkdir -p $reports

	if [ -f ${reports}SBE-queue ]; then

    # @4.1 - Clean queue
    while read rline
    do
      runq=$(awk -F";" '{print $1}' <<< $rline)
      if [ ! -e /proc/${runq} -a /proc/${runq}/exe ]; then
        if [ -f ${reports}SBE-queue-run ]; then
          sed -i "/^$runq;.*$/d" ${reports}SBE-queue-run
          sed -i '/^$/d' ${reports}SBE-queue-run
        else
          touch ${reports}SBE-queue-run
        fi
      fi
    done < ${reports}SBE-queue

    # @4.2 - Check queue
    if cat ${reports}SBE-queue | grep ${sname} | grep ${PERIOD} &> /dev/null; then
      return 1
    fi

  else
    # Create file if it does not exist
    touch ${reports}SBE-queue
  fi

  if [ ! -f ${reports}SBE-queue-run ]; then
    # Create file if it does not exist
    touch ${reports}SBE-queue-run
  fi

  return 0

}


manage_queue () {

	# @5 --------------------------
  # Manage queue - To avoid heavy loads
	st=$(($stmax+1))
	sti=1
	rm -f ${sdir}run
  while [ "$st" -ge "$stmax" ]
	do

    # @5.1 - Delete empty lines in queue files
    sed -i '/^$/d' ${reports}SBE-queue
    sed -i '/^$/d' ${reports}SBE-queue-run

    # @5.2 - Add the remote server to the queue if the PID does not exist
    if [ ! -f ${reports}SBE-queue ]; then
      echo "$$; ${START_DATE}; ${sname}; ${PERIOD};" >> ${reports}SBE-queue
    else
      if ! cat ${reports}SBE-queue | grep $$ &> /dev/null; then
        echo "$$; ${START_DATE}; ${sname}; ${PERIOD};" >> ${reports}SBE-queue
      fi
    fi

    # @5.3 -  Check if SBE-queue-run exists. If not, backup should start immediately
    if [ -f ${reports}SBE-queue-run ]; then

      # @5.3.1 - Pick next in queue
      queue=$(sed -n ${sti}p ${reports}SBE-queue);

      # @5.3.2 - Check if the PID used in SBE-queue is really used at the moment (Delete old entries)
      while read rline
      do
        runq=$(awk -F";" '{print $1}' <<< $rline)
        if [ ! -e /proc/${runq} -a /proc/${runq}/exe ]; then
          sed -i "/^$runq;.*$/d" ${reports}SBE-queue
          sed -i '/^$/d' ${reports}SBE-queue
        fi
      done < ${reports}SBE-queue

      # @5.3.3 - Check if the PID used in SBE-queue-run is really used at the moment (Delete old entries)
      while read rline
      do
        runq=$(awk -F";" '{print $1}' <<< $rline)
        if [ ! -e /proc/${runq} -a /proc/${runq}/exe ]; then
          sed -i "/^$runq;.*$/d" ${reports}SBE-queue-run
          sed -i '/^$/d' ${reports}SBE-queue-run
        fi
      done < ${reports}SBE-queue-run

      # @5.3.4 - Check if there's already a backup process for the remote server in queue-run. If so, use next entry in queue
      if ! cat ${reports}SBE-queue-run | grep ${sname} &> /dev/null; then

        # @5.3.5 - End loop if queue exists and queue run count is less then stmax
        if [[ $queue =~ "$$;" ]]; then
          st=$(cat ${reports}SBE-queue-run | wc -l)
        fi

        # @5.3.6 - Wait for 2 seconds if
        if [ $st -ge $stmax ]; then
          sleep 2
        fi

        sti=1

      else

        if [ $(cat ${reports}SBE-queue | wc -l) -gt 1 ]; then
          sti=2
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

# Create
tar_backup () {
   echo "Tar Archive Backup"
   mkdir -p ${sdir}.mounted/archives/
   ssh -p ${PORT} ${USER}@${SERVER} tar czf - ${SHARE} > ${sdir}.mounted/archives/$(date +"%y-%m-%d_%H:%M").tar.gz
}

# MAIN

if [[ $@ =~ "--sshCopy" ]]; then

  [[ "$@" =~ "--log" ]] && echo "Copy ssh public key"

  ssh-copy-id -i ~/.ssh/id_rsa.pub -p $PORT $USER@$SERVER

elif [ $BACKUP -eq 1 ]; then

  [[ "$@" =~ "--log" ]] && echo "Backup process started"

  remote_server_up || exit 1 && [[ "$@" =~ "--log" ]] && echo "Server is up"

  mount_backup_directory || exit 4 && [[ "$@" =~ "--log" ]] && echo "Backup directory mounted"

  create_backup_directory || exit 5 && [[ "$@" =~ "--log" ]] && echo "Backup directory created"

  process_in_queue || exit 2 && [[ "$@" =~ "--log" ]] && echo "Backup was not already in queue"

  manage_queue && [[ "$@" =~ "--log" ]] && echo "Managed queue"

  write_to_queue && [[ "$@" =~ "--log" ]] && echo "Added backup to queue"


  # Backup process
  (
    echo "Starting Backup: $(date +"%y-%m-%d %H:%M")"
    echo "Backup Directory: $bdir"
    echo ""

    tc=0
    [[ "$@" =~ "--log" ]] && echo "Starting backup type: $TYPE"
    [[ $TYPE == "rsync" ]] && rsync_backup; tc=1
    [[ $TYPE == "share" ]] && share_backup; tc=1
    [[ $TYPE == "tar" ]] && tar_backup; tc=1
    [ $tc -eq 1 ] || exit 3

    echo "Successfull backup: $(date +"%y-%m-%d %H:%M")"
    rm -f ${sdir}run
    sed -i "/^$cID;.*$/d" ${reports}SBE-queue-run

    echo "$cID; ${START_DATE}; ${sname}; ${PERIOD}; $(date);" >> ${reports}SBE-done

  ) >> ${sdir}bac.log | tee ${rdir}all.log 2> ${sdir}err.log | tee ${rdir}all.log

  [[ "$@" =~ "--log" ]] && echo "Backup done"

  umount_backup_directory

  notify; [[ "$@" =~ "--log" ]] && echo "Notify"

fi

exit 0
