"""Cisco route table parser."""
import re
from typing import List, Optional
from .base import BaseParser, ParsedRoute, VRFInfo


class CiscoParser(BaseParser):
    """Parser for Cisco IOS/IOS-XE/IOS-XR routing tables."""
    
    def __init__(self):
        super().__init__("cisco")
    
    def get_routing_table_command(self, vrf: str = "default") -> str:
        """Get command to retrieve routing table for a VRF."""
        if vrf == "default":
            return "show ip route"
        else:
            return f"show ip route vrf {vrf}"
    
    def get_vrf_list_command(self) -> str:
        """Get command to list all VRFs."""
        return "show vrf"
    
    def parse_vrf_list(self, output: str) -> List[VRFInfo]:
        """Parse VRF list output."""
        vrfs = [VRFInfo(name="default")]  # Always include default VRF
        
        cleaned_output = self.clean_output(output)
        lines = cleaned_output.split('\n')
        
        # Skip header lines
        data_started = False
        for line in lines:
            line = line.strip()
            if not line or line.startswith("Name"):
                if "Name" in line:
                    data_started = True
                continue
            
            if not data_started:
                continue
            
            # Parse VRF line: Name Default RD Protocols Interfaces
            parts = line.split()
            if len(parts) >= 1:
                vrf_name = parts[0]
                rd = parts[2] if len(parts) > 2 and parts[2] != "<not" else None
                
                vrfs.append(VRFInfo(name=vrf_name, rd=rd))
        
        return vrfs
    
    def parse_routing_table(self, output: str, vrf: str = "default") -> List[ParsedRoute]:
        """Parse Cisco routing table output."""
        routes = []
        cleaned_output = self.clean_output(output)
        lines = cleaned_output.split('\n')
        
        # Patterns for different route types
        route_patterns = [
            # Standard format: B    10.1.1.0/24 [200/0] via 192.168.1.1
            re.compile(r'^([BOSCLERIAD*]+[\*]?)\s+(\S+)\s+\[(\d+)/(\d+)\]\s+via\s+(\S+)(?:\s+\d+:\d+:\d+)?(?:,\s+(\S+))?'),
            # Connected: C    192.168.1.0/24 is directly connected, GigabitEthernet0/0
            re.compile(r'^([CL])\s+(\S+)\s+is\s+directly\s+connected,\s+(\S+)'),
            # Static: S    10.0.0.0/8 [1/0] via 192.168.1.1
            re.compile(r'^([S])\s+(\S+)\s+\[(\d+)/(\d+)\]\s+via\s+(\S+)'),
        ]
        
        current_route = None
        
        for line in lines:
            line = line.strip()
            if not line or line.startswith("Codes:") or line.startswith("Gateway"):
                continue
            
            # Try to match route patterns
            matched = False
            for pattern in route_patterns:
                match = pattern.match(line)
                if match:
                    matched = True
                    groups = match.groups()
                    
                    if len(groups) >= 2:
                        protocol_code = groups[0].replace('*', '').strip()
                        network = groups[1]
                        
                        # Parse network
                        try:
                            destination, prefix_length = self.parse_network(network)
                        except:
                            continue
                        
                        # Create route object
                        route = ParsedRoute(
                            destination=destination,
                            prefix_length=prefix_length,
                            protocol=self.normalize_protocol(protocol_code),
                            vrf=vrf
                        )
                        
                        # Extract additional information based on pattern
                        if len(groups) >= 5:  # Has AD/metric/next_hop
                            route.admin_distance = int(groups[2]) if groups[2] else None
                            route.metric = int(groups[3]) if groups[3] else None
                            route.next_hop = groups[4] if groups[4] else None
                            route.interface = groups[5] if len(groups) > 5 and groups[5] else None
                        elif len(groups) >= 3:  # Connected route
                            route.interface = groups[2] if groups[2] else None
                        
                        routes.append(route)
                        current_route = route
                    break
            
            # Handle continuation lines (multiple next hops)
            if not matched and current_route and line.startswith('['):
                # Additional next hop: [200/0] via 192.168.1.2
                via_match = re.search(r'\[(\d+)/(\d+)\]\s+via\s+(\S+)', line)
                if via_match:
                    # Create additional route entry for load balancing
                    additional_route = ParsedRoute(
                        destination=current_route.destination,
                        prefix_length=current_route.prefix_length,
                        protocol=current_route.protocol,
                        admin_distance=int(via_match.group(1)),
                        metric=int(via_match.group(2)),
                        next_hop=via_match.group(3),
                        vrf=vrf
                    )
                    routes.append(additional_route)
        
        self.logger.info("Parsed routing table", vrf=vrf, route_count=len(routes))
        return routes
    
    def get_bgp_table_command(self, vrf: str = "default") -> str:
        """Get command to retrieve BGP table for detailed BGP information."""
        if vrf == "default":
            return "show ip bgp"
        else:
            return f"show ip bgp vpnv4 vrf {vrf}"
    
    def parse_bgp_table(self, output: str, vrf: str = "default") -> List[ParsedRoute]:
        """Parse BGP table for detailed BGP attributes."""
        routes = []
        cleaned_output = self.clean_output(output)
        lines = cleaned_output.split('\n')
        
        # BGP table pattern: *> 10.1.1.0/24    192.168.1.1    0    100    0 65001 i
        bgp_pattern = re.compile(
            r'^([*>sd\s]+)\s+(\S+)\s+(\S+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(.+)\s+([ie?])\s*$'
        )
        
        for line in lines:
            line = line.strip()
            if not line or line.startswith("BGP") or line.startswith("Network"):
                continue
            
            match = bgp_pattern.match(line)
            if match:
                status = match.group(1).strip()
                network = match.group(2)
                next_hop = match.group(3)
                metric = match.group(4)
                local_pref = match.group(5)
                weight = match.group(6)
                as_path = match.group(7).strip()
                origin = match.group(8)
                
                try:
                    destination, prefix_length = self.parse_network(network)
                except:
                    continue
                
                route = ParsedRoute(
                    destination=destination,
                    prefix_length=prefix_length,
                    next_hop=next_hop if next_hop != "0.0.0.0" else None,
                    protocol="BGP",
                    metric=int(metric) if metric.isdigit() else None,
                    local_preference=int(local_pref) if local_pref.isdigit() else None,
                    as_path=as_path,
                    vrf=vrf
                )
                
                # Determine route type from status
                if ">" in status:
                    route.route_type = "best"
                elif "*" in status:
                    route.route_type = "valid"
                
                routes.append(route)
        
        return routes