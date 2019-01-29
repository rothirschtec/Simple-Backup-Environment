#!/bin/bash

read -p "HostName: " sname
read -p "User: " suser
read -p "Server IP Adress: " sip
read -p "Server Port: " sport

cd $(dirname $0)
sdir="$PWD/"
cd ..
hdir="$PWD/"


echo
echo 'Change the ssh config on your remote server'
echo ' - PermitRootLogin yes'
echo ' - PasswordAuthentication yes'
read -p 'Approve if done [Enter]'

ssh-copy-id -i ~/.ssh/id_rsa.pub -p $sport $suser@$sip 

bacfol="${hdir}${sname}/"
mkdir -p ${bacfol}

rsync -av ${hdir}tools/server.config    ${bacfol}/
rsync -av ${hdir}tools/backup_server.sh ${bacfol}/

sed -i 's/!#Host#!/'$sname'/g'          ${bacfol}server.config
sed -i 's/!#IPadress#!/'$sip'/g'        ${bacfol}server.config
sed -i 's/!#Port#!/'$sport'/g'          ${bacfol}server.config
sed -i 's/!#User#!/'$suser'/g'          ${bacfol}server.config

bash ${bacfol}backup_server.sh
