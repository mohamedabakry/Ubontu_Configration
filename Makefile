# Route Table Collector Makefile
# Provides common tasks for development and deployment

.PHONY: help build run stop logs clean test lint format install dev-install docker-build docker-run docker-stop

# Default target
help:
	@echo "Route Table Collector - Available Commands:"
	@echo ""
	@echo "Development:"
	@echo "  install      - Install production dependencies"
	@echo "  dev-install  - Install development dependencies"
	@echo "  test         - Run tests"
	@echo "  lint         - Run linting (flake8)"
	@echo "  format       - Format code (black)"
	@echo "  clean        - Clean up temporary files"
	@echo ""
	@echo "Docker:"
	@echo "  docker-build - Build Docker image"
	@echo "  docker-run   - Run with docker-compose"
	@echo "  docker-stop  - Stop docker-compose services"
	@echo "  docker-logs  - View docker-compose logs"
	@echo "  docker-clean - Clean up Docker resources"
	@echo ""
	@echo "Application:"
	@echo "  init-db      - Initialize database"
	@echo "  collect      - Run one-time collection"
	@echo "  scheduler    - Start scheduler"
	@echo "  shell        - Open application shell"
	@echo ""
	@echo "Database:"
	@echo "  db-shell     - Open PostgreSQL shell"
	@echo "  db-backup    - Backup database"
	@echo "  db-restore   - Restore database"

# Development commands
install:
	pip install -r requirements.txt

dev-install:
	pip install -r requirements.txt
	pip install pytest pytest-cov black flake8 mypy pre-commit

test:
	pytest tests/ -v --cov=src --cov-report=term-missing

lint:
	flake8 src/ --max-line-length=100 --ignore=E203,W503
	mypy src/ --ignore-missing-imports

format:
	black src/ --line-length=100
	black tests/ --line-length=100

clean:
	find . -type f -name "*.pyc" -delete
	find . -type d -name "__pycache__" -delete
	find . -type d -name "*.egg-info" -exec rm -rf {} +
	rm -rf .pytest_cache/
	rm -rf .coverage
	rm -rf dist/
	rm -rf build/

# Docker commands
docker-build:
	docker-compose build

docker-run:
	docker-compose up -d

docker-stop:
	docker-compose down

docker-logs:
	docker-compose logs -f route-collector

docker-clean:
	docker-compose down -v
	docker system prune -f
	docker volume prune -f

# Application commands (using Docker)
init-db:
	docker-compose exec route-collector python -m src.cli init-db

collect:
	docker-compose exec route-collector python -m src.cli collect

collect-device:
	@read -p "Enter device hostname: " device; \
	docker-compose exec route-collector python -m src.cli collect --device $$device

scheduler:
	docker-compose exec route-collector python -m src.cli scheduler

shell:
	docker-compose exec route-collector bash

# Application commands (local)
local-init-db:
	python main.py init-db

local-collect:
	python main.py collect

local-scheduler:
	python main.py scheduler

# Database commands
db-shell:
	docker-compose exec postgres psql -U postgres -d routing_tables

db-backup:
	@mkdir -p backups
	docker-compose exec postgres pg_dump -U postgres routing_tables > backups/backup_$(shell date +%Y%m%d_%H%M%S).sql

db-restore:
	@read -p "Enter backup file path: " backup_file; \
	docker-compose exec -T postgres psql -U postgres -d routing_tables < $$backup_file

# Environment setup
setup-env:
	cp .env.example .env
	@echo "Please edit .env file with your configuration"

setup-inventory:
	@if [ ! -f inventory/hosts.yaml ]; then \
		echo "Creating inventory/hosts.yaml from template"; \
		cp inventory/hosts.yaml inventory/hosts.yaml.bak 2>/dev/null || true; \
	fi
	@echo "Please edit inventory files with your device information"

# Development setup
dev-setup: dev-install setup-env setup-inventory
	@echo "Development environment setup complete!"
	@echo "Next steps:"
	@echo "1. Edit .env file with your configuration"
	@echo "2. Edit inventory files with your device information"
	@echo "3. Run 'make docker-run' to start services"

# Quick start
quickstart: setup-env setup-inventory docker-build docker-run
	@echo "Quick start complete!"
	@echo "Services are starting up..."
	@echo "Run 'make docker-logs' to view logs"
	@echo "Run 'make init-db' to initialize database"

# Monitoring
status:
	docker-compose ps

health:
	docker-compose exec route-collector python -c "from src.database import db_manager; db_manager.initialize(); print('Database connection: OK')"

# Maintenance
update:
	git pull
	docker-compose build --no-cache
	docker-compose up -d

restart:
	docker-compose restart route-collector

# Export/Import
export-routes:
	@mkdir -p exports
	docker-compose exec route-collector python -m src.cli export --output /app/exports/routes_$(shell date +%Y%m%d_%H%M%S).json --format json

export-csv:
	@mkdir -p exports
	docker-compose exec route-collector python -m src.cli export --output /app/exports/routes_$(shell date +%Y%m%d_%H%M%S).csv --format csv

# Security
security-scan:
	docker run --rm -v $(PWD):/app pyupio/safety safety check -r /app/requirements.txt

# Documentation
docs:
	@echo "Opening documentation..."
	@echo "README: file://$(PWD)/README.md"

# Version management
version:
	@echo "Current version: $(shell grep '__version__' src/__init__.py | cut -d'"' -f2)"

# Build for production
prod-build:
	docker build -t route-collector:latest .
	docker tag route-collector:latest route-collector:$(shell date +%Y%m%d)

# Deploy to production (customize as needed)
deploy:
	@echo "Deploying to production..."
	docker-compose -f docker-compose.prod.yml up -d

# Kubernetes
k8s-deploy:
	kubectl apply -f k8s/

k8s-delete:
	kubectl delete -f k8s/

# Performance testing
perf-test:
	docker-compose exec route-collector python -m src.cli collect --dry-run
	@echo "Check logs for performance metrics"