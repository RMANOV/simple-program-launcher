# Run: python tests/test_clip_persistence.py — failure-injection test of clipboard/usage persistence, on temp files only.
import errno
import importlib.util
import json
import logging
import sys
import tempfile
from datetime import datetime
from pathlib import Path

SRC = Path(__file__).resolve().parents[1] / "launcher.pyw"
spec = importlib.util.spec_from_loader("launcher_under_test", loader=None)
mod = importlib.util.module_from_spec(spec)
mod.__file__ = str(SRC)
exec(
    compile(SRC.read_text(encoding="utf-8"), str(SRC), "exec"), mod.__dict__
)  # __name__ != "__main__": GUI does not start
root = logging.getLogger()
for h in list(
    root.handlers
):  # never write test errors into the real launcher_errors.log
    root.removeHandler(h)
    h.close()
root.addHandler(logging.NullHandler())

tmp = Path(tempfile.mkdtemp())
mod.CLIP_FILE, mod.CLIP_BACKUP = tmp / "clipboard.json", tmp / "clipboard.json.bak"
mod.USAGE_FILE, mod.USAGE_BACKUP = tmp / "usage.json", tmp / "usage.json.bak"
p = mod.LauncherPopup(None, None)
fails = 0


def check(name, cond, extra=""):
    global fails
    print(("PASS " if cond else "FAIL ") + name + (f" | {extra}" if extra else ""))
    fails += 0 if cond else 1


now = datetime.now().isoformat()
A = [
    {"text": "OODA prompt", "count": 111, "last": now},
    {"text": "b", "count": 4, "last": now},
]
B = A + [{"text": "c", "count": 0, "last": now}]
p._save_clips(A)
check(
    "normal save/readback", [c["text"] for c in p._load_clips()] == ["OODA prompt", "b"]
)
check("first save: no backup yet", not mod.CLIP_BACKUP.exists())
p._save_clips(B)
check(
    "second save: backup = previous version",
    json.loads(mod.CLIP_BACKUP.read_text(encoding="utf-8")) == A,
)
check("second save: main = new version", len(p._load_clips()) == 3)

good_main = mod.CLIP_FILE.read_bytes()
good_bak = mod.CLIP_BACKUP.read_bytes()
real_dump = mod.json.dump


def full_disk(*a, **k):
    raise OSError(errno.ENOSPC, "No space left on device")


mod.json.dump = full_disk
p._save_clips(B + [{"text": "d", "count": 0, "last": now}])
mod.json.dump = real_dump
check("disk full: main intact", mod.CLIP_FILE.read_bytes() == good_main)
check("disk full: backup intact", mod.CLIP_BACKUP.read_bytes() == good_bak)
check("disk full: no .tmp left", not (tmp / "clipboard.json.tmp").exists())

mod.CLIP_FILE.write_text("", encoding="utf-8")  # the 08.09 state: empty main
loaded = p._load_clips()
check(
    "empty/corrupt main: load recovers from backup",
    [c["text"] for c in loaded] == ["OODA prompt", "b"],
    f"{len(loaded)} items",
)
p._save_clips(loaded + [{"text": "e", "count": 0, "last": now}])
check(
    "corrupt main never overwrites good backup",
    mod.CLIP_BACKUP.read_bytes() == good_bak,
)
check(
    "after recovery: counts survive (111 kept)",
    max(c["count"] for c in p._load_clips()) == 111,
)

p._save_usage({"x.exe": {"count": 63, "last": now}})
p._save_usage({"x.exe": {"count": 64, "last": now}})
mod.USAGE_FILE.write_text("", encoding="utf-8")
check(
    "usage: empty main recovers from backup",
    p._load_usage().get("x.exe", {}).get("count") == 63,
)

q = tmp / "old_pattern.json"
q.write_text(json.dumps(A), encoding="utf-8")
mod.json.dump = full_disk
try:
    with open(q, "w", encoding="utf-8") as f:
        mod.json.dump([], f)
except OSError:
    pass
mod.json.dump = real_dump
check(
    "CONTROL: old open('w') pattern leaves 0 bytes on disk full", q.stat().st_size == 0
)
print("ALL PASS" if fails == 0 else f"{fails} FAIL")
sys.exit(1 if fails else 0)
