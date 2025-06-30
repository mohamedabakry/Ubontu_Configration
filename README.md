# Route Table Collector

A containerized tool for collecting routing tables from multi-vendor routers and storing per-VRF subnet data into a PostgreSQL database. Built for service provider networks with support for Cisco, Juniper, Huawei, and other network vendors.

## 🚀 Features

- **Multi-vendor Support**: Cisco (IOS/IOS-XE/IOS-XR/NX-OS), Juniper (JunOS), Huawei (VRP)
- **VRF-aware Collection**: Automatically discovers and collects routes from all VRFs
- **Multiple Connection Methods**: SSH/Netmiko, NAPALM, Scrapli support
- **Change Detection**: Track routing changes over time with detailed logging
- **PostgreSQL Storage**: Structured storage with full relational database features
- **Containerized**: Docker and Kubernetes ready with docker-compose
- **Scheduled Collection**: Built-in scheduler with configurable intervals
- **Rich CLI**: Beautiful command-line interface with progress bars and tables
- **Export Capabilities**: JSON and CSV export for integration with other tools
- **Scalable Architecture**: Concurrent collection with configurable worker pools

## 📋 Requirements

### System Requirements
- Docker and Docker Compose
- Network connectivity to target routers
- PostgreSQL database (included in docker-compose)

### Network Device Requirements
- SSH access enabled
- User credentials with read access to routing tables
- Support for CLI commands (show ip route, show vrf, etc.)

## 🛠 Installation

### Quick Start with Docker Compose

1. **Clone the repository**:
```bash
git clone <repository-url>
cd route-table-collector
```

2. **Configure your network devices**:
```bash
# Copy and edit the inventory files
cp inventory/hosts.yaml.example inventory/hosts.yaml
cp inventory/groups.yaml.example inventory/groups.yaml
cp inventory/defaults.yaml.example inventory/defaults.yaml

# Edit inventory/hosts.yaml with your device information
```

3. **Configure environment**:
```bash
cp .env.example .env
# Edit .env with your database and collection settings
```

4. **Start the services**:
```bash
# Start with scheduler (automatic collection)
docker-compose up -d

# Or start with pgAdmin for database management
docker-compose --profile admin up -d
```

5. **Initialize the database** (if not auto-initialized):
```bash
docker-compose exec route-collector python -m src.cli init-db
```

### Manual Installation

1. **Install Python dependencies**:
```bash
pip install -r requirements.txt
```

2. **Setup PostgreSQL database**:
```bash
# Install PostgreSQL and create database
createdb routing_tables
```

3. **Configure environment**:
```bash
cp .env.example .env
# Edit .env with your configuration
```

4. **Initialize database**:
```bash
python main.py init-db
```

## 📁 Project Structure

```
route-table-collector/
├── src/                          # Main application code
│   ├── __init__.py
│   ├── cli.py                    # Command-line interface
│   ├── config.py                 # Configuration management
│   ├── database.py               # Database connection and session management
│   ├── models.py                 # SQLAlchemy database models
│   ├── collector.py              # Main collection logic using Nornir
│   ├── scheduler.py              # Scheduling and change detection
│   └── parsers/                  # Vendor-specific parsers
│       ├── __init__.py
│       ├── base.py               # Base parser class
│       ├── cisco.py              # Cisco parser
│       ├── juniper.py            # Juniper parser
│       └── huawei.py             # Huawei parser
├── inventory/                    # Nornir inventory files
│   ├── hosts.yaml               # Device definitions
│   ├── groups.yaml              # Device groups and connection settings
│   └── defaults.yaml            # Default connection parameters
├── scripts/                     # Database and utility scripts
│   └── init.sql                 # PostgreSQL initialization
├── logs/                        # Application logs (created at runtime)
├── Dockerfile                   # Container definition
├── docker-compose.yml          # Multi-service deployment
├── requirements.txt             # Python dependencies
├── main.py                      # Application entry point
├── .env.example                 # Environment configuration template
└── README.md                    # This file
```

## 🔧 Configuration

### Device Inventory

Configure your network devices in the Nornir inventory files:

**inventory/hosts.yaml**:
```yaml
router1-cisco:
  hostname: 192.168.1.10
  platform: ios
  vendor: cisco
  groups:
    - cisco_routers
  data:
    location: "Datacenter-1"
    os_version: "15.6(3)M"
```

**inventory/groups.yaml**:
```yaml
cisco_routers:
  connection_options:
    netmiko:
      platform: cisco_ios
      extras:
        device_type: cisco_ios
```

**inventory/defaults.yaml**:
```yaml
username: admin
password: admin
connection_options:
  netmiko:
    extras:
      timeout: 60
```

### Environment Variables

Key configuration options in `.env`:

```bash
# Database
DB_HOST=postgres
DB_NAME=routing_tables
DB_USER=postgres
DB_PASSWORD=postgres

# Collection
COLLECTION_INTERVAL=3600    # 1 hour
MAX_WORKERS=10
TIMEOUT=60

# Logging
LOG_LEVEL=INFO

# Change Detection
ENABLE_CHANGE_DETECTION=true
CHANGE_THRESHOLD=0.1        # 10% change threshold
```

## 💻 Usage

### Command Line Interface

The CLI provides several commands for managing the route collection:

```bash
# Initialize database
python main.py init-db

# Run one-time collection from all devices
python main.py collect

# Run collection from specific device
python main.py collect --device router1-cisco

# Start the scheduler (continuous collection)
python main.py scheduler

# View devices
python main.py devices

# View routes
python main.py routes --device router1 --vrf CUSTOMER-A

# View routing changes
python main.py changes --days 7

# View statistics
python main.py stats

# Export routes to JSON/CSV
python main.py export --output routes.json --format json
```

