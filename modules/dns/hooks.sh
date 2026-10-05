#!/usr/bin/env bash
# modules/dns/hooks.sh - NetworkManager DNS servers, revertible (P8.1).
# Sourced INSIDE the runner's hook subshell (lib/runner.sh stage 5); run()
# is called once. The runner provides io_*/run_cmd/run_sudo + FS_* seams and
# has already called state_init in real mode; this hook sources lib/state.sh
# (state_note) and lib/sudo.sh (sudo_detect/run_sudo) itself when the runner
# has not -- lib/sudo.sh is only pre-sourced by the bootstrap outside
# mock-backend runs, and a package-free module normally runs on the mock
# backend. Both are guarded by declare -F on purpose: re-sourcing them
# unconditionally would re-run their top-level `FS_STATE_DIR=""` /
# `FS_RUNNING_AS_ROOT=0` assignments and wipe state the runner had already
# initialized.
#
# What this replaces (prototype scripts/add_google_dns.sh): the prototype
# deleted /etc/resolv.conf, rewrote it with Google DNS and then applied
# `chattr +i` -- making the file immutable so the user could not undo it --
# plus a blind `systemctl restart NetworkManager`. This module never writes
# to /etc and never mentions resolv.conf or chattr in any executable path:
# it changes the NetworkManager connection PROFILE through nmcli, which is
# the supported, reversible way, and reactivation is what makes the new
# values live.
#
# Safety model:
#   - Non-NetworkManager host (no nmcli, or NetworkManager not running) ->
#     graceful skip (io_info, rc0), nothing executed.
#   - Connection selection: FS_DNS_CONNECTION names it explicitly (no probe
#     needed, so it also works in dry-run); otherwise the active connection
#     on the device that carries the DEFAULT ROUTE is selected, which is the
#     one whose DNS actually matters. The loopback connection NetworkManager
#     also reports as activated is never selected. Two or more remaining
#     active connections is AMBIGUOUS and fails closed (io_error, rc1): a
#     destructive module must never guess which connection to break.
#   - The prior properties (ipv4.ignore-auto-dns, ipv4.dns) are recorded in
#     the state notes registry BEFORE the mutation, so a crash, a failed
#     postcondition or a wrong choice always leaves a revert path.
#   - After `nmcli connection modify` the properties are read back and
#     compared (postcondition, the P7.6 rule): --stop is not trusted on its
#     own. Mismatch -> io_error + rc1, and the record is KEPT.
#   - Reactivation (`nmcli connection up`) is best-effort: a failure is a
#     warning carrying the manual command, never fatal, because the profile
#     is already correct and the next reconnect picks it up. The run-layer
#     label therefore carries --stop WITHOUT [DESTROY]: --stop is what makes
#     run_cmd propagate the failure so this hook can warn about it, while the
#     [DESTROY] tag would claim "abort the run" (a lie here) and without
#     either the keep-going default would return 0 for a failed `nmcli` and
#     the warning could never fire -- the P7.6 untrustworthy-rc rule again.
#   - Name resolution is then checked with getent, retried a few times so a
#     still-settling network is not reported as broken. A missing getent is a
#     warning (the change is already made, so verification is skipped);
#     resolution that still FAILS is io_error + rc1, because a broken
#     resolver is exactly what the printed revert instructions are for.
#   - A REVERT whose resolution check fails is also io_error + rc1, and it
#     KEEPS the record: a broken resolver after "your settings are back" is
#     exactly the state the user must be able to retry out of, so the only
#     copy of the prior values is never deleted on a bad outcome.
#   - Never guesses: every probed value is shape-validated (a boolean must be
#     yes/no/empty, every address a dotted quad) and anything unexpected
#     fails closed before any write.
#
# Revert: `FS_DNS_REVERT=1` switches run() to the revert path, restoring the
# exact recorded prior values and removing the record. NOTE the runner's
# module registry: once a module is marked done its hooks are skipped
# ("already completed: dns"), so reverting an ALREADY-APPLIED dns module
# needs the mark dropped first -- the apply path prints both commands
# verbatim, and reverting an unmarked module (or a dry run) works directly.
#
# Dry-run: nothing is ever probed. With FS_DNS_CONNECTION set every command
# is rendered exactly; without it the connection name only exists at run
# time, so the plan lines carry the literal marker RESOLVED-AT-RUN-TIME (the
# P7.6 chrome convention). The name-resolution check is reported in an info
# line, not executed. No record is written.
#
# verify() (A2): the absent-nmcli arm returns lib/verify.sh's
# _VERIFY_HOOK_SKIP rather than 0 or 1. On a host that is not a NetworkManager
# host this hook cannot ask its question at all, so 0 would be the
# "verify() passed" the audit prints and 1 would report a missing OPTIONAL
# tool as a broken install -- the false-PASS and false-FAIL halves of the same
# defect. The remaining arms stay FAIL: an nmcli that answers but reports the
# wrong DNS settings IS a finding, and so is a connection name this module
# cannot use. lib/verify.sh is sourced for the constant under the same
# declare -F guard the other hooks use.
# Bash >= 4.3 safe. No comments inside function bodies by house rule.

