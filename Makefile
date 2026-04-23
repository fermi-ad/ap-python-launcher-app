PYTHON  ?= .venv/bin/python
UVICORN ?= .venv/bin/uvicorn
IMAGE   ?= ap-python-launcher:dev
PORT    ?= 8000
FVM     ?= ../.fvm/flutter_sdk/bin/

.PHONY: help install test test-backend test-frontend test-cov dev mock lint build-frontend build-mock docker-build docker-run

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  %-14s %s\n", $$1, $$2}'

install: ## Install all dependencies (including dev) via uv
	uv sync

test: test-backend test-frontend ## Run all tests (backend + frontend)

test-frontend: ## Run Flutter (frontend/) tests
	cd frontend && $(FVM)flutter test --concurrency=1

test-backend: ## Run backend (Python) tests only
	$(PYTHON) -m pytest tests/unit tests/integration

test-cov: ## Run tests with coverage report
	$(PYTHON) -m pytest --cov=ap_python_launcher --cov-report=term-missing

dev: ## Run the server against a real Harbor/k8s (requires env vars)
	$(UVICORN) ap_python_launcher.server:app --reload --port $(PORT)

mock: ## Run the server with fakes — no Harbor or k8s needed
	AP_MOCK_MODE=true $(UVICORN) ap_python_launcher.server:app --reload --port $(PORT)

lint: ## Run ruff + flutter analyze
	$(PYTHON) -m ruff check ap_python_launcher tests
	cd frontend && $(FVM)flutter analyze

build-frontend: ## Build Flutter web frontend into ap_python_launcher/static/
	cd frontend && $(FVM)flutter pub get
	cd frontend && $(FVM)flutter build web --release --wasm
	rm -rf src/ap_python_launcher/static/*
	cp -r frontend/build/web/. src/ap_python_launcher/static/

build-mock: build-frontend mock ## Build frontend then run mock server

docker-build: build-frontend ## Build the Docker image
	docker build -t $(IMAGE) .

docker-run: ## Run the Docker image locally (mock mode)
	docker run --rm -p $(PORT):8000 -e AP_MOCK_MODE=true $(IMAGE)
