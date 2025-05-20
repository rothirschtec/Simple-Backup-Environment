#!/usr/bin/env python3

import os
import sys
import logging
import subprocess
from pathlib import Path
from typing import List, Dict, Any, Optional

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Import our modules
try:
    from tools.lib.config import ConfigManager
except ImportError:
    from backup.tools.lib.config import ConfigManager

class BackupStatus:
    """Status reporting for SBE backups"""
    
    def __init__(self, base_dir: Optional[str] = None):
        """Initialize the backup status reporter
        
        Args:
            base_dir: Base directory of SBE installation. If None, detect automatically.
        """
        if base_dir:
            self.base_dir = Path(base_dir)
        else:
            # Set base directory to the SBE root (2 levels up from this script)
            self.base_dir = Path(__file__).resolve().parent.parent

        # Directory where backups are stored
        self.store_dir = self.base_dir / "store"

        self.config = ConfigManager(str(self.base_dir))
        
        # Load environment variables
        self.env_config = self.config.env_config
        
        # Set reports directory
        self.reports_dir = Path(self.env_config.get("REPORTS_DIR", "/var/SBE/reports/"))
    
    def show_status(self) -> None:
        """Show status of backups"""
        # Check if reports directory exists
        if not self.reports_dir.exists():
            print("Reports directory not found")
            return
        
        # Get system information
        try:
            # Try to get OS release info
            os_name = "Unknown OS"
            if Path("/etc/os-release").exists():
                with open("/etc/os-release", "r") as f:
                    for line in f:
                        if line.startswith("NAME="):
                            os_name = line.split("=")[1].strip().strip('"\'')
                            break
            
            print(os_name)
        except:
            print("Unknown system")
        
        # Show queue status
        print("\nQUEUE STATUS")
        print("------------")
        
        # Show current queue
        queue_file = self.reports_dir / "SBE-queue"
        print("\nCurrent queue:")
        if queue_file.exists():
            with open(queue_file, "r") as f:
                print(f.read())
        else:
            print("No queue file found")
        
        # Show running backups
        queue_run_file = self.reports_dir / "SBE-queue-run"
        print("\nBackups running at the moment:")
        if queue_run_file.exists():
            with open(queue_run_file, "r") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    
                    print(line)
                    parts = line.split(";")
                    if len(parts) >= 1:
                        pid = parts[0].strip()
                        
                        # Check if process is still alive
                        try:
                            os.kill(int(pid), 0)  # Signal 0 just checks if process exists
                            print("  > Task is still alive")
                        except:
                            print("  > No task with PID detected")
        else:
            print("No running backups")
        
        # Show completed backups
        done_file = self.reports_dir / "SBE-done"
        print("\nBackups done:")
        if done_file.exists() and done_file.stat().st_size > 0:
            print("(Last 10)")
            try:
                with open(done_file, "r") as f:
                    lines = f.readlines()
                    for line in lines[-10:]:
                        print(line.strip())
            except Exception as e:
                print(f"Error reading done file: {str(e)}")
        else:
            print("No backups with state DONE")
    
    def clean_queue(self) -> None:
        """Clean up the queue by removing orphaned entries"""
        # Check each queue file
        for queue_file in ["SBE-queue", "SBE-queue-run"]:
            file_path = self.reports_dir / queue_file
            
            if file_path.exists():
                with open(file_path, "r") as f:
                    lines = f.readlines()
                
                # Filter out orphaned entries
                new_lines = []
                for line in lines:
                    line = line.strip()
                    if not line:
                        continue
                    
                    parts = line.split(";")
                    if len(parts) >= 1:
                        pid = parts[0].strip()
                        
                        try:
                            # Check if process is still alive
                            os.kill(int(pid), 0)
                            # Process exists, keep line
                            new_lines.append(line + "\n")
                        except:
                            # Process doesn't exist, skip line
                            pass
                
                # Write cleaned queue
                with open(file_path, "w") as f:
                    f.writelines(new_lines)
                
                print(f"Cleaned {queue_file}: removed {len(lines) - len(new_lines)} orphaned entries")
    
    def check_mounts(self) -> None:
        """Check status of backup mounts"""
        print("\nBACKUP MOUNTS")
        print("-------------")
        
        # Get list of all backup directories
        backup_dir = self.store_dir
        mounted_count = 0
        
        for server_dir in backup_dir.iterdir():
            if not server_dir.is_dir() or server_dir.name == "tools" or server_dir.name.startswith("."):
                continue
            
            # Check if mounted
            mount_dir = server_dir / ".mounted"
            if mount_dir.exists():
                # Check if it's a mount point
                try:
                    result = subprocess.run(
                        ["findmnt", str(mount_dir)],
                        capture_output=True,
                        text=True
                    )
                    
                    is_mounted = result.returncode == 0
                    
                    print(f"{server_dir.name}: {'MOUNTED' if is_mounted else 'NOT MOUNTED'}")
                    
                    if is_mounted:
                        mounted_count += 1
                        
                        # Try to get disk usage
                        try:
                            result = subprocess.run(
                                ["df", "-h", str(mount_dir)],
                                capture_output=True,
                                text=True
                            )
                            
                            if result.returncode == 0:
                                # Print only the relevant line
                                for line in result.stdout.splitlines()[1:]:
                                    print(f"  {line}")
                        except:
                            pass
                except:
                    print(f"{server_dir.name}: MOUNT STATUS UNKNOWN")
        
        print(f"\nTotal mounted: {mounted_count}")

# Command-line interface
if __name__ == "__main__":
    import argparse
    
    # Parse arguments
    parser = argparse.ArgumentParser(description="SBE Backup Status")
    parser.add_argument("--clean", action="store_true", help="Clean up orphaned queue entries")
    parser.add_argument("--mounts", action="store_true", help="Check backup mounts")
    
    args = parser.parse_args()
    
    # Create status reporter
    status = BackupStatus()
    
    # Show status
    status.show_status()
    
    # Additional actions if requested
    if args.clean:
        status.clean_queue()
    
    if args.mounts:
        status.check_mounts()
