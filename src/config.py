"""Configuration management for the routing table collector."""
import os
from typing import Dict, List, Optional, Any
from pydantic import BaseSettings, Field, validator
from pydantic_settings import SettingsConfigDict


class DatabaseConfig(BaseSettings):
    """Database configuration."""
    
    model_config = SettingsConfigDict(env_prefix="DB_")
    
    host: str = Field(default="localhost", description="Database host")
    port: int = Field(default=5432, description="Database port")
    name: str = Field(default="routing_tables", description="Database name")
    user: str = Field(default="postgres", description="Database user")
    password: str = Field(default="postgres", description="Database password")
    
    @property
    def url(self) -> str:
        """Get SQLAlchemy database URL."""
        return f"postgresql://{self.user}:{self.password}@{self.host}:{self.port}/{self.name}"


class CollectorConfig(BaseSettings):
    """Main collector configuration."""
    
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")
    
    # Database settings
    database: DatabaseConfig = Field(default_factory=DatabaseConfig)
    
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
    
    @validator("log_level")
    def validate_log_level(cls, v):
        """Validate log level."""
        valid_levels = ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]
        if v.upper() not in valid_levels:
            raise ValueError(f"Invalid log level. Must be one of: {valid_levels}")
        return v.upper()


# Global configuration instance
config = CollectorConfig()