"""Integration tests: full API flows through create_app() with only
Harbor HTTP (requests.Session) and Kubernetes client mocked out."""

from __future__ import annotations

from unittest.mock import MagicMock

import pytest

from ap_launcher.discovery import HarborRepo
from ap_launcher.launch import MAX_JOBS_PER_APP, MAX_JOBS_TOTAL


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _make_response(data, raise_http_error=False):
    import requests

    resp = MagicMock()
    resp.json.return_value = data
    if raise_http_error:
        resp.raise_for_status.side_effect = requests.HTTPError()
    else:
        resp.raise_for_status.return_value = None
    return resp


def _make_job(active=None, succeeded=None, failed=None, *, deletion_timestamp=None):
    j = MagicMock()
    j.metadata.deletion_timestamp = deletion_timestamp
    j.status.active = active
    j.status.succeeded = succeeded
    j.status.failed = failed
    return j


def _jobs_list(*jobs):
    lst = MagicMock()
    lst.items = list(jobs)
    return lst


def _pod_list(*names):
    lst = MagicMock()
    lst.items = []
    for n in names:
        p = MagicMock()
        p.metadata.name = n
        lst.items.append(p)
    return lst


def _svc_list(*svcs):
    lst = MagicMock()
    lst.items = list(svcs)
    return lst


@pytest.fixture
def integrated_client(mocker):
    """Full TestClient with only network I/O mocked."""
    mocker.patch("ap_launcher.launch.config.load_incluster_config")
    mocker.patch("ap_launcher.launch.config.load_kube_config")

    from fastapi.testclient import TestClient
    from ap_launcher.server import create_app

    return TestClient(create_app())


# ---------------------------------------------------------------------------
# Apps discovery
# ---------------------------------------------------------------------------


def test_apps_discovery_returns_only_latest_tagged_repos(mocker, integrated_client):
    side_effects = [
        _make_response([{"name": "ap-python/app-a"}, {"name": "ap-python/app-b"}]),
        _make_response([{"tags": [{"name": "latest"}]}]),  # app-a has latest
        _make_response([{"tags": [{"name": "v1.0"}]}]),  # app-b does not
    ]
    mocker.patch("requests.Session.get", side_effect=side_effects)
    resp = integrated_client.get("/apps")
    assert resp.status_code == 200
    apps = resp.json()["apps"]
    assert len(apps) == 1
    assert "app-a" in apps[0]["repo"]


def test_apps_discovery_returns_empty_when_no_repos(mocker, integrated_client):
    mocker.patch("requests.Session.get", return_value=_make_response([]))
    resp = integrated_client.get("/apps")
    assert resp.status_code == 200
    assert resp.json()["apps"] == []


# ---------------------------------------------------------------------------
# Full launch flow
# ---------------------------------------------------------------------------


def _mock_harbor_for_launch(mocker, repo: str = "ap-python/myapp", tag: str = "latest"):
    """Mock HarborClient.list_latest_apps to return a single matching repo."""
    mocker.patch(
        "ap_launcher.server._make_harbor_client",
        return_value=MagicMock(
            list_latest_apps=MagicMock(
                return_value=[HarborRepo(repo=repo, tag=tag, all_tags=(tag,))]
            )
        ),
    )


