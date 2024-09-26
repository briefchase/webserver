# Variables

DOCKER_COMPOSE_VERSION := 2.20.3
DOCKER_COMPOSE_PATH := /usr/local/bin/docker-compose
EXTERNAL_DOMAIN := briefchase.com
EMAIL := chaseglong@gmail.com

# Main targets

go: clean setup run
live: clean setup run-detached
clean: stop clean-config docker-nuke

# Helper targets

setup: install-docker install-docker-compose verify-docker create-traefik-config create-acme-json create-docker-compose

run:
	@sudo docker-compose up
	@$(MAKE) adjust-perms

run-detached:
	@sudo docker-compose up -d
	@$(MAKE) adjust-perms

stop:
	@echo "Stopping all running containers..."
	@sudo docker-compose down
	@echo "All services stopped."

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
	@sudo docker --version
	@sudo docker-compose --version

create-traefik-config:
	@echo "Creating Traefik configuration..."
	@sudo mkdir -p traefik
	@sudo cp traefik/traefik.template.toml traefik/traefik.toml
	@sudo sed -i 's/{{EMAIL}}/$(EMAIL)/g' traefik/traefik.toml
	@sudo sed -i 's/{{EXTERNAL_DOMAIN}}/$(EXTERNAL_DOMAIN)/g' traefik/traefik.toml
	@echo "Traefik configuration created."

create-acme-json:
	@echo "Creating acme.json file..."
	@sudo touch traefik/acme.json
	@sudo chmod 600 traefik/acme.json
	@echo "acme.json file created with correct permissions."

create-docker-compose:
	@echo "Creating docker-compose.yml..."
	@sudo cp docker-compose.template.yml docker-compose.yml
	@sudo sed -i 's/{{EXTERNAL_DOMAIN}}/$(EXTERNAL_DOMAIN)/g' docker-compose.yml
	@echo "docker-compose.yml created."

adjust-perms:
	@echo "Adjusting permissions inside the Traefik container..."
	@sudo docker exec traefik_container chmod 600 /etc/traefik/acme.json
	@echo "Permissions adjusted."

clean-config:
	@echo "Cleaning up configuration files..."
	@sudo rm -f traefik/traefik.toml
	@sudo rm -f traefik/acme.json
	@sudo rm -f docker-compose.yml
	@echo "Configuration files removed."

docker-clean:
	@echo "Stopping and removing all Docker containers..."
	@sudo docker-compose down --rmi all --volumes --remove-orphans
	@echo "Docker environment cleaned up."

docker-nuke:
	@echo "Removing all Docker data..."
	@sudo docker system prune -a -f --volumes
	@echo "Docker system pruned."
