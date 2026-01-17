#!/usr/bin/env python3
"""
Simple Program Launcher - Windows Python Version
Cross-platform program launcher triggered by simultaneous L+R mouse click.

This version uses Python + tkinter for Windows where GUI dependencies are built-in.
For Linux/macOS, use the Rust version for better performance.

Requirements:
- Python 3.8+
- pywin32 (Windows only, for clipboard)
- pynput (for mouse events)

Install: pip install pynput pywin32
"""

import json
import os
import sys
import threading
import time
from pathlib import Path
from dataclasses import dataclass, field
from typing import List, Dict, Optional, Callable
from datetime import datetime, timedelta
import subprocess
import math

# Cross-platform imports
try:
    import tkinter as tk
    from tkinter import ttk, simpledialog, messagebox
except ImportError:
    print("Error: tkinter not available. Install python3-tk package.")
    sys.exit(1)

try:
    from pynput import mouse
    from pynput.mouse import Listener as MouseListener
except ImportError:
    print("Error: pynput not available. Install with: pip install pynput")
    sys.exit(1)

# Windows-specific imports
if sys.platform == 'win32':
    try:
        import ctypes
        from ctypes import wintypes
    except ImportError:
        pass


# ============== Configuration ==============

@dataclass
class LaunchItem:
    """A launchable item (program, document, or shortcut)"""
    name: str
    path: str
    icon: Optional[str] = None
    args: List[str] = field(default_factory=list)
    item_type: str = "program"  # program, document, shortcut

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "path": self.path,
            "icon": self.icon,
            "args": self.args,
            "item_type": self.item_type,
        }

    @classmethod
    def from_dict(cls, data: dict) -> "LaunchItem":
        return cls(
            name=data.get("name", ""),
            path=data.get("path", ""),
            icon=data.get("icon"),
            args=data.get("args", []),
            item_type=data.get("item_type", "program"),
        )


@dataclass
class Config:
    """Launcher configuration"""
    pinned_programs: List[LaunchItem] = field(default_factory=list)
    pinned_documents: List[LaunchItem] = field(default_factory=list)
    shortcuts: List[LaunchItem] = field(default_factory=list)
    pinned_clipboard: List[str] = field(default_factory=list)  # Pinned clipboard entries
    max_frequent_programs: int = 5
    max_frequent_documents: int = 5
    max_clipboard_history: int = 10000
    simultaneous_threshold_ms: int = 50
    debounce_ms: int = 500
    ui_width: int = 300
    dark_mode: bool = True

    @classmethod
    def get_config_path(cls) -> Path:
        if sys.platform == 'win32':
            base = Path(os.environ.get('APPDATA', Path.home()))
        else:
            base = Path.home() / '.config'
        config_dir = base / 'launcher'
        config_dir.mkdir(parents=True, exist_ok=True)
        return config_dir / 'config.json'

    @classmethod
    def load(cls) -> "Config":
        path = cls.get_config_path()
        if path.exists():
            try:
                with open(path, 'r') as f:
                    data = json.load(f)
                return cls(
                    pinned_programs=[LaunchItem.from_dict(p) for p in data.get("pinned_programs", [])],
                    pinned_documents=[LaunchItem.from_dict(d) for d in data.get("pinned_documents", [])],
                    shortcuts=[LaunchItem.from_dict(s) for s in data.get("shortcuts", [])],
                    pinned_clipboard=data.get("pinned_clipboard", []),
                    max_frequent_programs=data.get("max_frequent_programs", 5),
                    max_frequent_documents=data.get("max_frequent_documents", 5),
                    max_clipboard_history=data.get("max_clipboard_history", 10000),
                    simultaneous_threshold_ms=data.get("trigger", {}).get("simultaneous_threshold_ms", 50),
                    debounce_ms=data.get("trigger", {}).get("debounce_ms", 500),
                    ui_width=data.get("ui", {}).get("width", 300),
                    dark_mode=data.get("ui", {}).get("dark_mode", True),
                )
            except Exception as e:
                print(f"Error loading config: {e}")
        return cls._default()

    @classmethod
    def _default(cls) -> "Config":
        return cls(
            shortcuts=[
                LaunchItem(
                    name="Lock Screen",
                    path="rundll32.exe" if sys.platform == 'win32' else "loginctl",
                    args=["user32.dll,LockWorkStation"] if sys.platform == 'win32' else ["lock-session"],
                    item_type="shortcut",
                ),
            ]
        )

    def save(self):
        path = self.get_config_path()
        data = {
            "pinned_programs": [p.to_dict() for p in self.pinned_programs],
            "pinned_documents": [d.to_dict() for d in self.pinned_documents],
            "shortcuts": [s.to_dict() for s in self.shortcuts],
            "pinned_clipboard": self.pinned_clipboard,
            "max_frequent_programs": self.max_frequent_programs,
            "max_frequent_documents": self.max_frequent_documents,
            "max_clipboard_history": self.max_clipboard_history,
            "trigger": {
                "simultaneous_threshold_ms": self.simultaneous_threshold_ms,
                "debounce_ms": self.debounce_ms,
            },
            "ui": {
                "width": self.ui_width,
                "dark_mode": self.dark_mode,
            },
        }
        with open(path, 'w') as f:
            json.dump(data, f, indent=2)