def test_full_launch_flow(mocker, integrated_client):
    # Mock Harbor: return a matching app so the launch endpoint can resolve the tag
    _mock_harbor_for_launch(mocker)
    mock_batch = MagicMock()
    mock_core = MagicMock()
    mocker.patch("ap_launcher.launch.client.BatchV1Api", return_value=mock_batch)
    mocker.patch("ap_launcher.launch.client.CoreV1Api", return_value=mock_core)

    # No active jobs (under limit)
    mock_batch.list_namespaced_job.return_value = _jobs_list()
    mock_batch.create_namespaced_job.return_value = MagicMock()
    mock_core.create_namespaced_service.return_value = MagicMock()

    resp = integrated_client.post(
        "/launch", json={"repo": "ap-python/myapp", "tag": "latest"}
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["launchId"]
    assert data["jobName"]
    assert data["access"]["status"] == "Pending"


def test_full_launch_then_status_running(mocker, integrated_client):
    _mock_harbor_for_launch(mocker)
    mock_batch = MagicMock()
    mock_core = MagicMock()
    mocker.patch("ap_launcher.launch.client.BatchV1Api", return_value=mock_batch)
    mocker.patch("ap_launcher.launch.client.CoreV1Api", return_value=mock_core)

    mock_batch.list_namespaced_job.return_value = _jobs_list()
    mock_batch.create_namespaced_job.return_value = MagicMock()
    mock_core.create_namespaced_service.return_value = MagicMock()

    launch_resp = integrated_client.post(
        "/launch", json={"repo": "ap-python/myapp", "tag": "latest"}
    )
    launch_id = launch_resp.json()["launchId"]

    # Now poll status — simulate Running job
    running_job = _make_job(active=1)
    running_job.metadata.name = "job-name"
    running_job.status.start_time = None
    running_job.status.completion_time = None
    mock_batch.list_namespaced_job.return_value = _jobs_list(running_job)
    mock_core.list_namespaced_pod.return_value = _pod_list("pod-abc")
    mock_core.list_namespaced_service.return_value = _svc_list()

    status_resp = integrated_client.get(f"/launch/{launch_id}")
    assert status_resp.status_code == 200
    assert status_resp.json()["status"] == "Running"


# ---------------------------------------------------------------------------
# Concurrency limits
# ---------------------------------------------------------------------------


def test_global_job_limit_returns_429(mocker, integrated_client):
    _mock_harbor_for_launch(mocker)
    mock_batch = MagicMock()
    mock_core = MagicMock()
    mocker.patch("ap_launcher.launch.client.BatchV1Api", return_value=mock_batch)
    mocker.patch("ap_launcher.launch.client.CoreV1Api", return_value=mock_core)

    mock_batch.list_namespaced_job.return_value = _jobs_list(
        *[_make_job(active=1) for _ in range(MAX_JOBS_TOTAL)]
    )

    resp = integrated_client.post(
        "/launch", json={"repo": "ap-python/myapp", "tag": "latest"}
    )
    assert resp.status_code == 429


def test_per_app_job_limit_returns_429(mocker, integrated_client):
    _mock_harbor_for_launch(mocker)
    mock_batch = MagicMock()
    mock_core = MagicMock()
    mocker.patch("ap_launcher.launch.client.BatchV1Api", return_value=mock_batch)
    mocker.patch("ap_launcher.launch.client.CoreV1Api", return_value=mock_core)

    under_total = _jobs_list(*[_make_job(active=1) for _ in range(5)])
    at_per_app = _jobs_list(*[_make_job(active=1) for _ in range(MAX_JOBS_PER_APP)])
    mock_batch.list_namespaced_job.side_effect = [under_total, at_per_app]

    resp = integrated_client.post(
        "/launch", json={"repo": "ap-python/myapp", "tag": "latest"}
    )
    assert resp.status_code == 429


# ---------------------------------------------------------------------------
# Readyz reflects env vars
# ---------------------------------------------------------------------------


def test_readyz_reflects_env_vars(mocker, monkeypatch):
    monkeypatch.setenv("AP_HARBOR_PROJECT", "my-custom-project")
    monkeypatch.setenv("AP_WORKLOAD_NAMESPACE", "my-custom-ns")
    mocker.patch("ap_launcher.launch.config.load_incluster_config")
    mocker.patch("ap_launcher.launch.config.load_kube_config")

    from fastapi.testclient import TestClient
    from ap_launcher.server import create_app

    c = TestClient(create_app())
    resp = c.get("/readyz")
    assert resp.status_code == 200
    data = resp.json()
    assert data["harborProject"] == "my-custom-project"
    assert data["workloadNamespace"] == "my-custom-ns"


# ---------------------------------------------------------------------------
# Harbor auth passed through
# ---------------------------------------------------------------------------


def test_harbor_auth_passed_through(mocker, monkeypatch):
    monkeypatch.setenv("AP_HARBOR_USERNAME", "robotuser")
    monkeypatch.setenv("AP_HARBOR_PASSWORD", "robotpass")
    mocker.patch("ap_launcher.launch.config.load_incluster_config")
    mocker.patch("ap_launcher.launch.config.load_kube_config")

    # Capture HarborClient constructor args
    captured = {}
    original_init = __import__(
        "ap_launcher.discovery", fromlist=["HarborClient"]
    ).HarborClient.__init__

    def patched_init(self, base_url, project, username, password):
        captured["username"] = username
        captured["password"] = password
        original_init(self, base_url, project, username, password)

    mocker.patch("ap_launcher.discovery.HarborClient.__init__", patched_init)
    mocker.patch("requests.Session.get", return_value=_make_response([]))

    from fastapi.testclient import TestClient
    from ap_launcher.server import create_app

    c = TestClient(create_app())
    c.get("/apps")
    assert captured.get("username") == "robotuser"
    assert captured.get("password") == "robotpass"
