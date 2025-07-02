#!/bin/bash

echo "🛠️  FINAL SOLUTION - Fix All Docker Build Issues"
echo "==============================================="

# Step 1: Stop everything and clean
echo "1. Stopping containers and cleaning up..."
docker-compose down -v 2>/dev/null || docker compose down -v 2>/dev/null || {
    docker stop $(docker ps -q --filter "name=ubontu_configration") 2>/dev/null || true
    docker rm $(docker ps -aq --filter "name=ubontu_configration") 2>/dev/null || true
    docker volume rm $(docker volume ls -q --filter "name=ubontu_configration") 2>/dev/null || true
}

# Step 2: Remove old images
echo "2. Removing old images..."
docker rmi -f $(docker images | grep -E "(route-collector|ubontu_configration)" | awk '{print $3}') 2>/dev/null || echo "   No old images to remove"

# Step 3: Fix requirements.txt - Use compatible versions
echo "3. Fixing requirements.txt - using compatible versions..."
cat > requirements.txt << 'EOF'
# Simplified requirements - Compatible with Python 3.9
# Network Automation Libraries
nornir>=3.3.0
nornir-napalm>=0.3.0
nornir-netmiko>=0.1.2
napalm>=4.0.0
netmiko>=4.1.0
scrapli>=2022.7.30

# Database & ORM
psycopg2-binary>=2.9.0
sqlalchemy>=1.4.0,<2.0.0
alembic>=1.9.0

# CLI & User Interface
click>=8.0.0
rich>=13.0.0
schedule>=1.1.0

# Network Utilities
netaddr>=0.8.0
pysnmp>=4.4.0

# File & Data Handling
pyyaml>=6.0
jinja2>=3.1.0
python-dotenv>=0.21.0

# Logging & Monitoring
structlog>=22.0.0

# Security & Utilities
cryptography>=3.4.0
paramiko>=2.12.0
EOF

echo "   ✅ Updated requirements.txt with compatible versions"

# Step 4: Fix Dockerfile - Simple and working
echo "4. Fixing Dockerfile..."
cat > Dockerfile << 'EOF'
FROM python:3.9-slim

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    libpq-dev \
    openssh-client \
    sshpass \
    telnet \
    iputils-ping \
    netcat-openbsd \
    curl \
    vim \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Create application directory
WORKDIR /app

# Upgrade pip first
RUN pip install --upgrade pip

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY src/ ./src/
COPY inventory/ ./inventory/

# Create .env file template
RUN echo "# Database Configuration" > .env.example && \
    echo "DB_HOST=postgres" >> .env.example && \
    echo "DB_PORT=5432" >> .env.example && \
    echo "DB_NAME=routing_tables" >> .env.example && \
    echo "DB_USER=postgres" >> .env.example && \
    echo "DB_PASSWORD=postgres" >> .env.example && \
    echo "" >> .env.example && \
    echo "# Collection Configuration" >> .env.example && \
    echo "COLLECTION_INTERVAL=3600" >> .env.example && \
    echo "MAX_WORKERS=10" >> .env.example && \
    echo "TIMEOUT=60" >> .env.example && \
    echo "" >> .env.example && \
    echo "# Logging" >> .env.example && \
    echo "LOG_LEVEL=INFO" >> .env.example && \
    echo "" >> .env.example && \
    echo "# Change Detection" >> .env.example && \
    echo "ENABLE_CHANGE_DETECTION=true" >> .env.example && \
    echo "CHANGE_THRESHOLD=0.1" >> .env.example

