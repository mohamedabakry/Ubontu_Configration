"""Configuration management for the routing table collector."""
import os
from typing import Optional
from dataclasses import dataclass


@dataclass
class Config:
    """Main application configuration using environment variables."""
    
    # Database settings
    db_host: str = "localhost"
    db_port: int = 9100
    db_name: str = "routing_tables"
    db_user: str = "postgres"
    db_password: str = "postgres"
    
    # Collection settings
    collection_interval: int = 3600
    max_workers: int = 10
    timeout: int = 60
    
    # Nornir inventory paths
    inventory_hosts: str = "inventory/hosts.yaml"
    inventory_groups: str = "inventory/groups.yaml"
    inventory_defaults: str = "inventory/defaults.yaml"
    
    # Logging
    log_level: str = "INFO"
    log_file: Optional[str] = None
    
    # Change detection
    enable_change_detection: bool = True
    change_threshold: float = 0.1
    
    def __post_init__(self):
        """Load configuration from environment variables."""
        # Database settings
        self.db_host = os.getenv("DB_HOST", self.db_host)
        self.db_port = int(os.getenv("DB_PORT", str(self.db_port)))
        self.db_name = os.getenv("DB_NAME", self.db_name)
        self.db_user = os.getenv("DB_USER", self.db_user)
        self.db_password = os.getenv("DB_PASSWORD", self.db_password)
        
        # Collection settings
        self.collection_interval = int(os.getenv("COLLECTION_INTERVAL", str(self.collection_interval)))
        self.max_workers = int(os.getenv("MAX_WORKERS", str(self.max_workers)))
        self.timeout = int(os.getenv("TIMEOUT", str(self.timeout)))
        
        # Logging
        self.log_level = os.getenv("LOG_LEVEL", self.log_level).upper()
        self.log_file = os.getenv("LOG_FILE", self.log_file)
        
        # Change detection
        self.enable_change_detection = os.getenv("ENABLE_CHANGE_DETECTION", "true").lower() == "true"
        self.change_threshold = float(os.getenv("CHANGE_THRESHOLD", str(self.change_threshold)))
        
        # Validate log level
        valid_levels = ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]
        if self.log_level not in valid_levels:
            self.log_level = "INFO"
    
    @property
    def database_url(self) -> str:
        """Get SQLAlchemy database URL."""
        return f"postgresql://{self.db_user}:{self.db_password}@{self.db_host}:{self.db_port}/{self.db_name}"


# Global configuration instance
config = Config()