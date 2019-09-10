#!/bin/bash

# Checks dependencies and tries to install them
installed=0
dep=("mysql-client" "mailutils" "pwgen" "cstream")
for x in "${dep[@]}"; do
    dpkg -s $x &> /dev/null
    if [ $? -eq 1 ]; then
        echo "$x: is not installed"
        read -p "The package '$x' is needed. Should I install it? (yN): " install
        if [[ $install == [yY] ]]; then
            apt-get install $x
            installed=1
	else
		echo ""; echo "Sorry but you have to install the dependencies at least"
		exit 1
        fi
    fi
done
# # #

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

    mPa="$(pwgen -c -n -y -B -1 24 | tr '`"' '$@')"
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
