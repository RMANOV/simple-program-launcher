# Memory leak in WatchCursor - automation.FromPoint() objects not disposed

## Description

The `WatchCursor` class has a severe memory leak that causes Python to consume 20+ GB of memory over several hours of operation, eventually crashing the system.

## Environment
- Windows 11 Pro
- Python 3.14
- Windows-MCP v0.5.6
- Claude Desktop

## Root Cause

In `live_inspect/watch_cursor.py`, line 44:

```python
def focus_changed_func(self):
    from FlaUI.Core.Input import Mouse
    with UIAutomation() as automation:
        focus_handler = self.register_focus_changed(automation)
        try:
            while self.is_running.is_set():
                point = Mouse.Position
                automation.FromPoint(point)  # <-- LEAK: AutomationElement not disposed
                sleep(1.0)
        finally:
            self.unregister_focus_changed(automation,focus_handler)
```

The `automation.FromPoint(point)` call returns a FlaUI `AutomationElement` (COM object) every second, but these objects are never explicitly disposed. The pythonnet bridge doesn't properly garbage-collect .NET/COM objects, causing them to accumulate in memory.

## Impact

- Memory grows at ~5-10 MB/second
- After 4 hours: ~20 GB consumed
- System becomes unresponsive
- Services fail with "paging file too small" errors
- Forced restart required

## Evidence from Windows Event Log

```
TimeCreated: 19-Jan-26 18:48:13
Id: 2004
ProviderName: Microsoft-Windows-Resource-Exhaustion-Detector
Message: Windows successfully diagnosed a low virtual memory condition.
  python.exe (4592) consumed 21,661,949,952 bytes (20.2 GB)
```

## Suggested Fix

Option 1: Dispose the AutomationElement explicitly:
```python
while self.is_running.is_set():
    point = Mouse.Position
    element = automation.FromPoint(point)
    if element:
        element.Dispose()  # or use 'del element'
    sleep(1.0)
```

Option 2: Use a context manager or try/finally pattern.

Option 3: Reduce polling frequency (1 second might be too aggressive).

## Workaround

Users can disable the Windows-MCP extension to prevent the leak.