# Create entrypoint script
RUN echo '#!/bin/bash' > /app/entrypoint.sh && \
    echo 'set -e' >> /app/entrypoint.sh && \
    echo '' >> /app/entrypoint.sh && \
    echo '# Copy environment template if .env does not exist' >> /app/entrypoint.sh && \
    echo 'if [ ! -f /app/.env ]; then' >> /app/entrypoint.sh && \
    echo '    cp /app/.env.example /app/.env' >> /app/entrypoint.sh && \
    echo '    echo "Created .env file from template"' >> /app/entrypoint.sh && \
    echo 'fi' >> /app/entrypoint.sh && \
    echo '' >> /app/entrypoint.sh && \
    echo '# Wait for database' >> /app/entrypoint.sh && \
    echo 'echo "Waiting for database..."' >> /app/entrypoint.sh && \
    echo 'while ! nc -z $DB_HOST $DB_PORT; do' >> /app/entrypoint.sh && \
    echo '    sleep 1' >> /app/entrypoint.sh && \
    echo 'done' >> /app/entrypoint.sh && \
    echo 'echo "Database is ready!"' >> /app/entrypoint.sh && \
    echo '' >> /app/entrypoint.sh && \
    echo '# Initialize database if needed' >> /app/entrypoint.sh && \
    echo 'python -m src.cli init-db' >> /app/entrypoint.sh && \
    echo '' >> /app/entrypoint.sh && \
    echo '# Execute the command passed to docker run' >> /app/entrypoint.sh && \
    echo 'exec "$@"' >> /app/entrypoint.sh && \
    chmod +x /app/entrypoint.sh

# Set the entrypoint
ENTRYPOINT ["/app/entrypoint.sh"]

# Default command
CMD ["python", "-m", "src.cli", "scheduler"]

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD python -c "import sys; sys.path.append('/app'); from src.database import db_manager; db_manager.initialize(); print('OK')" || exit 1

# Expose port for potential web interface
EXPOSE 8000

# Labels
LABEL maintainer="Network Automation Team"
LABEL description="Multi-vendor routing table collector"
LABEL version="1.0.0"
EOF

echo "   ✅ Fixed Dockerfile"

# Step 5: Fix config.py - Remove Pydantic
echo "5. Fixing config.py - removing Pydantic..."
cat > src/config.py << 'EOF'
"""Ultra-simple configuration using only Python standard library."""
import os
from typing import Optional


class SimpleConfig:
    """Simple configuration class using only standard library."""
    
    def __init__(self):
        # Database settings
        self.db_host = os.getenv("DB_HOST", "localhost")
        self.db_port = int(os.getenv("DB_PORT", "5433"))
        self.db_name = os.getenv("DB_NAME", "routing_tables")
        self.db_user = os.getenv("DB_USER", "postgres")
        self.db_password = os.getenv("DB_PASSWORD", "postgres")
        
        # Collection settings
        self.collection_interval = int(os.getenv("COLLECTION_INTERVAL", "3600"))
        self.max_workers = int(os.getenv("MAX_WORKERS", "10"))
        self.timeout = int(os.getenv("TIMEOUT", "60"))
        
        # Nornir inventory paths
        self.inventory_hosts = os.getenv("INVENTORY_HOSTS", "inventory/hosts.yaml")
        self.inventory_groups = os.getenv("INVENTORY_GROUPS", "inventory/groups.yaml")
        self.inventory_defaults = os.getenv("INVENTORY_DEFAULTS", "inventory/defaults.yaml")
        
        # Logging
        self.log_level = self._validate_log_level(os.getenv("LOG_LEVEL", "INFO"))
        self.log_file = os.getenv("LOG_FILE")
        
        # Change detection
        self.enable_change_detection = os.getenv("ENABLE_CHANGE_DETECTION", "true").lower() == "true"
        self.change_threshold = float(os.getenv("CHANGE_THRESHOLD", "0.1"))
    
    def _validate_log_level(self, level: str) -> str:
        """Validate and return log level."""
        valid_levels = ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]
        level = level.upper()
        return level if level in valid_levels else "INFO"
    
    @property
    def database_url(self) -> str:
        """Get SQLAlchemy database URL."""
        return f"postgresql://{self.db_user}:{self.db_password}@{self.db_host}:{self.db_port}/{self.db_name}"


# Global configuration instance
config = SimpleConfig()
EOF

echo "   ✅ Fixed Pydantic import issues"

# Step 6: Fix docker-compose.yml ports and remove version warning
echo "6. Fixing docker-compose.yml..."
cp docker-compose.yml docker-compose.yml.backup 2>/dev/null || true

# Remove version line to avoid warning
sed -i '/^version:/d' docker-compose.yml 2>/dev/null || sed -i '' '/^version:/d' docker-compose.yml

