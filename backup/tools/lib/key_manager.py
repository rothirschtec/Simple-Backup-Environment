#!/usr/bin/env python3

import os
import logging
import json
import requests
from typing import Dict, Optional, Tuple, Any
from pathlib import Path

logger = logging.getLogger(__name__)

class KeyManager:
    """Manages encryption keys for SBE using the key server API"""
    
    def __init__(self, keyserver_host: Optional[str] = None, api_key: Optional[str] = None):
        """Initialize the key manager
        
        Args:
            keyserver_host: URL of the key server
            api_key: API key for authentication
        """
        # Get keyserver host from environment or argument
        self.keyserver_host = keyserver_host or os.environ.get("KEYSERVER_HOST", None)
        
        # Fix environment variable interpolation issues
        if self.keyserver_host and "${" in self.keyserver_host:
            # If we detect an unresolved variable, try to get the domain from environment
            domain = os.environ.get("DOMAIN", "example.com")
            self.keyserver_host = self.keyserver_host.replace("${DOMAIN}", domain)
        
        # If still not set, use default
        if not self.keyserver_host:
            self.keyserver_host = "https://sbe.keyserver.your.domain:8443"
        
        # Get API key
        self.api_key = api_key or os.environ.get("KEYSERVER_API_KEY", "your_api_key_here")
        
        # Strip trailing slash from keyserver_host if present
        if self.keyserver_host.endswith("/"):
            self.keyserver_host = self.keyserver_host[:-1]
            
        logger.info(f"KeyManager initialized with keyserver: {self.keyserver_host}")
    
    def store_encryption_key(self, hostname: str, encryption_key: str) -> Tuple[bool, str]:
        """Store an encryption key in the key server
        
        Args:
            hostname: Hostname identifier for the key
            encryption_key: The encryption key to store
            
        Returns:
            Tuple of (success, message)
        """
        # Validate inputs
        if not hostname or not encryption_key:
            return False, "Hostname and encryption key are required"
        
        # Create JSON payload
        payload = {"hostname": hostname, "key": encryption_key}
        
        try:
            # Send request to key server
            response = requests.post(
                f"{self.keyserver_host}/api/keys",
                headers={
                    "Content-Type": "application/json",
                    "Authorization": f"Bearer {self.api_key}"
                },
                json=payload,
                verify=False  # Set to False for self-signed certs in dev
            )
            
            # Check response
            if response.status_code == 200:
                logger.info(f"Key stored successfully for {hostname}")
                return True, "Key stored successfully"
            else:
                error_msg = f"Error storing key: HTTP {response.status_code}"
                if response.text:
                    error_msg += f" - {response.text}"
                logger.error(error_msg)
                return False, error_msg
                
        except requests.RequestException as e:
            error_msg = f"Error connecting to key server: {str(e)}"
            logger.error(error_msg)
            return False, error_msg
    
    def retrieve_encryption_key(self, hostname: str) -> Tuple[bool, str]:
        """Retrieve an encryption key from the key server
        
        Args:
            hostname: Hostname identifier for the key
            
        Returns:
            Tuple of (success, key_or_error_message)
        """
        # Validate input
        if not hostname:
            return False, "Hostname is required"
        
        try:
            # Send request to key server
            response = requests.get(
                f"{self.keyserver_host}/api/keys/{hostname}",
                headers={"Authorization": f"Bearer {self.api_key}"},
                verify=False  # Set to False for self-signed certs in dev
            )
            
            # Check response
            if response.status_code == 200:
                try:
                    data = response.json()
                    if "key" in data:
                        logger.info(f"Key retrieved successfully for {hostname}")
                        return True, data["key"]
                    else:
                        return False, "Key not found in response"
                except json.JSONDecodeError:
                    return False, "Invalid JSON response from server"
            else:
                error_msg = f"Error retrieving key: HTTP {response.status_code}"
                if response.text:
                    error_msg += f" - {response.text}"
                logger.error(error_msg)
                return False, error_msg
                
        except requests.RequestException as e:
            error_msg = f"Error connecting to key server: {str(e)}"
            logger.error(error_msg)
            return False, error_msg
    
    def delete_encryption_key(self, hostname: str) -> Tuple[bool, str]:
        """Delete an encryption key from the key server
        
        Args:
            hostname: Hostname identifier for the key to delete
            
        Returns:
            Tuple of (success, message)
        """
        # Validate input
        if not hostname:
            return False, "Hostname is required"
        
        try:
            # Send request to key server
            response = requests.delete(
                f"{self.keyserver_host}/api/keys/{hostname}",
                headers={"Authorization": f"Bearer {self.api_key}"},
                verify=False  # Set to False for self-signed certs in dev
            )
            
            # Check response
            if response.status_code == 200:
                logger.info(f"Key deleted successfully for {hostname}")
                return True, "Key deleted successfully"
            else:
                error_msg = f"Error deleting key: HTTP {response.status_code}"
                if response.text:
                    error_msg += f" - {response.text}"
                logger.error(error_msg)
                return False, error_msg
                
        except requests.RequestException as e:
            error_msg = f"Error connecting to key server: {str(e)}"
            logger.error(error_msg)
            return False, error_msg
    
    def check_keyserver_health(self) -> Tuple[bool, str]:
        """Check if the key server is available
        
        Returns:
            Tuple of (success, message)
        """
        try:
            # Log the URL we're about to connect to
            logger.info(f"Checking keyserver health at {self.keyserver_host}/health")
            
            # Send request to key server health endpoint
            response = requests.get(
                f"{self.keyserver_host}/health",
                verify=False,  # Set to False for self-signed certs in dev
                timeout=5     # Add a timeout to avoid hanging
            )
            
            # Check response
            if response.status_code == 200:
                try:
                    data = response.json()
                    if data.get("status") == "healthy":
                        return True, "Key server is healthy"
                    else:
                        return False, f"Key server status: {data.get('status', 'unknown')}"
                except json.JSONDecodeError:
                    return False, "Invalid JSON response from health endpoint"
            else:
                return False, f"Key server health check failed: HTTP {response.status_code}"
                
        except requests.RequestException as e:
            error_msg = f"Error connecting to key server: {str(e)}"
            logger.error(error_msg)
            return False, error_msg
    
    def backup_key_locally(self, hostname: str, key: str, backup_dir: Optional[str] = None) -> Tuple[bool, str]:
        """Backup an encryption key to local file as fallback
        
        Args:
            hostname: Hostname identifier for the key
            key: The encryption key to backup
            backup_dir: Directory to store the backup (default: hostname dir)
            
        Returns:
            Tuple of (success, message)
        """
        try:
            # Determine backup location
            if backup_dir:
                backup_path = Path(backup_dir) / "passphrase.backup"
            else:
                # Assuming standard SBE structure
                base_dir = Path(__file__).resolve().parent.parent.parent.parent
                backup_path = base_dir / "store" / hostname / "passphrase.backup"
            
            # Create parent directories if they don't exist
            backup_path.parent.mkdir(parents=True, exist_ok=True)
            
            # Write key to file
            with open(backup_path, "w") as backup_file:
                backup_file.write(key)
            
            # Create marker file to indicate key server is used
            marker_path = backup_path.parent / ".use_keyserver"
            marker_path.touch()
            
            return True, f"Key backed up to {backup_path}"
            
        except Exception as e:
            error_msg = f"Error backing up key: {str(e)}"
            logger.error(error_msg)
            return False, error_msg
    
    def get_key_with_fallback(self, hostname: str, backup_dir: Optional[str] = None) -> Tuple[bool, str]:
        """Retrieve key with fallback to local backup if key server fails
        
        Args:
            hostname: Hostname identifier for the key
            backup_dir: Directory where backup is stored (default: hostname dir)
            
        Returns:
            Tuple of (success, key_or_error_message)
        """
        # Try key server first
        success, key_or_error = self.retrieve_encryption_key(hostname)
        if success:
            return True, key_or_error
        
        logger.warning(f"Failed to retrieve key from server: {key_or_error}")
        logger.info("Trying local backup...")
        
        # Determine backup location
        if backup_dir:
            backup_path = Path(backup_dir) / "passphrase.backup"
            alt_backup_path = Path(backup_dir) / "passphrase"
        else:
            # Assuming standard SBE structure
            base_dir = Path(__file__).resolve().parent.parent.parent.parent
            backup_path = base_dir / "store" / hostname / "passphrase.backup"
            alt_backup_path = base_dir / "store" / hostname / "passphrase"
        
        # Try backup file
        try:
            if backup_path.exists():
                with open(backup_path, "r") as backup_file:
                    key = backup_file.read().strip()
                return True, key
            elif alt_backup_path.exists():
                with open(alt_backup_path, "r") as backup_file:
                    key = backup_file.read().strip()
                return True, key
            else:
                return False, "Key not found in server or local backup"
        except Exception as e:
            error_msg = f"Error reading backup key: {str(e)}"
            logger.error(error_msg)
            return False, error_msg
