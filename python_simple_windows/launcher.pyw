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


# Config files (same directory as script)
# Copy config.example.json to config.json and customize
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
        self._current_items = []
        self._item_labels = []
        self._clip_labels = []
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
        """Load clipboard history sorted by usage count"""
        if CLIP_FILE.exists():
            try:
                with open(CLIP_FILE, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    if data and isinstance(data[0], str):
                        return [{"text": t, "count": 0, "last": ""} for t in data]
                    return sorted(data, key=lambda x: (x.get("count", 0), x.get("last", "")), reverse=True)
            except:
                pass
        return []

    def _save_clips(self, clips):
        """Save clipboard history, evicting stale and least-used items"""
        # Time-based decay: count < 3 expires after 1 day, count >= 3 after count days
        now = datetime.now()
        clips = [c for c in clips if not c.get("last") or (
            now - datetime.fromisoformat(c["last"])
        ).days < (1 if c.get("count", 0) < 3 else c.get("count", 0))]
        # Evict least-used oldest when over limit
        while len(clips) > MAX_CLIPS:
            victim = min(clips, key=lambda c: (c.get("count", 0), c.get("last", "")))
            clips.remove(victim)
        try:
            with open(CLIP_FILE, "w", encoding="utf-8") as f:
                json.dump(clips, f, indent=2, ensure_ascii=False)
        except:
            pass

    def _poll_clipboard(self):
        """Poll clipboard for changes"""
        try:
            text = self.root.clipboard_get()
            if text and text != self._last_clip and len(text) < 1000:
                clips = self._load_clips()
                now = datetime.now().isoformat()
                found = False
                for c in clips:
                    if c["text"] == text:
                        c["last"] = now
                        found = True
                        break
                if not found:
                    clips.append({"text": text, "count": 0, "last": now})
                self._save_clips(clips)
                self._last_clip = text
        except tk.TclError:
            pass
        self.root.after(CLIP_POLL_MS, self._poll_clipboard)

    def _track_clip_usage(self, text):
        """Track clipboard paste usage"""
        clips = self._load_clips()
        now = datetime.now().isoformat()
        for c in clips:
            if c["text"] == text:
                c["count"] = c.get("count", 0) + 1
                c["last"] = now
                self._save_clips(clips)
                return

    def _paste_clip(self, text):
        """Paste text to active window"""
        self._track_clip_usage(text)
        self.hide()
        try:
            self.root.clipboard_clear()
            self.root.clipboard_append(text)
            self.root.update()
            time.sleep(0.1)
            user32.keybd_event(0x11, 0, 0, 0)  # Ctrl down
            user32.keybd_event(0x56, 0, 0, 0)  # V down
            user32.keybd_event(0x56, 0, 2, 0)  # V up
            user32.keybd_event(0x11, 0, 2, 0)  # Ctrl up
        except Exception as e:
            print(f"Paste error: {e}")

    # ==================== HELPERS ====================
    def _eval_math(self, text):
        """Try to evaluate text as math expression"""
        try:
            expr = text.strip().replace('x', '*').replace('×', '*').replace('÷', '/')
            expr = expr.replace(',', '.').replace(' ', '')
            if not all(c in '0123456789.+-*/()' for c in expr):
                return None
            if not expr or not any(c.isdigit() for c in expr):
                return None
            result = eval(expr)
            if isinstance(result, (int, float)) and result != float(expr.replace('.', '').replace('-', '') or 0):
                return round(result, 4) if isinstance(result, float) else result
        except:
            pass
        return None

    def _show_tooltip(self, widget, text):
        """Show tooltip near widget"""
        if hasattr(self, '_tooltip') and self._tooltip:
            self._tooltip.destroy()
        display = text[:500] + "..." if len(text) > 500 else text
        self._tooltip = tk.Toplevel(self.win)
        self._tooltip.overrideredirect(True)
        self._tooltip.attributes("-topmost", True)
        lbl = tk.Label(
            self._tooltip, text=display, font=("Segoe UI", 9),
            bg="#ffffcc", fg="#000000", relief="solid", borderwidth=1,
            wraplength=300, justify="left", padx=4, pady=2
        )
        lbl.pack()
        x = widget.winfo_rootx() + widget.winfo_width() + 5
        y = widget.winfo_rooty()
        self._tooltip.geometry(f"+{x}+{y}")

    def _hide_tooltip(self):
        """Hide tooltip"""
        if hasattr(self, '_tooltip') and self._tooltip:
            self._tooltip.destroy()
            self._tooltip = None

    # ==================== UI ====================
    def show(self, x, y):
        if self.win or self._closing:
            return

        items = self._load_items()
        pinned_paths = {i.get("path") for i in items if not i.get("separator")}
        mfu = [m for m in self._get_mfu(MFU_COUNT) if m.get("path") not in pinned_paths]
        all_clips = self._load_clips()  # Already sorted by count
        today = datetime.now().date().isoformat()
        clips = [c for c in all_clips if c.get("count", 0) > 2
                 or c.get("last", "")[:10] == today][:10]

        self.win = tk.Toplevel(self.root)
        self.win.overrideredirect(True)
        self.win.attributes("-topmost", True)
        self.win.attributes("-alpha", 0.95)
        self.win.configure(bg=self.BG)

        self._frame = tk.Frame(self.win, bg=self.BG)
        self._frame.pack(fill="both", expand=True, padx=4, pady=4)

        self._item_labels = []
        self._current_items = items
        idx = 0

        if mfu:
            self._create_section_header("⭐ FREQUENT")
            for item in mfu:
                lbl = self._create_item_label(item, idx, show_count=True)
                if lbl:
                    self._item_labels.append(lbl)
                    idx += 1

        self._create_section_header("📌 PINNED")
        for item in items:
            lbl = self._create_item_label(item, idx)
            if lbl:
                self._item_labels.append(lbl)
                if not item.get("separator"):
                    idx += 1

        self._create_add_button(self._frame)

        self._clip_labels = []
        if clips:
            self._clip_header = self._create_section_header("📋 CLIPBOARD")
            for clip_obj in clips:
                lbl = self._create_clip_item(clip_obj)
                if lbl:
                    self._clip_labels.append(lbl)

        self.win.update_idletasks()
        height = self.win.winfo_reqheight()
        screen_w = self.root.winfo_screenwidth()
        screen_h = self.root.winfo_screenheight()
        x = min(x, screen_w - self.WIDTH - 10)
        y = min(y, screen_h - height - 40)
        self.win.geometry(f"{self.WIDTH}x{height}+{x}+{y}")

        self.win.bind("<Escape>", lambda e: self._on_escape())
        self.win.focus_force()

        self._buttons_released = False
        self.win.after(50, self._check_click_outside)

    def _create_section_header(self, text):
        """Create section header"""
        lbl = tk.Label(
            self._frame, text=f" {text}", font=("Segoe UI", 9),
            bg=self.BG, fg=self.SECTION_FG, anchor="w", pady=2
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
                self._frame, text=f"  {name}", font=("Segoe UI", 9),
                bg=self.BG, fg="#555555", anchor="center", pady=0,
            )
            lbl.pack(fill="x", pady=0)
            return lbl

        text = f" {icon}  {name}"
        if show_count and count > 0:
            text += f" ({count})"

        lbl = tk.Label(
            self._frame, text=text, font=("Segoe UI", 11),
            bg=self.BG, fg=self.FG, anchor="w", padx=4, pady=2, cursor="hand2",
        )
        lbl.pack(fill="x", pady=1)
        lbl._path = path

        lbl.bind("<Enter>", lambda e: lbl.configure(bg=self.HOVER))
        lbl.bind("<Leave>", lambda e: lbl.configure(bg=self.BG))
        lbl.bind("<Button-1>", lambda e: self._launch(path))

        if index < 9:
            self.win.bind(str(index + 1), lambda e, p=path: self._launch(p))

        return lbl

    def _create_clip_item(self, clip_obj):
        """Create clipboard item with usage count and math preview"""
        text = clip_obj.get("text", "")
        count = clip_obj.get("count", 0)
        display = text[:35] + "..." if len(text) > 35 else text
        display = display.replace("\n", " ").replace("\r", "")
        if count > 0:
            display = f"{display} ({count})"
        math_result = self._eval_math(text)
        if math_result is not None:
            display = f"{display} = {math_result}"

        lbl = tk.Label(
            self._frame, text=f"   {display}", font=("Segoe UI", 9),
            bg=self.BG, fg="#aaaaaa", anchor="w", padx=4, pady=1, cursor="hand2",
        )
        lbl.pack(fill="x", pady=0)

        def on_enter(e):
            lbl.configure(bg=self.HOVER)
            if len(text) > 35:
                self._show_tooltip(lbl, text)
        def on_leave(e):
            lbl.configure(bg=self.BG)
            self._hide_tooltip()

        lbl.bind("<Enter>", on_enter)
        lbl.bind("<Leave>", on_leave)
        lbl.bind("<Button-1>", lambda e, t=text: self._paste_clip(t))
        return lbl

    def _create_add_button(self, parent):
        """Create + button at bottom"""
        self._add_btn = tk.Label(
            parent, text=" ➕  Add new...", font=("Segoe UI", 10),
            bg=self.BG, fg="#888888", anchor="w", padx=4, pady=2, cursor="hand2",
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

        tk.Label(self._add_form, text="Path:", font=("Segoe UI", 9),
                bg=self.BG, fg="#888888").pack(anchor="w")
        self._path_entry = tk.Entry(self._add_form, font=("Segoe UI", 10),
                                    bg="#2d2d44", fg=self.FG, insertbackground=self.FG,
                                    relief="flat", width=28)
        self._path_entry.pack(fill="x", pady=(0, 2))

        tk.Label(self._add_form, text="Name:", font=("Segoe UI", 9),
                bg=self.BG, fg="#888888").pack(anchor="w")
        self._name_entry = tk.Entry(self._add_form, font=("Segoe UI", 10),
                                    bg="#2d2d44", fg=self.FG, insertbackground=self.FG,
                                    relief="flat", width=28)
        self._name_entry.pack(fill="x", pady=(0, 2))

        self._path_entry.bind("<Return>", lambda e: self._name_entry.focus())
        self._name_entry.bind("<Return>", lambda e: self._save_new_item())

        self._path_entry.focus()

        self.win.update_idletasks()
        h = self.win.winfo_reqheight()
        self.win.geometry(f"{self.WIDTH}x{h}")

    def _hide_add_form(self):
        """Hide the add form"""
        if self._add_form:
            self._add_form.destroy()
            self._add_form = None
            self._add_btn.pack(fill="x", pady=(4, 0))
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
            name = Path(path).stem

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
        self._track_usage(path)
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

        self.root.after(1000, self.popup._poll_clipboard)

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
    # Single instance check using Windows mutex
    kernel32 = ctypes.windll.kernel32
    mutex = kernel32.CreateMutexW(None, True, "MouseLauncherMutex")
    if kernel32.GetLastError() == 183:  # ERROR_ALREADY_EXISTS
        import sys
        sys.exit(0)

    MouseLauncher().run()
