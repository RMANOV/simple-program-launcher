# Simple Windows-Only Python Launcher

**Zero-dependency launcher for Windows** - uses Windows API directly via ctypes.

## Requirements

- Python 3.8+ (tkinter included)
- Windows only
- **No pip install needed!**

## Usage

```powershell
# Just run it!
pythonw launcher.pyw

# Or with console output for debugging:
python launcher.pyw
```

## Trigger

Press **L+R mouse buttons simultaneously** to open the popup.

## Features

- **MFU Tracking** - Most Frequently Used items appear at top
- **Clipboard History** - Auto-captures clipboard with usage tracking
- **Math Preview** - Shows `2+2 = 4` for math expressions
- **Inline Add** - Add new items directly from popup
- **Keyboard Shortcuts** - Press 1-9 to launch items

## Files

| File | Description |
|------|-------------|
| `launcher.pyw` | Main launcher script |
| `config.example.json` | Example configuration (copy to `config.json`) |
| `config.json` | Your pinned items (create from example) |
| `usage.json` | Usage statistics (auto-generated) |
| `clipboard.json` | Clipboard history (auto-generated) |

## Configuration

Copy `config.example.json` to `config.json` and edit:

```json
{
  "items": [
    {"name": "Notepad", "path": "notepad.exe", "icon": "📝"},
    {"name": "My App", "path": "C:\\Path\\To\\app.exe", "icon": "🚀"},
    {"name": "─────────", "path": "", "separator": true}
  ]
}
```

## Autostart

To run at Windows startup, create a shortcut to `launcher.pyw` in:
```
%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup
```
