#!/bin/bash
#
# Main Task in Odoo: 
#
# You can copy your ssh key to the remote server if you want
# backup_server.sh sshCopy

set -euo pipefail
# # #
# "Dirs and vars"
cd $(dirname $0)
sdir="$PWD"
name=${sdir##*/}
sdir="${sdir}/"
cd ..
rdir="$PWD/"
error=false
# # #


# # #
# Wait 10 seconds for each existing backup process
# To avoid heavy loads
stmax=3
st=$(($stmax+1))
echo $$ >> /tmp/SBE-query
while [ "$st" -gt "$stmax" ]
do

    query=$(head -1 /tmp/SBE-query);
    # Check if first in query exists
    if ! ps -p $query &> /dev/null; then
        sed -i '1d' /tmp/SBE-query
    elif ! ps -ax | grep '^'${query}'.*bash.*/backup_server.sh' &> /dev/null; then
        sed -i '1d' /tmp/SBE-query
    else 

        sleep 5

        # End loop if st is less than 3
        if [[ $query == $$ ]]; then
            st=$(ps -ef | grep "bash.*/backup_server.sh" | wc -l)
            st=$(($st-3))
        fi
    fi

done
echo "Is running..." > ${sdir}run
echo ${sdir}run

exit 0
# # #
# Load config
if [ -f ${rdir}config ]; then
    source ${rdir}config
else
    source ${rdir}tools/config_example
fi

# # #
# Initialize vars
BDAYS=1
BWEEKS=1

# # #
# Source vars
    if [ -f ${sdir}server.config ]; then
        mysqlIF="false"
        source ${sdir}server.config
    else
        >&2 echo "No server.config found!!!"
        error=true
        # exit only this subshell
    fi
# # #

CURRENT_DAY=$((10#$(date +%j)))
CURRENT_WEEK=$((10#$(date +%V)))

if [[ $@ =~ "--weekly" ]]; then
     BUCKET=$(( CURRENT_WEEK % BWEEKS ))
     BUCKET_TYPE="weekly"
elif [[ $@ =~ "--archive" ]]; then
     BUCKET=$(( CURRENT_WEEK % BWEEKS ))
     BUCKET_TYPE="weekly"
     TYPE="tar"
else
     BUCKET=$(( CURRENT_DAY % BDAYS ))
     BUCKET_TYPE="daily"
fi


if [ $BACKUP -eq 1 ]; then

    # # #
    # Define shares
        mou="${sdir}${SHARE}"
        mdir="${sdir}${SHARE}/"
    # # #

    if [[ $@ =~ "--sshCopy" ]]; then

	ssh-copy-id -i ~/.ssh/id_rsa.pub -p $PORT $USER@$SERVER

    elif [[ $error == false ]]; then

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
                    echo "backup..."
                    # $1:mysql config file, $2:backupdir, $3:sendmail(1/0), $4:mail mail, $5:delete backups after 
                    if [[ "$BUCKET_TYPE" == "weekly" ]]; then
                        /bin/bash ${rdir}tools/mysql-backup.sh "${sdir}mysql.cnf" "${bmdi}" "$mail" "$sdir" "$MBWEEKS"
                    else
                        /bin/bash ${rdir}tools/mysql-backup.sh "${sdir}mysql.cnf" "${bmdi}" "$mail" "$sdir" "$MBDAYS"
                fi
                   
                fi
                echo "kill tunnel with $pid..."
                kill -9 $pid
                wait $pid 2>/dev/null
            fi

            bdir="${sdir}rotate_bak/${BUCKET_TYPE}/${BUCKET}/"
            mkdir -p ${bdir}
            echo "Starting Backup: $(date +"%y-%m-%d %H:%M")"
            echo "Backup Directory: $bdir"
            echo ""

            # # #
            # Backup
            if [[ $TYPE == "rsync" ]]; then

               echo "Rsync Backup"
               rsync -e "ssh -p ${PORT}" "${roption[@]}" ${USER}@${SERVER}:${SHARE} ${bdir}
               for radd in "${rsyncadd[@]}"
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
               for radd in "${rsyncadd[@]}"
               do
                  eval ${radd}
               done


            else

                >&2 echo "TYPE not defined"
                exit 12

            fi
            # # #

            echo "Successfull backup: $(date +"%y-%m-%d %H:%M")"

        ) > ${sdir}bac.log | tee ${rdir}all.log 2> ${sdir}err.log | tee ${rdir}all.log
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

    # # #
    # End message

    if [[ "$@" =~ "--log" ]]; then
        # Add disk space stats of backup filesystem
        cat ${sdir}bac.log | mail -s "[SBE] Backup log from host: $name" $mail
    fi
    if [ $(cat ${sdir}err.log | wc -w | awk '{ print $1 }') -gt 0 ]; then
        echo "Script stopped: $(date +"%y-%m-%d %H:%M")" >> ${sdir}err.log
        cat ${sdir}err.log | mail -s "[SBE] !!!ERROR!!!, detected on host: $name" $mail
    fi
    # # #

    rm -f ${sdir}run
        
fi # if $BACKUP -eq 1
