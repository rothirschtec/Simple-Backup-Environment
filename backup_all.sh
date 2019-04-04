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
        bash "${dir}/backup_server.sh" $@

    fi
done

rm -rf $tdir
exit 0
