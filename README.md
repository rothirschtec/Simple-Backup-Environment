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
