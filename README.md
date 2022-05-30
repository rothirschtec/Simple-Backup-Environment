# RT-Blog-SBE (beta)

***SBE or Simple Backup Environment***
A backup solution using *rsync* to take full backups of Debian/Armbian systems.

This script is meant to run on a *backup server*. From this, any backup will be taken via SSH and rsync from the remote hosts.

## Installation

### Docker

We'd recommend using docker to run SBE because it's the easiest way to configure the whole thing. But in some cases you have to use the local installation. Scroll down to install anything locally.

#### Docker configuration Step-by-Step

- Install docker using docker instructions: https://docs.docker.com/engine/install/
- Copy configuration files and configure them to your needs

```
  cp msmtprc.example msmtprc
  cp env.example .env
  vim msmtprc
  vim .env
  docker-compose build
  docker-compose up -d
```

Work with the container

```
  docker exec -ti sbe.your.domain bash
```


### Install locally

#### Dependencies

Uses rsync over ssh. So you need to have those service installed on the host and the server. You also need to have a valid user SSH key for the host on the server that is allowed to do a system backup. Do send mails we use msmtp but if you have already installed a mail client you shouldn't install this packages.

Use the install list from SBE_docker/Dockerfile do install dependencies you need to your local system.

#### systemd service file

Copy service file to systemd and change location of *ExecStart=/../RT-Blog-SBE/SBE_data/main.sh*

```
  cp SBE_data/tools/sbe.service /etc/systemd/system/sbe.service
  vim SBE_data/tools/sbe.service
  systemctl daemon-reload
  systemctl enable sbe
  systemctl start sbe
```


## Configure backups

### Add a host to backup

You use the add_host.sh script to configure the backups for a host

```
  cd SBE_data
  ./tools/add_host.sh
```

If you want to encrypt your backup location use --encrypted (ALPHA)

```
  ./tools/add_host.sh --encrypted
```

Follow the instructions of the script

### backup.xml

```
  cd SBE_data
  cp tools/backup.xml-example backup.xml
```

You can manage your backup operations with this simple xml file. Configure it as followed:

```
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
```

### intervall

You can use following intervals

- 4h, Use a full hour and add a 'h' to it. *e.g. 4h to make a backup every 4 hours. 10h to make a backup every 10 hours.*
- 40m, Use a full minute and add a 'm' to it. *e.g. 40m to make a backup every 40 minutes.*
- 13:12, Use hours and minutes to create a backup at this time

### date

You can use following dates

- Wed,Thu: Use short names for any week day you want to configure the setup. You can use multiple week days separated by comma.
- 22: Use an exact day of month to do you backup on this day

### type

This option helps you to categorize your backups

- daily: Saves your backup to <backupimage>/daily/
- weekly: Saves your backup to <backupimage>/weekly/
- monthly: Saves your backup to <backupimage>/monthly/
