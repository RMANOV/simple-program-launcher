# Mouse Launcher

**Minimalist app launcher triggered by simultaneous Left+Right mouse click.**

Zero external dependencies - pure Python standard library (tkinter + ctypes).

![Windows](https://img.shields.io/badge/Windows-0078D6?style=flat&logo=windows)
![Python 3.8+](https://img.shields.io/badge/Python-3.8+-blue.svg)
![No Dependencies](https://img.shields.io/badge/Dependencies-None-green.svg)

---

## Features

- **L+R Click Trigger** - Press both mouse buttons simultaneously to show launcher
- **Instant Access** - Popup appears at cursor position
- **Hot Reload** - Edit `config.json` anytime, changes apply on next trigger
- **Keyboard Shortcuts** - Press 1-9 to launch items quickly
- **Click Outside to Close** - Or press Escape
- **Separators** - Organize items into groups
- **➕ Add New Items** - Click to add programs directly from launcher
- **Auto-naming** - Leave name empty, uses filename automatically
- **UWP/Store Apps** - Launch Windows Store apps via `shell:AppsFolder`
- **Compact Design** - Minimal margins, maximum density
- **Auto Start** - Optional Windows startup integration

---

## Quick Start

```bash
# Run directly
pythonw launcher.pyw

# Or with visible console (for debugging)
python launcher.pyw
```

**Usage:** Press **Left + Right mouse buttons** together anywhere on screen.

---

## Claude / Codex session panes

`WT Quad (4)` reserves the left two panes as persistent launcher slots:

- pane 1: Claude
- pane 2: Codex
- panes 3-4: regular CMD/Clink shells

`WT Quad (4)` is the only command that creates the stable named window
`RManovQuad`; its first two panes run resident supervisors. `Claude Resume` and
`Codex Resume` only send an idempotent request to those existing slots. They do
not create a window/tab/pane, never kill an active writer, and never create one
window per agent/click. State is stored under
`%LOCALAPPDATA%\RManov\SessionPanes` by `scripts/session_pane.ps1`.

The old automatic four-pane `startupActions` is disabled so a normal WT launch
cannot create a second, unmanaged quad. After the current old tab is no longer
needed, close that WT window once and run `WT Quad (4)` to create the canonical
layout; later resume clicks stay in its fixed panes.

Inside either TUI, `/restart` records the exact session UUID.  After exit, the
same UUID is resumed; a failed resume keeps the state for the next attempt.

The CMD panes load `%LOCALAPPDATA%\clink\console_audit.lua`, which prints a
dated/attributed `COMMAND` prompt and a separate `RESULT` marker immediately
before command output.

---

## Adding Items

### Method 1: Via UI (Quick)

1. Trigger launcher (L+R click)
2. Click **"➕ Add new..."**
3. Enter path (full path to exe/file/folder)
4. Enter name (optional - auto-generated from filename)
5. Press **Enter** to save

### Method 2: Edit config.json (Full Control)

Edit `config.json` directly for separators, custom icons, and advanced options.

---

## Configuration

Edit `config.json` to customize your launcher:

```json
{
  "items": [
    {"name": "My App", "path": "C:\\path\\to\\app.exe", "icon": "🚀"},
    {"name": "Project Folder", "path": "D:\\Projects", "icon": "📁"},
    {"name": "─────────────", "path": "", "icon": " ", "separator": true},
    {"name": "Notepad", "path": "notepad.exe", "icon": "📝"},
    {"name": "Calculator", "path": "calc.exe", "icon": "🔢"}
  ]
}
```

### Item Properties

| Property | Required | Description |
|----------|----------|-------------|
| `name` | Yes | Display name |
| `path` | Yes | Full path to exe/file/folder, or system command |
| `icon` | No | Emoji or character (default: ▶) |
| `separator` | No | Set `true` for non-clickable divider line |

### Windows Store / UWP Apps

```json
{"name": "ChatGPT", "path": "shell:AppsFolder\\OpenAI.ChatGPT-Desktop_2p2nqsd0c76g0!ChatGPT", "icon": "💬"},
{"name": "Copilot", "path": "shell:AppsFolder\\Microsoft.MicrosoftOfficeHub_8wekyb3d8bbwe!Microsoft.MicrosoftOfficeHub", "icon": "✨"}
```

**Find AppID via PowerShell:**
```powershell
Get-StartApps | Where-Object Name -match "appname"
```

---

## Auto Start (Windows)

### Method 1: VBS Script (Silent, No Console Flash)

1. Press `Win+R`, type `shell:startup`, press Enter
2. Create `MouseLauncher.vbs` with this content:

```vbs
' MouseLauncher.vbs - Silent startup script
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "pythonw ""D:\path\to\launcher.pyw""", 0, False
```

### Method 2: BAT File (Simple, Brief Console Flash)

Create `MouseLauncher.bat` in `shell:startup`:

```bat
@echo off
start "" pythonw "D:\path\to\launcher.pyw"
```

---

## How It Works

### Architecture

```
┌─────────────────────────────────────────────────────┐
│  MouseLauncher (Main Controller)                    │
│  ├── Polls mouse state every 30ms via Windows API  │
│  ├── Detects L+R simultaneous press                │
│  └── Manages popup lifecycle                        │
├─────────────────────────────────────────────────────┤
│  LauncherPopup (UI)                                 │
│  ├── Borderless tkinter window                     │
│  ├── Loads config.json fresh on each show          │
│  ├── Click-outside detection with debounce         │
│  └── Inline add form for new items                 │
└─────────────────────────────────────────────────────┘
```

### Key Technical Decisions

**1. Polling vs Hooks**
```python
# Using GetAsyncKeyState polling (simple, reliable)
left = user32.GetAsyncKeyState(VK_LBUTTON) & 0x8000
right = user32.GetAsyncKeyState(VK_RBUTTON) & 0x8000

# Why not SetWindowsHookEx?
# - Hooks require message pump in separate thread
# - 64-bit type issues with ctypes callbacks
# - Polling at 30ms is imperceptible and CPU-light
```

**2. Click-Outside Detection Challenge**
```python
# Problem: L+R triggers popup, but L is still held
# → Immediately detected as "click outside" → closes instantly

# Solution: Wait for BOTH buttons to release first
if not self._buttons_released:
    if not left and not right:
        self._buttons_released = True  # Now start listening
    return  # Keep waiting
```

**3. Hot Reload Config**
```python
def show(self, x, y):
    items = self._load_items()  # Fresh load every time!
    # No restart needed when editing config.json
```

**4. Launch Strategy**
```python
if os.path.exists(path):
    os.startfile(path)      # Files, folders, URLs
else:
    subprocess.Popen(path, shell=True)  # System commands, UWP apps
```

**5. Auto-naming**
```python
if not name:
    name = Path(path).stem  # Extract filename without extension
```

---

## Full Source Code

<details>
<summary>launcher.pyw (~330 lines)</summary>

```python
"""
Mouse Launcher - L+R Click to Launch
Minimalist launcher with zero external dependencies
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


CONFIG_FILE = Path(__file__).parent / "config.json"
POLL_MS = 30


class LauncherPopup:
    """Floating popup window with pinned items"""

    BG = "#1a1a2e"
    FG = "#ffffff"
    HOVER = "#2d2d44"
    ITEM_HEIGHT = 26
    WIDTH = 240

    def __init__(self, root, on_close):
        self.root = root
        self.on_close = on_close
        self.win = None
        self._closing = False
        self._add_form = None

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

        items = self._load_items()

        self.win = tk.Toplevel(self.root)
        self.win.overrideredirect(True)
        self.win.attributes("-topmost", True)
        self.win.attributes("-alpha", 0.95)
        self.win.configure(bg=self.BG)

        height = len(items) * self.ITEM_HEIGHT + 30
        screen_w = self.root.winfo_screenwidth()
        screen_h = self.root.winfo_screenheight()
        x = min(x, screen_w - self.WIDTH - 10)
        y = min(y, screen_h - height - 40)
        self.win.geometry(f"{self.WIDTH}x{height}+{x}+{y}")

        self._frame = tk.Frame(self.win, bg=self.BG)
        self._frame.pack(fill="both", expand=True, padx=4, pady=4)

        for i, item in enumerate(items):
            self._create_item(self._frame, item, i)

        self._create_add_button(self._frame)

        self.win.bind("<Escape>", lambda e: self._on_escape())
        self.win.focus_force()

        self._buttons_released = False
        self.win.after(50, self._check_click_outside)

    def _create_item(self, parent, item, index):
        icon = item.get("icon", "▶")
        name = item.get("name", "Unknown")
        path = item.get("path", "")
        is_sep = item.get("separator", False)

        if is_sep:
            lbl = tk.Label(parent, text=f"  {name}", font=("Segoe UI", 9),
                          bg=self.BG, fg="#555555", anchor="center", pady=0)
            lbl.pack(fill="x", pady=0)
            return

        lbl = tk.Label(parent, text=f" {icon}  {name}", font=("Segoe UI", 11),
                      bg=self.BG, fg=self.FG, anchor="w", padx=4, pady=2,
                      cursor="hand2")
        lbl.pack(fill="x", pady=1)

        lbl.bind("<Enter>", lambda e: lbl.configure(bg=self.HOVER))
        lbl.bind("<Leave>", lambda e: lbl.configure(bg=self.BG))
        lbl.bind("<Button-1>", lambda e: self._launch(path))

        if index < 9:
            self.win.bind(str(index + 1), lambda e, p=path: self._launch(p))

    def _create_add_button(self, parent):
        """Create + button at bottom"""
        self._add_btn = tk.Label(parent, text=" ➕  Add new...",
                                font=("Segoe UI", 10), bg=self.BG, fg="#888888",
                                anchor="w", padx=4, pady=2, cursor="hand2")
        self._add_btn.pack(fill="x", pady=(4, 0))
        self._add_btn.bind("<Enter>", lambda e: self._add_btn.configure(bg=self.HOVER))
        self._add_btn.bind("<Leave>", lambda e: self._add_btn.configure(bg=self.BG))
        self._add_btn.bind("<Button-1>", lambda e: self._show_add_form())

    def _show_add_form(self):
        """Show inline add form"""
        if self._add_form:
            return

        self._add_btn.pack_forget()

        self._add_form = tk.Frame(self._frame, bg=self.BG)
        self._add_form.pack(fill="x", pady=(4, 0))

        tk.Label(self._add_form, text="Path:", font=("Segoe UI", 9),
                bg=self.BG, fg="#888888").pack(anchor="w")
        self._path_entry = tk.Entry(self._add_form, font=("Segoe UI", 10),
                                    bg="#2d2d44", fg=self.FG,
                                    insertbackground=self.FG, relief="flat")
        self._path_entry.pack(fill="x", pady=(0, 2))

        tk.Label(self._add_form, text="Name:", font=("Segoe UI", 9),
                bg=self.BG, fg="#888888").pack(anchor="w")
        self._name_entry = tk.Entry(self._add_form, font=("Segoe UI", 10),
                                    bg="#2d2d44", fg=self.FG,
                                    insertbackground=self.FG, relief="flat")
        self._name_entry.pack(fill="x", pady=(0, 2))

        self._path_entry.bind("<Return>", lambda e: self._name_entry.focus())
        self._name_entry.bind("<Return>", lambda e: self._save_new_item())

        self._path_entry.focus()

        self.win.update_idletasks()
        self.win.geometry(f"{self.WIDTH}x{self.win.winfo_reqheight()}")

    def _hide_add_form(self):
        if self._add_form:
            self._add_form.destroy()
            self._add_form = None
            self._add_btn.pack(fill="x", pady=(4, 0))
            self.win.update_idletasks()
            self.win.geometry(f"{self.WIDTH}x{self.win.winfo_reqheight()}")

    def _save_new_item(self):
        """Save new item to config"""
        path = self._path_entry.get().strip()
        name = self._name_entry.get().strip()

        if not path:
            return

        if not name:
            name = Path(path).stem  # Auto-name from filename

        items = self._load_items()
        items.append({"name": name, "path": path, "icon": "📌"})

        try:
            with open(CONFIG_FILE, "w", encoding="utf-8") as f:
                json.dump({"items": items}, f, indent=2, ensure_ascii=False)
        except:
            pass

        self.hide()

    def _on_escape(self):
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

        if not self._buttons_released:
            if not left and not right:
                self._buttons_released = True
            self.win.after(50, self._check_click_outside)
            return

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
                if now - self._last_trigger > 0.5:
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
```

</details>

---

## License

MIT License - Use freely, modify as needed.

---

*Built with Python, zero dependencies, maximum simplicity.*
