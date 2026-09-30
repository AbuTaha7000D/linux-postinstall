#!/usr/bin/env bash
# lib/io.sh - leveled logging and UI primitives for fedora-setup.
# Sourced by callers; io_init optionally configures the audit log. A
# configured FS_LOG_FILE is preserved even when appends fail, so callers
# can reliably detect an unusable log path. io_* functions never abort
# the caller under set -e / set -u.
#
# FS_NO_COLOR is normalized to 0 here, so EVERY color gate must compare it
# NUMERICALLY (`(( FS_NO_COLOR == 0 ))`), never with `-z`: a `-z` test is
# false for the string "0", which silently disables color. lib/ui.sh had
# exactly that bug and P8.3 fixed it -- the `[high-risk]` red flag had never
# once rendered. One gate, one comparison, or the flag is dead.
#
# io_alert is the one io_* that goes to STDOUT instead of its level's
# stderr, and is deliberately un-timestamped: it annotates a rendered plan
# (e.g. a dry run) rather than narrating it, so it must interleave with the
# plan lines in order and a timestamp would only blur the alignment. It is
# styled bold+red on a TTY and prints the byte-identical `!! <msg>` text when
# piped, so a piped/fixture assertion never has to know about ANSI. It is
# also audit-logged through _io_logline under the same `!!` prefix.

FS_DEBUG="${FS_DEBUG:-0}"
FS_VERBOSE="${FS_VERBOSE:-0}"
FS_NO_COLOR="${FS_NO_COLOR:-0}"
FS_LOG_FILE="${FS_LOG_FILE:-}"
IO_INITIALIZED=0
_IO_LAST_PROGRESS=""

_io_fd_tty() {
    [[ -t "$1" ]]
}

# The ONE relation for "does a real, writable, non-empty audit trail exist at
# this path", combining the `-f` AND `-w` rule lib/run.sh:56 has always used
# with the non-emptiness a POINTER additionally needs. It is shared deliberately:
# P9.5 first shipped a guard in lib/bootstrap.sh and a pointer in
# lib/summary.sh as two SEPARATE tests of this one property, and they
# disagreed -- the guard accepted a non-empty file this run cannot append to
# (io_init then skips its write and only warns, always returning 0), so the
# summary could name a log holding no part of the run. That is the P9.2 B4
# defect shape: the auditor's comparison relation must BE the writer's.
#
# It is a P9.5 predicate, not run.sh's: run.sh legitimately accepts an EMPTY
# file (it is about to append to it) and additionally RAISES FS_LOG_INFRA,
# which this deliberately does not. Callers must therefore invoke it AFTER
# the run has written something -- _fs_open_run_log calls it after io_init.
_io_log_usable() {
    local path="${1:-}"
    [[ -n "$path" && -f "$path" && -w "$path" && -s "$path" ]]
}

_io_ansi() {
    local name="$1"
    case "$name" in
    red) printf '%s' $'\033[31m' ;;
    yellow) printf '%s' $'\033[33m' ;;
    green) printf '%s' $'\033[32m' ;;
    dim) printf '%s' $'\033[2m' ;;
    bold) printf '%s' $'\033[1m' ;;
    esac
}

_io_logline() {
    local msg="$1"
    if [[ -n "$FS_LOG_FILE" ]]; then
        if [[ -e "$FS_LOG_FILE" && (! -f "$FS_LOG_FILE" || ! -w "$FS_LOG_FILE") ]]; then
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
    if ((FS_NO_COLOR == 0)) && _io_fd_tty "$fd"; then
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
        if [[ -e "$FS_LOG_FILE" && (! -f "$FS_LOG_FILE" || ! -w "$FS_LOG_FILE") ]]; then
            log_ok=0
        else
            {
                printf '==== fedora-setup log ====\n'
                printf -v ts '%(%Y-%m-%dT%H:%M:%S)T' -1
                printf '[%s] io initialized\n' "$ts"
            } 2>/dev/null >>"$FS_LOG_FILE" || log_ok=0
        fi
        ((log_ok == 1)) || printf 'warning: log file unusable: %s\n' "$FS_LOG_FILE" >&2 2>/dev/null || true
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

io_alert() {
    local msg="$*" col="" rst=""
    _io_logline "!! $msg"
    if ((FS_NO_COLOR == 0)) && _io_fd_tty 1; then
        col="$(_io_ansi red)$(_io_ansi bold)"
        rst=$'\033[0m'
    fi
    {
        printf '%s!! %s%s\n' "$col" "$msg" "$rst"
    } >&1 2>/dev/null || true
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
