.PHONY: help setup dev prod test clean lint format

# Default target
.DEFAULT_GOAL := help

# Variables
VENV_DIR := venv
PROJECT_ROOT := $(shell pwd)
PYTHON := $(VENV_DIR)/bin/python3
PIP := $(VENV_DIR)/bin/pip
FLAKE8 := $(VENV_DIR)/bin/flake8
BLACK := $(VENV_DIR)/bin/black
PYTEST := $(VENV_DIR)/bin/pytest

help: ## Show this help message
	@echo "Roxy-WI Development Makefile"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'
	@echo ""
	@echo "Examples:"
	@echo "  make setup          # Initial setup"
	@echo "  make dev            # Run development server"
	@echo "  make test           # Run tests"
	@echo "  make clean          # Clean up"

setup: ## Setup development environment
	@echo "Setting up development environment..."
	@bash scripts/setup_dev_env.sh

dev: ## Run development server
	@bash scripts/start_dev.sh

prod: ## Run production server with Gunicorn
	@bash scripts/start_prod.sh

venv: ## Create virtual environment
	@echo "Creating virtual environment..."
	@python3 -m venv $(VENV_DIR)
	@echo "Virtual environment created. Run 'source $(VENV_DIR)/bin/activate'"

install: venv ## Install dependencies
	@echo "Installing dependencies..."
	@$(PIP) install --upgrade pip setuptools wheel
	@$(PIP) install -r requirements.txt
	@if [ -f requirements-dev.txt ]; then $(PIP) install -r requirements-dev.txt; fi
	@echo "Dependencies installed"

test: ## Run tests with pytest
	@echo "Running tests..."
	@$(PYTEST) tests/ -v --tb=short

test-cov: ## Run tests with coverage
	@echo "Running tests with coverage..."
	@$(PYTEST) tests/ --cov=app --cov-report=html --cov-report=term-missing

lint: ## Run linting checks
	@echo "Running linting checks..."
	@$(FLAKE8) app/ tests/ --max-line-length=100 --exclude=migrations --statistics || true

format: ## Format code with black
	@echo "Formatting code with black..."
	@$(BLACK) app/ tests/ --line-length=100

format-check: ## Check code formatting without changes
	@echo "Checking code formatting..."
	@$(BLACK) app/ tests/ --line-length=100 --check

init-db: ## Initialize database
	@echo "Initializing database..."
	@$(PYTHON) app/create_db.py
	@echo "Database initialized"

migrate: ## Run database migrations
	@echo "Running database migrations..."
	@$(PYTHON) app/migrate.py migrate

migrate-create: ## Create a new database migration
	@echo "Creating new migration. Usage: make migrate-create NAME=migration_name"
	@$(PYTHON) app/migrate.py create $(NAME)

shell: ## Open Python interactive shell with app context
	@echo "Opening interactive shell..."
	@$(PYTHON) -c "from app import app; from flask import Flask; app.app_context().push()" || $(PYTHON)

scheduler: ## Run background scheduler
	@echo "Running scheduler..."
	@$(PYTHON) scheduler_runner.py

clean: ## Clean up generated files and cache
	@echo "Cleaning up..."
	@find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	@find . -type f -name "*.pyc" -delete
	@find . -type f -name ".DS_Store" -delete
	@rm -rf htmlcov/
	@rm -f .coverage
	@echo "Cleanup complete"

distclean: clean ## Deep clean including virtual environment
	@echo "Removing virtual environment..."
	@rm -rf $(VENV_DIR)
	@echo "Clean complete"

logs: ## View application logs
	@tail -f logs/roxy-wi.log 2>/dev/null || echo "Log file not found. Start the dev server first."

config-show: ## Show development configuration
	@cat .roxy-wi-dev/etc/roxy-wi.cfg 2>/dev/null || echo "Development config not found. Run 'make setup' first."

version: ## Show application version
	@$(PYTHON) -c "from app.version import version; print('Roxy-WI version:', version)" 2>/dev/null || echo "Unable to get version"

deps-check: ## Check for outdated dependencies
	@echo "Checking for outdated packages..."
	@$(PIP) list --outdated

deps-update: ## Update all dependencies
	@echo "Updating dependencies..."
	@$(PIP) install --upgrade -r requirements.txt
	@if [ -f requirements-dev.txt ]; then $(PIP) install --upgrade -r requirements-dev.txt; fi
	@echo "Dependencies updated"

.PHONY: help setup dev prod test clean lint format venv install
