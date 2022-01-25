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
source /etc/os-release
echo $NAME

echo; echo "QUEUE STATUS"
echo "------------"

echo; echo "Current queue:"
cat ${reports}SBE-queue

echo; echo "Backups running at the moment:"
while read line
do
	echo $line
	pid=$(awk -F ';' '{print $1}' <<< $line)

	if ps -p $pid &>/dev/null; then
		echo "  > Task ist still alive"
	else
		echo "  > No task with PID detected"
	fi

done < ${reports}SBE-queue-run



echo; echo "Backups done:"
if [ -f ${reports}SBE-done ]; then
	echo "(Last 10)"
	tail -10 ${reports}SBE-done
else
	echo "No backups with state DONE"
fi
