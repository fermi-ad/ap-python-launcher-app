import json
import os
from datetime import datetime
from pathlib import Path

TELEMETRY_LOG = Path(os.getenv("AP_LAUNCHER_TELEMETRY", "./telemetry.log"))


def utc_now() -> str:
    return datetime.utcnow().isoformat() + "Z"


def log_event(event: str, **kwargs) -> None:
    TELEMETRY_LOG.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "event": event,
        "timestamp": utc_now(),
        "user": os.getenv("USER", "unknown"),
        "host": os.uname().nodename,
    }
    payload.update(kwargs)
    with TELEMETRY_LOG.open("a", encoding="utf-8") as f:
        f.write(json.dumps(payload) + "\n")
