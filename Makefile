ANSIBLE_DIR := ansible
PB := cd $(ANSIBLE_DIR) && ansible-playbook

# Local dev stack: base compose.yml + dev overrides + dev variables.
DEV := docker compose -f docker/compose.yml -f docker/compose.dev.yml --env-file docker/dev.env
# Prod file alone, with example values (for config validation only).
PROD := docker compose -f docker/compose.yml --env-file docker/.env.example

.DEFAULT_GOAL := help
.PHONY: help deploy hermes check lint deps dev dev-down dev-restart dev-logs dev-ps dev-pull dev-config dev-shell

help: ## List targets
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  %-12s %s\n", $$1, $$2}'

deploy: ## First install or full re-deploy (asks questions on first run)
	./deploy.sh

hermes: ## Only (re)deploy / upgrade the Hermes stack
	./deploy.sh --tags hermes

deps: ## Install Ansible collections and Galaxy roles
	cd $(ANSIBLE_DIR) && ansible-galaxy collection install -r requirements.yml -p collections >/dev/null
	cd $(ANSIBLE_DIR) && ansible-galaxy role install -r requirements.yml -p galaxy_roles >/dev/null

check: deps ## Dry run with diff (after the first deploy)
	$(PB) site.yml --check --diff

lint: deps ## Syntax check scripts, playbooks and compose files
	bash -n deploy.sh
	$(PB) site.yml --syntax-check -i inventory/hosts.example.yml
	$(PROD) config -q
	$(DEV) config -q

dev: ## Start the local dev stack → http://hermes.localhost:8080 (dev / dev-password)
	$(DEV) up -d
	@echo "Hermes:  http://hermes.localhost:8080  (login dev / dev-password)"
	@echo "Traefik: http://localhost:8081"

dev-down: ## Stop the dev stack (state in docker/.dev-data is kept)
	$(DEV) down

dev-restart: ## Restart the dev stack
	$(DEV) restart

dev-logs: ## Follow dev logs
	$(DEV) logs -f

dev-ps: ## Show dev containers
	$(DEV) ps

dev-pull: ## Pull newer images for the dev stack
	$(DEV) pull

dev-config: ## Print the merged dev compose config
	$(DEV) config

dev-shell: ## Shell into the dev Hermes container
	$(DEV) exec hermes bash
