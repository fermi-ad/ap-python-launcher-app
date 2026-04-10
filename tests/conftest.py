from __future__ import annotations

import pytest

from ap_launcher.config import WebConfig
from ap_launcher.launch import KubeLauncher


@pytest.fixture
def base_config():
    return WebConfig(
        harbor_base_url="https://harbor.example.com",
        harbor_project="test-project",
        harbor_username=None,
        harbor_password=None,
        kubeconfig=None,
        workload_namespace="test-ns",
        app_target_port=14500,
        lb_port=80,
        lb_annotations_json=None,
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
    mocker.patch("ap_launcher.launch.config.load_incluster_config")
    mocker.patch("ap_launcher.launch.config.load_kube_config")
    mocker.patch("ap_launcher.launch.client.BatchV1Api", return_value=mock_batch_api)
    mocker.patch("ap_launcher.launch.client.CoreV1Api", return_value=mock_core_api)
    return KubeLauncher(namespace="test-ns")
