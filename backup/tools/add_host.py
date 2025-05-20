#!/usr/bin/env python3

import os
import sys
import logging
import argparse
import secrets
import subprocess
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
    from backup.tools.lib.key_manager import KeyManager
    from backup.tools.lib.config import ConfigManager
    from backup.tools.lib.mount import BackupMounter

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
        
        # Check if directory already exists
        if backup_dir.exists():
            # If it exists, we'll update the configuration
            logger.info(f"Backup directory for {hostname} already exists, updating configuration")
        else:
            # Create backup directory
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
                
                success, message = self._encrypt_backup_image(str(backup_img), passphrase, hostname)
                if not success:
                    return False, message
                
                # Store passphrase both locally and in key server
                with open(backup_dir / "passphrase", "w") as f:
                    f.write(passphrase)
                
                # Try to store in key server if available
                health_ok, _ = self.key_manager.check_keyserver_health()
                if health_ok:
                    success, message = self.key_manager.store_encryption_key(hostname, passphrase)
                    if success:
                        # Mark that this host uses the key server
                        (backup_dir / ".use_keyserver").touch()
                        
                        # Backup locally as fallback
                        self.key_manager.backup_key_locally(hostname, passphrase, str(backup_dir))
                    else:
                        logger.warning(f"Key server unavailable: {message}")
                        logger.info("Using local passphrase file only")
                else:
                    logger.warning("Key server unavailable, using local passphrase file only")
                
                # Format the device
                result = subprocess.run(
                    ["mkfs.ext4", f"/dev/mapper/{hostname}.mounted"],
                    capture_output=True,
                    text=True
                )
                
                if result.returncode != 0:
                    return False, f"Failed to format encrypted device: {result.stderr}"
                
                # Close the device for now
                self.mounter._close_luks_device(f"{hostname}.mounted")
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
                subprocess.Popen(
                    ["bash", str(backup_dir / "backup_server.sh")],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE
                )
                logger.info("Backup started in background")
            except Exception as e:
                logger.error(f"Failed to start backup: {str(e)}")
        
        return True, f"Host {hostname} added successfully"
    
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
    
    def _encrypt_backup_image(self, image_path: str, passphrase: str, name: str) -> Tuple[bool, str]:
        """Encrypt a backup image using LUKS
        
        Args:
            image_path: Path to backup image
            passphrase: Encryption passphrase
            name: Name to use for mapped device
            
        Returns:
            Tuple of (success, message)
        """
        try:
            # Format with LUKS
            process = subprocess.Popen(
                ["echo", "-n", passphrase],
                stdout=subprocess.PIPE
            )
            
            result = subprocess.run(
                ["cryptsetup", "-y", "luksFormat", "--type", "luks2", image_path],
                stdin=process.stdout,
                capture_output=True,
                text=True
            )
            
            if result.returncode != 0:
                return False, f"Failed to format with LUKS: {result.stderr}"
            
            # Open with LUKS
            process = subprocess.Popen(
                ["echo", "-n", passphrase],
                stdout=subprocess.PIPE
            )
            
            result = subprocess.run(
                ["cryptsetup", "luksOpen", "--type", "luks2", image_path, f"{name}.mounted"],
                stdin=process.stdout,
                capture_output=True,
                text=True
            )
            
            if result.returncode != 0:
                return False, f"Failed to open LUKS device: {result.stderr}"
            
            return True, "Backup image encrypted successfully"
        except Exception as e:
            return False, f"Error encrypting backup image: {str(e)}"
    
    def _copy_backup_script(self, hostname: str) -> bool:
        """Copy the backup script to the server directory
        
        Args:
            hostname: Host to copy script for
            
        Returns:
            True if successful, False otherwise
        """
        try:
            source = self.base_dir / "backup" / "tools" / "backup_server.sh"
            destination = self.base_dir / "backup" / hostname / "backup_server.sh"
            
            # If Python version exists, use that instead
            py_source = self.base_dir / "backup" / "tools" / "backup_server.py"
            if py_source.exists():
                destination = destination.with_suffix(".py")
                source = py_source
            
            if source.exists():
                # Copy file
                with open(source, "r") as src_file:
                    content = src_file.read()
                
                with open(destination, "w") as dest_file:
                    dest_file.write(content)
                
                # Make executable
                os.chmod(destination, 0o755)
                
                return True
            else:
                logger.error(f"Backup script not found at {source}")
                return False
        except Exception as e:
            logger.error(f"Error copying backup script: {str(e)}")
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
