#!/usr/bin/env python3

import os
import sys
import logging
import argparse
import secrets
import subprocess
import hashlib
from pathlib import Path
from typing import Dict, Any, Optional, Tuple

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Import our modules
try:
    from lib.key_manager import KeyManager
    from lib.config import ConfigManager
    from lib.mount import BackupMounter
except ImportError:
    try:
        from backup.tools.lib.key_manager import KeyManager
        from backup.tools.lib.config import ConfigManager
        from backup.tools.lib.mount import BackupMounter
    except ImportError:
        logger.error("Could not import required modules. Make sure you're running this script from the correct directory.")
        sys.exit(1)

def check_and_clean_existing_device(name: str) -> bool:
    """
    Check if a LUKS device already exists and try to clean it up
    
    Args:
        name: Device name
        
    Returns:
        True if device was cleaned or doesn't exist, False if couldn't clean
    """
    device_path = f"/dev/mapper/{name}"
    
    # Check if device exists
    if os.path.exists(device_path):
        logger.info(f"LUKS device {name} already exists, attempting to clean up")
        
        # Try to get info about the device
        try:
            result = subprocess.run(
                ["dmsetup", "info", name],
                capture_output=True,
                text=True
            )
            logger.info(f"Device info: {result.stdout}")
        except Exception as e:
            logger.warning(f"Failed to get device info: {str(e)}")
        
        # Try to close the device
        try:
            # First see if it's mounted
            result = subprocess.run(
                ["findmnt", device_path],
                capture_output=True,
                text=True
            )
            
            if result.returncode == 0:
                # It's mounted, try to unmount
                logger.info("Device is mounted, attempting to unmount")
                umount_result = subprocess.run(
                    ["umount", device_path],
                    capture_output=True,
                    text=True
                )
                if umount_result.returncode != 0:
                    logger.error(f"Failed to unmount device: {umount_result.stderr}")
            
            # Now try to close the LUKS container
            close_result = subprocess.run(
                ["cryptsetup", "luksClose", name],
                capture_output=True,
                text=True
            )
            
            if close_result.returncode != 0:
                logger.error(f"Failed to close LUKS device: {close_result.stderr}")
                
                # Try with dmsetup
                logger.info("Trying dmsetup to remove device")
                dmsetup_result = subprocess.run(
                    ["dmsetup", "remove", name],
                    capture_output=True,
                    text=True
                )
                
                if dmsetup_result.returncode != 0:
                    logger.error(f"Failed to remove device with dmsetup: {dmsetup_result.stderr}")
                    
                    # Final attempt with force flag
                    force_result = subprocess.run(
                        ["dmsetup", "remove", "-f", name],
                        capture_output=True,
                        text=True
                    )
                    
                    if force_result.returncode != 0:
                        logger.error(f"Failed to force remove device: {force_result.stderr}")
                        print("\nERROR: Unable to clean up existing LUKS device.")
                        print(f"The device '{name}' already exists and could not be removed.")
                        print("This is likely because it's still in use by another process.")
                        print("\nPossible solutions:")
                        print("1. Try a different hostname")
                        print("2. Reboot the container to release all device mappings")
                        print("3. Check for any processes using the device: 'lsof | grep mapper'")
                        return False
            
            logger.info("Successfully cleaned up existing LUKS device")
            return True
            
        except Exception as e:
            logger.error(f"Error cleaning up device: {str(e)}")
            return False
    
    # Device doesn't exist, no cleanup needed
    return True

def generate_unique_device_name(hostname: str) -> str:
    """
    Generate a unique device name that won't conflict with existing mapper entries
    
    Args:
        hostname: Original hostname
        
    Returns:
        Unique device name
    """
    # Create a hash of the hostname to ensure uniqueness
    h = hashlib.md5(hostname.encode()).hexdigest()[:8]
    
    # Use a prefix that's unlikely to conflict with other device mapper entries
    return f"sbe_{h}_mapper"

