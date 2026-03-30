from __future__ import annotations

from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles

from .config import load_web_config
from .discovery import HarborClient
from .launch import KubeLauncher, LaunchLimitExceededError


def create_app() -> FastAPI:
    cfg = load_web_config()

    app = FastAPI(title="ap-python-launcher", version="0.1.0")

    static_dir = Path(__file__).parent / "static"
    app.mount("/static", StaticFiles(directory=str(static_dir)), name="static")

    @app.get("/", response_class=HTMLResponse)
    def index() -> str:
        return (static_dir / "index.html").read_text(encoding="utf-8")

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
        hc = HarborClient(
            cfg.harbor_base_url,
            cfg.harbor_project,
            cfg.harbor_username,
            cfg.harbor_password,
        )

        apps = hc.list_latest_apps()
        return {
            "source": "harbor",
            "project": cfg.harbor_project,
            "apps": [{"repo": a.repo, "tag": a.tag} for a in apps],
        }

    @app.post("/launch")
    def launch(body: dict) -> dict:
        repo = body.get("repo")
        tag = body.get("tag", "latest")
        if not isinstance(repo, str) or not repo:
            raise HTTPException(status_code=400, detail="Missing/invalid repo")
        if not isinstance(tag, str) or not tag:
            raise HTTPException(status_code=400, detail="Missing/invalid tag")

        # Image ref must be a registry host + repository path.
        registry_host = cfg.harbor_base_url.replace("https://", "").replace(
            "http://", ""
        )
        image = f"{registry_host}/{repo}:{tag}"

        kl = KubeLauncher(
            namespace=cfg.workload_namespace,
            kubeconfig_content=cfg.kubeconfig,
            app_target_port=cfg.app_target_port,
            lb_port=cfg.lb_port,
            lb_annotations_json=cfg.lb_annotations_json,
        )
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
            "access": {"status": "Pending", "urls": []},
        }

    @app.get("/launch/{launch_id}")
    def launch_status(launch_id: str) -> dict:
        kl = KubeLauncher(
            namespace=cfg.workload_namespace,
            kubeconfig_content=cfg.kubeconfig,
            app_target_port=cfg.app_target_port,
            lb_port=cfg.lb_port,
            lb_annotations_json=cfg.lb_annotations_json,
        )
        return kl.get_launch_status(launch_id=launch_id)

    return app


app = create_app()
