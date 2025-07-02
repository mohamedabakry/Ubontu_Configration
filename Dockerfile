# ==================================================
# STABLE PRODUCTION DOCKERFILE
# ==================================================

# Use Python 3.9 - Most stable for network automation
FROM python:3.9.16-slim-bullseye

# Set environment variables for stability
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_NO_CACHE_DIR=1
ENV PIP_DISABLE_PIP_VERSION_CHECK=1

# Install system dependencies - STABLE VERSIONS
RUN apt-get update && apt-get install -y \
    # Build essentials
    gcc=4:10.2.1-1 \
    # PostgreSQL client
    libpq-dev=13.18-0+deb11u1 \
    # Network tools
    openssh-client=1:8.4p1-5+deb11u3 \
    sshpass=1.09-1 \
    telnet=0.17-41.2 \
    iputils-ping=3:20210202-1 \
    netcat-openbsd=1.217-3 \
    # Utilities
    curl=7.74.0-1.3+deb11u13 \
    vim=2:8.2.2434-3+deb11u1 \
    # Cleanup
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Create application directory
WORKDIR /app

# Upgrade pip to stable version and install wheel
RUN pip install --no-cache-dir \
    pip==23.0.1 \
    setuptools==65.6.3 \
    wheel==0.38.4

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY src/ ./src/
COPY inventory/ ./inventory/

# Create .env file template with STABLE configuration
RUN echo "# Database Configuration - STABLE SETTINGS" > .env.example && \
    echo "DB_HOST=postgres" >> .env.example && \
    echo "DB_PORT=5432" >> .env.example && \
    echo "DB_NAME=routing_tables" >> .env.example && \
    echo "DB_USER=postgres" >> .env.example && \
    echo "DB_PASSWORD=postgres" >> .env.example && \
    echo "" >> .env.example && \
    echo "# Collection Configuration" >> .env.example && \
    echo "COLLECTION_INTERVAL=3600" >> .env.example && \
    echo "MAX_WORKERS=10" >> .env.example && \
    echo "TIMEOUT=60" >> .env.example && \
    echo "" >> .env.example && \
    echo "# Logging" >> .env.example && \
    echo "LOG_LEVEL=INFO" >> .env.example && \
    echo "" >> .env.example && \
    echo "# Change Detection" >> .env.example && \
    echo "ENABLE_CHANGE_DETECTION=true" >> .env.example && \
    echo "CHANGE_THRESHOLD=0.1" >> .env.example

# Create stable entrypoint script
RUN echo '#!/bin/bash' > /app/entrypoint.sh && \
    echo 'set -e' >> /app/entrypoint.sh && \
    echo '' >> /app/entrypoint.sh && \
    echo '# Copy environment template if .env does not exist' >> /app/entrypoint.sh && \
    echo 'if [ ! -f /app/.env ]; then' >> /app/entrypoint.sh && \
    echo '    cp /app/.env.example /app/.env' >> /app/entrypoint.sh && \
    echo '    echo "Created .env file from template"' >> /app/entrypoint.sh && \
    echo 'fi' >> /app/entrypoint.sh && \
    echo '' >> /app/entrypoint.sh && \
    echo '# Wait for database with timeout' >> /app/entrypoint.sh && \
    echo 'echo "Waiting for database..."' >> /app/entrypoint.sh && \
    echo 'timeout=60' >> /app/entrypoint.sh && \
    echo 'while ! nc -z $DB_HOST $DB_PORT; do' >> /app/entrypoint.sh && \
    echo '    timeout=$((timeout - 1))' >> /app/entrypoint.sh && \
    echo '    if [ $timeout -le 0 ]; then' >> /app/entrypoint.sh && \
    echo '        echo "Database connection timeout!"' >> /app/entrypoint.sh && \
    echo '        exit 1' >> /app/entrypoint.sh && \
    echo '    fi' >> /app/entrypoint.sh && \
    echo '    sleep 1' >> /app/entrypoint.sh && \
    echo 'done' >> /app/entrypoint.sh && \
    echo 'echo "Database is ready!"' >> /app/entrypoint.sh && \
    echo '' >> /app/entrypoint.sh && \
    echo '# Initialize database if needed' >> /app/entrypoint.sh && \
    echo 'python -m src.cli init-db' >> /app/entrypoint.sh && \
    echo '' >> /app/entrypoint.sh && \
    echo '# Execute the command passed to docker run' >> /app/entrypoint.sh && \
    echo 'exec "$@"' >> /app/entrypoint.sh && \
    chmod +x /app/entrypoint.sh

# Set the entrypoint
ENTRYPOINT ["/app/entrypoint.sh"]

# Default command
CMD ["python", "-m", "src.cli", "scheduler"]

# Health check with proper timeout
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD python -c "import sys; sys.path.append('/app'); from src.database import db_manager; db_manager.initialize(); print('OK')" || exit 1

# Expose port for potential web interface
EXPOSE 9090

# Labels for maintainability
LABEL maintainer="Network Automation Team"
LABEL description="Multi-vendor routing table collector - STABLE VERSION"
LABEL version="1.0.0-stable"
LABEL python.version="3.9.16"