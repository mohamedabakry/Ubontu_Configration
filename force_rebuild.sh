#!/bin/bash

echo "🔥 FORCE REBUILDING Docker containers (clearing ALL caches)..."

# Stop all containers
echo "1. Stopping all containers..."
docker-compose down --remove-orphans

# Remove containers
echo "2. Removing containers..."
docker-compose rm -f

# Remove images related to this project
echo "3. Removing project images..."
docker rmi $(docker images -q "*route*" "*collector*" "*ubontu*") 2>/dev/null || true

# Remove ALL build cache (nuclear option)
echo "4. Clearing ALL Docker build cache..."
docker builder prune -a -f

# Remove dangling images
echo "5. Removing dangling images..."
docker image prune -f

# Show current Docker state
echo "6. Current Docker state:"
docker images | head -5
echo ""

# Force rebuild with no cache
echo "7. Building with NO CACHE..."
docker-compose build --no-cache --pull

# Start containers
echo "8. Starting containers..."
docker-compose up -d

# Wait a moment for startup
sleep 5

# Show status
echo "9. Container status:"
docker-compose ps

echo ""
echo "10. Checking logs for errors..."
docker-compose logs route-collector | tail -20

echo ""
echo "✅ FORCE REBUILD COMPLETE!"
echo ""
echo "📊 Services should now be available on:"
echo "  🗄️  PostgreSQL: localhost:9100"
echo "  🔴 Redis: localhost:8080" 
echo "  🌐 pgAdmin: localhost:9090"
echo ""
echo "📝 To monitor: docker-compose logs -f route-collector"