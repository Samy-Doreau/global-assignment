# Makefile
# Automatically include and export variables from .env file if it exists
ifneq (,$(wildcard ./.env))
    include .env
    export
endif

.PHONY: up down load-data dbt erd dbt-debug pipeline

up: ## Start postgres via docker-compose
	docker compose up -d

down: ## Stop and remove containers
	docker compose down

load-data: ## Load events JSONL into Postgres (usage: make load-data FILE=event_logs.json)
	python3 scripts/load_events_to_postgres.py --file $(FILE)

dbt-debug: ## Debug dbt connection
	cd dbt && dbt debug --profiles-dir $(PWD)

dbt: ## Run dbt deps, seed, run, test
	cd dbt && \
	dbt deps --profiles-dir $(PWD) && \
	dbt seed --profiles-dir $(PWD) && \
	dbt run --profiles-dir $(PWD) && \
	dbt test --profiles-dir $(PWD)

elementary-init: ## Run elementary
	cd dbt && dbt run --select elementary

elementary-report: ## Run elementary report
	cd dbt && edr report --profiles-dir $(PWD)

pipeline: ## Run full pipeline (truncate->seed->load->dbt->export)
	python3 scripts/pipeline.py --events $(FILE) 