ANSIBLE_DIR := ansible
PB := cd $(ANSIBLE_DIR) && ansible-playbook

.PHONY: deploy hermes check lint

deploy: ## First install or full re-deploy (asks questions on first run)
	./deploy.sh

hermes: ## Only (re)deploy / upgrade the Hermes stack
	./deploy.sh --tags hermes

check: ## Dry run with diff (after the first deploy)
	$(PB) site.yml --check --diff

lint: ## Syntax check scripts and playbooks
	bash -n deploy.sh
	$(PB) bootstrap.yml --syntax-check -i inventory/hosts.example.yml
	$(PB) site.yml --syntax-check -i inventory/hosts.example.yml
