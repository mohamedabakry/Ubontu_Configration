"""Database models for routing table storage."""
import uuid
from datetime import datetime
from typing import Optional
from sqlalchemy import (
    Column, String, Integer, DateTime, Boolean, Text, 
    ForeignKey, Index, Float, JSON, UniqueConstraint
)
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import relationship
from sqlalchemy.dialects.postgresql import UUID, INET

Base = declarative_base()


class Device(Base):
    """Device model for storing router information."""
    
    __tablename__ = "devices"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    hostname = Column(String(255), unique=True, nullable=False, index=True)
    ip_address = Column(INET, nullable=False)
    vendor = Column(String(50), nullable=False)
    platform = Column(String(100), nullable=False)
    os_version = Column(String(100), nullable=True)
    location = Column(String(255), nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    last_seen = Column(DateTime, nullable=True)
    is_active = Column(Boolean, default=True)
    
    # Relationships
    vrfs = relationship("VRF", back_populates="device", cascade="all, delete-orphan")
    collection_runs = relationship("CollectionRun", back_populates="device")
    
    def __repr__(self):
        return f"<Device(hostname='{self.hostname}', vendor='{self.vendor}')>"


class VRF(Base):
    """VRF model for storing VRF information."""
    
    __tablename__ = "vrfs"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    device_id = Column(UUID(as_uuid=True), ForeignKey("devices.id"), nullable=False)
    name = Column(String(255), nullable=False)
    rd = Column(String(100), nullable=True)  # Route Distinguisher
    description = Column(Text, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    # Relationships
    device = relationship("Device", back_populates="vrfs")
    routes = relationship("Route", back_populates="vrf", cascade="all, delete-orphan")
    
    # Constraints
    __table_args__ = (
        UniqueConstraint("device_id", "name", name="uq_device_vrf"),
        Index("ix_vrf_device_name", "device_id", "name"),
    )
    
    def __repr__(self):
        return f"<VRF(name='{self.name}', device='{self.device.hostname if self.device else None}')>"


class Route(Base):
    """Route model for storing individual route entries."""
    
    __tablename__ = "routes"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    vrf_id = Column(UUID(as_uuid=True), ForeignKey("vrfs.id"), nullable=False)
    collection_run_id = Column(UUID(as_uuid=True), ForeignKey("collection_runs.id"), nullable=False)
    
    # Route information
    destination = Column(INET, nullable=False)
    prefix_length = Column(Integer, nullable=False)
    next_hop = Column(INET, nullable=True)
    protocol = Column(String(20), nullable=False)  # BGP, OSPF, STATIC, CONNECTED, etc.
    metric = Column(Integer, nullable=True)
    admin_distance = Column(Integer, nullable=True)
    interface = Column(String(100), nullable=True)
    
    # Additional route attributes
    as_path = Column(Text, nullable=True)  # For BGP routes
    local_preference = Column(Integer, nullable=True)  # For BGP routes
    med = Column(Integer, nullable=True)  # For BGP routes
    communities = Column(JSON, nullable=True)  # For BGP communities
    route_type = Column(String(50), nullable=True)  # Internal, External, etc.
    
    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow)
    
    # Relationships
    vrf = relationship("VRF", back_populates="routes")
    collection_run = relationship("CollectionRun", back_populates="routes")
    
    # Constraints and indexes
    __table_args__ = (
        Index("ix_route_destination", "destination", "prefix_length"),
        Index("ix_route_vrf_protocol", "vrf_id", "protocol"),
        Index("ix_route_collection", "collection_run_id"),
    )
    
    @property
    def network(self):
        """Get network in CIDR notation."""
        return f"{self.destination}/{self.prefix_length}"
    
    def __repr__(self):
        return f"<Route(network='{self.network}', protocol='{self.protocol}')>"


class CollectionRun(Base):
    """Collection run model for tracking data collection sessions."""
    
    __tablename__ = "collection_runs"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    device_id = Column(UUID(as_uuid=True), ForeignKey("devices.id"), nullable=False)
    
    # Run information
    started_at = Column(DateTime, default=datetime.utcnow)
    completed_at = Column(DateTime, nullable=True)
    status = Column(String(20), nullable=False, default="running")  # running, completed, failed
    error_message = Column(Text, nullable=True)
    
    # Statistics
    total_routes = Column(Integer, default=0)
    total_vrfs = Column(Integer, default=0)
    processing_time = Column(Float, nullable=True)  # seconds
    
    # Change detection
    routes_added = Column(Integer, default=0)
    routes_removed = Column(Integer, default=0)
    routes_modified = Column(Integer, default=0)
    
    # Relationships
    device = relationship("Device", back_populates="collection_runs")
    routes = relationship("Route", back_populates="collection_run")
    
    # Indexes
    __table_args__ = (
        Index("ix_collection_run_device_status", "device_id", "status"),
        Index("ix_collection_run_started", "started_at"),
    )
    
    @property
    def duration(self) -> Optional[float]:
        """Get run duration in seconds."""
        if self.completed_at and self.started_at:
            return (self.completed_at - self.started_at).total_seconds()
        return None
    
    def __repr__(self):
        return f"<CollectionRun(device='{self.device.hostname if self.device else None}', status='{self.status}')>"


class ChangeLog(Base):
    """Change log model for tracking routing table changes."""
    
    __tablename__ = "change_logs"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    device_id = Column(UUID(as_uuid=True), ForeignKey("devices.id"), nullable=False)
    vrf_name = Column(String(255), nullable=False)
    
    # Change information
    change_type = Column(String(20), nullable=False)  # added, removed, modified
    route_network = Column(String(50), nullable=False)
    old_values = Column(JSON, nullable=True)
    new_values = Column(JSON, nullable=True)
    detected_at = Column(DateTime, default=datetime.utcnow)
    
    # Relationships
    device = relationship("Device")
    
    # Indexes
    __table_args__ = (
        Index("ix_change_log_device_time", "device_id", "detected_at"),
        Index("ix_change_log_type", "change_type"),
    )
    
    def __repr__(self):
        return f"<ChangeLog(device='{self.device.hostname if self.device else None}', type='{self.change_type}')>"