#!/bin/bash
#
set -euo pipefail

# Function for generating Email
function gen_log {
    newline=$1
    line=$2
    file=$3
    if [ $newline -eq 1 ]; then
        echo "$line" >> $file
    else
        echo -n "$line" >> $file
    fi
}

# Get data in yyyy-mm-dd format
DATE=`date +%Y-%m-%d_%H-%M-%S` DAY=`date +%Y-%m-%d` 

# $1 -> authFile
# Mysql Credentials
authFile=$1

# $2 -> backupdir
# Backup Dest directory, change this if you have someother location
destination=$2

# $3 -> notifymail
NOTIFY_EMAIL=$3

# $4 -> SBE location
SBE_dir=$4

# Modify the variables below to your need


# Linux bin paths, change this if it can't be autodetected via which command
MYSQL="$(which mysql)"
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
NOTIFY_SUBJECT="${HOST}: MySQL Backup Notification ($DAY)"

# Or specify which databases to backup
#DBS="mysql zarafa"

# DO NOT BACKUP these databases
IGGY="test performance_schema information_schema"

# mysqldump parameters
DUMP_OPTS='-Q --skip-lock-tables --single-transaction --max_allowed_packet=1024M '

# Temp Message file
backup_log="${SBE_dir}bac.log"
error_log="${SBE_dir}err.log"

# Backup all existing databases
DBS=$($MYSQL --defaults-file=$authFile -Bse "show databases" 2> $error_log)

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
        FILE="${destination}$db.$HOST.$DATE"
        # do all inone job in pipe,
        # connect to mysql using mysqldump for select mysql database
        # and pipe it out to gz file in backup dir :)

        # # #
        # BACKUP HERE
        echo "Backup DB: $db" >> $backup_log

        if [[ $db == *"mysql"* ]]; then
            $MYSQLDUMP --defaults-file=$authFile $DUMP_OPTS --events --ignore-table=mysql.events $db | $GZIP -9 | cstream -t 100000000 > "$FILE.gz" 2> $error_log
        else
            $MYSQLDUMP --defaults-file=$authFile $DUMP_OPTS  $db | $GZIP -9 | cstream -t 100000000 > "$FILE.gz" 2> $error_log
        fi
    fi
done


echo "Backup script ended successfully"
exit 0
