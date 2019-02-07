#!/bin/bash
#

# Get data in yyyy-mm-dd format
DATE=`date +%Y-%m-%d_%H-%M-%S` DAY=`date +%Y-%m-%d` 
# Function for generating Email
function gen_email {
  DO_SEND=$1
  TMP_FILE=$2
  NEW_LINE=$3
  LINE=$4
  if [ $DO_SEND -eq 1 ]; then
    if [ $NEW_LINE -eq 1 ]; then
      echo "$LINE" >> $TMP_FILE
    else
      echo -n "$LINE" >> $TMP_FILE
    fi
  fi
}

# $1 -> authFile
# $2 -> backupdir
# $3 -> sendmail? (1/0)
# $4 -> notifymail

# Modify the variables below to your need

# Mysql Credentials
authFile=$1
rHost=$(cat $authFile |grep ^'# sshHostName=')
rHost=$(sed 's/# sshHostName=//g' <<< $rHost)

MYSQL="$(which mysql)"

# Linux bin paths, change this if it can't be autodetected via which command
MYSQLDUMP="$(which mysqldump)"
GREP="$(which grep)"
CHOWN="$(which chown)"
CHMOD="$(which chmod)"
GZIP="$(which gzip)"
MAIL="$(which mail)"
FIND="$(which find)"
DF="$(which df)"

# Get hostname
HOST="$(hostname)"

# Send Result EMail
SEND_EMAIL=$3
NOTIFY_EMAIL=$4
NOTIFY_SUBJECT="${HOST}: MySQL Backup Notification ($DAY)"

killIT=0

# Or specify which databases to backup
#DBS="mysql zarafa"

# DO NOT BACKUP these databases
IGGY="test performance_schema information_schema"

# Backup Dest directory, change this if you have someother location
DEST=$2

# mysqldump parameters
DUMP_OPTS='-Q --skip-lock-tables --single-transaction --max_allowed_packet=1024M '

# Owner of mysql backup dir
OWNER="root"
# Group of mysql backup dir
GROUP="root"

# Temp Message file
LOG_DIR="/var/log/backups/"
errMSG="${LOG_DIR}${rHost}_${DATE}.log"

# Delete old backups
DELETE_OLD_BACKUPS=1 # (1/0)
if [ -z $5 ]; then
    gen_email $SEND_EMAIL $errMSG 1 'U need to use all 8 config options'
    killIT=1
else
    re='^[0-99]+$'
    if [[ $5 =~ $re ]]; then
        DELETE_BACKUPS_OLDER_THAN_DAYS=$5
    else
        gen_email $SEND_EMAIL $errMSG 1 'U need to use a [0-99] integer on $5'
        killIT=1
    fi
fi

# Backup all existing databases
DBS=$($MYSQL --defaults-file=$authFile -Bse "show databases") &> ${errMSG}
ERR=$?

if [[ $ERR != 0 ]]; then
    gen_email $SEND_EMAIL $errMSG 1 'Error: '"$ERR"', while backing up database: '"$db"''
    gen_email $SEND_EMAIL $errMSG 1 'MSG: '"$(cat ${errMSG})"''
    killIT=1
fi	

