#!/usr/bin/env bash
# modules/apps/hooks.sh - desktop-apps verification (P7.1).
# Sourced INSIDE the runner's hook subshell (lib/runner.sh stage 4); run()
# and verify() are called by the runner / `setup verify` (P9.2).
#
# run() is a documented no-op: installation of this module is the
# declarative flatpaks.list batch the runner already performed at stage 3
# (flatpak namespace -> flatpak backend, P5.7 NB-A), so the hook stage has
# nothing further to do and adds no side effects. The function exists only
# because the module contract requires hooks.sh to define run() when the
# file is present (a hooks.sh without run() fails the module).
#
# verify() is the read-only P6.5/P7.1 diagnostic: it refuses to run in
# dry-run (verification probes the live flatpak store; dry-run never
# probes -- io_info guard, rc0, nothing executed), then confirms every
# curated app in flatpaks.list is actually installed. The dry-run and
# flatpak-CLI-presence guards run FIRST -- before resolving the repo path
# or parsing the list -- so a fail-closed verify works even with a broken
# PATH or no tools (and dry-run never has to resolve anything). Presence
# mirrors the P3.6 backend's flatpak_query_installed (per-user probe
# first, system fallback) as a deliberate hook-local duplicate: calling
# the pkg dispatcher from a hook would resolve the FAMILY backend for
# system-package namespace -- the P5.7 NB-A trap -- unless wrapped in an
# FS_PKG_BACKEND=flatpak subshell. The divergence risk is a recorded
# review NB; P9.2's `setup verify` wiring should route flatpak rows
# through the backend's own query instead. Each app reports io_info on
# success or io_error on a missing install; rc1 when anything is missing,
# else io_info "verify passed". verify() never writes.

run() {
    return 0
}

verify() {
    local root="" out="" app="" rc=0 n=0
    if (( FS_DRY_RUN == 1 )); then
        io_info "apps: verify is read-only; runs only in real mode"
        return 0
    fi
    if ! command -v flatpak >/dev/null 2>&1; then
        io_error "apps: verify: flatpak CLI not found; cannot verify"
        return 1
    fi
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || return 1
    source "$root/lib/lists.sh"
    local -a want=()
    out="$(list_parse "$root/modules/apps/flatpaks.list")" || return 1
    if [[ -n "$out" ]]; then
        while IFS= read -r app; do
            want+=("$app")
        done <<<"$out"
    fi
    if (( ${#want[@]} == 0 )); then
        io_info "apps: verify: flatpaks.list empty; nothing to verify"
        return 0
    fi
    for (( n = 0; n < ${#want[@]}; n++ )); do
        app="${want[$n]}"
        if flatpak info --user "$app" >/dev/null 2>&1; then
            io_info "apps: verify ok: flatpak present: $app"
        elif flatpak info --system "$app" >/dev/null 2>&1; then
            io_info "apps: verify ok: flatpak present: $app"
        else
            io_error "apps: verify FAILED: flatpak not installed: $app"
            rc=1
        fi
    done
    if (( rc == 0 )); then
        io_info "apps: verify passed"
    fi
    return "$rc"
}