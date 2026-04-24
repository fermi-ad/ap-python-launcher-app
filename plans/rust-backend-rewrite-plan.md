# Rust backend rewrite plan

## Goals

- Replace the Python FastAPI backend in [`src/ap_python_launcher/server.py`](src/ap_python_launcher/server.py:1) with a Rust service.
- Preserve required behavior:
  - URL prefix stripping for `/ap-python/*` (and redirect `/ap-python` -> `/ap-python/`).
  - Serve Flutter web build output from the backend container.
  - Harbor discovery and Kubernetes Job/Service lifecycle semantics currently implemented in [`src/ap_python_launcher/discovery.py`](src/ap_python_launcher/discovery.py:1) and [`src/ap_python_launcher/launch.py`](src/ap_python_launcher/launch.py:1).
- API changes are allowed, but keep frontend churn low unless there is a clear benefit.

## Proposed Rust stack (maintainable, small-service friendly)

- HTTP server: Axum + Tower on Tokio
- HTTP client: Reqwest
- Kubernetes: kube-rs (with k8s-openapi via features)
- Serialization: serde + serde_json
- Errors: thiserror + anyhow
- Logging/metrics:
  - tracing + tracing-subscriber
  - optional: tower-http trace layer

## Repository layout (new)

- Add a Rust workspace folder, e.g. [`rust-backend/Cargo.toml`](rust-backend/Cargo.toml:1)
- Binary crate, e.g. [`rust-backend/src/main.rs`](rust-backend/src/main.rs:1)
- Modules:
  - [`rust-backend/src/config.rs`](rust-backend/src/config.rs:1)
  - [`rust-backend/src/http/mod.rs`](rust-backend/src/http/mod.rs:1)
  - [`rust-backend/src/http/routes.rs`](rust-backend/src/http/routes.rs:1)
  - [`rust-backend/src/http/static_files.rs`](rust-backend/src/http/static_files.rs:1)
  - [`rust-backend/src/harbor.rs`](rust-backend/src/harbor.rs:1)
  - [`rust-backend/src/kube_launcher.rs`](rust-backend/src/kube_launcher.rs:1)
  - [`rust-backend/src/models.rs`](rust-backend/src/models.rs:1)
  - [`rust-backend/src/errors.rs`](rust-backend/src/errors.rs:1)

## API surface

### Recommendation

Keep the existing unversioned paths used by the Flutter client in [`frontend/lib/api_service.dart`](frontend/lib/api_service.dart:1) for now:

- `GET /healthz`
- `GET /readyz`
- `GET /apps`
- `POST /launch`
- `POST /launch/status`
- `GET /launch/{launchId}`
- `DELETE /launch/{launchId}`

Rationale: versioning is not inherently more idiomatic in Rust; it is a product/API lifecycle choice. Keeping paths avoids unnecessary frontend changes.

### Allowed improvements (optional)

- Add `GET /api/v1/*` equivalents later, keeping old paths as thin wrappers.
- Add structured error responses (still map to correct HTTP status codes).

## Required semantics to preserve

### Prefix stripping

Implement a Tower layer that:

- Redirects `/ap-python` -> `/ap-python/` with 301.
- For any path starting with `/ap-python`, strips the prefix before routing.

This mirrors [`StripPrefixMiddleware`](src/ap_python_launcher/server.py:49).

### Static Flutter hosting

- Embed Flutter build output into the container image.
- Serve it at `/` with typical Flutter web paths:
  - `/index.html`
  - `/flutter_bootstrap.js`
  - `/assets/*`

Behavior should match the Python server’s mount in [`create_app()`](src/ap_python_launcher/server.py:59).

### Harbor discovery

Implement equivalent of [`HarborClient.list_latest_apps()`](src/ap_python_launcher/discovery.py:106):

- List repositories under project:
  - `GET /api/v2.0/projects/{project}/repositories` (paged)
- For each repo, list artifacts with tags:
  - `GET /api/v2.0/projects/{project}/repositories/{repo_short}/artifacts?with_tag=true` (paged)
- Select the first artifact that has tag `latest`.
- Resolve `tag`:
  - Prefer first tag containing digits.
  - Else first non-`latest` tag.
  - Else `latest`.
- Return sorted by repo.

### Kubernetes launcher

Implement equivalent of [`KubeLauncher`](src/ap_python_launcher/launch.py:33):

- Config loading:
  - If `AP_KUBECONFIG` is set (content), write to temp file and load.
  - Else try in-cluster config; fall back to default kubeconfig.
