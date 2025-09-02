# IMAP Synchronization Service - Operations Makefile
# Convenience targets for build, deploy, test, and management operations

.PHONY: help build start stop restart logs status clean test validate deploy-portainer health check-config

# Default target
help: ## Show this help message
	@echo "IMAP Synchronization Service - Available Commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Quick Start:"
	@echo "  1. cp .env.example .env"
	@echo "  2. Edit .env with your IMAP credentials"
	@echo "  3. make build"
	@echo "  4. make start"
	@echo ""

# Build targets
build: ## Build the Docker image
	@echo "Building IMAP sync Docker image..."
	docker-compose build --no-cache
	@echo "Build completed successfully!"

build-quick: ## Build the Docker image (with cache)
	@echo "Building IMAP sync Docker image (quick)..."
	docker-compose build
	@echo "Build completed successfully!"

# Service management
start: ## Start the IMAP sync service
	@echo "Starting IMAP sync service..."
	docker-compose up -d
	@echo "Service started! Use 'make logs' to view output."

stop: ## Stop the IMAP sync service
	@echo "Stopping IMAP sync service..."
	docker-compose down
	@echo "Service stopped."

restart: ## Restart the IMAP sync service
	@echo "Restarting IMAP sync service..."
	docker-compose restart
	@echo "Service restarted."

# Monitoring and logs
logs: ## Show service logs (follow mode)
	docker-compose logs -f imap-sync

logs-tail: ## Show last 100 lines of logs
	docker-compose logs --tail=100 imap-sync

status: ## Show service status and health
	@echo "=== Service Status ==="
	docker-compose ps
	@echo ""
	@echo "=== Health Check ==="
	@docker-compose exec imap-sync /app/health-check.sh || echo "Health check failed or service not running"
	@echo ""
	@echo "=== Resource Usage ==="
	@docker stats --no-stream imap-sync 2>/dev/null || echo "Service not running"

health: ## Run health check
	@docker-compose exec imap-sync /app/health-check.sh

# Testing and validation
test: ## Run connection tests
	@echo "Testing IMAP connections..."
	@if [ ! -f .env ]; then echo "Error: .env file not found. Copy .env.example to .env and configure it."; exit 1; fi
	docker-compose run --rm imap-sync /bin/bash -c "source /app/sync-script.sh && validate_config && test_connections"

validate: check-config ## Validate configuration (alias for check-config)

check-config: ## Check configuration file
	@echo "Validating configuration..."
	@if [ ! -f .env ]; then echo "Error: .env file not found. Copy .env.example to .env and configure it."; exit 1; fi
	@echo "✓ .env file exists"
	@grep -q "^HOST_1=" .env && echo "✓ HOST_1 configured" || echo "✗ HOST_1 missing"
	@grep -q "^USER_1=" .env && echo "✓ USER_1 configured" || echo "✗ USER_1 missing"
	@grep -q "^PASSWORD_1=" .env && echo "✓ PASSWORD_1 configured" || echo "✗ PASSWORD_1 missing"
	@grep -q "^HOST_2=" .env && echo "✓ HOST_2 configured" || echo "✗ HOST_2 missing"
	@grep -q "^USER_2=" .env && echo "✓ USER_2 configured" || echo "✗ USER_2 missing"
	@grep -q "^PASSWORD_2=" .env && echo "✓ PASSWORD_2 configured" || echo "✗ PASSWORD_2 missing"
	@echo "Configuration check completed."

# Cleanup
clean: ## Clean up containers, images, and volumes
	@echo "Cleaning up Docker resources..."
	docker-compose down -v --remove-orphans
	docker image prune -f
	@echo "Cleanup completed."

clean-all: ## Clean up everything including images
	@echo "Cleaning up all Docker resources..."
	docker-compose down -v --remove-orphans --rmi all
	docker system prune -f
	@echo "Full cleanup completed."

# Development
shell: ## Open shell in running container
	docker-compose exec imap-sync /bin/bash

debug: ## Start service in debug mode with shell access
	docker-compose run --rm imap-sync /bin/bash

# Portainer deployment
deploy-portainer: ## Generate Portainer stack configuration
	@echo "Generating Portainer stack configuration..."
	@echo "Copy the following configuration to Portainer:"
	@echo ""
	@echo "=== DOCKER COMPOSE STACK ==="
	@cat docker-compose.yml
	@echo ""
	@echo "=== ENVIRONMENT VARIABLES ==="
	@echo "Configure these in Portainer's environment variables section:"
	@if [ -f .env ]; then cat .env | grep -v '^#' | grep -v '^$$'; else echo "No .env file found. Use .env.example as reference."; fi
	@echo ""
	@echo "=== DEPLOYMENT NOTES ==="
	@echo "1. Create a new stack in Portainer"
	@echo "2. Paste the Docker Compose configuration above"
	@echo "3. Add environment variables from the list above"
	@echo "4. Deploy the stack"

# Backup and restore
backup: ## Backup logs and data
	@echo "Creating backup..."
	@mkdir -p backups
	@tar -czf backups/imap-sync-backup-$(shell date +%Y%m%d-%H%M%S).tar.gz logs data .env 2>/dev/null || true
	@echo "Backup created in backups/ directory"

# Update
update: ## Update and restart service
	@echo "Updating IMAP sync service..."
	git pull
	make build
	make restart
	@echo "Update completed!"

# Production deployment helpers
prod-deploy: check-config build start ## Deploy to production (check config, build, start)
	@echo "Production deployment completed!"
	@echo "Monitor with: make logs"
	@echo "Check status with: make status"

# Quick status check
quick-status: ## Quick status check
	@docker-compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

# Connection mode setup
setup-idle: ## Switch to IDLE mode (recommended for Gmail)
	@chmod +x setup-connection-mode.sh
	@./setup-connection-mode.sh idle

setup-push: ## Switch to Push mode (requires Google Cloud setup)
	@chmod +x setup-connection-mode.sh
	@./setup-connection-mode.sh push

setup-poll: ## Switch to Poll mode (traditional polling)
	@chmod +x setup-connection-mode.sh
	@./setup-connection-mode.sh poll

connection-help: ## Show connection mode help
	@chmod +x setup-connection-mode.sh
	@./setup-connection-mode.sh help
