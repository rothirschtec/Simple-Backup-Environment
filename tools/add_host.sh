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
echo 'Change the /etc/ssh/sshd_config on your remote host'
echo ' - PermitRootLogin yes'
echo ' - PasswordAuthentication yes'
echo 'And restart it afterwards'
read -p 'Approve if done [Enter]'

ssh-copy-id -i ~/.ssh/id_rsa.pub -p $sport $suser@$sip 


bacfol="${hdir}${sname}/"
mkdir -p ${bacfol}

rsync -a ${hdir}tools/server.config    ${bacfol}
rsync -a ${hdir}tools/backup_server.sh ${bacfol}

read -p "Is there a mysql server to backup? (true): " mysqlIF
if [[ $mysqlIF != "true" ]]; then mysqlIF="false"; fi

sed -i 's/!#Host#!/'$sname'/g'          ${bacfol}server.config
sed -i 's/!#IPadress#!/'$sip'/g'        ${bacfol}server.config
sed -i 's/!#Port#!/'$sport'/g'          ${bacfol}server.config
sed -i 's/!#User#!/'$suser'/g'          ${bacfol}server.config

# mariadb
if [[ $mysqlIF == "true" ]]; then 

    if pwgen &> /dev/null; then 
    	mPa="$(pwgen -c -n -y -B -1 24 | tr '`"' '$@')"
    else
    	mPa="ThisIsNotAStrongPassword"
    fi
    echo
    echo 'Create an user on the mysql server'
    echo 'bash: mysql -u root -p'
    echo "mysql: GRANT ALL PRIVILEGES ON *.* to SBE@'localhost' IDENTIFIED BY '$mPa';"
    echo 'mysql: FLUSH PRIVILEGES;'
    echo 'mysql: quit'
    read -p 'Approve if done [Enter]'


	read -e -p "MySQL User: " -i "SBE" mUs
	read -e -p "MySQL Port: " -i "3306" mPo
	echo "MySQL Pass: " $mPa

	rsync -a ${hdir}tools/mysql.cnf     ${bacfol}
	sed -i 's/!#mysqlUSER#!/'$mUs'/g'   ${bacfol}mysql.cnf
	sed -i 's/!#mysqlPASS#!/'$mPa'/g'   ${bacfol}mysql.cnf
	sed -i 's/!#mysqlPORT#!/'$mPo'/g'   ${bacfol}mysql.cnf
	sed -i 's/!#mysqlIF#!/true/g'       ${bacfol}server.config
fi


echo "..."
echo "Configuration finished"
echo "Starting backup process for the first time"
#bash ${bacfol}backup_server.sh
