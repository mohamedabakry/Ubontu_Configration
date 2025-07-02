#!/bin/bash

echo "🔧 STABLE VERSION REBUILD - Using proven stable dependencies"
echo "=================================================="

# Display versions being used
echo "📋 STABLE VERSIONS:"
echo "   🐍 Python: 3.9.16"
echo "   🗄️  PostgreSQL: 13.18-alpine"
echo "   🔴 Redis: 7.0.15-alpine"
echo "   🌐 pgAdmin: 8.5"
echo "   📦 SQLAlchemy: 1.4.46"
echo "   🌐 Nornir: 3.3.0"
echo "   🔧 No Pydantic (using dataclasses)"
echo ""

# Stop everything
echo "1. Stopping all containers..."
docker-compose down --remove-orphans

# Remove project-specific containers and images
echo "2. Removing old project artifacts..."
docker-compose rm -f
docker rmi $(docker images -q "*route*" "*collector*" "*ubontu*") 2>/dev/null || true

# Clear build cache
echo "3. Clearing Docker build cache..."
docker builder prune -f

# Build with stable versions
echo "4. Building with stable dependencies (no cache)..."
docker-compose build --no-cache --pull

# Start services
echo "5. Starting services..."
docker-compose up -d

# Wait for startup
echo "6. Waiting for services to start..."
sleep 15

# Check status
echo "7. Service status:"
docker-compose ps

echo ""
echo "8. Checking application logs..."
docker-compose logs route-collector | tail -10

echo ""
echo "✅ STABLE REBUILD COMPLETE!"
echo ""
echo "📊 Services available on:"
echo "   🗄️  PostgreSQL: localhost:9100"
echo "   🔴 Redis: localhost:8080"
echo "   🌐 pgAdmin: localhost:9090"
echo ""
echo "📝 Monitor: docker-compose logs -f route-collector"
echo "🔧 Stop: docker-compose down"