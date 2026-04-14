from __future__ import annotations

from unittest.mock import MagicMock

import pytest
from kubernetes.client.exceptions import ApiException

from ap_launcher.launch import (
    LaunchLimitExceededError,
    MAX_JOBS_TOTAL,
    MAX_JOBS_PER_APP,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _make_job(
    active=None,
    succeeded=None,
    failed=None,
    name="test-job",
    labels=None,
    *,
    deletion_timestamp=None,
):
    job = MagicMock()
    job.metadata.name = name
    job.metadata.labels = labels or {}
    job.metadata.deletion_timestamp = deletion_timestamp
    job.status.active = active
    job.status.succeeded = succeeded
    job.status.failed = failed
    job.status.start_time = None
    job.status.completion_time = None
    return job


def _jobs_list(*jobs):
    lst = MagicMock()
    lst.items = list(jobs)
    return lst


def _make_pod(name: str, *, ready: bool = False):
    p = MagicMock()
    p.metadata.name = name
    cond = MagicMock()
    cond.type = "Ready"
    cond.status = "True" if ready else "False"
    p.status.conditions = [cond]
    return p


def _pod_list(*names, ready: bool = False):
    lst = MagicMock()
    lst.items = [_make_pod(n, ready=ready) for n in names]
    return lst


def _service(name="test-svc", ingress=None):
    svc = MagicMock()
    svc.metadata.name = name
    if ingress is None:
        svc.status.load_balancer.ingress = None
    else:
        svc.status.load_balancer.ingress = ingress
    return svc


def _svc_list(*svcs):
    lst = MagicMock()
    lst.items = list(svcs)
    return lst


# ---------------------------------------------------------------------------
# _labels_for_launch
# ---------------------------------------------------------------------------


def test_base_labels_present(launcher):
    labels = launcher._labels_for_launch(
        launch_id="abc123", repo="myproject/myapp", tag="latest", requested_by=None
    )
    assert "app.kubernetes.io/managed-by" in labels
    assert "ap-python.fnal.gov/repo" in labels
    assert "ap-python.fnal.gov/tag" in labels
    assert "ap-python.fnal.gov/launch-id" in labels
    assert "ap-python.fnal.gov/requested-by" not in labels


def test_repo_slash_replaced_with_underscore(launcher):
    labels = launcher._labels_for_launch(
        launch_id="x", repo="foo/bar", tag="v1", requested_by=None
    )
    assert labels["ap-python.fnal.gov/repo"] == "foo_bar"


def test_no_requested_by_label_when_none(launcher):
    labels = launcher._labels_for_launch(
        launch_id="x", repo="r", tag="t", requested_by=None
    )
    assert "ap-python.fnal.gov/requested-by" not in labels


def test_requested_by_label_when_set(launcher):
    labels = launcher._labels_for_launch(
        launch_id="x", repo="r", tag="t", requested_by="alice"
    )
    assert labels["ap-python.fnal.gov/requested-by"] == "alice"


# ---------------------------------------------------------------------------
# _service_name_for_launch
# ---------------------------------------------------------------------------


def test_service_name_basic_format(launcher):
    name = launcher._service_name_for_launch(
        repo="proj/my-app", launch_id="abcd1234-0000-0000-0000-000000000000"
    )
    assert name.startswith("appl-my-app-abcd1234")


def test_service_name_truncated_to_63_chars(launcher):
    long_repo = "proj/" + "x" * 100
    name = launcher._service_name_for_launch(
        repo=long_repo, launch_id="abcd1234-0000-0000-0000-000000000000"
    )
    assert len(name) <= 63


def test_service_name_all_lowercase(launcher):
    name = launcher._service_name_for_launch(
        repo="PROJ/MY-APP", launch_id="abcd1234-0000-0000-0000-000000000000"
    )
    assert name == name.lower()


def test_service_name_underscores_and_dots_replaced_with_dashes(launcher):
    name = launcher._service_name_for_launch(
        repo="proj/my_app.v2", launch_id="abcd1234-0000-0000-0000-000000000000"
    )
    assert "my-app-v2" in name


def test_service_name_takes_only_last_path_segment(launcher):
    name = launcher._service_name_for_launch(
        repo="proj/my-app", launch_id="abcd1234-0000-0000-0000-000000000000"
    )
    assert "proj" not in name


# ---------------------------------------------------------------------------
# _parse_lb_annotations
# ---------------------------------------------------------------------------


def test_parse_lb_annotations_returns_empty_dict_when_none(launcher):
    launcher.lb_annotations_json = None
    assert launcher._parse_lb_annotations() == {}


def test_parse_lb_annotations_valid_json(launcher):
    launcher.lb_annotations_json = (
        '{"service.beta.kubernetes.io/aws-load-balancer-type": "nlb"}'
    )
    result = launcher._parse_lb_annotations()
    assert result == {"service.beta.kubernetes.io/aws-load-balancer-type": "nlb"}


def test_parse_lb_annotations_invalid_json_raises_value_error(launcher):
    launcher.lb_annotations_json = "not-valid-json"
    with pytest.raises(ValueError, match="Invalid AP_LB_ANNOTATIONS_JSON"):
        launcher._parse_lb_annotations()


def test_parse_lb_annotations_non_string_value_raises_value_error(launcher):
    launcher.lb_annotations_json = '{"key": 123}'
    with pytest.raises(ValueError, match="AP_LB_ANNOTATIONS_JSON must be"):
        launcher._parse_lb_annotations()


# ---------------------------------------------------------------------------
# _count_active_jobs
# ---------------------------------------------------------------------------


def test_count_active_jobs_counts_only_active(launcher, mock_batch_api):
    mock_batch_api.list_namespaced_job.return_value = _jobs_list(
        _make_job(active=1),
        _make_job(active=1),
        _make_job(active=None),
    )
    assert launcher._count_active_jobs() == 2


def test_count_active_jobs_with_repo_filter_includes_repo_in_label_selector(
    launcher, mock_batch_api
):
    mock_batch_api.list_namespaced_job.return_value = _jobs_list()
    launcher._count_active_jobs(repo="proj/myapp")
    call_kwargs = mock_batch_api.list_namespaced_job.call_args[1]
    assert "ap-python.fnal.gov/repo=proj_myapp" in call_kwargs["label_selector"]


def test_count_active_jobs_none_status_not_counted(launcher, mock_batch_api):
    job = MagicMock()
    job.status = None
    mock_batch_api.list_namespaced_job.return_value = _jobs_list(job)
    assert launcher._count_active_jobs() == 0


def test_count_active_zero_not_counted(launcher, mock_batch_api):
    mock_batch_api.list_namespaced_job.return_value = _jobs_list(_make_job(active=0))
    assert launcher._count_active_jobs() == 0


# ---------------------------------------------------------------------------
# _enforce_limits
# ---------------------------------------------------------------------------


def test_enforce_limits_allows_when_under_both(launcher, mock_batch_api):
    mock_batch_api.list_namespaced_job.return_value = _jobs_list(
        *[_make_job(active=1) for _ in range(5)]
    )
    launcher._enforce_limits(repo="proj/app")  # should not raise


def test_enforce_limits_raises_on_total_limit(launcher, mock_batch_api):
    mock_batch_api.list_namespaced_job.return_value = _jobs_list(
        *[_make_job(active=1) for _ in range(MAX_JOBS_TOTAL)]
    )
    with pytest.raises(LaunchLimitExceededError):
        launcher._enforce_limits(repo="proj/app")


def test_enforce_limits_raises_on_per_app_limit(launcher, mock_batch_api):
    # First call (total) returns under limit; second call (per-app) returns at limit
    under_total = _jobs_list(*[_make_job(active=1) for _ in range(5)])
    at_per_app = _jobs_list(*[_make_job(active=1) for _ in range(MAX_JOBS_PER_APP)])
    mock_batch_api.list_namespaced_job.side_effect = [under_total, at_per_app]
    with pytest.raises(LaunchLimitExceededError, match="proj/app"):
        launcher._enforce_limits(repo="proj/app")


def test_enforce_limits_checks_total_before_per_app(launcher, mock_batch_api):
    # Total at limit — should not make second call for per-app
    mock_batch_api.list_namespaced_job.return_value = _jobs_list(
        *[_make_job(active=1) for _ in range(MAX_JOBS_TOTAL)]
    )
    with pytest.raises(LaunchLimitExceededError):
        launcher._enforce_limits(repo="proj/app")
    assert mock_batch_api.list_namespaced_job.call_count == 1


# ---------------------------------------------------------------------------
# create_job
# ---------------------------------------------------------------------------


def _setup_create_job(launcher, mock_batch_api, mock_core_api):
    """Set up mocks for a successful create_job call."""
    mock_batch_api.list_namespaced_job.return_value = _jobs_list()
    mock_core_api.create_namespaced_service.return_value = MagicMock()
    mock_batch_api.create_namespaced_job.return_value = MagicMock()


def test_create_job_calls_batch_create(launcher, mock_batch_api, mock_core_api):
    _setup_create_job(launcher, mock_batch_api, mock_core_api)
    launcher.create_job(image="img:latest", repo="proj/app", tag="latest")
    mock_batch_api.create_namespaced_job.assert_called_once()


def test_create_job_creates_loadbalancer_service(
    launcher, mock_batch_api, mock_core_api
):
    _setup_create_job(launcher, mock_batch_api, mock_core_api)
    launcher.create_job(image="img:latest", repo="proj/app", tag="latest")
    mock_core_api.create_namespaced_service.assert_called_once()


def test_create_job_returns_launch_result_with_non_empty_id(
    launcher, mock_batch_api, mock_core_api
):
    _setup_create_job(launcher, mock_batch_api, mock_core_api)
    result = launcher.create_job(image="img:latest", repo="proj/app", tag="latest")
    assert result.launch_id
    assert result.job_name
    assert result.service_name
    assert result.namespace == "test-ns"


def test_create_job_job_name_truncated_to_63_chars(
    launcher, mock_batch_api, mock_core_api
):
    _setup_create_job(launcher, mock_batch_api, mock_core_api)
    long_repo = "proj/" + "x" * 100
    result = launcher.create_job(image="img:latest", repo=long_repo, tag="latest")
    assert len(result.job_name) <= 63


def test_create_job_propagates_launch_limit_error(launcher, mocker):
    mocker.patch.object(
        launcher, "_enforce_limits", side_effect=LaunchLimitExceededError("at limit")
    )
    with pytest.raises(LaunchLimitExceededError):
        launcher.create_job(image="img:latest", repo="proj/app", tag="latest")


def test_create_job_idempotent_on_409_service_conflict(
    launcher, mock_batch_api, mock_core_api
):
    _setup_create_job(launcher, mock_batch_api, mock_core_api)
    conflict = ApiException(status=409)
    conflict.status = 409
    mock_core_api.create_namespaced_service.side_effect = conflict
    # Should not raise
    launcher.create_job(image="img:latest", repo="proj/app", tag="latest")


def test_create_job_reraises_non_409_api_exception(
    launcher, mock_batch_api, mock_core_api
):
    _setup_create_job(launcher, mock_batch_api, mock_core_api)
    error = ApiException(status=500)
    error.status = 500
    mock_core_api.create_namespaced_service.side_effect = error
    with pytest.raises(ApiException):
        launcher.create_job(image="img:latest", repo="proj/app", tag="latest")


# ---------------------------------------------------------------------------
# get_launch_status
# ---------------------------------------------------------------------------


def _setup_status(
    mock_batch_api, mock_core_api, job=None, pods=None, svc=None, pod_ready=False
):
    mock_batch_api.list_namespaced_job.return_value = (
        _jobs_list(job) if job else _jobs_list()
    )
    mock_core_api.list_namespaced_pod.return_value = (
        _pod_list(*pods, ready=pod_ready) if pods else _pod_list()
    )
    mock_core_api.list_namespaced_service.return_value = (
        _svc_list(svc) if svc else _svc_list()
    )
    mock_core_api.delete_namespaced_service.return_value = MagicMock()


def test_get_launch_status_not_found(launcher, mock_batch_api, mock_core_api):
    _setup_status(mock_batch_api, mock_core_api)
    result = launcher.get_launch_status(launch_id="test-id")
    assert result["status"] == "NotFound"
    assert result["launchId"] == "test-id"


def test_get_launch_status_pending(launcher, mock_batch_api, mock_core_api):
    job = _make_job(active=None, succeeded=None, failed=None)
    _setup_status(mock_batch_api, mock_core_api, job=job, pods=["pod-1"])
    result = launcher.get_launch_status(launch_id="test-id")
    assert result["status"] == "Pending"


def test_get_launch_status_running(launcher, mock_batch_api, mock_core_api):
    job = _make_job(active=1)
    _setup_status(mock_batch_api, mock_core_api, job=job, pods=["pod-1"])
    result = launcher.get_launch_status(launch_id="test-id")
    assert result["status"] == "Running"


def test_get_launch_status_succeeded(launcher, mock_batch_api, mock_core_api):
    job = _make_job(succeeded=1)
    _setup_status(mock_batch_api, mock_core_api, job=job)
    result = launcher.get_launch_status(launch_id="test-id")
    assert result["status"] == "Succeeded"
    assert result["serviceName"] is None
    assert result["access"]["urls"] == []


def test_get_launch_status_failed(launcher, mock_batch_api, mock_core_api):
    job = _make_job(failed=1)
    _setup_status(mock_batch_api, mock_core_api, job=job)
    result = launcher.get_launch_status(launch_id="test-id")
    assert result["status"] == "Failed"


def test_get_launch_status_cleans_up_service_on_succeeded(
    launcher, mock_batch_api, mock_core_api
):
    job = _make_job(succeeded=1)
    svc = _service("my-svc")
    _setup_status(mock_batch_api, mock_core_api, job=job, svc=svc)
    launcher.get_launch_status(launch_id="test-id")
    mock_core_api.delete_namespaced_service.assert_called()


def test_get_launch_status_cleans_up_service_on_failed(
    launcher, mock_batch_api, mock_core_api
):
    job = _make_job(failed=1)
    svc = _service("my-svc")
    _setup_status(mock_batch_api, mock_core_api, job=job, svc=svc)
    launcher.get_launch_status(launch_id="test-id")
    mock_core_api.delete_namespaced_service.assert_called()


def test_get_launch_status_ending_when_deletion_timestamp_set(
    launcher, mock_batch_api, mock_core_api
):
    job = _make_job(active=1, deletion_timestamp="2026-01-01T00:00:00Z")
    svc = _service("my-svc")
    _setup_status(mock_batch_api, mock_core_api, job=job, pods=["pod-1"], svc=svc)
    result = launcher.get_launch_status(launch_id="test-id")
    assert result["status"] == "Ending"
    # Service should be cleaned up while ending.
    mock_core_api.delete_namespaced_service.assert_called()


def test_get_launch_status_returns_lb_urls_when_ingress_has_ip(
    launcher, mock_batch_api, mock_core_api
):
    job = _make_job(active=1)
    ingress_item = MagicMock()
    ingress_item.hostname = None
    ingress_item.ip = "1.2.3.4"
    svc = _service("my-svc", ingress=[ingress_item])
    _setup_status(
        mock_batch_api, mock_core_api, job=job, pods=["pod-1"], svc=svc, pod_ready=True
    )
    result = launcher.get_launch_status(launch_id="test-id")
    assert "http://1.2.3.4:80/" in result["access"]["urls"]
    assert result["access"]["status"] == "Ready"


def test_get_launch_status_access_pending_when_pod_not_ready(
    launcher, mock_batch_api, mock_core_api
):
    # LB has an IP but the pod readiness probe has not yet passed.
    job = _make_job(active=1)
    ingress_item = MagicMock()
    ingress_item.hostname = None
    ingress_item.ip = "1.2.3.4"
    svc = _service("my-svc", ingress=[ingress_item])
    _setup_status(
        mock_batch_api, mock_core_api, job=job, pods=["pod-1"], svc=svc, pod_ready=False
    )
    result = launcher.get_launch_status(launch_id="test-id")
    assert "http://1.2.3.4:80/" in result["access"]["urls"]
    assert result["access"]["status"] == "Pending"


def test_get_launch_status_prefers_hostname_over_ip(
    launcher, mock_batch_api, mock_core_api
):
    job = _make_job(active=1)
    ingress_item = MagicMock()
    ingress_item.hostname = "my.host.example.com"
    ingress_item.ip = "1.2.3.4"
    svc = _service("my-svc", ingress=[ingress_item])
    _setup_status(
        mock_batch_api, mock_core_api, job=job, pods=["pod-1"], svc=svc, pod_ready=True
    )
    result = launcher.get_launch_status(launch_id="test-id")
    assert "my.host.example.com" in result["access"]["urls"][0]
    assert "1.2.3.4" not in result["access"]["urls"][0]


def test_get_launch_status_includes_pod_name(launcher, mock_batch_api, mock_core_api):
    job = _make_job(active=1)
    _setup_status(mock_batch_api, mock_core_api, job=job, pods=["my-pod-xyz"])
    result = launcher.get_launch_status(launch_id="test-id")
    assert result["podName"] == "my-pod-xyz"


def test_get_launch_status_cleans_up_service_when_pod_gone(
    launcher, mock_batch_api, mock_core_api
):
    # Running job but no pod — service should be cleaned up
    job = _make_job(active=1)
    svc = _service("my-svc")
    _setup_status(mock_batch_api, mock_core_api, job=job, pods=[], svc=svc)
    result = launcher.get_launch_status(launch_id="test-id")
    mock_core_api.delete_namespaced_service.assert_called()
    assert result["access"]["urls"] == []


def test_get_launch_status_access_pending_when_no_urls(
    launcher, mock_batch_api, mock_core_api
):
    job = _make_job(active=1)
    svc = _service("my-svc", ingress=[])
    _setup_status(mock_batch_api, mock_core_api, job=job, pods=["pod-1"], svc=svc)
    result = launcher.get_launch_status(launch_id="test-id")
    assert result["access"]["status"] == "Pending"
    assert result["access"]["urls"] == []


def test_get_launch_status_start_time_is_iso_string(
    launcher, mock_batch_api, mock_core_api
):
    from datetime import datetime, timezone

    job = _make_job(active=1)
    job.status.start_time = datetime(2024, 1, 15, 10, 30, 0, tzinfo=timezone.utc)
    _setup_status(mock_batch_api, mock_core_api, job=job, pods=["pod-1"])
    result = launcher.get_launch_status(launch_id="test-id")
    assert result["startTime"] is not None
    assert "2024" in result["startTime"]


def test_get_launch_status_completion_time_is_iso_string(
    launcher, mock_batch_api, mock_core_api
):
    from datetime import datetime, timezone

    job = _make_job(succeeded=1)
    job.status.completion_time = datetime(2024, 1, 15, 11, 0, 0, tzinfo=timezone.utc)
    _setup_status(mock_batch_api, mock_core_api, job=job)
    result = launcher.get_launch_status(launch_id="test-id")
    assert result["completionTime"] is not None
    assert "2024" in result["completionTime"]
