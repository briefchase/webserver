# Variables

DOCKER_COMPOSE_VERSION := 2.20.3
DOCKER_COMPOSE_PATH := /usr/local/bin/docker-compose
EXTERNAL_DOMAIN := briefchase.com
EMAIL := chaseglong@gmail.com

# Main targets

go: clean setup run
live: clean setup run-detached
clean: clean-config

# Helper targets

setup: install-docker install-docker-compose verify-docker create-traefik-config create-acme-json create-docker-compose

run:
	@docker-compose up
	@$(MAKE) adjust-perms

run-detached:
	@docker-compose up -d
	@$(MAKE) adjust-perms

install-docker:
	@echo "Checking for Docker installation..."
	@if [ -x "$$(command -v docker)" ]; then \
		echo "Docker is already installed"; \
	else \
		if [ ! -f "./get-docker.sh" ]; then \
			echo "Downloading get-docker.sh..."; \
			curl -fsSL https://get.docker.com -o get-docker.sh; \
		fi; \
		echo "Making get-docker.sh executable..."; \
		chmod +x get-docker.sh; \
		echo "Running get-docker.sh..."; \
		sudo ./get-docker.sh; \
	fi

install-docker-compose:
	@echo "Installing/upgrading Docker Compose to version $(DOCKER_COMPOSE_VERSION)..."
	@sudo curl -L "https://github.com/docker/compose/releases/download/v$(DOCKER_COMPOSE_VERSION)/docker-compose-$$(uname -s)-$$(uname -m)" -o $(DOCKER_COMPOSE_PATH)
	@sudo chmod +x $(DOCKER_COMPOSE_PATH)
	@echo "Docker Compose installed/upgraded."

verify-docker:
	@docker --version
	@docker-compose --version

create-traefik-config:
	@echo "Creating Traefik configuration..."
	@mkdir -p traefik
	@cp traefik/traefik.template.toml traefik/traefik.toml
	@sed -i 's/{{EMAIL}}/$(EMAIL)/g' traefik/traefik.toml
	@sed -i 's/{{EXTERNAL_DOMAIN}}/$(EXTERNAL_DOMAIN)/g' traefik/traefik.toml
	@echo "Traefik configuration created."

create-acme-json:
	@echo "Creating acme.json file..."
	@touch traefik/acme.json
	@chmod 600 traefik/acme.json
	@echo "acme.json file created with correct permissions."

create-docker-compose:
	@echo "Creating docker-compose.yml..."
	@cp docker-compose.template.yml docker-compose.yml
	@sed -i 's/{{EXTERNAL_DOMAIN}}/$(EXTERNAL_DOMAIN)/g' docker-compose.yml
	@echo "docker-compose.yml created."

adjust-perms:
	@echo "Adjusting permissions inside the Traefik container..."
	@docker exec traefik_container chmod 600 /etc/traefik/acme.json
	@echo "Permissions adjusted."

clean-config:
	@echo "Cleaning up configuration files..."
	@rm -f traefik/traefik.toml
	@rm -f traefik/acme.json
	@rm -f docker-compose.yml
	@echo "Configuration files removed."

docker-clean:
	@echo "Stopping and removing all Docker containers..."
	@docker-compose down --rmi all --volumes --remove-orphans
	@echo "Docker environment cleaned up."

docker-nuke:
	@echo "Removing all Docker data..."
	@docker system prune -a -f --volumes
	@echo "Docker system pruned."
