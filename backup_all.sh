#!/bin/bash

cd $(dirname $0)
hdir="$PWD/"

if [ -f ${hdir}config.sh ]; then
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
            cat ${dir}/bac.log | mail -s "[SBE] Backup log from host: $host" $mail
        fi
    fi
done