# ============== Usage Tracking ==============

@dataclass
class UsageRecord:
    """Usage record for a single item with recency-weighted scoring"""
    path: str
    name: str
    launches: List[str] = field(default_factory=list)  # ISO timestamps

    HALF_LIFE_DAYS = 7

    def record_launch(self):
        self.launches.append(datetime.utcnow().isoformat())
        # Keep only last 100 launches
        if len(self.launches) > 100:
            self.launches = self.launches[-100:]

    def score(self) -> float:
        """Calculate recency-weighted score with 7-day half-life"""
        now = datetime.utcnow()
        half_life = timedelta(days=self.HALF_LIFE_DAYS)
        total = 0.0

        for ts_str in self.launches:
            try:
                ts = datetime.fromisoformat(ts_str.replace('Z', '+00:00').replace('+00:00', ''))
                age = now - ts
                if age.total_seconds() < 0:
                    total += 1.0
                else:
                    decay = math.pow(2, -age.total_seconds() / half_life.total_seconds())
                    total += decay
            except:
                pass

        return total


class UsageTracker:
    """Track program and document usage"""

    def __init__(self):
        self.programs: Dict[str, UsageRecord] = {}
        self.documents: Dict[str, UsageRecord] = {}
        self._load()

    @staticmethod
    def _data_path() -> Path:
        if sys.platform == 'win32':
            base = Path(os.environ.get('LOCALAPPDATA', Path.home()))
        else:
            base = Path.home() / '.local' / 'share'
        data_dir = base / 'launcher'
        data_dir.mkdir(parents=True, exist_ok=True)
        return data_dir / 'usage.json'

    def _load(self):
        path = self._data_path()
        if path.exists():
            try:
                with open(path, 'r') as f:
                    data = json.load(f)
                for key, val in data.get("programs", {}).items():
                    self.programs[key] = UsageRecord(
                        path=val.get("path", key),
                        name=val.get("name", ""),
                        launches=val.get("launches", []),
                    )
                for key, val in data.get("documents", {}).items():
                    self.documents[key] = UsageRecord(
                        path=val.get("path", key),
                        name=val.get("name", ""),
                        launches=val.get("launches", []),
                    )
            except Exception as e:
                print(f"Error loading usage data: {e}")

    def save(self):
        path = self._data_path()
        data = {
            "programs": {
                k: {"path": v.path, "name": v.name, "launches": v.launches}
                for k, v in self.programs.items()
            },
            "documents": {
                k: {"path": v.path, "name": v.name, "launches": v.launches}
                for k, v in self.documents.items()
            },
        }
        with open(path, 'w') as f:
            json.dump(data, f, indent=2)

    def record_program(self, path: str, name: str):
        if path not in self.programs:
            self.programs[path] = UsageRecord(path=path, name=name)
        self.programs[path].record_launch()

    def record_document(self, path: str, name: str):
        if path not in self.documents:
            self.documents[path] = UsageRecord(path=path, name=name)
        self.documents[path].record_launch()

    def top_programs(self, n: int) -> List[UsageRecord]:
        return sorted(self.programs.values(), key=lambda r: r.score(), reverse=True)[:n]

    def top_documents(self, n: int) -> List[UsageRecord]:
        return sorted(self.documents.values(), key=lambda r: r.score(), reverse=True)[:n]


