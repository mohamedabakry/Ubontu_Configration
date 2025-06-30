"""Scheduler for periodic route table collection and change detection."""
import time
import schedule
from datetime import datetime, timedelta
from typing import Dict, List, Set, Any
import structlog
from sqlalchemy import and_, desc

from .config import config
from .database import db_manager
from .models import Device, VRF, Route, CollectionRun, ChangeLog
from .collector import RouteTableCollector

logger = structlog.get_logger(__name__)


class ChangeDetector:
    """Detect changes in routing tables between collection runs."""
    
    def __init__(self):
        self.logger = logger.bind(component="change_detector")
    
    def detect_changes(self, device_id: str, current_run_id: str) -> Dict[str, int]:
        """Detect changes between current and previous collection runs."""
        with db_manager.get_session() as session:
            # Get current collection run
            current_run = session.query(CollectionRun).filter_by(id=current_run_id).first()
            if not current_run:
                return {"added": 0, "removed": 0, "modified": 0}
            
            # Get previous successful collection run
            previous_run = session.query(CollectionRun).filter(
                and_(
                    CollectionRun.device_id == device_id,
                    CollectionRun.id != current_run_id,
                    CollectionRun.status == "completed"
                )
            ).order_by(desc(CollectionRun.completed_at)).first()
            
            if not previous_run:
                # No previous run to compare
                return {"added": current_run.total_routes, "removed": 0, "modified": 0}
            
            # Get routes from both runs
            current_routes = session.query(Route).filter_by(
                collection_run_id=current_run_id
            ).all()
            
            previous_routes = session.query(Route).filter_by(
                collection_run_id=previous_run.id
            ).all()
            
            # Create route sets for comparison
            current_route_set = self._create_route_set(current_routes)
            previous_route_set = self._create_route_set(previous_routes)
            
            # Detect changes
            added_routes = current_route_set - previous_route_set
            removed_routes = previous_route_set - current_route_set
            
            # Detect modifications (same network but different attributes)
            current_networks = {self._get_route_key(r): r for r in current_routes}
            previous_networks = {self._get_route_key(r): r for r in previous_routes}
            
            modified_count = 0
            for network_key in current_networks.keys() & previous_networks.keys():
                if self._routes_differ(current_networks[network_key], 
                                     previous_networks[network_key]):
                    modified_count += 1
            
            changes = {
                "added": len(added_routes),
                "removed": len(removed_routes),
                "modified": modified_count
            }
            
            # Update collection run statistics
            current_run.routes_added = changes["added"]
            current_run.routes_removed = changes["removed"]
            current_run.routes_modified = changes["modified"]
            session.commit()
            
            # Log changes if significant
            total_change_pct = (changes["added"] + changes["removed"] + changes["modified"]) / max(current_run.total_routes, 1) * 100
            if total_change_pct > config.change_threshold:
                self._log_changes(session, device_id, current_routes, previous_routes, changes)
            
            self.logger.info("Change detection completed", 
                           device_id=device_id, 
                           changes=changes,
                           change_percentage=total_change_pct)
            
            return changes
    
    def _create_route_set(self, routes: List[Route]) -> Set[str]:
        """Create a set of route identifiers for comparison."""
        return {self._get_route_signature(route) for route in routes}
    
    def _get_route_key(self, route: Route) -> str:
        """Get a unique key for a route (network + VRF)."""
        return f"{route.destination}/{route.prefix_length}:{route.vrf.name}"
    
    def _get_route_signature(self, route: Route) -> str:
        """Get a complete signature for a route including all attributes."""
        return (f"{route.destination}/{route.prefix_length}:"
                f"{route.vrf.name}:{route.protocol}:{route.next_hop}:"
                f"{route.metric}:{route.admin_distance}")
    
    def _routes_differ(self, route1: Route, route2: Route) -> bool:
        """Check if two routes with same network differ in attributes."""
        return (route1.next_hop != route2.next_hop or
                route1.protocol != route2.protocol or
                route1.metric != route2.metric or
                route1.admin_distance != route2.admin_distance or
                route1.interface != route2.interface)
    
    def _log_changes(self, session, device_id: str, current_routes: List[Route], 
                    previous_routes: List[Route], changes: Dict[str, int]):
        """Log detailed changes to the change log table."""
        device = session.query(Device).filter_by(id=device_id).first()
        if not device:
            return
        
        # Create detailed change logs
        current_networks = {self._get_route_key(r): r for r in current_routes}
        previous_networks = {self._get_route_key(r): r for r in previous_routes}
        
        # Log added routes
        for network_key in current_networks.keys() - previous_networks.keys():
            route = current_networks[network_key]
            change_log = ChangeLog(
                device_id=device_id,
                vrf_name=route.vrf.name,
                change_type="added",
                route_network=f"{route.destination}/{route.prefix_length}",
                new_values={
                    "protocol": route.protocol,
                    "next_hop": route.next_hop,
                    "metric": route.metric,
                    "admin_distance": route.admin_distance,
                    "interface": route.interface
                }
            )
            session.add(change_log)
        
        # Log removed routes
        for network_key in previous_networks.keys() - current_networks.keys():
            route = previous_networks[network_key]
            change_log = ChangeLog(
                device_id=device_id,
                vrf_name=route.vrf.name,
                change_type="removed",
                route_network=f"{route.destination}/{route.prefix_length}",
                old_values={
                    "protocol": route.protocol,
                    "next_hop": route.next_hop,
                    "metric": route.metric,
                    "admin_distance": route.admin_distance,
                    "interface": route.interface
                }
            )
            session.add(change_log)
        
        # Log modified routes
        for network_key in current_networks.keys() & previous_networks.keys():
            current_route = current_networks[network_key]
            previous_route = previous_networks[network_key]
            
            if self._routes_differ(current_route, previous_route):
                change_log = ChangeLog(
                    device_id=device_id,
                    vrf_name=current_route.vrf.name,
                    change_type="modified",
                    route_network=f"{current_route.destination}/{current_route.prefix_length}",
                    old_values={
                        "protocol": previous_route.protocol,
                        "next_hop": previous_route.next_hop,
                        "metric": previous_route.metric,
                        "admin_distance": previous_route.admin_distance,
                        "interface": previous_route.interface
                    },
                    new_values={
                        "protocol": current_route.protocol,
                        "next_hop": current_route.next_hop,
                        "metric": current_route.metric,
                        "admin_distance": current_route.admin_distance,
                        "interface": current_route.interface
                    }
                )
                session.add(change_log)


