# ap-python-launcher (web)

In-cluster web UI + API for listing Harbor-hosted AP Python app images and launching them as Kubernetes Jobs.

## Accessing a launched app

Each launch creates:
- a `Job` (and Pod) in the workload namespace, and
- a per-launch `Service` of type `LoadBalancer` that selects the Pod by `ap-python.fnal.gov/launch-id`.

The `POST /launch` response includes `launchId` and `serviceName`. Poll [`GET /launch/{launchId}`](src/ap_python_launcher/server.py:117) until `access.urls` becomes non-empty, then open one of the returned URLs.

The launcher will delete the per-launch Service when the Job finishes (Succeeded/Failed) or when the Pod disappears.

## Run locally

```bash
uv sync
make dev PORT=8080
```

Then open: `http://localhost:8080/`

## Frontend (Flutter web)

The web UI is implemented as a Flutter web app in [`frontend/`](frontend/). The FastAPI server serves the built Flutter assets from [`src/ap_python_launcher/static/`](src/ap_python_launcher/static/) (this directory is a build artifact).

This repo requires using [FVM](https://fvm.app/) for Flutter version management. Install FVM and run `fvm install` in the repo root to get the [pinned Flutter version](.fvmrc). All `make` targets and the commands below use `fvm flutter` automatically.

### Build the frontend into the FastAPI static directory

```bash
make build-frontend
```

### Build the frontend and run the mock server

```bash
make build-mock
```

This builds the Flutter web frontend into the FastAPI static directory and then starts the mock server. Open: `http://localhost:8000/`

### Run the frontend with hot reload (dev)

In one terminal:

```bash
make mock PORT=8080
```

In another terminal:

```bash
cd frontend
fvm flutter run -d chrome --web-port 5173
```

Then open: `http://localhost:5173/`

Note: the Flutter dev server will not automatically proxy API calls to the FastAPI server. For local dev, either:
- run the Flutter app from the FastAPI-served build output (`make build-mock` then open `http://localhost:8000/`), or
- configure a proxy in your browser / dev environment.

## Docker

### Production image

**Build:**

```bash
docker build -t ap-python-launcher .
```

**Run:**

```bash
docker run --rm -p 8080:8000 ap-python-launcher
```

Then open: `http://localhost:8080/`

Pass environment variables with `-e`:

```bash
docker run --rm -p 8080:8000 \
  -e AP_HARBOR_USERNAME=myuser \
  -e AP_HARBOR_PASSWORD=mypassword \
  -e AP_KUBECONFIG="$(cat /home/chowingt/.kube/config)" \
  ap-python-launcher
```

### Development and integration testing with Docker Compose

The local dev stack now uses [`compose.local.yaml`](compose.local.yaml) plus Dockerfiles under [`compose/local/`](compose/local/):
- [`compose/local/ap-python-launcher/Dockerfile`](compose/local/ap-python-launcher/Dockerfile) builds the app container used for running the launcher and integration tests
- [`compose/local/minikube/Dockerfile`](compose/local/minikube/Dockerfile) builds the dedicated Minikube management container
- [`compose.local.yaml`](compose.local.yaml) defines the two-service stack

#### Service layout

- [`app-dev`](compose.local.yaml:2) runs the launcher app from [`compose/local/ap-python-launcher/Dockerfile`](compose/local/ap-python-launcher/Dockerfile)
- [`minikube`](compose.local.yaml:34) runs the cluster manager from [`compose/local/minikube/Dockerfile`](compose/local/minikube/Dockerfile)

Both services share repo-mounted [`.kube/`](.kube) and [`.minikube/`](.minikube) state so the app container can talk to the local cluster created by the Minikube container.

#### Build the Compose images

```bash
make docker-dev-build
```

#### Start Minikube

```bash
make docker-minikube-start
```

This starts the dedicated [`minikube`](compose.local.yaml:34) service, which uses the host Docker daemon through the mounted Docker socket, installs upstream MetalLB automatically, applies [`compose/local/minikube/metallb-pool.yaml`](compose/local/minikube/metallb-pool.yaml), and keeps the Minikube profile alive.

#### Start the app

```bash
make docker-dev-run AP_MOCK_MODE=false
```

Open: `http://localhost:8000/`

#### Open a shell in the app container

```bash
make docker-dev-shell
```

Use this shell to run ad hoc commands like:

```bash
/workspace/.venv/bin/python -m pytest tests/integration -q
kubectl get pods -A
```

#### Check or stop Minikube

```bash
make docker-minikube-status
make docker-minikube-stop
```

#### Run integration tests against the local cluster

```bash
export AP_HARBOR_BASE_URL=https://adregistry.fnal.gov
export AP_HARBOR_PROJECT=ap-python
export AP_HARBOR_USERNAME=myuser
export AP_HARBOR_PASSWORD=mypassword
export AP_WORKLOAD_NAMESPACE=ap-python
make docker-integration-run AP_MOCK_MODE=false
```

This starts [`minikube`](compose.local.yaml:34) if needed and runs [`pytest`](tests/integration) from the [`app-dev`](compose.local.yaml:2) container.

#### Use real Harbor and shared-IP settings

Export real credentials before running [`make docker-dev-run`](Makefile:87) or [`make docker-integration-run`](Makefile:104):

```bash
export AP_HARBOR_BASE_URL=https://adregistry.fnal.gov
export AP_HARBOR_PROJECT=ap-python
export AP_HARBOR_USERNAME=myuser
export AP_HARBOR_PASSWORD=mypassword
export AP_WORKLOAD_NAMESPACE=ap-python
export AP_SHARED_LB_IP=192.168.49.10
export AP_SHARED_LB_ANNOTATIONS_JSON='{"metallb.io/allow-shared-ip":"ap-python-launcher"}'
```

If you want to reuse an existing kubeconfig instead of the Compose-managed Minikube profile, inject kubeconfig content through [`AP_KUBECONFIG`](README.md:202):

```bash
make docker-dev-run AP_MOCK_MODE=false AP_KUBECONFIG_CONTENT="$(cat /home/chowingt/.kube/config)"
```

#### Caveats

The [`minikube`](compose.local.yaml:34) service still requires:
- `--privileged`
- access to the host Docker socket
- host networking behavior that is compatible with Docker-driver Minikube and MetalLB

On startup, [`start.sh`](compose/local/minikube/start.sh) performs this bootstrapping automatically:
- starts Minikube
- updates kube context
- installs upstream MetalLB
- waits for the MetalLB controller and speaker to become ready
- applies [`compose/local/minikube/metallb-pool.yaml`](compose/local/minikube/metallb-pool.yaml)

This is practical for local development, but it is still a high-trust setup.

## Configuration

Environment variables (defaults shown):

- `AP_HARBOR_BASE_URL=https://adregistry.fnal.gov`
- `AP_HARBOR_PROJECT=ap-python`
- `AP_HARBOR_USERNAME` (optional)
- `AP_HARBOR_PASSWORD` (optional)
- `AP_KUBECONFIG` (optional; kubeconfig *content* as a string. If unset, uses in-cluster auth.)
- `AP_WORKLOAD_NAMESPACE=ap-python`

### Per-launch Service exposure

Each launch creates a `Service(type=LoadBalancer)` using a shared external IP and a unique external port per launch.

Shared-LB settings:
- `AP_SHARED_LB_IP` (optional; if set, forces `Service.spec.loadBalancerIP`)
  - if unset, the launcher will try to discover a canonical shared IP from existing launcher-managed Services and join it
- `AP_SHARED_LB_ANNOTATIONS_JSON` (optional; JSON object of string→string merged into the Service annotations)
  - if unset, the launcher will add `metallb.io/allow-shared-ip=ap-python-launcher`
- `AP_SHARED_LB_PORT_RANGE_START=30000`
- `AP_SHARED_LB_PORT_RANGE_END=39999`

Example for MetalLB shared IP:

```bash
export AP_SHARED_LB_IP=192.0.2.10
export AP_SHARED_LB_ANNOTATIONS_JSON='{"metallb.io/allow-shared-ip":"ap-python-launcher"}'
export AP_SHARED_LB_PORT_RANGE_START=31000
export AP_SHARED_LB_PORT_RANGE_END=31999
```
