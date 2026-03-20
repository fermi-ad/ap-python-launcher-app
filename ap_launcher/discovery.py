import json
import re
import subprocess
import uuid
from typing import Dict, List, Optional, Tuple
from urllib import parse, request

from .models import AppEntry, GUI_HINT_KEYS, LauncherConfig
from .telemetry import log_event


def harbor_request_json(
    cfg: LauncherConfig, api_path: str, query: Dict[str, str]
) -> List[dict]:
    q = parse.urlencode(query)
    url = f"{cfg.harbor_base_url}{api_path}?{q}"
    req = request.Request(url)
    token = f"{cfg.harbor_username}:{cfg.harbor_token}".encode("utf-8")
    import base64

    req.add_header("Authorization", "Basic " + base64.b64encode(token).decode("ascii"))
    req.add_header("Accept", "application/json")

    with request.urlopen(req, timeout=30) as resp:
        payload = json.loads(resp.read().decode("utf-8"))
    return payload


def list_repositories(cfg: LauncherConfig) -> List[str]:
    repos: List[str] = []
    page = 1
    while True:
        chunk = harbor_request_json(
            cfg,
            "/api/v2.0/projects/{}/repositories".format(
                parse.quote(cfg.harbor_project, safe="")
            ),
            {"page": str(page), "page_size": str(cfg.page_size)},
        )
        if not chunk:
            break
        repos.extend([r.get("name", "") for r in chunk if r.get("name")])
        page += 1
    return repos


def list_artifacts(cfg: LauncherConfig, repository: str) -> List[dict]:
    artifacts: List[dict] = []
    page = 1
    while True:
        chunk = harbor_request_json(
            cfg,
            "/api/v2.0/projects/{}/repositories/{}/artifacts".format(
                parse.quote(cfg.harbor_project, safe=""),
                parse.quote(repository, safe=""),
            ),
            {"page": str(page), "page_size": str(cfg.page_size), "with_tag": "true"},
        )
        if not chunk:
            break
        artifacts.extend(chunk)
        page += 1
    return artifacts


def choose_tag(tags: List[dict], allow_patterns: List[str]) -> Optional[str]:
    names = [t.get("name", "") for t in tags if t.get("name")]
    if not names:
        return None

    candidates = []
    for name in names:
        lowered = name.lower()
        if any(re.match(p, lowered) for p in allow_patterns):
            candidates.append(name)

    stable = [
        t for t in candidates if not re.search(r"(dev|test|scratch|rc|beta)", t.lower())
    ]
    source = stable or candidates

    semver = sorted(
        source,
        key=lambda s: (
            tuple(int(x) if x.isdigit() else 0 for x in re.findall(r"\d+", s)) or (0,)
        ),
        reverse=True,
    )
    return semver[0] if semver else source[0]


def inspect_image(cfg: LauncherConfig, image_ref: str) -> dict:
    p = subprocess.run(
        [cfg.podman_bin, "image", "inspect", image_ref],
        text=True,
        capture_output=True,
        check=False,
    )
    if p.returncode != 0:
        raise RuntimeError(f"podman inspect failed: {p.stderr.strip()}")
    data = json.loads(p.stdout)
    if not data:
        raise RuntimeError("podman inspect returned empty result")
    return data[0]


def infer_command(inspect: dict, fallback: List[str]) -> List[str]:
    cfg = inspect.get("Config", {})
    entrypoint = cfg.get("Entrypoint") or []
    cmd = cfg.get("Cmd") or []
    if entrypoint and cmd:
        return entrypoint + cmd
    if cmd:
        return cmd
    if entrypoint:
        return entrypoint
    return fallback


def infer_gui(inspect: dict, command: List[str]) -> bool:
    envs = inspect.get("Config", {}).get("Env") or []
    env_map = {}
    for e in envs:
        if "=" in e:
            k, v = e.split("=", 1)
            env_map[k] = v
    for key in GUI_HINT_KEYS:
        if env_map.get(key, "").lower() in {"1", "true", "yes", "on"}:
            return True
    cmd_line = " ".join(command).lower()
    return any(h in cmd_line for h in ["pyqt", "pyside", "tkinter"])


def infer_name(repository: str, tag: str) -> str:
    leaf = repository.split("/")[-1]
    return leaf if leaf else f"{repository}:{tag}"


def discover_apps(
    cfg: LauncherConfig, session_id: str
) -> Tuple[List[AppEntry], List[str]]:
    apps: List[AppEntry] = []
    warnings: List[str] = []
    log_event("discovery_start", session_id=session_id, project=cfg.harbor_project)

    repos = list_repositories(cfg)

    for repo in repos:
        try:
            artifacts = list_artifacts(cfg, repo)
            for artifact in artifacts:
                tags = artifact.get("tags") or []
                selected_tag = choose_tag(tags, cfg.tag_allow_regex)
                if not selected_tag:
                    continue
                image_ref = f"{cfg.harbor_base_url.replace('https://', '').replace('http://', '')}/{repo}:{selected_tag}"

                if cfg.registry_prefix_allowlist and not any(
                    image_ref.startswith(prefix)
                    for prefix in cfg.registry_prefix_allowlist
                ):
                    continue

                inspect = inspect_image(cfg, image_ref)
                command = infer_command(inspect, cfg.fallback_command)
                gui = infer_gui(inspect, command)
                app = AppEntry(
                    app_id=str(uuid.uuid4()),
                    name=infer_name(repo, selected_tag),
                    repository=repo,
                    tag=selected_tag,
                    image_ref=image_ref,
                    command=command,
                    env={},
                    gui=gui,
                )
                apps.append(app)
        except Exception as exc:
            msg = f"Repository '{repo}' discovery failed: {exc}"
            warnings.append(msg)
            log_event(
                "discovery_repo",
                session_id=session_id,
                repository=repo,
                result="error",
                error_category="harbor_repo_partial",
                details=str(exc),
            )

    log_event(
        "discovery_complete",
        session_id=session_id,
        app_count=len(apps),
        warning_count=len(warnings),
    )
    return apps, warnings
