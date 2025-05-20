# SBE - Simple Backup Environment with Key Server (Python Implementation)

A comprehensive dockerized backup solution for automated remote server backups with
secure key management, implemented in Python for improved reliability and
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
- Support for multiple backup strategies (daily, weekly, monthly, yearly, latest)
- Backup encryption using LUKS
- SSH/rsync-based secure transfer
- Email notifications for backup success/failure
- Queue management to avoid server overload
- Monitoring and reporting tools
- Support for backup integrity verification
- Universal backup script for consistent backup operations

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

   Important settings to configure:
   - `KEYSERVER_HOST`: Must be a valid URL without variable placeholders
   - `DOMAIN`: Used for container naming and networking
   - `KEYSERVER_API_KEY`: Strong random key for authenticating to the key server

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
   add_host
   ```

## Command Reference

SBE provides simple commands that are available in the system PATH. These commands
are wrapper scripts that call the Python scripts with the correct paths.

### Add a New Host

```bash
add_host [--encrypted] [--non-interactive]
```

Adds a new host for backup. In interactive mode, you'll be prompted for:
- Hostname (used as directory name)
- Backup size (e.g., 10G, 1000M)
- SSH connection details
- Whether to encrypt the backup
- Whether to transfer SSH key
- Whether to run an initial backup

### Mount/Unmount Backup Volumes

```bash
mount_backup --mount --project ServerName
mount_backup --umount --project ServerName
```

Mounts or unmounts a backup directory for maintenance or manual operations.

### Check Backup Status

```bash
backup_status [--clean] [--mounts]
```

Displays the status of all configured backups, including running backups and queue.
- `--clean`: Clean up orphaned queue entries
- `--mounts`: Check backup mount status

### Run Backups Immediately

```bash
backup_scheduler --now
```

Triggers all scheduled backups to run immediately, regardless of their normal schedule.

### Run a Backup Manually

```bash
# Using the convenient wrapper
run_backup --server ServerName --daily --retention 7

# The command accepts all the same parameters as the universal script
run_backup --server ServerName --weekly
run_backup --server ServerName --monthly --retention 12
```

## Universal Backup Script

SBE implements a universal backup script approach that centralizes all backup logic, making maintenance and updates easier while ensuring consistent behavior across all hosts.

### How It Works

The system uses a central `backup_server.py` script located in the `backup/tools/` directory that handles all backup operations. When you add a new host with `add_host`, a small wrapper script is created in the host's directory that calls the universal script with the appropriate parameters.

### Command Line Arguments

The universal backup script (accessible via `run_backup`) accepts the following arguments:

- `--server` - (Required) The name of the server/host to back up
- Backup type (one of the following):
  - `--daily` - Run a daily backup
  - `--weekly` - Run a weekly backup
  - `--monthly` - Run a monthly backup
  - `--yearly` - Run a yearly backup
  - `--latest` - Run a latest backup
- `--retention` - (Optional) Number of backups to keep for this type

### Usage Examples

```bash
# Run daily backup for host1
run_backup --server host1 --daily

# Run weekly backup for host2 with a retention of 5 backups
run_backup --server host2 --weekly --retention 5

# Run monthly backup for host3
run_backup --server host3 --monthly
```

### Using Host-Specific Wrappers

Each host directory contains a wrapper script that automatically passes the hostname parameter:

```bash
# Using the wrapper for host1
/opt/SBE/backup/host1/backup_server.py --daily

# With retention
/opt/SBE/backup/host1/backup_server.py --weekly --retention 4
```

### Benefits of the Universal Script

1. **Centralized Logic**: All backup logic is maintained in one place
2. **Consistency**: Every backup uses the same code, ensuring consistent results
3. **Easier Maintenance**: Only one script to update when making changes
4. **Simplified Troubleshooting**: Issues can be fixed in one location
5. **Reduced Duplication**: No duplicate scripts for each host

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
  
  # Monthly backup - runs on the 1st of each month at 3 AM
  - backupdirectory: ServerName
    intervall: "03:00"
    date: "1"  # Day of month (1-31)
    type: monthly
    retention: 12  # Keep last 12 monthly backups
```

## Directory Structure

