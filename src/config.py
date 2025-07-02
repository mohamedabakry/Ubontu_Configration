"""Ultra-simple configuration using only Python standard library."""
import os
from typing import Optional


class SimpleConfig:
    """Simple configuration class using only standard library."""
    
    def __init__(self):
        # Database settings
        self.db_host = os.getenv("DB_HOST", "localhost")
        self.db_port = int(os.getenv("DB_PORT", "5433"))
        self.db_name = os.getenv("DB_NAME", "routing_tables")
        self.db_user = os.getenv("DB_USER", "postgres")
        self.db_password = os.getenv("DB_PASSWORD", "postgres")
        
        # Collection settings
        self.collection_interval = int(os.getenv("COLLECTION_INTERVAL", "3600"))
        self.max_workers = int(os.getenv("MAX_WORKERS", "10"))
        self.timeout = int(os.getenv("TIMEOUT", "60"))
        
        # Nornir inventory paths
        self.inventory_hosts = os.getenv("INVENTORY_HOSTS", "inventory/hosts.yaml")
        self.inventory_groups = os.getenv("INVENTORY_GROUPS", "inventory/groups.yaml")
        self.inventory_defaults = os.getenv("INVENTORY_DEFAULTS", "inventory/defaults.yaml")
        
        # Logging
        self.log_level = self._validate_log_level(os.getenv("LOG_LEVEL", "INFO"))
        self.log_file = os.getenv("LOG_FILE")
        
        # Change detection
        self.enable_change_detection = os.getenv("ENABLE_CHANGE_DETECTION", "true").lower() == "true"
        self.change_threshold = float(os.getenv("CHANGE_THRESHOLD", "0.1"))
    
    def _validate_log_level(self, level: str) -> str:
        """Validate and return log level."""
        valid_levels = ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]
        level = level.upper()
        return level if level in valid_levels else "INFO"
    
    @property
    def database_url(self) -> str:
        """Get SQLAlchemy database URL."""
        return f"postgresql://{self.db_user}:{self.db_password}@{self.db_host}:{self.db_port}/{self.db_name}"


# Global configuration instance
config = SimpleConfig()