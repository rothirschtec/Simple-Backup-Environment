#!/usr/bin/env python3

import os
import logging
import subprocess
import time
import random
import string
import hashlib
from pathlib import Path
from typing import Optional, Tuple

# Import our modules
try:
    from lib.key_manager import KeyManager
    from lib.config import ConfigManager
except ImportError:
    from backup.tools.lib.key_manager import KeyManager
    from backup.tools.lib.config import ConfigManager

logger = logging.getLogger(__name__)

class BackupMounter:
    """Handles mounting and unmounting of backup directories"""
    
    def __init__(self, base_dir: Optional[str] = None):
        """Initialize the backup mounter
        
        Args:
            base_dir: Base directory of SBE installation. If None, detect automatically.
        """
        if base_dir:
            self.base_dir = Path(base_dir)
        else:
            # Set base directory to the SBE root (3 levels up from this script)
            self.base_dir = Path(__file__).resolve().parent.parent.parent
        
        self.config = ConfigManager(str(self.base_dir))
        self.key_manager = KeyManager()
    
    def mount_backup_directory(self, server_name: str) -> Tuple[bool, str]:
        """Mount a backup directory
        
        Args:
            server_name: Name of the server (directory name)
            
        Returns:
            Tuple of (success, message)
        """
        # Load server config
        server_config = self.config.load_server_config(server_name)
        if not server_config:
            return False, f"Failed to load configuration for {server_name}"
        
        # Set paths
        server_dir = self.base_dir / "backup" / server_name
        backup_img = server_dir / "backups"
        mount_dir = server_dir / ".mounted"
        
        # Check if already mounted
        if self._is_mounted(mount_dir):
            return True, f"Backup directory for {server_name} is already mounted"
        
        # Create mount directory if it doesn't exist
        mount_dir.mkdir(parents=True, exist_ok=True)
        
        # Check if encrypted
        encrypted = server_config.get("ENCRYPTED", "0") == "1"
        
        if encrypted:
            # Check if LUKS device is already open
            mapper_path = Path(f"/dev/mapper/{server_name}.mounted")
            if mapper_path.exists():
                logger.info(f"LUKS device {mapper_path} is already open")
            else:
                # Get passphrase
                use_keyserver = (server_dir / ".use_keyserver").exists()
                
                if use_keyserver:
                    # Try to get key from key server with fallback
                    success, key_or_error = self.key_manager.get_key_with_fallback(server_name, str(server_dir))
                    if not success:
                        return False, f"Failed to retrieve encryption key: {key_or_error}"
                    passphrase = key_or_error
                else:
                    # Use local passphrase file
                    passphrase_file = server_dir / "passphrase"
                    if not passphrase_file.exists():
                        return False, f"Passphrase file not found at {passphrase_file}"
                    
                    with open(passphrase_file, "r") as f:
                        passphrase = f.read().strip()
                
                # Open LUKS device
                result = self._open_luks_device(str(backup_img), f"{server_name}.mounted", passphrase)
                if not result[0]:
                    return result
            
            # Mount the device
            return self._mount_device(f"/dev/mapper/{server_name}.mounted", str(mount_dir))
        else:
            # Not encrypted, mount directly
            return self._mount_device(str(backup_img), str(mount_dir))
    
    def unmount_backup_directory(self, server_name: str) -> Tuple[bool, str]:
        """Unmount a backup directory
        
        Args:
            server_name: Name of the server (directory name)
            
        Returns:
            Tuple of (success, message)
        """
        # Load server config
        server_config = self.config.load_server_config(server_name)
        if not server_config:
            return False, f"Failed to load configuration for {server_name}"
        
        # Set paths
        server_dir = self.base_dir / "backup" / server_name
        mount_dir = server_dir / ".mounted"
        
        # Check if mounted
        if not self._is_mounted(mount_dir):
            return True, f"Backup directory for {server_name} is not mounted"
        
        # Unmount
        result = self._unmount_device(str(mount_dir))
        if not result[0]:
            return result
        
        # Check if encrypted
        encrypted = server_config.get("ENCRYPTED", "0") == "1"
        
        if encrypted:
            # Close LUKS device
            return self._close_luks_device(f"{server_name}.mounted")
        
        return True, f"Backup directory for {server_name} unmounted successfully"
    
    def initialize_backup_directories(self, server_name: str) -> Tuple[bool, str]:
        """Initialize backup directories after mounting
        
        Args:
            server_name: Name of the server (directory name)
            
        Returns:
            Tuple of (success, message)
        """
        # Set paths
        server_dir = self.base_dir / "backup" / server_name
        mount_dir = server_dir / ".mounted"
        
        # Check if mounted
        if not self._is_mounted(mount_dir):
            return False, f"Backup directory for {server_name} is not mounted"
        
        # Create required directories
        try:
            periods = ["daily", "weekly", "monthly", "yearly", "latest"]
            for period in periods:
                period_dir = mount_dir / period
                period_dir.mkdir(parents=True, exist_ok=True)
            
            return True, f"Backup directories initialized for {server_name}"
        except Exception as e:
            return False, f"Error initializing backup directories: {str(e)}"
    
    def _is_mounted(self, mount_point: Path) -> bool:
        """Check if a directory is a mount point
        
        Args:
            mount_point: Path to check
            
        Returns:
            True if mounted, False otherwise
        """
        try:
            result = subprocess.run(
                ["findmnt", str(mount_point)], 
                capture_output=True, 
                text=True
            )
            return result.returncode == 0
        except Exception as e:
            logger.error(f"Error checking mount status: {str(e)}")
            return False

    def _generate_unique_device_name(self, hostname: str) -> str:
        """Generate a unique mapper name similar to backup.tools.mount"""
        timestamp = int(time.time())
        random_part = ''.join(random.choice(string.ascii_lowercase) for _ in range(6))
        h = hashlib.md5(hostname.encode()).hexdigest()[:4]
        return f"sbe_map_{timestamp}_{random_part}_{h}"
    
    def _open_luks_device(self, device: str, name: str, passphrase: str) -> Tuple[bool, str]:
        """Open a LUKS encrypted device and handle existing mapper names"""
        mapper_path = Path(f"/dev/mapper/{name}")

        def mapper_exists() -> bool:
            if mapper_path.exists():
                return True
            try:
                res = subprocess.run(["dmsetup", "ls"], capture_output=True, text=True)
                if res.returncode == 0:
                    return any(line.split()[0] == name for line in res.stdout.splitlines())
            except Exception:
                pass
            return False

        try:
            if mapper_exists():
                logger.info(f"Mapper {name} already exists, attempting cleanup")
                # Attempt to unmount and close
                subprocess.run(["umount", str(mapper_path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                subprocess.run(["cryptsetup", "luksClose", name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                subprocess.run(["dmsetup", "remove", "-f", name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

                if mapper_exists():
                    logger.warning("Cleanup failed, generating new mapper name")
                    new_name = self._generate_unique_device_name(name)
                    server_dir = Path(device).parent
                    try:
                        with open(server_dir / "device_name", "w") as f:
                            f.write(new_name)
                    except Exception as e:
                        logger.error(f"Failed to write device name: {e}")
                    name = new_name
                    mapper_path = Path(f"/dev/mapper/{name}")

            process = subprocess.Popen([
                "echo", "-n", passphrase
            ], stdout=subprocess.PIPE)

            result = subprocess.run([
                "cryptsetup", "luksOpen", "--type", "luks2", device, name
            ], stdin=process.stdout, capture_output=True, text=True)

            if result.returncode != 0:
                return False, f"Failed to open LUKS device: {result.stderr}"

            return True, f"LUKS device {device} opened as {name}"
        except Exception as e:
            return False, f"Error opening LUKS device: {str(e)}"
    
    def _close_luks_device(self, name: str) -> Tuple[bool, str]:
        """Close a LUKS encrypted device
        
        Args:
            name: Name of the mapped device
            
        Returns:
            Tuple of (success, message)
        """
        try:
            result = subprocess.run(
                ["cryptsetup", "luksClose", name],
                capture_output=True,
                text=True
            )
            
            if result.returncode != 0:
                return False, f"Failed to close LUKS device: {result.stderr}"
            
            return True, f"LUKS device {name} closed"
        except Exception as e:
            return False, f"Error closing LUKS device: {str(e)}"
    
    def _mount_device(self, device: str, mount_point: str) -> Tuple[bool, str]:
        """Mount a device to a directory
        
        Args:
            device: Device to mount
            mount_point: Directory to mount to
            
        Returns:
            Tuple of (success, message)
        """
        try:
            result = subprocess.run(
                ["mount", device, mount_point],
                capture_output=True,
                text=True
            )
            
            if result.returncode != 0:
                return False, f"Failed to mount device: {result.stderr}"
            
            return True, f"Device {device} mounted at {mount_point}"
        except Exception as e:
            return False, f"Error mounting device: {str(e)}"
    
    def _unmount_device(self, mount_point: str) -> Tuple[bool, str]:
        """Unmount a directory
        
        Args:
            mount_point: Directory to unmount
            
        Returns:
            Tuple of (success, message)
        """
        try:
            result = subprocess.run(
                ["umount", mount_point],
                capture_output=True,
                text=True
            )
            
            if result.returncode != 0:
                return False, f"Failed to unmount device: {result.stderr}"
            
            return True, f"Directory {mount_point} unmounted"
        except Exception as e:
            return False, f"Error unmounting device: {str(e)}"
