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
	cd dbt && dbt debug --profiles-dir ..

dbt: ## Run dbt deps, seed, run, test
	cd dbt && \
	dbt deps --profiles-dir .. && \
	dbt seed --profiles-dir .. && \
	dbt run --profiles-dir .. && \
	dbt test --profiles-dir ..

erd: ## Generate ERD SVG in docs/ (requires: pip install dbt-erd)
	cd dbt && dbt-erd render models/ --profiles-dir .. --output ../docs/erd.svg 

pipeline: ## Run full pipeline (truncate->seed->load->dbt->export)
	python3 scripts/pipeline.py --events $(FILE) 