"""Juniper route table parser."""
import re
from typing import List, Optional
from .base import BaseParser, ParsedRoute, VRFInfo


class JuniperParser(BaseParser):
    """Parser for Juniper JunOS routing tables."""
    
    def __init__(self):
        super().__init__("juniper")
    
    def get_routing_table_command(self, vrf: str = "default") -> str:
        """Get command to retrieve routing table for a VRF."""
        if vrf == "default":
            return "show route"
        else:
            return f"show route table {vrf}"
    
    def get_vrf_list_command(self) -> str:
        """Get command to list all VRFs (routing instances)."""
        return "show route instance"
    
    def parse_vrf_list(self, output: str) -> List[VRFInfo]:
        """Parse VRF list output."""
        vrfs = [VRFInfo(name="default")]  # Always include default VRF
        
        cleaned_output = self.clean_output(output)
        lines = cleaned_output.split('\n')
        
        for line in lines:
            line = line.strip()
            if not line or line.startswith("Instance"):
                continue
            
            # Parse instance line: instance-name Type RD
            parts = line.split()
            if len(parts) >= 1:
                instance_name = parts[0]
                rd = None
                
                # Look for RD in the line
                for part in parts:
                    if ":" in part and re.match(r'\d+:\d+', part):
                        rd = part
                        break
                
                vrfs.append(VRFInfo(name=instance_name, rd=rd))
        
        return vrfs
    
    def parse_routing_table(self, output: str, vrf: str = "default") -> List[ParsedRoute]:
        """Parse Juniper routing table output."""
        routes = []
        cleaned_output = self.clean_output(output)
        lines = cleaned_output.split('\n')
        
        current_destination = None
        
        for line in lines:
            line = line.strip()
            if not line:
                continue
            
            # Skip header lines
            if any(header in line for header in ["Destination", "inet.0:", "inet6.0:"]):
                continue
            
            # Check if this is a destination line (starts with network)
            if re.match(r'^\d+\.\d+\.\d+\.\d+/\d+', line):
                # New destination
                parts = line.split()
                current_destination = parts[0]
                
                # If there's route info on the same line
                if len(parts) > 1:
                    route = self._parse_route_line(current_destination, line, vrf)
                    if route:
                        routes.append(route)
            
            elif line.startswith('*[') or line.startswith('['):
                # Route continuation line
                if current_destination:
                    route = self._parse_route_line(current_destination, line, vrf)
                    if route:
                        routes.append(route)
            
            elif current_destination and (line.startswith('>') or 
                                        any(line.startswith(p) for p in ['via', 'to'])):
                # Another route for the same destination
                route = self._parse_route_line(current_destination, line, vrf)
                if route:
                    routes.append(route)
        
        self.logger.info("Parsed routing table", vrf=vrf, route_count=len(routes))
        return routes
    
    def _parse_route_line(self, destination: str, line: str, vrf: str) -> Optional[ParsedRoute]:
        """Parse a single route line."""
        try:
            dest_ip, prefix_length = self.parse_network(destination)
        except:
            return None
        
        # Parse route information
        # Format: *[BGP/170] 1d 2h 3m, MED 0, localpref 100, from 192.168.1.1
        #         > to 10.0.0.1 via ae0.100
        
        protocol = None
        admin_distance = None
        metric = None
        next_hop = None
        interface = None
        local_pref = None
        med = None
        as_path = None
        
        # Extract protocol and admin distance
        protocol_match = re.search(r'\[([A-Za-z]+)/(\d+)\]', line)
        if protocol_match:
            protocol = self.normalize_protocol(protocol_match.group(1))
            admin_distance = int(protocol_match.group(2))
        
        # Extract MED
        med_match = re.search(r'MED (\d+)', line)
        if med_match:
            med = int(med_match.group(1))
        
        # Extract local preference
        localpref_match = re.search(r'localpref (\d+)', line)
        if localpref_match:
            local_pref = int(localpref_match.group(1))
        
        # Extract metric
        metric_match = re.search(r'metric (\d+)', line)
        if metric_match:
            metric = int(metric_match.group(1))
        
        # Extract next hop and interface
        via_match = re.search(r'to\s+(\S+)\s+via\s+(\S+)', line)
        if via_match:
            next_hop = via_match.group(1)
            interface = via_match.group(2)
        else:
            # Try alternative format
            to_match = re.search(r'>\s+to\s+(\S+)', line)
            if to_match:
                next_hop = to_match.group(1)
            
            via_match = re.search(r'via\s+(\S+)', line)
            if via_match:
                interface = via_match.group(1)
        
        # Extract AS path for BGP routes
        if protocol == "BGP":
            as_path_match = re.search(r'AS path: (.+?)(?:,|$)', line)
            if as_path_match:
                as_path = as_path_match.group(1).strip()
        
        route = ParsedRoute(
            destination=dest_ip,
            prefix_length=prefix_length,
            next_hop=next_hop,
            protocol=protocol or "UNKNOWN",
            metric=metric,
            admin_distance=admin_distance,
            interface=interface,
            local_preference=local_pref,
            med=med,
            as_path=as_path,
            vrf=vrf
        )
        
        return route
    
    def get_bgp_table_command(self, vrf: str = "default") -> str:
        """Get command to retrieve BGP table."""
        if vrf == "default":
            return "show route protocol bgp"
        else:
            return f"show route table {vrf} protocol bgp"