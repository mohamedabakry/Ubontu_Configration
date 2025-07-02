#!/bin/bash

echo "🔍 VERIFY FRESH FILES - Check Repository Status"
echo "=============================================="

# Step 1: Check Git status and branch
echo "1. Git Repository Status:"
echo "   📁 Current directory: $(pwd)"
echo "   🌿 Current branch: $(git branch --show-current 2>/dev/null || echo 'Not a git repository')"
echo "   📊 Git status:"
git status --porcelain 2>/dev/null | head -10 || echo "   No git repository found"
echo ""

# Step 2: Check when files were last modified
echo "2. File Modification Times:"
echo "   📄 requirements.txt: $(stat -c '%y' requirements.txt 2>/dev/null || echo 'File not found')"
echo "   📄 Dockerfile: $(stat -c '%y' Dockerfile 2>/dev/null || echo 'File not found')"
echo "   📄 docker-compose.yml: $(stat -c '%y' docker-compose.yml 2>/dev/null || echo 'File not found')"
echo "   📄 src/config.py: $(stat -c '%y' src/config.py 2>/dev/null || echo 'File not found')"
echo ""

# Step 3: Check requirements.txt content
echo "3. Current requirements.txt content:"
if [ -f requirements.txt ]; then
    echo "   📦 First 10 lines:"
    head -10 requirements.txt | sed 's/^/   /'
    echo "   📊 Total lines: $(wc -l < requirements.txt)"
    
    # Check for problematic packages
    if grep -q "nornir-netmiko==0.1.2" requirements.txt; then
        echo "   ❌ OLD VERSION: Found nornir-netmiko==0.1.2 (causes conflicts)"
    else
        echo "   ✅ Good: No old nornir-netmiko==0.1.2 found"
    fi
    
    if grep -q "pydantic" requirements.txt; then
        echo "   ❌ PYDANTIC: Found pydantic dependencies (should be removed)"
    else
        echo "   ✅ Good: No pydantic dependencies found"
    fi
else
    echo "   ❌ requirements.txt not found!"
fi
echo ""

# Step 4: Check config.py content
echo "4. Current config.py content:"
if [ -f src/config.py ]; then
    echo "   📄 First 5 lines:"
    head -5 src/config.py | sed 's/^/   /'
    
    if grep -q "from pydantic import" src/config.py; then
        echo "   ❌ OLD VERSION: Found pydantic imports in config.py"
    else
        echo "   ✅ Good: No pydantic imports in config.py"
    fi
    
    if grep -q "class SimpleConfig" src/config.py; then
        echo "   ✅ Good: Found SimpleConfig class (new version)"
    else
        echo "   ❌ Missing SimpleConfig class"
    fi
else
    echo "   ❌ src/config.py not found!"
fi
echo ""

# Step 5: Check Docker images
echo "5. Docker Images Status:"
echo "   🐳 Route collector images:"
docker images | grep -E "(route-collector|ubontu_configration)" | sed 's/^/   /' || echo "   No route collector images found"
echo ""

# Step 6: Check Docker build cache
echo "6. Docker Build Cache:"
echo "   🗂️  Build cache size:"
docker system df | grep "Build Cache" | sed 's/^/   /' || echo "   No build cache info available"
echo ""

# Step 7: Check if containers are using old code
echo "7. Running Containers:"
if docker ps --filter "name=ubontu_configration" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" | grep -v NAMES | wc -l | grep -q "0"; then
    echo "   📦 No route collector containers running"
else
    echo "   📦 Running containers:"
    docker ps --filter "name=ubontu_configration" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" | sed 's/^/   /'
fi
echo ""

# Step 8: Provide recommendations
echo "8. Verification Results:"
echo ""

# Check if this looks like a fresh repository
FRESH_INDICATORS=0
PROBLEM_INDICATORS=0

if [ -f requirements.txt ] && ! grep -q "nornir-netmiko==0.1.2" requirements.txt; then
    FRESH_INDICATORS=$((FRESH_INDICATORS + 1))
else
    PROBLEM_INDICATORS=$((PROBLEM_INDICATORS + 1))
    echo "   ❌ requirements.txt contains old conflicting versions"
fi

if [ -f src/config.py ] && ! grep -q "from pydantic import" src/config.py; then
    FRESH_INDICATORS=$((FRESH_INDICATORS + 1))
else
    PROBLEM_INDICATORS=$((PROBLEM_INDICATORS + 1))
    echo "   ❌ config.py still has pydantic imports"
fi

if [ $FRESH_INDICATORS -gt $PROBLEM_INDICATORS ]; then
    echo "   ✅ LOOKS FRESH: Repository appears to have updated files"
    echo ""
    echo "🚀 Next Steps:"
    echo "   1. Run: docker-compose down -v"
    echo "   2. Run: docker system prune -f"
    echo "   3. Run: docker-compose build --no-cache route-collector"
    echo "   4. Run: docker-compose up -d"
else
    echo "   ❌ OLD FILES: Repository still has old/problematic files"
    echo ""
    echo "🔧 To Get Fresh Files:"
    echo "   1. cd .."
    echo "   2. rm -rf $(basename $(pwd))"
    echo "   3. git clone https://github.com/mohamedabakry/Ubontu_Configration/"
    echo "   4. cd Ubontu_Configration"
    echo "   5. git checkout cursor/update-import-paths-and-replace-ports-1ad6"
    echo "   6. Run the fix script"
fi

echo ""
echo "📋 File Verification Commands:"
echo "   Check requirements.txt: head -10 requirements.txt"
echo "   Check config.py: head -10 src/config.py"
echo "   Check for pydantic: grep -r pydantic src/"
echo "   Check Docker cache: docker system df"
echo "   Force clean rebuild: docker-compose build --no-cache --pull"