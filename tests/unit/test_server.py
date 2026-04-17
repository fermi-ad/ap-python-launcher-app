from __future__ import annotations

import pytest

from ap_launcher.config import WebConfig
from ap_launcher.discovery import HarborRepo
from ap_launcher.test.fakes import FakeHarborClient, FakeKubeLauncher
from ap_launcher.launch import LaunchLimitExceededError


# ---------------------------------------------------------------------------
# Fixtures: TestClient built from create_app() with fakes injected
# ---------------------------------------------------------------------------


@pytest.fixture
def mock_harbor(mocker):
    """Inject a FakeHarborClient (empty by default; set ._repos to customise)."""
    instance = FakeHarborClient(repos=[])
    mocker.patch("ap_launcher.server.HarborClient", return_value=instance)
    return instance


@pytest.fixture
def mock_launcher(mocker):
    """Inject a FakeKubeLauncher; resets class-level job state after each test."""
    instance = FakeKubeLauncher(namespace="test-ns")
    mocker.patch("ap_launcher.server.KubeLauncher", return_value=instance)
    yield instance
    FakeKubeLauncher.reset()


@pytest.fixture
def client(mocker, base_config, mock_harbor, mock_launcher):
    mocker.patch("ap_launcher.server.load_web_config", return_value=base_config)
    from fastapi.testclient import TestClient
    from ap_launcher.server import create_app

    return TestClient(create_app())


# ---------------------------------------------------------------------------
# GET /
# ---------------------------------------------------------------------------


def test_get_root_returns_html(client):
    resp = client.get("/")
    assert resp.status_code == 200
    assert "text/html" in resp.headers["content-type"]
    assert "flutter_bootstrap.js" in resp.text


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
    mock_harbor._repos = [
        HarborRepo(repo="proj/app", tag="v1.0.0", all_tags=("v1.0.0", "latest"))
    ]
    resp = client.get("/apps")
    assert resp.status_code == 200
    data = resp.json()
    assert data["apps"] == [
        {"repo": "proj/app", "tag": "v1.0.0", "allTags": ["v1.0.0", "latest"]}
    ]


def test_apps_returns_empty_list_when_no_apps(client, mock_harbor):
    # mock_harbor starts empty
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
    mock_cls = mocker.patch("ap_launcher.server.HarborClient")
    mock_cls.return_value.list_latest_apps.return_value = []
    mocker.patch(
        "ap_launcher.server.KubeLauncher", return_value=FakeKubeLauncher(namespace="ns")
    )

    from fastapi.testclient import TestClient
    from ap_launcher.server import create_app

    c = TestClient(create_app())
    c.get("/apps")
    mock_cls.assert_called_once_with(
        cfg.harbor_base_url, cfg.harbor_project, "myuser", "mypass"
    )


# ---------------------------------------------------------------------------
# POST /launch
# ---------------------------------------------------------------------------

# Repo used across launch tests; must exist in mock_harbor._repos.
_LAUNCH_REPO = "proj/app"
_LAUNCH_TAG = "v1.0.0"
_LAUNCH_APP = HarborRepo(
    repo=_LAUNCH_REPO, tag=_LAUNCH_TAG, all_tags=(_LAUNCH_TAG, "latest")
)


def test_launch_missing_repo_returns_400(client):
    resp = client.post("/launch", json={})
    assert resp.status_code == 400
    assert "repo" in resp.json()["detail"].lower()


def test_launch_empty_repo_returns_400(client):
    resp = client.post("/launch", json={"repo": ""})
    assert resp.status_code == 400


def test_launch_unknown_repo_returns_404(client, mock_harbor):
    # mock_harbor has no repos by default
    resp = client.post("/launch", json={"repo": "proj/unknown"})
    assert resp.status_code == 404


def test_launch_success_returns_launch_id(client, mock_harbor):
    mock_harbor._repos = [_LAUNCH_APP]
    resp = client.post("/launch", json={"repo": _LAUNCH_REPO})
    assert resp.status_code == 200
    assert resp.json()["launchId"]


def test_launch_response_includes_resolved_tag(client, mock_harbor):
    mock_harbor._repos = [_LAUNCH_APP]
    resp = client.post("/launch", json={"repo": _LAUNCH_REPO})
    assert resp.json()["tag"] == _LAUNCH_TAG


