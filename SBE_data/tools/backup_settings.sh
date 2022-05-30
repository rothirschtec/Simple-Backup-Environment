#!/bin/bash

cd $(dirname $0)
sdir="$PWD/"
cd ..
hdir="$PWD/"
cd ..
mdir="$PWD/"

if [ -f ${mdir}.env ]; then
    source ${mdir}.env
else
    echo "You have to configure .env first. Copy from env.example to .env and configure it."
    exit 1
fi

echo; echo $sbdir
read -p "The content of this directory will be erased (o): " a
[[ $a == "o" ]] || exit 1

rm -rf ${sbdir}*
mkdir -p $sbdir

for x in ${hdir}*; do

  if [ -d $x ] && [[ ! $x =~ "tools" ]]; then
    destination="${x}/"
    server=${x##*/}
    echo "Backup: ${server}"
    server="${server}/"
    rsync -a ${destination}server.config ${sbdir}${server}
  fi

done
