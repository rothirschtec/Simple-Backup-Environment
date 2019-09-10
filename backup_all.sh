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

        echo "0" > ${dir}/run
        ps -ef | grep bash | while read psLine; do
                if [[ $psLine == *"${host}/backup_server.sh"* ]]; then
                    echo 1 > ${dir}/run
                fi
        done

        if [ $(cat ${dir}/run) -eq 0 ]; then
                echo "Starting backup for $host..."
                bash "${dir}/backup_server.sh" $@ &
        else
                echo "Backup for $host under way..."
        fi

    fi
done

rm -rf $tdir
exit 0
