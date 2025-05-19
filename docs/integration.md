# SBE Integration Guide

This document explains how the Backup Service and Key Server components work together to provide a secure backup solution.

## Architecture Overview

The SBE system consists of three main components:

1. **Backup Service** - Handles the scheduling, execution, and management of backups
2. **Key Server** - Provides secure storage and retrieval of encryption keys
3. **Database** - Stores encrypted keys with their associated hostnames

## Communication Flow

### Creating an Encrypted Backup

1. When a new encrypted backup is created:
   - The `add_host.sh` script generates a secure random passphrase
   - It checks if the Key Server is available by calling the health endpoint
   - If available, it calls the Key Server API to store the passphrase
   - A marker file (`.use_keyserver`) is created to indicate the backup uses the Key Server
   - A local backup copy of the passphrase is also stored for redundancy
   - The backup volume is encrypted using the passphrase

### Retrieving a Key for Decryption

1. When mounting an encrypted backup:
   - The script checks if the `.use_keyserver` marker file exists
   - If it exists, it retrieves the passphrase from the Key Server
   - If the Key Server is unavailable, it falls back to the local backup copy
   - The passphrase is used to decrypt and mount the backup

## Fallback Mechanisms

The system includes several fallback mechanisms to ensure reliability:

1. **Key Server Unavailable**: 
   - When creating a backup, if the Key Server is unavailable, the passphrase is stored locally
   - When mounting a backup, if the Key Server is unavailable, the script attempts to use the local backup copy

2. **Local Backup Copy**:
   - Even when using the Key Server, a local backup copy of the passphrase is maintained
   - This provides redundancy in case the Key Server is temporarily unavailable

3. **Standard Local Passphrase**:
   - If both the Key Server and the backup copy are unavailable, the script attempts to use the standard passphrase file

## Security Considerations

1. **API Key Protection**:
   - The API key is used for authentication between the Backup Service and Key Server
   - It should be kept secure and rotated periodically
   - Environment variables are used to avoid hardcoding the key

2. **Network Isolation**:
   - The Key Server should ideally be placed on a separate, secured network segment
   - Firewall rules should restrict access to only authorized clients

3. **SSL/TLS**:
   - All communication between the Backup Service and Key Server uses HTTPS
   - In production, proper SSL certificates should be used instead of self-signed ones

4. **Key Encryption**:
   - Keys stored in the database are encrypted using a master key derived from the API key
   - This provides an additional layer of protection for stored keys
