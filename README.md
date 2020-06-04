# RT-Blog-SBE (alpha)

***SBE or Simple Backup Environment***
A backup solution using *rsync* to take full backups of Debian/Armbian systems.

## Dependencies
Uses rsync over ssh. So you need to have those service installed on the host and the server. You also need to have a valid user SSH key for the host on the server that is allowed to do a system backup.

- ssh
- rsync

### Optional
- pwgen
- mysql-client or mariadb-client


## backup.xml

    cp tools/backup.xml-example backup.xml

You can manage your backup operations with this simple xml file. Configure it as followed:

    <server>
        <backupdirectory>backup directory name</backupdirectory>
        <intervall>4h</intervall>
        <date>Fri</date>
        <type>daily</type>
    </server>
    <server>
        <backupdirectory>backup directory name</backupdirectory>
        <intervall>03:15</intervall>
        <date>Wed,Thu,Fri</date>
    ...

### <backupdirectory>
This is the directory name created with ´./tools/add_host.sh´ script.

### <intervall>
You can use following intervals

- 4h, Use a full hour and add a h to it. *e.g. 4h to make a backup every 4 hours. 10 to make a backup every 10 hours.*
- 40m, Use a minutes and add a h to it. *e.g. 40m to make a backup every 40 minutes.*
- 13:12, Use exact time to create a backup on this time

### <date>
You can use following intervals

- Wed,Thu: Use short names for any week day you want to configure the setup. You can use multiple week days separated by comma.
- 22: Use an exact day of month to do you backup on this day

### <type>
This option helps you to categorize your backups

- daily: Saves your backup to <backupdirectory>rotate_bak/daily/
- weekly: Saves your backup to <backupdirectory>rotate_bak/weekly/
- monthly: Saves your backup to <backupdirectory>rotate_bak/monthly/

## How to use
Start with 

    sudo ./tools/add_host.sh

## Crontab
You can add a crontab to execute the script:

	crontab -e

	# SBE backup each minute
	*/1 * * * * bash <PathToRT-Blog-SBE>/backup_all.sh
	# SBE checker
	0 6 * * * bash <PathToRT-Blog-SBE>/tools/checker.sh


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

## qNap crontab

On a qNap NAS you have to add the cron tasks inside _/etc/config/crontab_ and reload crontab after it

	crontab /etc/config/crontab && /etc/init.d/crond.sh restart
