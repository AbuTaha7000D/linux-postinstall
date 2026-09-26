#!/usr/bin/env bash
# lib/io.sh - leveled logging and UI primitives for fedora-setup.
# Sourced by callers; io_init optionally configures the audit log. A
# configured FS_LOG_FILE is preserved even when appends fail, so callers
# can reliably detect an unusable log path. io_* functions never abort
# the caller under set -e / set -u.

FS_DEBUG="${FS_DEBUG:-0}"
FS_VERBOSE="${FS_VERBOSE:-0}"
FS_NO_COLOR="${FS_NO_COLOR:-0}"
FS_LOG_FILE="${FS_LOG_FILE:-}"
IO_INITIALIZED=0
_IO_LAST_PROGRESS=""

_io_fd_tty() {
    [[ -t "$1" ]]
}

_io_ansi() {
    local name="$1"
    case "$name" in
        red)    printf '%s' $'\033[31m' ;;
        yellow) printf '%s' $'\033[33m' ;;
        green)  printf '%s' $'\033[32m' ;;
        dim)    printf '%s' $'\033[2m' ;;
    esac
}

_io_logline() {
    local msg="$1"
    if [[ -n "$FS_LOG_FILE" ]]; then
        if [[ -e "$FS_LOG_FILE" && ( ! -f "$FS_LOG_FILE" || ! -w "$FS_LOG_FILE" ) ]]; then
            return 0
        fi
        printf '%s\n' "$msg" 2>/dev/null >>"$FS_LOG_FILE" || true
    fi
    return 0
}

_io_log() {
    local fd="$1" level="$2" color="$3" msg="$4"
    local ts col="" rst=""
    printf -v ts '%(%H:%M:%S)T' -1
    _io_logline "[$ts] [$level] $msg"
    if [[ "$level" == "debug" && "$FS_DEBUG" != "1" ]]; then
        return 0
    fi
    if (( FS_NO_COLOR == 0 )) && _io_fd_tty "$fd"; then
        col="$(_io_ansi "$color")"
        rst=$'\033[0m'
    fi
    {
        printf '[%s] %s[%s] %s%s\n' "$ts" "$col" "$level" "$msg" "$rst"
    } >&"$fd" 2>/dev/null || true
}

io_init() {
    _IO_LAST_PROGRESS=""
    local log_ok=1
    if [[ $# -ge 1 && -n "$1" ]]; then
        FS_LOG_FILE="$1"
    fi
    if [[ -n "$FS_LOG_FILE" ]]; then
        local parent="."
        if [[ "$FS_LOG_FILE" == */* ]]; then
            parent="${FS_LOG_FILE%/*}"
            [[ -z "$parent" ]] && parent="/"
        fi
        mkdir -p -- "$parent" 2>/dev/null || log_ok=0
        if [[ -e "$FS_LOG_FILE" && ( ! -f "$FS_LOG_FILE" || ! -w "$FS_LOG_FILE" ) ]]; then
            log_ok=0
        else
            {
                printf '==== fedora-setup log ====\n'
                printf -v ts '%(%Y-%m-%dT%H:%M:%S)T' -1
                printf '[%s] io initialized\n' "$ts"
            } 2>/dev/null >>"$FS_LOG_FILE" || log_ok=0
        fi
        (( log_ok == 1 )) || printf 'warning: log file unusable: %s\n' "$FS_LOG_FILE" >&2 2>/dev/null || true
    fi
    IO_INITIALIZED=1
    return 0
}

io_error() {
    _io_log 2 error red "$*"
}

io_warn() {
    _io_log 2 warn yellow "$*"
}

io_info() {
    _io_log 1 info green "$*"
}

io_debug() {
    _io_log 1 debug dim "$*"
}

io_progress() {
    local cur="${1:-}" total="${2:-}" label="${3:-}" plain=""
    printf -v plain '[%s/%s] %s' "$cur" "$total" "$label"
    if _io_fd_tty 1; then
        printf '\r%s\033[K' "$plain" >&1 2>/dev/null || true
        _IO_LAST_PROGRESS="$plain"
    else
        printf '%s\n' "$plain" >&1 2>/dev/null || true
        _io_logline "$plain"
        _IO_LAST_PROGRESS=""
    fi
}

io_progress_end() {
    if _io_fd_tty 1; then
        printf '\n' >&1 2>/dev/null || true
    fi
    if [[ -n "$_IO_LAST_PROGRESS" ]]; then
        _io_logline "$_IO_LAST_PROGRESS"
        _IO_LAST_PROGRESS=""
    fi
}

io_summary() {
    local title="${1:-}"
    shift 2>/dev/null || true
    {
        printf '== %s ==\n' "$title"
        for line in "$@"; do
            printf '  - %s\n' "$line"
        done
    } >&1 2>/dev/null || true
    _io_logline "== $title =="
    for line in "$@"; do
        _io_logline "  - $line"
    done
}