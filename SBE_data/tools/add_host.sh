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
# Non-interactive mode flag
non_interactive=0

# Parse command line arguments for non-interactive mode
if [ "$1" == "--non-interactive" ]; then
  non_interactive=1
  shift
  if [ $# -ge 5 ]; then
    sname="$1"
    bmaxsize="$2"
    suser="$3"
    sip="$4"
    sport="$5"
    # Additional args can be processed as needed
  else
    echo "Non-interactive mode requires at least 5 arguments:"
    echo "Usage: $0 --non-interactive [name] [size] [user] [server] [port] [--encrypted]"
    exit 1
  fi
  if [[ "$6" == "--encrypted" ]]; then
    encrypted=1
  else
    encrypted=0
  fi
else
  [[ "$@" =~ "--encrypted" ]] && encrypted=1 ||  encrypted=0
fi

get_information () {
  if [ $non_interactive -eq 0 ]; then
    read -p "HostName (used as backup directory name): " sname
    read -p "Backup max size (Format: 1000M or 1G): " bmaxsize
    read -p "User: " suser
    read -p "Server IP Adress: " sip
    read -p "Server Port: " sport
  fi
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
  if [ $non_interactive -eq 0 ]; then
    echo
    echo 'Change the /etc/ssh/sshd_config on your remote host'
    echo ' - PermitRootLogin yes'
    echo ' - PasswordAuthentication yes'
    echo 'And restart the ssh service afterwards "service ssh restart"'
    read -p 'Approve if done [Enter]'
    echo ''
  fi
}

# Transfer SSH publick key
transfer_public_key () {
  scp -P $sport ~/.ssh/id_rsa.pub $suser@${sip}:~/.ssh/authorized_keys
}

# Inform user how to secure ssh on the remote server
close_ssh () {
  if [ $non_interactive -eq 0 ]; then
    echo
    echo 'Change the /etc/ssh/sshd_config back to secure'
    echo ' - PermitRootLogin prohibit-password'
    echo ' - PasswordAuthentication no'
    echo 'And restart the ssh service again "service ssh restart"'
    read -p 'Approve if done [Enter]'
  fi
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
  
  # Handle existing directory
  if [[ -d $bdir ]]; then
    echo "Backup directory exists already"
    if [ $non_interactive -eq 1 ]; then
      # In non-interactive mode, update the configuration
      echo "Updating configuration for existing backup directory"
      return 0
    else
      exit 2
    fi
  fi

  mkdir -p $bdir
  mkdir -p ${bdir}.mounted
  touch ${bdir}backups
  fallocate -l $bmaxsize ${bdir}backups
  [[ $encrypted -eq 1 ]] && encrypt_backup_directory || mkfs.ext4 ${bdir}backups
}

# Simply mount backup image
mount_backup_directory () {
  # Check if already mounted
  if mount | grep "${bdir}.mounted" > /dev/null; then
    echo "Backup directory is already mounted"
    return 0
  fi

  if [[ $encrypted -eq 1 ]]; then
    # Check if already opened
    if [ -e "/dev/mapper/${sname}.mounted" ]; then
      echo "LUKS device is already open"
    else
      if [ -f "${bdir}passphrase" ]; then
        passphrase=$(cat ${bdir}passphrase)
        echo -n "$passphrase" | cryptsetup luksOpen --type luks2 ${bdir}backups ${sname}.mounted
      else
        echo "Error: Passphrase file not found"
        return 1
      fi
    fi
    mount /dev/mapper/${sname}.mounted ${bdir}.mounted
  else
    mount ${bdir}backups ${bdir}.mounted
  fi

  # Create required directories
  mkdir -p ${bdir}.mounted/daily
  mkdir -p ${bdir}.mounted/weekly
  mkdir -p ${bdir}.mounted/monthly
  mkdir -p ${bdir}.mounted/yearly
  mkdir -p ${bdir}.mounted/latest
}

fill_backup_directory () {
  # Only copy if files don't exist or are different
  if [ ! -f "${bdir}server.config" ]; then
    cp ${SBE_dir}tools/server.config ${bdir}
  fi
  
  if [ ! -f "${bdir}backup_server.sh" ]; then
    cp ${SBE_dir}tools/backup_server.sh ${bdir}
  fi

  # Always update configuration
  sed -i 's/!#Host#!/'$sname'/g' ${bdir}server.config
  sed -i 's/!#IPadress#!/'$sip'/g' ${bdir}server.config
  sed -i 's/!#Port#!/'$sport'/g' ${bdir}server.config
  sed -i 's/!#User#!/'$suser'/g' ${bdir}server.config
  sed -i "s/ENCRYPTED=.*/ENCRYPTED=${encrypted}/g" ${bdir}server.config
}

# MAIN

get_information

show_information
if [ $non_interactive -eq 0 ]; then
  read -p 'Do you want to continue with this settings? (y/N): ' a
  [[ $a == [Yy] ]] || exit 1
fi

if [ $non_interactive -eq 0 ]; then
  read -p 'Transfer SSH pub key? (y/N): ' a
  if [[ $a == [Yy] ]]; then
    open_ssh
    transfer_public_key
    close_ssh
  fi
elif [ "$7" == "--transfer-key" ]; then
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

if [ $non_interactive -eq 0 ]; then
  read -p 'Shall I start the first backup process? (y/N): ' a
  if [[ $a == [Yy] ]]; then
    echo "..."
    echo "Starting first backup"
    /bin/bash ${bdir}backup_server.sh &
    echo "You can kill the process with - kill $!"
  fi
elif [ "$8" == "--run-backup" ]; then
  echo "..."
  echo "Starting first backup"
  /bin/bash ${bdir}backup_server.sh &
  echo "You can kill the process with - kill $!"
fi

exit 0
