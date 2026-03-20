import json
import os
import shutil
from pathlib import Path

from .models import (
    DEFAULT_XPRA_DISPLAY,
    HOST_ENV_ALLOWLIST_DEFAULT,
    LauncherConfig,
)

CONFIG_PATH = Path(os.getenv("AP_LAUNCHER_CONFIG", "./config.json"))


def load_config(path: Path) -> LauncherConfig:
    if not path.exists():
        raise RuntimeError(
            f"Config file not found: {path}. Create it with Harbor URL/project/credentials."
        )

    raw = json.loads(path.read_text(encoding="utf-8"))
    required = ["harbor_base_url", "harbor_project", "harbor_username", "harbor_token"]
    missing = [k for k in required if not raw.get(k)]
    if missing:
        raise RuntimeError(f"Missing required config fields: {', '.join(missing)}")

    cfg = LauncherConfig(
        harbor_base_url=raw["harbor_base_url"].rstrip("/"),
        harbor_project=raw["harbor_project"],
        harbor_username=raw["harbor_username"],
        harbor_token=raw["harbor_token"],
        podman_bin=raw.get("podman_bin", "podman"),
        xpra_mode=raw.get("xpra_mode", "auto"),
        xpra_display=raw.get("xpra_display", DEFAULT_XPRA_DISPLAY),
        host_env_allowlist=raw.get("host_env_allowlist", HOST_ENV_ALLOWLIST_DEFAULT),
        bind_mounts=raw.get("bind_mounts", []),
        registry_prefix_allowlist=raw.get("registry_prefix_allowlist", []),
        fallback_command=raw.get("fallback_command", ["python", "-m", "app"]),
        tag_allow_regex=raw.get("tag_allow_regex", [r".*(?:prod).*"]),
        page_size=int(raw.get("page_size", 50)),
    )

    if cfg.xpra_mode not in {"off", "auto", "required"}:
        raise RuntimeError("xpra_mode must be one of: off, auto, required")
    return cfg


def check_tool_exists(binary: str) -> bool:
    return shutil.which(binary) is not None


def validate_runtime(cfg: LauncherConfig) -> None:
    if not check_tool_exists(cfg.podman_bin):
        raise RuntimeError(f"Podman binary not found in PATH: {cfg.podman_bin}")
    if cfg.xpra_mode != "off" and not check_tool_exists("xpra"):
        if cfg.xpra_mode == "required":
            raise RuntimeError("xpra_mode=required but xpra is not installed")
