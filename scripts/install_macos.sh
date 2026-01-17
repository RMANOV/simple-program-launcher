#!/bin/bash
# Install script for Simple Program Launcher on macOS
# Sets up the binary and launchd plist for auto-start

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BINARY_NAME="launcher"
INSTALL_DIR="$HOME/.local/bin"
PLIST_DIR="$HOME/Library/LaunchAgents"
CONFIG_DIR="$HOME/Library/Application Support/launcher"
PLIST_NAME="com.rmanov.launcher.plist"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Simple Program Launcher - macOS Installer${NC}"
echo "=========================================="

# Check if running from project directory
if [ ! -f "$PROJECT_DIR/Cargo.toml" ]; then
    echo -e "${RED}Error: Cargo.toml not found. Run this script from the project directory.${NC}"
    exit 1
fi

# Build release binary
echo -e "\n${YELLOW}Building release binary...${NC}"
cd "$PROJECT_DIR"
cargo build --release

# Check if build succeeded
if [ ! -f "$PROJECT_DIR/target/release/$BINARY_NAME" ]; then
    echo -e "${RED}Error: Build failed. Binary not found.${NC}"
    exit 1
fi

# Create install directory
echo -e "\n${YELLOW}Installing binary to $INSTALL_DIR...${NC}"
mkdir -p "$INSTALL_DIR"
cp "$PROJECT_DIR/target/release/$BINARY_NAME" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/$BINARY_NAME"

# Create config directory
echo -e "\n${YELLOW}Setting up configuration...${NC}"
mkdir -p "$CONFIG_DIR"
if [ ! -f "$CONFIG_DIR/config.json" ]; then
    cp "$PROJECT_DIR/config/default_config.json" "$CONFIG_DIR/config.json"
    echo "Created default config at $CONFIG_DIR/config.json"
else
    echo "Config already exists, skipping..."
fi

# Create launchd plist
echo -e "\n${YELLOW}Creating launchd plist...${NC}"
mkdir -p "$PLIST_DIR"

cat > "$PLIST_DIR/$PLIST_NAME" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.rmanov.launcher</string>

    <key>ProgramArguments</key>
    <array>
        <string>$INSTALL_DIR/$BINARY_NAME</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>

    <key>StandardOutPath</key>
    <string>/tmp/launcher.log</string>

    <key>StandardErrorPath</key>
    <string>/tmp/launcher.err</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>RUST_LOG</key>
        <string>info</string>
    </dict>
</dict>
</plist>
EOF

# Load the launch agent
echo -e "\n${YELLOW}Loading launch agent...${NC}"
launchctl unload "$PLIST_DIR/$PLIST_NAME" 2>/dev/null || true
launchctl load "$PLIST_DIR/$PLIST_NAME"

# Note about accessibility permissions
echo -e "\n${YELLOW}IMPORTANT: Accessibility Permissions Required${NC}"
echo "=============================================="
echo "For the launcher to capture mouse events, you need to grant"
echo "accessibility permissions to the binary:"
echo ""
echo "1. Open System Preferences > Security & Privacy > Privacy"
echo "2. Select 'Accessibility' from the left panel"
echo "3. Click the lock to make changes"
echo "4. Add $INSTALL_DIR/$BINARY_NAME to the list"
echo ""

# Print status
echo -e "${GREEN}Installation complete!${NC}"
echo "=========================================="
echo -e "Binary:  ${YELLOW}$INSTALL_DIR/$BINARY_NAME${NC}"
echo -e "Config:  ${YELLOW}$CONFIG_DIR/config.json${NC}"
echo -e "Plist:   ${YELLOW}$PLIST_DIR/$PLIST_NAME${NC}"
echo ""
echo "Useful commands:"
echo "  Start:  launchctl load ~/Library/LaunchAgents/$PLIST_NAME"
echo "  Stop:   launchctl unload ~/Library/LaunchAgents/$PLIST_NAME"
echo "  Logs:   tail -f /tmp/launcher.log"
echo ""
echo -e "${GREEN}Trigger: Press L+R mouse buttons simultaneously!${NC}"
