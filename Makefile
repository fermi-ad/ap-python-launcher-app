FVM ?= ./.fvm/flutter_sdk/bin/

.PHONY: help test lint build

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
