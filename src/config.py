"""Configuration management for the routing table collector."""
import os
from typing import Optional

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Config(BaseSettings):
    """Main application configuration."""
    
    model_config = SettingsConfigDict(
        env_file=".env", 
        env_file_encoding="utf-8",
        case_sensitive=False
    )
    
    # Database settings
    db_host: str = Field(default="localhost", description="Database host")
    db_port: int = Field(default=9100, description="Database port")
    db_name: str = Field(default="routing_tables", description="Database name")
    db_user: str = Field(default="postgres", description="Database user")
    db_password: str = Field(default="postgres", description="Database password")
    
    # Collection settings
    collection_interval: int = Field(default=3600, description="Collection interval in seconds")
    max_workers: int = Field(default=10, description="Maximum concurrent workers")
    timeout: int = Field(default=60, description="Device connection timeout")
    
    # Nornir inventory paths
    inventory_hosts: str = Field(default="inventory/hosts.yaml", description="Hosts inventory file")
    inventory_groups: str = Field(default="inventory/groups.yaml", description="Groups inventory file")
    inventory_defaults: str = Field(default="inventory/defaults.yaml", description="Defaults inventory file")
    
    # Logging
    log_level: str = Field(default="INFO", description="Logging level")
    log_file: Optional[str] = Field(default=None, description="Log file path")
    
    # Change detection
    enable_change_detection: bool = Field(default=True, description="Enable change detection")
    change_threshold: float = Field(default=0.1, description="Change threshold percentage")
    
    @field_validator("log_level")
    @classmethod
    def validate_log_level(cls, v: str) -> str:
        """Validate log level."""
        valid_levels = ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]
        if v.upper() not in valid_levels:
            raise ValueError(f"Invalid log level. Must be one of: {valid_levels}")
        return v.upper()
    
    @property
    def database_url(self) -> str:
        """Get SQLAlchemy database URL."""
        return f"postgresql://{self.db_user}:{self.db_password}@{self.db_host}:{self.db_port}/{self.db_name}"


# Global configuration instance
config = Config()