_DNS_NOTE_KEY="dns"
_DNS_DEFAULT_SERVERS="8.8.8.8 8.8.4.4"
_DNS_MARKER="RESOLVED-AT-RUN-TIME"

run() {
    local root name=""
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || return 1
    declare -F state_note >/dev/null 2>&1 || source "$root/lib/state.sh"
    declare -F sudo_detect >/dev/null 2>&1 || source "$root/lib/sudo.sh"
    if ! command -v nmcli >/dev/null 2>&1; then
        io_info "dns: nmcli not found (not a NetworkManager host); skipping"
        return 0
    fi
    name="${FS_DNS_CONNECTION:-}"
    if [[ -n "$name" ]]; then
        if ! _dns_ok_connection "$name"; then
            io_error "dns: invalid FS_DNS_CONNECTION: $name"
            return 1
        fi
    elif ((FS_DRY_RUN != 1)); then
        if ! _dns_nm_running; then
            io_info "dns: NetworkManager is not running; skipping"
            return 0
        fi
        name="$(_dns_active_connection)" || return 1
        if [[ -z "$name" ]]; then
            io_info "dns: no active NetworkManager connection; skipping"
            return 0
        fi
        if ! _dns_ok_connection "$name"; then
            io_error "dns: unusable active connection name: $name"
            return 1
        fi
    fi
    if _dns_truthy "${FS_DNS_REVERT:-}"; then
        _dns_revert "$name"
        return $?
    fi
    _dns_apply "$name"
}

verify() {
    local name="" want="" want_csv="" cur="" host="" rc=0
    if ((FS_DRY_RUN == 1)); then
        io_info "dns: verify skipped in dry-run (no probing)"
        return 0
    fi
    if ! command -v nmcli >/dev/null 2>&1; then
        io_info "dns: nmcli not found on PATH; cannot verify"
        declare -F _verify_hook >/dev/null 2>&1 || source "${BASH_SOURCE[0]%/*}/../../lib/verify.sh"
        return "$_VERIFY_HOOK_SKIP"
    fi
    name="${FS_DNS_CONNECTION:-}"
    if [[ -n "$name" ]]; then
        if ! _dns_ok_connection "$name"; then
            io_error "dns: invalid FS_DNS_CONNECTION: $name"
            return 1
        fi
    else
        name="$(_dns_active_connection)" || return 1
        if [[ -z "$name" ]]; then
            io_error "dns: no active NetworkManager connection"
            return 1
        fi
    fi
    want="${FS_DNS_SERVERS:-$_DNS_DEFAULT_SERVERS}"
    if ! _dns_ok_servers "$want"; then
        io_error "dns: invalid DNS server list: $want"
        return 1
    fi
    want_csv="$(_dns_normalize_servers "$want")"
    cur="$(_dns_prop "$name" ipv4.ignore-auto-dns)" || return 1
    if [[ -z "$cur" ]]; then
        cur="no"
    fi
    if [[ "$cur" != yes ]]; then
        io_error "dns: $name still uses automatic DNS (ipv4.ignore-auto-dns=$cur)"
        return 1
    fi
    cur="$(_dns_prop "$name" ipv4.dns)" || return 1
    if [[ "$cur" != "$want_csv" ]]; then
        io_error "dns: $name uses different DNS servers: ${cur:-<none>}"
        return 1
    fi
    host="${FS_DNS_CHECK_HOST:-flathub.org}"
    rc=0
    _dns_resolve "$host" || rc=$?
    if ((rc != 0)); then
        io_error "dns: name resolution failed for $host"
        return 1
    fi
    io_info "dns: verify passed ($name uses $want_csv)"
    return 0
}

_dns_truthy() {
    case "${1:-}" in
    1 | true | TRUE | True | yes | YES | Yes | on | ON | On) return 0 ;;
    esac
    return 1
}

_dns_ok_connection() {
    local name="${1:-}"
    case "$name" in
    "" | -* | *[[:cntrl:]]* | *"|"*) return 1 ;;
    esac
    return 0
}

