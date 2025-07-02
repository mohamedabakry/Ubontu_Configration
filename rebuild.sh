#!/bin/bash

echo "🔧 Rebuilding Docker containers with Pydantic fixes..."

# Stop all running containers
echo "Stopping containers..."
docker-compose down

# Remove any existing images to force rebuild
echo "Removing old images..."
docker-compose rm -f
docker rmi $(docker images -q --filter "reference=*route*" --filter "reference=*collector*") 2>/dev/null || true

# Clear Docker build cache
echo "Clearing build cache..."
docker builder prune -f

# Rebuild and start containers
echo "Building and starting containers..."
docker-compose build --no-cache
docker-compose up -d

# Show container status
echo "Container status:"
docker-compose ps

echo "✅ Rebuild complete!"
echo ""
echo "📊 Your services are now available on:"
echo "  🗄️  PostgreSQL: localhost:9100"
echo "  🔴 Redis: localhost:8080" 
echo "  🌐 pgAdmin: localhost:9090"
echo ""
echo "📝 To view logs: docker-compose logs -f"