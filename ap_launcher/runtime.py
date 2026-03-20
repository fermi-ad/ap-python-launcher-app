import os
import subprocess
from typing import Dict, List, Tuple

from .config import check_tool_exists
from .models import AppEntry, LauncherConfig
from .telemetry import log_event


def xpra_ensure(display_id: str) -> None:
    log_event("xpra_check", display_id=display_id)
    info = subprocess.run(
        ["xpra", "info", display_id], capture_output=True, text=True, check=False
    )
    if info.returncode == 0:
        return
    start = subprocess.run(
        ["xpra", "start", display_id, "--mdns=no", "--daemon=yes"],
        capture_output=True,
        text=True,
        check=False,
    )
    if start.returncode != 0:
        log_event("xpra_error", display_id=display_id, details=start.stderr.strip())
        raise RuntimeError(start.stderr.strip() or "xpra start failed")
    log_event("xpra_start", display_id=display_id)


def build_podman_run(
    cfg: LauncherConfig, app: AppEntry, env: Dict[str, str]
) -> List[str]:
    cmd = [cfg.podman_bin, "run", "--rm"]

    for key in cfg.host_env_allowlist:
        value = env.get(key)
        if value:
            cmd.extend(["-e", f"{key}={value}"])

    for k, v in app.env.items():
        cmd.extend(["-e", f"{k}={v}"])

    for mount in cfg.bind_mounts:
        cmd.extend(["-v", mount])

    cmd.append(app.image_ref)
    cmd.extend(app.command)
    return cmd


def classify_error(stderr: str) -> str:
    s = stderr.lower()
    if "unauthorized" in s or "authentication" in s:
        return "auth"
    if "not found" in s:
        return "not_found"
    if "network" in s or "timeout" in s:
        return "network"
    return "runtime"


def launch_app(cfg: LauncherConfig, app: AppEntry, session_id: str) -> Tuple[bool, str]:
    runtime_env = os.environ.copy()

    if app.gui and cfg.xpra_mode in {"auto", "required"}:
        if not check_tool_exists("xpra"):
            if cfg.xpra_mode == "required":
                return False, "xpra is required but not installed"
        else:
            xpra_ensure(cfg.xpra_display)
            runtime_env["DISPLAY"] = cfg.xpra_display

    log_event(
        "launch_attempt",
        session_id=session_id,
        app_id=app.app_id,
        image_ref=app.image_ref,
    )

    log_event(
        "pull_start", session_id=session_id, app_id=app.app_id, image_ref=app.image_ref
    )
    pull = subprocess.run(
        [cfg.podman_bin, "pull", app.image_ref],
        capture_output=True,
        text=True,
        check=False,
    )
    if pull.returncode != 0:
        category = classify_error(pull.stderr)
        log_event(
            "pull_error",
            session_id=session_id,
            app_id=app.app_id,
            image_ref=app.image_ref,
            error_category=category,
            details=pull.stderr.strip(),
        )
        return False, f"podman pull failed ({category}): {pull.stderr.strip()}"

    log_event(
        "pull_success",
        session_id=session_id,
        app_id=app.app_id,
        image_ref=app.image_ref,
    )

    run_cmd = build_podman_run(cfg, app, runtime_env)
    log_event(
        "run_start", session_id=session_id, app_id=app.app_id, image_ref=app.image_ref
    )
    run = subprocess.run(
        run_cmd, capture_output=True, text=True, check=False, env=runtime_env
    )
    if run.returncode != 0:
        category = classify_error(run.stderr)
        log_event(
            "run_error",
            session_id=session_id,
            app_id=app.app_id,
            image_ref=app.image_ref,
            error_category=category,
            details=run.stderr.strip(),
        )
        return False, f"podman run failed ({category}): {run.stderr.strip()}"

    log_event(
        "run_success", session_id=session_id, app_id=app.app_id, image_ref=app.image_ref
    )
    return True, "Launch completed successfully"
