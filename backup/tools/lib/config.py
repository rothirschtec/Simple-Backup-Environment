#!/usr/bin/env python3

import os
import yaml
import json
import logging
from pathlib import Path
from typing import Dict, Any, Optional, Union

logger = logging.getLogger(__name__)

class ConfigManager:
    """Configuration manager for SBE that loads and validates configuration"""
    
    def __init__(self, base_dir: Optional[str] = None):
        """Initialize the configuration manager
        
        Args:
            base_dir: The base directory for SBE. If None, use parent of current script.
        """
        if base_dir:
            self.base_dir = Path(base_dir)
        else:
            # Set base directory to the SBE root (2 levels up from this script)
            self.base_dir = Path(__file__).resolve().parent.parent.parent.parent
        
        self.env_config = {}
        self.server_config = {}
        self.backup_config = {}
        
        # Load environment variables
        self._load_env()
    
    def _load_env(self) -> None:
        """Load environment variables from .env file"""
        env_path = self.base_dir / ".env"
        if not env_path.exists():
            logger.warning(f"No .env file found at {env_path}")
            return
        
        with open(env_path, "r") as env_file:
            for line in env_file:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                
                key, _, value = line.partition("=")
                if key and value:
                    # Remove quotes if present
                    value = value.strip('"\'')
                    self.env_config[key.strip()] = value
                    # Also set in environment
                    os.environ[key.strip()] = value
    
    def load_server_config(self, server_name: str) -> Dict[str, Any]:
        """Load server-specific configuration
        
        Args:
            server_name: Name of the server (directory name)
            
        Returns:
            Dict containing server configuration
        """
        server_dir = self.base_dir / "backup" / server_name
        config_path = server_dir / "server.config"
        
        if not config_path.exists():
            logger.error(f"No server config found at {config_path}")
            return {}
        
        # Parse shell-style config file
        with open(config_path, "r") as config_file:
            for line in config_file:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                
                key, _, value = line.partition("=")
                if key and value:
                    # Remove quotes if present
                    value = value.strip('"\'')
                    self.server_config[key.strip()] = value
        
        return self.server_config
    
    def load_backup_config(self) -> Dict[str, Any]:
        """Load backup configuration from YAML/JSON file
        
        Returns:
            Dict containing backup configuration
        """
        # Check for YAML config first
        yaml_path = self.base_dir / "backup" / "config" / "backup.yaml"
        json_path = self.base_dir / "backup" / "config" / "backup.json"
        xml_path = self.base_dir / "backup" / "backup.xml"
        
        if yaml_path.exists():
            with open(yaml_path, "r") as yaml_file:
                self.backup_config = yaml.safe_load(yaml_file)
        elif json_path.exists():
            with open(json_path, "r") as json_file:
                self.backup_config = json.load(json_file)
        elif xml_path.exists():
            # For backwards compatibility - parse XML using the XML parser
            self.backup_config = self._parse_xml_config(xml_path)
        else:
            logger.error("No backup configuration file found")
            return {}
        
        return self.backup_config
    
    def _parse_xml_config(self, xml_path: Path) -> Dict[str, Any]:
        """Parse the old XML config format for backward compatibility
        
        Args:
            xml_path: Path to XML config file
            
        Returns:
            Dict representation of XML config
        """
        import xml.etree.ElementTree as ET
        
        servers = []
        try:
            tree = ET.parse(xml_path)
            root = tree.getroot()
            
            for server in root.findall(".//server"):
                server_config = {}
                
                # Extract elements
                for element in server:
                    # Handle retention as integer
                    if element.tag == "retention":
                        server_config[element.tag] = int(element.text)
                    else:
                        server_config[element.tag] = element.text
                
                servers.append(server_config)
                
        except Exception as e:
            logger.error(f"Error parsing XML config: {e}")
        
        return {"servers": servers}
    
    def get_value(self, key: str, default: Any = None) -> Any:
        """Get a configuration value by key
        
        Args:
            key: Configuration key to look up
            default: Default value if key not found
            
        Returns:
            Configuration value or default
        """
        # Check environment config first
        if key in self.env_config:
            return self.env_config[key]
        
        # Then check server config
        if key in self.server_config:
            return self.server_config[key]
        
        # Finally check backup config (top-level keys only)
        if key in self.backup_config:
            return self.backup_config[key]
        
        return default
    
    def save_server_config(self, server_name: str, config: Dict[str, Any]) -> bool:
        """Save server configuration to file
        
        Args:
            server_name: Name of the server (directory name)
            config: Configuration dict to save
            
        Returns:
            True if successful, False otherwise
        """
        server_dir = self.base_dir / "backup" / server_name
        config_path = server_dir / "server.config"
        
        try:
            # Create directory if it doesn't exist
            server_dir.mkdir(parents=True, exist_ok=True)
            
            # Write config in shell format
            with open(config_path, "w") as config_file:
                config_file.write("# Server configuration for SBE\n")
                config_file.write(f"# Created: {os.environ.get('HOSTNAME', 'unknown')}\n\n")
                
                for key, value in config.items():
                    config_file.write(f"{key}=\"{value}\"\n")
            
            return True
        
        except Exception as e:
            logger.error(f"Error saving server config: {e}")
            return False
            
    def convert_xml_to_yaml(self) -> bool:
        """Convert XML configuration to YAML format
        
        Returns:
            True if successful, False otherwise
        """
        xml_path = self.base_dir / "backup" / "backup.xml"
        yaml_path = self.base_dir / "backup" / "config" / "backup.yaml"
        
        if not xml_path.exists():
            logger.error(f"No XML config found at {xml_path}")
            return False
        
        # Parse XML and convert to YAML
        config = self._parse_xml_config(xml_path)
        
        try:
            # Create directory if it doesn't exist
            yaml_path.parent.mkdir(parents=True, exist_ok=True)
            
            with open(yaml_path, "w") as yaml_file:
                yaml.dump(config, yaml_file, default_flow_style=False)
            
            return True
        
        except Exception as e:
            logger.error(f"Error converting XML to YAML: {e}")
            return False
