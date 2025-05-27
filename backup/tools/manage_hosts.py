#!/usr/bin/env python3
"""
Orchestrates add/remove of SBE backup hosts as defined in backup/config/servers.yaml.
Should be run regularly to keep actual hosts in sync with config.
"""

import os
import sys
import subprocess
from pathlib import Path
import yaml
import logging
import shutil

# Config paths
BASE_DIR = Path(__file__).resolve().parent.parent.parent
CONFIG_YAML = BASE_DIR / "backup" / "config" / "servers.yaml"
STORE_DIR = BASE_DIR / "backup" / "store"
ADD_HOST_SCRIPT = BASE_DIR / "backup" / "tools" / "add_host.py"

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
log = logging.getLogger("manage_hosts")

def load_servers_yaml(path):
    """Load servers config YAML"""
    with open(path, 'r') as f:
        data = yaml.safe_load(f)
    return data.get('servers', [])

def get_existing_hosts(store_dir):
    """Returns a set of currently managed hostnames in BACKUP/store/"""
    if not store_dir.exists():
        return set()
    return set([d.name for d in store_dir.iterdir() if d.is_dir() and not d.name.startswith('.')])

def add_host(entry):
    """Run add_host.py with dict config for a host"""
    cmd = [
        sys.executable, str(ADD_HOST_SCRIPT),
        '--hostname', entry['hostname'],
        '--max-size', entry['max_size'],
        '--ssh-user', entry['ssh_user'],
        '--server-ip', entry['server_ip'],
        '--ssh-port', str(entry.get('ssh_port', 22))
    ]
    if entry.get('encrypted', False):
        cmd.append('--encrypted')
    if entry.get('transfer_key', False):
        cmd.append('--transfer-key')
    if entry.get('run_backup', False):
        cmd.append('--run-backup')
    # Logging cmd
    log.info(f"Adding host: {' '.join(map(str,cmd))}")
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        log.error(f"add_host.py failed: {res.stderr.strip()}")
    else:
        log.info(f"add_host.py success: {res.stdout.strip()}")
    return res.returncode == 0

def unmount_and_remove_host(hostname):
    """Unmount, close luks, and remove the store dir for a host"""
    server_dir = STORE_DIR / hostname
    mount_dir = server_dir / ".mounted"
    # Try to unmount (ignore errors)
    if mount_dir.exists():
        subprocess.run(["umount", str(mount_dir)], capture_output=True)
    # Try to close LUKS device per add_host.py logic
    import hashlib
    h = hashlib.md5(hostname.encode()).hexdigest()[:8]
    device_name = f"sbe_{h}_mapper"
    # Attempt LUKS close, ignore errors
    subprocess.run(["cryptsetup", "luksClose", device_name], capture_output=True)
    subprocess.run(["dmsetup", "remove", "-f", device_name], capture_output=True)
    # Remove directory
    if server_dir.exists():
        log.info(f"Removing backup dir: {server_dir}")
        shutil.rmtree(server_dir)

def main():
    # Load config
    servers = load_servers_yaml(CONFIG_YAML)
    wanted = set([entry['hostname'] for entry in servers])
    existing = get_existing_hosts(STORE_DIR)

    # Add hosts (new in config)
    for entry in servers:
        if entry['hostname'] not in existing:
            ok = add_host(entry)
            if not ok:
                log.error(f"Failed to add host {entry['hostname']}")

    # Remove hosts (no longer in config)
    for hostname in sorted(existing - wanted):
        log.info(f"Removing host not in config: {hostname}")
        unmount_and_remove_host(hostname)

if __name__ == "__main__":
    main()