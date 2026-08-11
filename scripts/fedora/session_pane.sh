#!/usr/bin/env bash
# Idempotent Claude/Codex session broker for a four-pane tmux workspace.
# State lives below XDG_STATE_HOME, never in the repository.

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SCRIPT_PATH=$SCRIPT_DIR/$(basename -- "${BASH_SOURCE[0]}")
AUDIT_SCRIPT=${SPL_AUDIT_SCRIPT:-$SCRIPT_DIR/console_audit.bash}
STATE_ROOT=${SPL_STATE_ROOT:-${XDG_STATE_HOME:-$HOME/.local/state}/simple-program-launcher/session-panes}
SESSION_NAME=${SPL_TMUX_SESSION_NAME:-simple-program-launcher}
AUTHOR=${USER:-$(id -un 2>/dev/null || printf 'unknown')}

mkdir -p "$STATE_ROOT/restart" "$STATE_ROOT/requests"
umask 077

usage() {
    cat <<'EOF'
Usage:
  session_pane.sh prepare
  session_pane.sh request claude|codex
  session_pane.sh mark-restart claude|codex [UUID]
  session_pane.sh host claude|codex
  session_pane.sh inspect claude|codex
  session_pane.sh self-test
EOF
}

stamp() { date '+%Y-%m-%d %H:%M:%S'; }
log() { printf '[%s] [%s] %s\n' "$(stamp)" "$AUTHOR" "$*"; }

valid_uuid() {
    # Accept UUIDv7 as well as older Claude/Codex UUID formats.
    [[ ${1:-} =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$ ]]
}

valid_agent() { [[ ${1:-} == claude || ${1:-} == codex ]]; }

