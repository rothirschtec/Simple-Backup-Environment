# Simple Backup Environment (SBE)

A dockerized backup solution for automated remote server backups via SSH/rsync with scheduling, encryption options, and monitoring.

## Features

- Schedule automated backups with flexible intervals (hourly, daily, weekly, monthly)
- Support for multiple backup strategies (daily, weekly, monthly, latest)
- Backup encryption using LUKS
- SSH/rsync-based secure transfer
- Docker containerization for easy deployment
- Email notifications for backup success/failure
- Queue management to avoid server overload
- Monitoring and reporting tools
- Support for backup integrity verification

## Requirements

- Docker and Docker Compose
- SSH server on remote hosts
- sendmail or compatible MTA (for notifications)
- cryptsetup (for encrypted backups)

## Installation

1. Clone the repository:
   ```
   git clone https://github.com/yourusername/SBE.git
   cd SBE
   ```

2. Copy example configuration files:
   ```
   cp env.example .env
   cp msmtprc.example msmtprc
   ```

3. Configure the environment variables in `.env` file:
   ```
   # Edit the .env file to match your environment
   nano .env
   ```

4. Configure mail settings in `msmtprc` file:
   ```
   nano msmtprc
   ```

5. Build and start the Docker container:
   ```
   docker-compose up -d
   ```

## Configuration

### Environment Variables

Edit the `.env` file to configure:

- `COMPOSE_PROJECT_NAME`: Project name for multiple instances
- `domain`: Domain name for container
- `sshdir`: Path to SSH keys
- `reports`: Directory for backup reports
- `sbdir`: Backup settings directory
- `mail`: Email for notifications
- `grep`: System path to grep
- `sendmail`: System path to sendmail
- `MBAST`: Maximum backups at the same time
- `SUBNET`: Subnet definition for Docker network

### Backup Configuration

Create a `backup.xml` file to define backup jobs:

```xml
<?xml version="1.0"?>
<servers>
    <server>
        <backupdirectory>ServerName</backupdirectory>
        <intervall>5h</intervall>
        <date>Mon</date>
        <type>daily</type>
    </server>
    <server>
        <backupdirectory>AnotherServer</backupdirectory>
        <intervall>15:00</intervall>
        <date>22</date>
        <type>weekly</type>
    </server>
</servers>
```

### Server Configuration

Each server needs a `server.config` file in its directory with settings like:

- Remote server address and credentials
- Backup method
- Inclusion/exclusion patterns
- Rotation settings

## Usage

### Adding a New Host

```bash
cd /opt/SBE
bash SBE_data/tools/add_host.sh
```

For encrypted backups:

```bash
bash SBE_data/tools/add_host.sh --encrypted
```

### Checking Backup Status

```bash
bash SBE_data/status.sh
```

### Manual Backup

To run a backup immediately:

```bash
bash SBE_data/main.sh now
```

### Mounting/Unmounting Backup Directories

```bash
bash SBE_data/tools/mount.sh --mount
# or
bash SBE_data/tools/mount.sh --umount
```

### Backup Integrity Verification

Set up verification codes:

```bash
bash SBE_data/tools/backup_server.sh --set-code
```

## Interval Format

- Hourly: `Xh` (e.g., `5h` for every 5 hours)
- Minutes: `Xm` (e.g., `30m` for every 30 minutes)
- Specific time: `HH:MM` (e.g., `15:00` for 3 PM)

## Date Format

- Day of month: `1-31` (e.g., `15` for the 15th day)
- Day of week: `Mon`, `Tue`, `Wed`, etc.

## Backup Types

- `daily`: Daily rotation based on BDAYS setting
- `weekly`: Weekly rotation based on BWEEKS setting
- `monthly`: Monthly rotation based on BMONTHS setting
- `latest`: Always overwrites the same backup

## File Structure

- `SBE_data/`: Main scripts and tools
  - `main.sh`: Main entry point
  - `status.sh`: Check backup status
  - `tools/`: Support scripts and libraries
    - `add_host.sh`: Add new hosts
    - `backup_server.sh`: Perform backups
    - `checker.sh`: Check backup executions
    - `mount.sh`: Mount/unmount backup directories
    - `lib/`: Library scripts
- `SBE_docker/`: Docker configuration
- `docker-compose.yml`: Docker Compose configuration
- `.env`: Environment variables
- `msmtprc`: Mail transfer configuration

## Security Features

- SSH key-based authentication
- Optional LUKS encryption for backups
- Unique code verification for backup integrity

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Author

Copyright (c) 2019 René Zingerle
