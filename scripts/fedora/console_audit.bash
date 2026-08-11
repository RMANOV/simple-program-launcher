#!/usr/bin/env bash
# Timestamped COMMAND/RESULT markers for interactive Bash on Fedora.
# Source this file from ~/.bashrc. It does not read or write clipboard data.

if [[ ${SPL_CONSOLE_AUDIT_LOADED:-0} == 1 ]]; then
    return 0 2>/dev/null || exit 0
fi
export SPL_CONSOLE_AUDIT_LOADED=1

if [[ $- != *i* ]]; then
    return 0 2>/dev/null || exit 0
fi

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

# A pre-existing DEBUG trap may belong to another tool. Do not overwrite it;
# the prompt remains timestamped and RESULT markers are disabled fail-safe.
if [[ -z $(trap -p DEBUG) ]]; then
    trap '__spl_audit_preexec' DEBUG
else
    printf '[%s] [%s] AUDIT DEBUG trap already present; RESULT hook disabled\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$__spl_audit_author" >&2
fi

# Keep existing PROMPT_COMMAND hooks under a guard so their internal commands
# do not produce phantom RESULT markers.
if [[ ${PROMPT_COMMAND:-} != *'__spl_audit_prompt_marker'* ]]; then
    __spl_audit_existing_prompt_command=${PROMPT_COMMAND:-}
    __spl_audit_prompt_marker() {
        local rc=$?
        __SPL_AUDIT_IN_HOOK=1
        if [[ -n ${__spl_audit_existing_prompt_command:-} ]]; then
            eval "$__spl_audit_existing_prompt_command"
        fi
        __SPL_AUDIT_READY=1
        __SPL_AUDIT_IN_HOOK=0
        return "$rc"
    }
    PROMPT_COMMAND='__spl_audit_prompt_marker'
fi

PS1='[$(date "+%Y-%m-%d %H:%M:%S")] ['"$__spl_audit_author"'] COMMAND '"$__spl_audit_base_ps1"
