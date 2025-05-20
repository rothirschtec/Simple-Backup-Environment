# SBE - Simple Backup Environment with Key Server (Python Implementation)

A comprehensive dockerized backup solution for automated remote server backups with
secure key management, now implemented in Python for improved reliability and
maintainability.

## Overview

SBE is a complete backup system consisting of two main components:

1. **Backup Service** - Handles the automated backup of remote servers using SSH/rsync
   with scheduling, encryption, and monitoring
2. **Key Server** - Provides secure storage for encryption keys, separating them from
   the backup storage for enhanced security

This integrated solution offers a balance of security and convenience, with the key
server providing a secure API for encryption key management while maintaining fallback
mechanisms for reliability.

## Features

### Backup Service

- Schedule automated backups with flexible intervals (hourly, daily, weekly, monthly)
- Support for multiple backup strategies (daily, weekly, monthly, latest)
- Backup encryption using LUKS
- SSH/rsync-based secure transfer
- Email notifications for backup success/failure
- Queue management to avoid server overload
- Monitoring and reporting tools
- Support for backup integrity verification

### Key Server

- Secure storage of encryption keys in a PostgreSQL database
- HTTPS API with strong authentication
- Automatic encryption of stored keys
- Redundancy with local backup copies
- Fallback mechanisms for reliability

## Quick Start

1. Clone the repository:

   ```bash
   # Using HTTPS
   git clone https://github.com/rothirschtec/Simple-Backup-Environment.git
   
   # Or using SSH
   git clone git@github.com:rothirschtec/Simple-Backup-Environment.git
   
   cd Simple-Backup-Environment
   ```

2. Copy the example environment file:

   ```bash
   cp .env.example .env
   ```

3. Edit the `.env` file with your settings:

   ```bash
   # Generate strong keys and passwords
   KEYSERVER_API_KEY=$(openssl rand -hex 32)
   POSTGRES_PASSWORD=$(openssl rand -base64 24)
   
   # Update the .env file with these values
   nano .env
   ```

4. Generate SSL certificates for the key server:

   ```bash
   cd keyserver/scripts
   ./generate_certs.sh
   cd ../..
   ```

5. Start the services:

   ```bash
   DOMAIN=your.domain docker compose up -d
   ```

6. Add your first backup host:

   ```bash
   docker exec -it sbe.backup.your.domain bash
   # Now you can use the commands directly
   add_host --encrypted
   ```

## Directory Structure

```
SBE/
├── backup/              # Backup service component (Python)
│   ├── tools/           # Python utility scripts
│   │   ├── lib/         # Shared Python modules
│   │   ├── add_host.py  # Add new host for backup
│   │   ├── mount.py     # Mount/unmount backup directories
│   ├── config/          # Configuration files
│   ├── main.py          # Main scheduler script
│   ├── status.py        # Status reporting script
├── keyserver/           # Key server component (Flask API)
├── docker-compose.yml   # Main Docker Compose file
├── requirements.txt     # Python dependencies
└── docs/                # Documentation
```

## Configuration

SBE now uses YAML for configuration, which is more readable and maintainable than the
previous XML format. The configuration files are located in the `backup/config/` directory.

### Example YAML Configuration

```yaml
# SBE Backup Configuration
servers:
  # Daily backup - runs every day at 1 AM
  - backupdirectory: ServerName
    intervall: "01:00"  # Format: HH:MM
    date: "*"  # * means every day
    type: daily
    retention: 7  # Keep last 7 daily backups
  
  # Weekly backup - runs every Sunday at 2 AM
  - backupdirectory: ServerName
    intervall: "02:00"
    date: Sun  # Day of week
    type: weekly
    retention: 4  # Keep last 4 weekly backups
```

## Command Reference

SBE now provides simple commands that are available in the system PATH. These commands
are wrapper scripts that call the Python scripts with the correct paths.

### Add a New Host

```bash
add_host [--encrypted] [--non-interactive]
```

### Mount/Unmount Backup Volumes

```bash
mount_backup --mount --project ServerName
mount_backup --umount --project ServerName
```

### Check Backup Status

```bash
backup_status [--clean] [--mounts]
```

### Run Backups Immediately

```bash
backup_scheduler --now
```

## For Existing Installations

If you've already deployed SBE and want to install the command wrappers, you can run
the following:

```bash
docker exec -it sbe.backup.your.domain bash -c "curl -s https://raw.githubusercontent.com/rothirschtec/Simple-Backup-Environment/main/install_commands.sh | bash"
```

Or alternatively, you can manually create the wrappers:

```bash
docker exec -it sbe.backup.your.domain bash

# Then run these commands inside the container
cat > /usr/local/bin/add_host << 'EOF'
#!/bin/bash
python3 /opt/SBE/backup/tools/add_host.py "$@"
EOF

chmod +x /usr/local/bin/add_host

# Repeat for other commands
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.
