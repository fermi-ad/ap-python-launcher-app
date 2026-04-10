from __future__ import annotations

from unittest.mock import MagicMock

import pytest

from ap_launcher.config import WebConfig
from ap_launcher.discovery import HarborRepo
from ap_launcher.launch import LaunchLimitExceededError, LaunchResult


# ---------------------------------------------------------------------------
# Fixture: TestClient built from create_app() with all external I/O mocked
# ---------------------------------------------------------------------------

@pytest.fixture
def mock_harbor(mocker):
    """Return a mock HarborClient instance (injected via class patch)."""
    mock_cls = mocker.patch("ap_launcher.server.HarborClient")
    mock_instance = MagicMock()
    mock_instance.list_latest_apps.return_value = []
    mock_cls.return_value = mock_instance
    return mock_instance


@pytest.fixture
def mock_launcher(mocker):
    """Return a mock KubeLauncher instance (injected via class patch)."""
    mocker.patch("ap_launcher.launch.config.load_incluster_config")
    mocker.patch("ap_launcher.launch.config.load_kube_config")
    mock_cls = mocker.patch("ap_launcher.server.KubeLauncher")
    mock_instance = MagicMock()
    mock_cls.return_value = mock_instance
    return mock_instance


@pytest.fixture
def client(mocker, base_config, mock_harbor, mock_launcher):
    mocker.patch("ap_launcher.server.load_web_config", return_value=base_config)
    from fastapi.testclient import TestClient
    # Import create_app AFTER patching load_web_config
    from ap_launcher.server import create_app
    return TestClient(create_app())


# ---------------------------------------------------------------------------
# GET /
# ---------------------------------------------------------------------------

def test_get_root_returns_html(client):
    resp = client.get("/")
    assert resp.status_code == 200
    assert "text/html" in resp.headers["content-type"]
    assert "AP Python Launcher" in resp.text


# ---------------------------------------------------------------------------
# GET /healthz
# ---------------------------------------------------------------------------

def test_healthz_returns_ok_true(client):
    resp = client.get("/healthz")
    assert resp.status_code == 200
    assert resp.json() == {"ok": True}


# ---------------------------------------------------------------------------
# GET /readyz
# ---------------------------------------------------------------------------

def test_readyz_returns_project_and_namespace(client, base_config):
    resp = client.get("/readyz")
    assert resp.status_code == 200
    data = resp.json()
    assert data["harborProject"] == base_config.harbor_project
    assert data["workloadNamespace"] == base_config.workload_namespace


def test_readyz_ok_is_true(client):
    resp = client.get("/readyz")
    assert resp.json()["ok"] is True


# ---------------------------------------------------------------------------
# GET /apps
# ---------------------------------------------------------------------------

def test_apps_returns_list_with_apps(client, mock_harbor):
    mock_harbor.list_latest_apps.return_value = [HarborRepo(repo="proj/app", tag="latest")]
    resp = client.get("/apps")
    assert resp.status_code == 200
    data = resp.json()
    assert data["apps"] == [{"repo": "proj/app", "tag": "latest"}]


def test_apps_returns_empty_list_when_no_apps(client, mock_harbor):
    mock_harbor.list_latest_apps.return_value = []
    resp = client.get("/apps")
    assert resp.status_code == 200
    assert resp.json()["apps"] == []


def test_apps_source_field_is_harbor(client):
    resp = client.get("/apps")
    assert resp.json()["source"] == "harbor"


def test_apps_project_field_matches_config(client, base_config):
    resp = client.get("/apps")
    assert resp.json()["project"] == base_config.harbor_project


def test_apps_passes_credentials_to_harbor_client(mocker, base_config):
    cfg = WebConfig(
        harbor_base_url="https://harbor.example.com",
        harbor_project="proj",
        harbor_username="myuser",
        harbor_password="mypass",
        kubeconfig=None,
        workload_namespace="ns",
        app_target_port=14500,
        lb_port=80,
        lb_annotations_json=None,
    )
    mocker.patch("ap_launcher.server.load_web_config", return_value=cfg)
    mocker.patch("ap_launcher.launch.config.load_incluster_config")
    mocker.patch("ap_launcher.launch.config.load_kube_config")
    mock_cls = mocker.patch("ap_launcher.server.HarborClient")
    mock_cls.return_value.list_latest_apps.return_value = []
    mocker.patch("ap_launcher.server.KubeLauncher")

    from fastapi.testclient import TestClient
    from ap_launcher.server import create_app
    c = TestClient(create_app())
    c.get("/apps")
    mock_cls.assert_called_once_with(cfg.harbor_base_url, cfg.harbor_project, "myuser", "mypass")


# ---------------------------------------------------------------------------
# POST /launch
# ---------------------------------------------------------------------------

def test_launch_missing_repo_returns_400(client):
    resp = client.post("/launch", json={"tag": "latest"})
    assert resp.status_code == 400
    assert "repo" in resp.json()["detail"].lower()


def test_launch_empty_repo_returns_400(client):
    resp = client.post("/launch", json={"repo": "", "tag": "latest"})
    assert resp.status_code == 400


