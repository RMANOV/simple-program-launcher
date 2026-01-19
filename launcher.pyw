"""
Mouse Launcher - L+R Click to Launch
Минималистичен launcher без външни зависимости
Features: MFU tracking, Clipboard history, Fuzzy search
"""
import ctypes
import json
import os
import subprocess
import time
import tkinter as tk
from datetime import datetime
from pathlib import Path

# Windows API
user32 = ctypes.windll.user32
VK_LBUTTON, VK_RBUTTON = 0x01, 0x02


class POINT(ctypes.Structure):
    _fields_ = [("x", ctypes.c_long), ("y", ctypes.c_long)]


# Config files
CONFIG_FILE = Path(__file__).parent / "config.json"
USAGE_FILE = Path(__file__).parent / "usage.json"
CLIP_FILE = Path(__file__).parent / "clipboard.json"

# Settings
POLL_MS = 30
MAX_CLIPS = 20
MFU_COUNT = 5
CLIP_POLL_MS = 500


class LauncherPopup:
    """Floating popup window with pinned items"""

    BG = "#1a1a2e"
    FG = "#ffffff"
    HOVER = "#2d2d44"
    SECTION_FG = "#666666"
    ITEM_HEIGHT = 26
    WIDTH = 260

    def __init__(self, root, on_close):
        self.root = root
        self.on_close = on_close
        self.win = None
        self._closing = False
        self._add_form = None
        self._search_frame = None
        self._search_entry = None
        self._current_items = []
        self._item_labels = []
        self._clip_labels = []
        self._current_clips = []
        self._last_clip = ""

    # ==================== CONFIG ====================
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

    # ==================== MFU (Most Frequently Used) ====================
    def _load_usage(self):
        """Load usage stats"""
        if USAGE_FILE.exists():
            try:
                with open(USAGE_FILE, "r", encoding="utf-8") as f:
                    return json.load(f).get("items", {})
            except:
                pass
        return {}

    def _save_usage(self, usage):
        """Save usage stats"""
        try:
            with open(USAGE_FILE, "w", encoding="utf-8") as f:
                json.dump({"items": usage}, f, indent=2, ensure_ascii=False)
        except:
            pass

    def _track_usage(self, path):
        """Track item usage"""
        if not path:
            return
        usage = self._load_usage()
        now = datetime.now().isoformat()
        if path in usage:
            usage[path]["count"] += 1
            usage[path]["last"] = now
        else:
            usage[path] = {"count": 1, "last": now}
        self._save_usage(usage)

    def _get_mfu(self, top=5):
        """Get most frequently used items"""
        usage = self._load_usage()
        items = self._load_items()

        # Build path->item mapping
        path_to_item = {i["path"]: i for i in items if i.get("path")}

        # Sort by count descending
        sorted_paths = sorted(
            usage.keys(),
            key=lambda p: usage[p]["count"],
            reverse=True
        )[:top]

        result = []
        for path in sorted_paths:
            if path in path_to_item:
                item = path_to_item[path].copy()
                item["_count"] = usage[path]["count"]
                result.append(item)
        return result

    # ==================== CLIPBOARD ====================
    def _load_clips(self):
        """Load clipboard history"""
        if CLIP_FILE.exists():
            try:
                with open(CLIP_FILE, "r", encoding="utf-8") as f:
                    return json.load(f)
            except:
                pass
        return []

    def _save_clips(self, clips):
        """Save clipboard history"""
        try:
            with open(CLIP_FILE, "w", encoding="utf-8") as f:
                json.dump(clips[-MAX_CLIPS:], f, indent=2, ensure_ascii=False)
        except:
            pass

    def _poll_clipboard(self):
        """Poll clipboard for changes"""
        try:
            text = self.root.clipboard_get()
            if text and text != self._last_clip and len(text) < 1000:
                clips = self._load_clips()
                # Remove duplicate if exists
                if text in clips:
                    clips.remove(text)
                clips.append(text)
                self._save_clips(clips)
                self._last_clip = text
        except tk.TclError:
            pass  # Clipboard empty or non-text
        self.root.after(CLIP_POLL_MS, self._poll_clipboard)

    def _paste_clip(self, text):
        """Paste text to active window"""
        self.hide()
        try:
            self.root.clipboard_clear()
            self.root.clipboard_append(text)
            self.root.update()
            # Simulate Ctrl+V
            time.sleep(0.1)
            user32.keybd_event(0x11, 0, 0, 0)  # Ctrl down
            user32.keybd_event(0x56, 0, 0, 0)  # V down
            user32.keybd_event(0x56, 0, 2, 0)  # V up
            user32.keybd_event(0x11, 0, 2, 0)  # Ctrl up
        except Exception as e:
            print(f"Paste error: {e}")

    # ==================== SEARCH ====================
    def _fuzzy_match(self, query, text):
        """Simple fuzzy match - all chars in order"""
        if not query:
            return True
        qi = 0
        for c in text.lower():
            if qi < len(query) and c == query[qi].lower():
                qi += 1
        return qi == len(query)

    def _filter_items(self, query):
        """Filter items by fuzzy search"""
        if not query:
            return self._current_items
        return [i for i in self._current_items
                if not i.get("separator") and self._fuzzy_match(query, i.get("name", ""))]

    def _show_search(self):
        """Show search field"""
        if self._search_frame:
            return

        self._search_frame = tk.Frame(self._frame, bg=self.BG)
        self._search_frame.pack(fill="x", pady=(0, 4), before=self._frame.winfo_children()[0])

        self._search_entry = tk.Entry(
            self._search_frame,
            font=("Segoe UI", 11),
            bg="#2d2d44",
            fg=self.FG,
            insertbackground=self.FG,
            relief="flat",
            width=28
        )
        self._search_entry.pack(fill="x", padx=2)
        self._search_entry.bind("<KeyRelease>", self._on_search_change)
        self._search_entry.bind("<Return>", self._on_search_enter)
        self._search_entry.bind("<Escape>", lambda e: self._hide_search())
        self._search_entry.focus()

    def _hide_search(self):
        """Hide search and restore items"""
        if self._search_frame:
            self._search_frame.destroy()
            self._search_frame = None
            self._search_entry = None
            self._rebuild_items(self._current_items)
            self.win.focus_force()

    def _on_search_change(self, event=None):
        """Handle search text change"""
        if not self._search_entry:
            return
        query = self._search_entry.get().strip()
        filtered_items = self._filter_items(query)
        # Also filter clipboard
        filtered_clips = [c for c in self._current_clips
                         if self._fuzzy_match(query, c)] if query else self._current_clips[:3]
        self._rebuild_items(filtered_items, filtered_clips)

    def _on_search_enter(self, event=None):
        """Launch first item on Enter"""
        if self._item_labels:
            # Find first non-separator
            for lbl in self._item_labels:
                path = lbl._path if hasattr(lbl, "_path") else None
                if path:
                    self._launch(path)
                    return

    def _on_key(self, event):
        """Handle keypress - show search on typing"""
        if event.char and event.char.isalnum() and not self._add_form:
            self._show_search()
            if self._search_entry:
                self._search_entry.insert("end", event.char)

    def _rebuild_items(self, items, clips=None):
        """Rebuild item list and optionally clips"""
        # Clear existing items
        for lbl in self._item_labels:
            lbl.destroy()
        self._item_labels = []

        # Clear existing clips
        for lbl in self._clip_labels:
            lbl.destroy()
        self._clip_labels = []
        if hasattr(self, '_clip_header') and self._clip_header:
            self._clip_header.destroy()
            self._clip_header = None

        # Rebuild items
        for i, item in enumerate(items):
            lbl = self._create_item_label(item, i)
            if lbl:
                self._item_labels.append(lbl)

        # Rebuild clips
        if clips:
            self._clip_header = self._create_section_header("📋 CLIPBOARD")
            for clip_text in clips[:10]:  # Max 10 in search results
                lbl = self._create_clip_item(clip_text)
                if lbl:
                    self._clip_labels.append(lbl)

        # Resize window
        self.win.update_idletasks()
        h = self.win.winfo_reqheight()
        self.win.geometry(f"{self.WIDTH}x{h}")

    # ==================== UI ====================
    def show(self, x, y):
        if self.win or self._closing:
            return

        items = self._load_items()
        mfu = self._get_mfu(MFU_COUNT)
        all_clips = self._load_clips()
        all_clips.reverse()  # Most recent first
        self._current_clips = all_clips
        clips = all_clips[:3]  # Show last 3

        self.win = tk.Toplevel(self.root)
        self.win.overrideredirect(True)
        self.win.attributes("-topmost", True)
        self.win.attributes("-alpha", 0.95)
        self.win.configure(bg=self.BG)

        # Main frame
        self._frame = tk.Frame(self.win, bg=self.BG)
        self._frame.pack(fill="both", expand=True, padx=4, pady=4)

        self._item_labels = []
        self._current_items = items
        idx = 0

        # MFU Section (if any)
        if mfu:
            self._create_section_header("⭐ FREQUENT")
            for item in mfu:
                lbl = self._create_item_label(item, idx, show_count=True)
                if lbl:
                    self._item_labels.append(lbl)
                    idx += 1

        # Pinned Section
        self._create_section_header("📌 PINNED")
        for item in items:
            lbl = self._create_item_label(item, idx)
            if lbl:
                self._item_labels.append(lbl)
                if not item.get("separator"):
                    idx += 1

        # Clipboard Section (if any)
        self._clip_labels = []
        if clips:
            self._clip_header = self._create_section_header("📋 CLIPBOARD")
            for clip_text in clips:
                lbl = self._create_clip_item(clip_text)
                if lbl:
                    self._clip_labels.append(lbl)

        # Add button
        self._create_add_button(self._frame)

        # Size and position
        self.win.update_idletasks()
        height = self.win.winfo_reqheight()
        screen_w = self.root.winfo_screenwidth()
        screen_h = self.root.winfo_screenheight()
        x = min(x, screen_w - self.WIDTH - 10)
        y = min(y, screen_h - height - 40)
        self.win.geometry(f"{self.WIDTH}x{height}+{x}+{y}")

        # Bindings
        self.win.bind("<Escape>", lambda e: self._on_escape())
        self.win.bind("<Key>", self._on_key)
        self.win.focus_force()

        # Click-outside detection
        self._buttons_released = False
        self.win.after(50, self._check_click_outside)

    def _create_section_header(self, text):
        """Create section header"""
        lbl = tk.Label(
            self._frame,
            text=f" {text}",
            font=("Segoe UI", 9),
            bg=self.BG,
            fg=self.SECTION_FG,
            anchor="w",
            pady=2
        )
        lbl.pack(fill="x", pady=(2, 0))
        return lbl

    def _create_item_label(self, item, index, show_count=False):
        """Create single item label"""
        icon = item.get("icon", "▶")
        name = item.get("name", "Unknown")
        path = item.get("path", "")
        is_sep = item.get("separator", False)
        count = item.get("_count", 0)

        if is_sep:
            lbl = tk.Label(
                self._frame,
                text=f"  {name}",
                font=("Segoe UI", 9),
                bg=self.BG,
                fg="#555555",
                anchor="center",
                pady=0,
            )
            lbl.pack(fill="x", pady=0)
            return lbl

        # Build text with optional count
        text = f" {icon}  {name}"
        if show_count and count > 0:
            text += f" ({count})"

        lbl = tk.Label(
            self._frame,
            text=text,
            font=("Segoe UI", 11),
            bg=self.BG,
            fg=self.FG,
            anchor="w",
            padx=4,
            pady=2,
            cursor="hand2",
        )
        lbl.pack(fill="x", pady=1)
        lbl._path = path  # Store path for search

        lbl.bind("<Enter>", lambda e: lbl.configure(bg=self.HOVER))
        lbl.bind("<Leave>", lambda e: lbl.configure(bg=self.BG))
        lbl.bind("<Button-1>", lambda e: self._launch(path))

        if index < 9:
            self.win.bind(str(index + 1), lambda e, p=path: self._launch(p))

        return lbl

    def _create_clip_item(self, text):
        """Create clipboard item"""
        # Truncate long text
        display = text[:40] + "..." if len(text) > 40 else text
        display = display.replace("\n", " ").replace("\r", "")

        lbl = tk.Label(
            self._frame,
            text=f"   {display}",
            font=("Segoe UI", 9),
            bg=self.BG,
            fg="#aaaaaa",
            anchor="w",
            padx=4,
            pady=1,
            cursor="hand2",
        )
        lbl.pack(fill="x", pady=0)

        lbl.bind("<Enter>", lambda e: lbl.configure(bg=self.HOVER))
        lbl.bind("<Leave>", lambda e: lbl.configure(bg=self.BG))
        lbl.bind("<Button-1>", lambda e, t=text: self._paste_clip(t))
        lbl._clip_text = text  # Store for search
        return lbl

    def _create_add_button(self, parent):
        """Create + button at bottom"""
        self._add_btn = tk.Label(
            parent,
            text=" ➕  Add new...",
            font=("Segoe UI", 10),
            bg=self.BG,
            fg="#888888",
            anchor="w",
            padx=4,
            pady=2,
            cursor="hand2",
        )
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

        # Path field
        tk.Label(self._add_form, text="Path:", font=("Segoe UI", 9),
                bg=self.BG, fg="#888888").pack(anchor="w")
        self._path_entry = tk.Entry(self._add_form, font=("Segoe UI", 10),
                                    bg="#2d2d44", fg=self.FG, insertbackground=self.FG,
                                    relief="flat", width=28)
        self._path_entry.pack(fill="x", pady=(0, 2))

        # Name field
        tk.Label(self._add_form, text="Name:", font=("Segoe UI", 9),
                bg=self.BG, fg="#888888").pack(anchor="w")
        self._name_entry = tk.Entry(self._add_form, font=("Segoe UI", 10),
                                    bg="#2d2d44", fg=self.FG, insertbackground=self.FG,
                                    relief="flat", width=28)
        self._name_entry.pack(fill="x", pady=(0, 2))

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
            self._add_btn.pack(fill="x", pady=(4, 0))
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
        if self._search_frame:
            self._hide_search()
        elif self._add_form:
            self._hide_add_form()
        else:
            self.hide()

    def _launch(self, path):
        self._track_usage(path)  # Track before hide
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

        # Start clipboard polling
        self.root.after(1000, self.popup._poll_clipboard)

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
    # Single instance check using Windows mutex
    kernel32 = ctypes.windll.kernel32
    mutex = kernel32.CreateMutexW(None, True, "MouseLauncherMutex")
    if kernel32.GetLastError() == 183:  # ERROR_ALREADY_EXISTS
        import sys
        sys.exit(0)  # Another instance running, exit silently

    MouseLauncher().run()
