#!/bin/bash
#
# Main Task in Odoo: 
# https://odoo.gasmotoren.company/web?debug=#id=1392&view_type=form&model=project.task&action=141&active_id=8
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
# Load config
if [ -f ${rdir}config.sh ]; then
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


                ssh -p ${PORT} -o ServerAliveInterval=10 -M -T -M -N -L 3309:127.0.0.1:${myPort} ${USER}@${SERVER} 2>  ${sdir}err.log &
                pid=$!
                echo "Got pid $pid ..."
                if [ $(wc -c ${sdir}err.log | awk '{print $1}') -eq 0 ]; then
                    sleep 2
                    echo "backup..."
                  
                    # $1:mysql config file, $2:backupdir, $3:sendmail(1/0), $4:mail mail, $5:delete backups after 
                    /bin/bash ${rdir}tools/mysql-backup.sh "${sdir}mysql.cnf" "${bmdi}" "$mail" "$sdir"
                   
                fi
                echo "kill tunnel with $pid..."
                kill -9 $pid
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


    fi

    # # #
    # End message
    if [[ $(cat ${sdir}err.log) != "" ]]; then
        echo "Script stopped: $(date +"%y-%m-%d %H:%M")" >> ${sdir}err.log
        cat ${sdir}err.log | mail -s "Backup Problem!!! ${name}" $mail
    fi
    # # #
        
fi # if $BACKUP -eq 1
