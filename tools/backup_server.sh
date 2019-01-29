#!/bin/bash
#
# Main Task in Odoo: 
# https://odoo.gasmotoren.company/web?debug=#id=1392&view_type=form&model=project.task&action=141&active_id=8
#
# You can copy your ssh key to the remote server if you want
# backup_server.sh sshCopy


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
# Initialize vars
BDAYS=1
BWEEKS=1

# # #
# Source vars
    if [ -f ${sdir}server.config ]; then
        source ${sdir}server.config
    else
        >&2 echo "No server.config found!!!"
        error=true
        # exit only this subshell
    fi
# # #

CURRENT_DAY=$((10#$(date +%j)))
CURRENT_WEEK=$((10#$(date +%V)))

if [ "$1" == "--weekly" ]; then
     BUCKET=$(( CURRENT_WEEK % BWEEKS ))
     BUCKET_TYPE="weekly"
elif [ "$1" == "--archive" ]; then
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

    if [[ $1 == "sshCopy" ]]; then

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
        echo "Scripts stopped: $(date +"%y-%m-%d %H:%M")" >> ${sdir}err.log
        source ${rdir}tools/mailtools.sh
        mail2admin "$(cat ${sdir}err.log)" "Backup Problem!!!" "${name}|$(basename $0)"
    fi
    # # #
        
fi # if $BACKUP -eq 1
