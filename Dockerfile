FROM python:3.11-slim

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    libpq-dev \
    openssh-client \
    sshpass \
    telnet \
    iputils-ping \
    curl \
    vim \
    && rm -rf /var/lib/apt/lists/*

# Create application directory
WORKDIR /app

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY src/ ./src/
COPY inventory/ ./inventory/

# Create .env file template
RUN echo "# Database Configuration" > .env.example && \
    echo "DB_HOST=postgres" >> .env.example && \
    echo "DB_PORT=9100" >> .env.example && \
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

# Create entrypoint script
RUN echo '#!/bin/bash' > /app/entrypoint.sh && \
    echo 'set -e' >> /app/entrypoint.sh && \
    echo '' >> /app/entrypoint.sh && \
    echo '# Copy environment template if .env does not exist' >> /app/entrypoint.sh && \
    echo 'if [ ! -f /app/.env ]; then' >> /app/entrypoint.sh && \
    echo '    cp /app/.env.example /app/.env' >> /app/entrypoint.sh && \
    echo '    echo "Created .env file from template"' >> /app/entrypoint.sh && \
    echo 'fi' >> /app/entrypoint.sh && \
    echo '' >> /app/entrypoint.sh && \
    echo '# Wait for database' >> /app/entrypoint.sh && \
    echo 'echo "Waiting for database..."' >> /app/entrypoint.sh && \
    echo 'while ! nc -z $DB_HOST $DB_PORT; do' >> /app/entrypoint.sh && \
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

# Install netcat for database health check
RUN apt-get update && apt-get install -y netcat-traditional && rm -rf /var/lib/apt/lists/*

# Set the entrypoint
ENTRYPOINT ["/app/entrypoint.sh"]

# Default command
CMD ["python", "-m", "src.cli", "scheduler"]

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD python -c "import sys; sys.path.append('/app'); from src.database import db_manager; db_manager.initialize(); print('OK')" || exit 1

# Expose port for potential web interface (future enhancement)
EXPOSE 9090

# Labels
LABEL maintainer="Network Automation Team"
LABEL description="Multi-vendor routing table collector"
LABEL version="1.0.0"