#!/bin/bash

echo "🔧 COMPLETE PYDANTIC FIX - Apply to Fresh Clone"
echo "================================================"

# Step 1: Stop any running containers
echo "1. Stopping containers..."
docker-compose down -v 2>/dev/null || docker compose down -v 2>/dev/null || echo "No containers to stop"

# Step 2: Remove old images
echo "2. Removing old images..."
docker rmi -f $(docker images | grep route-collector | awk '{print $3}') 2>/dev/null || echo "No old images"

# Step 3: Replace config.py with non-Pydantic version
echo "3. Replacing config.py with non-Pydantic version..."
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

# Step 4: Update docker-compose.yml ports to avoid conflicts
echo "4. Updating docker-compose.yml ports..."
sed -i 's/"9100:5432"/"5433:5432"/g' docker-compose.yml 2>/dev/null || sed -i '' 's/"9100:5432"/"5433:5432"/g' docker-compose.yml
sed -i 's/"9090:80"/"8081:80"/g' docker-compose.yml 2>/dev/null || sed -i '' 's/"9090:80"/"8081:80"/g' docker-compose.yml
sed -i 's/"8080:6379"/"6380:6379"/g' docker-compose.yml 2>/dev/null || sed -i '' 's/"8080:6379"/"6380:6379"/g' docker-compose.yml

# Step 5: Update requirements.txt to remove Pydantic
echo "5. Updating requirements.txt..."
if grep -q "pydantic" requirements.txt; then
    sed -i '/pydantic/d' requirements.txt 2>/dev/null || sed -i '' '/pydantic/d' requirements.txt
    echo "# Configuration Management - PURE PYTHON STANDARD LIBRARY" >> requirements.txt
    echo "# Using simple Python classes with os.getenv() - no external dependencies" >> requirements.txt
fi

# Step 6: Clean Python cache
echo "6. Cleaning Python cache..."
find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
find . -name "*.pyc" -delete 2>/dev/null || true

# Step 7: Test configuration
echo "7. Testing configuration..."
python3 -c "
import sys
sys.path.insert(0, 'src')
try:
    from config import config
    print('✅ Configuration imported successfully!')
    print(f'Database URL: {config.database_url}')
    print('✅ No Pydantic dependencies!')
except Exception as e:
    print(f'❌ Configuration test failed: {e}')
    exit(1)
"

if [ $? -ne 0 ]; then
    echo "❌ Configuration test failed!"
    exit 1
fi

# Step 8: Build container
echo "8. Building container with no cache..."
docker-compose build --no-cache route-collector

if [ $? -ne 0 ]; then
    echo "❌ Build failed!"
    exit 1
fi

# Step 9: Start services
echo "9. Starting services..."
docker-compose up -d

# Step 10: Wait and check
echo "10. Waiting for startup..."
sleep 15

echo "11. Checking logs..."
docker-compose logs --tail=20 route-collector

echo ""
echo "✅ PYDANTIC COMPLETELY ELIMINATED!"
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