### Docker Commands

```bash
# Start services
docker-compose up -d

# Run one-time collection
docker-compose run --rm route-collector-once

# View logs
docker-compose logs -f route-collector

# Access CLI inside container
docker-compose exec route-collector python -m src.cli --help

# Stop services
docker-compose down

# Start with database admin interface
docker-compose --profile admin up -d
```

### Kubernetes Deployment

Basic Kubernetes manifests (extend as needed):

```yaml
# Save as k8s-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: route-collector
spec:
  replicas: 1
  selector:
    matchLabels:
      app: route-collector
  template:
    metadata:
      labels:
        app: route-collector
    spec:
      containers:
      - name: route-collector
        image: route-collector:latest
        env:
        - name: DB_HOST
          value: "postgres-service"
        - name: COLLECTION_INTERVAL
          value: "3600"
        volumeMounts:
        - name: inventory
          mountPath: /app/inventory
      volumes:
      - name: inventory
        configMap:
          name: inventory-config
```

Deploy with:
```bash
kubectl apply -f k8s-deployment.yaml
```

## 📊 Database Schema

The tool creates the following main tables:

- **devices**: Router information (hostname, vendor, platform, etc.)
- **vrfs**: VRF definitions per device
- **routes**: Individual route entries with full attributes
- **collection_runs**: Metadata for each collection session
- **change_logs**: Detailed change tracking

Example queries:

```sql
-- View all BGP routes
SELECT d.hostname, v.name as vrf, r.destination, r.prefix_length, r.next_hop
FROM routes r
JOIN vrfs v ON r.vrf_id = v.id  
JOIN devices d ON v.device_id = d.id
WHERE r.protocol = 'BGP';

-- View route changes in last 24 hours
SELECT d.hostname, cl.vrf_name, cl.change_type, cl.route_network, cl.detected_at
FROM change_logs cl
JOIN devices d ON cl.device_id = d.id
WHERE cl.detected_at >= NOW() - INTERVAL '24 hours';

-- Collection statistics
SELECT d.hostname, cr.total_routes, cr.total_vrfs, cr.processing_time
FROM collection_runs cr
JOIN devices d ON cr.device_id = d.id
WHERE cr.status = 'completed'
ORDER BY cr.completed_at DESC;
```

## 🔍 Monitoring and Troubleshooting

### Health Checks

The container includes health checks:
```bash
# Check container health
docker-compose ps

# View detailed health status
docker inspect route-collector --format='{{json .State.Health}}'
```

### Logs

Structured JSON logging for easy parsing:
```bash
# View application logs
docker-compose logs -f route-collector

# Filter for errors
docker-compose logs route-collector | grep '"level":"error"'

# View database logs
docker-compose logs postgres
```

### Common Issues

1. **Connection timeouts**: Increase `TIMEOUT` and device-specific timeout values
2. **Authentication failures**: Verify credentials in inventory files
3. **Parser errors**: Check device command output format compatibility
4. **Database connection issues**: Ensure PostgreSQL is running and accessible

### Performance Tuning

- Adjust `MAX_WORKERS` based on your network size and capacity
- Tune `COLLECTION_INTERVAL` based on change frequency needs
- Monitor database performance and add indexes for large deployments
- Use connection pooling for high-frequency collections

## 🤝 Integration

### NetBox Integration

Export routes for NetBox import:
```bash
python main.py export --format json --output netbox-routes.json
# Process the JSON for NetBox API calls
```

### Automation Integration

The tool integrates well with:
- **Ansible**: Use for inventory management and deployment
- **Jenkins/GitLab CI**: For automated deployment and collection
- **Grafana**: For visualization of route statistics
- **Prometheus**: For metrics collection and alerting
- **ELK Stack**: For log analysis and visualization

### API Integration (Future Enhancement)

The architecture supports adding a REST API:
```python
# Future: API endpoints
GET /api/devices
GET /api/devices/{id}/routes
GET /api/devices/{id}/vrfs
GET /api/changes
POST /api/collect/{device}
```

## 🛡 Security Considerations

1. **Credential Management**: Store sensitive credentials in environment variables or secrets management
2. **Network Access**: Limit collector network access to required devices only
3. **Database Security**: Use strong passwords and limit database access
4. **Container Security**: Regularly update base images and dependencies
5. **SSH Keys**: Prefer SSH key authentication over passwords where possible

## 📈 Scaling

For large deployments:

1. **Horizontal Scaling**: Run multiple collector instances with different device groups
2. **Database Scaling**: Use PostgreSQL clustering or read replicas
3. **Load Balancing**: Distribute collection across multiple workers
4. **Caching**: Implement Redis for caching device information
5. **Monitoring**: Add comprehensive monitoring and alerting

## 🐛 Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure code follows PEP 8 style guidelines
5. Submit a pull request

### Development Setup

```bash
# Clone for development
git clone <repository-url>
cd route-table-collector

# Create virtual environment
python -m venv venv
source venv/bin/activate  # or venv\Scripts\activate on Windows

# Install development dependencies
pip install -r requirements.txt
pip install pytest black flake8 mypy

# Run tests
pytest

# Format code
black src/

# Lint code
flake8 src/
```

## 📝 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- **Nornir**: Network automation framework
- **NAPALM**: Multi-vendor network automation library  
- **Netmiko**: Multi-vendor SSH library
- **Scrapli**: Fast SSH client for network devices
- **SQLAlchemy**: Python SQL toolkit
- **Click**: Python CLI framework
- **Rich**: Python rich text and beautiful formatting

## 📞 Support

For support and questions:
- Create an issue on GitHub
- Check the documentation in the `docs/` directory
- Review the examples in the `examples/` directory

---

**Route Table Collector** - Bringing order to network routing data! 🌐📊