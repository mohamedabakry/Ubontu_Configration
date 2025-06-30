"""Huawei route table parser."""
import re
from typing import List, Optional
from .base import BaseParser, ParsedRoute, VRFInfo


class HuaweiParser(BaseParser):
    """Parser for Huawei VRP routing tables."""
    
    def __init__(self):
        super().__init__("huawei")
    
    def get_routing_table_command(self, vrf: str = "default") -> str:
        """Get command to retrieve routing table for a VRF."""
        if vrf == "default":
            return "display ip routing-table"
        else:
            return f"display ip routing-table vpn-instance {vrf}"
    
    def get_vrf_list_command(self) -> str:
        """Get command to list all VRFs (VPN instances)."""
        return "display ip vpn-instance"
    
    def parse_vrf_list(self, output: str) -> List[VRFInfo]:
        """Parse VRF list output."""
        vrfs = [VRFInfo(name="default")]  # Always include default VRF
        
        cleaned_output = self.clean_output(output)
        lines = cleaned_output.split('\n')
        
        # Skip header lines and find data
        data_started = False
        for line in lines:
            line = line.strip()
            if not line:
                continue
            
            # Look for header line
            if "VPN-Instance" in line and "RD" in line:
                data_started = True
                continue
            
            if not data_started:
                continue
            
            # Parse VPN instance line
            parts = line.split()
            if len(parts) >= 1 and not line.startswith("-"):
                vpn_name = parts[0]
                rd = parts[1] if len(parts) > 1 and ":" in parts[1] else None
                
                vrfs.append(VRFInfo(name=vpn_name, rd=rd))
        
        return vrfs
    
    def parse_routing_table(self, output: str, vrf: str = "default") -> List[ParsedRoute]:
        """Parse Huawei routing table output."""
        routes = []
        cleaned_output = self.clean_output(output)
        lines = cleaned_output.split('\n')
        
        # Patterns for different route formats
        # Standard: B       10.1.1.0/24         192.168.1.1         UG    100     0       GE0/0/1
        route_pattern = re.compile(
            r'^([BOSCLED\*\s]+)\s+(\S+)\s+(\S+)\s+([A-Z]+)\s+(\d+)\s+(\d+)\s+(\S+)'
        )
        
        # Connected: C       192.168.1.0/24         0.0.0.0             U     0       0       GE0/0/1
        connected_pattern = re.compile(
            r'^([CL])\s+(\S+)\s+(\S+)\s+([A-Z]+)\s+(\d+)\s+(\d+)\s+(\S+)'
        )
        
        for line in lines:
            line = line.strip()
            if not line or any(header in line for header in 
                             ["Route Flags:", "Destination", "---", "Proto"]):
                continue
            
            # Try to match route patterns
            match = route_pattern.match(line) or connected_pattern.match(line)
            if match:
                protocol_code = match.group(1).strip()
                network = match.group(2)
                next_hop = match.group(3)
                flags = match.group(4)
                preference = match.group(5)
                cost = match.group(6)
                interface = match.group(7)
                
                # Parse network
                try:
                    destination, prefix_length = self.parse_network(network)
                except:
                    continue
                
                # Skip invalid next hops
                if next_hop == "0.0.0.0" or not self.validate_ip_address(next_hop):
                    next_hop = None
                
                route = ParsedRoute(
                    destination=destination,
                    prefix_length=prefix_length,
                    next_hop=next_hop,
                    protocol=self.normalize_protocol(protocol_code),
                    admin_distance=int(preference) if preference.isdigit() else None,
                    metric=int(cost) if cost.isdigit() else None,
                    interface=interface if interface != "NULL0" else None,
                    vrf=vrf
                )
                
                routes.append(route)
        
        self.logger.info("Parsed routing table", vrf=vrf, route_count=len(routes))
        return routes
    
    def normalize_protocol(self, protocol: str) -> str:
        """Normalize Huawei protocol names."""
        huawei_protocol_map = {
            "B": "BGP",
            "O": "OSPF",
            "S": "STATIC",
            "C": "CONNECTED",
            "D": "DIRECT",
            "L": "LOCAL",
            "R": "RIP",
            "I": "ISIS",
            "U": "USER",
            "O_INTRA": "OSPF_INTRA",
            "O_INTER": "OSPF_INTER",
            "O_ASE": "OSPF_ASE",
            "O_NSSA": "OSPF_NSSA",
        }
        
        # Use base class normalization first, then Huawei-specific
        normalized = super().normalize_protocol(protocol)
        return huawei_protocol_map.get(protocol.upper(), normalized)
    
    def get_bgp_table_command(self, vrf: str = "default") -> str:
        """Get command to retrieve BGP table."""
        if vrf == "default":
            return "display bgp routing-table"
        else:
            return f"display bgp vpnv4 vpn-instance {vrf} routing-table"
    
    def parse_bgp_table(self, output: str, vrf: str = "default") -> List[ParsedRoute]:
        """Parse BGP routing table for detailed BGP attributes."""
        routes = []
        cleaned_output = self.clean_output(output)
        lines = cleaned_output.split('\n')
        
        # BGP table pattern for Huawei
        # *>i 10.1.1.0/24        192.168.1.1      100    0    65001 i
        bgp_pattern = re.compile(
            r'^([*>di\s]+)\s+(\S+)\s+(\S+)\s+(\d+)\s+(\d+)\s+(.+)\s+([ie])\s*$'
        )
        
        for line in lines:
            line = line.strip()
            if not line or any(header in line for header in 
                             ["BGP", "Network", "Total"]):
                continue
            
            match = bgp_pattern.match(line)
            if match:
                status = match.group(1).strip()
                network = match.group(2)
                next_hop = match.group(3)
                local_pref = match.group(4)
                med = match.group(5)
                as_path = match.group(6).strip()
                origin = match.group(7)
                
                try:
                    destination, prefix_length = self.parse_network(network)
                except:
                    continue
                
                route = ParsedRoute(
                    destination=destination,
                    prefix_length=prefix_length,
                    next_hop=next_hop if next_hop != "0.0.0.0" else None,
                    protocol="BGP",
                    local_preference=int(local_pref) if local_pref.isdigit() else None,
                    med=int(med) if med.isdigit() else None,
                    as_path=as_path,
                    vrf=vrf
                )
                
                # Determine route type from status
                if ">" in status:
                    route.route_type = "best"
                elif "*" in status:
                    route.route_type = "valid"
                elif "i" in status:
                    route.route_type = "internal"
                
                routes.append(route)
        
        return routes