# ============== Platform Data Sources ==============

def get_recent_files_windows(limit: int) -> List[LaunchItem]:
    """Get recent files from Windows Recent folder"""
    items = []
    recent_dir = Path(os.environ.get('APPDATA', '')) / 'Microsoft' / 'Windows' / 'Recent'

    if recent_dir.exists():
        files = sorted(recent_dir.glob('*.lnk'), key=lambda p: p.stat().st_mtime, reverse=True)
        for lnk in files[:limit * 2]:  # Get more, filter later
            # Extract target from .lnk (simplified - just use the name)
            name = lnk.stem
            if name.startswith('.') or name in ('desktop.ini',):
                continue
            items.append(LaunchItem(
                name=name,
                path=str(lnk),
                item_type="document",
            ))
            if len(items) >= limit:
                break

    return items


def get_installed_apps_windows() -> List[LaunchItem]:
    """Get installed apps from Start Menu"""
    items = []
    start_menu_paths = [
        Path(os.environ.get('APPDATA', '')) / 'Microsoft' / 'Windows' / 'Start Menu' / 'Programs',
        Path(os.environ.get('PROGRAMDATA', '')) / 'Microsoft' / 'Windows' / 'Start Menu' / 'Programs',
    ]

    for start_menu in start_menu_paths:
        if start_menu.exists():
            for lnk in start_menu.rglob('*.lnk'):
                name = lnk.stem
                if name.startswith('.'):
                    continue
                items.append(LaunchItem(
                    name=name,
                    path=str(lnk),
                    item_type="program",
                ))

    # Remove duplicates by name
    seen = set()
    unique = []
    for item in items:
        if item.name not in seen:
            seen.add(item.name)
            unique.append(item)

    return unique


def launch_item(item: LaunchItem):
    """Launch an item"""
    try:
        if sys.platform == 'win32':
            os.startfile(item.path)
        elif sys.platform == 'darwin':
            subprocess.Popen(['open', item.path] + item.args)
        else:
            if item.item_type == 'document':
                subprocess.Popen(['xdg-open', item.path])
            else:
                subprocess.Popen([item.path] + item.args)
    except Exception as e:
        print(f"Error launching {item.name}: {e}")


# ============== Clipboard ==============

