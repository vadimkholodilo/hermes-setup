ANSIBLE_DIR := ansible
VAULT := --ask-vault-pass
PB := cd $(ANSIBLE_DIR) && ansible-playbook

.PHONY: deps bootstrap deploy hermes check lint

deps: ## Install required Ansible collections
	cd $(ANSIBLE_DIR) && ansible-galaxy collection install -r requirements.yml -p collections

bootstrap: ## First run on a fresh VPS (as root): create admin user
	$(PB) bootstrap.yml $(VAULT)

deploy: ## Full machine config + Hermes stack (idempotent)
	$(PB) site.yml $(VAULT)

hermes: ## Only (re)deploy / upgrade the Hermes stack
	$(PB) site.yml --tags hermes $(VAULT)

check: ## Dry run with diff
	$(PB) site.yml --check --diff $(VAULT)

lint: ## Syntax check playbooks
	$(PB) bootstrap.yml --syntax-check
	$(PB) site.yml --syntax-check
