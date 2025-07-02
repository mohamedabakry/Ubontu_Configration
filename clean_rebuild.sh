#!/bin/bash

echo "🧹 CLEAN REBUILD - No Pydantic, Fixed Ports"
echo "============================================"

# Verify configuration first
echo "1. Verifying configuration..."
python3 test_config_simple.py
if [ $? -ne 0 ]; then
    echo "❌ Configuration test failed!"
    exit 1
fi

# Stop and clean
echo "2. Stopping containers..."
docker-compose down -v 2>/dev/null || docker compose down -v 2>/dev/null || echo "No containers to stop"

# Remove old images
echo "3. Removing old images..."
docker rmi -f $(docker images | grep route-collector | awk '{print $3}') 2>/dev/null || echo "No old images"

# Clean Python cache
echo "4. Cleaning Python cache..."
find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
find . -name "*.pyc" -delete 2>/dev/null || true

# Build fresh
echo "5. Building container..."
docker-compose build --no-cache route-collector

if [ $? -ne 0 ]; then
    echo "❌ Build failed!"
    exit 1
fi

# Start services
echo "6. Starting services..."
docker-compose up -d

# Wait and check
echo "7. Waiting for startup..."
sleep 15

echo "8. Checking logs..."
docker-compose logs --tail=20 route-collector

echo ""
echo "✅ REBUILD COMPLETE!"
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