class ClipboardManager:
    """Manage clipboard history"""

    def __init__(self, max_items: int = 10000):
        self.max_items = max_items
        self.history: List[str] = []
        self.last_content = ""

    def update(self):
        """Check clipboard and update history"""
        try:
            if sys.platform == 'win32':
                import ctypes
                CF_TEXT = 1
                user32 = ctypes.windll.user32
                kernel32 = ctypes.windll.kernel32

                user32.OpenClipboard(0)
                try:
                    if user32.IsClipboardFormatAvailable(CF_TEXT):
                        data = user32.GetClipboardData(CF_TEXT)
                        text = ctypes.c_char_p(data).value
                        if text:
                            text = text.decode('utf-8', errors='ignore')
                            self._add_to_history(text)
                finally:
                    user32.CloseClipboard()
            else:
                # Use tkinter clipboard
                try:
                    root = tk._default_root
                    if root:
                        text = root.clipboard_get()
                        self._add_to_history(text)
                except:
                    pass
        except:
            pass

    def _add_to_history(self, text: str):
        """Add text to history if it's new"""
        if not text or text == self.last_content:
            return

        # Skip password-like content
        if self._looks_like_password(text):
            return

        self.last_content = text

        # Remove if already in history
        if text in self.history:
            self.history.remove(text)

        # Add to front
        self.history.insert(0, text)

        # Trim
        self.history = self.history[:self.max_items]

    def _looks_like_password(self, text: str) -> bool:
        """Simple heuristic for password detection"""
        if len(text) < 8 or len(text) > 32:
            return False
        if ' ' in text:
            return False
        has_upper = any(c.isupper() for c in text)
        has_lower = any(c.islower() for c in text)
        has_digit = any(c.isdigit() for c in text)
        return has_upper and has_lower and has_digit

    def paste(self, text: str):
        """Set clipboard content"""
        try:
            if sys.platform == 'win32':
                import ctypes
                CF_UNICODETEXT = 13
                user32 = ctypes.windll.user32
                kernel32 = ctypes.windll.kernel32

                user32.OpenClipboard(0)
                try:
                    user32.EmptyClipboard()
                    data = text.encode('utf-16-le') + b'\x00\x00'
                    h = kernel32.GlobalAlloc(0x0042, len(data))
                    p = kernel32.GlobalLock(h)
                    ctypes.memmove(p, data, len(data))
                    kernel32.GlobalUnlock(h)
                    user32.SetClipboardData(CF_UNICODETEXT, h)
                finally:
                    user32.CloseClipboard()
            else:
                root = tk._default_root
                if root:
                    root.clipboard_clear()
                    root.clipboard_append(text)
        except Exception as e:
            print(f"Error setting clipboard: {e}")

    def search(self, query: str, limit: int = 50) -> List[str]:
        """Search clipboard history - instant fuzzy search"""
        if not query:
            return self.history[:limit]

        query_lower = query.lower()
        results = []

        for item in self.history:
            if query_lower in item.lower():
                results.append(item)
                if len(results) >= limit:
                    break

        return results


# ============== Mouse Input ==============

class MouseInputListener:
    """Detect simultaneous L+R mouse clicks"""

    def __init__(self, threshold_ms: int, debounce_ms: int, on_trigger: Callable[[tuple], None]):
        self.threshold = threshold_ms / 1000.0
        self.debounce = debounce_ms / 1000.0
        self.on_trigger = on_trigger

        self.left_pressed: Optional[float] = None
        self.right_pressed: Optional[float] = None
        self.last_trigger: Optional[float] = None
        self.last_position = (0, 0)

        self.listener: Optional[MouseListener] = None

    def start(self):
        """Start listening for mouse events"""
        self.listener = MouseListener(
            on_click=self._on_click,
            on_move=self._on_move,
        )
        self.listener.start()

    def stop(self):
        """Stop listening"""
        if self.listener:
            self.listener.stop()

    def _on_move(self, x, y):
        self.last_position = (x, y)

    def _on_click(self, x, y, button, pressed):
        self.last_position = (x, y)
        now = time.time()

        if pressed:
            if button == mouse.Button.left:
                self.left_pressed = now
            elif button == mouse.Button.right:
                self.right_pressed = now

            self._check_trigger()
        else:
            if button == mouse.Button.left:
                self.left_pressed = None
            elif button == mouse.Button.right:
                self.right_pressed = None

    def _check_trigger(self):
        if self.left_pressed is None or self.right_pressed is None:
            return

        diff = abs(self.left_pressed - self.right_pressed)
        if diff > self.threshold:
            return

        now = time.time()
        if self.last_trigger and (now - self.last_trigger) < self.debounce:
            return

        self.last_trigger = now
        self.left_pressed = None
        self.right_pressed = None

        self.on_trigger(self.last_position)


# ============== UI ==============

