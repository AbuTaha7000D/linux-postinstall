#!/usr/bin/env bash
# lib/pkg/flatpak.sh - flatpak package backend for fedora-setup.
# Depends on lib/io.sh (errors), lib/run.sh (run_cmd). Defines the full
# seven-member backend contract (lib/pkg.sh) as flatpak_<op>, honoured by
# the pkg.sh dispatcher. Prototype-bug fix: a guaranteed Flathub remote-add
# (--if-not-exists) precedes every install transaction so an install never
# aborts for a missing/absent remote; the constant pair FLATPAK_REMOTE_ID
# + FLATPAK_REMOTE_URL is stable and never user-supplied.
# Install scope is always the per-user installation (no sudo; apps live in
# the invoking user's store), kept deterministic for dry-run rendering.
# user/system install detection: query and list probe the user scope first
# and fall back to (or merge) the system scope, so apps installed by another
# user or site-wide are not reported missing. Local bundles and remotes are
# rendered with run_cmd (audit trail, %q dry rendering, dry-run honouring);
# no privileged step, no /etc/sudoers, no file writes outside the flatpak
# store (remote-add writes are registry operations, not fs-level files).
# Dry-run contract: install_batch prints the remote-add-if-not-exists line
# plus ONE install command and touches nothing; real mode filters
# already-installed apps per scope, runs remote-add once and installs the
# remainder in a single transaction (already-installed leftovers never
# reinstall). Every mutator gates on flatpak_supported before any mutation
# (batch/update/local match the family backends; add_repo is a superset).
# install_local checks bundle existence only in real mode:
# dry-run prints the would-run line without a filesystem probe (AGENTS.md
# no-probing). list_installed tolerates a flatpak answering just one scope
# (a failing probe's output is dropped via || true) and returns empty when
# flatpak is absent rather than failing. update_metadata refreshes appstream
# cache (flatpak pulls remote metadata lazily at install; --appstream
# mirrors the family backends' repo-metadata refresh). Bash >= 4.3 safe.

FLATPAK_REMOTE_ID="flathub"
FLATPAK_REMOTE_URL="https://dl.flathub.org/repo/flathub.flatpakrepo"

flatpak_supported() {
    command -v flatpak >/dev/null 2>&1
}

flatpak_query_installed() {
    local app="${1:-}"
    [[ -n "$app" ]] || { io_error "flatpak query requires an app id"; return 1; }
    if flatpak info --user "$app" >/dev/null 2>&1; then
        return 0
    fi
    flatpak info --system "$app" >/dev/null 2>&1
}

flatpak_list_installed() {
    (
        flatpak list --user --app --columns=application 2>/dev/null || true
        flatpak list --system --app --columns=application 2>/dev/null || true
    ) | sort -u
}

flatpak_install_batch() {
    flatpak_supported || return $?
    if (( FS_DRY_RUN == 1 )); then
        run_cmd "flatpak remote-add" "flatpak" "remote-add" "--user" \
            "--if-not-exists" "$FLATPAK_REMOTE_ID" "$FLATPAK_REMOTE_URL"
        run_cmd "flatpak install" "flatpak" "install" "--user" \
            "--noninteractive" "--assumeyes" "$@"
        return 0
    fi
    local missing=()
    local app
    for app in "$@"; do
        if [[ -n "$app" ]] && ! flatpak_query_installed "$app"; then
            missing+=("$app")
        fi
    done
    if (( ${#missing[@]} == 0 )); then
        return 0
    fi
    run_cmd "flatpak remote-add" "flatpak" "remote-add" "--user" \
        "--if-not-exists" "$FLATPAK_REMOTE_ID" "$FLATPAK_REMOTE_URL"
    run_cmd "flatpak install" "flatpak" "install" "--user" \
        "--noninteractive" "--assumeyes" "${missing[@]}"
}

flatpak_update_metadata() {
    flatpak_supported || return $?
    run_cmd "flatpak update appstream" "flatpak" "update" "--appstream"
}

flatpak_install_local() {
    local file="${1:-}"
    [[ -n "$file" ]] || { io_error "flatpak install_local requires a bundle"; return 1; }
    flatpak_supported || return $?
    if (( FS_DRY_RUN == 1 )); then
        run_cmd "flatpak install local" "flatpak" "install" "--user" \
            "--noninteractive" "--assumeyes" "$file"
        return 0
    fi
    [[ -f "$file" ]] || { io_error "local flatpak bundle not found: $file"; return 1; }
    run_cmd "flatpak install local" "flatpak" "install" "--user" \
        "--noninteractive" "--assumeyes" "$file"
}

flatpak_add_repo() {
    local id="${1:-}" url="${2:-}" key="${3:-}"
    [[ -n "$id" ]] || { io_error "flatpak add_repo requires a remote id"; return 1; }
    [[ -n "$url" ]] || { io_error "flatpak add_repo requires a remote url"; return 1; }
    flatpak_supported || return $?
    [[ "$id" =~ ^[A-Za-z0-9._-]+$ ]] || { io_error "invalid flatpak remote id: $id"; return 1; }
    [[ "$url" != *$'\n'* && "$url" != *$'\r'* ]] || { io_error "invalid flatpak remote url: $url"; return 1; }
    local args=("remote-add" "--user" "--if-not-exists" "$id" "$url")
    if [[ -n "$key" ]]; then
        args+=("--gpg-import" "$key")
    fi
    run_cmd "flatpak add repo" "flatpak" "${args[@]}"
}