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

_cli_check_impl() {
    local root="$1" name rc=0
    [[ -n "$root" ]] || _fs_die "check requires the repository root"
    _fs_check_layout "$root"
    for name in distro sudo state check; do
        . "$root/lib/$name.sh"
    done
    check_run "$root" || rc=1
    return "$rc"
}

_cli_install_sources() {
    local root="$1" name
    for name in run pkg planner lists state modules depgraph profiles runner ui; do
        . "$root/lib/$name.sh"
    done
}

_cli_write_defaults() {
    local sel="$1" tmp="" rc=0
    shift
    tmp="$(mktemp "${sel%/*}/.fs-def.XXXXXX" 2>/dev/null)" || {
        io_error "cannot create defaults temp in: ${sel%/*}"
        return 1
    }
    if (( $# > 0 )); then
        printf '%s\n' "$@" >"$tmp" 2>/dev/null || rc=1
    else
        : >"$tmp" 2>/dev/null || rc=1
    fi
    if (( rc == 0 )); then
        mv -fT -- "$tmp" "$sel" 2>/dev/null || rc=1
    fi
    if (( rc != 0 )); then
        rm -f -- "$tmp" 2>/dev/null || :
        io_error "cannot write defaults to: $sel"
        return 1
    fi
    return 0
}

_cli_install_impl() {
    local root="$1"
    local mdir="${FS_MODULES_DIR:-$root/modules}"
    local pdir="${FS_PROFILES_DIR:-$root/profiles}"
    local name="${FS_PROFILE:-full}"
    local family="${FS_DISTRO_FAMILY:-}"
    if [[ -z "$family" ]]; then
        . "$root/lib/distro.sh"
        distro_detect || return 1
        family="${FS_DISTRO_FAMILY:-}"
    fi
    case "$family" in
        rpm | deb | arch) ;;
        *) io_error "unsupported family: $family"; return 1 ;;
    esac
    _cli_install_sources "$root"
    local -a dirs=() defaults=() cli_ids=() final=() hruns=()
    local id="" dir="" closure="" entries="" sel="" htxt="" hid=""
    local -i i=0 have=0 exact=1 rc=0
    if [[ ! -d "$mdir" ]]; then
        io_error "modules directory not found: $mdir"
        return 1
    fi
    while IFS= read -r id; do
        [[ -n "$id" ]] || continue
        module_validate "$mdir/$id" "$family" || return 1
        dirs+=("$mdir/$id")
    done < <(for dir in "$mdir"/*; do
        [[ -d "$dir" ]] || continue
        [[ "${dir##*/}" == .* ]] && continue
        printf '%s\n' "${dir##*/}"
    done | LC_ALL=C sort)
    module_validate_set ${dirs[@]+"${dirs[@]}"} || return 1
    closure="$(profile_resolve "$mdir" "$pdir" "$name")" || return 1
    if [[ -n "$closure" ]]; then
        while IFS= read -r id; do
            defaults+=("$id")
        done <<<"$closure"
    fi
    cli_ids=(${FS_CMD_ARGS[@]+"${FS_CMD_ARGS[@]}"})
    for id in ${cli_ids[@]+"${cli_ids[@]}"}; do
        module_valid_id "$id" || { io_error "invalid module id: $id"; return 1; }
        [[ -d "$mdir/$id" ]] || { io_error "module not found: $id"; return 1; }
        have=0
        for (( i = 0; i < ${#defaults[@]}; i++ )); do
            if [[ "${defaults[i]}" == "$id" ]]; then
                have=1
            fi
        done
        (( have == 1 )) || defaults+=("$id")
    done
    local scratch=""
    if (( FS_DRY_RUN == 1 )); then
        scratch="$(mktemp -d "${TMPDIR:-/tmp}/fs-install.XXXXXX")" || {
            io_error "cannot create install scratch"
            return 1
        }
        sel="$scratch/selection.sel"
    else
        state_init || return 1
        scratch="$(mktemp -d "${TMPDIR:-/tmp}/fs-install.XXXXXX")" || {
            io_error "cannot create install scratch"
            return 1
        }
        mkdir -p -- "$FS_STATE_DIR/selections" 2>/dev/null || {
            io_error "cannot create state selections dir"
            return 1
        }
        sel="$FS_STATE_DIR/selections/$name.sel"
    fi
    trap 'if [[ -n "${scratch:-}" ]]; then rm -rf -- "$scratch" 2>/dev/null || :; fi; trap - RETURN EXIT' RETURN EXIT
    entries="$scratch/entries"
    for dir in ${dirs[@]+"${dirs[@]}"}; do
        module_load "$dir" || return 1
        printf '%s\t%s\t%s\n' "$MODULE_ID" "${MODULE_TITLE:-$MODULE_ID}" "$MODULE_RISK"
    done >"$entries"
    local -a safe=()
    local -a held=()
    for id in ${defaults[@]+"${defaults[@]}"}; do
        module_load "$mdir/$id" || return 1
        have=0
        for (( i = 0; i < ${#cli_ids[@]}; i++ )); do
            if [[ "${cli_ids[i]}" == "$id" ]]; then
                have=1
            fi
        done
        case "$MODULE_RISK" in
            high | destructive)
                if (( have == 0 )); then
                    held+=("$id")
                else
                    safe+=("$id")
                fi
                ;;
            *) safe+=("$id") ;;
        esac
    done
    if (( ${#held[@]} > 0 )); then
        htxt=""
        for id in ${held[@]+"${held[@]}"}; do
            htxt="$htxt $id"
        done
        io_alert "high-risk module(s) not selected:$htxt; name one on the command line to run it"
    fi
    _cli_write_defaults "$sel" ${safe[@]+"${safe[@]}"} || return 1
    if (( FS_YES != 1 )); then
        ui_multiselect "Select modules for profile '$name'" "$entries" "$sel" || return 1
    fi
    if [[ -f "$sel" ]]; then
        while IFS= read -r id; do
            [[ -n "$id" ]] || continue
            final+=("$id")
        done <"$sel"
    fi
    for id in ${final[@]+"${final[@]}"}; do
        module_load "$mdir/$id" || return 1
        case "$MODULE_RISK" in
            high | destructive) hruns+=("$id") ;;
        esac
    done
    if (( ${#hruns[@]} > 0 )); then
        htxt=""
        for hid in ${hruns[@]+"${hruns[@]}"}; do
            htxt="$htxt $hid"
        done
        if ! ui_confirm "high-risk module(s) enabled:$htxt; continue?"; then
            io_warn "installation aborted (high-risk confirmation declined)"
            return 1
        fi
    fi
    if (( FS_DRY_RUN != 1 )) && [[ "${FS_PKG_BACKEND:-}" != mock ]]; then
        . "$root/lib/sudo.sh"
        sudo_detect
    fi
    if (( ${#cli_ids[@]} > 0 )); then
        exact=0
    else
        local fsrt="" csrt=""
        fsrt="$(printf '%s\n' ${final[@]+"${final[@]}"} | LC_ALL=C sort)"
        csrt="$(printf '%s\n' ${defaults[@]+"${defaults[@]}"} | LC_ALL=C sort)"
        if [[ "$fsrt" != "$csrt" ]]; then
            exact=0
        fi
    fi
    if (( exact == 1 )); then
        runner_run "$mdir" "$pdir" "$name" "$family"
    else
        runner_run "$mdir" "$pdir" "selection" "$family" ${final[@]+"${final[@]}"}
    fi
    rc=$?
    rm -rf -- "$scratch" 2>/dev/null || :
    return "$rc"
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
            _cli_check_impl "$root"
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
        install)
            _cli_install_impl "$root" || rc=1
            ;;
        verify|export|update)
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
