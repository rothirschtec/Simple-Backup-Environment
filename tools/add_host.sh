#!/bin/bash
#
# Dependencies:
# - quota
# - pwgen
# - udisks2

# Script location
cd $(dirname $0)
sdir="$PWD/"

# SBE directory
cd ..
SBE_dir="$PWD/"

# Backup directory
bdir=""
bmount=""
# Backup loop device
bdisk=""

# Server name, used as backup directory name
sname=""
# Maximum size of backup directory
quota=""
# SSH user of the server
suser=""
# IP address of the server
sip=""
# SSH port of the server
sport=""



get_information () {
  read -p "HostName (used as backup directory name): " sname
  read -p "Backup max size (Format: 1000M or 1G): " bmaxsize
  read -p "User: " suser
  read -p "Server IP Adress: " sip
  read -p "Server Port: " sport
}

show_information () {
  echo; echo -----
  echo Backup directory: ${SBE_dir}${sname}
  echo Maximum backup directory size: $bmaxsize
  echo "Remote server: "
  echo SSH user: $suser
  echo IP address: $sip
  echo SSH port: $sport
  echo -----; echo
}

# Inform user how to configure ssh on the remote server
open_ssh () {
  echo
  echo 'Change the /etc/ssh/sshd_config on your remote host'
  echo ' - PermitRootLogin yes'
  echo ' - PasswordAuthentication yes'
  echo 'And restart the ssh service afterwards "service ssh restart"'
  read -p 'Approve if done [Enter]'
  echo ''
}

# Transfer SSH publick key
transfer_public_key () {
  scp -P $sport ~/.ssh/id_rsa.pub $suser@${sip}:~/.ssh/authorized_keys
  #ssh-copy-id -i ~/.ssh/id_rsa.pub -p $sport ${suser}@${sip}
}

# Inform user how to secure ssh on the remote server
close_ssh () {
  echo
  echo 'Change the /etc/ssh/sshd_config back to secure'
  echo ' - PermitRootLogin prohibit-password'
  echo ' - PasswordAuthentication no'
  echo 'And restart the ssh service again "service ssh restart"'
  read -p 'Approve if done [Enter]'
}

# Create filesystem with backup maximum size
create_backup_directory () {
  bdir="${SBE_dir}${sname}/"
  mkdir -p $bdir
  touch ${bdir}backups
  fallocate -l $bmaxsize ${bdir}backups

  mkfs.ext4 ${bdir}backups -E root_owner=$UID:$UID

}

get_backup_mount () {
  for disk in /dev/loop*; do
    if test -b $disk; then
      backingfile=$(udisksctl info -b $disk |grep BackingFile)
      if [[ $backingfile =~ /home/r9/Workbench/Projects/blog/blog-sbe/rt.bg_new/backup ]]; then
        # Find MountPoints and remove unneeded information
        bmount="$(udisksctl info -b $disk | grep 'MountPoints:' | awk -F ':' '{print $2}' | sed -e 's/^[ \t]*//')/"
        bdisk=$disk
      fi
    fi
  done
}

mount_backup_directory () {
  udisksctl loop-setup -f ${bdir}backups
  get_backup_mount
  echo "Backup mount: $bmount"
  sudo chown -R $USER:$USER ${bmount}
}

umount_backup_directory () {
  udisksctl unmount -b ${bdisk}
}

fill_backup_directory () {

  rsync -a ${SBE_dir}tools/server.config    ${bdir}
  rsync -a ${SBE_dir}tools/backup_server.sh ${bdir}

  sed -i 's/!#Host#!/'$sname'/g'          ${bdir}server.config
  sed -i 's/!#IPadress#!/'$sip'/g'        ${bdir}server.config
  sed -i 's/!#Port#!/'$sport'/g'          ${bdir}server.config
  sed -i 's/!#User#!/'$suser'/g'          ${bdir}server.config

  read -p "Is there a mysql server to backup? (true): " mysqlIF
  if [[ $mysqlIF != "true" ]]; then mysqlIF="false"; fi
  sed -i "s/!#mysqlIF#!/${mysqlIF}/g" ${bdir}server.config

}

# MAIN

get_information

show_information
read -p 'Do you want to continue with this settings? (y): ' a
[[ $a =~ [Yy] ]] || exit 1


read -p 'Transfer SSH pub key? (y): ' a
if [[ $a =~ [Yy] ]]; then
  open_ssh
  transfer_public_key
  close_ssh
fi

# Create backup
create_backup_directory
mount_backup_directory
fill_backup_directory

echo "..."
echo "Configuration finished"

echo "..."
echo "Starting first backup"
/bin/bash ${bdir}backup_server.sh &
echo "You can kill the process with - kill $!"

exit 0

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

	rsync -a ${SBE_dir}tools/mysql.cnf     ${bmount}
	sed -i 's/!#mysqlUSER#!/'$mUs'/g'   ${bmount}mysql.cnf
	sed -i 's/!#mysqlPASS#!/'$mPa'/g'   ${bmount}mysql.cnf
	sed -i 's/!#mysqlPORT#!/'$mPo'/g'   ${bmount}mysql.cnf
	sed -i 's/!#mysqlIF#!/true/g'       ${bmount}server.config
fi
