#!/bin/bash
#
# You can copy your ssh key to the remote server if you want
# backup_server.sh --sshCopy


# Set variables

# Directories
cd $(dirname $0)
sdir="$PWD"
name=${sdir##*/}
sdir="${sdir}/"
cd ..
rdir="$PWD/"
error=false

# Dates and types
BDAYS=1
BWEEKS=1
BMONTHS=1


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
    mysqlIF="false"
    source ${sdir}server.config
else
    >&2 echo "No server.config found!!!"
    error=true
    # exit only this subshell
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
     BID=$(( CURRENT_WEEK % BWEEKS ))
     PERIOD="weekly"
elif [[ $@ =~ "--monthly" ]]; then
     BID=$(( CURRENT_MONTH % BMONTHS ))
     PERIOD="monthly"
elif [[ $@ =~ "--archive" ]]; then
     BID=$(( CURRENT_WEEK % BWEEKS ))
     PERIOD="archive"
     TYPE="tar"
else
     BID=$(( CURRENT_DAY % BDAYS ))
     PERIOD="daily"
fi

# Create backup directory
bdir="${sdir}rotate_bak/${PERIOD}/${BID}_$(date +"%Y-%m-%d_%H%M%S")"

n=0
while read -r -d ''; do
  ((n++))
done < <(find ${sdir}rotate_bak/${PERIOD}/ -maxdepth 1 -name "${BID}_*" -print0)

if [ $n -gt 1 ]; then
  echo -e "Subject: There are multiple backups with same BID. Related name $name on $HOSTNAME\n\n" | $sendmail $mail
  exit 0
elif [ $n -eq 1 ]; then
  echo "exists"
  olddir=$(echo ${sdir}rotate_bak/${PERIOD}/${BID}_*)
  mv $olddir $bdir
else
  echo "does not exist"
  mkdir -p ${bdir}
fi

# FUNCTIONS

remote_server_up () {

  # Check if remote server is availabe for backup operations
	ssh ${USER}@$SERVER -p $PORT "echo 2>&1" && return 0 || return 1

}

process_in_queue () {
# Check if there already exists a backup process for the given server and PERIOD

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
    if cat ${reports}SBE-queue | grep ${name} | grep ${PERIOD} &> /dev/null; then
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
      echo "$$; ${START_DATE}; ${name}; ${PERIOD};" >> ${reports}SBE-queue
    else
      if ! cat ${reports}SBE-queue | grep $$ &> /dev/null; then
        echo "$$; ${START_DATE}; ${name}; ${PERIOD};" >> ${reports}SBE-queue
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
      if ! cat ${reports}SBE-queue-run | grep ${name} &> /dev/null; then

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
  echo "$cID; ${START_DATE}; ${name};" >> ${reports}SBE-queue-run
  sed -i "/^$cID;.*$/d" ${reports}SBE-queue

}

# Notify admin user
notify () {

  [[ "$@" =~ "--log" ]] || echo -e "Subject: Backup Success with $name on $HOSTNAME\n\n $(cat ${sdir}bac.log)" | $sendmail $mail

  if [ $(cat ${sdir}err.log | wc -w | awk '{ print $1 }') -gt 0 ]; then
    echo "Script stopped: $(date +"%y-%m-%d %H:%M")" >> ${sdir}err.log
    echo -e "Subject: Backup Error with $name on $HOSTNAME\n\n $(cat ${sdir}err.log)" | $sendmail $mail
    exit 1
  fi

}

manage_logs () {
  if [ -f ${sdir}mysql/mysql_err.log ]; then
      echo ${sdir}mysql/mysql_err.log >> ${sdir}err.log
  fi
}

# mysql Backup
mysql_backup () {

  bmdi="${sdir}mysql/${PERIOD}/${BID}/"
  mkdir -p ${bmdi}

  # Get mySqlPort
  myPort=$(myPort=$(cat ${sdir}mysql.cnf |grep 'remoteport='); echo $myPort |grep -oP "(?<=').*?(?=')";)
  mylocp=$(sed "s/'//g" <<<$(sed 's/port=//g' <<<$(cat ${sdir}mysql.cnf |grep '^port=')))

  ssh -p ${PORT} -o ServerAliveInterval=10 -M -T -M -N -L $mylocp:127.0.0.1:${myPort} ${USER}@${SERVER} 2>  ${sdir}err.log &
  pid=$!
  echo "Got pid $pid ..."
  if [ $(wc -c ${sdir}err.log | awk '{print $1}') -eq 0 ]; then
    sleep 2
    # $1:mysql config file, $2:backupdir, $3:sendmail(1/0), $4:mail mail, $5:delete backups after
    if [[ "$PERIOD" == "weekly" ]]; then
      /bin/bash ${rdir}tools/mysql-backup.sh "${sdir}mysql.cnf" "${bmdi}" "$sdir" "$MBWEEKS"
    else
      /bin/bash ${rdir}tools/mysql-backup.sh "${sdir}mysql.cnf" "${bmdi}" "$sdir" "$MBDAYS"
    fi
  fi
  echo "kill tunnel with $pid..."
  kill -9 $pid
  wait $pid 2>/dev/null
}

# backup via rsync
rsync_backup () {
  rsync -e "ssh -p ${PORT}" "${roption[@]}" ${USER}@${SERVER}:${SHARE} ${bdir}

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

tar_backup () {
   echo "Tar Archive Backup"
   mkdir -p ${sdir}archive/
   ssh -p ${PORT} ${USER}@${SERVER} tar czf - ${SHARE} > ${sdir}archive/file.tar.gz
   rsyncsize=${#rsyncadd[@]}
   [ "$rsyncsize" -lt 1 ] && for radd in "${rsyncadd[@]}"
   do
      eval ${radd}
   done
}

# MAIN

if [[ $@ =~ "--sshCopy" ]]; then

  [[ "$@" =~ "--log" ]] && echo "Copy ssh public key"

  ssh-copy-id -i ~/.ssh/id_rsa.pub -p $PORT $USER@$SERVER

elif [ $BACKUP -eq 1 ]; then

  [[ "$@" =~ "--log" ]] && echo "Backup process started"

  remote_server_up || exit 1 && [[ "$@" =~ "--log" ]] && echo "Server is up"

  process_in_queue || exit 2 && [[ "$@" =~ "--log" ]] && echo "Backup was not already in queue"

  manage_queue && [[ "$@" =~ "--log" ]] && echo "Managed queue"

  write_to_queue && [[ "$@" =~ "--log" ]] && echo "Added backup to queue"


  # Backup process
  (
    [[ $mysqlIF == "true" ]] && mysql_backup

    echo "Starting Backup: $(date +"%y-%m-%d %H:%M")"
    echo "Backup Directory: $bdir"
    echo ""

    # Backup
    tc=0
    [[ $TYPE == "rsync" ]] && rsync_backup; tc=1
    [[ $TYPE == "share" ]] && share_backup; tc=1
    [[ $TYPE == "tar" ]] && tar_backup; tc=1
    [ $tc -eq 1 ] || exit 3

    echo "Successfull backup: $(date +"%y-%m-%d %H:%M")"
    rm -f ${sdir}run
    sed -i "/^$cID;.*$/d" ${reports}SBE-queue-run

    echo "$cID; ${START_DATE}; ${name}; ${PERIOD}; $(date);" >> ${reports}SBE-done

  ) >> ${sdir}bac.log | tee ${rdir}all.log 2> ${sdir}err.log | tee ${rdir}all.log

  [[ "$@" =~ "--log" ]] && echo "Backup done"

  manage_logs; [[ "$@" =~ "--log" ]] && echo "Managed logs"

  notify; [[ "$@" =~ "--log" ]] && echo "Notify"


fi
