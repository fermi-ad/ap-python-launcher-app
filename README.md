# ap-python-launcher (web)

In-cluster web UI + API for listing Harbor-hosted AP Python app images and launching them as Kubernetes Jobs.

## Accessing a launched app

Each launch creates:
- a `Job` (and Pod) in the workload namespace, and
- a per-launch `Service` of type `LoadBalancer` that selects the Pod by `ap-python.fnal.gov/launch-id`.

The `POST /launch` response includes `launchId` and `serviceName`. Poll [`GET /launch/{launchId}`](src/ap_python_launcher/server.py:117) until `access.urls` becomes non-empty, then open one of the returned URLs.

The per-launch Service is created with an `ownerReference` pointing at the Job. When the Job is deleted (for example via `ttlSecondsAfterFinished`), Kubernetes garbage collection will also delete the Service.

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

This builds the Flutter web frontend into the FastAPI static directory and then starts the mock server with fake Harbor and fake Kubernetes. Open: `http://localhost:8000/`

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

## Prod Docker workflow

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

### Dev Docker workflow

Prereqs:
- Minikube installed and running
- MetalLB installed in the cluster
- A MetalLB IP pool configured (see [`manifests/metallb_ip_pool.yaml`](manifests/metallb_ip_pool.yaml))

Use [`Dockerfile.dev`](Dockerfile.dev) together with [`make docker-dev`](Makefile) for local Minikube + MetalLB testing.

For fake-Harbor + real-Kubernetes testing, a simple launchable image is provided in [`docker/test-app/Dockerfile`](docker/test-app/Dockerfile).

Build and load all fake Harbor images into Minikube with:

```bash
make minikube-load-test-images
```

Then run the launcher with [`AP_MOCK_HARBOR`](README.md:117) enabled and [`AP_MOCK_KUBE`](README.md:118) unset so the fake Harbor catalog resolves to the real images now present in Minikube.

1. Copy [`.env.example`](.env.example) to [`.env`](.env) and adjust values for your cluster.
2. Create the workload namespace:

   ```bash
   kubectl apply -f manifests/ap_python_namespace.yaml
   ```

3. Generate a kubeconfig:

   ```bash
   kubectl config view --raw --minify --flatten > .kubeconfig
   ```

   Verify [`.kubeconfig`](.kubeconfig) contains `certificate-authority-data`, `client-certificate-data`, and `client-key-data` (not `certificate-authority`, `client-certificate`, `client-key`).

   If you need to use a different kubeconfig context, set `KUBECONFIG=...` before running the command above.
4. Run:

```bash
make docker-dev
```

This target:
- builds [`Dockerfile.dev`](Dockerfile.dev)
- passes the env file with `--env-file`
- mounts the kubeconfig file into the container
- sets `AP_KUBECONFIG_PATH` so the app loads kubeconfig from the mounted file

## Configuration

Environment variables (defaults shown):

- `AP_HARBOR_BASE_URL=https://adregistry.fnal.gov`
- `AP_HARBOR_PROJECT=ap-python`
- `AP_HARBOR_USERNAME` (optional)
- `AP_HARBOR_PASSWORD` (optional)
- `AP_MOCK_HARBOR` (optional; if truthy, use the fake Harbor catalog)
- `AP_MOCK_KUBE` (optional; if truthy, use the fake Kubernetes launcher)
- `AP_KUBECONFIG` (optional; kubeconfig *content* as a string. If unset, uses in-cluster auth or a kubeconfig path.)
- `AP_KUBECONFIG_PATH` (optional; path to a kubeconfig file. Used when `AP_KUBECONFIG` is unset.)
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
