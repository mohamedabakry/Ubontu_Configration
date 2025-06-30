"""Command line interface for the route table collector."""
import json
import sys
from datetime import datetime, timedelta
from typing import Optional
import click
import structlog
from rich.console import Console
from rich.table import Table
from rich.progress import Progress, SpinnerColumn, TextColumn

from .config import config
from .database import db_manager
from .models import Device, VRF, Route, CollectionRun, ChangeLog
from .collector import RouteTableCollector
from .scheduler import RouteTableScheduler

console = Console()
logger = structlog.get_logger(__name__)


def setup_logging():
    """Setup structured logging."""
    structlog.configure(
        processors=[
            structlog.stdlib.filter_by_level,
            structlog.stdlib.add_logger_name,
            structlog.stdlib.add_log_level,
            structlog.stdlib.PositionalArgumentsFormatter(),
            structlog.processors.TimeStamper(fmt="iso"),
            structlog.processors.StackInfoRenderer(),
            structlog.processors.format_exc_info,
            structlog.processors.UnicodeDecoder(),
            structlog.processors.JSONRenderer()
        ],
        context_class=dict,
        logger_factory=structlog.stdlib.LoggerFactory(),
        wrapper_class=structlog.stdlib.BoundLogger,
        cache_logger_on_first_use=True,
    )


@click.group()
@click.option('--debug', is_flag=True, help='Enable debug logging')
@click.option('--config-file', help='Configuration file path')
def cli(debug: bool, config_file: Optional[str]):
    """Route Table Collector - Multi-vendor routing table collection tool."""
    if debug:
        config.log_level = "DEBUG"
    
    setup_logging()
    
    # Initialize database
    db_manager.initialize()


@cli.command()
def init_db():
    """Initialize the database schema."""
    try:
        with console.status("[bold green]Creating database tables..."):
            db_manager.create_tables()
        console.print("✅ Database initialized successfully", style="bold green")
    except Exception as e:
        console.print(f"❌ Database initialization failed: {e}", style="bold red")
        sys.exit(1)


@cli.command()
@click.option('--device', help='Collect from specific device')
@click.option('--dry-run', is_flag=True, help='Show what would be collected without storing')
def collect(device: Optional[str], dry_run: bool):
    """Collect routing tables from devices."""
    try:
        collector = RouteTableCollector()
        
        if device:
            # Collect from specific device
            with Progress(
                SpinnerColumn(),
                TextColumn("[progress.description]{task.description}"),
                console=console
            ) as progress:
                task = progress.add_task(f"Collecting from {device}...", total=None)
                
                if dry_run:
                    console.print(f"Would collect routing table from: {device}")
                else:
                    success = collector.collect_device(device)
                    if success:
                        console.print(f"✅ Successfully collected from {device}", style="bold green")
                    else:
                        console.print(f"❌ Failed to collect from {device}", style="bold red")
                        sys.exit(1)
        else:
            # Collect from all devices
            with Progress(
                SpinnerColumn(),
                TextColumn("[progress.description]{task.description}"),
                console=console
            ) as progress:
                task = progress.add_task("Collecting from all devices...", total=None)
                
                if dry_run:
                    console.print("Would collect routing tables from all configured devices")
                else:
                    summary = collector.collect_all_devices()
                    
                    # Display summary table
                    table = Table(title="Collection Summary")
                    table.add_column("Metric", style="cyan")
                    table.add_column("Value", style="magenta")
                    
                    table.add_row("Total Devices", str(summary["total_devices"]))
                    table.add_row("Successful", str(summary["successful"]))
                    table.add_row("Failed", str(summary["failed"]))
                    table.add_row("Total Routes", str(summary["total_routes"]))
                    table.add_row("Elapsed Time", f"{summary['elapsed_time']:.2f}s")
                    
                    console.print(table)
    
    except Exception as e:
        console.print(f"❌ Collection failed: {e}", style="bold red")
        logger.error("Collection failed", error=str(e))
        sys.exit(1)


@cli.command()
def scheduler():
    """Run the periodic collection scheduler."""
    try:
        scheduler = RouteTableScheduler()
        
        console.print("🚀 Starting route table scheduler...", style="bold blue")
        console.print(f"Collection interval: {config.collection_interval} seconds")
        console.print("Press Ctrl+C to stop")
        
        scheduler.run()
    
    except KeyboardInterrupt:
        console.print("\n👋 Scheduler stopped by user", style="bold yellow")
    except Exception as e:
        console.print(f"❌ Scheduler failed: {e}", style="bold red")
        logger.error("Scheduler failed", error=str(e))
        sys.exit(1)


