PYTHON  ?= .venv/bin/python
UVICORN ?= .venv/bin/uvicorn
IMAGE   ?= ap-python-launcher:dev
PORT    ?= 8000
FVM     ?= ../.fvm/flutter_sdk/bin/

.PHONY: help install test test-backend test-frontend test-cov dev mock lint build-frontend build-mock docker-build docker-run docker-dev-build docker-dev-run docker-dev-shell docker-minikube-start docker-minikube-stop docker-minikube-status docker-integration-build docker-integration-run

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
#   make docker-dev-run AP_KUBECONFIG_CONTENT="$(cat /home/chowingt/.kube/config)"
AP_KUBECONFIG_CONTENT ?=
AP_MOCK_MODE ?= false

COMPOSE_ENV = DOCKER_DEV_PORT=$(DOCKER_DEV_PORT) \
	DOCKER_SOCKET=$(DOCKER_SOCKET) \
	MINIKUBE_PROFILE=$(MINIKUBE_PROFILE) \
	MINIKUBE_DRIVER=$(MINIKUBE_DRIVER) \
	MINIKUBE_CPUS=$(MINIKUBE_CPUS) \
	MINIKUBE_MEMORY=$(MINIKUBE_MEMORY) \
	MINIKUBE_K8S_VERSION=$(MINIKUBE_K8S_VERSION) \
	AP_MOCK_MODE=$(AP_MOCK_MODE) \
	AP_KUBECONFIG_CONTENT='$(AP_KUBECONFIG_CONTENT)' \
	AP_HARBOR_BASE_URL='$(if $(AP_HARBOR_BASE_URL),$(AP_HARBOR_BASE_URL),http://localhost:8081)' \
	AP_HARBOR_PROJECT='$(if $(AP_HARBOR_PROJECT),$(AP_HARBOR_PROJECT),ap-python)' \
	AP_HARBOR_USERNAME='$(if $(AP_HARBOR_USERNAME),$(AP_HARBOR_USERNAME),admin)' \
	AP_HARBOR_PASSWORD='$(if $(AP_HARBOR_PASSWORD),$(AP_HARBOR_PASSWORD),Harbor12345)' \
	AP_WORKLOAD_NAMESPACE='$(AP_WORKLOAD_NAMESPACE)' \
	AP_SHARED_LB_IP='$(AP_SHARED_LB_IP)' \
	AP_SHARED_LB_ANNOTATIONS_JSON='$(AP_SHARED_LB_ANNOTATIONS_JSON)' \
	AP_SHARED_LB_PORT_RANGE_START='$(AP_SHARED_LB_PORT_RANGE_START)' \
	AP_SHARED_LB_PORT_RANGE_END='$(AP_SHARED_LB_PORT_RANGE_END)' \
	COMPOSE_PROFILES='$(COMPOSE_PROFILES)'


docker-dev-build: ## Build compose images for the selected profile(s)
	$(COMPOSE_ENV) $(COMPOSE) build


docker-dev-run: ## Start the selected compose profile(s) and follow the app logs
	mkdir -p .minikube .kube
	$(COMPOSE_ENV) $(COMPOSE) up app-dev


docker-dev-shell: ## Open an interactive shell in the app-dev container for the selected profile(s)
	mkdir -p .minikube .kube
	$(COMPOSE_ENV) $(COMPOSE) run --rm app-dev bash


docker-minikube-start: ## Start the Kubernetes-focused profile services
	mkdir -p .minikube .kube
	$(COMPOSE_ENV) COMPOSE_PROFILES='k8s' $(COMPOSE) up -d minikube


docker-minikube-stop: ## Stop the Minikube service
	$(COMPOSE_ENV) COMPOSE_PROFILES='k8s' $(COMPOSE) stop minikube


docker-minikube-status: ## Show Minikube profile status from the minikube container
	$(COMPOSE_ENV) COMPOSE_PROFILES='k8s' $(COMPOSE) exec minikube bash -lc 'minikube status --profile $(MINIKUBE_PROFILE)'


docker-harbor-start: ## Start the Harbor-focused local Harbor profile
	$(COMPOSE_ENV) COMPOSE_PROFILES='harbor' $(COMPOSE) up -d harbor-db harbor-redis harbor-registry harbor-jobservice harbor-core harbor-portal harbor-proxy


docker-harbor-stop: ## Stop the Harbor-focused local Harbor profile
	$(COMPOSE_ENV) COMPOSE_PROFILES='harbor' $(COMPOSE) stop harbor-db harbor-redis harbor-registry harbor-jobservice harbor-core harbor-portal harbor-proxy


docker-harbor-shell: ## Open a shell in the app-dev container with the Harbor profile selected
	$(COMPOSE_ENV) COMPOSE_PROFILES='harbor' $(COMPOSE) run --rm app-dev bash


docker-integration-build: ## Build compose images used for the selected profile(s)
	$(COMPOSE_ENV) $(COMPOSE) build


docker-integration-run: ## Run integration tests from the app-dev container against the selected profile(s)
	mkdir -p .minikube .kube
	$(COMPOSE_ENV) $(COMPOSE) run --rm app-dev bash -lc '/workspace/.venv/bin/python -m pytest tests/integration -q'
