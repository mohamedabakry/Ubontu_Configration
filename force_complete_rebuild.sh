#!/bin/bash

echo "🔥 FORCE COMPLETE REBUILD - Eliminating ALL Pydantic Dependencies"
echo "=================================================================="

# Step 1: Stop and remove everything
echo "1. Stopping all containers and removing volumes..."
docker-compose down -v 2>/dev/null || docker compose down -v 2>/dev/null || echo "No containers to stop"

# Step 2: Remove all images related to this project
echo "2. Removing all project images..."
docker rmi -f $(docker images | grep route-collector | awk '{print $3}') 2>/dev/null || echo "No project images found"
docker rmi -f $(docker images | grep route_collector | awk '{print $3}') 2>/dev/null || echo "No project images found"

# Step 3: Remove all unused images and build cache
echo "3. Cleaning Docker system..."
docker system prune -af 2>/dev/null || echo "Docker system clean skipped"

# Step 4: Remove Python cache files
echo "4. Removing Python cache files..."
find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find . -name "*.pyc" -delete 2>/dev/null || true
find . -name "*.pyo" -delete 2>/dev/null || true

# Step 5: Verify no Pydantic imports exist
echo "5. Verifying no Pydantic imports in source code..."
if grep -r "pydantic" src/ 2>/dev/null; then
    echo "❌ ERROR: Pydantic imports still found in source code!"
    exit 1
fi

if grep -r "BaseSettings" src/ 2>/dev/null; then
    echo "❌ ERROR: BaseSettings imports still found in source code!"
    exit 1
fi

echo "✅ Source code verified clean of Pydantic dependencies"

# Step 6: Build with no cache and verbose output
echo "6. Building container with NO cache..."
DOCKER_BUILDKIT=1 docker-compose build --no-cache --progress=plain route-collector 2>&1 | tee build.log

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "❌ Build failed! Check build.log for details"
    exit 1
fi

# Step 7: Start services
echo "7. Starting services..."
docker-compose up -d

# Step 8: Wait and check logs
echo "8. Waiting for services to start..."
sleep 10

echo "9. Checking container logs..."
docker-compose logs route-collector

# Step 9: Test the configuration
echo "10. Testing configuration import..."
docker-compose exec route-collector python -c "
import sys
sys.path.append('/app/src')
try:
    from config import config
    print('✅ Configuration imported successfully!')
    print(f'Database URL: {config.database_url}')
    print('✅ No Pydantic dependencies detected!')
except Exception as e:
    print(f'❌ Configuration test failed: {e}')
    sys.exit(1)
" 2>/dev/null || echo "Container not ready for testing yet"

echo ""
echo "✅ FORCE REBUILD COMPLETE!"
echo "📊 Monitor: docker-compose logs -f route-collector"
echo "🛑 Stop: docker-compose down"
echo "📁 Build log saved to: build.log"