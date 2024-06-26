#!/bin/bash

cd "$(dirname "$0")"
hdir="$PWD/"
cd ..
mdir="$PWD/"

# Parse config
if [ -f "${mdir}.env" ]; then
	source "${mdir}.env"
else
	echo "You have to configure .env first. Copy from env.example to .env and configure it."
	exit 1
fi

source /etc/os-release
echo "$NAME"

echo; echo "QUEUE STATUS"
echo "------------"

echo; echo "Current queue:"
cat "${reports}SBE-queue"

echo; echo "Backups running at the moment:"
while read -r line; do
	echo "$line"
	pid=$(awk -F ';' '{print $1}' <<< "$line")

	if ps -p "$pid" &>/dev/null; then
		echo "  > Task is still alive"
	else
		echo "  > No task with PID detected"
	fi
done < "${reports}SBE-queue-run"

echo; echo "Backups done:"
if [ -f "${reports}SBE-done" ]; then
	echo "(Last 10)"
	tail -10 "${reports}SBE-done"
else
	echo "No backups with state DONE"
fi
