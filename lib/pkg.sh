#!/usr/bin/env bash
# lib/pkg.sh - package backend interface and dispatcher for fedora-setup.
# Depends on lib/io.sh, lib/distro.sh (family detection), lib/run.sh (runner).
# Backend selection: FS_PKG_BACKEND=rpm|deb|arch|flatpak|mock (env, wins);
# else the distro family from distro_detect() (rpm|deb|arch). Selection is a
# read-only input: a successful load never rewrites FS_PKG_BACKEND.
# Backend contract (uniform across lib/pkg/<name>.sh, each defines ALL seven):
#   <name>_query_installed <pkg>   rc0 if installed, rc1 if not (no stdout)
#   <name>_list_installed           prints installed packages, one per line
#   <name>_install_batch <pkg>...   single transaction for the whole list
#   <name>_update_metadata          refresh repo metadata
#   <name>_install_local <file>     install a local package file
#   <name>_add_repo <id> <url>...   add repo if-not-exists; never overwrites
#   <name>_supported                rc0 if the backend is usable (e.g. the
#                                   package manager binary is present)
# pkg_supported() resolves selection, loads the backend, and dispatches to
# <name>_supported. Unimplemented, partial, or unknown backends error clearly
# via io_error. Real backends must route every privileged step through
# run_sudo/lib/run.sh so dry-run stays side-effect-free
# ({FS_DRY_RUN}/{FS_VERBOSE}/{FS_DEBUG} honored) and the FS_LOG_FILE audit
# trail holds; fs-style atomicity applies to repo files. Never touches
# /etc/sudoers. Bash >= 4.3 safe ($#-based bounds, guarded namerefs).

FS_PKG_BACKEND="${FS_PKG_BACKEND:-}"
_pkg_active=""
_pkg_loaded_backend=""
_pkg_dir="${BASH_SOURCE[0]%/*}"
if [[ "$_pkg_dir" == "${BASH_SOURCE[0]}" ]]; then
    _pkg_dir="."
elif [[ "$_pkg_dir" != /* ]]; then
    _pkg_dir="$(cd -- "$_pkg_dir" 2>/dev/null && pwd)" || _pkg_dir="."
fi

pkg_backend() {
    if [[ -n "${FS_PKG_BACKEND:-}" ]]; then
        printf '%s' "$FS_PKG_BACKEND"
        return 0
    fi
    if [[ -n "${FS_DISTRO_FAMILY:-}" ]]; then
        printf '%s' "$FS_DISTRO_FAMILY"
        return 0
    fi
    io_error "no package backend selected (set FS_PKG_BACKEND or run distro_detect)"
    return 1
}

_pkg_backend_name() {
    local name
    name="$(pkg_backend)" || return $?
    case "$name" in
        rpm|deb|arch|flatpak|mock) ;;
        *) io_error "unknown package backend: $name"; return 1 ;;
    esac
    printf '%s' "$name"
}

_pkg_load() {
    local name
    name="$(_pkg_backend_name)" || return $?
    if [[ "$name" != "$_pkg_loaded_backend" ]]; then
        local file="$_pkg_dir/pkg/$name.sh"
        if [[ ! -f "$file" ]]; then
            io_error "package backend not implemented: $name"
            return 1
        fi
        . "$file"
        local op
        for op in supported query_installed list_installed install_batch \
                update_metadata install_local add_repo; do
            if ! declare -F "${name}_${op}" >/dev/null 2>&1; then
                io_error "package backend not implemented: $name"
                return 1
            fi
        done
        _pkg_loaded_backend="$name"
    fi
    _pkg_active="$name"
    return 0
}

pkg_supported() {
    _pkg_load || return $?
    "${_pkg_active}_supported" || return $?
}

pkg_query_installed() {
    _pkg_load || return $?
    "${_pkg_active}_query_installed" "$@"
}

pkg_list_installed() {
    _pkg_load || return $?
    "${_pkg_active}_list_installed" "$@"
}

pkg_install_batch() {
    _pkg_load || return $?
    "${_pkg_active}_install_batch" "$@"
}

pkg_update_metadata() {
    _pkg_load || return $?
    "${_pkg_active}_update_metadata" "$@"
}

pkg_install_local() {
    _pkg_load || return $?
    "${_pkg_active}_install_local" "$@"
}

pkg_add_repo() {
    _pkg_load || return $?
    "${_pkg_active}_add_repo" "$@"
}