_dns_ok_ipv4() {
    local ip="${1:-}" a="" b="" c="" d="" extra="" part="" v=0
    local -i i=0
    local -a parts=()
    case "$ip" in
    *[!0-9.]*) return 1 ;;
    esac
    IFS='.' read -r a b c d extra <<<"$ip"
    [[ -n "$a" && -n "$b" && -n "$c" && -n "$d" && -z "${extra:-}" ]] || return 1
    parts=("$a" "$b" "$c" "$d")
    for ((i = 0; i < 4; i++)); do
        part="${parts[i]}"
        ((${#part} <= 3)) || return 1
        v=$((10#$part))
        ((v <= 255)) || return 1
    done
    return 0
}

_dns_normalize_servers() {
    local in="${1:-}" out="" tok="" first=1
    local -a toks=()
    read -r -a toks <<<"$in"
    for tok in ${toks[@]+"${toks[@]}"}; do
        if ((first == 1)); then
            out="$tok"
            first=0
        else
            out="$out,$tok"
        fi
    done
    printf '%s' "$out"
}

_dns_servers_to_words() {
    local in="${1:-}" sp=" "
    printf '%s' "${in//,/$sp}"
}

_dns_ok_servers() {
    local in="${1:-}" tok="" rc=0
    local -a toks=()
    if [[ -z "${in// /}" ]]; then
        return 1
    fi
    read -r -a toks <<<"$in"
    for tok in "${toks[@]}"; do
        if ! _dns_ok_ipv4 "$tok"; then
            rc=1
        fi
    done
    return "$rc"
}

_dns_nm_running() {
    local out=""
    out="$(nmcli -t -f RUNNING general 2>/dev/null)" || return 1
    out="${out//[[:space:]]/}"
    [[ "$out" == running ]]
}

_dns_default_device() {
    local raw="" line="" tok="" prev="" dev=""
    if ! command -v ip >/dev/null 2>&1; then
        return 1
    fi
    raw="$(ip -o route show default 2>/dev/null)" || return 1
    [[ -n "$raw" ]] || return 1
    line="${raw%%$'\n'*}"
    for tok in $line; do
        if [[ "$prev" == dev ]]; then
            dev="$tok"
            break
        fi
        prev="$tok"
    done
    [[ -n "$dev" ]] || return 1
    printf '%s' "$dev"
}

_dns_active_connection() {
    local raw="" line="" name="" device="" state="" rest="" first="" dev="" rc=0
    local -i n=0 i=0
    local -a cname=() cdev=()
    rc=0
    raw="$(nmcli -t -f NAME,DEVICE,STATE connection show --active 2>/dev/null)" || rc=$?
    if ((rc != 0)); then
        io_error "dns: cannot list active NetworkManager connections"
        return 1
    fi
    dev="$(_dns_default_device)" || dev=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -n "$line" ]] || continue
        state="${line##*:}"
        rest="${line%:*}"
        device="${rest##*:}"
        name="${rest%:*}"
        [[ "$state" == activated ]] || continue
        [[ "$device" != lo ]] || continue
        cname+=("${name//\\:/:}")
        cdev+=("${device//\\:/:}")
    done <<<"$raw"
    if ((${#cname[@]} == 0)); then
        return 0
    fi
    if [[ -n "$dev" ]]; then
        n=0
        first=""
        for ((i = 0; i < ${#cname[@]}; i++)); do
            if [[ "${cdev[i]}" == "$dev" ]]; then
                n=$((n + 1))
                if [[ -z "$first" ]]; then
                    first="${cname[i]}"
                fi
            fi
        done
        if ((n == 1)); then
            printf '%s' "$first"
            return 0
        fi
    fi
    if ((${#cname[@]} == 1)); then
        printf '%s' "${cname[0]}"
        return 0
    fi
    io_error "dns: ${#cname[@]} active connections; refusing to guess (set FS_DNS_CONNECTION)"
    return 1
}

_dns_prop() {
    local name="${1:-}" prop="${2:-}" out="" rc=0
    if [[ -z "$name" || -z "$prop" ]]; then
        return 1
    fi
    rc=0
    out="$(nmcli -g "$prop" connection show "$name" 2>/dev/null)" || rc=$?
    if ((rc != 0)); then
        io_error "dns: cannot read $prop of connection: $name"
        return 1
    fi
    out="${out%$'\n'}"
    printf '%s' "$out"
}

_dns_plan_name() {
    if [[ -n "${1:-}" ]]; then
        printf '%s' "$1"
    else
        printf '%s' "$_DNS_MARKER"
    fi
}

_dns_resolve() {
    local host="${1:-}" out="" tmp="" rc=0 attempts=0 max=3
    local -i i=0
    max="${FS_DNS_RESOLVE_ATTEMPTS:-3}"
    case "$max" in
    '' | *[!0-9]*) max=3 ;;
    esac
    ((max >= 1)) || max=1
    ((max <= 5)) || max=5
    if ! command -v getent >/dev/null 2>&1; then
        io_warn "dns: getent not found; skipping the name-resolution check"
        return 0
    fi
    tmp="$(mktemp "${TMPDIR:-/tmp}/fedora-setup-dns.XXXXXX" 2>/dev/null)" || {
        io_error "dns: cannot create temp for the resolution check"
        return 1
    }
    for ((i = 0; i < max; i++)); do
        rc=0
        run_cmd "dns: check name resolution ($host)" --stop -- getent hosts "$host" >"$tmp" 2>/dev/null || rc=$?
        out="$(cat -- "$tmp" 2>/dev/null)" || out=""
        : >"$tmp" 2>/dev/null || :
        attempts=$((attempts + 1))
        if ((rc == 0)) && [[ -n "${out//[[:space:]]/}" ]]; then
            rm -f -- "$tmp" 2>/dev/null || :
            return 0
        fi
        if ((i + 1 < max)); then
            sleep 1
        fi
    done
    rm -f -- "$tmp" 2>/dev/null || :
    return 1
}

_dns_reactivate() {
    local name="$1" rc=0
    if [[ "${FS_DNS_REACTIVATE:-1}" == 0 ]]; then
        return 0
    fi
    rc=0
    run_sudo "dns: reactivate connection" --stop -- nmcli connection up "$name" || rc=$?
    if ((rc != 0)); then
        io_warn "dns: could not reactivate $name; run: nmcli connection up $name"
    fi
    return 0
}

_dns_revert() {
    local name="${1:-}" rec="" recname="" rest="" prior_ignore="" prior_dns=""
    local cur="" host="${FS_DNS_CHECK_HOST:-flathub.org}" rc=0
    if ((FS_DRY_RUN == 1)); then
        run_sudo "dns: restore DNS settings [DESTROY]" -- \
            nmcli connection modify "$(_dns_plan_name "$name")" \
            ipv4.ignore-auto-dns "<recorded>" ipv4.dns "<recorded>"
        io_info "dns: dry-run state is not read, so the recorded values are not shown"
        return 0
    fi
    rc=0
    rec="$(state_note_get "$_DNS_NOTE_KEY")" || rc=$?
    if ((rc != 0)); then
        io_info "dns: no recorded change; nothing to revert"
        return 0
    fi
    if [[ "$rec" != *"|"*"|"* ]]; then
        io_error "dns: malformed dns record: $rec"
        return 1
    fi
    recname="${rec%%|*}"
    rest="${rec#*|}"
    prior_ignore="${rest%%|*}"
    prior_dns="${rest#*|}"
    if ! _dns_ok_connection "$recname"; then
        io_error "dns: invalid connection name in record: $recname"
        return 1
    fi
    if [[ -n "$name" ]]; then
        if [[ "$name" != "$recname" ]]; then
            io_error "dns: revert target mismatch (selected '$name', recorded '$recname')"
            return 1
        fi
    else
        name="$recname"
    fi
    case "$prior_ignore" in
    yes | no) ;;
    *)
        io_error "dns: malformed record ignore-auto-dns: $prior_ignore"
        return 1
        ;;
    esac
    if [[ -n "$prior_dns" ]] && ! _dns_ok_servers "$(_dns_servers_to_words "$prior_dns")"; then
        io_error "dns: malformed record dns list: $prior_dns"
        return 1
    fi
    io_info "dns: reverting $name (ignore-auto-dns=$prior_ignore, dns=${prior_dns:-<none>})"
    if ! sudo_detect; then
        io_error "dns: sudo state unavailable, cannot revert"
        return 1
    fi
    rc=0
    run_sudo "dns: restore DNS settings [DESTROY]" --stop -- \
        nmcli connection modify "$name" ipv4.ignore-auto-dns "$prior_ignore" ipv4.dns "$prior_dns" || rc=$?
    if ((rc != 0)); then
        return 1
    fi
    cur="$(_dns_prop "$name" ipv4.ignore-auto-dns)" || return 1
    if [[ -z "$cur" ]]; then
        cur="no"
    fi
    if [[ "$cur" != "$prior_ignore" ]]; then
        io_error "dns: revert did not take effect (ipv4.ignore-auto-dns=$cur)"
        return 1
    fi
    cur="$(_dns_prop "$name" ipv4.dns)" || return 1
    if [[ "$cur" != "$prior_dns" ]]; then
        io_error "dns: revert did not take effect (ipv4.dns=${cur:-<none>})"
        return 1
    fi
    _dns_reactivate "$name"
    rc=0
    _dns_resolve "$host" || rc=$?
    if ((rc != 0)); then
        io_error "dns: name resolution for $host failed after the revert"
        io_error "dns: the record is kept; retry with FS_DNS_REVERT=1 ./setup install --yes dns"
        return 1
    fi
    state_note_remove "$_DNS_NOTE_KEY" || return 1
    io_info "dns: revert complete ($name)"
    return 0
}

_dns_apply() {
    local name="${1:-}" want="${FS_DNS_SERVERS:-$_DNS_DEFAULT_SERVERS}" want_csv=""
    local prior_ignore="" prior_dns="" cur="" host="${FS_DNS_CHECK_HOST:-flathub.org}" rc=0
    if ! _dns_ok_servers "$want"; then
        io_error "dns: invalid DNS server list: $want"
        return 1
    fi
    if [[ -n "$name" ]] && ! _dns_ok_connection "$name"; then
        io_error "dns: invalid connection name: $name"
        return 1
    fi
    want_csv="$(_dns_normalize_servers "$want")"
    if ((FS_DRY_RUN == 1)); then
        run_sudo "dns: set DNS servers [DESTROY]" -- \
            nmcli connection modify "$(_dns_plan_name "$name")" ipv4.dns "$want_csv" ipv4.ignore-auto-dns yes
        if [[ "${FS_DNS_REACTIVATE:-1}" != 0 ]]; then
            run_sudo "dns: reactivate connection [DESTROY]" -- \
                nmcli connection up "$(_dns_plan_name "$name")"
        fi
        io_info "dns: name-resolution check for $host cannot run in dry-run (no probing)"
        if [[ -z "$name" ]]; then
            io_info "dns: set FS_DNS_CONNECTION to render the exact connection name"
        fi
        return 0
    fi
    prior_ignore="$(_dns_prop "$name" ipv4.ignore-auto-dns)" || return 1
    if [[ -z "$prior_ignore" ]]; then
        prior_ignore="no"
    fi
    case "$prior_ignore" in
    yes | no) ;;
    *)
        io_error "dns: unexpected ipv4.ignore-auto-dns value: $prior_ignore"
        return 1
        ;;
    esac
    prior_dns="$(_dns_prop "$name" ipv4.dns)" || return 1
    if [[ -n "$prior_dns" ]] && ! _dns_ok_servers "$(_dns_servers_to_words "$prior_dns")"; then
        io_error "dns: unexpected ipv4.dns value: $prior_dns"
        return 1
    fi
    if [[ "$prior_ignore" == yes && "$prior_dns" == "$want_csv" ]]; then
        io_info "dns: $name already uses $want_csv; no change"
        return 0
    fi
    io_info "dns: to revert later: rm -f the dns mark, then FS_DNS_REVERT=1 ./setup install --yes dns"
    state_note "$_DNS_NOTE_KEY" "$name|$prior_ignore|$prior_dns" || return 1
    if ! sudo_detect; then
        io_error "dns: sudo state unavailable, cannot change DNS"
        return 1
    fi
    rc=0
    run_sudo "dns: set DNS servers [DESTROY]" --stop -- \
        nmcli connection modify "$name" ipv4.dns "$want_csv" ipv4.ignore-auto-dns yes || rc=$?
    if ((rc != 0)); then
        return 1
    fi
    cur="$(_dns_prop "$name" ipv4.ignore-auto-dns)" || return 1
    if [[ -z "$cur" ]]; then
        cur="no"
    fi
    if [[ "$cur" != yes ]]; then
        io_error "dns: DNS was not applied (ipv4.ignore-auto-dns=$cur)"
        return 1
    fi
    cur="$(_dns_prop "$name" ipv4.dns)" || return 1
    if [[ "$cur" != "$want_csv" ]]; then
        io_error "dns: DNS was not applied (ipv4.dns=${cur:-<none>}, want $want_csv)"
        return 1
    fi
    _dns_reactivate "$name"
    io_info "dns: $name now uses $want_csv (ignore-auto-dns=yes)"
    rc=0
    _dns_resolve "$host" || rc=$?
    if ((rc != 0)); then
        io_error "dns: name resolution for $host failed after the change"
        io_error "dns: revert with FS_DNS_REVERT=1 ./setup install --yes dns"
        return 1
    fi
    io_info "dns: name resolution for $host works"
    return 0
}
