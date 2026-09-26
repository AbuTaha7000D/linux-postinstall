#!/usr/bin/env bash
# lib/pkg/arch.sh - Arch package backend for fedora-setup.
# Loaded only through lib/pkg.sh (dispatcher). Depends on lib/io.sh and the
# runner (lib/run.sh run_sudo) for dry-run/audit semantics; policy globals
# FS_RUNNING_AS_ROOT / FS_SUDO_AVAILABLE come from lib/sudo.sh defaults in
# lib/run.sh (failing closed when the policy is absent).
# Capability requires pacman in PATH. Queries use `pacman -Q` (rc0 when
# installed, rc1 otherwise, no other output) and `pacman -Qq` for the
# installed package names, one per line. Mutations route through run_sudo:
# batch install is a SINGLE `pacman -S --noconfirm --needed` transaction
# after filtering out already-installed packages in real mode (--needed keeps
# the skip native); dry-run skips the filter and emits one "# would run:"
# line per call (no queries, no writes). Metadata refresh is `pacman -Sy`;
# local install is `pacman -U --noconfirm <file>`. Repository include files
# are added IF-NOT-EXISTS (never overwritten) under
# ${FS_ARCH_REPO_DIR:-/etc/pacman.d} via atomic `install -m 0644 <tmp>
# <dest>`; the file is named `<id>.conf` with `[<id>]` + `Server = <url>`
# and, when a key is given, a `SigLevel = <key>` line. AUR is strictly
# OPT-IN: arch_aur_helper only DISCOVERS an existing paru/yay in PATH and
# never installs one; arch_aur_batch installs AUR packages through that
# helper in a single transaction and refuses clearly when no helper exists.
# Never edits /etc/sudoers. Bash >= 4.3 safe.

arch_supported() {
    if command -v pacman >/dev/null 2>&1; then
        return 0
    fi
    io_error "arch backend unusable: need pacman in PATH"
    return 1
}

arch_query_installed() {
    local pkg="${1:-}"
    if [[ -z "$pkg" ]]; then
        io_error "query_installed requires a package name"
        return 1
    fi
    pacman -Q "$pkg" >/dev/null 2>&1
}

arch_list_installed() {
    pacman -Qq 2>/dev/null
}

arch_install_batch() {
    arch_supported || return $?
    if (( FS_DRY_RUN == 1 )); then
        run_sudo "install packages ($#)" -- pacman -S --noconfirm --needed "$@"
        return 0
    fi
    local list=() pkg
    for pkg in "$@"; do
        if ! arch_query_installed "$pkg"; then
            list+=("$pkg")
        fi
    done
    if (( ${#list[@]} == 0 )); then
        io_info "all packages already installed"
        return 0
    fi
    run_sudo "install packages (${#list[@]})" -- pacman -S --noconfirm --needed "${list[@]}"
}

arch_update_metadata() {
    arch_supported || return $?
    run_sudo "refresh arch metadata" -- pacman -Sy
}

arch_install_local() {
    local file="${1:-}"
    if [[ -z "$file" ]]; then
        io_error "install_local requires a package file"
        return 1
    fi
    if [[ ! -f "$file" ]]; then
        io_error "local package file not found: $file"
        return 1
    fi
    arch_supported || return $?
    run_sudo "install local package" -- pacman -U --noconfirm "$file"
}

arch_add_repo() {
    local id="${1:-}" url="${2:-}" key="${3:-}"
    if [[ -z "$id" || "$id" == */* || "$id" == *$'\n'* || "$id" == "." || "$id" == ".." ]]; then
        io_error "refusing invalid repo id: $id"
        return 1
    fi
    if [[ -z "$url" || "$url" == *$'\n'* ]]; then
        io_error "add_repo requires a repo url"
        return 1
    fi
    local base="${FS_ARCH_REPO_DIR:-/etc/pacman.d}"
    local dest="$base/$id.conf" content tmp rv=0
    if [[ -e "$dest" ]]; then
        io_debug "repo exists, skipping: $dest"
        return 0
    fi
    printf -v content '[%s]\nServer = %s\n' "$id" "$url"
    if [[ -n "$key" ]]; then
        content+="SigLevel = ${key}"$'\n'
    fi
    if (( FS_DRY_RUN == 1 )); then
        run_sudo "add repo $id" -- install -m 0644 \
            "${TMPDIR:-/tmp}/fedora-setup-repo-$id.dry" "$dest"
        return 0
    fi
    tmp="$(mktemp -- "${TMPDIR:-/tmp}/fedora-setup-repo-$id.XXXXXX")" || return $?
    printf '%s' "$content" >"$tmp" || {
        rm -f -- "$tmp"
        io_error "cannot write repo content for $id"
        return 1
    }
    run_sudo "add repo $id" -- install -m 0644 "$tmp" "$dest" || rv=$?
    rm -f -- "$tmp"
    return "$rv"
}

arch_aur_helper() {
    if command -v paru >/dev/null 2>&1; then
        printf 'paru\n'
        return 0
    fi
    if command -v yay >/dev/null 2>&1; then
        printf 'yay\n'
        return 0
    fi
    return 1
}

arch_aur_batch() {
    if (( $# == 0 )); then
        io_error "aur_batch requires at least one package"
        return 1
    fi
    local helper
    helper="$(arch_aur_helper)" || {
        io_error "AUR packages are opt-in: install an AUR helper (paru or yay) first; none found in PATH"
        return 1
    }
    run_sudo "install aur packages ($#)" -- "$helper" -S --noconfirm "$@"
}