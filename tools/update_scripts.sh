#!/bin/bash

cd $(dirname $0)
sdir="$PWD/"
cd ..
hdir="$PWD/"

for x in ${hdir}*; do

      if [ -d $x ] && [[ ! $x =~ "tools" ]]; then 
            destination="${x}/"
            echo "Update: ${destination}backup_server.sh"
            cp ${hdir}tools/backup_server.sh ${destination}
      fi 
done
