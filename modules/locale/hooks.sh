#!/usr/bin/env bash
# modules/locale/hooks.sh - opt-in system locale change via localectl (P8.2).
# Sourced INSIDE the runner's hook subshell (lib/runner.sh stage 5); run()
# is called once. The runner provides io_*/run_cmd/run_sudo + FS_* seams and
# has already called state_init in real mode; this hook sources the libs it
# needs (state notes, backups, sudo) itself when the runner has not, guarded
# by declare -F -- re-sourcing unconditionally would re-run top-level
# `FS_STATE_DIR=""` / `FS_RUNNING_AS_ROOT=0` assignments and wipe state the
# runner had already initialized.
#
# What this replaces (prototype scripts/change_language.sh): the prototype
# overwrote /etc/locale.conf with `sudo tee` after a single un-timestamped
# `cp .bak` (so a second run silently clobbered the first backup), ran
# `update-locale` opportunistically, then `source`d /etc/locale.conf into its
# own shell -- a shell-local side effect that changes nothing system-wide and
# exits with the script. It also wrote LC_ALL alongside LANG, which is the
# recommended way to *override* every category rather than pick a language.
# This module uses the supported interface only:
#   - `localectl set-locale LANG=<locale>` on a systemd host, and
#   - `localectl status` to read the result back,
# never a raw file rewrite and never `source`. The backup is taken with the
# existing fs_backup/state_backup_add registry (timestamped, so a repeat run
# never clobbers an earlier backup), and the prior LANG value is recorded in
# the state notes registry so the revert restores the exact previous value.
#
# Safety model:
#   - Not a systemd host (no `localectl`) -> graceful skip (io_info, rc0),
#     nothing executed. The task text is explicit: skip with a clear message
#     rather than rewrite the file behind systemd's back.
#   - LANG is the ONLY variable set. LC_ALL is deliberately NOT written: it
#     overrides every category regardless of the others and is a debugging
#     tool, not a language choice. Any other LC_* category the user wants is
#     their call, not this module's.
#   - The locale must be one the system can actually provide. `localectl
#     list-locales` is consulted when available and an unknown locale fails
#     closed BEFORE any backup or write; when it cannot be consulted, the
#     value is still shape-validated and the postcondition (readback) decides.
#   - A timestamped backup of /etc/locale.conf is taken with the existing
#     fs_backup + state_backup_add registry BEFORE the mutation (the
#     prototype's single un-timestamped `cp .bak` was clobbered by the next
#     run, so it was not a backup at all). A failed backup is fatal: the
#     change is refused rather than made un-revertible. A missing
#     /etc/locale.conf is not an error -- there is nothing to preserve, and
#     the revert record still holds the prior LANG.
#   - The prior LANG is recorded in the state notes registry BEFORE the
#     mutation, so a crash, a failed postcondition or a wrong choice always
#     leaves a revert path.
#   - After `localectl set-locale` the value is read back with `localectl
#     status` and compared (postcondition, the P7.6 rule): --stop is not
#     trusted on its own. Mismatch -> io_error + rc1, record KEPT.
#   - Never guesses: the requested locale is shape-validated (no whitespace,
#     no control characters, no quotes, no `=`), the probed prior value is
#     shape-validated, and anything unexpected fails closed before any write.
#
# Revert: `FS_LOCALE_REVERT=1` switches run() to the revert path, restoring
# the exact recorded prior LANG through the same localectl seam and only then
# removing the record. NOTE the runner's module registry: once a module is
# marked done its hooks are skipped ("already completed: locale"), so
# reverting an ALREADY-APPLIED locale module needs the mark dropped first --
# the apply path prints both commands verbatim, and reverting an unmarked
# module (or a dry run) works directly.
#
# Dry-run: nothing is ever probed and no backup is taken. The `localectl
# set-locale` line is rendered exactly; the readback check is reported in an
# info line, not executed. The value check and the dry-run branch come
# BEFORE the `localectl list-locales` check on purpose -- a dry run must not
# execute a single real command, and `list-locales` is a real command.
# No record is written and no backup file is created.
# Bash >= 4.3 safe. No comments inside function bodies by house rule.

_LOCALE_NOTE_KEY="locale"
_LOCALE_DEFAULT_LOCALE="en_US.UTF-8"

