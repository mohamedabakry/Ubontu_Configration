#!/bin/bash

echo "🔥 COMPLETE REBUILD - Removing ALL Docker artifacts and rebuilding from scratch..."

# Stop and remove everything related to this project
echo "1. Stopping all containers..."
docker-compose down --remove-orphans --volumes

echo "2. Removing project containers..."
docker-compose rm -f -v

echo "3. Removing project images..."
PROJECT_IMAGES=$(docker images --format "table {{.Repository}}:{{.Tag}}" | grep -E "(ubontu|route|collector)" | awk '{print $1}')
if [ ! -z "$PROJECT_IMAGES" ]; then
    echo "Found project images: $PROJECT_IMAGES"
    docker rmi -f $PROJECT_IMAGES 2>/dev/null || true
fi

echo "4. Removing ALL unused images..."
docker image prune -a -f

echo "5. Removing ALL build cache..."
docker builder prune -a -f

echo "6. Removing ALL system cache..."
docker system prune -a -f --volumes

echo "7. Current Docker state (should be clean):"
docker images | head -5
docker ps -a | head -5

echo ""
echo "8. Building with fresh Python 3.9 and stable dependencies..."
docker-compose build --no-cache --pull --force-rm

echo "9. Starting containers..."
docker-compose up -d

echo "10. Waiting for startup..."
sleep 10

echo "11. Container status:"
docker-compose ps

echo ""
echo "12. Checking application logs..."
docker-compose logs route-collector | tail -15

echo ""
echo "✅ COMPLETE REBUILD FINISHED!"
echo ""
echo "📊 Services should now be available on:"
echo "  🗄️  PostgreSQL: localhost:9100"
echo "  🔴 Redis: localhost:8080" 
echo "  🌐 pgAdmin: localhost:9090"
echo ""
echo "📝 Monitor with: docker-compose logs -f route-collector"