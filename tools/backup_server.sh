#!/bin/bash
#
# You can copy your ssh key to the remote server if you want
# backup_server.sh sshCopy

# @1 Set variables
#   @1.1 Directories
#   @1.2 Dates and types
# @2 Load configuration files
#   @2.1 Default configruation can be change in config file
# @3 Check if remote server is availabe for backup operations
# @4 Check if there already exists a backup process for the given server and BUCKET_TYPE
#   @4.1 Clean queue
#   @4.2 Check queue
# @5 Manage queue - To avoid heavy loads
#   @5.1 Delete empty lines in queue files
#   @5.2 Add the remote server to the queue if the PID does not exist
#   @5.3 Check if SBE-queue-run exists. If not, backup should start immediately 
#       @5.3.1 Pick next in queue
#       @5.3.2 Check if the PID used in SBE-queue is really used at the moment (Delete old entries)
#       @5.3.3 Check if the PID used in SBE-queue-run is really used at the moment (Delete old entries)
#       @5.3.4 Check if there's already a backup process for the remote server in queue-run. If so, use next entry in queue
#       @5.3.5 End loop if queue exists and queue run count is less then stmax
#       @5.3.6 Wait for 2 seconds if 
# @6 Write to queue-run
# @7 Backup




# @1 ------------------------------
# @1.1
set -euo pipefail
cd $(dirname $0)
sdir="$PWD"
name=${sdir##*/}
sdir="${sdir}/"
cd ..
rdir="$PWD/"
error=false



# @1.2
BDAYS=1
BWEEKS=1
BMONTHS=1


# @2 ------------------------------

# @2.1
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

CURRENT_DAY=$((10#$(date +%j)))
CURRENT_WEEK=$((10#$(date +%V)))
CURRENT_MONTH=$((10#$(date +%m)))
START_DATE=$(date)

if [[ $@ =~ "--weekly" ]]; then
     BUCKET=$(( CURRENT_WEEK % BWEEKS ))
     BUCKET_TYPE="weekly"
elif [[ $@ =~ "--monthly" ]]; then
     BUCKET=$(( CURRENT_MONTH % BMONTHS ))
     BUCKET_TYPE="monthly"
elif [[ $@ =~ "--archive" ]]; then
     BUCKET=$(( CURRENT_WEEK % BWEEKS ))
     BUCKET_TYPE="archive"
     TYPE="tar"
else
     BUCKET=$(( CURRENT_DAY % BDAYS ))
     BUCKET_TYPE="daily"
fi


if [ $BACKUP -eq 1 ]; then

	# @3 --------------------------

	ssh ${USER}@$SERVER -p $PORT "echo 2>&1" && online=1 || online=0
	if [ $online -eq 0 ]; then

	    echo "Server down"
	    exit 1

	fi


	# @4 --------------------------

	if [ -f ${reports}SBE-queue ]; then
		# @4.1
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

		# @4.2
		if cat ${reports}SBE-queue | grep ${name} | grep ${BUCKET_TYPE} &> /dev/null; then
		    echo "Already in queue"
		    exit 2
		fi
	else
		touch ${reports}SBE-queue
	fi

	if [ ! -f ${reports}SBE-queue-run ]; then
		touch ${reports}SBE-queue-run
	fi


	# @5 --------------------------
	stmax=2
	st=$(($stmax+1))
	sti=1
	rm -f ${sdir}run
	while [ "$st" -ge "$stmax" ]
	do


	    # @5.1
	    sed -i '/^$/d' ${reports}SBE-queue
	    sed -i '/^$/d' ${reports}SBE-queue-run

	    # @5.2
	    if [ ! -f ${reports}SBE-queue ]; then
		echo "$$; ${START_DATE}; ${name}; ${BUCKET_TYPE};" >> ${reports}SBE-queue
	    else
		if ! cat ${reports}SBE-queue | grep $$ &> /dev/null; then
		    echo "$$; ${START_DATE}; ${name}; ${BUCKET_TYPE};" >> ${reports}SBE-queue
		fi
	    fi


	    # @5.3
	    if [ -f ${reports}SBE-queue-run ]; then

		# @5.3.1
		queue=$(sed -n ${sti}p ${reports}SBE-queue);

		# @5.3.2
		while read rline
		do
		    runq=$(awk -F";" '{print $1}' <<< $rline)
		    if [ ! -e /proc/${runq} -a /proc/${runq}/exe ]; then
			sed -i "/^$runq;.*$/d" ${reports}SBE-queue
			sed -i '/^$/d' ${reports}SBE-queue
		    fi
		done < ${reports}SBE-queue

		# @5.3.3
		while read rline
		do
		    runq=$(awk -F";" '{print $1}' <<< $rline)
		    if [ ! -e /proc/${runq} -a /proc/${runq}/exe ]; then
			sed -i "/^$runq;.*$/d" ${reports}SBE-queue-run
			sed -i '/^$/d' ${reports}SBE-queue-run
		    fi
		done < ${reports}SBE-queue-run


		# @5.3.4
		if ! cat ${reports}SBE-queue-run | grep ${name} &> /dev/null; then

		    # @5.3.5
		    if [[ $queue =~ "$$;" ]]; then
			st=$(cat ${reports}SBE-queue-run | wc -l)
		    fi

		    # @5.3.6
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


	# @6 ---------------------------
	cID=$$
	echo "$cID; ${START_DATE}; ${name};" >> ${reports}SBE-queue-run
	sed -i "/^$cID;.*$/d" ${reports}SBE-queue




    # # #
    # Define shares
        mou="${sdir}${SHARE}"
        mdir="${sdir}${SHARE}/"
    # # #

    if [[ $@ =~ "--sshCopy" ]]; then

	    ssh-copy-id -i ~/.ssh/id_rsa.pub -p $PORT $USER@$SERVER

    elif [[ $error == false ]]; then


	# @7 ---------------------------

        # # #
        # Remove old logs
            rm -f ${sdir}err.log
            rm -f ${sdir}bac.log
        # # #

        
        # # #
        # Backup process
        ( 

            if [[ $mysqlIF == "true" ]]; then

                echo "mySql Backup"

                bmdi="${sdir}mysql/${BUCKET_TYPE}/${BUCKET}/"
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
                    if [[ "$BUCKET_TYPE" == "weekly" ]]; then
                        /bin/bash ${rdir}tools/mysql-backup.sh "${sdir}mysql.cnf" "${bmdi}" "$sdir" "$MBWEEKS"
                    else
                        /bin/bash ${rdir}tools/mysql-backup.sh "${sdir}mysql.cnf" "${bmdi}" "$sdir" "$MBDAYS"
                    fi
                   
                fi
                echo "kill tunnel with $pid..."
                kill -9 $pid
                wait $pid 2>/dev/null
            fi

            bdir="${sdir}rotate_bak/${BUCKET_TYPE}/${BUCKET}_$(date +"%Y-%m-%d_%H%M%S")/"
            if [ -d ${sdir}rotate_bak/${BUCKET_TYPE}/${BUCKET}* ]; then
                olddir=$(echo ${sdir}rotate_bak/${BUCKET_TYPE}/${BUCKET}*)
                mv $olddir $bdir
            else
                mkdir -p ${bdir}
            fi
            echo "Starting Backup: $(date +"%y-%m-%d %H:%M")"
            echo "Backup Directory: $bdir"
            echo ""

            # # #
            # Backup
            if [[ $TYPE == "rsync" ]]; then

               echo "Rsync Backup"
               rsync -e "ssh -p ${PORT}" "${roption[@]}" ${USER}@${SERVER}:${SHARE} ${bdir}
               rsyncsize=${#rsyncadd[@]}
               [ "$rsyncsize" -lt 1 ] && for radd in "${rsyncadd[@]}"
               do
                  eval ${radd}
               done

            elif [[ $TYPE == "mount" ]]; then

                echo "Mount and backup"
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

            elif [[ $TYPE == "tar" ]]; then

               echo "Tar Archive Backup"
               mkdir -p ${sdir}archive/
               ssh -p ${PORT} ${USER}@${SERVER} tar czf - ${SHARE} > ${sdir}archive/file.tar.gz
               rsyncsize=${#rsyncadd[@]}
               [ "$rsyncsize" -lt 1 ] && for radd in "${rsyncadd[@]}"
               do
                  eval ${radd}
               done


            else

                >&2 echo "TYPE not defined"
                exit 12

            fi
            # # #

            echo "Successfull backup: $(date +"%y-%m-%d %H:%M")"
            rm -f ${sdir}run
            sed -i "/^$cID;.*$/d" ${reports}SBE-queue-run

	    echo "$cID; ${START_DATE}; ${name}; ${BUCKET_TYPE}; $(date);" >> ${reports}SBE-done

        ) >> ${sdir}bac.log | tee ${rdir}all.log 2> ${sdir}err.log | tee ${rdir}all.log
        # # #

        if [ -f ${sdir}mysql/mysql_bac.log ]; then
            echo ""                         >> ${sdir}bac.log
            echo "# # #"                    >> ${sdir}bac.log
            echo "# MYSQL Backups"          >> ${sdir}bac.log
            echo ${sdir}mysql/mysql_bac.log >> ${sdir}bac.log
        fi

        if [ -f ${sdir}mysql/mysql_err.log ]; then
            echo ${sdir}mysql/mysql_err.log >> ${sdir}err.log
        fi


    fi


    # End message
    if [[ "$@" =~ "--log" ]]; then
        # Add disk space stats of backup filesystem
        echo -e "Subject: Backup Success with $name on $HOSTNAME\n\n $(cat ${sdir}bac.log)" | /usr/sbin/sendmail $mail

    fi
    if [ $(cat ${sdir}err.log | wc -w | awk '{ print $1 }') -gt 0 ]; then
        echo "Script stopped: $(date +"%y-%m-%d %H:%M")" >> ${sdir}err.log
        echo -e "Subject: Backup Error with $name on $HOSTNAME\n\n $(cat ${sdir}err.log)" | /usr/sbin/sendmail $mail
	exit 1
    fi
    # # #

        
fi # if $BACKUP -eq 1