```
SBE/
├── backup/              # Backup service component (Python)
│   ├── tools/           # Python utility scripts
│   │   ├── lib/         # Shared Python modules
│   │   ├── add_host.py  # Add new host for backup
│   │   ├── mount.py     # Mount/unmount backup directories
│   │   ├── backup_server.py # Universal backup script
│   ├── config/          # Configuration files
│   ├── main.py          # Main scheduler script
│   ├── status.py        # Status reporting script
├── keyserver/           # Key server component (Flask API)
├── docker-compose.yml   # Main Docker Compose file
├── requirements.txt     # Python dependencies
└── docs/                # Documentation
```

## Troubleshooting

### Device Mapper Conflicts

SBE uses LUKS encryption for backups, which relies on the Linux device mapper. If you encounter issues with device mapper entries already existing, try these steps:

1. List all device mapper entries:
   ```bash
   dmsetup ls
   ```

2. Remove conflicting entries:
   ```bash
   dmsetup remove -f device_name
   ```

3. If device is busy and cannot be removed:
   ```bash
   # Check what's using the device
   lsof | grep device_name
   
   # Force unmount if mounted
   umount -f /dev/mapper/device_name
   
   # Try closing with cryptsetup
   cryptsetup close device_name
   ```

4. For persistent issues, restart the container:
   ```bash
   docker restart sbe.backup.your.domain
   ```

5. Use a different hostname when adding a new host to avoid conflicts with existing device names.

### Keyserver Connection Issues

If the keyserver is not connecting properly:

1. Check the `.env` file to ensure the `KEYSERVER_HOST` is correctly configured:
   ```bash
   nano /opt/SBE/.env
   # Make sure KEYSERVER_HOST does not contain ${DOMAIN} or other variables
   ```

2. Test connectivity to the keyserver:
   ```bash
   curl -vk https://sbe.keyserver.your.domain:8443/health
   ```

3. Ensure the keyserver container is running:
   ```bash
   docker ps | grep keyserver
   ```

4. Check keyserver logs:
   ```bash
   docker logs sbe.keyserver.your.domain
   ```

### SSL Certificate Issues

If you encounter SSL certificate verification issues:

1. The keyserver uses self-signed certificates by default. In the `key_manager.py` file, SSL verification is disabled (`verify=False`) for self-signed certificates.

2. If you want to use proper certificates:
   - Replace the self-signed certificates in `keyserver/config/certs/` with valid ones
   - Update the `key_manager.py` file to use `verify=True`

### Backup Script Not Found

If you get "Backup script not found" errors:

1. Check if the universal backup script exists:
   ```bash
   ls -la /opt/SBE/backup/tools/backup_server.py
   ```

2. If missing, create it using the provided templates in this repository.

3. Make sure the wrapper script for the host is correctly created:
   ```bash
   # For a host named "server1"
   cat /opt/SBE/backup/server1/backup_server.py
   ```

## For Existing Installations

### Upgrading to Universal Backup Script

If you have an existing installation and want to upgrade to the universal backup script approach:

1. First, copy the universal backup script:
   ```bash
   docker exec -it sbe.backup.your.domain bash
   
   # Create the universal backup script
   curl -s https://raw.githubusercontent.com/rothirschtec/Simple-Backup-Environment/main/backup/tools/backup_server.py > /opt/SBE/backup/tools/backup_server.py
   chmod +x /opt/SBE/backup/tools/backup_server.py
   ```

2. Create wrapper scripts for each existing host:
   ```bash
   # For each host, e.g., "server1"
   cat > /opt/SBE/backup/server1/backup_server.py << 'EOF'
   #!/bin/bash
   python3 /opt/SBE/backup/tools/backup_server.py --server server1 "$@"
   EOF
   chmod +x /opt/SBE/backup/server1/backup_server.py
   ```

3. Add the `run_backup` command:
   ```bash
   cat > /usr/local/bin/run_backup << 'EOF'
   #!/bin/bash
   python3 /opt/SBE/backup/tools/backup_server.py "$@"
   EOF
   chmod +x /usr/local/bin/run_backup
   ```

### Installing Command Wrappers

If you've already deployed SBE and want to install the command wrappers, you can run:

```bash
docker exec -it sbe.backup.your.domain bash -c "curl -s https://raw.githubusercontent.com/rothirschtec/Simple-Backup-Environment/main/install_commands.sh | bash"
```

Or manually create the wrappers:

```bash
docker exec -it sbe.backup.your.domain bash

# Then run these commands inside the container
cat > /usr/local/bin/add_host << 'EOF'
#!/bin/bash
python3 /opt/SBE/backup/tools/add_host.py "$@"
EOF

chmod +x /usr/local/bin/add_host

# Repeat for other commands including run_backup
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.
