from __future__ import annotations

import dataclasses

import pytest

from ap_python_launcher.config import load_web_config

# All AP_* env vars to clear for isolation
_AP_VARS = [
    "AP_HARBOR_BASE_URL",
    "AP_HARBOR_PROJECT",
    "AP_HARBOR_USERNAME",
    "AP_HARBOR_PASSWORD",
    "AP_KUBECONFIG",
    "AP_WORKLOAD_NAMESPACE",
    "AP_APP_TARGET_PORT",
    "AP_LB_PORT",
    "AP_LB_ANNOTATIONS_JSON",
    "AP_SHARED_LB_IP",
    "AP_SHARED_LB_ANNOTATIONS_JSON",
    "AP_SHARED_LB_PORT_RANGE_START",
    "AP_SHARED_LB_PORT_RANGE_END",
]


@pytest.fixture(autouse=True)
def _clear_env(monkeypatch):
    for var in _AP_VARS:
        monkeypatch.delenv(var, raising=False)


def test_defaults_when_no_env_vars_set():
    cfg = load_web_config()
    assert cfg.harbor_base_url == "https://adregistry.fnal.gov"
    assert cfg.harbor_project == "ap-python"
    assert cfg.harbor_username is None
    assert cfg.harbor_password is None
    assert cfg.kubeconfig is None
    assert cfg.workload_namespace == "ap-python"
    assert cfg.app_target_port == 14500
    assert cfg.lb_port == 80
    assert cfg.lb_annotations_json is None
    assert cfg.shared_lb_ip is None
    assert cfg.shared_lb_annotations_json is None
    assert cfg.shared_lb_port_range_start == 30000
    assert cfg.shared_lb_port_range_end == 39999


def test_all_env_vars_overridden(monkeypatch):
    monkeypatch.setenv("AP_HARBOR_BASE_URL", "https://myharbor.io")
    monkeypatch.setenv("AP_HARBOR_PROJECT", "my-project")
    monkeypatch.setenv("AP_HARBOR_USERNAME", "myuser")
    monkeypatch.setenv("AP_HARBOR_PASSWORD", "mypass")
    monkeypatch.setenv("AP_KUBECONFIG", "kubeconfig-content")
    monkeypatch.setenv("AP_WORKLOAD_NAMESPACE", "my-ns")
    monkeypatch.setenv("AP_APP_TARGET_PORT", "9000")
    monkeypatch.setenv("AP_LB_PORT", "8080")
    monkeypatch.setenv("AP_LB_ANNOTATIONS_JSON", '{"k": "v"}')
    monkeypatch.setenv("AP_SHARED_LB_IP", "192.0.2.10")
    monkeypatch.setenv(
        "AP_SHARED_LB_ANNOTATIONS_JSON", '{"metallb.io/allow-shared-ip": "ap-python"}'
    )
    monkeypatch.setenv("AP_SHARED_LB_PORT_RANGE_START", "31000")
    monkeypatch.setenv("AP_SHARED_LB_PORT_RANGE_END", "31010")

    cfg = load_web_config()
    assert cfg.harbor_base_url == "https://myharbor.io"
    assert cfg.harbor_project == "my-project"
    assert cfg.harbor_username == "myuser"
    assert cfg.harbor_password == "mypass"
    assert cfg.kubeconfig == "kubeconfig-content"
    assert cfg.workload_namespace == "my-ns"
    assert cfg.app_target_port == 9000
    assert cfg.lb_port == 8080
    assert cfg.lb_annotations_json == '{"k": "v"}'
    assert cfg.shared_lb_ip == "192.0.2.10"
    assert (
        cfg.shared_lb_annotations_json == '{"metallb.io/allow-shared-ip": "ap-python"}'
    )
    assert cfg.shared_lb_port_range_start == 31000
    assert cfg.shared_lb_port_range_end == 31010


def test_harbor_username_and_password_from_env(monkeypatch):
    monkeypatch.setenv("AP_HARBOR_USERNAME", "user")
    monkeypatch.setenv("AP_HARBOR_PASSWORD", "pass")
    cfg = load_web_config()
    assert cfg.harbor_username == "user"
    assert cfg.harbor_password == "pass"


def test_app_target_port_parsed_as_int(monkeypatch):
    monkeypatch.setenv("AP_APP_TARGET_PORT", "9000")
    cfg = load_web_config()
    assert cfg.app_target_port == 9000
    assert isinstance(cfg.app_target_port, int)


def test_lb_port_parsed_as_int(monkeypatch):
    monkeypatch.setenv("AP_LB_PORT", "8080")
    cfg = load_web_config()
    assert cfg.lb_port == 8080
    assert isinstance(cfg.lb_port, int)


def test_invalid_port_raises_value_error(monkeypatch):
    monkeypatch.setenv("AP_APP_TARGET_PORT", "notanint")
    with pytest.raises(ValueError):
        load_web_config()


def test_empty_string_numeric_envs_use_defaults(monkeypatch):
    monkeypatch.setenv("AP_APP_TARGET_PORT", "")
    monkeypatch.setenv("AP_LB_PORT", "")
    monkeypatch.setenv("AP_SHARED_LB_PORT_RANGE_START", "")
    monkeypatch.setenv("AP_SHARED_LB_PORT_RANGE_END", "")

    cfg = load_web_config()

    assert cfg.app_target_port == 14500
    assert cfg.lb_port == 80
    assert cfg.shared_lb_port_range_start == 30000
    assert cfg.shared_lb_port_range_end == 39999


def test_lb_annotations_json_preserved_as_string(monkeypatch):
    monkeypatch.setenv(
        "AP_LB_ANNOTATIONS_JSON",
        '{"service.beta.kubernetes.io/aws-load-balancer-type": "nlb"}',
    )
    cfg = load_web_config()
    assert (
        cfg.lb_annotations_json
        == '{"service.beta.kubernetes.io/aws-load-balancer-type": "nlb"}'
    )


def test_webconfig_is_frozen():
    cfg = load_web_config()
    with pytest.raises(dataclasses.FrozenInstanceError):
        cfg.harbor_project = "new-project"  # type: ignore[misc]
