PYTHON  ?= .venv/bin/python
UVICORN ?= .venv/bin/uvicorn
IMAGE   ?= ap-python-launcher:dev
PORT    ?= 8000

.PHONY: help install test test-backend test-frontend test-cov dev mock lint docker-build docker-run

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  %-14s %s\n", $$1, $$2}'

install: ## Install all dependencies (including dev) via uv
	uv sync

test: test-backend test-frontend ## Run all tests (backend + frontend)

test-backend: ## Run backend (Python) tests only
	$(PYTHON) -m pytest tests/unit tests/integration

test-frontend: ## Run frontend (Jest) tests
	cd tests/frontend && npm test

test-cov: ## Run tests with coverage report
	$(PYTHON) -m pytest --cov=ap_launcher --cov-report=term-missing

dev: ## Run the server against a real Harbor/k8s (requires env vars)
	$(UVICORN) ap_launcher.server:app --reload --port $(PORT)

mock: ## Run the server with fakes — no Harbor or k8s needed
	AP_MOCK_MODE=true $(UVICORN) ap_launcher.server:app --reload --port $(PORT)

lint: ## Run ruff (if available)
	$(PYTHON) -m ruff check ap_launcher tests

docker-build: ## Build the Docker image
	docker build -t $(IMAGE) .

docker-run: ## Run the Docker image locally (mock mode)
	docker run --rm -p $(PORT):8000 -e AP_MOCK_MODE=true $(IMAGE)
