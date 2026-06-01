FVM ?= ../.fvm/flutter_sdk/bin/

.PHONY: help test-frontend lint build-frontend

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  %-14s %s\n", $$1, $$2}'

test-frontend: ## Run Flutter (frontend/) tests
	cd frontend && $(FVM)flutter test --concurrency=1

lint: ## Run flutter analyze
	cd frontend && $(FVM)flutter analyze

build-frontend: ## Build Flutter web frontend
	cd frontend && $(FVM)flutter pub get
	cd frontend && $(FVM)flutter build web --wasm --no-web-resources-cdn
