#!/usr/bin/env python3

import os
import sys
import time
import logging
import subprocess
import datetime
from pathlib import Path
import re
import signal
import yaml
from typing import List, Dict, Any, Optional, Set, Tuple
import threading

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

class BackupScheduler:
    """Main scheduler for SBE backups"""
    
    def __init__(self, base_dir: Optional[str] = None):
        """Initialize the backup scheduler
        
        Args:
            base_dir: Base directory of SBE installation. If None, detect automatically.
        """
        if base_dir:
            self.base_dir = Path(base_dir)
        else:
            # Set base directory to the SBE root (2 levels up from this script)
            self.base_dir = Path(__file__).resolve().parent.parent
        
        self.config = ConfigManager(str(self.base_dir))
        self.running = False
        self.backups_running = set()
        
        # Load environment variables
        self.reports_dir = Path(os.environ.get("REPORTS_DIR", "/var/SBE/reports/"))
        self.mail_recipient = os.environ.get("MAIL_RECIPIENT", "admin")
        self.sendmail_path = os.environ.get("sendMAIL_RECIPIENT", "/usr/sbin/sendmail")
        self.max_backups = int(os.environ.get("MAX_SIMULTANEOUS_BACKUPS", "2"))
        
        # Ensure reports directory exists
        if not self.reports_dir.exists():
            self.reports_dir.mkdir(parents=True, exist_ok=True)
            # Create empty queue files
            (self.reports_dir / "SBE-queue").touch()
            (self.reports_dir / "SBE-queue-run").touch()
            (self.reports_dir / "SBE-done").touch()
            logger.info("Created reports directory and initialized queue files.")
    
    def start(self, now: bool = False, logs: bool = False) -> None:
        """Start the backup scheduler
        
        Args:
            now: Whether to run all backups immediately
            logs: Whether to show detailed logs
        """
        self.running = True
        self.logs = logs
        
        # Handle signals
        signal.signal(signal.SIGINT, self._handle_signal)
        signal.signal(signal.SIGTERM, self._handle_signal)
        
        logger.info("Backup scheduler started")
        
        # Clear run queue on startup
        with open(self.reports_dir / "SBE-queue-run", "w") as f:
            f.write("")
        
        # Main loop
        try:
            while self.running:
                # Wait until the start of the next minute
                self._wait_for_next_minute()
                
                # Load and validate backup configuration
                backup_config = self._load_backup_config()
                if not backup_config:
                    logger.error("Failed to load backup configuration")
                    time.sleep(60)
                    continue
                
                # Process each backup
                for server_config in backup_config.get("servers", []):
                    self._process_backup(server_config, now)
                
                # Run checker script at 18:00
                current_time = datetime.datetime.now().strftime("%H%M")
                if current_time == "1800":
                    self._run_checker()
                
                # Sleep until the next minute
                time.sleep(60)
                
        except Exception as e:
            logger.error(f"Error in scheduler: {str(e)}")
            self._send_email(f"Error in SBE scheduler", f"An error occurred in the SBE scheduler: {str(e)}")
        
        logger.info("Backup scheduler stopped")
    
    def stop(self) -> None:
        """Stop the backup scheduler"""
        self.running = False
    
    def _handle_signal(self, signum: int, frame) -> None:
        """Handle termination signals
        
        Args:
            signum: Signal number
            frame: Current stack frame
        """
        logger.info(f"Received signal {signum}, shutting down")
        self.stop()
    
    def _wait_for_next_minute(self) -> None:
        """Wait until the start of the next minute"""
        logger.info("Waiting for the start of the next minute...")
        while datetime.datetime.now().second != 0:
            time.sleep(1)
    
    def _load_backup_config(self) -> Dict[str, Any]:
        """Load backup configuration
        
        Returns:
            Dict containing backup configuration
        """
        # Check if YAML/JSON config exists
        yaml_path = self.base_dir / "backup" / "config" / "backup.yaml"
        json_path = self.base_dir / "backup" / "config" / "backup.json"
        xml_path = self.base_dir / "backup" / "backup.xml"
        
        if yaml_path.exists():
            try:
                with open(yaml_path, "r") as f:
                    return yaml.safe_load(f)
            except Exception as e:
                logger.error(f"Error loading YAML config: {str(e)}")
                return {}
        elif json_path.exists():
            import json
            try:
                with open(json_path, "r") as f:
                    return json.load(f)
            except Exception as e:
                logger.error(f"Error loading JSON config: {str(e)}")
                return {}
        elif xml_path.exists():
            return self._parse_xml_config(xml_path)
        else:
            logger.error("No backup configuration file found")
            # Copy example config
            example_path = self.base_dir / "backup" / "tools" / "backup.xml-example"
            if example_path.exists():
                import shutil
                shutil.copy(example_path, xml_path)
                logger.info("Copied example backup.xml. Please configure it.")
            
            return {}
    
    def _parse_xml_config(self, xml_path: Path) -> Dict[str, Any]:
        """Parse XML backup configuration
        
        Args:
            xml_path: Path to XML config file
            
        Returns:
            Dict containing backup configuration
        """
        import xml.etree.ElementTree as ET
        
        try:
            # Validate XML
            result = subprocess.run(
                ["xmllint", "--noout", "--schema", str(self.base_dir / "backup" / "config" / "backup.xsd"), str(xml_path)],
                capture_output=True,
                text=True
            )
            
            if result.returncode != 0:
                logger.error(f"Invalid XML format: {result.stderr}")
                return {}
            
            logger.info("XML valid")
            
            # Parse XML
            servers = []
            tree = ET.parse(xml_path)
            root = tree.getroot()
            
            for server in root.findall(".//server"):
                server_config = {}
                
                for element in server:
                    # Convert retention to int if present
                    if element.tag == "retention" and element.text:
                        server_config[element.tag] = int(element.text)
                    else:
                        server_config[element.tag] = element.text
                
                servers.append(server_config)
            
            return {"servers": servers}
            
        except Exception as e:
            logger.error(f"Error parsing XML config: {str(e)}")
            return {}
    
    def _process_backup(self, server_config: Dict[str, Any], now: bool = False) -> None:
        """Process a backup configuration
        
        Args:
            server_config: Server configuration
            now: Whether to run backup immediately
        """
        # Extract configuration
        directory = server_config.get("backupdirectory")
        interval = server_config.get("intervall")
        date_pattern = server_config.get("date")
        backup_type = server_config.get("type")
        retention = server_config.get("retention")
        
        if not directory or not interval or not date_pattern or not backup_type:
            logger.error(f"Invalid backup configuration: {server_config}")
            return
        
        # Debug information
        if self.logs:
            logger.info(f"Checking backup for: {directory}")
            logger.info(f"Interval: {interval}")
            logger.info(f"Date: {date_pattern}")
            logger.info(f"Type: {backup_type}")
            logger.info(f"Retention: {retention}")
        
        # Check if backup should run
        should_run = False
        
        if now:
            should_run = True
        else:
            # Check interval
            current_time = datetime.datetime.now()
            
            # Parse interval
            if re.match(r"^\d+[hH]$", interval):
                # Hourly interval (e.g., "12h")
                hours = int(interval[:-1])
                if current_time.hour % hours == 0 and current_time.minute == 0:
                    should_run = True
            elif re.match(r"^\d+[mM]$", interval):
                # Minute interval (e.g., "30m")
                minutes = int(interval[:-1])
                if current_time.minute % minutes == 0:
                    should_run = True
            elif re.match(r"^\d{2}:\d{2}$", interval):
                # Specific time (e.g., "01:30")
                hour, minute = map(int, interval.split(":"))
                if current_time.hour == hour and current_time.minute == minute:
                    should_run = True
            else:
                logger.warning(f"Unknown interval format: {interval}")
                return
            
            # If interval condition met, check date pattern
            if should_run:
                # Check date pattern
                if date_pattern == "*":
                    # Wildcard - run every day
                    pass
                elif re.match(r"^\d{1,2}$", date_pattern):
                    # Day of month (e.g., "15")
                    if current_time.day != int(date_pattern):
                        should_run = False
                elif re.match(r"^[A-Za-z]{3}$", date_pattern) or re.match(r"^[A-Za-z]+$", date_pattern):
                    # Day of week (e.g., "Mon" or "Monday")
                    current_day_short = current_time.strftime("%a")
                    current_day_full = current_time.strftime("%A")
                    if date_pattern not in [current_day_short, current_day_full]:
                        should_run = False
                elif re.match(r"^[A-Za-z]{3}-\d{1,2}$", date_pattern) or re.match(r"^[A-Za-z]+-\d{1,2}$", date_pattern):
                    # Month-Day format for yearly backups (e.g., "Jan-1")
                    month_part, day_part = date_pattern.split("-")
                    current_month_short = current_time.strftime("%b")
                    current_month_full = current_time.strftime("%B")
                    if (month_part != current_month_short and month_part != current_month_full) or int(day_part) != current_time.day:
                        should_run = False
                else:
                    logger.warning(f"Unknown date pattern format: {date_pattern}")
                    should_run = False
        
        # If all conditions are met, run backup
        if should_run:
            self._run_backup(directory, backup_type, retention)
    
    def _run_backup(self, directory: str, backup_type: str, retention: Optional[int] = None) -> None:
        """Run a backup
        
        Args:
            directory: Backup directory
            backup_type: Type of backup (daily, weekly, monthly, yearly, latest)
            retention: Retention period in days
        """
        # Check if backup directory exists
        backup_dir = self.base_dir / "backup" / directory
        
        if not backup_dir.exists():
            logger.error(f"Backup directory {backup_dir} doesn't exist")
            self._send_email(f"Backup error for {directory}", f"Backup directory {backup_dir} doesn't exist")
            return
        
        # Avoid duplicates in queue
        if not self._check_queue(directory, backup_type):
            if self.logs:
                logger.info(f"Backup for {directory} already in queue with type {backup_type}")
            return
        
        # Manage queue to avoid overloading
        self._manage_queue()
        
        logger.info(f"Starting backup for {directory} with type {backup_type}")
        
        # Add to run queue
        self._add_to_run_queue(directory, backup_type)
        
        # Universal backup script
        universal_script = self.base_dir / "backup" / "tools" / "backup_server.py"
        
        # Build command
        command = [
            sys.executable, 
            str(universal_script), 
            "--server", directory,
            f"--{backup_type}"
        ]
        
        if retention is not None:
            command.extend(["--retention", str(retention)])
        
        # Start backup in background
        try:
            process = subprocess.Popen(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )
            
            # Add to running backups set
            self.backups_running.add(process.pid)
            
            # Start thread to monitor process completion
            threading.Thread(
                target=self._monitor_backup_process,
                args=(process, directory, backup_type),
                daemon=True
            ).start()
            
        except Exception as e:
            logger.error(f"Error starting backup for {directory}: {str(e)}")
            self._send_email(f"Backup error for {directory}", f"Error starting backup: {str(e)}")
            self._remove_from_queue(directory, backup_type)
    
    def _monitor_backup_process(self, process: subprocess.Popen, directory: str, backup_type: str) -> None:
        """Monitor backup process and handle completion
        
        Args:
            process: Subprocess process object
            directory: Backup directory
            backup_type: Type of backup
        """
        stdout, stderr = process.communicate()
        
        # Get return code
        return_code = process.poll()
        
        # Remove from running backups
        if process.pid in self.backups_running:
            self.backups_running.remove(process.pid)
        
        # Move from run queue to done
        self._remove_from_run_queue(process.pid)
        self._add_to_done(process.pid, directory, backup_type, return_code == 0)
        
        # Check for errors
        if return_code != 0:
            logger.error(f"Backup failed for {directory}: {stderr.decode()}")
            self._send_email(
                f"Backup failed for {directory}",
                f"Return code: {return_code}\n\nStdout:\n{stdout.decode()}\n\nStderr:\n{stderr.decode()}"
            )
        else:
            logger.info(f"Backup completed successfully for {directory}")
            if self.logs:
                logger.info(f"Backup output: {stdout.decode()}")
    
    def _check_queue(self, directory: str, backup_type: str) -> bool:
        """Check if backup is already in queue
        
        Args:
            directory: Backup directory
            backup_type: Type of backup
            
        Returns:
            True if not in queue, False otherwise
        """
        # Create directory if it doesn't exist
        if not self.reports_dir.exists():
            self.reports_dir.mkdir(parents=True, exist_ok=True)
        
        # Check if the PID used in queue file is active (Delete old entries)
        for queue_file in ["SBE-queue", "SBE-queue-run"]:
            queue_path = self.reports_dir / queue_file
            
            if queue_path.exists():
                # Read queue file
                with open(queue_path, "r") as f:
                    lines = f.readlines()
                
                # Check if lines match current backup
                new_lines = []
                for line in lines:
                    if not line.strip():
                        continue
                    
                    parts = line.split(";")
                    if len(parts) >= 4:
                        pid_str = parts[0].strip()
                        try:
                            pid = int(pid_str)
                            # Check if PID is still active
                            try:
                                os.kill(pid, 0)  # Signal 0 just checks if process exists
                                # Process exists, keep line
                                new_lines.append(line)
                                
                                # Check if this is our directory and type
                                if parts[2].strip() == directory and parts[3].strip() == backup_type:
                                    return False  # Already in queue
                            except OSError:
                                # Process doesn't exist, remove line
                                pass
                        except ValueError:
                            # Invalid PID, keep line
                            new_lines.append(line)
                
                # Write cleaned queue file
                with open(queue_path, "w") as f:
                    f.writelines(new_lines)
        
        # Add to queue
        with open(self.reports_dir / "SBE-queue", "a") as f:
            start_date = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            f.write(f"{os.getpid()}; {start_date}; {directory}; {backup_type};\n")
        
        return True
    
    def _manage_queue(self) -> None:
        """Manage backup queue to avoid overloading"""
        # Check current number of running backups
        queue_path = self.reports_dir / "SBE-queue-run"
        
        if queue_path.exists():
            with open(queue_path, "r") as f:
                # Count non-empty lines
                lines = [line for line in f.readlines() if line.strip()]
                running_count = len(lines)
            
            # Wait until there's room in the queue
            while running_count >= self.max_backups:
                time.sleep(2)
                
                # Recheck queue
                with open(queue_path, "r") as f:
                    lines = [line for line in f.readlines() if line.strip()]
                    running_count = len(lines)
    
    def _add_to_run_queue(self, directory: str, backup_type: str) -> None:
        """Add backup to run queue
        
        Args:
            directory: Backup directory
            backup_type: Type of backup
        """
        with open(self.reports_dir / "SBE-queue-run", "a") as f:
            start_date = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            f.write(f"{os.getpid()}; {start_date}; {directory}; {backup_type};\n")
        
        # Remove from waiting queue
        self._remove_from_queue(directory, backup_type)
    
    def _remove_from_queue(self, directory: str, backup_type: str) -> None:
        """Remove backup from waiting queue
        
        Args:
            directory: Backup directory
            backup_type: Type of backup
        """
        queue_path = self.reports_dir / "SBE-queue"
        
        if queue_path.exists():
            with open(queue_path, "r") as f:
                lines = f.readlines()
            
            # Filter out matching lines
            new_lines = []
            for line in lines:
                if not line.strip():
                    continue
                
                parts = line.split(";")
                if len(parts) >= 4 and parts[2].strip() == directory and parts[3].strip() == backup_type:
                    continue
                
                new_lines.append(line)
            
            # Write filtered queue
            with open(queue_path, "w") as f:
                f.writelines(new_lines)
    
    def _remove_from_run_queue(self, pid: int) -> None:
        """Remove backup from run queue
        
        Args:
            pid: Process ID
        """
        queue_path = self.reports_dir / "SBE-queue-run"
        
        if queue_path.exists():
            with open(queue_path, "r") as f:
                lines = f.readlines()
            
            # Filter out matching lines
            new_lines = []
            for line in lines:
                if not line.strip():
                    continue
                
                parts = line.split(";")
                if len(parts) >= 1 and parts[0].strip() == str(pid):
                    continue
                
                new_lines.append(line)
            
            # Write filtered queue
            with open(queue_path, "w") as f:
                f.writelines(new_lines)
    
    def _add_to_done(self, pid: int, directory: str, backup_type: str, success: bool) -> None:
        """Add backup to done list
        
        Args:
            pid: Process ID
            directory: Backup directory
            backup_type: Type of backup
            success: Whether backup was successful
        """
        with open(self.reports_dir / "SBE-done", "a") as f:
            start_date = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            status = "SUCCESS" if success else "FAILED"
            f.write(f"{pid}; {start_date}; {directory}; {backup_type}; {status};\n")
    
    def _run_checker(self) -> None:
        """Run the checker script"""
        logger.info("Running checker script")
        
        checker_script = self.base_dir / "backup" / "tools" / "checker.sh"
        py_checker_script = self.base_dir / "backup" / "tools" / "checker.py"
        
        if py_checker_script.exists():
            # Use Python script if available
            command = [sys.executable, str(py_checker_script)]
        elif checker_script.exists():
            # Use shell script
            command = ["bash", str(checker_script)]
        else:
            logger.error("Checker script not found")
            return
        
        try:
            subprocess.run(command, check=True)
            logger.info("Checker script completed successfully")
        except subprocess.CalledProcessError as e:
            logger.error(f"Checker script failed: {e}")
            self._send_email("Checker script failed", f"Error code: {e.returncode}\n\nOutput: {e.stdout}\n\nError: {e.stderr}")
    
    def _send_email(self, subject: str, body: str) -> None:
        """Send email notification
        
        Args:
            subject: Email subject
            body: Email body
        """
        try:
            process = subprocess.Popen(
                [self.sendmail_path, self.mail_recipient],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )
            
            message = f"Subject: {subject}\n\n{body}"
            stdout, stderr = process.communicate(input=message)
            
            if process.returncode != 0:
                logger.error(f"Failed to send email: {stderr}")
        except Exception as e:
            logger.error(f"Error sending email: {str(e)}")

