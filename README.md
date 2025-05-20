# SBE - Simple Backup Environment (Python Implementation)

**NOTICE: This repository has been migrated from shell scripts to Python for improved maintainability and functionality.**

# SBE - Simple Backup Environment with Key Server

A comprehensive dockerized backup solution for automated remote server backups with secure key management.

## Overview

SBE is a complete backup system consisting of two main components:

1. **Backup Service** - Handles the automated backup of remote servers using SSH/rsync with scheduling, encryption, and monitoring
2. **Key Server** - Provides secure storage for encryption keys, separating them from the backup storage for enhanced security

This integrated solution offers a balance of security and convenience, with the key server providing a secure API for encryption key management while maintaining fallback mechanisms for reliability.

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
   ```
   git clone https://github.com/yourusername/SBE.git
   cd SBE
   ```

2. Copy the example environment file:
   ```
   cp .env.example .env
   ```

3. Edit the `.env` file with your settings:
   ```
   # Generate strong keys and passwords
   KEYSERVER_API_KEY=$(openssl rand -hex 32)
   POSTGRES_PASSWORD=$(openssl rand -base64 24)
   
   # Update the .env file with these values
   nano .env
   ```

4. Generate SSL certificates for the key server:
   ```
   cd keyserver/scripts
   ./generate_certs.sh
   cd ../..
   ```

5. Start the services:
   ```
   docker-compose up -d
   ```

6. Add your first backup host:
   ```
   docker exec -it sbe.backup.your.domain bash
   cd /opt/SBE
   bash ./tools/add_host.sh --encrypted
   ```

## Directory Structure

```
SBE/
├── backup/           # Backup service component
├── keyserver/        # Key server component
├── docker-compose.yml # Main Docker Compose file
└── docs/             # Documentation
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Python Implementation

This repository has been updated from shell scripts to Python for better:

- Code structure and maintainability
- Error handling
- Configuration management (YAML instead of XML)
- Cross-platform compatibility
- Type safety (with type hints)

The Python implementation maintains full compatibility with the original shell-based version, while adding improved reliability and extension points.

### Requirements

- Python 3.7 or higher
- Required Python packages (see requirements.txt)
- Same system tools as the original (rsync, cryptsetup, etc.)

### Using Python Scripts

All commands work the same way as before, but use the .py extension instead of .sh:

```bash
# Add a new host
python3 backup/tools/add_host.py

# Mount a backup directory
python3 backup/tools/mount.py --mount --project ServerName

# Check status
python3 backup/status.py
```

You can still use the original shell scripts during the transition period as they have been preserved with .bak extensions.
