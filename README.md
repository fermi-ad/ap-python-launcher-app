# ap-python-launcher (web)

In-cluster web UI + API for listing Harbor-hosted AP Python app images and launching them as Kubernetes Jobs.

## Run locally

```bash
python -m pip install -e .
uvicorn ap_python_launcher.server:app --reload --port 8080
```

Then open: `http://localhost:8080/`

## Configuration

Environment variables (defaults shown):

- `AP_HARBOR_BASE_URL=https://adregistry.fnal.gov`
- `AP_HARBOR_PROJECT=ap-python`
- `AP_HARBOR_USERNAME` (optional)
- `AP_HARBOR_PASSWORD` (optional)
- `AP_KUBECONFIG` (optional; kubeconfig *content* as a string. If unset, uses in-cluster auth.)
- `AP_WORKLOAD_NAMESPACE=ap-python`
