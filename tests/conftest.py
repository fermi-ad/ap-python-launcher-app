from __future__ import annotations

import pytest

from ap_python_launcher.config import WebConfig
from ap_python_launcher.launch import KubeLauncher


@pytest.fixture
def base_config():
    return WebConfig(
        harbor_base_url="https://harbor.example.com",
        harbor_project="test-project",
        harbor_username=None,
        harbor_password=None,
        kubeconfig=None,
        kubeconfig_path=None,
        workload_namespace="test-ns",
        app_target_port=14500,
        lb_port=80,
        lb_annotations_json=None,
        shared_lb_ip=None,
        shared_lb_annotations_json='{"metallb.io/allow-shared-ip": "ap-python-launcher"}',
        shared_lb_port_range_start=30000,
        shared_lb_port_range_end=39999,
    )


@pytest.fixture
def mock_batch_api(mocker):
    return mocker.MagicMock()


@pytest.fixture
def mock_core_api(mocker):
    return mocker.MagicMock()


@pytest.fixture
def launcher(mocker, mock_batch_api, mock_core_api):
    """KubeLauncher with all k8s I/O patched out."""
    mocker.patch("ap_python_launcher.launch.config.load_incluster_config")
    mocker.patch("ap_python_launcher.launch.config.load_kube_config")
    mocker.patch(
        "ap_python_launcher.launch.client.BatchV1Api", return_value=mock_batch_api
    )
    mocker.patch(
        "ap_python_launcher.launch.client.CoreV1Api", return_value=mock_core_api
    )
    return KubeLauncher(namespace="test-ns")