class HostManager:
    """Manages server hosts for SBE backups"""
    
    def __init__(self, base_dir: Optional[str] = None):
        """Initialize the host manager
        
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
        self.mounter = BackupMounter(str(self.base_dir))
    
    def add_host(self, 
                hostname: str, 
                max_size: str,
                ssh_user: str,
                server_ip: str,
                ssh_port: str,
                encrypted: bool = False,
                transfer_key: bool = False,
                run_backup: bool = False) -> Tuple[bool, str]:
        """Add a new host for backup
        
        Args:
            hostname: Name to use for the host (will be directory name)
            max_size: Maximum size of backup (format: 1000M or 1G)
            ssh_user: SSH username for remote server
            server_ip: IP address of remote server
            ssh_port: SSH port for remote server
            encrypted: Whether to encrypt the backup
            transfer_key: Whether to transfer SSH public key
            run_backup: Whether to run an initial backup
            
        Returns:
            Tuple of (success, message)
        """
        # Set paths
        backup_dir = self.base_dir / "backup" / hostname
        mounted_dir = backup_dir / ".mounted"
        backup_img = backup_dir / "backups"
        
        # Generate a unique device name to avoid conflicts
        device_name = generate_unique_device_name(hostname)
        
        # Start fresh - if directory exists, completely remove it
        if backup_dir.exists():
            logger.info(f"Removing existing backup directory for {hostname} to ensure clean state")
            try:
                # First make sure nothing is mounted
                if self._is_mounted(mounted_dir):
                    logger.info(f"Unmounting {mounted_dir}")
                    subprocess.run(["umount", str(mounted_dir)], capture_output=True)
                
                # If encrypted, make sure the mapper device is closed
                if os.path.exists(f"/dev/mapper/{device_name}"):
                    logger.info(f"Closing LUKS device {device_name}")
                    subprocess.run(["cryptsetup", "luksClose", device_name], capture_output=True)
                    
                    # If still exists, try force removing
                    if os.path.exists(f"/dev/mapper/{device_name}"):
                        logger.info("Using dmsetup to force remove")
                        subprocess.run(["dmsetup", "remove", "-f", device_name], capture_output=True)
                
                # Now remove the directory
                import shutil
                shutil.rmtree(backup_dir)
                logger.info(f"Successfully removed {backup_dir}")
            except Exception as e:
                logger.error(f"Error cleaning up existing directory: {e}")
                # Continue anyway, we'll try to work with what we have
        
        # Create backup directory fresh
        backup_dir.mkdir(parents=True, exist_ok=True)
        mounted_dir.mkdir(parents=True, exist_ok=True)
        
        # Create backup image file
        try:
            logger.info(f"Creating backup image of size {max_size}")
            result = subprocess.run(
                ["fallocate", "-l", max_size, str(backup_img)],
                capture_output=True,
                text=True
            )
            
            if result.returncode != 0:
                return False, f"Failed to create backup image: {result.stderr}"
        except Exception as e:
            return False, f"Error creating backup image: {str(e)}"
        
        # If encrypted, set up LUKS encryption
        if encrypted:
            passphrase = self._generate_passphrase()
            logger.info("Encrypting backup image")
            
            success, message = self._encrypt_backup_image(str(backup_img), passphrase, device_name)
            if not success:
                return False, message

            # Store passphrase both locally and in key server
            with open(backup_dir / "passphrase", "w") as f:
                f.write(passphrase)

            # Determine final device name (it may have been changed)
            device_name_file = backup_dir / "device_name"
            if device_name_file.exists():
                with open(device_name_file, "r") as f:
                    device_name = f.read().strip()
            else:
                with open(device_name_file, "w") as f:
                    f.write(device_name)
            
            # Always try to store in key server first
            logger.info("Attempting to store encryption key in key server")
            health_ok, health_msg = self.key_manager.check_keyserver_health()
            if health_ok:
                success, message = self.key_manager.store_encryption_key(hostname, passphrase)
                if success:
                    # Mark that this host uses the key server
                    (backup_dir / ".use_keyserver").touch()
                    logger.info("Key stored in key server and marked for keyserver use")
                    
                    # Backup locally as fallback
                    self.key_manager.backup_key_locally(hostname, passphrase, str(backup_dir))
                    logger.info("Key backed up locally as fallback")
                else:
                    logger.warning(f"Key server unavailable: {message}")
                    logger.info("Using local passphrase file only")
            else:
                logger.warning(f"Key server health check failed: {health_msg}")
                logger.info("Using local passphrase file only")
            
            # Format the device
            result = subprocess.run(
                ["mkfs.ext4", f"/dev/mapper/{device_name}"],
                capture_output=True,
                text=True
            )
            
            if result.returncode != 0:
                return False, f"Failed to format encrypted device: {result.stderr}"
            
            # Close the device for now
            self.mounter._close_luks_device(device_name)
        else:
            # Format as ext4 directly
            result = subprocess.run(
                ["mkfs.ext4", str(backup_img)],
                capture_output=True,
                text=True
            )
            
            if result.returncode != 0:
                return False, f"Failed to format backup image: {result.stderr}"
        
        # Prepare server configuration
        server_config = {
            "SERVER": server_ip,
            "PORT": ssh_port,
            "USER": ssh_user,
            "ENCRYPTED": "1" if encrypted else "0",
            "SHARE": "",  # Default share path (will be set by user)
            "BACKUP": "1",  # Enable backup by default
            "BDAYS": "7",  # Default retention: 7 days
            "BWEEKS": "4",  # Default retention: 4 weeks
            "BMONTHS": "12",  # Default retention: 12 months
            "BYEARS": "5",  # Default retention: 5 years
            "MBAST": "2",  # Default max simultaneous backups
        }
        
        # Store the device name in the config if encrypted
        if encrypted:
            server_config["DEVICE_NAME"] = device_name
        
        # Save server configuration
        success = self.config.save_server_config(hostname, server_config)
        if not success:
            return False, "Failed to save server configuration"
        
        # Copy backup script to server directory
        self._copy_backup_script(hostname)
        
        # Transfer SSH public key if requested
        if transfer_key:
            success, message = self._transfer_ssh_key(ssh_user, server_ip, ssh_port)
            if not success:
                return False, message
        
        # Mount backup directory
        success, message = self.mounter.mount_backup_directory(hostname)
        if success:
            self.mounter.initialize_backup_directories(hostname)
        else:
            return False, f"Failed to mount backup directory: {message}"
        
        # Run initial backup if requested
        if run_backup:
            logger.info("Starting initial backup")
            try:
                # First check for the Python version, then fall back to shell
                backup_py = backup_dir / "backup_server.py"
                backup_sh = backup_dir / "backup_server.sh"
                
                if backup_py.exists():
                    subprocess.Popen(
                        ["python3", str(backup_py)],
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE
                    )
                    logger.info("Python backup script started in background")
                elif backup_sh.exists():
                    subprocess.Popen(
                        ["bash", str(backup_sh)],
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE
                    )
                    logger.info("Shell backup script started in background")
                else:
                    logger.warning("Could not find backup script to run")
            except Exception as e:
                logger.error(f"Failed to start backup: {str(e)}")
        
        return True, f"Host {hostname} added successfully"

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
    
    def _generate_passphrase(self) -> str:
        """Generate a secure random passphrase
        
        Returns:
            Secure random passphrase
        """
        try:
            # Try to use pwgen if available
            result = subprocess.run(
                ["pwgen", "-s", "16", "1"], 
                capture_output=True,
                text=True
            )
            
            if result.returncode == 0:
                return result.stdout.strip()
        except:
            pass
        
        # Fallback to secrets module
        return secrets.token_hex(16)
    
    def _encrypt_backup_image(self, image_path: str, passphrase: str, device_name: str) -> Tuple[bool, str]:
        """Encrypt a backup image using LUKS with robust error handling
        
        Args:
            image_path: Path to backup image
            passphrase: Encryption passphrase
            device_name: Name to use for mapped device
            
        Returns:
            Tuple of (success, message)
        """
        # First check if the device already exists and forcibly remove it
        mapper_path = f"/dev/mapper/{device_name}"

        # Always try to forcibly clean up any existing device first
        if os.path.exists(mapper_path):
            logger.info(f"Removing existing device: {mapper_path}")

            try:
                subprocess.run(["umount", mapper_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                subprocess.run(["cryptsetup", "luksClose", device_name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                subprocess.run(["dmsetup", "remove", "-f", device_name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except Exception:
                pass

        if os.path.exists(mapper_path):
            return False, "Cannot create LUKS device - all attempts failed. Try rebooting the container."
        
        try:
            # Format with LUKS - be more explicit about parameters to avoid prompts
            logger.info(f"Formatting {image_path} with LUKS")
            format_cmd = [
                "cryptsetup", 
                "-q",  # Quiet mode, no questions
                "-y",  # Verify passphrase
                "--type", "luks2", 
                "--batch-mode",  # For non-interactive use
                "luksFormat", 
                image_path
            ]
            
            # Use a proper pipe for the passphrase
            format_process = subprocess.Popen(format_cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            format_stdout, format_stderr = format_process.communicate(input=passphrase.encode())
            
            if format_process.returncode != 0:
                return False, f"Failed to format with LUKS: {format_stderr.decode()}"
            
            # Open with LUKS using the BackupMounter helper
            success, msg = self.mounter._open_luks_device(image_path, device_name, passphrase)
            if not success:
                return False, msg

            return True, "Backup image encrypted successfully"
            
        except Exception as e:
            error_msg = str(e)
            logger.error(f"Error during LUKS encryption: {error_msg}")
            return False, f"Error encrypting backup image: {error_msg}"
        
    def _copy_backup_script(self, hostname: str) -> bool:
        """Create a symbolic link to the universal backup script
        
        Args:
            hostname: Host to setup backup script for
            
        Returns:
            True if successful, False otherwise
        """
        try:
            # Use universal backup script in the tools directory
            universal_script = self.base_dir / "backup" / "tools" / "backup_server.py"
            
            # Create command wrapper script
            wrapper_script = self.base_dir / "backup" / hostname / "backup_server.py"
            
            # Create the wrapper script content
            wrapper_content = f'''#!/bin/bash
# Wrapper script for universal backup_server.py
# Auto-generated, do not edit

python3 {universal_script} --server {hostname} "$@"
'''
            
            # Write the wrapper script
            os.makedirs(os.path.dirname(wrapper_script), exist_ok=True)
            with open(wrapper_script, "w") as f:
                f.write(wrapper_content)
            
            # Make it executable
            os.chmod(wrapper_script, 0o755)
            
            logger.info(f"Created backup script wrapper for {hostname}")
            return True
        except Exception as e:
            logger.error(f"Error creating backup script wrapper: {str(e)}")
            return False
    
    def _transfer_ssh_key(self, user: str, server: str, port: str) -> Tuple[bool, str]:
        """Transfer SSH public key to remote server
        
        Args:
            user: SSH username
            server: Server IP or hostname
            port: SSH port
            
        Returns:
            Tuple of (success, message)
        """
        try:
            print("Transferring SSH public key...")
            print("Note: You may need to enter the SSH password.")
            
            result = subprocess.run(
                ["ssh-copy-id", "-i", "~/.ssh/id_rsa.pub", "-p", port, f"{user}@{server}"],
                capture_output=False,  # Let user interact with the process
                text=True
            )
            
            if result.returncode != 0:
                return False, "Failed to transfer SSH key"
            
            return True, "SSH key transferred successfully"
        except Exception as e:
            return False, f"Error transferring SSH key: {str(e)}"

# Interactive mode for getting information
def get_host_information() -> Dict[str, Any]:
    """Interactively prompt for host information
    
    Returns:
        Dict with host information
    """
    info = {}
    
    print("\nAdding a new host to SBE")
    print("------------------------")
    
    info["hostname"] = input("Hostname (used as backup directory name): ")
    info["max_size"] = input("Backup max size (Format: 1000M or 1G): ")
    info["ssh_user"] = input("User: ")
    info["server_ip"] = input("Server IP Address: ")
    info["ssh_port"] = input("Server Port: ")
    
    encrypted = input("Encrypt backup? (y/N): ").lower()
    info["encrypted"] = encrypted.startswith("y")
    
    transfer_key = input("Transfer SSH public key? (y/N): ").lower()
    info["transfer_key"] = transfer_key.startswith("y")
    
    run_backup = input("Start initial backup after setup? (y/N): ").lower()
    info["run_backup"] = run_backup.startswith("y")
    
    # Show summary
    print("\nSummary:")
    print(f"Hostname: {info['hostname']}")
    print(f"Backup size: {info['max_size']}")
    print(f"SSH connection: {info['ssh_user']}@{info['server_ip']}:{info['ssh_port']}")
    print(f"Encrypted: {'Yes' if info['encrypted'] else 'No'}")
    print(f"Transfer SSH key: {'Yes' if info['transfer_key'] else 'No'}")
    print(f"Run initial backup: {'Yes' if info['run_backup'] else 'No'}")
    
    confirm = input("\nContinue with these settings? (y/N): ").lower()
    if not confirm.startswith("y"):
        return get_host_information()
    
    return info

# Command-line interface
if __name__ == "__main__":
    # Parse arguments
    parser = argparse.ArgumentParser(description="Add a host for backup")
    parser.add_argument("--non-interactive", action="store_true", help="Use command-line arguments instead of prompts")
    parser.add_argument("--hostname", help="Hostname (used as backup directory name)")
    parser.add_argument("--max-size", help="Backup max size (Format: 1000M or 1G)")
    parser.add_argument("--ssh-user", help="SSH username")
    parser.add_argument("--server-ip", help="Server IP address")
    parser.add_argument("--ssh-port", help="SSH port")
    parser.add_argument("--encrypted", action="store_true", help="Encrypt backup")
    parser.add_argument("--transfer-key", action="store_true", help="Transfer SSH public key")
    parser.add_argument("--run-backup", action="store_true", help="Run initial backup after setup")
    
    args = parser.parse_args()
    
    # Get host information
    if args.non_interactive:
        # Validate required arguments
        if not (args.hostname and args.max_size and args.ssh_user and args.server_ip and args.ssh_port):
            parser.error("--non-interactive requires --hostname, --max-size, --ssh-user, --server-ip, and --ssh-port")
        
        host_info = {
            "hostname": args.hostname,
            "max_size": args.max_size,
            "ssh_user": args.ssh_user,
            "server_ip": args.server_ip,
            "ssh_port": args.ssh_port,
            "encrypted": args.encrypted,
            "transfer_key": args.transfer_key,
            "run_backup": args.run_backup
        }
    else:
        host_info = get_host_information()
    
    # Add the host
    host_manager = HostManager()
    success, message = host_manager.add_host(
        hostname=host_info["hostname"],
        max_size=host_info["max_size"],
        ssh_user=host_info["ssh_user"],
        server_ip=host_info["server_ip"],
        ssh_port=host_info["ssh_port"],
        encrypted=host_info["encrypted"],
        transfer_key=host_info["transfer_key"],
        run_backup=host_info["run_backup"]
    )
    
    print(message)
    sys.exit(0 if success else 1)
