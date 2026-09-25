#!/usr/bin/env bash
set -euo pipefail

FS_VERSION="0.1.0-dev"
FS_MIN_BASH_MAJOR=4
FS_MIN_BASH_MINOR=3

_fs_die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

_fs_script_path() {
    local name="$1"
    if [[ "$name" != */* ]]; then
        if [[ -f "$PWD/$name" ]]; then
            name="$PWD/$name"
        elif command -v -- "$name" >/dev/null 2>&1; then
            name="$(command -v -- "$name")"
        fi
    fi
    [[ -n "$name" ]] || _fs_die "cannot locate the script"
    if command -v readlink >/dev/null 2>&1; then
        name="$(readlink -f -- "$name" 2>/dev/null || printf '%s' "$name")"
    fi
    printf '%s\n' "$name"
}

_fs_root() {
    local path
    path="$(_fs_script_path "${BASH_SOURCE[0]}")"
    printf '%s\n' "$(cd -- "$(dirname -- "$path")/.." && pwd)"
}

_fs_check_bash() {
    local major="${BASH_VERSINFO[0]}"
    local minor="${BASH_VERSINFO[1]}"
    if (( major < FS_MIN_BASH_MAJOR )) || { (( major == FS_MIN_BASH_MAJOR )) && (( minor < FS_MIN_BASH_MINOR )); }; then
        _fs_die "Bash ${FS_MIN_BASH_MAJOR}.${FS_MIN_BASH_MINOR}+ required (found ${BASH_VERSION})"
    fi
}

_fs_check_tools() {
    local cmd
    for cmd in dirname; do
        command -v "$cmd" >/dev/null 2>&1 || _fs_die "required tool '$cmd' not found in PATH"
    done
}

_fs_check_layout() {
    [[ -d "$1/lib" ]] || _fs_die "repository layout broken: missing '$1/lib'"
    [[ -f "$1/setup" ]] || _fs_die "repository layout broken: missing '$1/setup'"
}

main() {
    local root
    _fs_check_bash
    _fs_check_tools
    root="$(_fs_root)"
    _fs_check_layout "$root"
    printf '%s %s\n' "fedora-setup" "$FS_VERSION"
    printf 'CLI dispatcher is not wired yet (planned in P2); nothing to do.\n'
}

main "$@"
