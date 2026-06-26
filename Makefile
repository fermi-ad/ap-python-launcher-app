FVM          ?= ./.fvm/flutter_sdk/bin/
DEV_IMAGE    ?= ap-python-launcher-app:dev
DEV_PORT     ?= 8080
API_BASE_URL ?= http://localhost:8000/

.PHONY: help test lint build docker-build docker-run

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  %-14s %s\n", $$1, $$2}'

test: ## Run Flutter (frontend/) tests
	$(FVM)flutter test --concurrency=1

lint: ## Run flutter analyze
	$(FVM)flutter analyze

build: ## Build Flutter web frontend
	$(FVM)flutter pub get
	$(FVM)flutter build web --wasm --no-web-resources-cdn

docker-build: ## Build the dev Docker image
	docker build -t $(DEV_IMAGE) .

docker-run: ## Run the dev container (flutter run web-server on DEV_PORT)
	docker run --rm -it \
	  -p $(DEV_PORT):8080 \
	  -e API_BASE_URL=$(API_BASE_URL) \
	  -v "$(PWD):/app" \
	  $(DEV_IMAGE)
