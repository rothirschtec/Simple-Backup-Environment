# RT-Blog-SBE

## SBE or Simple Backup Environment

A backup solution with *rsync* to take full backups.

### Dependencies
Uses rsync over ssh. So you need to have those service installed on the host and the server. You also need to have a valid user SSH key for the host on the server that is allowed to do a system backup.

### How to use
Start with 

    sudo ./tools/add_host.sh

You have to install the dependencies asked. Better explanations coming soon.

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
	opkg install git git-http
