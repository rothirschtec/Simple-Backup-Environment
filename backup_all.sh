#!/bin/bash

cd $(dirname $0)
hdir="$PWD/"
tdir="/tmp/SBE/$RANDOM/"
mkdir -p $tdir

function getlatest() {
    echo "Getting latest version"
    git pull &> /dev/null
    bash ${hdir}tools/update_scripts.sh &> /dev/null
}

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

        if [[ $MACHTYPE == x86_64-QNAP-linux-gnu ]]; then

            if  [[ $@ =~ "--weekly" ]] && \
                [ $(ps -w | grep "bash.*${host}/backup_server.sh.*--weekly" | wc -l) -eq 1 ]; then
                echo "Starting daily backup for $host..."
                getlatest
                bash "${dir}/backup_server.sh" $@ &

            elif [[ $@ =~ "--daily" ]] && \
                 [ $(ps -w | grep "bash.*${host}/backup_server.sh.*--daily" | wc -l) -eq 1 ]; then
                echo "Starting daily backup for $host..."
                getlatest
                bash "${dir}/backup_server.sh" $@ &

            else
                echo "Backup for $host under way..."
            fi

        else
            if  [[ $@ =~ "--weekly" ]] && \
                [ $(ps -ef | grep "bash.*${host}/backup_server.sh.*--weekly" | wc -l) -eq 1 ]; then
                echo "Starting weekly backup for $host..."
                getlatest
                bash "${dir}/backup_server.sh" $@ &

            elif [[ $@ =~ "--daily" ]] && \
                 [ $(ps -ef | grep "bash.*${host}/backup_server.sh.*--daily" | wc -l) -eq 1 ]; then
                echo "Starting daily backup for $host..."
                getlatest
                bash "${dir}/backup_server.sh" $@ &

            else
                echo "Backup for $host under way..."
            fi
        fi
    fi
done

rm -rf $tdir
exit 0
