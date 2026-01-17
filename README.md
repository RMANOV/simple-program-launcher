# Simple Program Launcher

**Lightning-fast program launcher triggered by simultaneous L+R mouse click.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Rust](https://img.shields.io/badge/Rust-1.70+-orange.svg)](https://www.rust-lang.org/)
[![Python](https://img.shields.io/badge/Python-3.8+-blue.svg)](https://www.python.org/)
[![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20Windows%20%7C%20macOS-lightgrey.svg)]()

---

## Why Another Launcher?

| Problem | Solution |
|---------|----------|
| Keyboard shortcuts conflict with apps | **Mouse trigger** - L+R click never conflicts |
| Alt+Tab is slow for 20+ windows | **Instant popup** at cursor position |
| Start menu requires multiple clicks | **One gesture** opens everything |
| Clipboard managers are separate apps | **Built-in clipboard** with 10,000 entry history |

---

## Features

### Core
- **L+R Mouse Trigger** - Press both buttons simultaneously (50ms threshold)
- **Instant Popup** - <50ms latency, appears at cursor
- **Smart Tracking** - Learns your most-used programs (7-day recency weighting)
- **Keyboard Shortcuts** - Press 1-9 to launch instantly

### Clipboard Manager
- **10,000 Entry History** - Never lose copied text again
- **Fuzzy Search** - Type `hlo` to find `hello world`
- **Pin Important Items** - Keep frequently-used snippets accessible
- **Password Detection** - Auto-skips password-like content

### Customization
- **Pin Favorites** - Lock programs/documents to top
- **Custom Shortcuts** - Add commands like Lock/Sleep/Shutdown
- **Hot-Reload Config** - Changes apply without restart
- **Dark Theme** - Easy on the eyes

---

## Performance

```
+------------------+--------+--------+
| Metric           | Target | Actual |
+------------------+--------+--------+
| Memory (idle)    | <10 MB |  ~8 MB |
| CPU (idle)       | <0.1%  | <0.05% |
| Popup latency    | <50 ms |  ~30ms |
| Binary size      |  <5 MB |  ~4 MB |
| Startup time     | <100ms |  ~50ms |
+------------------+--------+--------+
```

---

## Installation

### Linux (Recommended: Rust)

```bash
git clone https://github.com/RMANOV/simple-program-launcher.git
cd simple-program-launcher
./scripts/install_linux.sh
```

### Windows (Python - Zero Dependencies)

```powershell
# Requires Python 3.8+ (tkinter included)
pip install pynput pywin32
.\scripts\install_windows.ps1
```

### macOS

```bash
./scripts/install_macos.sh
# Grant accessibility permissions when prompted
```

---

## Usage

| Action | How |
|--------|-----|
| Open launcher | Press L+R mouse buttons together |
| Launch item | Click or press number key (1-9) |
| Pin item | Click `pin` button |
| Search clipboard | Type in search box |
| Add shortcut | Click `[+ Add Shortcut]` |
| Close | Press `Escape` or click outside |

---

## Architecture

```
simple_program_launcher/
├── crates/
│   ├── core/           # Config, usage tracking, platform APIs
│   │   └── platform/   # Linux: xbel, Windows: Registry, macOS: plist
│   ├── ui/             # egui dark-themed popup
│   └── bin/            # rdev mouse listener + main loop
├── launcher.pyw        # Python/Windows standalone
├── config/             # Default configuration
└── scripts/            # Install scripts (systemd/Registry/launchd)
```

### Technology Stack

| Component | Rust (Linux/macOS) | Python (Windows) |
|-----------|-------------------|------------------|
| GUI | egui + glow | tkinter |
| Mouse Events | rdev | pynput |
| Clipboard | arboard | ctypes/win32 |
| Config | serde_json + notify | json |
| Recent Files | recently-used.xbel | Recent folder |

---

## Configuration

**Location:**
- Linux: `~/.config/launcher/config.json`
- Windows: `%APPDATA%\launcher\config.json`
- macOS: `~/Library/Application Support/launcher/config.json`

```json
{
  "pinned_programs": [
    {"name": "VS Code", "path": "code", "item_type": "program"}
  ],
  "pinned_clipboard": ["frequently used snippet"],
  "shortcuts": [
    {"name": "Lock", "path": "loginctl", "args": ["lock-session"]}
  ],
  "max_clipboard_history": 10000,
  "trigger": {
    "simultaneous_threshold_ms": 50,
    "debounce_ms": 500
  }
}
```

---

## How It Works

```
┌─────────────────────────────────────────────────────────┐
│                    Mouse Event Loop                      │
│  ┌─────────┐    ┌─────────┐    ┌─────────────────────┐  │
│  │ L Click │───►│ Within  │───►│ Trigger! Show Popup │  │
│  └─────────┘    │  50ms?  │    └─────────────────────┘  │
│  ┌─────────┐    └─────────┘                              │
│  │ R Click │───►     │                                   │
│  └─────────┘         │ No                                │
│                      ▼                                   │
│               Reset timer                                │
└─────────────────────────────────────────────────────────┘
```

### Recency-Weighted Scoring

Programs are ranked by usage with exponential decay:

```
Score = Σ 2^(-age_days / 7)
```

A launch today = 1.0 points, a week ago = 0.5, two weeks = 0.25, etc.

---

## Development

```bash
# Build
cargo build --release

# Run with logging
RUST_LOG=info cargo run

# Check for errors
cargo check

# Run tests
cargo test
```

---

## Roadmap

- [x] L+R mouse trigger
- [x] Smart program tracking
- [x] Clipboard history (10K entries)
- [x] Instant clipboard search
- [x] Pin clipboard entries
- [x] Fuzzy search

---

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing`)
5. Open a Pull Request

---

## License

MIT License - Use freely, attribution appreciated.

---

<p align="center">
  <b>Press L+R to launch!</b>
</p>
