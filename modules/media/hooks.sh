#!/usr/bin/env bash
# modules/media/hooks.sh - media-tools verification (P7.2).
# Sourced INSIDE the runner's hook subshell (lib/runner.sh stage 4); run()
# and verify() are called by the runner / `setup verify` (P9.2).
#
# run() is a documented no-op: installation of this module is the declarative
# system batch (obs-studio per family) + flatpaks.list batch the runner
# already performed at stage 3, so the hook stage has nothing further to do
# and adds no side effects. The function exists only because the module
# contract requires hooks.sh to define run() when the file is present (a
# hooks.sh without run() fails the module).
#
# verify() is the read-only P7.2 diagnostic for the FLATPAK row only: it
# refuses to run in dry-run (verification probes the live flatpak store;
# dry-run never probes -- io_info guard, rc0, nothing executed), then confirms
# every curated id in flatpaks.list is installed. The dry-run and
# flatpak-CLI-presence guards run FIRST -- before resolving the repo path or
# parsing the list -- so a verify still reports its verdict even with a broken
# PATH or no tools. The no-flatpak arm returns lib/verify.sh's
# _VERIFY_HOOK_SKIP, NOT 1: a missing optional tool means this hook checked
# nothing, so 1 would report an audit that never ran as a broken install. The
# contract is sourced there with a parameter-expansion path rather than
# `dirname`+`cd`, because that guard is precisely the arm that must not depend
# on PATH. Presence mirrors the P3.6 backend's flatpak_query_installed
# (per-user probe first, system fallback) as a deliberate hook-local
# duplicate: calling the pkg dispatcher from a hook would resolve the FAMILY
# backend for system rows -- the P5.7 NB-A trap -- so the native obs-studio
# row is deliberately NOT verified here; P9.2's `setup verify` wiring should
# route system rows through the active backend's own query and flatpak rows
# through the backend's query too (replacing this duplicate). Each app reports
# io_info on success or io_error on a missing install; rc1 when anything is
# missing, else io_info "verify passed". verify() never writes.

run() {
    return 0
}

verify() {
    local root="" out="" app="" rc=0 n=0
    if ((FS_DRY_RUN == 1)); then
        io_info "media: verify is read-only; runs only in real mode"
        return 0
    fi
    if ! command -v flatpak >/dev/null 2>&1; then
        declare -F _verify_hook >/dev/null 2>&1 || source "${BASH_SOURCE[0]%/*}/../../lib/verify.sh"
        io_info "media: verify: flatpak CLI not found; cannot verify"
        return "$_VERIFY_HOOK_SKIP"
    fi
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || return 1
    source "$root/lib/lists.sh"
    local -a want=()
    out="$(list_parse "$root/modules/media/flatpaks.list")" || return 1
    if [[ -n "$out" ]]; then
        while IFS= read -r app; do
            want+=("$app")
        done <<<"$out"
    fi
    if ((${#want[@]} == 0)); then
        io_info "media: verify: flatpaks.list empty; nothing to verify"
        return 0
    fi
    for ((n = 0; n < ${#want[@]}; n++)); do
        app="${want[$n]}"
        if flatpak info --user "$app" >/dev/null 2>&1; then
            io_info "media: verify ok: flatpak present: $app"
        elif flatpak info --system "$app" >/dev/null 2>&1; then
            io_info "media: verify ok: flatpak present: $app"
        else
            io_error "media: verify FAILED: flatpak not installed: $app"
            rc=1
        fi
    done
    if ((rc == 0)); then
        io_info "media: verify passed"
    fi
    return "$rc"
}
