# Convenience targets. All dbt commands run with explicit --project-dir and
# --profiles-dir so you can invoke `make <target>` from anywhere in the repo.

REPO         := $(CURDIR)
VENV         := $(REPO)/.venv
PY           := $(VENV)/bin/python
PIP          := $(VENV)/bin/pip
DBT          := $(VENV)/bin/dbt
DBT_PROJECT  := $(REPO)/dbt
DBT_PROFILES := $(REPO)/dbt
export DBT_DUCKDB_PATH := $(REPO)/warehouse/fashionable.duckdb

.PHONY: help venv install load deps debug run test build docs clean nuke

help:
	@echo "Targets:"
	@echo "  venv     - create .venv with pyenv 3.11.13"
	@echo "  install  - pip install -r requirements.txt into .venv"
	@echo "  deps     - dbt deps (install dbt packages)"
	@echo "  load     - run scripts/load_raw.py to (re)populate raw.fashionable_sales_raw"
	@echo "  debug    - dbt debug (verifies connection + config)"
	@echo "  run      - dbt run"
	@echo "  test     - dbt test"
	@echo "  build    - dbt build (run + test)"
	@echo "  docs     - generate + serve dbt docs on localhost:8080"
	@echo "  clean    - remove dbt target/ and dbt_packages/"
	@echo "  nuke     - clean + delete the DuckDB warehouse file"

venv:
	PYENV_VERSION=3.11.13 python -m venv $(VENV)
	$(PIP) install --upgrade pip

install: venv
	$(PIP) install -r requirements.txt

load:
	$(PY) scripts/load_raw.py

deps:
	$(DBT) deps --project-dir $(DBT_PROJECT) --profiles-dir $(DBT_PROFILES)

debug:
	$(DBT) debug --project-dir $(DBT_PROJECT) --profiles-dir $(DBT_PROFILES)

run:
	$(DBT) run --project-dir $(DBT_PROJECT) --profiles-dir $(DBT_PROFILES)

test:
	$(DBT) test --project-dir $(DBT_PROJECT) --profiles-dir $(DBT_PROFILES)

build:
	$(DBT) build --project-dir $(DBT_PROJECT) --profiles-dir $(DBT_PROFILES)

docs:
	$(DBT) docs generate --project-dir $(DBT_PROJECT) --profiles-dir $(DBT_PROFILES)
	$(DBT) docs serve   --project-dir $(DBT_PROJECT) --profiles-dir $(DBT_PROFILES)

clean:
	rm -rf $(DBT_PROJECT)/target $(DBT_PROJECT)/dbt_packages $(DBT_PROJECT)/logs

nuke: clean
	rm -f $(DBT_DUCKDB_PATH) $(DBT_DUCKDB_PATH).wal
