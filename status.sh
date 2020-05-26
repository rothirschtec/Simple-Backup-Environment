#!/bin/bash


cd $(dirname $0)
hdir="$PWD/"

# # #
# Parse config
if [ -f ${hdir}config ]; then
    source ${hdir}config
else
    source ${hdir}tools/config_example
fi


echo "QUEUE"
cat ${reports}SBE-queue
echo "RUN"
cat ${reports}SBE-queue-run

if [ -f ${reports}SBE-done ]; then
	echo "DONE (Last 10)"
	tail -10 ${reports}SBE-done
else
	echo "No backups with state DONE"
fi
