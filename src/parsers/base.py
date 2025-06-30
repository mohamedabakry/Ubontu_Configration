"""Base parser class for route table parsing."""
import re
import ipaddress
from abc import ABC, abstractmethod
from typing import Dict, List, Optional, Tuple, Any
from dataclasses import dataclass
import structlog

logger = structlog.get_logger(__name__)


@dataclass
class ParsedRoute:
    """Represents a parsed route entry."""
    destination: str
    prefix_length: int
    next_hop: Optional[str]
    protocol: str
    metric: Optional[int] = None
    admin_distance: Optional[int] = None
    interface: Optional[str] = None
    as_path: Optional[str] = None
    local_preference: Optional[int] = None
    med: Optional[int] = None
    communities: Optional[List[str]] = None
    route_type: Optional[str] = None
    vrf: str = "default"


@dataclass
class VRFInfo:
    """Represents VRF information."""
    name: str
    rd: Optional[str] = None
    description: Optional[str] = None


class BaseParser(ABC):
    """Base class for vendor-specific route table parsers."""
    
    def __init__(self, vendor: str):
        self.vendor = vendor
        self.logger = logger.bind(vendor=vendor)
    
    @abstractmethod
    def parse_routing_table(self, output: str, vrf: str = "default") -> List[ParsedRoute]:
        """Parse routing table output into structured route data."""
        pass
    
    @abstractmethod
    def parse_vrf_list(self, output: str) -> List[VRFInfo]:
        """Parse VRF list output."""
        pass
    
    @abstractmethod
    def get_routing_table_command(self, vrf: str = "default") -> str:
        """Get the command to retrieve routing table for a VRF."""
        pass
    
    @abstractmethod
    def get_vrf_list_command(self) -> str:
        """Get the command to list all VRFs."""
        pass
    
    def normalize_protocol(self, protocol: str) -> str:
        """Normalize protocol names across vendors."""
        protocol_map = {
            "B": "BGP",
            "O": "OSPF",
            "S": "STATIC",
            "C": "CONNECTED",
            "L": "LOCAL",
            "R": "RIP",
            "E": "EIGRP",
            "i": "ISIS",
            "IA": "OSPF_IA",
            "E1": "OSPF_E1",
            "E2": "OSPF_E2",
            "N1": "OSPF_NSSA_E1",
            "N2": "OSPF_NSSA_E2",
        }
        return protocol_map.get(protocol.upper(), protocol.upper())
    
    def parse_network(self, network_str: str) -> Tuple[str, int]:
        """Parse network string into IP and prefix length."""
        try:
            if "/" in network_str:
                ip, prefix_len = network_str.split("/")
                return ip.strip(), int(prefix_len)
            else:
                # Handle subnet mask notation
                parts = network_str.split()
                if len(parts) >= 2:
                    ip = parts[0]
                    mask = parts[1]
                    # Convert subnet mask to prefix length
                    prefix_len = sum([bin(int(x)).count('1') for x in mask.split('.')])
                    return ip, prefix_len
                else:
                    # Assume /32 for host routes
                    return network_str.strip(), 32
        except Exception as e:
            self.logger.warning("Failed to parse network", network=network_str, error=str(e))
            return network_str.strip(), 32
    
    def validate_ip_address(self, ip_str: str) -> bool:
        """Validate if string is a valid IP address."""
        try:
            ipaddress.ip_address(ip_str)
            return True
        except ValueError:
            return False
    
    def clean_output(self, output: str) -> str:
        """Clean command output by removing ANSI codes and extra whitespace."""
        # Remove ANSI escape sequences
        ansi_escape = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')
        cleaned = ansi_escape.sub('', output)
        
        # Remove extra whitespace
        lines = [line.rstrip() for line in cleaned.split('\n')]
        return '\n'.join(lines)
    
    def extract_communities(self, community_str: str) -> List[str]:
        """Extract BGP communities from string."""
        if not community_str:
            return []
        
        # Handle different community formats
        communities = []
        for comm in community_str.split():
            if ":" in comm:
                communities.append(comm)
        
        return communities