@cli.command()
@click.option('--device', help='Show devices matching pattern')
@click.option('--limit', default=20, help='Limit number of results')
def devices(device: Optional[str], limit: int):
    """List devices in the database."""
    with db_manager.get_session() as session:
        query = session.query(Device)
        
        if device:
            query = query.filter(Device.hostname.like(f"%{device}%"))
        
        devices_list = query.limit(limit).all()
        
        if not devices_list:
            console.print("No devices found", style="yellow")
            return
        
        table = Table(title="Devices")
        table.add_column("Hostname", style="cyan")
        table.add_column("IP Address", style="blue")
        table.add_column("Vendor", style="green")
        table.add_column("Platform", style="magenta")
        table.add_column("Last Seen", style="yellow")
        table.add_column("Status", style="red")
        
        for dev in devices_list:
            last_seen = dev.last_seen.strftime("%Y-%m-%d %H:%M") if dev.last_seen else "Never"
            status = "Active" if dev.is_active else "Inactive"
            
            table.add_row(
                dev.hostname,
                str(dev.ip_address),
                dev.vendor,
                dev.platform,
                last_seen,
                status
            )
        
        console.print(table)


@cli.command()
@click.option('--device', help='Show routes for specific device')
@click.option('--vrf', help='Show routes for specific VRF')
@click.option('--protocol', help='Filter by protocol')
@click.option('--limit', default=50, help='Limit number of results')
def routes(device: Optional[str], vrf: Optional[str], protocol: Optional[str], limit: int):
    """Display routes from the database."""
    with db_manager.get_session() as session:
        # Build query with joins
        query = session.query(Route).join(VRF).join(Device)
        
        if device:
            query = query.filter(Device.hostname.like(f"%{device}%"))
        
        if vrf:
            query = query.filter(VRF.name == vrf)
        
        if protocol:
            query = query.filter(Route.protocol.like(f"%{protocol}%"))
        
        # Get latest routes only
        query = query.join(CollectionRun).filter(
            CollectionRun.status == "completed"
        ).order_by(CollectionRun.completed_at.desc())
        
        routes_list = query.limit(limit).all()
        
        if not routes_list:
            console.print("No routes found", style="yellow")
            return
        
        table = Table(title="Routes")
        table.add_column("Device", style="cyan")
        table.add_column("VRF", style="blue")
        table.add_column("Network", style="green")
        table.add_column("Next Hop", style="magenta")
        table.add_column("Protocol", style="yellow")
        table.add_column("Metric", style="red")
        
        for route in routes_list:
            table.add_row(
                route.vrf.device.hostname,
                route.vrf.name,
                f"{route.destination}/{route.prefix_length}",
                route.next_hop or "N/A",
                route.protocol,
                str(route.metric) if route.metric is not None else "N/A"
            )
        
        console.print(table)


@cli.command()
@click.option('--device', help='Show changes for specific device')
@click.option('--days', default=7, help='Number of days to look back')
@click.option('--limit', default=50, help='Limit number of results')
def changes(device: Optional[str], days: int, limit: int):
    """Show routing table changes."""
    with db_manager.get_session() as session:
        cutoff_date = datetime.utcnow() - timedelta(days=days)
        
        query = session.query(ChangeLog).join(Device).filter(
            ChangeLog.detected_at >= cutoff_date
        )
        
        if device:
            query = query.filter(Device.hostname.like(f"%{device}%"))
        
        changes_list = query.order_by(ChangeLog.detected_at.desc()).limit(limit).all()
        
        if not changes_list:
            console.print("No changes found", style="yellow")
            return
        
        table = Table(title="Routing Changes")
        table.add_column("Device", style="cyan")
        table.add_column("VRF", style="blue")
        table.add_column("Change Type", style="green")
        table.add_column("Network", style="magenta")
        table.add_column("Detected", style="yellow")
        
        for change in changes_list:
            detected = change.detected_at.strftime("%Y-%m-%d %H:%M")
            
            table.add_row(
                change.device.hostname,
                change.vrf_name,
                change.change_type.upper(),
                change.route_network,
                detected
            )
        
        console.print(table)


