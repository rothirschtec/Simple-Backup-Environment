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

echo "QUEUE STATUS"
echo "------------"

echo; echo "Current queue:"
cat ${reports}SBE-queue

echo; echo "Backups running at the moment:"
cat ${reports}SBE-queue-run

echo; echo "Backups done:"
if [ -f ${reports}SBE-done ]; then
	echo; echo "DONE (Last 10)"
	tail -10 ${reports}SBE-done
else
	echo "No backups with state DONE"
fi
