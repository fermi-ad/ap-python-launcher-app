from __future__ import annotations

import os
from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.requests import Request
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from starlette.middleware.base import BaseHTTPMiddleware

from .config import WebConfig, load_web_config
from .discovery import HarborClient
from .launch import KubeLauncher, LaunchLimitExceededError


def _make_harbor_client(cfg: WebConfig) -> HarborClient:
    if os.environ.get("AP_MOCK_MODE", "").lower() in ("1", "true", "yes"):
        from .test.fakes import FakeHarborClient

        return FakeHarborClient()  # type: ignore[return-value]
    return HarborClient(
        cfg.harbor_base_url,
        cfg.harbor_project,
        cfg.harbor_username,
        cfg.harbor_password,
    )


def _make_kube_launcher(cfg: WebConfig) -> KubeLauncher:
    if os.environ.get("AP_MOCK_MODE", "").lower() in ("1", "true", "yes"):
        from .test.fakes import FakeKubeLauncher

        return FakeKubeLauncher(namespace=cfg.workload_namespace)  # type: ignore[return-value]
    return KubeLauncher(
        namespace=cfg.workload_namespace,
        kubeconfig_content=cfg.kubeconfig,
        app_target_port=cfg.app_target_port,
        lb_port=cfg.lb_port,
        lb_annotations_json=cfg.lb_annotations_json,
    )


_URL_PREFIX = "/ap-python"


class StripPrefixMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        path = request.scope["path"]
        if path.startswith(_URL_PREFIX):
            request.scope["path"] = path[len(_URL_PREFIX) :] or "/"
        return await call_next(request)


def create_app() -> FastAPI:
    cfg = load_web_config()

    app = FastAPI(title="ap-python-launcher", version="0.1.0")
    app.add_middleware(StripPrefixMiddleware)

    @app.get("/healthz")
    def healthz() -> dict:
        return {"ok": True}

    @app.get("/readyz")
    def readyz() -> dict:
        return {
            "ok": True,
            "harborProject": cfg.harbor_project,
            "workloadNamespace": cfg.workload_namespace,
        }

    @app.get("/apps")
    def list_apps() -> dict:
        hc = _make_harbor_client(cfg)
        apps = hc.list_latest_apps()
        return {
            "source": "harbor",
            "project": cfg.harbor_project,
            "apps": [
                {"repo": a.repo, "tag": a.tag, "allTags": list(a.all_tags)}
                for a in apps
            ],
        }

    @app.post("/launch")
    def launch(body: dict) -> dict:
        repo = body.get("repo")
        if not isinstance(repo, str) or not repo:
            raise HTTPException(status_code=400, detail="Missing/invalid repo")

        # Resolve the tag server-side so the client cannot specify an arbitrary one.
        hc = _make_harbor_client(cfg)
        apps = hc.list_latest_apps()
        match = next((a for a in apps if a.repo == repo), None)
        if match is None:
            raise HTTPException(status_code=404, detail=f"App not found: {repo}")
        tag = match.tag

        # Image ref must be a registry host + repository path.
        registry_host = cfg.harbor_base_url.replace("https://", "").replace(
            "http://", ""
        )
        image = f"{registry_host}/{repo}:{tag}"

        kl = _make_kube_launcher(cfg)
        try:
            res = kl.create_job(image=image, repo=repo, tag=tag)
        except LaunchLimitExceededError as e:
            raise HTTPException(status_code=429, detail=str(e)) from e
        except ValueError as e:
            raise HTTPException(status_code=400, detail=str(e)) from e

        # LoadBalancer ingress will usually be assigned asynchronously; user can poll
        # GET /launch/{launchId} for access URLs.
        return {
            "launchId": res.launch_id,
            "jobName": res.job_name,
            "serviceName": res.service_name,
            "namespace": res.namespace,
            "tag": tag,
            "access": {"status": "Pending", "urls": []},
        }

    @app.get("/launch/{launch_id}")
    def launch_status(launch_id: str) -> dict:
        return _make_kube_launcher(cfg).get_launch_status(launch_id=launch_id)

    @app.delete("/launch/{launch_id}")
    def delete_launch(launch_id: str) -> dict:
        return _make_kube_launcher(cfg).delete_job(launch_id=launch_id)

    static_dir = Path(__file__).parent / "static"
    # Serve Flutter web build output at the root (/, /flutter_bootstrap.js, /assets/*, etc.)
    app.mount("/", StaticFiles(directory=str(static_dir), html=True), name="static")

    return app


app = create_app()
