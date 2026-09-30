#!/usr/bin/env bash
# lib/pkg/rpm.sh - RPM package backend for fedora-setup.
# Loaded only through lib/pkg.sh (dispatcher). Depends on lib/io.sh and the
# runner (lib/run.sh run_sudo) for dry-run/audit semantics; policy globals
# FS_RUNNING_AS_ROOT / FS_SUDO_AVAILABLE come from lib/sudo.sh defaults in
# lib/run.sh (failing closed when the policy is absent).
# Capability requires both a dnf tool (dnf5 preferred over dnf, resolved via
# command -v) and rpm. Queries use `rpm -q` (rc0/rc1, no stdout) and
# `rpm -qa --qf '%{NAME}\n'` (installed package NAMES, one per line, matching
# the name form used by rpm -q). Mutations route through run_sudo: batch
# install is a SINGLE `install -y` transaction for the whole list after
# filtering out already-installed packages in real mode; dry-run skips the
# filter and emits one "# would run:" line per call (no queries, no writes).
# Local install is `dnf install -y <file>`. Repository files are added
# IF-NOT-EXISTS (never overwritten) under ${FS_REPOS_DIR:-/etc/yum.repos.d}
# via atomic `install -m 0644 <tmp> <dest>`; an optional <key> argument adds
# a gpgkey= line for copr-style repos. Never edits /etc/sudoers.
# Bash >= 4.3 safe.

_rpm_dnf() {
    if command -v dnf5 >/dev/null 2>&1; then
        printf 'dnf5'
    elif command -v dnf >/dev/null 2>&1; then
        printf 'dnf'
    else
        return 1
    fi
}

rpm_supported() {
    if _rpm_dnf >/dev/null 2>&1 && command -v rpm >/dev/null 2>&1; then
        return 0
    fi
    io_error "rpm backend unusable: need dnf5 or dnf plus rpm in PATH"
    return 1
}

rpm_query_installed() {
    local pkg="${1:-}"
    if [[ -z "$pkg" ]]; then
        io_error "query_installed requires a package name"
        return 1
    fi
    rpm -q "$pkg" >/dev/null 2>&1
}

rpm_list_installed() {
    rpm -qa --qf '%{NAME}\n' 2>/dev/null
}

rpm_install_batch() {
    rpm_supported || return $?
    local tool
    tool="$(_rpm_dnf)" || return $?
    if ((FS_DRY_RUN == 1)); then
        run_sudo "install packages ($#)" -- "$tool" install -y "$@"
        return 0
    fi
    local list=() pkg
    for pkg in "$@"; do
        if ! rpm_query_installed "$pkg"; then
            list+=("$pkg")
        fi
    done
    if ((${#list[@]} == 0)); then
        io_info "all packages already installed"
        return 0
    fi
    run_sudo "install packages (${#list[@]})" -- "$tool" install -y "${list[@]}"
}

rpm_update_metadata() {
    rpm_supported || return $?
    local tool
    tool="$(_rpm_dnf)" || return $?
    run_sudo "refresh rpm metadata" -- "$tool" makecache
}

rpm_install_local() {
    local file="${1:-}"
    if [[ -z "$file" ]]; then
        io_error "install_local requires a package file"
        return 1
    fi
    if [[ ! -f "$file" ]]; then
        io_error "local package file not found: $file"
        return 1
    fi
    rpm_supported || return $?
    local tool
    tool="$(_rpm_dnf)" || return $?
    run_sudo "install local package" -- "$tool" install -y "$file"
}

rpm_add_repo() {
    local id="${1:-}" url="${2:-}" key="${3:-}"
    if [[ -z "$id" || "$id" == */* || "$id" == *$'\n'* || "$id" == "." || "$id" == ".." ]]; then
        io_error "refusing invalid repo id: $id"
        return 1
    fi
    if [[ -z "$url" ]]; then
        io_error "add_repo requires a repo url"
        return 1
    fi
    local base="${FS_REPOS_DIR:-/etc/yum.repos.d}"
    local dest="$base/$id.repo" content tmp rv=0
    if [[ -e "$dest" ]]; then
        io_debug "repo exists, skipping: $dest"
        return 0
    fi
    printf -v content '[%s]\nname=%s\nbaseurl=%s\nenabled=1\ngpgcheck=1\n' "$id" "$id" "$url"
    if [[ -n "$key" ]]; then
        content+="gpgkey=${key}"$'\n'
    fi
    if ((FS_DRY_RUN == 1)); then
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
