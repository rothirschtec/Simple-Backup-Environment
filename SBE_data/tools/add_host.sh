#!/bin/bash
#
# Dependencies:
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

[[ "$@" =~ "--encrypted" ]] && encrypted=1 ||  encrypted=0


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

# Encrypt and store passphrase
encrypt_backup_directory () {
  passphrase=$(pwgen -s 16 1)
  echo -n "$passphrase" | cryptsetup -y luksFormat --type luks2 ${bdir}backups
  echo -n "$passphrase" | cryptsetup luksOpen --type luks2 ${bdir}backups ${sname}.mounted
  echo $passphrase > ${bdir}passphrase
  mkfs.ext4 /dev/mapper/${sname}.mounted
}

# Create filesystem with backup maximum size
create_backup_directory () {

  bdir="${SBE_dir}${sname}/"
  [[ -d $bdir ]] && echo "Backup directory exists already" && exit 2

  mkdir -p $bdir
  mkdir ${bdir}.mounted
  touch ${bdir}backups
  fallocate -l $bmaxsize ${bdir}backups
  [[ $encrypted -eq 1 ]] && encrypt_backup_directory || mkfs.ext4 ${bdir}backups

}

# Simply mount backup image
mount_backup_directory () {
  [[ $encrypted -eq 1 ]] && mount /dev/mapper/${sname}.mounted ${bdir}.mounted ||  mount ${bdir}backups ${bdir}.mounted
}

fill_backup_directory () {

  rsync -a ${SBE_dir}tools/server.config    ${bdir}
  rsync -a ${SBE_dir}tools/backup_server.sh ${bdir}

  sed -i 's/!#Host#!/'$sname'/g'          ${bdir}server.config
  sed -i 's/!#IPadress#!/'$sip'/g'        ${bdir}server.config
  sed -i 's/!#Port#!/'$sport'/g'          ${bdir}server.config
  sed -i 's/!#User#!/'$suser'/g'          ${bdir}server.config
  sed -i "s/ENCRYPTED=.*/ENCRYPTED=${encrypted}/g" ${bdir}server.config

}

# MAIN

get_information

show_information
read -p 'Do you want to continue with this settings? (y/N): ' a
[[ $a == [Yy] ]] || exit 1


read -p 'Transfer SSH pub key? (y/N): ' a
if [[ $a == [Yy] ]]; then
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


read -p 'Shall I start the first backup process? (y/N): ' a
if [[ $a == [Yy] ]]; then
  echo "..."
  echo "Starting first backup"
  /bin/bash ${bdir}backup_server.sh &
  echo "You can kill the process with - kill $!"
fi

exit 0
