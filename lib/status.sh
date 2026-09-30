#!/usr/bin/env bash
# lib/status.sh - shared PASS/WARN/FAIL result table (P9.1, reused by P9.2).
# Depends on lib/io.sh (io_summary). Bash >= 4.3 safe ($#-based bounds,
# every array expansion guarded, no namerefs).
#
# WHY THIS EXISTS. `check` (P9.1) and `verify` (P9.2) both have to answer the
# same two questions -- "what is the worst thing that happened?" and "what
# does the process exit with?" -- and both have to make the printed verdict
# and the exit code impossible to disagree. That rule lives here, once.
#
# THE RULE. One source of truth: the worst level recorded decides. Any FAIL ->
# rc1; otherwise rc0, WARNs included. A warning means "degraded but not
# blocking", so folding WARN into a non-zero exit would make the word a lie
# (an offline host must not look like a broken one). status_verdict prints
# the matching sentence and status_rc returns the matching code, and because
# both read the same STATUS_WORST they cannot drift apart.
#
# Levels are ordered integers so the comparison is a plain `>`:
#   STATUS_PASS 0 < STATUS_WARN 1 < STATUS_FAIL 2
# Callers add rows with status_row <level> <name> <detail>; the name is the
# row's subject and the detail is one clause, no trailing period, so the
# rendered table stays aligned and greppable. status_row is total: it always
# returns 0, because a reporting helper must never abort its caller.
#
# A row is a CLAIM, so only a caller that actually checked may write one.
STATUS_PASS=0
STATUS_WARN=1
STATUS_FAIL=2
STATUS_WORST=0
STATUS_ROWS=()

status_label() {
    case "${1:-0}" in
    0) printf 'PASS' ;;
    1) printf 'WARN' ;;
    *) printf 'FAIL' ;;
    esac
}

status_reset() {
    STATUS_WORST=0
    STATUS_ROWS=()
    return 0
}

status_row() {
    local level="${1:-0}" name="${2:-}" detail="${3:-}"
    STATUS_ROWS+=("$(printf '%-4s %s: %s' "$(status_label "$level")" "$name" "$detail")")
    if ((level > STATUS_WORST)); then
        STATUS_WORST=$level
    fi
    return 0
}

# status_verdict <noun> [action] prints the one-line verdict for a table.
# <noun> is the short label for the run ("preflight"), which is deliberately
# NOT always the same string as the table header ("preflight check"), so it
# is passed explicitly rather than derived. [action] is the trailing
# imperative on a FAIL line ("before installing"), so each command can point
# the reader at what to do next.
status_verdict() {
    local noun="${1:-results}" action="${2:-}" tail="fix the FAIL rows above"
    if [[ -n "$action" ]]; then
        tail="$tail $action"
    fi
    if ((STATUS_WORST >= STATUS_FAIL)); then
        printf '%s FAILED: %s' "$noun" "$tail"
    elif ((STATUS_WORST == STATUS_WARN)); then
        printf '%s OK with warnings' "$noun"
    else
        printf '%s OK' "$noun"
    fi
}

status_rc() {
    if ((STATUS_WORST >= STATUS_FAIL)); then
        return 1
    fi
    return 0
}

# status_report <header> [noun] [action] prints the table with the verdict as
# its last line, so the verdict sits in the same block as the rows it
# summarizes. <noun> defaults to <header> when omitted.
status_report() {
    local header="${1:-results}" noun="" verdict=""
    shift 2>/dev/null || true
    noun="${1:-$header}"
    shift 2>/dev/null || true
    verdict="$(status_verdict "$noun" "$@")"
    io_summary "$header" ${STATUS_ROWS[@]+"${STATUS_ROWS[@]}"} "$verdict"
    return 0
}