@cli.command()
@click.option('--device', help='Show statistics for specific device')
def stats(device: Optional[str]):
    """Show collection statistics."""
    with db_manager.get_session() as session:
        if device:
            # Device-specific stats
            dev = session.query(Device).filter(Device.hostname.like(f"%{device}%")).first()
            if not dev:
                console.print(f"Device not found: {device}", style="red")
                return
            
            # Get latest collection run
            latest_run = session.query(CollectionRun).filter_by(
                device_id=dev.id,
                status="completed"
            ).order_by(CollectionRun.completed_at.desc()).first()
            
            if not latest_run:
                console.print(f"No collection data found for {device}", style="yellow")
                return
            
            table = Table(title=f"Statistics for {dev.hostname}")
            table.add_column("Metric", style="cyan")
            table.add_column("Value", style="magenta")
            
            table.add_row("Last Collection", latest_run.completed_at.strftime("%Y-%m-%d %H:%M:%S"))
            table.add_row("Total Routes", str(latest_run.total_routes))
            table.add_row("Total VRFs", str(latest_run.total_vrfs))
            table.add_row("Processing Time", f"{latest_run.processing_time:.2f}s")
            table.add_row("Routes Added", str(latest_run.routes_added))
            table.add_row("Routes Removed", str(latest_run.routes_removed))
            table.add_row("Routes Modified", str(latest_run.routes_modified))
            
            console.print(table)
        
        else:
            # Global stats
            total_devices = session.query(Device).count()
            active_devices = session.query(Device).filter_by(is_active=True).count()
            total_routes = session.query(Route).count()
            total_vrfs = session.query(VRF).count()
            
            # Recent collection stats
            recent_runs = session.query(CollectionRun).filter(
                CollectionRun.completed_at >= datetime.utcnow() - timedelta(hours=24)
            ).count()
            
            table = Table(title="Global Statistics")
            table.add_column("Metric", style="cyan")
            table.add_column("Value", style="magenta")
            
            table.add_row("Total Devices", str(total_devices))
            table.add_row("Active Devices", str(active_devices))
            table.add_row("Total Routes", str(total_routes))
            table.add_row("Total VRFs", str(total_vrfs))
            table.add_row("Collections (24h)", str(recent_runs))
            
            console.print(table)


@cli.command()
@click.option('--output', default='routes.json', help='Output file path')
@click.option('--device', help='Export routes for specific device')
@click.option('--vrf', help='Export routes for specific VRF')
@click.option('--format', 'output_format', type=click.Choice(['json', 'csv']), default='json', help='Output format')
def export(output: str, device: Optional[str], vrf: Optional[str], output_format: str):
    """Export routes to JSON or CSV."""
    with db_manager.get_session() as session:
        # Build query
        query = session.query(Route).join(VRF).join(Device).join(CollectionRun).filter(
            CollectionRun.status == "completed"
        )
        
        if device:
            query = query.filter(Device.hostname.like(f"%{device}%"))
        
        if vrf:
            query = query.filter(VRF.name == vrf)
        
        routes_list = query.all()
        
        if not routes_list:
            console.print("No routes found to export", style="yellow")
            return
        
        # Prepare data
        data = []
        for route in routes_list:
            route_data = {
                "device": route.vrf.device.hostname,
                "vrf": route.vrf.name,
                "destination": str(route.destination),
                "prefix_length": route.prefix_length,
                "network": f"{route.destination}/{route.prefix_length}",
                "next_hop": route.next_hop,
                "protocol": route.protocol,
                "metric": route.metric,
                "admin_distance": route.admin_distance,
                "interface": route.interface,
                "as_path": route.as_path,
                "collected_at": route.created_at.isoformat()
            }
            data.append(route_data)
        
        # Write output
        try:
            if output_format == 'json':
                with open(output, 'w') as f:
                    json.dump(data, f, indent=2, default=str)
            elif output_format == 'csv':
                import csv
                if data:
                    with open(output, 'w', newline='') as f:
                        writer = csv.DictWriter(f, fieldnames=data[0].keys())
                        writer.writeheader()
                        writer.writerows(data)
            
            console.print(f"✅ Exported {len(data)} routes to {output}", style="bold green")
        
        except Exception as e:
            console.print(f"❌ Export failed: {e}", style="bold red")


if __name__ == '__main__':
    cli()