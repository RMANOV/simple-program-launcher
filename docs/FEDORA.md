# Fedora parity: audit prompts and session panes

The Rust launcher remains the recommended Fedora build. The optional scripts
in `scripts/fedora/` reproduce the Windows console behavior that is independent
of Windows Terminal:

- every interactive Bash prompt has a timestamp, author, and `COMMAND` label;
- a `RESULT` marker is printed immediately before command output;
- Claude and Codex use exact UUID state instead of `--last` after the first
  connection;
- repeated resume requests are idempotent, and an active writer is never
  killed or duplicated;
- the two agent slots stay in one fixed four-pane tmux session.

## Install

For a normal Fedora workstation:

```bash
sudo dnf install -y @development-tools rust cargo pkg-config tmux util-linux libxkbcommon-devel
sudo usermod -aG input "$USER"
# Log out and back in after the group change.
./scripts/install_linux.sh
./scripts/fedora/install_session_panes.sh --enable-bash
```

If Cargo reports a missing desktop development library, install the package
named by the error and rerun the build. The existing Linux installer remains
responsible for the Rust binary and its systemd user service.

## Four panes

Create the canonical workspace once:

```bash
~/.config/simple-program-launcher/session_pane.sh prepare
tmux attach -t simple-program-launcher
```

The panes are fixed as `Claude | Codex | Shell | MAIN`. If an existing tmux
session has anything other than one window and four panes, the broker fails
closed instead of appending another tab or pane. State is stored under
`${XDG_STATE_HOME:-$HOME/.local/state}/simple-program-launcher`; clipboard,
launcher usage, and shell history are not copied into the repository.

## Resume and restart

From the launcher or a shell, request a session with:

```bash
~/.config/simple-program-launcher/session_pane.sh request claude
~/.config/simple-program-launcher/session_pane.sh request codex
```

The first request may use the agent's normal `--continue`/`resume --last`
selection when no UUID is known. After that, the latest UUID is retained in
the per-agent state files. To mark an exact restart before leaving a TUI:

```bash
~/.config/simple-program-launcher/session_pane.sh mark-restart claude "$CLAUDE_CODE_SESSION_ID"
~/.config/simple-program-launcher/session_pane.sh mark-restart codex "$CODEX_THREAD_ID"
```

After the TUI exits, its host consumes the marker and resumes the same UUID in
the same pane. A failed resume leaves the marker in place for a later retry.
Use `inspect claude` or `inspect codex` to read only broker state.

## Audit output

New interactive shells show output in this shape:

```text
[2026-08-11 18:20:00] [user] COMMAND $ printf 'hello\n'
[2026-08-11 18:20:00] [user] RESULT
hello
```

The hook refuses to overwrite an unrelated pre-existing Bash `DEBUG` trap;
that preserves other tooling and is reported once so it can be resolved
explicitly. The prompt hook is idempotent and does not touch clipboard data.