def test_launch_missing_tag_defaults_to_latest(client, mock_launcher):
    mock_launcher.create_job.return_value = LaunchResult(
        launch_id="id1", namespace="test-ns", job_name="job-1", service_name="svc-1"
    )
    client.post("/launch", json={"repo": "proj/app"})
    call_kwargs = mock_launcher.create_job.call_args[1]
    assert call_kwargs["tag"] == "latest"


def test_launch_empty_tag_returns_400(client):
    resp = client.post("/launch", json={"repo": "proj/app", "tag": ""})
    assert resp.status_code == 400


def test_launch_success_returns_launch_id(client, mock_launcher):
    mock_launcher.create_job.return_value = LaunchResult(
        launch_id="launch-abc", namespace="test-ns", job_name="job-1", service_name="svc-1"
    )
    resp = client.post("/launch", json={"repo": "proj/app", "tag": "latest"})
    assert resp.status_code == 200
    assert resp.json()["launchId"] == "launch-abc"


def test_launch_strips_https_from_image_ref(client, mock_launcher, base_config):
    mock_launcher.create_job.return_value = LaunchResult(
        launch_id="x", namespace="ns", job_name="j", service_name="s"
    )
    client.post("/launch", json={"repo": "proj/app", "tag": "latest"})
    image_arg = mock_launcher.create_job.call_args[1]["image"]
    assert not image_arg.startswith("https://")


def test_launch_strips_http_from_image_ref(mocker, base_config):
    cfg = WebConfig(
        harbor_base_url="http://registry.example.com",
        harbor_project="proj",
        harbor_username=None, harbor_password=None, kubeconfig=None,
        workload_namespace="ns", app_target_port=14500, lb_port=80, lb_annotations_json=None,
    )
    mocker.patch("ap_launcher.server.load_web_config", return_value=cfg)
    mocker.patch("ap_launcher.launch.config.load_incluster_config")
    mocker.patch("ap_launcher.launch.config.load_kube_config")
    mock_cls = mocker.patch("ap_launcher.server.KubeLauncher")
    mock_inst = MagicMock()
    mock_inst.create_job.return_value = LaunchResult("x", "ns", "j", "s")
    mock_cls.return_value = mock_inst
    mocker.patch("ap_launcher.server.HarborClient").return_value.list_latest_apps.return_value = []

    from fastapi.testclient import TestClient
    from ap_launcher.server import create_app
    c = TestClient(create_app())
    c.post("/launch", json={"repo": "proj/app", "tag": "v1"})
    image_arg = mock_inst.create_job.call_args[1]["image"]
    assert not image_arg.startswith("http://")
    assert "registry.example.com" in image_arg


def test_launch_constructs_image_from_config_host_and_repo(client, mock_launcher, base_config):
    mock_launcher.create_job.return_value = LaunchResult("x", "ns", "j", "s")
    client.post("/launch", json={"repo": "proj/myapp", "tag": "v1"})
    image_arg = mock_launcher.create_job.call_args[1]["image"]
    assert "harbor.example.com" in image_arg
    assert "proj/myapp" in image_arg
    assert "v1" in image_arg


def test_launch_limit_exceeded_returns_429(client, mock_launcher):
    mock_launcher.create_job.side_effect = LaunchLimitExceededError("too many jobs")
    resp = client.post("/launch", json={"repo": "proj/app", "tag": "latest"})
    assert resp.status_code == 429
    assert "too many jobs" in resp.json()["detail"]


def test_launch_value_error_returns_400(client, mock_launcher):
    mock_launcher.create_job.side_effect = ValueError("bad annotations")
    resp = client.post("/launch", json={"repo": "proj/app", "tag": "latest"})
    assert resp.status_code == 400
    assert "bad annotations" in resp.json()["detail"]


def test_launch_access_field_is_pending(client, mock_launcher):
    mock_launcher.create_job.return_value = LaunchResult("x", "ns", "j", "s")
    resp = client.post("/launch", json={"repo": "proj/app", "tag": "latest"})
    data = resp.json()
    assert data["access"]["status"] == "Pending"
    assert data["access"]["urls"] == []


# ---------------------------------------------------------------------------
# GET /launch/{launch_id}
# ---------------------------------------------------------------------------

def test_launch_status_delegates_to_kube_launcher(client, mock_launcher):
    mock_launcher.get_launch_status.return_value = {"launchId": "abc", "status": "Running"}
    resp = client.get("/launch/abc")
    assert resp.status_code == 200
    assert resp.json()["status"] == "Running"


def test_launch_status_passes_correct_launch_id(client, mock_launcher):
    mock_launcher.get_launch_status.return_value = {"launchId": "test-id-123"}
    client.get("/launch/test-id-123")
    mock_launcher.get_launch_status.assert_called_once_with(launch_id="test-id-123")


# ---------------------------------------------------------------------------
# StripPrefixMiddleware
# ---------------------------------------------------------------------------

def test_strip_prefix_strips_ap_python(client):
    resp = client.get("/ap-python/healthz")
    assert resp.status_code == 200
    assert resp.json() == {"ok": True}


def test_non_prefixed_path_unchanged(client):
    resp = client.get("/healthz")
    assert resp.status_code == 200


def test_bare_prefix_becomes_root(client):
    resp = client.get("/ap-python")
    assert resp.status_code == 200
    assert "text/html" in resp.headers["content-type"]
