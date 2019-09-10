# RT-Blog-SBE

## SBE or Simple Backup Environment

A backup solution with *rsync* to take full backups.

### Dependencies
Uses rsync over ssh. So you need to have those service installed on the host and the server. You also need to have a valid user SSH key for the host on the server that is allowed to do a system backup.

### How to use
Start with 

    sudo ./tools/add_host.sh

You have to install the dependencies asked. Better explanations coming soon.