# Update ports to avoid conflicts
sed -i 's/"9100:5432"/"5433:5432"/g' docker-compose.yml 2>/dev/null || sed -i '' 's/"9100:5432"/"5433:5432"/g' docker-compose.yml
sed -i 's/"5432:5432"/"5433:5432"/g' docker-compose.yml 2>/dev/null || sed -i '' 's/"5432:5432"/"5433:5432"/g' docker-compose.yml
sed -i 's/"9090:80"/"8081:80"/g' docker-compose.yml 2>/dev/null || sed -i '' 's/"9090:80"/"8081:80"/g' docker-compose.yml
sed -i 's/"8080:80"/"8081:80"/g' docker-compose.yml 2>/dev/null || sed -i '' 's/"8080:80"/"8081:80"/g' docker-compose.yml
sed -i 's/"8080:6379"/"6380:6379"/g' docker-compose.yml 2>/dev/null || sed -i '' 's/"8080:6379"/"6380:6379"/g' docker-compose.yml

echo "   ✅ Fixed docker-compose.yml"

# Step 7: Clean Python cache
echo "7. Cleaning Python cache..."
find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
find . -name "*.pyc" -delete 2>/dev/null || true

# Step 8: Test configuration
echo "8. Testing configuration..."
python3 -c "
import sys
sys.path.insert(0, 'src')
try:
    from config import config
    print('   ✅ Configuration imported successfully!')
    print(f'   📊 Database URL: {config.database_url}')
    print('   ✅ No Pydantic dependencies!')
except Exception as e:
    print(f'   ❌ Configuration test failed: {e}')
    exit(1)
"

if [ $? -ne 0 ]; then
    echo "❌ Configuration test failed!"
    exit 1
fi

# Step 9: Build fresh container with better error handling
echo "9. Building fresh container (with improved pip install)..."
echo "   This may take a few minutes..."

# Try docker-compose first, then docker compose
if command -v docker-compose >/dev/null 2>&1; then
    BUILD_CMD="docker-compose build --no-cache route-collector"
else
    BUILD_CMD="docker compose build --no-cache route-collector"
fi

echo "   Running: $BUILD_CMD"
$BUILD_CMD

if [ $? -ne 0 ]; then
    echo "❌ Build failed!"
    echo ""
    echo "🔍 Troubleshooting:"
    echo "1. Check if all packages in requirements.txt are available"
    echo "2. Try building with verbose output:"
    echo "   docker-compose build --no-cache --progress=plain route-collector"
    echo "3. Or try a minimal requirements.txt with just essential packages"
    exit 1
fi

echo "   ✅ Build successful!"

# Step 10: Start services
echo "10. Starting services..."
if command -v docker-compose >/dev/null 2>&1; then
    docker-compose up -d
else
    docker compose up -d
fi

# Step 11: Wait and check
echo "11. Waiting for services to start..."
sleep 20

echo "12. Checking service status..."
docker ps --filter "name=ubontu_configration"

echo ""
echo "13. Checking logs..."
echo "--- PostgreSQL logs ---"
if command -v docker-compose >/dev/null 2>&1; then
    docker-compose logs --tail=10 postgres
else
    docker compose logs --tail=10 postgres
fi
echo ""
echo "--- Route Collector logs ---"
if command -v docker-compose >/dev/null 2>&1; then
    docker-compose logs --tail=10 route-collector
else
    docker compose logs --tail=10 route-collector
fi

echo ""
echo "✅ FINAL SOLUTION APPLIED!"
echo ""
echo "🔧 Fixed Issues:"
echo "   ❌ Requirements.txt dependency conflicts → ✅ Compatible versions"
echo "   ❌ Dockerfile package versions → ✅ Latest available packages"
echo "   ❌ Pydantic import errors → ✅ Pure Python configuration"
echo "   ❌ PostgreSQL version conflict → ✅ Fresh database"
echo "   ❌ Port conflicts → ✅ Unique ports"
echo "   ❌ Docker compose version warning → ✅ Removed obsolete version line"
echo ""
echo "📊 Services available on:"
echo "   🗄️  PostgreSQL: localhost:5433"
echo "   🌐 pgAdmin: localhost:8081 (if admin profile enabled)"
echo "   🔴 Redis: localhost:6380 (if cache profile enabled)"
echo ""
echo "📝 Commands:"
echo "   Monitor: docker-compose logs -f route-collector"
echo "   Stop: docker-compose down"
echo "   Test: docker-compose exec route-collector python -c 'from src.config import config; print(config.database_url)'"
echo ""
echo "🎉 Your containers should now be running successfully!"