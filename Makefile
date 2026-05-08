PYTHON           ?= .venv/bin/python
UVICORN          ?= .venv/bin/uvicorn
IMAGE            ?= ap-python-launcher:prod
DEV_DOCKER_IMAGE ?= ap-python-launcher:dev
PORT             ?= 8000
FVM              ?= ../.fvm/flutter_sdk/bin/
ENV_FILE         ?= .env
KUBECONFIG_PATH  ?= .kubeconfig
TEST_APP_REGISTRY ?= local/ap-python

.PHONY: help install test test-backend test-frontend test-cov dev mock lint build-frontend build-mock docker-build docker-run docker-dev-build docker-dev minikube-load-test-images

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  %-14s %s\n", $$1, $$2}'

install: ## Install all dependencies (including dev) via uv
	uv sync

test: test-backend test-frontend ## Run all tests (backend + frontend)

test-frontend: ## Run Flutter (frontend/) tests
	cd frontend && $(FVM)flutter test --concurrency=1

test-backend: ## Run backend (Python) tests only
	PYTHONPATH=src $(PYTHON) -m pytest tests/unit tests/integration

test-cov: ## Run tests with coverage report
	PYTHONPATH=src $(PYTHON) -m pytest --cov=ap_python_launcher --cov-report=term-missing

dev: ## Run the server against a real Harbor/k8s (requires env vars)
	$(UVICORN) ap_python_launcher.server:app --reload --port $(PORT)

mock: ## Run the server with fake Harbor and fake Kubernetes
	AP_MOCK_HARBOR=true AP_MOCK_KUBE=true $(UVICORN) ap_python_launcher.server:app --reload --port $(PORT)

lint: ## Run ruff + flutter analyze
	$(PYTHON) -m ruff check ap_python_launcher tests
	cd frontend && $(FVM)flutter analyze

build-frontend: ## Build Flutter web frontend into ap_python_launcher/static/
	cd frontend && $(FVM)flutter pub get
	cd frontend && $(FVM)flutter build web --release --wasm --no-web-resources-cdn
	rm -rf src/ap_python_launcher/static/*
	cp -r frontend/build/web/. src/ap_python_launcher/static/

build-mock: build-frontend mock ## Build frontend then run mock server

docker-prod-build: ## Build the Docker image
	docker build -t $(IMAGE) .

docker-prod-run: ## Run the Docker image locally with fake Harbor and fake Kubernetes
	docker run --rm -p $(PORT):8000 -e AP_MOCK_HARBOR=true -e AP_MOCK_KUBE=true $(IMAGE)

docker-dev-build: build-frontend ## Build the dev Docker image
	docker build -f Dockerfile.dev -t $(DEV_DOCKER_IMAGE) .

docker-dev-run: ## Run the dev Docker image with env-file and mounted kubeconfig
	docker run --rm -it --network=host \
		-p $(PORT):8000 \
		--env-file $(ENV_FILE) \
		-v $(CURDIR)/$(KUBECONFIG_PATH):/tmp/ap-kubeconfig:ro \
		-e AP_KUBECONFIG_PATH=/tmp/ap-kubeconfig \
		$(DEV_DOCKER_IMAGE) \
		/app/.venv/bin/python -m uvicorn ap_python_launcher.server:app --host 0.0.0.0 --port 8000 --reload

minikube-load: ## Build and load all fake Harbor test images into Minikube
	docker build -f docker/test-app/Dockerfile --build-arg TEST_APP_INDEX=docker/test-app/index-a.html -t $(TEST_APP_REGISTRY)/test-app-a:latest .
	docker build -f docker/test-app/Dockerfile --build-arg TEST_APP_INDEX=docker/test-app/index-b.html -t $(TEST_APP_REGISTRY)/test-app-b:latest .
	docker build -f docker/test-app/Dockerfile --build-arg TEST_APP_INDEX=docker/test-app/index-c.html -t $(TEST_APP_REGISTRY)/test-app-c:latest .
	minikube image load $(TEST_APP_REGISTRY)/test-app-a:latest
	minikube image load $(TEST_APP_REGISTRY)/test-app-b:latest
	minikube image load $(TEST_APP_REGISTRY)/test-app-c:latest