_locale_ok_value() {
    local v="${1:-}"
    [[ -n "$v" ]] || return 1
    case "$v" in
        *[[:space:]]* | *[\"\'\\]* | *"="* | *[[:cntrl:]]*) return 1 ;;
    esac
    return 0
}

_locale_current() {
    local raw="" line="" rc=0
    rc=0
    raw="$(localectl status 2>/dev/null)" || rc=$?
    if (( rc != 0 )); then
        return 1
    fi
    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            *"System Locale:"*)
                line="${line#*System Locale:}"
                line="${line#"${line%%[![:space:]]*}"}"
                line="${line%"${line##*[![:space:]]}"}"
                line="${line#LANG=}"
                line="${line#\"}"
                line="${line%\"}"
                if [[ -z "$line" ]]; then
                    return 0
                fi
                if ! _locale_ok_value "$line"; then
                    return 1
                fi
                printf '%s' "$line"
                return 0
                ;;
        esac
    done <<<"$raw"
    return 0
}

_locale_known() {
    local want="$1" raw="" rc=0
    if ! command -v localectl >/dev/null 2>&1; then
        return 0
    fi
    rc=0
    raw="$(localectl list-locales 2>/dev/null)" || rc=$?
    if (( rc != 0 )); then
        return 0
    fi
    if printf '%s\n' "$raw" | grep -qxF "$want"; then
        return 0
    fi
    return 1
}

_locale_revert() {
    local rec="" prior="" cur="" rc=0
    if (( FS_DRY_RUN == 1 )); then
        run_sudo "locale: restore previous LANG [DESTROY]" -- \
            localectl set-locale "LANG=<recorded>"
        io_info "locale: dry-run state is not read, so the recorded value is not shown"
        return 0
    fi
    rc=0
    rec="$(state_note_get "$_LOCALE_NOTE_KEY")" || rc=$?
    if (( rc != 0 )); then
        io_info "locale: no recorded change; nothing to revert"
        return 0
    fi
    if [[ -z "$rec" ]]; then
        io_error "locale: empty locale record"
        return 1
    fi
    prior="$rec"
    if ! _locale_ok_value "$prior"; then
        io_error "locale: invalid locale in record: $prior"
        return 1
    fi
    io_info "locale: reverting LANG to $prior"
    if ! sudo_detect; then
        io_error "locale: sudo state unavailable, cannot revert"
        return 1
    fi
    rc=0
    run_sudo "locale: restore previous LANG [DESTROY]" --stop -- \
        localectl set-locale "LANG=$prior" || rc=$?
    if (( rc != 0 )); then
        return 1
    fi
    cur="$(_locale_current)" || {
        io_error "locale: cannot read the current LANG"
        return 1
    }
    if [[ "$cur" != "$prior" ]]; then
        io_error "locale: revert did not take effect (LANG=${cur:-<none>})"
        return 1
    fi
    state_note_remove "$_LOCALE_NOTE_KEY" || return 1
    io_info "locale: revert complete (LANG=$prior)"
    return 0
}

_locale_apply() {
    local want="${1:-}" prior="" cur="" bkp="" rc=0
    if ! _locale_ok_value "$want"; then
        io_error "locale: invalid locale value: $want"
        return 1
    fi
    if (( FS_DRY_RUN == 1 )); then
        run_sudo "locale: set system LANG [DESTROY]" -- \
            localectl set-locale "LANG=$want"
        io_info "locale: the readback check cannot run in dry-run (no probing)"
        return 0
    fi
    if ! _locale_known "$want"; then
        io_error "locale: locale not available on this system: $want"
        io_error "locale: generate it first (locale-gen on most distros)"
        return 1
    fi
    prior="$(_locale_current)" || {
        io_error "locale: cannot read the current LANG"
        return 1
    }
    if [[ "$prior" == "$want" ]]; then
        io_info "locale: LANG is already $want; no change"
        return 0
    fi
    if [[ -f "${FS_LOCALE_CONF:-/etc/locale.conf}" ]]; then
        bkp="$(fs_backup "${FS_LOCALE_CONF:-/etc/locale.conf}")" || {
            io_error "locale: refusing to change LANG without a backup of ${FS_LOCALE_CONF:-/etc/locale.conf}"
            return 1
        }
        io_info "locale: backed up ${FS_LOCALE_CONF:-/etc/locale.conf} to $bkp"
    fi
    state_note "$_LOCALE_NOTE_KEY" "$prior" || return 1
    if ! sudo_detect; then
        io_error "locale: sudo state unavailable, cannot change the locale"
        return 1
    fi
    rc=0
    run_sudo "locale: set system LANG [DESTROY]" --stop -- \
        localectl set-locale "LANG=$want" || rc=$?
    if (( rc != 0 )); then
        return 1
    fi
    cur="$(_locale_current)" || {
        io_error "locale: cannot read back LANG after the change"
        return 1
    }
    if [[ "$cur" != "$want" ]]; then
        io_error "locale: LANG was not applied (LANG=${cur:-<none>}, want $want)"
        return 1
    fi
    io_info "locale: system LANG is now $want"
    io_info "locale: to revert: drop the module mark, then FS_LOCALE_REVERT=1 ./setup install --yes locale"
    return 0
}

run() {
    local root
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || return 1
    declare -F io_error >/dev/null 2>&1 || source "$root/lib/io.sh"
    declare -F run_cmd >/dev/null 2>&1 || source "$root/lib/run.sh"
    declare -F state_note >/dev/null 2>&1 || source "$root/lib/state.sh"
    declare -F fs_backup >/dev/null 2>&1 || source "$root/lib/fs.sh"
    declare -F sudo_detect >/dev/null 2>&1 || source "$root/lib/sudo.sh"
    if ! command -v localectl >/dev/null 2>&1; then
        io_info "locale: localectl not found (not a systemd host); skipping"
        return 0
    fi
    if [[ "${FS_LOCALE_REVERT:-0}" == 1 ]]; then
        _locale_revert
        return $?
    fi
    _locale_apply "${FS_LOCALE:-$_LOCALE_DEFAULT_LOCALE}"
}

verify() {
    local want="${1:-}" cur="" root
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || return 1
    declare -F io_error >/dev/null 2>&1 || source "$root/lib/io.sh"
    if (( FS_DRY_RUN == 1 )); then
        io_info "locale: verify skipped in dry-run (no probing)"
        return 0
    fi
    if ! command -v localectl >/dev/null 2>&1; then
        io_info "locale: localectl not found; cannot verify"
        return 0
    fi
    want="${FS_LOCALE:-$_LOCALE_DEFAULT_LOCALE}"
    if ! _locale_ok_value "$want"; then
        io_error "locale: invalid locale value: $want"
        return 1
    fi
    cur="$(_locale_current)" || {
        io_error "locale: cannot read the current LANG"
        return 1
    }
    if [[ "$cur" != "$want" ]]; then
        io_error "locale: LANG is ${cur:-<none>}, expected $want"
        return 1
    fi
    io_info "locale: verify passed (LANG=$want)"
    return 0
}
