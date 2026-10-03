#!/usr/bin/env bash
# Timestamped COMMAND/RESULT markers for interactive Bash on Fedora.
# Source this file from ~/.bashrc. It does not read or write clipboard data.

if [[ $- != *i* ]]; then
    return 0 2>/dev/null || exit 0
fi

if [[ ${SPL_CONSOLE_AUDIT_LOADED:-0} == 1 ]] &&
        declare -F __spl_audit_prompt_marker >/dev/null; then
    return 0 2>/dev/null || exit 0
fi
# The guard belongs to this shell, not to subsequently started Bash children.
export -n SPL_CONSOLE_AUDIT_LOADED
SPL_CONSOLE_AUDIT_LOADED=1

__spl_audit_author=${USER:-$(id -un 2>/dev/null || printf 'unknown')}
__spl_audit_base_ps1=${PS1-'\u@\h:\w\$ '}
__SPL_AUDIT_READY=0

__spl_audit_preexec() {
    [[ ${__SPL_AUDIT_READY:-0} == 1 ]] || return 0
    [[ ${__SPL_AUDIT_IN_HOOK:-0} == 1 ]] && return 0
    [[ ${FUNCNAME[1]:-} == __spl_audit_* ]] && return 0
    local command=${BASH_COMMAND:-}
    case "$command" in
        __spl_audit_*|__SPL_AUDIT_IN_HOOK=*|trap\ *DEBUG*|PROMPT_COMMAND*) return 0 ;;
    esac
    [[ -z "$command" ]] && return 0
    __SPL_AUDIT_IN_HOOK=1
    printf '[%s] [%s] RESULT\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$__spl_audit_author"
    __SPL_AUDIT_IN_HOOK=0
}

# Source and function bodies can hide the caller's DEBUG trap. Check at the
# first top-level prompt after sourcing returns, before enabling RESULT markers.
__SPL_AUDIT_DEBUG_CHECKED=0

__spl_audit_restore_status() { return "$1"; }

# Keep existing PROMPT_COMMAND hooks under a guard so their internal commands
# do not produce phantom RESULT markers.
if [[ ${PROMPT_COMMAND:-} != *'__spl_audit_prompt_marker'* ]]; then
    # Array expansion also captures a scalar as one entry, preserving order.
    __spl_audit_existing_prompt_commands=("${PROMPT_COMMAND[@]}")
    __spl_audit_prompt_marker() {
        local rc=${1:-$?} command hook_rc
        hook_rc=$rc
        __SPL_AUDIT_IN_HOOK=1
        for command in "${__spl_audit_existing_prompt_commands[@]}"; do
            if [[ -n $command ]]; then
                __spl_audit_restore_status "$hook_rc"
                eval "$command"
                hook_rc=$?
            fi
        done
        __SPL_AUDIT_READY=1
        __SPL_AUDIT_IN_HOOK=0
        return "$rc"
    }
    unset PROMPT_COMMAND
    PROMPT_COMMAND='__SPL_AUDIT_IN_HOOK=1 __SPL_AUDIT_PROMPT_RC=$?
if [[ ${__SPL_AUDIT_DEBUG_CHECKED:-0} == 0 ]]; then
    __SPL_AUDIT_DEBUG_CHECKED=1
    if [[ -z $(trap -p DEBUG) ]]; then
        trap "__spl_audit_preexec" DEBUG
    else
        printf "[%s] [%s] AUDIT DEBUG trap already present; RESULT hook disabled\n" \
            "$(date "+%Y-%m-%d %H:%M:%S")" "$__spl_audit_author" >&2
    fi
fi
__spl_audit_prompt_marker "$__SPL_AUDIT_PROMPT_RC"'
fi

PS1='[$(date "+%Y-%m-%d %H:%M:%S")] ['"$__spl_audit_author"'] COMMAND '"$__spl_audit_base_ps1"