def test_launch_uses_harbor_resolved_tag_not_client_tag(
    client, mock_harbor, mock_launcher
):
    """Client cannot override the tag — the backend always resolves it from Harbor."""
    mock_harbor._repos = [_LAUNCH_APP]
    # Send a different tag in the body; it should be ignored.
    client.post("/launch", json={"repo": _LAUNCH_REPO, "tag": "evil-tag"})
    assert mock_launcher.last_create_job_kwargs["tag"] == _LAUNCH_TAG


def test_launch_strips_https_from_image_ref(
    client, mock_harbor, mock_launcher, base_config
):
    mock_harbor._repos = [_LAUNCH_APP]
    client.post("/launch", json={"repo": _LAUNCH_REPO})
    assert not mock_launcher.last_create_job_kwargs["image"].startswith("https://")


def test_launch_strips_http_from_image_ref(mocker, base_config):
    cfg = WebConfig(
        harbor_base_url="http://registry.example.com",
        harbor_project="proj",
        harbor_username=None,
        harbor_password=None,
        kubeconfig=None,
        workload_namespace="ns",
        app_target_port=14500,
        lb_port=80,
        lb_annotations_json=None,
    )
    mocker.patch("ap_launcher.server.load_web_config", return_value=cfg)
    instance = FakeKubeLauncher(namespace="ns")
    mocker.patch("ap_launcher.server.KubeLauncher", return_value=instance)
    fake_harbor = FakeHarborClient(
        repos=[HarborRepo(repo="proj/app", tag="v1.0", all_tags=("v1.0", "latest"))]
    )
    mocker.patch("ap_launcher.server.HarborClient", return_value=fake_harbor)

    from fastapi.testclient import TestClient
    from ap_launcher.server import create_app

    c = TestClient(create_app())
    c.post("/launch", json={"repo": "proj/app"})
    image_arg = instance.last_create_job_kwargs["image"]
    assert not image_arg.startswith("http://")
    assert "registry.example.com" in image_arg


def test_launch_constructs_image_from_config_host_and_repo(
    client, mock_harbor, mock_launcher, base_config
):
    mock_harbor._repos = [
        HarborRepo(repo="proj/myapp", tag="v1", all_tags=("v1", "latest"))
    ]
    client.post("/launch", json={"repo": "proj/myapp"})
    image_arg = mock_launcher.last_create_job_kwargs["image"]
    assert "harbor.example.com" in image_arg
    assert "proj/myapp" in image_arg
    assert "v1" in image_arg


def test_launch_limit_exceeded_returns_429(client, mock_harbor, mock_launcher, mocker):
    mock_harbor._repos = [_LAUNCH_APP]
    mocker.patch.object(
        mock_launcher,
        "create_job",
        side_effect=LaunchLimitExceededError("too many jobs"),
    )
    resp = client.post("/launch", json={"repo": _LAUNCH_REPO})
    assert resp.status_code == 429
    assert "too many jobs" in resp.json()["detail"]


def test_launch_value_error_returns_400(client, mock_harbor, mock_launcher, mocker):
    mock_harbor._repos = [_LAUNCH_APP]
    mocker.patch.object(
        mock_launcher, "create_job", side_effect=ValueError("bad annotations")
    )
    resp = client.post("/launch", json={"repo": _LAUNCH_REPO})
    assert resp.status_code == 400
    assert "bad annotations" in resp.json()["detail"]


def test_launch_access_field_is_pending(client, mock_harbor):
    mock_harbor._repos = [_LAUNCH_APP]
    resp = client.post("/launch", json={"repo": _LAUNCH_REPO})
    data = resp.json()
    assert data["access"]["status"] == "Pending"
    assert data["access"]["urls"] == []


# ---------------------------------------------------------------------------
# GET /launch/{launch_id}
# ---------------------------------------------------------------------------


def test_launch_status_returns_valid_status(client, mock_harbor):
    mock_harbor._repos = [_LAUNCH_APP]
    launch_id = client.post("/launch", json={"repo": _LAUNCH_REPO}).json()["launchId"]
    resp = client.get(f"/launch/{launch_id}")
    assert resp.status_code == 200
    assert resp.json()["status"] in ("Pending", "Running", "Ending")


def test_launch_status_returns_correct_launch_id(client, mock_harbor):
    mock_harbor._repos = [_LAUNCH_APP]
    launch_id = client.post("/launch", json={"repo": _LAUNCH_REPO}).json()["launchId"]
    resp = client.get(f"/launch/{launch_id}")
    assert resp.json()["launchId"] == launch_id


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
