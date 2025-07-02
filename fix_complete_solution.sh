#!/bin/bash

echo "🛠️  COMPLETE SOLUTION - Fix All Issues"
echo "======================================"

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

# Step 3: Fix Dockerfile - Remove version pins
echo "3. Fixing Dockerfile package version issues..."
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
    && rm -rf /var/lib/apt/lists/*

# Create application directory
WORKDIR /app

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

echo "   ✅ Fixed Dockerfile package version issues"

# Step 4: Fix config.py - Remove Pydantic
echo "4. Fixing config.py - removing Pydantic..."
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

# Step 5: Fix docker-compose.yml ports
echo "5. Fixing docker-compose.yml port conflicts..."
cp docker-compose.yml docker-compose.yml.backup 2>/dev/null || true

# Remove version line to avoid warning
sed -i '/^version:/d' docker-compose.yml 2>/dev/null || sed -i '' '/^version:/d' docker-compose.yml

# Update ports
sed -i 's/"9100:5432"/"5433:5432"/g' docker-compose.yml 2>/dev/null || sed -i '' 's/"9100:5432"/"5433:5432"/g' docker-compose.yml
sed -i 's/"5432:5432"/"5433:5432"/g' docker-compose.yml 2>/dev/null || sed -i '' 's/"5432:5432"/"5433:5432"/g' docker-compose.yml
sed -i 's/"9090:80"/"8081:80"/g' docker-compose.yml 2>/dev/null || sed -i '' 's/"9090:80"/"8081:80"/g' docker-compose.yml
sed -i 's/"8080:80"/"8081:80"/g' docker-compose.yml 2>/dev/null || sed -i '' 's/"8080:80"/"8081:80"/g' docker-compose.yml
sed -i 's/"8080:6379"/"6380:6379"/g' docker-compose.yml 2>/dev/null || sed -i '' 's/"8080:6379"/"6380:6379"/g' docker-compose.yml

echo "   ✅ Fixed port conflicts: PostgreSQL:5433, pgAdmin:8081, Redis:6380"

# Step 6: Update requirements.txt
echo "6. Updating requirements.txt..."
if grep -q "pydantic" requirements.txt; then
    grep -v "pydantic" requirements.txt > requirements_new.txt
    mv requirements_new.txt requirements.txt
    echo "   ✅ Removed Pydantic dependencies"
else
    echo "   ✅ No Pydantic dependencies found"
fi

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

# Step 9: Build fresh container
echo "9. Building fresh container (this should work now)..."
docker-compose build --no-cache route-collector 2>/dev/null || docker compose build --no-cache route-collector

if [ $? -ne 0 ]; then
    echo "❌ Build failed! Check the error above."
    exit 1
fi

# Step 10: Start services
echo "10. Starting services..."
docker-compose up -d 2>/dev/null || docker compose up -d

# Step 11: Wait and check
echo "11. Waiting for services to start..."
sleep 20

echo "12. Checking service status..."
docker ps --filter "name=ubontu_configration"

echo ""
echo "13. Checking logs..."
echo "--- PostgreSQL logs ---"
docker-compose logs --tail=10 postgres 2>/dev/null || docker compose logs --tail=10 postgres
echo ""
echo "--- Route Collector logs ---"
docker-compose logs --tail=10 route-collector 2>/dev/null || docker compose logs --tail=10 route-collector

echo ""
echo "✅ COMPLETE SOLUTION APPLIED!"
echo ""
echo "🔧 Fixed Issues:"
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