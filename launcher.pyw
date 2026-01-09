"""
Mouse Launcher - L+R Click to Launch
Минималистичен launcher без външни зависимости
"""
import ctypes
import json
import os
import subprocess
import time
import tkinter as tk
from pathlib import Path

# Windows API
user32 = ctypes.windll.user32
VK_LBUTTON, VK_RBUTTON = 0x01, 0x02


class POINT(ctypes.Structure):
    _fields_ = [("x", ctypes.c_long), ("y", ctypes.c_long)]


# Config
CONFIG_FILE = Path(__file__).parent / "config.json"
POLL_MS = 30


class LauncherPopup:
    """Floating popup window with pinned items"""

    BG = "#1a1a2e"
    FG = "#ffffff"
    HOVER = "#2d2d44"
    ITEM_HEIGHT = 36
    WIDTH = 240

    def __init__(self, root, on_close):
        self.root = root
        self.on_close = on_close
        self.win = None
        self._closing = False
        self._add_form = None  # Add form frame

    def _load_items(self):
        """Load items fresh from config"""
        if CONFIG_FILE.exists():
            try:
                with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                    return json.load(f).get("items", [])
            except:
                pass
        return [
            {"name": "Notepad", "path": "notepad.exe", "icon": "📝"},
            {"name": "Explorer", "path": "explorer.exe", "icon": "📁"},
        ]

    def show(self, x, y):
        if self.win or self._closing:
            return

        items = self._load_items()  # Fresh load!

        self.win = tk.Toplevel(self.root)
        self.win.overrideredirect(True)
        self.win.attributes("-topmost", True)
        self.win.attributes("-alpha", 0.95)
        self.win.configure(bg=self.BG)

        # Size and position (+40 for Add button)
        height = len(items) * self.ITEM_HEIGHT + 56
        screen_w = self.root.winfo_screenwidth()
        screen_h = self.root.winfo_screenheight()
        x = min(x, screen_w - self.WIDTH - 10)
        y = min(y, screen_h - height - 40)
        self.win.geometry(f"{self.WIDTH}x{height}+{x}+{y}")

        # Items
        self._frame = tk.Frame(self.win, bg=self.BG)
        self._frame.pack(fill="both", expand=True, padx=8, pady=8)

        for i, item in enumerate(items):
            self._create_item(self._frame, item, i)

        # Add button
        self._create_add_button(self._frame)

        self.win.bind("<Escape>", lambda e: self._on_escape())
        self.win.focus_force()

        # Reset flag - wait for buttons to release before listening
        self._buttons_released = False
        self.win.after(50, self._check_click_outside)

    def _create_item(self, parent, item, index):
        icon = item.get("icon", "▶")
        name = item.get("name", "Unknown")
        path = item.get("path", "")
        is_sep = item.get("separator", False)

        if is_sep:
            # Separator - non-clickable divider
            lbl = tk.Label(
                parent,
                text=f"  {name}",
                font=("Segoe UI", 9),
                bg=self.BG,
                fg="#555555",
                anchor="center",
                pady=2,
            )
            lbl.pack(fill="x", pady=0)
            return

        lbl = tk.Label(
            parent,
            text=f" {icon}  {name}",
            font=("Segoe UI", 11),
            bg=self.BG,
            fg=self.FG,
            anchor="w",
            padx=8,
            pady=4,
            cursor="hand2",
        )
        lbl.pack(fill="x", pady=2)

        lbl.bind("<Enter>", lambda e: lbl.configure(bg=self.HOVER))
        lbl.bind("<Leave>", lambda e: lbl.configure(bg=self.BG))
        lbl.bind("<Button-1>", lambda e: self._launch(path))

        if index < 9:
            self.win.bind(str(index + 1), lambda e, p=path: self._launch(p))

    def _create_add_button(self, parent):
        """Create + button at bottom"""
        self._add_btn = tk.Label(
            parent,
            text=" ➕  Add new...",
            font=("Segoe UI", 10),
            bg=self.BG,
            fg="#888888",
            anchor="w",
            padx=8,
            pady=4,
            cursor="hand2",
        )
        self._add_btn.pack(fill="x", pady=(8, 0))
        self._add_btn.bind("<Enter>", lambda e: self._add_btn.configure(bg=self.HOVER))
        self._add_btn.bind("<Leave>", lambda e: self._add_btn.configure(bg=self.BG))
        self._add_btn.bind("<Button-1>", lambda e: self._show_add_form())

    def _show_add_form(self):
        """Show inline add form"""
        if self._add_form:
            return

        self._add_btn.pack_forget()

        self._add_form = tk.Frame(self._frame, bg=self.BG)
        self._add_form.pack(fill="x", pady=(8, 0))

        # Path field
        tk.Label(self._add_form, text="Path:", font=("Segoe UI", 9),
                bg=self.BG, fg="#888888").pack(anchor="w")
        self._path_entry = tk.Entry(self._add_form, font=("Segoe UI", 10),
                                    bg="#2d2d44", fg=self.FG, insertbackground=self.FG,
                                    relief="flat", width=28)
        self._path_entry.pack(fill="x", pady=(0, 4))

        # Name field
        tk.Label(self._add_form, text="Name:", font=("Segoe UI", 9),
                bg=self.BG, fg="#888888").pack(anchor="w")
        self._name_entry = tk.Entry(self._add_form, font=("Segoe UI", 10),
                                    bg="#2d2d44", fg=self.FG, insertbackground=self.FG,
                                    relief="flat", width=28)
        self._name_entry.pack(fill="x", pady=(0, 4))

        # Bind Enter to save
        self._path_entry.bind("<Return>", lambda e: self._name_entry.focus())
        self._name_entry.bind("<Return>", lambda e: self._save_new_item())

        self._path_entry.focus()

        # Resize window
        self.win.update_idletasks()
        h = self.win.winfo_reqheight()
        self.win.geometry(f"{self.WIDTH}x{h}")

    def _hide_add_form(self):
        """Hide the add form"""
        if self._add_form:
            self._add_form.destroy()
            self._add_form = None
            self._add_btn.pack(fill="x", pady=(8, 0))
            # Resize window back
            self.win.update_idletasks()
            h = self.win.winfo_reqheight()
            self.win.geometry(f"{self.WIDTH}x{h}")

    def _save_new_item(self):
        """Save new item to config"""
        path = self._path_entry.get().strip()
        name = self._name_entry.get().strip()

        if not path:
            return

        if not name:
            name = Path(path).stem  # Auto-name from filename

        # Load, append, save
        items = self._load_items()
        items.append({"name": name, "path": path, "icon": "📌"})

        try:
            with open(CONFIG_FILE, "w", encoding="utf-8") as f:
                json.dump({"items": items}, f, indent=2, ensure_ascii=False)
        except:
            pass

        self.hide()

    def _on_escape(self):
        """Handle Escape key"""
        if self._add_form:
            self._hide_add_form()
        else:
            self.hide()

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

    def _check_click_outside(self):
        if not self.win or self._closing:
            return

        left = user32.GetAsyncKeyState(VK_LBUTTON) & 0x8000
        right = user32.GetAsyncKeyState(VK_RBUTTON) & 0x8000

        # Wait for BOTH buttons to be released before listening for clicks
        if not self._buttons_released:
            if not left and not right:
                self._buttons_released = True
            self.win.after(50, self._check_click_outside)
            return

        # Now listen for fresh left click outside
        if left and not right:
            pt = POINT()
            user32.GetCursorPos(ctypes.byref(pt))
            try:
                wx, wy = self.win.winfo_rootx(), self.win.winfo_rooty()
                ww, wh = self.win.winfo_width(), self.win.winfo_height()
                if not (wx <= pt.x <= wx + ww and wy <= pt.y <= wy + wh):
                    self.hide()
                    return
            except tk.TclError:
                pass

        if self.win:
            self.win.after(50, self._check_click_outside)

    def hide(self):
        if self._closing:
            return
        self._closing = True

        if self.win:
            try:
                self.win.destroy()
            except:
                pass
            self.win = None

        # Small delay before allowing next popup
        self.root.after(300, self._finish_close)

    def _finish_close(self):
        self._closing = False
        self.on_close()


class MouseLauncher:
    """Main application controller"""

    def __init__(self):
        self.root = tk.Tk()
        self.root.withdraw()

        self.popup = LauncherPopup(self.root, self._on_popup_close)
        self._popup_shown = False
        self._both_were_up = True
        self._last_trigger = 0

    def _poll_mouse(self):
        left = user32.GetAsyncKeyState(VK_LBUTTON) & 0x8000
        right = user32.GetAsyncKeyState(VK_RBUTTON) & 0x8000

        if left and right:
            now = time.time()
            if self._both_were_up and not self._popup_shown:
                if now - self._last_trigger > 0.5:  # Debounce
                    self._both_were_up = False
                    self._last_trigger = now
                    pt = POINT()
                    user32.GetCursorPos(ctypes.byref(pt))
                    self._show_popup(pt.x, pt.y)
        elif not left and not right:
            self._both_were_up = True

        self.root.after(POLL_MS, self._poll_mouse)

    def _show_popup(self, x, y):
        self._popup_shown = True
        self.popup.show(x, y)

    def _on_popup_close(self):
        self._popup_shown = False

    def run(self):
        self.root.after(100, self._poll_mouse)
        self.root.mainloop()


if __name__ == "__main__":
    MouseLauncher().run()
