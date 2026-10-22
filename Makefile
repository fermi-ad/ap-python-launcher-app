FVM          ?= ./.fvm/flutter_sdk/bin/
DEV_IMAGE    ?= ap-python-launcher-app:dev
DEV_PORT     ?= 8080
API_BASE_URL ?= http://localhost:8000/
.PHONY: help test lint build docker-build docker-run harbor-push

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  %-14s %s\n", $$1, $$2}'

test: ## Run Flutter (frontend/) tests
	$(FVM)flutter test --concurrency=1

lint: ## Run flutter analyze and dart analyze, which have slightly different coverage
	@status=0; \
	$(FVM)flutter analyze || status=1; \
	$(FVM)dart analyze || status=1; \
	exit $$status

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

harbor-push: HARBOR_IMAGE := adregistry.fnal.gov/test/ap-python-launcher-app
harbor-push: HARBOR_IMAGE_TAG := $(HARBOR_IMAGE):$(HARBOR_TAG)
harbor-push: ## Build and push the Harbor image: make harbor-push HARBOR_TAG=<tag>. Requires Harbor authentication.
	@test -n "$(strip $(HARBOR_TAG))" || { echo "Usage: make harbor-push HARBOR_TAG=<tag>" >&2; exit 1; }
	$(MAKE) build
	docker build -t "$(HARBOR_IMAGE_TAG)" .
	docker push "$(HARBOR_IMAGE_TAG)"
