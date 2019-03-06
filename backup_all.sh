#!/bin/bash

cd $(dirname $0)
hdir="$PWD/"
tdir="/tmp/SBE/$RANDOM/"
mkdir -p $tdir

if [ -f ${hdir}config ]; then
    source ${hdir}config
else
    source ${hdir}tools/config_example
fi

echo "Backup"
for x in $(find . -maxdepth 2 -mindepth 1 -type f -name 'backup_server.sh')
do
    if [[ $x != *"tools"* ]]; then
        dir="$(dirname $x)"

        host="${dir##*/}"
        echo "Backup: $host"
        bash "${dir}/backup_server.sh" $1

        if [ $(cat ${dir}/err.log | wc -w | awk '{ print $1 }') -gt 0 ]; then
            cat ${dir}/err.log | mail -s "[SBE] !!!ERROR!!! Backup error detected on host: $host" $mail
        fi
        if [[ "$@" =~ "--log" ]]; then

            # Add disk space stats of backup filesystem
            cat ${dir}/bac.log | mail -s "[SBE] Backup log from host: $host" $mail
        fi
    fi
done

# # #
# Send summary
echo ""; echo "Backup of all instances done on $HOSTNAME"; echo "" > ${tdir}end.log
/bin/df >> ${tdir}end.log
if [[ "$@" =~ "--log" ]]; then
    cat ${tdir}end.log | mail -s "[SBE] All Backups done on host: $host" $mail
fi

rm -rf $tdir
exit 0
