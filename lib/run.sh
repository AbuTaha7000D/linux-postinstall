#!/usr/bin/env bash
# lib/run.sh - command runner with dry-run/verbose/debug and failure
# policy. Depends on lib/io.sh; lib/sudo.sh policy globals are defaulted
# here so run.sh also works standalone (failing closed when sudo policy
# is absent). Honors FS_DRY_RUN / FS_VERBOSE / FS_DEBUG.
# Logging: lib/io.sh preserves a configured FS_LOG_FILE even when an
# append fails, so an unusable log path is re-validated on every call and
# can never degrade into silent unlogged runs. The required audit file
# must be a regular writable file (e.g. /dev/null and FIFOs are
# unsupported; omit FS_LOG_FILE to disable logging). The log path is
# validated BEFORE any log write, and the log-unusable diagnostics are
# emitted directly to stderr so a broken or special logging path can
# never block a step or poison the audit trail.
# run_cmd/run_sudo proactively fail the step (FS_LOG_INFRA) when the
# configured log is not a regular writable file, because nothing further
# can be audited.
# Failure policy mapping (ROADMAP P2.7): default is keep-going (log the
# failure and continue, returning 0); a per-call --stop selects
# stop-on-error (return 1); a label containing the literal text
# [DESTROY] always forces stop-on-error; a broken or unwritable log file
# always stops the run. Command output is captured with combined
# stdout+stderr and tee'd to the log file while staying live on the
# terminal. Under dry-run NOTHING executes and the only stdout is one
# '# would run:' line per step, with arguments shell-quoted via %q so a
# planned step always renders on a single line. _run_exec is private;
# all callers must guard it with '|| rc=$?'.

FS_DRY_RUN="${FS_DRY_RUN:-0}"
FS_VERBOSE="${FS_VERBOSE:-0}"
FS_DEBUG="${FS_DEBUG:-0}"
FS_LOG_INFRA="${FS_LOG_INFRA:-0}"
FS_RUNNING_AS_ROOT="${FS_RUNNING_AS_ROOT:-0}"
FS_SUDO_AVAILABLE="${FS_SUDO_AVAILABLE:-0}"

_run_render() {
    local a IFS=' '
    local -a parts=()
    for a in "$@"; do
        parts+=("$(printf '%q' "$a")")
    done
    printf '%s\n' "${parts[*]}"
}

_run_err() {
    local ts
    printf -v ts '%(%H:%M:%S)T' -1
    printf '[%s] [error] %s\n' "$ts" "$*" >&2 2>/dev/null || true
}

_run_exec() {
    local logfile="$1"
    shift
    local -a cmd=("$@")
    local -a st=()
    if [[ -n "$logfile" ]]; then
        if [[ ! -f "$logfile" || ! -w "$logfile" ]]; then
            FS_LOG_INFRA=1
            _run_err "log file not usable: $logfile"
            return 1
        fi
        "${cmd[@]}" 2>&1 | tee -a -- "$logfile"
        st=("${PIPESTATUS[@]}")
        if [[ -n "${st[1]:-}" && "${st[1]:-0}" != 0 ]]; then
            FS_LOG_INFRA=1
            _run_err "cannot append command output to log: $logfile"
            return 1
        fi
        return "${st[0]:-0}"
    fi
    "${cmd[@]}" 2>&1 || return $?
    return 0
}

run_cmd() {
    local label="" stop=0 IFS=' '
    local -a cmd=()
    if (( $# == 0 )); then
        io_error "run_cmd requires a label"
        return 1
    fi
    label="$1"
    shift
    if [[ "${1:-}" == "--stop" ]]; then
        stop=1
        shift
    fi
    if [[ "${1:-}" == "--" ]]; then
        shift
    fi
    cmd=("$@")
    if [[ -z "$label" ]]; then
        io_error "run_cmd requires a label"
        return 1
    fi
    if (( ${#cmd[@]} == 0 )); then
        io_error "run_cmd requires a command for '$label'"
        return 1
    fi
    if [[ -z "${cmd[0]}" ]]; then
        io_error "run_cmd requires a non-empty command for '$label'"
        return 1
    fi
    if (( FS_DRY_RUN == 1 )); then
        printf '# would run: %s\n' "$(_run_render "${cmd[@]}")"
        return 0
    fi
    local logfile="${FS_LOG_FILE:-}"
    local rc=0
    FS_LOG_INFRA=0
    if [[ -n "$logfile" && ( ! -f "$logfile" || ! -w "$logfile" ) ]]; then
        FS_LOG_INFRA=1
        _run_err "log file not usable: $logfile"
        return 1
    fi
    if (( FS_VERBOSE == 1 )); then
        io_info "run: $label :: $(_run_render "${cmd[@]}")"
    else
        io_debug "run: $label :: $(_run_render "${cmd[@]}")"
    fi
    _run_exec "$logfile" "${cmd[@]}" || rc=$?
    if (( FS_LOG_INFRA == 1 )); then
        return 1
    fi
    if (( rc == 0 )); then
        io_debug "ok: $label"
        return 0
    fi
    io_error "command failed (rc=$rc): $label :: $(_run_render "${cmd[@]}")"
    if (( stop == 1 )) || [[ "$label" == *\[DESTROY\]* ]]; then
        return 1
    fi
    return 0
}

run_sudo() {
    local label="" stop=0 IFS=' '
    local -a args=()
    if (( $# == 0 )); then
        io_error "run_sudo requires a label"
        return 1
    fi
    label="$1"
    shift
    if [[ "${1:-}" == "--stop" ]]; then
        stop=1
        shift
    fi
    if [[ "${1:-}" == "--" ]]; then
        shift
    fi
    args=("$@")
    if [[ -z "$label" ]]; then
        io_error "run_sudo requires a label"
        return 1
    fi
    if (( ${#args[@]} == 0 )); then
        io_error "run_sudo requires a command for '$label'"
        return 1
    fi
    if [[ -z "${args[0]}" ]]; then
        io_error "run_sudo requires a non-empty command for '$label'"
        return 1
    fi
    if (( FS_DRY_RUN == 1 )); then
        if (( FS_RUNNING_AS_ROOT == 1 )); then
            printf '# would run: %s\n' "$(_run_render "${args[@]}")"
        else
            printf '# would run: %s\n' "$(_run_render sudo "${args[@]}")"
        fi
        return 0
    fi
    local rv=0
    if (( FS_RUNNING_AS_ROOT == 1 )); then
        if (( stop == 1 )); then
            run_cmd "$label" --stop -- "${args[@]}" || rv=$?
        else
            run_cmd "$label" -- "${args[@]}" || rv=$?
        fi
    elif (( FS_SUDO_AVAILABLE != 1 )); then
        io_error "run_sudo: sudo unavailable; cannot escalate: $(_run_render "${args[@]}")"
        return 1
    else
        if (( stop == 1 )); then
            run_cmd "$label" --stop -- sudo -- "${args[@]}" || rv=$?
        else
            run_cmd "$label" -- sudo -- "${args[@]}" || rv=$?
        fi
    fi
    return "$rv"
}