class RouteTableScheduler:
    """Scheduler for periodic route table collection."""
    
    def __init__(self):
        self.collector = RouteTableCollector()
        self.change_detector = ChangeDetector()
        self.logger = logger.bind(component="scheduler")
        self.running = False
    
    def setup_schedule(self):
        """Setup periodic collection schedule."""
        interval_minutes = config.collection_interval // 60
        
        # Schedule collection
        schedule.every(interval_minutes).minutes.do(self.run_collection)
        
        # Schedule cleanup (daily at 2 AM)
        schedule.every().day.at("02:00").do(self.cleanup_old_data)
        
        self.logger.info("Schedule configured", 
                        collection_interval_minutes=interval_minutes)
    
    def run_collection(self):
        """Run a collection cycle."""
        try:
            self.logger.info("Starting scheduled collection")
            
            # Initialize database if needed
            db_manager.initialize()
            
            # Collect from all devices
            summary = self.collector.collect_all_devices()
            
            # Run change detection if enabled
            if config.enable_change_detection:
                self.detect_changes_for_recent_runs()
            
            self.logger.info("Scheduled collection completed", **summary)
            
        except Exception as e:
            self.logger.error("Scheduled collection failed", error=str(e))
    
    def detect_changes_for_recent_runs(self):
        """Run change detection for recent collection runs."""
        with db_manager.get_session() as session:
            # Get recent successful runs (last hour)
            cutoff_time = datetime.utcnow() - timedelta(hours=1)
            recent_runs = session.query(CollectionRun).filter(
                and_(
                    CollectionRun.status == "completed",
                    CollectionRun.completed_at >= cutoff_time,
                    CollectionRun.routes_added == 0,  # Not yet processed
                    CollectionRun.routes_removed == 0,
                    CollectionRun.routes_modified == 0
                )
            ).all()
            
            for run in recent_runs:
                try:
                    self.change_detector.detect_changes(
                        str(run.device_id), 
                        str(run.id)
                    )
                except Exception as e:
                    self.logger.error("Change detection failed", 
                                    device_id=str(run.device_id),
                                    run_id=str(run.id),
                                    error=str(e))
    
    def cleanup_old_data(self):
        """Clean up old collection data."""
        try:
            with db_manager.get_session() as session:
                cutoff_date = datetime.utcnow() - timedelta(days=30)
                
                # Delete old collection runs and their routes
                old_runs = session.query(CollectionRun).filter(
                    CollectionRun.completed_at < cutoff_date
                ).all()
                
                deleted_runs = 0
                deleted_routes = 0
                
                for run in old_runs:
                    # Count routes before deletion
                    route_count = session.query(Route).filter_by(
                        collection_run_id=run.id
                    ).count()
                    
                    # Delete routes (cascade will handle this)
                    session.delete(run)
                    
                    deleted_runs += 1
                    deleted_routes += route_count
                
                # Delete old change logs
                old_changes = session.query(ChangeLog).filter(
                    ChangeLog.detected_at < cutoff_date
                ).delete()
                
                session.commit()
                
                self.logger.info("Cleanup completed", 
                               deleted_runs=deleted_runs,
                               deleted_routes=deleted_routes,
                               deleted_changes=old_changes)
        
        except Exception as e:
            self.logger.error("Cleanup failed", error=str(e))
    
    def run(self):
        """Run the scheduler."""
        self.logger.info("Starting route table scheduler")
        self.running = True
        
        # Setup schedule
        self.setup_schedule()
        
        # Run initial collection
        self.run_collection()
        
        # Start scheduler loop
        while self.running:
            try:
                schedule.run_pending()
                time.sleep(60)  # Check every minute
            except KeyboardInterrupt:
                self.logger.info("Scheduler stopped by user")
                break
            except Exception as e:
                self.logger.error("Scheduler error", error=str(e))
                time.sleep(60)
        
        self.logger.info("Route table scheduler stopped")
    
    def stop(self):
        """Stop the scheduler."""
        self.running = False