# Command-line interface
if __name__ == "__main__":
    import argparse
    
    # Parse arguments
    parser = argparse.ArgumentParser(description="SBE Backup Scheduler")
    parser.add_argument("--now", action="store_true", help="Run all backups immediately")
    parser.add_argument("--update", action="store_true", help="Update scripts")
    parser.add_argument("--logs", action="store_true", help="Show detailed logs")
    
    args = parser.parse_args()
    
    # Handle update request
    if args.update:
        logger.info("Updating scripts")
        
        try:
            # Pull latest from git
            subprocess.run(["git", "pull"], check=True)
            
            # Run update script
            update_script = Path(__file__).resolve().parent / "tools" / "update_scripts.sh"
            py_update_script = Path(__file__).resolve().parent / "tools" / "update_scripts.py"
            
            if py_update_script.exists():
                subprocess.run([sys.executable, str(py_update_script)], check=True)
            elif update_script.exists():
                subprocess.run(["bash", str(update_script)], check=True)
            else:
                logger.error("Update script not found")
            
            logger.info("Scripts updated successfully")
            
        except subprocess.CalledProcessError as e:
            logger.error(f"Update failed: {e}")
        
        sys.exit(0)
    
    # Start scheduler
    scheduler = BackupScheduler()
    scheduler.start(now=args.now, logs=args.logs)
