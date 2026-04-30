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
  -e AP_KUBECONFIG="$(cat ~/.kube/config)" \
  ap-python-launcher
```

## Configuration

Environment variables (defaults shown):

- `AP_HARBOR_BASE_URL=https://adregistry.fnal.gov`
- `AP_HARBOR_PROJECT=ap-python`
- `AP_HARBOR_USERNAME` (optional)
- `AP_HARBOR_PASSWORD` (optional)
- `AP_KUBECONFIG` (optional; kubeconfig *content* as a string. If unset, uses in-cluster auth.)
- `AP_WORKLOAD_NAMESPACE=ap-python`

### Per-launch Service exposure

By default, each launch creates a `Service(type=LoadBalancer)` and uses `AP_LB_PORT` as the external port.

Optional shared-LB mode (single external IP, unique port per launch):
- `AP_SHARED_LB_IP` (optional; if set, enables shared-LB mode and sets `Service.spec.loadBalancerIP`)
- `AP_SHARED_LB_ANNOTATIONS_JSON` (optional; JSON object of string→string merged into the Service annotations)
- `AP_SHARED_LB_PORT_RANGE_START=30000`
- `AP_SHARED_LB_PORT_RANGE_END=39999`

Example for MetalLB shared IP:

```bash
export AP_SHARED_LB_IP=192.0.2.10
export AP_SHARED_LB_ANNOTATIONS_JSON='{"metallb.io/allow-shared-ip":"ap-python"}'
export AP_SHARED_LB_PORT_RANGE_START=31000
export AP_SHARED_LB_PORT_RANGE_END=31999
```
