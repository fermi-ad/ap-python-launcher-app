from dataclasses import dataclass, field
from typing import Dict, List

DEFAULT_XPRA_DISPLAY = ":100"
GUI_HINT_KEYS = {"AP_GUI", "GUI_APP", "USE_GUI"}
HOST_ENV_ALLOWLIST_DEFAULT = ["HOME", "USER", "LOGNAME", "LANG", "LC_ALL", "XAUTHORITY"]


@dataclass
class LauncherConfig:
    harbor_base_url: str
    harbor_project: str
    harbor_username: str
    harbor_token: str
    podman_bin: str = "podman"
    xpra_mode: str = "auto"  # off | auto | required
    xpra_display: str = DEFAULT_XPRA_DISPLAY
    host_env_allowlist: List[str] = field(
        default_factory=lambda: HOST_ENV_ALLOWLIST_DEFAULT.copy()
    )
    bind_mounts: List[str] = field(default_factory=list)
    registry_prefix_allowlist: List[str] = field(default_factory=list)
    fallback_command: List[str] = field(default_factory=lambda: ["python", "-m", "app"])
    tag_allow_regex: List[str] = field(
        default_factory=lambda: [r".*(?:prod).*".lower()]
    )
    page_size: int = 50


@dataclass
class AppEntry:
    app_id: str
    name: str
    repository: str
    tag: str
    image_ref: str
    command: List[str]
    env: Dict[str, str]
    gui: bool
