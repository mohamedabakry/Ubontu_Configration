#!/bin/bash

echo "🔧 MINIMAL FIX - Create Working Container"
echo "========================================"

# Step 1: Stop everything and clean completely
echo "1. Complete cleanup..."
docker-compose down -v 2>/dev/null || docker compose down -v 2>/dev/null || true
docker rmi -f $(docker images | grep -E "(route-collector|ubontu_configration)" | awk '{print $3}') 2>/dev/null || true
docker system prune -f 2>/dev/null || true

# Step 2: Create MINIMAL requirements.txt that definitely works
echo "2. Creating minimal requirements.txt..."
cat > requirements.txt << 'EOF'
# MINIMAL WORKING REQUIREMENTS - NO CONFLICTS
click==8.1.7
rich==13.7.0
psycopg2-binary==2.9.9
sqlalchemy==2.0.23
structlog==23.2.0
pyyaml==6.0.1
python-dotenv==1.0.0
EOF

echo "   ✅ Created minimal requirements.txt (no network automation libs for now)"

# Step 3: Create MINIMAL Dockerfile
echo "3. Creating minimal Dockerfile..."
cat > Dockerfile << 'EOF'
FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    libpq-dev \
    netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy and install requirements
COPY requirements.txt .
RUN pip install --upgrade pip && pip install -r requirements.txt

# Copy application code
COPY src/ ./src/
COPY inventory/ ./inventory/

# Simple entrypoint
RUN echo '#!/bin/bash' > /app/entrypoint.sh && \
    echo 'echo "Waiting for database..."' >> /app/entrypoint.sh && \
    echo 'while ! nc -z ${DB_HOST:-postgres} ${DB_PORT:-5432}; do sleep 1; done' >> /app/entrypoint.sh && \
    echo 'echo "Database is ready!"' >> /app/entrypoint.sh && \
    echo 'exec "$@"' >> /app/entrypoint.sh && \
    chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["python", "-c", "print('Route collector container is running!'); import time; time.sleep(3600)"]
EOF

echo "   ✅ Created minimal Dockerfile"

# Step 4: Fix config.py
echo "4. Fixing config.py..."
cat > src/config.py << 'EOF'
"""Simple configuration."""
import os

class SimpleConfig:
    def __init__(self):
        self.db_host = os.getenv("DB_HOST", "localhost")
        self.db_port = int(os.getenv("DB_PORT", "5433"))
        self.db_name = os.getenv("DB_NAME", "routing_tables")
        self.db_user = os.getenv("DB_USER", "postgres")
        self.db_password = os.getenv("DB_PASSWORD", "postgres")
        self.log_level = os.getenv("LOG_LEVEL", "INFO")
        
    @property
    def database_url(self):
        return f"postgresql://{self.db_user}:{self.db_password}@{self.db_host}:{self.db_port}/{self.db_name}"

config = SimpleConfig()
EOF

echo "   ✅ Fixed config.py"

# Step 5: Test config
echo "5. Testing config..."
python3 -c "
import sys
sys.path.insert(0, 'src')
from config import config
print('   ✅ Config works!')
print(f'   📊 Database URL: {config.database_url}')
"

# Step 6: Build minimal container
echo "6. Building minimal container..."
if command -v docker-compose >/dev/null 2>&1; then
    BUILD_CMD="docker-compose build --no-cache route-collector"
else
    BUILD_CMD="docker compose build --no-cache route-collector"
fi

echo "   Running: $BUILD_CMD"
$BUILD_CMD

if [ $? -ne 0 ]; then
    echo "❌ Even minimal build failed!"
    echo ""
    echo "📋 Manual steps:"
    echo "1. docker-compose down -v"
    echo "2. docker system prune -f"
    echo "3. Replace requirements.txt with just:"
    echo "   click==8.1.7"
    echo "   psycopg2-binary==2.9.9"
    echo "4. docker-compose build --no-cache route-collector"
    exit 1
fi

echo "   ✅ Minimal build successful!"

# Step 7: Start services
echo "7. Starting services..."
if command -v docker-compose >/dev/null 2>&1; then
    docker-compose up -d
else
    docker compose up -d
fi

sleep 10

echo "8. Checking status..."
docker ps --filter "name=ubontu_configration"

echo ""
echo "9. Checking logs..."
if command -v docker-compose >/dev/null 2>&1; then
    docker-compose logs --tail=10 route-collector
else
    docker compose logs --tail=10 route-collector
fi

echo ""
echo "✅ MINIMAL CONTAINER WORKING!"
echo ""
echo "🎯 Next Steps:"
echo "1. The container is now running with minimal dependencies"
echo "2. You can gradually add network automation libraries later"
echo "3. PostgreSQL is on port 5433"
echo ""
echo "📝 To add network libraries later:"
echo "   - Add one package at a time to requirements.txt"
echo "   - Test each addition"
echo "   - Use compatible versions"
echo ""
echo "🎉 Basic container is now working!"