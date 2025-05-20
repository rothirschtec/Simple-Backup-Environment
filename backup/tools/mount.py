#!/usr/bin/env python3

import os
import sys
import logging
import argparse
from pathlib import Path

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Import our modules
try:
    from lib.mount import BackupMounter
except ImportError:
    from backup.tools.lib.mount import BackupMounter

def get_project_name() -> str:
    """Interactive prompt to select a project
    
    Returns:
        Selected project name
    """
    # Find the SBE directory
    base_dir = Path(__file__).resolve().parent.parent.parent
    
    # List available projects
    print("\nExisting projects")
    print("-----------")
    
    projects = []
    for item in (base_dir / "backup").iterdir():
        if item.is_dir() and (item / "server.config").exists() and item.name != "tools":
            projects.append(item.name)
            print(item.name)
    
    # Prompt for selection
    project = input("\nWhich project will you mount? ")
    if project not in projects:
        print(f"Project '{project}' not found.")
        return get_project_name()
    
    return project

# Command-line interface
if __name__ == "__main__":
    # Parse arguments
    parser = argparse.ArgumentParser(description="Mount/unmount backup directories")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--mount", action="store_true", help="Mount a backup directory")
    group.add_argument("--umount", action="store_true", help="Unmount a backup directory")
    parser.add_argument("--project", help="Project name (if not provided, interactive prompt will be used)")
    
    args = parser.parse_args()
    
    # Get project name
    project_name = args.project or get_project_name()
    
    # Mount or unmount
    mounter = BackupMounter()
    
    if args.mount:
        success, message = mounter.mount_backup_directory(project_name)
        if success:
            mounter.initialize_backup_directories(project_name)
    else:  # unmount
        success, message = mounter.unmount_backup_directory(project_name)
    
    print(message)
    sys.exit(0 if success else 1)
