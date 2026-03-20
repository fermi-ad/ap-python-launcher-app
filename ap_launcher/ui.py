import threading
import uuid
from tkinter import (
    BOTH,
    END,
    LEFT,
    RIGHT,
    Button,
    Frame,
    Label,
    Listbox,
    Scrollbar,
    Tk,
    messagebox,
)
from typing import List, Optional

from .discovery import discover_apps
from .models import AppEntry, LauncherConfig
from .runtime import launch_app


class LauncherUI:
    def __init__(self, cfg: LauncherConfig):
        self.cfg = cfg
        self.session_id = str(uuid.uuid4())
        self.apps: List[AppEntry] = []
        self.root = Tk()
        self.root.title("AP Python Launcher")

        top = Frame(self.root)
        top.pack(fill=BOTH, expand=True)

        self.listbox = Listbox(top, width=80, height=18)
        self.listbox.pack(side=LEFT, fill=BOTH, expand=True)

        scrollbar = Scrollbar(top)
        scrollbar.pack(side=RIGHT, fill="y")
        self.listbox.config(yscrollcommand=scrollbar.set)
        scrollbar.config(command=self.listbox.yview)

        controls = Frame(self.root)
        controls.pack(fill=BOTH)

        Button(controls, text="Refresh", command=self.refresh).pack(side=LEFT)
        Button(controls, text="Details", command=self.show_details).pack(side=LEFT)
        self.launch_btn = Button(
            controls, text="Launch", command=self.launch_selected, state="disabled"
        )
        self.launch_btn.pack(side=LEFT)

        self.status_label = Label(self.root, text="Ready", anchor="w")
        self.status_label.pack(fill=BOTH)

        self.listbox.bind("<<ListboxSelect>>", self.on_select)

    def set_status(self, text: str) -> None:
        self.status_label.config(text=text)

    def on_select(self, _event=None) -> None:
        selected = bool(self.listbox.curselection())
        self.launch_btn.config(state="normal" if selected else "disabled")

    def refresh(self) -> None:
        self.set_status("Refreshing app catalog from Harbor...")
        self.launch_btn.config(state="disabled")

        def worker():
            try:
                apps, warnings = discover_apps(self.cfg, self.session_id)
                self.root.after(0, lambda: self._finish_refresh(apps, warnings))
            except Exception as exc:
                self.root.after(0, lambda e=exc: self._refresh_error(e))

        threading.Thread(target=worker, daemon=True).start()

    def _finish_refresh(self, apps: List[AppEntry], warnings: List[str]) -> None:
        self.apps = apps
        self.listbox.delete(0, END)
        for app in self.apps:
            mode = "GUI" if app.gui else "Headless"
            self.listbox.insert(END, f"{app.name}   [{mode}]   {app.image_ref}")

        status = f"Loaded {len(self.apps)} app(s)"
        if warnings:
            status += f" with {len(warnings)} warning(s)"
        self.set_status(status)

    def _refresh_error(self, exc: Exception) -> None:
        self.set_status("Discovery failed")
        messagebox.showerror("Discovery Error", str(exc))

    def selected_app(self) -> Optional[AppEntry]:
        sel = self.listbox.curselection()
        if not sel:
            return None
        return self.apps[sel[0]]

    def show_details(self) -> None:
        app = self.selected_app()
        if not app:
            messagebox.showinfo("Details", "Select an app first")
            return
        details = (
            f"Name: {app.name}\n"
            f"Repository: {app.repository}\n"
            f"Tag: {app.tag}\n"
            f"Image: {app.image_ref}\n"
            f"GUI: {'yes' if app.gui else 'no'}\n"
            f"Command: {' '.join(app.command)}"
        )
        messagebox.showinfo("App Details", details)

    def launch_selected(self) -> None:
        app = self.selected_app()
        if not app:
            messagebox.showinfo("Launch", "Select an app first")
            return

        self.set_status(f"Pulling and launching: {app.name}")
        self.launch_btn.config(state="disabled")

        def worker():
            ok, msg = launch_app(self.cfg, app, self.session_id)
            self.root.after(0, lambda: self._finish_launch(ok, msg))

        threading.Thread(target=worker, daemon=True).start()

    def _finish_launch(self, ok: bool, msg: str) -> None:
        self.on_select()
        self.set_status(msg)
        if ok:
            messagebox.showinfo("Launch", msg)
        else:
            messagebox.showerror("Launch Error", msg)

    def run(self) -> None:
        self.refresh()
        self.root.mainloop()
