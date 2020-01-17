#!/bin/bash

echo "QUEUE"
cat /tmp/SBE-queue
echo "RUN"
cat /tmp/SBE-queue-run

if [ -f /tmp/SBE-done ]; then
	echo "DONE (Last 10)"
	tail -10 /tmp/SBE-done
else
	echo "No backups with state DONE"
fi
