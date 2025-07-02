#!/bin/bash

echo "🚨 EMERGENCY REBUILD - Clearing ALL Docker cache and rebuilding"
echo "=============================================================="

# Stop everything
echo "1. Stopping all containers..."
docker compose down --remove-orphans --volumes

# Nuclear option - remove EVERYTHING Docker related
echo "2. NUCLEAR CLEANUP - Removing all Docker artifacts..."
docker system prune -a -f --volumes
docker builder prune -a -f

# Show current requirements
echo "3. Current requirements.txt:"
echo "----------------------------"
cat requirements.txt
echo "----------------------------"

# Verify no NAPALM in requirements
if grep -q "napalm" requirements.txt; then
    echo "❌ ERROR: NAPALM still found in requirements.txt!"
    echo "Removing NAPALM..."
    sed -i '/napalm/d' requirements.txt
    echo "✅ NAPALM removed"
else
    echo "✅ No NAPALM found in requirements.txt"
fi

# Build with maximum verbosity and no cache
echo "4. Building with ultra-minimal requirements..."
docker compose build --no-cache --pull --progress=plain

# Start services
echo "5. Starting services..."
docker compose up -d

# Check logs immediately
echo "6. Checking logs..."
sleep 5
docker compose logs route-collector

echo ""
echo "✅ EMERGENCY REBUILD COMPLETE!"
echo "If this still fails, the issue might be in a cached Docker layer."
echo "Try: docker system prune -a -f && docker volume prune -f"