"""
Mouse Launcher - L+R Click to Launch
Минималистичен launcher без външни зависимости
"""
import ctypes
import ctypes.wintypes as wt
import json
import os
import subprocess
import threading
import time
import tkinter as tk
from pathlib import Path

# Windows API constants
WH_MOUSE_LL = 14
WM_LBUTTONDOWN, WM_LBUTTONUP = 0x201, 0x202
WM_RBUTTONDOWN, WM_RBUTTONUP = 0x204, 0x205

# Config
CONFIG_FILE = Path(__file__).parent / "config.json"
CLICK_TOLERANCE_MS = 100  # L+R must be within this window


class MouseHook:
    """Global low-level mouse hook using Windows API"""

    def __init__(self, on_trigger):
        self.on_trigger = on_trigger
        self.left_down = False
        self.right_down = False
        self.left_time = 0
        self.right_time = 0
        self.hook = None
        self._running = True

        # Setup CallNextHookEx with proper types for 64-bit
        self._call_next = ctypes.windll.user32.CallNextHookEx
        self._call_next.argtypes = [wt.HHOOK, ctypes.c_int, wt.WPARAM, wt.LPARAM]
        self._call_next.restype = wt.LPARAM

        # Define callback type (LRESULT for 64-bit compatibility)
        self.HOOKPROC = ctypes.CFUNCTYPE(
            wt.LPARAM, ctypes.c_int, wt.WPARAM, wt.LPARAM
        )
        self._callback = self.HOOKPROC(self._hook_callback)

    def _hook_callback(self, nCode, wParam, lParam):
        if nCode >= 0:
            now = time.time() * 1000

            if wParam == WM_LBUTTONDOWN:
                self.left_down = True
                self.left_time = now
                self._check_trigger()
            elif wParam == WM_LBUTTONUP:
                self.left_down = False
            elif wParam == WM_RBUTTONDOWN:
                self.right_down = True
                self.right_time = now
                self._check_trigger()
            elif wParam == WM_RBUTTONUP:
                self.right_down = False

        return self._call_next(self.hook, nCode, wParam, lParam)

    def _check_trigger(self):
        if self.left_down and self.right_down:
            if abs(self.left_time - self.right_time) < CLICK_TOLERANCE_MS:
                # Get cursor position
                pt = wt.POINT()
                ctypes.windll.user32.GetCursorPos(ctypes.byref(pt))
                self.on_trigger(pt.x, pt.y)

    def start(self):
        def run():
            self.hook = ctypes.windll.user32.SetWindowsHookExW(
                WH_MOUSE_LL, self._callback, None, 0
            )
            msg = wt.MSG()
            while self._running and ctypes.windll.user32.GetMessageW(
                ctypes.byref(msg), None, 0, 0
            ) > 0:
                ctypes.windll.user32.TranslateMessage(ctypes.byref(msg))
                ctypes.windll.user32.DispatchMessageW(ctypes.byref(msg))

        thread = threading.Thread(target=run, daemon=True)
        thread.start()

    def stop(self):
        self._running = False
        if self.hook:
            ctypes.windll.user32.UnhookWindowsHookEx(self.hook)


class LauncherPopup:
    """Floating popup window with pinned items"""

    BG = "#1a1a2e"
    FG = "#ffffff"
    HOVER = "#2d2d44"
    ITEM_HEIGHT = 36
    WIDTH = 220

    def __init__(self, root, items, on_close):
        self.root = root
        self.items = items
        self.on_close = on_close
        self.win = None

    def show(self, x, y):
        if self.win:
            self.hide()

        self.win = tk.Toplevel(self.root)
        self.win.overrideredirect(True)
        self.win.attributes("-topmost", True)
        self.win.attributes("-alpha", 0.95)
        self.win.configure(bg=self.BG)

        # Calculate size and position
        height = len(self.items) * self.ITEM_HEIGHT + 16

        # Ensure popup stays on screen
        screen_w = self.root.winfo_screenwidth()
        screen_h = self.root.winfo_screenheight()
        x = min(x, screen_w - self.WIDTH - 10)
        y = min(y, screen_h - height - 40)

        self.win.geometry(f"{self.WIDTH}x{height}+{x}+{y}")

        # Create items
        frame = tk.Frame(self.win, bg=self.BG)
        frame.pack(fill="both", expand=True, padx=8, pady=8)

        for i, item in enumerate(self.items):
            self._create_item(frame, item, i)

        # Bindings
        self.win.bind("<Escape>", lambda e: self.hide())
        self.win.bind("<FocusOut>", lambda e: self._on_focus_out())
        self.win.focus_force()

    def _create_item(self, parent, item, index):
        icon = item.get("icon", "▶")
        name = item.get("name", "Unknown")
        path = item.get("path", "")

        lbl = tk.Label(
            parent,
            text=f" {icon}  {name}",
            font=("Segoe UI", 11),
            bg=self.BG,
            fg=self.FG,
            anchor="w",
            padx=8,
            pady=4,
            cursor="hand2"
        )
        lbl.pack(fill="x", pady=2)

        # Hover effects
        lbl.bind("<Enter>", lambda e: lbl.configure(bg=self.HOVER))
        lbl.bind("<Leave>", lambda e: lbl.configure(bg=self.BG))
        lbl.bind("<Button-1>", lambda e: self._launch(path))

        # Keyboard shortcut (1-9)
        if index < 9:
            self.win.bind(str(index + 1), lambda e, p=path: self._launch(p))

    def _launch(self, path):
        self.hide()
        if path:
            try:
                if os.path.exists(path):
                    os.startfile(path)
                else:
                    subprocess.Popen(path, shell=True)
            except Exception as e:
                print(f"Launch error: {e}")

    def _on_focus_out(self):
        # Delay to allow click events to process
        if self.win:
            self.win.after(100, self.hide)

    def hide(self):
        if self.win:
            self.win.destroy()
            self.win = None
        self.on_close()


class MouseLauncher:
    """Main application controller"""

    def __init__(self):
        self.root = tk.Tk()
        self.root.withdraw()  # Hide main window

        self.items = self._load_config()
        self.popup = LauncherPopup(self.root, self.items, self._on_popup_close)
        self.hook = MouseHook(self._on_trigger)
        self._popup_shown = False

    def _load_config(self):
        if CONFIG_FILE.exists():
            try:
                with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    return data.get("items", [])
            except Exception:
                pass

        # Default items
        return [
            {"name": "Notepad", "path": "notepad.exe", "icon": "📝"},
            {"name": "Explorer", "path": "explorer.exe", "icon": "📁"},
            {"name": "Calculator", "path": "calc.exe", "icon": "🔢"},
            {"name": "CMD", "path": "cmd.exe", "icon": "⌨"},
        ]

    def _on_trigger(self, x, y):
        if not self._popup_shown:
            self._popup_shown = True
            self.root.after(0, lambda: self.popup.show(x, y))

    def _on_popup_close(self):
        self._popup_shown = False

    def run(self):
        self.hook.start()
        try:
            self.root.mainloop()
        finally:
            self.hook.stop()


if __name__ == "__main__":
    app = MouseLauncher()
    app.run()
