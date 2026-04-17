# Sleuthgraph local dev Makefile.
# Run from ~/sleuthgraph/deploy/.

.PHONY: up down logs ps shell-db shell-redis shell-api shell-web test clean rebuild

ENV_FILE := .env
COMPOSE := docker compose --env-file $(ENV_FILE) -f docker-compose.yml -f docker-compose.dev.yml

up:
	$(COMPOSE) up -d
	@echo "API:  http://localhost:$${API_PORT:-8000}/docs"
	@echo "Web:  http://localhost:$${WEB_PORT:-3000}"
	@echo "MinIO console: http://localhost:9001"

down:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f --tail=100

ps:
	$(COMPOSE) ps

shell-db:
	$(COMPOSE) exec db psql -U $${POSTGRES_USER} $${POSTGRES_DB}

shell-redis:
	$(COMPOSE) exec redis redis-cli

shell-api:
	$(COMPOSE) exec api bash

shell-web:
	$(COMPOSE) exec web sh

test:
	$(COMPOSE) exec api pytest
	$(COMPOSE) exec web pnpm test

rebuild:
	$(COMPOSE) build --no-cache
	$(COMPOSE) up -d

clean:
	$(COMPOSE) down -v
	@echo "All containers, volumes, and networks removed."
