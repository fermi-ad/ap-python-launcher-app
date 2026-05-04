PYTHON  ?= .venv/bin/python
UVICORN ?= .venv/bin/uvicorn
IMAGE   ?= ap-python-launcher:dev
PORT    ?= 8000
FVM     ?= ../.fvm/flutter_sdk/bin/

.PHONY: help install test test-backend test-frontend test-cov dev mock lint build-frontend build-mock docker-build docker-run compose-build-kube compose-run-kube compose-build-harbor compose-run-harbor compose-build-full compose-run-full compose-shell compose-minikube-status compose-harbor-shell compose-integration-run

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
	AP_MOCK_HARBOR=true AP_MOCK_KUBE=true $(UVICORN) ap_python_launcher.server:app --reload --port $(PORT)

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
	docker run --rm -p $(PORT):8000 -e AP_MOCK_HARBOR=true -e AP_MOCK_KUBE=true $(IMAGE)

DOCKER_DEV_IMAGE ?= ap-python-launcher-dev:latest
DOCKER_DEV_PORT  ?= 8000
MINIKUBE_PROFILE ?= ap-python-launcher
MINIKUBE_DRIVER ?= docker
MINIKUBE_CPUS ?= 4
MINIKUBE_MEMORY ?= 8192
MINIKUBE_K8S_VERSION ?=
DOCKER_SOCKET ?= /var/run/docker.sock
COMPOSE_FILE ?= compose.local.yaml
COMPOSE ?= docker compose -f $(COMPOSE_FILE)
COMPOSE_PROFILES ?= k8s

# Pass through kube config content when needed, for example:
#   make compose-run-kube AP_KUBECONFIG_CONTENT="$(cat /home/chowingt/.kube/config)"
AP_KUBECONFIG_CONTENT ?=
AP_MOCK_HARBOR ?= false
AP_MOCK_KUBE ?= false

COMPOSE_ENV = DOCKER_DEV_PORT=$(DOCKER_DEV_PORT) \
	DOCKER_SOCKET=$(DOCKER_SOCKET) \
	MINIKUBE_PROFILE=$(MINIKUBE_PROFILE) \
	MINIKUBE_DRIVER=$(MINIKUBE_DRIVER) \
	MINIKUBE_CPUS=$(MINIKUBE_CPUS) \
	MINIKUBE_MEMORY=$(MINIKUBE_MEMORY) \
	MINIKUBE_K8S_VERSION=$(MINIKUBE_K8S_VERSION) \
	AP_MOCK_HARBOR=$(AP_MOCK_HARBOR) \
	AP_MOCK_KUBE=$(AP_MOCK_KUBE) \
	AP_KUBECONFIG_CONTENT='$(AP_KUBECONFIG_CONTENT)' \
	AP_HARBOR_BASE_URL='$(if $(AP_HARBOR_BASE_URL),$(AP_HARBOR_BASE_URL),http://localhost:8081)' \
	AP_HARBOR_PROJECT='$(if $(AP_HARBOR_PROJECT),$(AP_HARBOR_PROJECT),ap-python)' \
	AP_HARBOR_USERNAME='$(if $(AP_HARBOR_USERNAME),$(AP_HARBOR_USERNAME),admin)' \
	AP_HARBOR_PASSWORD='$(if $(AP_HARBOR_PASSWORD),$(AP_HARBOR_PASSWORD),Harbor12345)' \
	AP_WORKLOAD_NAMESPACE='$(AP_WORKLOAD_NAMESPACE)' \
	AP_SHARED_LB_IP='$(AP_SHARED_LB_IP)' \
	AP_SHARED_LB_ANNOTATIONS_JSON='$(AP_SHARED_LB_ANNOTATIONS_JSON)' \
	AP_SHARED_LB_PORT_RANGE_START='$(AP_SHARED_LB_PORT_RANGE_START)' \
	AP_SHARED_LB_PORT_RANGE_END='$(AP_SHARED_LB_PORT_RANGE_END)'


compose-kube-build: ## Build compose images for the Kubernetes-focused profile
	$(COMPOSE_ENV) COMPOSE_PROFILES='k8s' $(COMPOSE) build


compose-kube-run: ## Start the Kubernetes-focused profile services and follow logs
	$(COMPOSE_ENV) COMPOSE_PROFILES='k8s' $(COMPOSE) up app-dev minikube


compose-harbor-build: ## Build compose images for the Harbor-focused profile
	$(COMPOSE_ENV) COMPOSE_PROFILES='harbor' $(COMPOSE) build


compose-harbor-run: ## Start the Harbor-focused profile services and follow logs
	$(COMPOSE_ENV) COMPOSE_PROFILES='harbor' $(COMPOSE) up app-dev harbor-db harbor-redis harbor-registry harbor-jobservice harbor-core harbor-portal harbor-proxy


compose-full-build: ## Build compose images for the full local stack
	$(COMPOSE_ENV) COMPOSE_PROFILES='full' $(COMPOSE) build


compose-full-run: ## Start the full local stack and follow logs
	$(COMPOSE_ENV) COMPOSE_PROFILES='full' $(COMPOSE) up app-dev minikube harbor-db harbor-redis harbor-registry harbor-jobservice harbor-core harbor-portal harbor-proxy


compose-shell: ## Open an interactive shell in the app-dev container for the selected profile(s)
	$(COMPOSE_ENV) $(COMPOSE) run --rm app-dev bash


compose-minikube-status: ## Show Minikube profile status from the minikube container
	$(COMPOSE_ENV) COMPOSE_PROFILES='k8s' $(COMPOSE) exec minikube bash -lc 'minikube status --profile $(MINIKUBE_PROFILE)'


compose-harbor-shell: ## Open a shell in the app-dev container with the Harbor profile selected
	$(COMPOSE_ENV) COMPOSE_PROFILES='harbor' $(COMPOSE) run --rm app-dev bash


compose-integration-run: ## Run integration tests from the app-dev container against the selected profile(s)
	$(COMPOSE_ENV) $(COMPOSE) run --rm app-dev bash -lc '/workspace/.venv/bin/python -m pytest tests/integration -q'
