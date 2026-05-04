from __future__ import annotations

from dataclasses import dataclass
import os


@dataclass(frozen=True)
class WebConfig:
    """Runtime configuration for the in-cluster web launcher."""

    harbor_base_url: str
    harbor_project: str
    harbor_username: str | None
    harbor_password: str | None

    # Optional: if set, the server will use this kubeconfig (content) instead of
    # in-cluster service account auth.
    kubeconfig: str | None
    kubeconfig_path: str | None

    workload_namespace: str

    # Per-launch access Service settings
    app_target_port: int
    lb_port: int
    lb_annotations_json: str | None

    # If shared_lb_ip is unset, the launcher will attempt to discover a canonical
    # shared IP from existing launcher-managed Services.
    shared_lb_ip: str | None
    shared_lb_annotations_json: str | None
    shared_lb_port_range_start: int
    shared_lb_port_range_end: int


def load_web_config() -> WebConfig:
    """Load configuration from environment variables.

    Authentication is optional for initial development; if credentials are not
    provided, the Harbor client should operate in anonymous mode.
    """

    return WebConfig(
        harbor_base_url=os.environ.get(
            "AP_HARBOR_BASE_URL", "https://adregistry.fnal.gov"
        ),
        harbor_project=os.environ.get("AP_HARBOR_PROJECT", "ap-python"),
        harbor_username=os.environ.get("AP_HARBOR_USERNAME"),
        harbor_password=os.environ.get("AP_HARBOR_PASSWORD"),
        kubeconfig=os.environ.get("AP_KUBECONFIG"),
        kubeconfig_path=os.environ.get("AP_KUBECONFIG_PATH"),
        workload_namespace=os.environ.get("AP_WORKLOAD_NAMESPACE", "ap-python"),
        app_target_port=int(os.environ.get("AP_APP_TARGET_PORT", "14500")),
        lb_port=int(os.environ.get("AP_LB_PORT", "80")),
        lb_annotations_json=os.environ.get("AP_LB_ANNOTATIONS_JSON"),
        shared_lb_ip=os.environ.get("AP_SHARED_LB_IP"),
        shared_lb_annotations_json=os.environ.get("AP_SHARED_LB_ANNOTATIONS_JSON"),
        shared_lb_port_range_start=int(
            os.environ.get("AP_SHARED_LB_PORT_RANGE_START", "30000")
        ),
        shared_lb_port_range_end=int(
            os.environ.get("AP_SHARED_LB_PORT_RANGE_END", "39999")
        ),
    )
