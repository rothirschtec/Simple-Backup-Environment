#!/bin/bash

read -p "HostName: " sname
read -p "User: " suser
read -p "Server IP Adress: " sip
read -p "Server Port: " sport

read -p "Is there a mysql server to backup? (true): " mysqlIF
if [[ $mysqlIF != "true" ]]; then mysqlIF="false"; fi

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

rsync -a ${hdir}tools/server.config    ${bacfol}
rsync -a ${hdir}tools/backup_server.sh ${bacfol}

sed -i 's/!#Host#!/'$sname'/g'          ${bacfol}server.config
sed -i 's/!#IPadress#!/'$sip'/g'        ${bacfol}server.config
sed -i 's/!#Port#!/'$sport'/g'          ${bacfol}server.config
sed -i 's/!#User#!/'$suser'/g'          ${bacfol}server.config

# mySql
if [[ $mysqlIF == "true" ]]; then 

    read -p "MySQL User: " mUs
    read -p "MySQL Pass: " mPa
    read -p "MySQL Port: " mPo

    rsync -a ${hdir}tools/mysql.cnf     ${bacfol}
    sed -i 's/!#mysqlUSER#!/'$mUs'/g'   ${bacfol}mysql.cnf
    sed -i 's/!#mysqlPASS#!/'$mPa'/g'   ${bacfol}mysql.cnf
    sed -i 's/!#mysqlPORT#!/'$mPo'/g'   ${bacfol}mysql.cnf
    sed -i 's/!#mysqlIF#!/true/g'       ${bacfol}server.config
fi


echo "..."
echo "Configuration finished"
echo "Starting backup process for the first time"
bash ${bacfol}backup_server.sh
