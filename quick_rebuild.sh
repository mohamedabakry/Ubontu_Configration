#!/bin/bash

echo "🔧 QUICK REBUILD - No Pydantic Dependencies"
echo "=============================================="

# Stop containers
echo "1. Stopping containers..."
docker-compose down 2>/dev/null || docker compose down 2>/dev/null || echo "No containers running"

# Remove old images
echo "2. Removing old images..."
docker-compose rm -f 2>/dev/null || docker compose rm -f 2>/dev/null || echo "No images to remove"
docker rmi $(docker images -q route-collector_route-collector) 2>/dev/null || echo "No old images found"

# Build without cache
echo "3. Building fresh container..."
docker-compose build --no-cache route-collector 2>/dev/null || docker compose build --no-cache route-collector 2>/dev/null

# Start services
echo "4. Starting services..."
docker-compose up -d 2>/dev/null || docker compose up -d 2>/dev/null

# Show logs
echo "5. Checking logs..."
sleep 5
docker-compose logs route-collector 2>/dev/null || docker compose logs route-collector 2>/dev/null

echo ""
echo "✅ REBUILD COMPLETE!"
echo "📊 Monitor logs: docker-compose logs -f route-collector"
echo "🛑 Stop: docker-compose down"