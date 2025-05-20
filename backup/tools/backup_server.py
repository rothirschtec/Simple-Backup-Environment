#!/usr/bin/env python3

import os
import sys
import logging
import argparse
import subprocess
from pathlib import Path
from datetime import datetime

try:
    from lib.mount import BackupMounter
except ImportError:
    from backup.tools.lib.mount import BackupMounter

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def run_backup(server_name, backup_type="daily", retention=None):
    """Run a backup with the specified server, type and retention
    
    Args:
        server_name: Name of the server to back up
        backup_type: Type of backup (daily, weekly, monthly, yearly, latest)
        retention: Number of backups to keep
    """
    logger.info(f"Starting {backup_type} backup for {server_name}")
    
    # Set base directory to the SBE root
    base_dir = Path(__file__).resolve().parent.parent.parent
    
    # Get paths
    server_dir = base_dir / "store" / server_name
    mount_dir = server_dir / ".mounted"
    backup_dir = mount_dir / backup_type

    # Ensure mount
    mounter = BackupMounter(str(base_dir))
    mounted_here = False
    if not _is_mounted(mount_dir):
        success, msg = mounter.mount_backup_directory(server_name)
        if not success:
            logger.error(f"Failed to mount backup directory: {msg}")
            return False
        mounter.initialize_backup_directories(server_name)
        mounted_here = True
    
    # Create timestamp for this backup
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    
    success = False
    try:
        # Make sure backup directory exists
        backup_dir.mkdir(parents=True, exist_ok=True)

        # Read server configuration
        config = _read_server_config(server_dir / "server.config")

        # Get rsync parameters
        rsync_opts = ["-a", "--delete", "--numeric-ids", "--relative"]

        # Add SSH options if needed (pass as separate arguments)
        ssh_cmd = f"ssh -p {config.get('PORT', '22')}"
        rsync_opts.extend(["-e", ssh_cmd])

        # Build rsync command
        rsync_cmd = ["rsync"] + rsync_opts
        share = config.get('SHARE', '/') or '/'  # Default to '/' if empty
        source = f"{config.get('USER', 'root')}@{config.get('SERVER')}:{share}"
        target = str(backup_dir / timestamp)

        # Create target directory
        os.makedirs(target, exist_ok=True)

        # Run rsync
        logger.info(f"Running rsync from {source} to {target}")
        command = rsync_cmd + [source, target]
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError(
                f"rsync failed with code {result.returncode}: {result.stderr}"
            )

        # Record executed command and timestamp
        with open(f"{target}/backup_info.txt", "w") as f:
            f.write(f"Backup created at {datetime.now().isoformat()}\n")
            f.write(f"Server: {server_name}\n")
            f.write(f"Type: {backup_type}\n")
            f.write(
                f"Command: {' '.join(command)}\nReturn code: {result.returncode}\n"
            )

        logger.info(f"Created backup at {target}")

        # Implement retention policy if specified
        if retention:
            _apply_retention_policy(backup_dir, retention)

        success = True
    except Exception as e:
        logger.error(f"Backup failed: {str(e)}")
        success = False
    finally:
        if mounted_here:
            u_success, msg = mounter.unmount_backup_directory(server_name)
            if not u_success:
                logger.error(f"Failed to unmount backup directory: {msg}")

    return success

def _is_mounted(mount_point):
    """Check if a directory is mounted"""
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

def _read_server_config(config_file):
    """Read server configuration from file"""
    config = {}
    
    if not os.path.exists(config_file):
        logger.warning(f"Config file {config_file} not found")
        return config
    
    try:
        with open(config_file, "r") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                
                key, _, value = line.partition("=")
                if key and value:
                    # Remove quotes if present
                    config[key.strip()] = value.strip().strip('"\'')
        
        return config
    except Exception as e:
        logger.error(f"Error reading config: {str(e)}")
        return config

def _apply_retention_policy(backup_dir, retention):
    """Apply retention policy by removing old backups"""
    try:
        # List all backups
        backups = []
        for item in os.listdir(backup_dir):
            item_path = backup_dir / item
            if os.path.isdir(item_path):
                backups.append(item)
        
        # Sort by name (timestamp)
        backups.sort(reverse=True)
        
        # Remove old backups
        if len(backups) > retention:
            for old_backup in backups[retention:]:
                logger.info(f"Removing old backup: {old_backup}")
                subprocess.run(["rm", "-rf", str(backup_dir / old_backup)])
    except Exception as e:
        logger.error(f"Error applying retention policy: {str(e)}")

if __name__ == "__main__":
    # Parse arguments
    parser = argparse.ArgumentParser(description="Run server backup")
    parser.add_argument("--server", required=True, help="Server name to back up")
    parser.add_argument("--daily", action="store_true", help="Run daily backup")
    parser.add_argument("--weekly", action="store_true", help="Run weekly backup")
    parser.add_argument("--monthly", action="store_true", help="Run monthly backup")
    parser.add_argument("--yearly", action="store_true", help="Run yearly backup")
    parser.add_argument("--latest", action="store_true", help="Run latest backup")
    parser.add_argument("--retention", type=int, help="Number of backups to keep")
    
    args = parser.parse_args()
    
    # Determine backup type
    backup_type = "daily"  # Default
    if args.weekly:
        backup_type = "weekly"
    elif args.monthly:
        backup_type = "monthly"
    elif args.yearly:
        backup_type = "yearly"
    elif args.latest:
        backup_type = "latest"
    
    # Run backup
    success = run_backup(args.server, backup_type, args.retention)
    
    # Exit with appropriate code
    sys.exit(0 if success else 1)
