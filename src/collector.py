"""Main route table collector using Nornir."""
import time
from datetime import datetime
from typing import Dict, List, Optional, Any
from concurrent.futures import ThreadPoolExecutor, as_completed
import structlog
from nornir import InitNornir
from nornir.core.task import Task, Result
from nornir.core.filter import F
from nornir_netmiko.tasks import netmiko_send_command
from nornir_napalm.tasks import napalm_get
from nornir_scrapli.tasks import send_command as scrapli_send_command

from .config import config
from .database import db_manager
from .models import Device, VRF, Route, CollectionRun, ChangeLog
from .parsers import CiscoParser, JuniperParser, HuaweiParser
from .parsers.base import ParsedRoute, VRFInfo

logger = structlog.get_logger(__name__)


class RouteTableCollector:
    """Main collector class for routing table data."""
    
    def __init__(self):
        self.nr = None
        self.parsers = {
            "cisco": CiscoParser(),
            "juniper": JuniperParser(),
            "huawei": HuaweiParser(),
        }
        self.logger = logger
        self._initialize_nornir()
    
    def _initialize_nornir(self):
        """Initialize Nornir with inventory."""
        try:
            self.nr = InitNornir(
                inventory={
                    "options": {
                        "host_file": config.inventory_hosts,
                        "group_file": config.inventory_groups,
                        "defaults_file": config.inventory_defaults,
                    }
                },
                logging={"enabled": False}  # We'll use our own logging
            )
            self.logger.info("Nornir initialized successfully", 
                           host_count=len(self.nr.inventory.hosts))
        except Exception as e:
            self.logger.error("Failed to initialize Nornir", error=str(e))
            raise
    
    def get_parser(self, vendor: str) -> Optional[Any]:
        """Get parser for a vendor."""
        vendor_lower = vendor.lower()
        
        # Map common vendor names
        vendor_map = {
            "ios": "cisco",
            "iosxe": "cisco", 
            "iosxr": "cisco",
            "nxos": "cisco",
            "junos": "juniper",
            "vrp": "huawei",
        }
        
        mapped_vendor = vendor_map.get(vendor_lower, vendor_lower)
        return self.parsers.get(mapped_vendor)
    
    def collect_device_info(self, task: Task) -> Result:
        """Nornir task to collect device information."""
        host = task.host
        parser = self.get_parser(host.platform)
        
        if not parser:
            return Result(
                host=host,
                failed=True,
                exception=f"No parser available for platform: {host.platform}"
            )
        
        try:
            # Get VRF list first
            vrf_command = parser.get_vrf_list_command()
            vrf_result = task.run(
                netmiko_send_command,
                command_string=vrf_command,
                use_textfsm=False
            )
            
            vrfs = parser.parse_vrf_list(vrf_result.result)
            
            # Collect routing tables for each VRF
            all_routes = []
            for vrf_info in vrfs:
                try:
                    rt_command = parser.get_routing_table_command(vrf_info.name)
                    rt_result = task.run(
                        netmiko_send_command,
                        command_string=rt_command,
                        use_textfsm=False
                    )
                    
                    routes = parser.parse_routing_table(rt_result.result, vrf_info.name)
                    all_routes.extend(routes)
                    
                    self.logger.info("Collected routes", 
                                   host=host.name, vrf=vrf_info.name, 
                                   route_count=len(routes))
                
                except Exception as e:
                    self.logger.warning("Failed to collect VRF routes", 
                                      host=host.name, vrf=vrf_info.name, 
                                      error=str(e))
            
            return Result(
                host=host,
                result={
                    "vrfs": vrfs,
                    "routes": all_routes,
                    "collection_time": datetime.utcnow()
                }
            )
        
        except Exception as e:
            self.logger.error("Failed to collect device data", 
                            host=host.name, error=str(e))
            return Result(host=host, failed=True, exception=str(e))
    
    def store_device_data(self, hostname: str, host_data: Dict, 
                         device_info: Dict) -> Optional[str]:
        """Store collected data in database."""
        with db_manager.get_session() as session:
            try:
                # Get or create device
                device = session.query(Device).filter_by(hostname=hostname).first()
                if not device:
                    device = Device(
                        hostname=hostname,
                        ip_address=host_data.get("hostname", hostname),
                        vendor=device_info.get("vendor", "unknown"),
                        platform=device_info.get("platform", "unknown"),
                        os_version=device_info.get("os_version"),
                        location=device_info.get("location")
                    )
                    session.add(device)
                    session.flush()  # Get device ID
                
                # Update last seen
                device.last_seen = datetime.utcnow()
                device.is_active = True
                
                # Create collection run
                collection_run = CollectionRun(
                    device_id=device.id,
                    started_at=datetime.utcnow()
                )
                session.add(collection_run)
                session.flush()  # Get run ID
                
                # Process VRFs and routes
                vrfs_data = device_info.get("vrfs", [])
                routes_data = device_info.get("routes", [])
                
                # Store VRFs
                vrf_map = {}
                for vrf_info in vrfs_data:
                    vrf = session.query(VRF).filter_by(
                        device_id=device.id, 
                        name=vrf_info.name
                    ).first()
                    
                    if not vrf:
                        vrf = VRF(
                            device_id=device.id,
                            name=vrf_info.name,
                            rd=vrf_info.rd,
                            description=vrf_info.description
                        )
                        session.add(vrf)
                        session.flush()
                    
                    vrf_map[vrf_info.name] = vrf.id
                
                # Store routes
                route_count = 0
                for route_data in routes_data:
                    vrf_id = vrf_map.get(route_data.vrf)
                    if not vrf_id:
                        continue
                    
                    route = Route(
                        vrf_id=vrf_id,
                        collection_run_id=collection_run.id,
                        destination=route_data.destination,
                        prefix_length=route_data.prefix_length,
                        next_hop=route_data.next_hop,
                        protocol=route_data.protocol,
                        metric=route_data.metric,
                        admin_distance=route_data.admin_distance,
                        interface=route_data.interface,
                        as_path=route_data.as_path,
                        local_preference=route_data.local_preference,
                        med=route_data.med,
                        communities=route_data.communities,
                        route_type=route_data.route_type
                    )
                    session.add(route)
                    route_count += 1
                
                # Update collection run statistics
                collection_run.completed_at = datetime.utcnow()
                collection_run.status = "completed"
                collection_run.total_routes = route_count
                collection_run.total_vrfs = len(vrfs_data)
                collection_run.processing_time = (
                    collection_run.completed_at - collection_run.started_at
                ).total_seconds()
                
                session.commit()
                
                self.logger.info("Stored device data", 
                               hostname=hostname, 
                               routes=route_count, 
                               vrfs=len(vrfs_data))
                
                return str(collection_run.id)
            
            except Exception as e:
                session.rollback()
                self.logger.error("Failed to store device data", 
                                hostname=hostname, error=str(e))
                
                # Update collection run with error
                if 'collection_run' in locals():
                    collection_run.status = "failed"
                    collection_run.error_message = str(e)
                    collection_run.completed_at = datetime.utcnow()
                    session.commit()
                
                return None
    
    def collect_all_devices(self) -> Dict[str, Any]:
        """Collect routing tables from all devices."""
        self.logger.info("Starting collection from all devices")
        start_time = time.time()
        
        # Run collection tasks
        results = self.nr.run(task=self.collect_device_info, num_workers=config.max_workers)
        
        # Process results
        success_count = 0
        failure_count = 0
        total_routes = 0
        
        for hostname, result in results.items():
            host = self.nr.inventory.hosts[hostname]
            
            if result.failed:
                failure_count += 1
                self.logger.error("Collection failed", 
                                hostname=hostname, 
                                error=str(result.exception))
                
                # Store failed collection run
                with db_manager.get_session() as session:
                    device = session.query(Device).filter_by(hostname=hostname).first()
                    if device:
                        failed_run = CollectionRun(
                            device_id=device.id,
                            started_at=datetime.utcnow(),
                            completed_at=datetime.utcnow(),
                            status="failed",
                            error_message=str(result.exception)
                        )
                        session.add(failed_run)
                        session.commit()
                continue
            
            # Store successful results
            device_info = {
                "vendor": getattr(host, "vendor", "unknown"),
                "platform": host.platform,
                "os_version": getattr(host, "os_version", None),
                "location": getattr(host, "location", None),
                **result.result
            }
            
            collection_run_id = self.store_device_data(
                hostname, 
                {"hostname": host.hostname}, 
                device_info
            )
            
            if collection_run_id:
                success_count += 1
                total_routes += len(result.result.get("routes", []))
            else:
                failure_count += 1
        
        elapsed_time = time.time() - start_time
        
        summary = {
            "total_devices": len(results),
            "successful": success_count,
            "failed": failure_count,
            "total_routes": total_routes,
            "elapsed_time": elapsed_time,
            "timestamp": datetime.utcnow()
        }
        
        self.logger.info("Collection completed", **summary)
        return summary
    
    def collect_device(self, hostname: str) -> bool:
        """Collect routing table from a specific device."""
        if hostname not in self.nr.inventory.hosts:
            self.logger.error("Device not found in inventory", hostname=hostname)
            return False
        
        # Filter to specific host
        device_nr = self.nr.filter(F(name=hostname))
        results = device_nr.run(task=self.collect_device_info)
        
        result = results[hostname]
        if result.failed:
            self.logger.error("Collection failed", 
                            hostname=hostname, 
                            error=str(result.exception))
            return False
        
        # Store results
        host = self.nr.inventory.hosts[hostname]
        device_info = {
            "vendor": getattr(host, "vendor", "unknown"),
            "platform": host.platform,
            "os_version": getattr(host, "os_version", None),
            "location": getattr(host, "location", None),
            **result.result
        }
        
        collection_run_id = self.store_device_data(
            hostname, 
            {"hostname": host.hostname}, 
            device_info
        )
        
        return collection_run_id is not None