"""Concrete in-memory fakes for HarborClient and KubeLauncher.

Shared by:
  - AP_MOCK_MODE server: run `AP_MOCK_MODE=true uvicorn ...` for local UI dev
  - Unit tests: inject via fixtures instead of MagicMock where fine-grained
    control (call_args, side_effect) is not required
"""

from __future__ import annotations

import uuid

from ..discovery import HarborRepo
from ..launch import LaunchResult


DEFAULT_REPOS = [
    HarborRepo("ap-python/demo-app", "latest"),
    HarborRepo("ap-python/analysis-tool", "latest"),
    HarborRepo("ap-python/jupyter-env", "latest"),
]


class FakeHarborClient:
    """Returns a configurable static list of repos; never contacts Harbor."""

    def __init__(
        self,
        base_url: str | None = None,
        project: str | None = None,
        username: str | None = None,
        password: str | None = None,
        *,
        repos: list[HarborRepo] | None = None,
    ):
        self._repos: list[HarborRepo] = (
            repos if repos is not None else list(DEFAULT_REPOS)
        )

    def list_latest_apps(self) -> list[HarborRepo]:
        return list(self._repos)


class FakeKubeLauncher:
    """Stateful in-memory launcher.

    Job state is stored at the class level so that multiple instances (one per
    request, as the real server creates them) share the same store.  Call
    ``FakeKubeLauncher.reset()`` in test teardown to clear state.

    Status progression per job (counted by ``get_launch_status`` calls):
      polls 1-2 → Pending
      polls 3-5 → Running
      poll  6+  → Running + access URL (frontend shows "Ready")
    """

    _jobs: dict[str, dict] = {}

    def __init__(
        self,
        namespace: str = "fake-ns",
        *,
        kubeconfig_content: str | None = None,
        app_target_port: int = 14500,
        lb_port: int = 80,
        lb_annotations_json: str | None = None,
    ):
        self.namespace = namespace
        self.lb_port = lb_port
        # Records kwargs from the most recent create_job call; useful in tests.
        self.last_create_job_kwargs: dict = {}

    @classmethod
    def reset(cls) -> None:
        cls._jobs.clear()

    def create_job(
        self,
        *,
        image: str,
        repo: str,
        tag: str,
        requested_by: str | None = None,
    ) -> LaunchResult:
        self.last_create_job_kwargs = {
            "image": image,
            "repo": repo,
            "tag": tag,
            "requested_by": requested_by,
        }
        launch_id = str(uuid.uuid4())
        safe_repo = repo.split("/")[-1].replace("_", "-").replace(".", "-")
        short = launch_id.split("-")[0]
        job_name = f"fake-{safe_repo}-{short}"
        service_name = f"fake-svc-{short}"
        self.__class__._jobs[launch_id] = {
            "repo": repo,
            "tag": tag,
            "image": image,
            "job_name": job_name,
            "service_name": service_name,
            "poll_count": 0,
        }
        return LaunchResult(
            launch_id=launch_id,
            namespace=self.namespace,
            job_name=job_name,
            service_name=service_name,
        )

    def get_launch_status(self, *, launch_id: str) -> dict:
        if launch_id not in self.__class__._jobs:
            return {"launchId": launch_id, "status": "NotFound"}

        job = self.__class__._jobs[launch_id]
        job["poll_count"] += 1
        count = job["poll_count"]

        if count <= 2:
            status, urls = "Pending", []
        elif count <= 5:
            status, urls = "Running", []
        else:
            status = "Running"
            urls = [f"http://fake-lb.example.com:{self.lb_port}/"]

        return {
            "launchId": launch_id,
            "namespace": self.namespace,
            "jobName": job["job_name"],
            "podName": f"fake-pod-{launch_id.split('-')[0]}",
            "status": status,
            "startTime": None,
            "completionTime": None,
            "serviceName": job["service_name"],
            "access": {
                "status": "Ready" if urls else "Pending",
                "urls": urls,
            },
        }

    def delete_job(self, *, launch_id: str) -> dict:
        if launch_id not in self.__class__._jobs:
            return {"launchId": launch_id, "deleted": False, "reason": "NotFound"}
        job = self.__class__._jobs.pop(launch_id)
        return {"launchId": launch_id, "deleted": True, "jobName": job["job_name"]}
