#!/bin/bash

cd $(dirname $0)
sdir="$PWD/"
cd ..
hdir="$PWD/"
bdir="/var/backups/RT-Blog-SBE_settings/"
mkdir -p $bdir

for x in ${hdir}*; do

      if [ -d $x ] && [[ ! $x =~ "tools" ]]; then
            destination="${x}/"
            server=${x##*/}
            echo "Backup: ${server}"
            server="${server}/"
            rsync -a ${destination}server.config ${bdir}${server}
      fi

done
