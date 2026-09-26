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

_cli_check_stub() {
    local root="${1:-}"
    [[ -n "$root" ]] || _fs_die "check requires the repository root"
    _fs_check_layout "$root"
    printf 'check: baseline prerequisites OK (stub)\n'
}

_cli_list_family() {
    case "${FS_DISTRO_FAMILY:-}" in
        rpm | deb | arch) printf '%s' "$FS_DISTRO_FAMILY" ;;
        *) printf '%s' "" ;;
    esac
}

_cli_list_impl() {
    local mdir="$1" family="$2" dir id status rc=0
    local -a dirs=()
    if [[ ! -d "$mdir" ]]; then
        io_error "modules directory not found: $mdir"
        return 1
    fi
    for dir in "$mdir"/*; do
        [[ -d "$dir" ]] || continue
        [[ "${dir##*/}" == .* ]] && continue
        dirs+=("$dir")
    done
    if ((${#dirs[@]} == 0)); then
        return 0
    fi
    for dir in "${dirs[@]}"; do
        module_validate "$dir" "$family" || rc=1
    done
    if (( rc != 0 )); then
        return 1
    fi
    module_validate_set "${dirs[@]}" || return 1
    local ids
    ids="$(printf '%s\n' "${dirs[@]##*/}" | LC_ALL=C sort)"
    while IFS= read -r id; do
        dir="$mdir/$id"
        module_load "$dir" || return 1
        if state_module_check "$id"; then
            status="done"
        else
            status="-"
        fi
        printf '%s\t%s\t%s\t%s\t%s\n' "$MODULE_ID" "$MODULE_TITLE" \
            "$MODULE_RISK" "$MODULE_DEFAULT" "$status"
    done <<<"$ids"
    return 0
}

main() {
    local root rc=0
    _fs_check_bash
    _fs_check_tools
    root="$(_fs_root)"
    _fs_check_layout "$root"
    . "$root/lib/io.sh"
    . "$root/lib/cli.sh"
    if ! cli_parse "$@"; then
        exit 1
    fi
    case "$FS_CMD" in
        version)
            printf 'fedora-setup %s\n' "$FS_VERSION"
            ;;
        help)
            cli_help
            ;;
        check)
            _cli_check_stub "$root"
            ;;
        list)
            . "$root/lib/modules.sh"
            . "$root/lib/state.sh"
            if ! state_init; then
                rc=1
            else
                if [[ -z "${FS_DISTRO_FAMILY:-}" ]]; then
                    . "$root/lib/distro.sh"
                    distro_detect || rc=1
                fi
                if (( rc == 0 )); then
                    _cli_list_impl "${FS_MODULES_DIR:-$root/modules}" "$(_cli_list_family)" || rc=1
                fi
            fi
            ;;
        install|verify|export|update)
            io_error "command '$FS_CMD' not implemented yet (planned in a later phase)"
            rc=1
            ;;
        *)
            io_error "command '$FS_CMD' is not wired into the dispatcher"
            rc=1
            ;;
    esac
    exit "$rc"
}

main "$@"
