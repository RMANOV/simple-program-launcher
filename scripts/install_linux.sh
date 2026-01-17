#!/bin/bash
# Install script for Simple Program Launcher on Linux
# Sets up the binary and systemd user service for auto-start

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BINARY_NAME="launcher"
INSTALL_DIR="$HOME/.local/bin"
SERVICE_DIR="$HOME/.config/systemd/user"
CONFIG_DIR="$HOME/.config/launcher"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Simple Program Launcher - Linux Installer${NC}"
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

# Create config directory and copy default config
echo -e "\n${YELLOW}Setting up configuration...${NC}"
mkdir -p "$CONFIG_DIR"
if [ ! -f "$CONFIG_DIR/config.json" ]; then
    cp "$PROJECT_DIR/config/default_config.json" "$CONFIG_DIR/config.json"
    echo "Created default config at $CONFIG_DIR/config.json"
else
    echo "Config already exists, skipping..."
fi

# Create systemd user service
echo -e "\n${YELLOW}Creating systemd user service...${NC}"
mkdir -p "$SERVICE_DIR"

cat > "$SERVICE_DIR/launcher.service" << EOF
[Unit]
Description=Simple Program Launcher
Documentation=https://github.com/rmanov/simple-program-launcher
After=graphical-session.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/$BINARY_NAME
Restart=on-failure
RestartSec=5
Environment=DISPLAY=:0
Environment=RUST_LOG=info

# Resource limits
MemoryMax=50M
CPUQuota=10%

[Install]
WantedBy=default.target
EOF

# Reload systemd and enable service
echo -e "\n${YELLOW}Enabling systemd service...${NC}"
systemctl --user daemon-reload
systemctl --user enable launcher.service

# Ask about starting the service now
echo -e "\n${YELLOW}Do you want to start the launcher now? (y/n)${NC}"
read -r response
if [[ "$response" =~ ^[Yy]$ ]]; then
    systemctl --user start launcher.service
    echo -e "${GREEN}Launcher started!${NC}"
fi

# Print status
echo -e "\n${GREEN}Installation complete!${NC}"
echo "=========================================="
echo -e "Binary:  ${YELLOW}$INSTALL_DIR/$BINARY_NAME${NC}"
echo -e "Config:  ${YELLOW}$CONFIG_DIR/config.json${NC}"
echo -e "Service: ${YELLOW}$SERVICE_DIR/launcher.service${NC}"
echo ""
echo "Useful commands:"
echo "  Start:   systemctl --user start launcher"
echo "  Stop:    systemctl --user stop launcher"
echo "  Status:  systemctl --user status launcher"
echo "  Logs:    journalctl --user -u launcher -f"
echo ""
echo -e "${GREEN}Trigger: Press L+R mouse buttons simultaneously!${NC}"
