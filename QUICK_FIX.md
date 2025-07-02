# 🚨 QUICK FIX for PostgreSQL + Pydantic Issues

## Problem Summary
1. **PostgreSQL**: Database incompatibility from previous version
2. **Pydantic**: Import errors from old code in fresh clone

## 🔧 QUICK SOLUTION

### Option 1: Run the Fix Script
```bash
chmod +x fix_all_issues.sh
./fix_all_issues.sh
```

### Option 2: Manual Steps

#### Step 1: Stop Everything & Clean
```bash
# Stop containers and remove volumes
docker-compose down -v
# OR
docker compose down -v

# Remove old images
docker rmi -f $(docker images | grep route-collector | awk '{print $3}')

# Clean Docker system
docker system prune -f
```

#### Step 2: Fix Pydantic (Replace src/config.py)
```bash
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
```

#### Step 3: Fix Port Conflicts (Edit docker-compose.yml)
```bash
# Replace these lines in docker-compose.yml:
# "9100:5432" → "5433:5432"  (PostgreSQL)
# "9090:80"   → "8081:80"    (pgAdmin)
# "8080:6379" → "6380:6379"  (Redis)

sed -i 's/"9100:5432"/"5433:5432"/g' docker-compose.yml
sed -i 's/"9090:80"/"8081:80"/g' docker-compose.yml
sed -i 's/"8080:6379"/"6380:6379"/g' docker-compose.yml
```

#### Step 4: Remove Pydantic from requirements.txt
```bash
grep -v "pydantic" requirements.txt > requirements_new.txt
mv requirements_new.txt requirements.txt
```

#### Step 5: Test Configuration
```bash
python3 -c "
import sys
sys.path.insert(0, 'src')
from config import config
print('✅ Config works!')
print(f'Database URL: {config.database_url}')
"
```

#### Step 6: Build & Start Fresh
```bash
# Build fresh container
docker-compose build --no-cache route-collector

# Start with fresh database
docker-compose up -d

# Check logs
docker-compose logs route-collector
```

## ✅ Expected Result
- PostgreSQL starts fresh on port 5433
- No Pydantic import errors
- Route collector starts successfully

## 📊 New Ports
- **PostgreSQL**: localhost:5433
- **pgAdmin**: localhost:8081
- **Redis**: localhost:6380

## 🚨 If Still Having Issues
```bash
# Nuclear option - clean everything
docker-compose down -v
docker system prune -af
docker volume prune -f

# Then rebuild
docker-compose build --no-cache
docker-compose up -d
```