from tkinter import Tk, messagebox

from .config import CONFIG_PATH, load_config, validate_runtime
from .telemetry import log_event
from .ui import LauncherUI


def main() -> None:
    try:
        cfg = load_config(CONFIG_PATH)
        validate_runtime(cfg)
        ui = LauncherUI(cfg)
        ui.run()
    except Exception as exc:
        log_event("startup_error", details=str(exc))
        root = Tk()
        root.withdraw()
        messagebox.showerror("AP Launcher Startup Error", str(exc))
        raise
