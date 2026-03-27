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

    workload_namespace: str


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
        workload_namespace=os.environ.get("AP_WORKLOAD_NAMESPACE", "ap-python"),
    )