- Concurrency limits:
  - Total active jobs <= `MAX_JOBS_TOTAL` (45)
  - Per-app active jobs <= `MAX_JOBS_PER_APP` (10)
  - Active means Job status `active > 0`.
- Job creation:
  - Labels:
    - `app.kubernetes.io/managed-by=ap-python-launcher`
    - `ap-python.fnal.gov/repo` (repo with `/` replaced by `_`)
    - `ap-python.fnal.gov/tag`
    - `ap-python.fnal.gov/launch-id`
    - optional `ap-python.fnal.gov/requested-by`
  - Job spec:
    - `ttlSecondsAfterFinished=3600`
    - `activeDeadlineSeconds=86400`
    - `backoffLimit=0`
    - Pod:
      - container port `AP_APP_TARGET_PORT` (default 14500)
      - readiness probe HTTP GET `/` on target port
      - resource requests/limits as in Python
- Service creation:
  - Per-launch `Service` type `LoadBalancer`
  - Selector: `ap-python.fnal.gov/launch-id={launchId}`
  - Port `AP_LB_PORT` (default 80) -> target port `AP_APP_TARGET_PORT`
  - Optional annotations from `AP_LB_ANNOTATIONS_JSON` (must be JSON object string->string)
  - Idempotent create (ignore 409)
- Status:
  - Determine Job status: Pending/Running/Succeeded/Failed
  - If deletion timestamp set: Ending
  - Find Pod by selector; compute readiness from Pod conditions
  - Compute LB URLs from Service status ingress hostname/ip
  - Only expose URLs when pod is Ready
  - Cleanup Service when:
    - Job is Succeeded/Failed/Ending, or
    - Pod disappears
- Delete:
  - Delete Job by selector (foreground propagation)
  - Always best-effort delete Service

## Configuration

Match env vars from [`src/ap_python_launcher/config.py`](src/ap_python_launcher/config.py:28):

- `AP_HARBOR_BASE_URL` default `https://adregistry.fnal.gov`
- `AP_HARBOR_PROJECT` default `ap-python`
- `AP_HARBOR_USERNAME` optional
- `AP_HARBOR_PASSWORD` optional
- `AP_KUBECONFIG` optional (content)
- `AP_WORKLOAD_NAMESPACE` default `ap-python`
- `AP_APP_TARGET_PORT` default `14500`
- `AP_LB_PORT` default `80`
- `AP_LB_ANNOTATIONS_JSON` optional

Additions (optional):

- `PORT` or `AP_PORT` for server listen port (default 8000)
- `RUST_LOG` or `AP_LOG_LEVEL` for logging

## Testing strategy

- Rust unit tests:
  - Harbor tag resolution logic
  - LB annotations parsing
  - Service name generation
  - Prefix stripping layer behavior
- Rust handler tests:
  - Use Axum router tests with mocked Harbor/Kube traits
  - Mirror key assertions from [`tests/unit/test_server.py`](tests/unit/test_server.py:1)
- Integration tests:
  - Mock Harbor via a local HTTP server (wiremock)
  - Kubernetes:
    - Prefer a fake kube API (kube-rs test utilities) for unit-level
    - Optional: kind-based integration in CI if feasible

## Container/build plan

Replace Python runtime stage in [`Dockerfile`](Dockerfile:1) with Rust:

- Stage 1: build Flutter web assets (keep existing)
- Stage 2: build Rust binary (cargo build --release)
- Stage 3: minimal runtime image (debian slim or distroless)
  - copy Rust binary
  - copy Flutter build output into a known directory served by Rust
  - run as non-root user (uid 10001)
  - expose 8000

## Makefile/CI plan

- Add Make targets:
  - `make rust-dev` run Rust server locally
  - `make rust-test` run cargo tests
  - `make build` builds Flutter + Rust container
- Update CI workflow in [`.github/workflows/integration.yaml`](.github/workflows/integration.yaml:1):
  - build Rust backend
  - run Rust unit tests
  - run Flutter tests against the Rust backend (or mocked API)

## Migration plan

- Keep Python backend available temporarily:
  - Option A: separate image tags (python-backend vs rust-backend)
  - Option B: build arg to select backend in Dockerfile
- Rollout:
  - Deploy Rust backend to a staging environment
  - Validate:
    - `/ap-python/*` routing
    - `/` static hosting
    - launch flows end-to-end
  - Switch production deployment to Rust image
  - Remove Python backend code and Python dependencies once stable
