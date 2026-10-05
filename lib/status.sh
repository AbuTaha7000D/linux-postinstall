#!/usr/bin/env bash
# lib/status.sh - shared PASS/SKIP/WARN/FAIL result table (P9.1, reused by
# P9.2, SKIPPED added in P11-R A2).
# Depends on lib/io.sh (io_summary). Bash >= 4.3 safe ($#-based bounds,
# every array expansion guarded, no namerefs).
#
# WHY THIS EXISTS. `check` (P9.1) and `verify` (P9.2) both have to answer the
# same two questions -- "what is the worst thing that happened?" and "what
# does the process exit with?" -- and both have to make the printed verdict
# and the exit code impossible to disagree. That rule lives here, once.
#
# THE RULE. One source of truth: the worst level recorded decides. Any FAIL ->
# rc1; otherwise rc0, WARNs and SKIPs included. A warning means "degraded but
# not blocking", so folding WARN into a non-zero exit would make the word a lie
# (an offline host must not look like a broken one); a skip is strictly WEAKER
# than a warning -- nothing was looked at and nothing was found -- so it cannot
# be the one that blocks either. status_verdict prints the matching sentence and
# status_rc returns the matching code, and because both read the same
# STATUS_WORST they cannot drift apart.
#
# EXIT-CODE POLICY, in full (A2), because the order of the levels IS the policy:
#   (a) only PASS and/or SKIP rows          -> rc0
#   (b) any WARN row, with or without SKIPs -> rc0
#   (c) any FAIL row, with or without SKIPs -> rc1
# A skip is therefore never silent even though it never blocks: when the worst
# level is SKIP the verdict names how many checks were not evaluated, so "every
# check that ran passed" and "N of them could not run" are different sentences.
#
# Levels are ordered integers so the comparison is a plain `>`:
#   STATUS_PASS 0 < STATUS_SKIP 1 < STATUS_WARN 2 < STATUS_FAIL 3
# The numbers are internal -- every caller names a STATUS_* constant and none
# hardcodes a literal, which is why inserting SKIP below WARN renumbered WARN
# and FAIL without touching a single row call.
# Callers add rows with status_row <level> <name> <detail>; the name is the
# row's subject and the detail is one clause, no trailing period, so the
# rendered table stays aligned and greppable. status_row is total: it always
# returns 0, because a reporting helper must never abort its caller.
#
# A row is a CLAIM, so only a caller that actually checked may write a PASS one.
# STATUS_SKIP is for the caller that could NOT check: the tool it needs is
# absent, the host is not the kind of host the check describes, or the check
# refused to probe. It is a verdict, not an absence -- it renders, it is
# counted, and the verdict line names it -- and it exists because rendering
# those cases as PASS made an audit that COULD NOT RUN indistinguishable from
# an audit that found everything correct.
#
# The rendered label is the four-character token SKIP, alongside PASS / WARN /
# FAIL, because the verdict column is formatted `%-4s` and a seven-character
# SKIPPED would re-indent every row `check` has ever printed. The word itself
# is spelled out in the verdict line ("N check(s) skipped"), which is what a
# script reads.
STATUS_PASS=0
STATUS_SKIP=1
STATUS_WARN=2
STATUS_FAIL=3
STATUS_WORST=0
STATUS_ROWS=()

status_label() {
    case "${1:-0}" in
    0) printf 'PASS' ;;
    1) printf 'SKIP' ;;
    2) printf 'WARN' ;;
    *) printf 'FAIL' ;;
    esac
}

# _status_skip_count prints how many recorded rows carry the SKIP label. It is
# counted from STATUS_ROWS at render time -- the same array status_report
# prints -- so the number in the verdict sentence and the rows above it are one
# derivation rather than two facts that happen to agree. The label is matched at
# the start of the row, which is unambiguous because status_row's `%-4s` puts a
# four-character token there: a row NAME can never be at offset 0.
_status_skip_count() {
    local row="" n=0
    for row in ${STATUS_ROWS[@]+"${STATUS_ROWS[@]}"}; do
        if [[ "$row" == "SKIP "* ]]; then
            n=$((n + 1))
        fi
    done
    printf '%s' "$n"
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
# the reader at what to do next. The SKIP arm is checked after WARN because
# the arms mirror the severity order, and it is reached only when no row is a
# WARN or a FAIL -- i.e. the table is a mix of PASS and not-evaluated rows.
status_verdict() {
    local noun="${1:-results}" action="${2:-}" tail="fix the FAIL rows above"
    if [[ -n "$action" ]]; then
        tail="$tail $action"
    fi
    if ((STATUS_WORST >= STATUS_FAIL)); then
        printf '%s FAILED: %s' "$noun" "$tail"
    elif ((STATUS_WORST == STATUS_WARN)); then
        printf '%s OK with warnings' "$noun"
    elif ((STATUS_WORST == STATUS_SKIP)); then
        printf '%s OK with %s check(s) skipped' "$noun" "$(_status_skip_count)"
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
