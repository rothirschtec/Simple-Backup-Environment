#!/bin/bash
#
# Dependencies:
# - cryptsetup

# Decrypt backup
decrypt_backup_directory () {
  passphrase=$(cat ${sdir}passphrase)
  echo -n "$passphrase" | cryptsetup luksOpen --type luks2 ${sdir}backups ${sname}.mounted
}

# Mount decrypted backup directory
mount_backup_directory () {
  if ! mount | grep "${sdir}.mounted" > /dev/null; then
    if [[ $ENCRYPTED -eq 1 ]]; then
      decrypt_backup_directory
      mount /dev/mapper/${sname}.mounted ${sdir}.mounted
    else
      mount ${sdir}backups ${sdir}.mounted
    fi
  fi
  bmount="${sdir}.mounted/"
}

# Simply unmount backup image
umount_backup_directory () {
  umount ${sdir}.mounted
  if [[ $ENCRYPTED -eq 1 ]]; then
    cryptsetup luksClose ${sname}.mounted
  fi
}
