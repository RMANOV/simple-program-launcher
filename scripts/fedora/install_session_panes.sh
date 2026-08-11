#!/usr/bin/env bash
# Install the Fedora console audit and tmux session broker for one user.

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TARGET_DIR=${XDG_CONFIG_HOME:-$HOME/.config}/simple-program-launcher
ENABLE_BASH=0

usage() { printf 'Usage: %s [--enable-bash]\n' "$(basename -- "$0")"; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --enable-bash) ENABLE_BASH=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

command -v bash >/dev/null 2>&1 || { echo 'bash is required' >&2; exit 1; }
command -v tmux >/dev/null 2>&1 || {
    echo 'tmux is required: sudo dnf install -y tmux' >&2
    exit 1
}
command -v flock >/dev/null 2>&1 || {
    echo 'flock is required: sudo dnf install -y util-linux' >&2
    exit 1
}

install -Dm644 "$SCRIPT_DIR/console_audit.bash" "$TARGET_DIR/console_audit.bash"
install -Dm755 "$SCRIPT_DIR/session_pane.sh" "$TARGET_DIR/session_pane.sh"

if [[ $ENABLE_BASH -eq 1 ]]; then
    BASHRC=${BASHRC_PATH:-$HOME/.bashrc}
    mkdir -p "$(dirname -- "$BASHRC")"
    marker='# simple-program-launcher Fedora console audit'
    if ! grep -Fqx "$marker" "$BASHRC" 2>/dev/null; then
        {
            printf '\n%s\n' "$marker"
            printf 'source %q\n' "$TARGET_DIR/console_audit.bash"
        } >> "$BASHRC"
    fi
fi

echo "Installed session broker: $TARGET_DIR/session_pane.sh"
echo "State directory: ${XDG_STATE_HOME:-$HOME/.local/state}/simple-program-launcher/session-panes"
if [[ $ENABLE_BASH -eq 0 ]]; then
    echo "To enable audit prompts in future Bash shells: source '$TARGET_DIR/console_audit.bash'"
else
    echo "Bash audit hook enabled in $BASHRC; open a new shell or source it once."
fi
echo "Create the four-pane workspace: $TARGET_DIR/session_pane.sh prepare"
echo "Attach to it: tmux attach -t ${SPL_TMUX_SESSION_NAME:-simple-program-launcher}"
