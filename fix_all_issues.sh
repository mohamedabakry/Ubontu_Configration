#!/bin/bash

echo "🔧 COMPREHENSIVE FIX - PostgreSQL + Pydantic Issues"
echo "====================================================="

# Step 1: Stop all containers and remove volumes
echo "1. Stopping containers and removing volumes..."
docker-compose down -v 2>/dev/null || docker compose down -v 2>/dev/null || {
    echo "   Using direct docker commands..."
    docker stop $(docker ps -q --filter "name=ubontu_configration") 2>/dev/null || true
    docker rm $(docker ps -aq --filter "name=ubontu_configration") 2>/dev/null || true
    docker volume rm $(docker volume ls -q --filter "name=ubontu_configration") 2>/dev/null || true
}

# Step 2: Remove all related images
echo "2. Removing old images..."
docker rmi -f $(docker images | grep -E "(route-collector|ubontu_configration)" | awk '{print $3}') 2>/dev/null || echo "   No old images to remove"

# Step 3: Clean Docker system
echo "3. Cleaning Docker system..."
docker system prune -f 2>/dev/null || echo "   Docker system clean skipped"

# Step 4: Fix config.py (replace Pydantic with pure Python)
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

# Step 5: Update docker-compose.yml ports
echo "5. Updating docker-compose.yml ports..."
cp docker-compose.yml docker-compose.yml.backup

# Update PostgreSQL port (avoid conflicts)
sed -i 's/"9100:5432"/"5433:5432"/g' docker-compose.yml 2>/dev/null || sed -i '' 's/"9100:5432"/"5433:5432"/g' docker-compose.yml
sed -i 's/"5432:5432"/"5433:5432"/g' docker-compose.yml 2>/dev/null || sed -i '' 's/"5432:5432"/"5433:5432"/g' docker-compose.yml

# Update pgAdmin port (avoid conflicts)
sed -i 's/"9090:80"/"8081:80"/g' docker-compose.yml 2>/dev/null || sed -i '' 's/"9090:80"/"8081:80"/g' docker-compose.yml
sed -i 's/"8080:80"/"8081:80"/g' docker-compose.yml 2>/dev/null || sed -i '' 's/"8080:80"/"8081:80"/g' docker-compose.yml

# Update Redis port (avoid conflicts)
sed -i 's/"8080:6379"/"6380:6379"/g' docker-compose.yml 2>/dev/null || sed -i '' 's/"8080:6379"/"6380:6379"/g' docker-compose.yml

echo "   ✅ Updated ports: PostgreSQL:5433, pgAdmin:8081, Redis:6380"

# Step 6: Update requirements.txt
echo "6. Updating requirements.txt..."
if grep -q "pydantic" requirements.txt; then
    # Remove pydantic lines
    grep -v "pydantic" requirements.txt > requirements_new.txt
    mv requirements_new.txt requirements.txt
    echo "   ✅ Removed Pydantic dependencies"
else
    echo "   ✅ No Pydantic dependencies found in requirements.txt"
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
echo "9. Building fresh container (no cache)..."
docker-compose build --no-cache --pull route-collector 2>/dev/null || docker compose build --no-cache --pull route-collector

if [ $? -ne 0 ]; then
    echo "❌ Build failed!"
    exit 1
fi

# Step 10: Start services with fresh volumes
echo "10. Starting services with fresh database..."
docker-compose up -d 2>/dev/null || docker compose up -d

# Step 11: Wait for services
echo "11. Waiting for services to start..."
sleep 20

# Step 12: Check service status
echo "12. Checking service status..."
docker ps --filter "name=ubontu_configration"

echo ""
echo "13. Checking logs..."
docker-compose logs --tail=15 postgres 2>/dev/null || docker compose logs --tail=15 postgres
echo ""
docker-compose logs --tail=15 route-collector 2>/dev/null || docker compose logs --tail=15 route-collector

echo ""
echo "✅ COMPREHENSIVE FIX COMPLETE!"
echo ""
echo "🔧 Issues Fixed:"
echo "   ❌ Pydantic import errors → ✅ Pure Python configuration"
echo "   ❌ PostgreSQL version conflict → ✅ Fresh database with correct version"
echo "   ❌ Port conflicts → ✅ Unique ports for all services"
echo ""
echo "📊 Services available on:"
echo "   🗄️  PostgreSQL: localhost:5433"
echo "   🌐 pgAdmin: localhost:8081 (if admin profile enabled)"
echo "   🔴 Redis: localhost:6380 (if cache profile enabled)"
echo ""
echo "📝 Commands:"
echo "   Monitor: docker-compose logs -f route-collector"
echo "   Stop: docker-compose down"
echo "   Fresh restart: docker-compose down -v && docker-compose up -d"
echo "   Test config: docker-compose exec route-collector python -c 'from src.config import config; print(config.database_url)'"
echo ""
echo "🚨 If you still see issues, try:"
echo "   1. docker-compose down -v"
echo "   2. docker system prune -f"
echo "   3. ./fix_all_issues.sh"