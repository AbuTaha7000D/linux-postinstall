#!/usr/bin/env bash
# lib/planner.sh - batch planner for fedora-setup.
# Depends on lib/io.sh and lib/pkg.sh; the pkg layer itself requires
# lib/run.sh (backends read bare FS_DRY_RUN, render dry lines via
# run_cmd/run_sudo, audit through FS_LOG_FILE), so callers MUST source
# run.sh before any plan_install. Turns the union of package requests
# from many modules into ONE per-family transaction: dedupe -> diff
# against installed -> single pkg_install_batch. Family-specific
# package-list merging (packages.list + packages.<family>.list
# precedence) is owned by the P4.3 list parsers in lib/modules.sh; this
# planner consumes the already-selected list for the ACTIVE backend, so
# "per-family" falls out of FS_PKG_BACKEND dispatch and dry-run rendering
# is the backend's own single `# would run:` line. Env seams: FS_DRY_RUN
# (numeric; the ${FS_DRY_RUN:-0} default keeps the planner's own read
# set -u-safe -- unset means real mode, no probes skipped -- while the
# pkg layer still needs run.sh for FS_DRY_RUN/FS_LOG_FILE/sudo-policy),
# FS_PKG_BACKEND. No writes, no sudo, no /etc/sudoers. Bash >= 4.3 (no
# namerefs; `declare -A` order keeps first-seen dedupe order).
#
# plan_dedupe  <pkg...>  print unique packages (first-seen order), empty
#                        args skipped, no file access.
# plan_pending <pkg...>  print the subset not installed by the active
#                        backend; under FS_DRY_RUN=1 prints the full
#                        deduped input with NO installed-state probes.
# plan_install <pkg...>  dedupe -> pending -> single pkg_install_batch;
#                        rc 0 when nothing remains or input is empty.

plan_dedupe() {
    declare -A _plan_seen=()
    local _plan_out=()
    local _plan_x
    for _plan_x in "$@"; do
        if [[ -z "$_plan_x" ]]; then
            continue
        fi
        if [[ -n "${_plan_seen[$_plan_x]:-}" ]]; then
            continue
        fi
        _plan_seen[$_plan_x]=1
        _plan_out+=("$_plan_x")
    done
    if (( ${#_plan_out[@]} > 0 )); then
        printf '%s\n' "${_plan_out[@]}"
    fi
}

plan_pending() {
    local -a _plan_pkgs=()
    local _plan_x
    while IFS= read -r _plan_x; do
        _plan_pkgs+=("$_plan_x")
    done < <(plan_dedupe "$@")
    if (( ${#_plan_pkgs[@]} == 0 )); then
        return 0
    fi
    local -a _plan_pending=()
    local _plan_pkg
    for _plan_pkg in "${_plan_pkgs[@]}"; do
        if (( ${FS_DRY_RUN:-0} == 1 )); then
            _plan_pending+=("$_plan_pkg")
            continue
        fi
        if pkg_query_installed "$_plan_pkg"; then
            continue
        fi
        _plan_pending+=("$_plan_pkg")
    done
    if (( ${#_plan_pending[@]} > 0 )); then
        printf '%s\n' "${_plan_pending[@]}"
    fi
}

plan_install() {
    local -a _plan_pending=()
    local _plan_x
    while IFS= read -r _plan_x; do
        _plan_pending+=("$_plan_x")
    done < <(plan_pending "$@")
    if (( ${#_plan_pending[@]} == 0 )); then
        return 0
    fi
    pkg_install_batch "${_plan_pending[@]}"
}