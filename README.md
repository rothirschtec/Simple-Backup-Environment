# RT-Blog-SBE

## SBE or Simple Backup Environment

A backup solution with *rsync* to take full backups.

### Dependencies
Uses rsync over ssh. So you need to have those service installed on the host and the server. You also need to have a valid user SSH key for the host on the server that is allowed to do a system backup.

### How to use
Start with 

    sudo ./tools/add_host.sh

## Dependencies

- ssh
- rsync

### Optional
- pwgen
- mysql-client or mariadb-client


## qnap
You can use this script on a qnap NAS. Connect to the NAS via SSH. You'll need git installed on the qnap NAS.
Therfore you can install qpkg via the app store to be able to build the entware package.

	cd /share/Public

	# Download the Entware-3x QPKG:
	wget --no-check-certificate "http://entware-3x.zyxmon.org/binaries/other/Entware-3x_0.99std.qpkg"

	# Install Entware via script
	sh Entware-3x_0.99std.qpkg

	# Logout in Login again
	# Check that it updates correctly:
	opkg update
	opkg install git git-http grep
	# If mysql database backups are needed
	opkg install mariadb-client mariadb-client-extra

And don't forget to set your e-mail settings in qnap control panel. *ControlPanel > Notification Center > Service Account and Device Pairing > E-mail > Add SMPT Service*

## Crontab
You can add a crontab to execute the script, here are a few examples:

	crontab -e

	# Each day at 18:00 o'clock
	0 18 * * * /bin/bash <PathToRT-Blog-SBE>/backup_all.sh --daily

	# Every 5 minutes through the day from 08:00 AM to 10:00 PM 
	# The script will only allow one host backup at the time
	# So if you will execute it every 5minutes it'll start again if one job is done
	*/5 8-22 * * * /bin/bash <PathToRT-Blog-SBE>/backup_all.sh --daily

	# Each sunday, you will create a weekly backup *--weekly* and send a mail *--log* to the admin
	0 20 * * 7 /bin/bash <PathToRT-Blog-SBE>/backup_all.sh --weekly --log

## qNap crontab
On a qNap NAS you have to add the cron tasks inside _/etc/config/crontab_ and reload crontab after it

	crontab /etc/config/crontab && /etc/init.d/crond.sh restart