pane_key() {
    local raw=${TMUX_PANE:-shell-$BASHPID}
    raw=${raw//[^A-Za-z0-9_.-]/_}
    printf '%s' "$raw"
}

state_file() { printf '%s/%s.%s' "$STATE_ROOT" "$1" "$2"; }
request_file() { printf '%s/requests/%s.request' "$STATE_ROOT" "$1"; }
agent_lock() { printf '%s/%s.lock' "$STATE_ROOT" "$1"; }

get_state() {
    local file value=''
    file=$(state_file "$1" "$2")
    if [[ -f "$file" ]]; then
        IFS= read -r value < "$file" || true
        printf '%s' "$value"
    fi
}

set_state() {
    local agent=$1 key=$2 value=${3-} file tmp
    file=$(state_file "$agent" "$key")
    mkdir -p "$(dirname -- "$file")"
    exec 9>"$(agent_lock "$agent")"
    flock -x 9
    tmp=$(mktemp "$STATE_ROOT/.state.XXXXXX")
    printf '%s\n' "$value" > "$tmp"
    mv -f -- "$tmp" "$file"
    exec 9>&-
}

write_atomic() {
    local destination=$1 value=$2 tmp
    mkdir -p "$(dirname -- "$destination")"
    tmp=$(mktemp "$STATE_ROOT/.write.XXXXXX")
    printf '%s\n' "$value" > "$tmp"
    mv -f -- "$tmp" "$destination"
}

tmux_has_session() { tmux has-session -t "$SESSION_NAME" 2>/dev/null; }

layout_ok() {
    tmux_has_session || return 1
    [[ $(tmux list-windows -t "$SESSION_NAME" 2>/dev/null | wc -l) -eq 1 ]] || return 1
    [[ $(tmux list-panes -t "$SESSION_NAME:0" 2>/dev/null | wc -l) -eq 4 ]] || return 1
}

ensure_layout() {
    command -v tmux >/dev/null 2>&1 || { log 'ERROR tmux is required'; return 1; }
    if tmux_has_session; then
        if layout_ok; then
            return 0
        fi
        log 'LAYOUT-DAMAGED existing session is not exactly one window with four panes; refusing to append panes'
        return 20
    fi

    local claude_cmd codex_cmd shell_cmd
    printf -v claude_cmd '%q host claude' "$SCRIPT_PATH"
    printf -v codex_cmd '%q host codex' "$SCRIPT_PATH"
    printf -v shell_cmd 'bash --rcfile %q -i' "$AUDIT_SCRIPT"
    tmux new-session -d -s "$SESSION_NAME" -n quad "$claude_cmd"
    tmux split-window -h -t "$SESSION_NAME:0.0" "$codex_cmd"
    tmux split-window -h -t "$SESSION_NAME:0.0" "$shell_cmd"
    tmux split-window -h -t "$SESSION_NAME:0.0" "$shell_cmd"
    tmux select-layout -t "$SESSION_NAME:0" even-horizontal >/dev/null
    tmux set-option -t "$SESSION_NAME" remain-on-exit on
    log "READY tmux session $SESSION_NAME (Claude | Codex | Shell | MAIN)"
}

select_agent_pane() {
    local agent=$1 index=0
    [[ $agent == codex ]] && index=1
    tmux select-window -t "$SESSION_NAME:0" 2>/dev/null || true
    tmux select-pane -t "$SESSION_NAME:0.$index" 2>/dev/null || true
    if [[ -n ${TMUX:-} ]]; then
        tmux switch-client -t "$SESSION_NAME" 2>/dev/null || true
    else
        log "ATTACH run: tmux attach -t $SESSION_NAME"
    fi
}

host_alive() {
    local pid
    pid=$(get_state "$1" pid || true)
    [[ $pid =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null
}

codex_writer_active() {
    local id=$1 lock="$HOME/.codex/thread-writer-locks/$1.lock"
    [[ -f "$lock" ]] || return 1
    ! flock -n "$lock" -c ':' 2>/dev/null
}

agent_process_active() {
    local agent=$1 id=${2:-}
    if [[ $agent == codex && -n $id ]] && codex_writer_active "$id"; then
        return 0
    fi
    if [[ $agent == claude ]]; then
        pgrep -af '(^|/)claude([[:space:]]|$)' >/dev/null 2>&1
    else
        pgrep -af '(^|/)codex([[:space:]]|$)' >/dev/null 2>&1
    fi
}

latest_session_id() {
    local agent=$1 file id
    if [[ $agent == claude ]]; then
        file=$(find "$HOME/.claude/projects" -type f -name '*.jsonl' -printf '%T@ %p\n' 2>/dev/null |
            sort -nr | head -n1 | cut -d' ' -f2- || true)
        id=$(basename "${file:-}" .jsonl 2>/dev/null || true)
        valid_uuid "$id" && printf '%s' "${id,,}"
    else
        while IFS= read -r file; do
            id=$(grep -oE '"id"[[:space:]]*:[[:space:]]*"[0-9a-fA-F-]{36}"' "$file" 2>/dev/null |
                head -n1 | grep -oE '[0-9a-fA-F-]{36}' || true)
            if valid_uuid "$id"; then
                printf '%s' "${id,,}"
                return 0
            fi
        done < <(find "$HOME/.codex/sessions" -type f -name '*.jsonl' -printf '%T@ %p\n' 2>/dev/null |
            sort -nr | cut -d' ' -f2- | head -n80)
    fi
}

claim_request() {
    local agent=$1 source destination lock
    source=$(request_file "$agent")
    destination="$source.inflight.$BASHPID"
    lock=$(agent_lock "$agent")
    exec 8>"$lock"
    flock -x 8
    if [[ -f "$source" ]]; then
        mv -f -- "$source" "$destination"
        printf '%s' "$destination"
    fi
    exec 8>&-
}

claim_restart() {
    local agent=$1 marker original destination lock id
    marker=$(find "$STATE_ROOT/restart" -maxdepth 1 -type f -name "$agent.*.marker" \
        -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f2- || true)
    [[ -n "$marker" && -f "$marker" ]] || return 1
    original=$marker
    destination="$marker.inflight.$BASHPID"
    lock=$(agent_lock "$agent")
    exec 8>"$lock"
    flock -x 8
    if [[ -f "$original" ]]; then
        mv -f -- "$original" "$destination"
    else
        destination=''
    fi
    exec 8>&-
    [[ -n "$destination" && -f "$destination" ]] || return 1
    id=$(head -n1 "$destination" | tr -d '[:space:]')
    if ! valid_uuid "$id"; then
        rm -f -- "$destination"
        return 1
    fi
    CLAIM_ID=${id,,}
    CLAIM_FILE=$destination
    CLAIM_ORIGINAL=$original
}

run_agent() {
    local agent=$1 id=${2:-} rc=0
    if [[ -n "$id" ]] && agent_process_active "$agent" "$id"; then
        log "ACTIVE $agent session $id already has a writer; no duplicate launch"
        return 73
    fi
    if [[ $agent == claude ]]; then
        command -v claude >/dev/null 2>&1 || { log 'ERROR claude CLI not found'; return 127; }
        if [[ -n "$id" ]]; then claude --resume "$id"; else claude --continue; fi
        rc=$?
    else
        command -v codex >/dev/null 2>&1 || { log 'ERROR codex CLI not found'; return 127; }
        if [[ -n "$id" ]]; then codex resume "$id"; else codex resume --last; fi
        rc=$?
    fi
    return "$rc"
}

host_loop() {
    local agent=$1 request id rc marker
    set_state "$agent" pid "$BASHPID"
    set_state "$agent" status ready
    log "READY $agent host in pane ${TMUX_PANE:-unknown}"
    while :; do
        request=$(claim_request "$agent" || true)
        if [[ -n "$request" && -f "$request" ]]; then
            id=$(head -n1 "$request" | tr -d '[:space:]')
            rm -f -- "$request"
            [[ $id == none ]] && id=''
            set_state "$agent" status starting
            if ! valid_uuid "$id"; then id=$(get_state "$agent" session || true); fi
            if ! valid_uuid "$id"; then id=''; fi
            rc=0
            run_agent "$agent" "$id" || rc=$?
            if [[ $rc -eq 0 && -z "$id" ]]; then
                id=$(latest_session_id "$agent" || true)
                valid_uuid "$id" && set_state "$agent" session "${id,,}"
            fi
            if [[ $rc -eq 73 ]]; then
                set_state "$agent" status external-active
            else
                set_state "$agent" status idle
            fi
            set_state "$agent" last_exit "$rc"
        fi

        marker=''
        CLAIM_ID=''; CLAIM_FILE=''; CLAIM_ORIGINAL=''
        if claim_restart "$agent"; then
            marker=$CLAIM_FILE
            id=$CLAIM_ID
            set_state "$agent" session "$id"
            set_state "$agent" status restarting
            rc=0
            run_agent "$agent" "$id" || rc=$?
            if [[ $rc -eq 0 ]]; then
                rm -f -- "$marker"
            elif [[ -e "$CLAIM_ORIGINAL" ]]; then
                rm -f -- "$marker"
            else
                mv -f -- "$marker" "$CLAIM_ORIGINAL"
            fi
            [[ $rc -ne 0 ]] && set_state "$agent" status resume-failed
            set_state "$agent" last_exit "$rc"
        fi
        sleep 0.25
    done
}

request_agent() {
    local agent=$1 status id request
    valid_agent "$agent" || { usage; return 2; }
    ensure_layout || return $?
    select_agent_pane "$agent"
    status=$(get_state "$agent" status || true)
    case "$status" in
        starting|running|queued|restarting|restart-marked)
            log "NOOP $agent request already $status"; return 0 ;;
    esac
    id=$(get_state "$agent" session || true)
    valid_uuid "$id" || id=$(latest_session_id "$agent" || true)
    if valid_uuid "$id" && agent_process_active "$agent" "$id"; then
        set_state "$agent" session "${id,,}"
        set_state "$agent" status external-active
        log "NOOP $agent session $id already has a writer"
        return 0
    fi
    valid_uuid "$id" || id='none'
    request=$(request_file "$agent")
    write_atomic "$request" "$id"
    [[ $id != none ]] && set_state "$agent" session "${id,,}"
    set_state "$agent" status queued
    log "QUEUED $agent ${id/none/no-known-UUID}"
}

mark_restart() {
    local agent=$1 id=${2:-} marker
    valid_agent "$agent" || { usage; return 2; }
    if [[ -z "$id" ]]; then
        if [[ $agent == claude ]]; then id=${CLAUDE_CODE_SESSION_ID:-}; else id=${CODEX_THREAD_ID:-}; fi
    fi
    valid_uuid "$id" || { log "ERROR valid $agent UUID is required; state unchanged"; return 2; }
    marker="$STATE_ROOT/restart/$agent.$(pane_key).marker"
    write_atomic "$marker" "${id,,}"
    set_state "$agent" session "${id,,}"
    set_state "$agent" status restart-marked
    log "RESTART-MARKED $agent session ${id,,}; exit the TUI and the same UUID will be resumed"
}

inspect_agent() {
    local agent=$1 key value
    valid_agent "$agent" || { usage; return 2; }
    for key in status session pid last_exit; do
        value=$(get_state "$agent" "$key" || true)
        printf '%s=%s\n' "$key" "${value:-}"
    done
    printf 'tmux_session=%s\n' "$SESSION_NAME"
    printf 'state_root=%s\n' "$STATE_ROOT"
}

self_test() {
    local root id
    root=$(mktemp -d)
    id=019fc7be-a1df-7190-b061-c9704b8e3cb6
    printf '%s\n' "$id" > "$root/state"
    valid_uuid "$(cat "$root/state")" || { rm -rf -- "$root"; return 1; }
    rm -rf -- "$root"
    log 'SELFTEST-OK UUID validation and state round-trip'
}

mode=${1:-}
case "$mode" in
    prepare) ensure_layout ;;
    request) request_agent "${2:-}" ;;
    mark-restart) mark_restart "${2:-}" "${3:-}" ;;
    host) valid_agent "${2:-}" && host_loop "$2" || { usage; exit 2; } ;;
    inspect) inspect_agent "${2:-}" ;;
    self-test) self_test ;;
    *) usage; exit 2 ;;
esac