if [[ $killIT == 0 ]]; then

    # Main directory where backup will be stored
    if [ ! -d $DEST ]; then 
      mkdir -p $DEST
      # Only $OWNER.$GROUP can access it!
      $CHOWN $OWNER:$GROUP -R $DEST
      $CHMOD 0750 $DEST
    fi

    # Create backup directory
    MBD="$DEST/$DATE"
    if [ ! -d "$MBD" ]; then
      mkdir "$MBD"
      # Only $OWNER.$GROUP can access it!
      $CHOWN $OWNER:$GROUP -R $MBD
      $CHMOD 0750 $MBD
    fi

    set -o pipefail

    # Start backing up databases
    STARTTIME=$(date +%s)
    for db in $DBS
    do
        skipdb=-1
        if [ "$IGGY" != "" ];
        then
            for i in $IGGY
            do
            [ "$db" == "$i" ] && skipdb=1 || :
            done
        fi

        if [ "$skipdb" == "-1" ] ; then
            FILE="$MBD/$db.$HOST.$DATE"
            # do all inone job in pipe,
            # connect to mysql using mysqldump for select mysql database
            # and pipe it out to gz file in backup dir :)

            # # #
            # BACKUP HERE
            if [[ $db == *"mysql"* ]]; then
                $MYSQLDUMP --defaults-file=$authFile $DUMP_OPTS --events --ignore-table=mysql.events $db | $GZIP -9 | cstream -t 100000000 > "$FILE.gz" 
            else
                $MYSQLDUMP --defaults-file=$authFile $DUMP_OPTS  $db | $GZIP -9 | cstream -t 100000000 > "$FILE.gz" 
            fi

            ERR=$?
            if [[ $ERR != 0 ]]; then
                NOTIFY_MESSAGE="Error: $ERR, while backing up database: $db"	
                killIT=1
            else
                NOTIFY_MESSAGE="Successfully backed up database: $db"
            fi	
            gen_email $SEND_EMAIL $errMSG 1 "$NOTIFY_MESSAGE"
        fi
    done

    if [[ $killIT == 0 ]]; then
        ENDTIME=$(date +%s)
        DIFFTIME=$(( $ENDTIME - $STARTTIME ))
        DUMPTIME="$(($DIFFTIME / 60)) minutes and $(($DIFFTIME % 60)) seconds."

        # Empty line in email and stdout
        gen_email $SEND_EMAIL $errMSG 1 ""
        echo ""

        # Log Time
        gen_email $SEND_EMAIL $errMSG 1 "mysqldump took: ${DUMPTIME}"

        # Empty line in email and stdout
        gen_email $SEND_EMAIL $errMSG 1 ""
        echo ""

        # Delete old backups

        if [ $DELETE_OLD_BACKUPS -eq 1 ]; then

            find "$DEST" -maxdepth 1 -mtime $DELETE_BACKUPS_OLDER_THAN_DAYS -type d | $GREP -v "^$DEST$" | while read DIR; do

                if [[ $killIT == 0 ]]; then
                    gen_email $SEND_EMAIL $errMSG 0 "Deleting: $DIR: "
                    rm -rf "$DIR"  &>> ${errMSG}
                    ERR=$?
                    if [ $ERR != 0 ]; then
                        NOTIFY_MESSAGE="ERROR: ${errMSG}"
                        killIT=1
                    else
                        NOTIFY_MESSAGE="rm $DIR [OK]"
                    fi
                    gen_email $SEND_EMAIL $errMSG 1 "$NOTIFY_MESSAGE"
                fi

            done

        fi
    fi
fi

# Empty line in email
gen_email $SEND_EMAIL $errMSG 1 ""
gen_email $SEND_EMAIL $errMSG 1 "--------------------------------------------------------"

# Add disk space stats of backup filesystem
if [ $SEND_EMAIL -eq 1 ]; then
  $DF -h "$DEST" >> "$errMSG"  
fi

# Sending notification email
if [ $SEND_EMAIL -eq 1 ]; then
    if [[ $killIT != 0 ]]; then
        $MAIL -s "$NOTIFY_SUBJECT" "$NOTIFY_EMAIL" < "$errMSG"
        echo "Backup script ends with problems"
        exit $ERR
    fi
fi

# Delete old LOG files
days="14"
minLogFiles="10"

check_amount() {
    ls -l $LOG_DIR${rHost}_* | wc -l
}

while read -r p
do

    vName=${p##*/}
    vName=${vName%*.log}
    vDate=$(awk 'BEGIN{FS=OFS="_"}{print $2}' <<< $vName)
    vTime=$(awk 'BEGIN{FS=OFS="_"}{print $3}' <<< $vName)
    vTime=$(sed 's/-/:/g' <<< $lTime)

    oDate="$vDate $vTime"
    oDate=$(date "+%s" -d "$oDate" )
    mDate=$(date --date="$days days ago" +"%s")
    if [ $oDate -lt $mDate ]; then
        if [ $(check_amount) -ge 10 ]; then
            rm -f $p
        fi  
    fi
done < <(ls $LOG_DIR${rHost}_*)

echo "Backup script ended successfully"
exit 0