class LauncherPopup:
    """Popup window for the launcher"""

    # Dark theme colors
    BG_COLOR = "#1e1e23"
    PANEL_COLOR = "#282830"
    TEXT_COLOR = "#e6e6e6"
    DIM_TEXT = "#9696a0"
    ACCENT_COLOR = "#6495ed"
    HOVER_COLOR = "#3c3c4b"
    SEPARATOR_COLOR = "#3c3c46"

    def __init__(self, position: tuple, config: Config, usage_tracker: UsageTracker,
                 clipboard_manager: ClipboardManager):
        self.config = config
        self.usage_tracker = usage_tracker
        self.clipboard = clipboard_manager
        self.position = position

        self.root: Optional[tk.Tk] = None
        self.shortcut_num = 1
        self.clipboard_search_var: Optional[tk.StringVar] = None
        self.clipboard_frame: Optional[tk.Frame] = None

    def show(self):
        """Show the popup window"""
        self.root = tk.Tk()
        self.root.title("Launcher")

        # Remove window decorations
        self.root.overrideredirect(True)

        # Position at cursor
        x, y = self.position
        self.root.geometry(f"{self.config.ui_width}x400+{int(x)}+{int(y)}")

        # Dark theme
        self.root.configure(bg=self.BG_COLOR)

        # Style
        style = ttk.Style()
        style.theme_use('clam')
        style.configure('TFrame', background=self.BG_COLOR)
        style.configure('TLabel', background=self.BG_COLOR, foreground=self.TEXT_COLOR)
        style.configure('Header.TLabel', background=self.BG_COLOR, foreground=self.DIM_TEXT, font=('', 10))
        style.configure('TButton', background=self.PANEL_COLOR, foreground=self.TEXT_COLOR)

        # Main frame with scrollbar
        main_frame = ttk.Frame(self.root)
        main_frame.pack(fill=tk.BOTH, expand=True, padx=4, pady=4)

        canvas = tk.Canvas(main_frame, bg=self.BG_COLOR, highlightthickness=0)
        scrollbar = ttk.Scrollbar(main_frame, orient="vertical", command=canvas.yview)
        scrollable_frame = ttk.Frame(canvas)

        scrollable_frame.bind(
            "<Configure>",
            lambda e: canvas.configure(scrollregion=canvas.bbox("all"))
        )

        canvas.create_window((0, 0), window=scrollable_frame, anchor="nw", width=self.config.ui_width - 20)
        canvas.configure(yscrollcommand=scrollbar.set)

        canvas.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")

        # Build content
        self._build_content(scrollable_frame)

        # Bindings
        self.root.bind('<Escape>', lambda e: self.close())
        self.root.bind('<FocusOut>', lambda e: self.close())

        # Number key bindings
        for i in range(1, 10):
            self.root.bind(str(i), self._make_key_handler(i))

        # Keep on top
        self.root.attributes('-topmost', True)

        # Start main loop
        self.root.mainloop()

    def _build_content(self, parent: ttk.Frame):
        """Build the popup content"""
        self.shortcut_num = 1

        # Pinned Programs
        if self.config.pinned_programs:
            self._add_section(parent, "Pinned Programs")
            for item in self.config.pinned_programs:
                self._add_item_row(parent, item, pinned=True)
            self._add_separator(parent)

        # Frequent Programs (from usage tracking)
        top_programs = self.usage_tracker.top_programs(self.config.max_frequent_programs)
        pinned_paths = {p.path for p in self.config.pinned_programs}
        frequent = [p for p in top_programs if p.path not in pinned_paths]

        if frequent:
            self._add_section(parent, "Frequent Programs")
            for record in frequent[:self.config.max_frequent_programs]:
                item = LaunchItem(name=record.name, path=record.path, item_type="program")
                self._add_item_row(parent, item, show_pin=True)
            self._add_separator(parent)

        # Pinned Documents
        if self.config.pinned_documents:
            self._add_section(parent, "Pinned Documents")
            for item in self.config.pinned_documents:
                self._add_item_row(parent, item, pinned=True)
            self._add_separator(parent)

        # Recent Documents
        if sys.platform == 'win32':
            recent_docs = get_recent_files_windows(self.config.max_frequent_documents)
            pinned_doc_paths = {d.path for d in self.config.pinned_documents}
            recent_docs = [d for d in recent_docs if d.path not in pinned_doc_paths]

            if recent_docs:
                self._add_section(parent, "Recent Documents")
                for item in recent_docs[:self.config.max_frequent_documents]:
                    self._add_item_row(parent, item, show_pin=True)
                self._add_separator(parent)

        # Clipboard History with instant search
        self.clipboard.update()
        if self.clipboard.history:
            self._add_section(parent, "Clipboard History")

            # Search box
            search_frame = tk.Frame(parent, bg=self.BG_COLOR)
            search_frame.pack(fill=tk.X, pady=2)

            search_label = tk.Label(
                search_frame,
                text="\U0001F50D",  # 🔍
                bg=self.BG_COLOR,
                fg=self.DIM_TEXT,
            )
            search_label.pack(side=tk.LEFT, padx=(0, 4))

            self.clipboard_search_var = tk.StringVar()
            search_entry = tk.Entry(
                search_frame,
                textvariable=self.clipboard_search_var,
                bg=self.PANEL_COLOR,
                fg=self.TEXT_COLOR,
                insertbackground=self.TEXT_COLOR,
                relief=tk.FLAT,
                font=('', 11),
            )
            search_entry.pack(side=tk.LEFT, fill=tk.X, expand=True)
            search_entry.bind('<KeyRelease>', lambda e: self._update_clipboard_results(parent))

            # Clipboard results container
            self.clipboard_frame = tk.Frame(parent, bg=self.BG_COLOR)
            self.clipboard_frame.pack(fill=tk.X)

            # Show initial results
            self._update_clipboard_results(parent)
            self._add_separator(parent)

        # Shortcuts
        if self.config.shortcuts:
            self._add_section(parent, "Shortcuts")
            for item in self.config.shortcuts:
                self._add_item_row(parent, item, icon="\u26a1")
            self._add_separator(parent)

        # Add Shortcut button
        add_btn = tk.Button(
            parent,
            text="[+ Add Shortcut]",
            bg=self.BG_COLOR,
            fg=self.ACCENT_COLOR,
            activebackground=self.HOVER_COLOR,
            activeforeground=self.TEXT_COLOR,
            relief=tk.FLAT,
            cursor="hand2",
            command=self._show_add_dialog,
        )
        add_btn.pack(fill=tk.X, pady=4)

    def _add_section(self, parent: ttk.Frame, title: str):
        """Add a section header"""
        label = ttk.Label(parent, text=title, style='Header.TLabel')
        label.pack(fill=tk.X, pady=(8, 2))

    def _add_separator(self, parent: ttk.Frame):
        """Add a separator line"""
        sep = tk.Frame(parent, height=1, bg=self.SEPARATOR_COLOR)
        sep.pack(fill=tk.X, pady=4)

    def _add_item_row(self, parent: ttk.Frame, item: LaunchItem, pinned: bool = False,
                      show_pin: bool = False, icon: str = None):
        """Add an item row"""
        frame = tk.Frame(parent, bg=self.BG_COLOR)
        frame.pack(fill=tk.X, pady=1)

        # Shortcut key
        if self.shortcut_num <= 9:
            key_label = tk.Label(
                frame,
                text=f"[{self.shortcut_num}]",
                bg=self.BG_COLOR,
                fg=self.DIM_TEXT,
                font=('Consolas', 10),
            )
            key_label.pack(side=tk.LEFT, padx=(0, 4))

        # Store for keyboard shortcut
        item._shortcut_num = self.shortcut_num
        self.shortcut_num += 1

        # Main button
        btn = tk.Button(
            frame,
            text=item.name,
            bg=self.BG_COLOR,
            fg=self.TEXT_COLOR,
            activebackground=self.HOVER_COLOR,
            activeforeground=self.TEXT_COLOR,
            relief=tk.FLAT,
            anchor='w',
            cursor="hand2",
            command=lambda: self._launch(item),
        )
        btn.pack(side=tk.LEFT, fill=tk.X, expand=True)

        # Pin indicator or button
        if pinned:
            pin_label = tk.Label(frame, text="\U0001F4CC", bg=self.BG_COLOR, fg="#ffc832")
            pin_label.pack(side=tk.RIGHT, padx=4)
        elif show_pin:
            pin_btn = tk.Button(
                frame,
                text="pin",
                bg=self.BG_COLOR,
                fg=self.DIM_TEXT,
                activebackground=self.HOVER_COLOR,
                relief=tk.FLAT,
                cursor="hand2",
                font=('', 8),
                command=lambda: self._pin_item(item),
            )
            pin_btn.pack(side=tk.RIGHT, padx=2)

        # Icon
        if icon:
            icon_label = tk.Label(frame, text=icon, bg=self.BG_COLOR, fg="#ff9632")
            icon_label.pack(side=tk.RIGHT, padx=4)

    def _add_clipboard_row(self, parent: ttk.Frame, text: str, pinned: bool = False):
        """Add a clipboard history row with pin option"""
        frame = tk.Frame(parent, bg=self.BG_COLOR)
        frame.pack(fill=tk.X, pady=1)

        # Truncate for display
        preview = text[:47] + "..." if len(text) > 50 else text
        preview = preview.replace('\n', ' ')

        btn = tk.Button(
            frame,
            text=preview,
            bg=self.BG_COLOR,
            fg=self.TEXT_COLOR,
            activebackground=self.HOVER_COLOR,
            activeforeground=self.TEXT_COLOR,
            relief=tk.FLAT,
            anchor='w',
            cursor="hand2",
            command=lambda: self._paste_clipboard(text),
        )
        btn.pack(side=tk.LEFT, fill=tk.X, expand=True)

        # Pin button or indicator
        if pinned:
            pin_label = tk.Label(frame, text="\U0001F4CC", bg=self.BG_COLOR, fg="#ffc832")  # 📌
            pin_label.pack(side=tk.RIGHT, padx=2)
            # Unpin button
            unpin_btn = tk.Button(
                frame,
                text="x",
                bg=self.BG_COLOR,
                fg=self.DIM_TEXT,
                activebackground=self.HOVER_COLOR,
                relief=tk.FLAT,
                cursor="hand2",
                font=('', 8),
                command=lambda: self._unpin_clipboard(text),
            )
            unpin_btn.pack(side=tk.RIGHT, padx=2)
        else:
            pin_btn = tk.Button(
                frame,
                text="pin",
                bg=self.BG_COLOR,
                fg=self.DIM_TEXT,
                activebackground=self.HOVER_COLOR,
                relief=tk.FLAT,
                cursor="hand2",
                font=('', 8),
                command=lambda: self._pin_clipboard(text),
            )
            pin_btn.pack(side=tk.RIGHT, padx=2)

        icon_label = tk.Label(frame, text="\U0001F4CB", bg=self.BG_COLOR, fg="#64c896")  # 📋
        icon_label.pack(side=tk.RIGHT, padx=4)

    def _update_clipboard_results(self, parent):
        """Update clipboard results based on search query"""
        if not self.clipboard_frame:
            return

        # Clear existing results
        for widget in self.clipboard_frame.winfo_children():
            widget.destroy()

        query = self.clipboard_search_var.get() if self.clipboard_search_var else ""

        # Get search results
        results = self.clipboard.search(query, limit=50)

        # Filter out pinned items from regular results
        pinned_set = set(self.config.pinned_clipboard)
        regular_results = [r for r in results if r not in pinned_set]

        # Show first 10 results
        for text in regular_results[:10]:
            self._add_clipboard_row(self.clipboard_frame, text, pinned=False)

        # Show pinned clipboard section if there are pinned items
        if self.config.pinned_clipboard:
            # Add separator if there were regular results
            if regular_results:
                sep = tk.Frame(self.clipboard_frame, height=1, bg=self.SEPARATOR_COLOR)
                sep.pack(fill=tk.X, pady=4)

            pinned_label = tk.Label(
                self.clipboard_frame,
                text="Pinned Clipboard",
                bg=self.BG_COLOR,
                fg=self.SECTION_HEADER if hasattr(self, 'SECTION_HEADER') else self.DIM_TEXT,
                font=('', 10),
            )
            pinned_label.pack(fill=tk.X, pady=(4, 2))

            # Filter pinned by search query
            for text in self.config.pinned_clipboard:
                if not query or query.lower() in text.lower():
                    self._add_clipboard_row(self.clipboard_frame, text, pinned=True)

    def _pin_clipboard(self, text: str):
        """Pin a clipboard entry"""
        if text not in self.config.pinned_clipboard:
            self.config.pinned_clipboard.append(text)
            self.config.save()
            # Refresh the clipboard display
            self._update_clipboard_results(None)

    def _unpin_clipboard(self, text: str):
        """Unpin a clipboard entry"""
        if text in self.config.pinned_clipboard:
            self.config.pinned_clipboard.remove(text)
            self.config.save()
            # Refresh the clipboard display
            self._update_clipboard_results(None)

    def _make_key_handler(self, num: int):
        """Create a keyboard shortcut handler"""
        def handler(event):
            # Find item with this shortcut number
            all_items = (
                list(self.config.pinned_programs) +
                [LaunchItem(name=r.name, path=r.path) for r in self.usage_tracker.top_programs(5)] +
                list(self.config.pinned_documents) +
                list(self.config.shortcuts)
            )
            if num <= len(all_items):
                self._launch(all_items[num - 1])
        return handler

    def _launch(self, item: LaunchItem):
        """Launch an item"""
        launch_item(item)

        # Record usage
        if item.item_type == 'document':
            self.usage_tracker.record_document(item.path, item.name)
        else:
            self.usage_tracker.record_program(item.path, item.name)
        self.usage_tracker.save()

        self.close()

    def _pin_item(self, item: LaunchItem):
        """Pin an item to config"""
        if item.item_type == 'document':
            if item.path not in [d.path for d in self.config.pinned_documents]:
                self.config.pinned_documents.append(item)
        else:
            if item.path not in [p.path for p in self.config.pinned_programs]:
                self.config.pinned_programs.append(item)
        self.config.save()

    def _paste_clipboard(self, text: str):
        """Paste clipboard item"""
        self.clipboard.paste(text)
        self.close()

    def _show_add_dialog(self):
        """Show dialog to add a shortcut"""
        name = simpledialog.askstring("Add Shortcut", "Name:", parent=self.root)
        if not name:
            return

        path = simpledialog.askstring("Add Shortcut", "Path/Command:", parent=self.root)
        if not path:
            return

        item = LaunchItem(name=name, path=path, item_type="shortcut")
        self.config.shortcuts.append(item)
        self.config.save()

    def close(self):
        """Close the popup"""
        if self.root:
            self.root.destroy()
            self.root = None


# ============== Main ==============

class Launcher:
    """Main launcher application"""

    def __init__(self):
        self.config = Config.load()
        self.usage_tracker = UsageTracker()
        self.clipboard = ClipboardManager(self.config.max_clipboard_history)
        self.popup: Optional[LauncherPopup] = None

        self.input_listener = MouseInputListener(
            self.config.simultaneous_threshold_ms,
            self.config.debounce_ms,
            self._on_trigger,
        )

    def _on_trigger(self, position: tuple):
        """Handle trigger event"""
        print(f"Trigger at {position}")

        # Close existing popup if any
        if self.popup and self.popup.root:
            self.popup.close()

        # Show new popup
        self.popup = LauncherPopup(position, self.config, self.usage_tracker, self.clipboard)

        # Run in thread to not block input listener
        threading.Thread(target=self.popup.show, daemon=True).start()

    def run(self):
        """Start the launcher"""
        print("Simple Program Launcher")
        print(f"Trigger: L+R click (threshold: {self.config.simultaneous_threshold_ms}ms)")
        print("Press Ctrl+C to exit")

        self.input_listener.start()

        try:
            # Keep main thread alive
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            print("\nShutting down...")
            self.input_listener.stop()


if __name__ == "__main__":
    launcher = Launcher()
    launcher.run()
