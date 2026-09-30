#!/usr/bin/env bash
# lib/distro.sh - distro detection and capability matrix for fedora-setup.
# Depends on lib/io.sh for io_error (source io.sh first).
# Input override: FS_DISTRO_FILE (env) or an explicit first argument; defaults
# to /etc/os-release. FS_DISTRO_FILE is read-only input and never mutated.
# Test injection for pkgmgr: FS_DISTRO_PKGMGR_OVERRIDE.

_distro_parse_value() {
    local file="$1" key="$2"
    local line rhs value=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*"$key"=(.*)$ ]] || continue
        rhs="${BASH_REMATCH[1]}"
        rhs="${rhs#"${rhs%%[![:space:]]*}"}"
        case "$rhs" in
        \"*)
            value="${rhs#\"}"
            value="${value%%\"*}"
            ;;
        \'*)
            value="${rhs#\'}"
            value="${value%%\'*}"
            ;;
        *)
            value="${rhs%%\#*}"
            value="${value%"${value##*[![:space:]]}"}"
            ;;
        esac
        break
    done <"$file"
    printf '%s' "$value"
}

_distro_family_from_id() {
    local id="$1" id_like="$2" fam=""
    case "$id" in
    fedora | nobara | rhel | centos | rocky | almalinux | ol | amzn) fam="rpm" ;;
    debian | ubuntu | linuxmint | pop | kali | elementary | zorin | mx | tuxedo) fam="deb" ;;
    arch | archlinux | cachyos | endeavouros | manjaro | arcolinux | garuda | artix | archcraft) fam="arch" ;;
    esac
    if [[ -z "$fam" ]]; then
        case "$id_like" in
        *fedora* | *rhel* | *centos*) fam="rpm" ;;
        *debian* | *ubuntu*) fam="deb" ;;
        *arch*) fam="arch" ;;
        esac
    fi
    printf '%s' "$fam"
}

_distro_pkgmgr() {
    local fam="$1"
    case "$fam" in
    rpm)
        if command -v dnf5 >/dev/null 2>&1; then
            printf 'dnf5'
        elif command -v dnf >/dev/null 2>&1; then
            printf 'dnf'
        fi
        ;;
    deb)
        if command -v apt-get >/dev/null 2>&1; then
            printf 'apt-get'
        fi
        ;;
    arch)
        if command -v pacman >/dev/null 2>&1; then
            printf 'pacman'
        fi
        ;;
    esac
}

_distro_localpkg() {
    local fam="$1" mgr="$2"
    case "$fam" in
    rpm)
        if [[ "$mgr" == "dnf5" ]]; then
            printf 'dnf5 localinstall'
        else
            printf 'dnf localinstall'
        fi
        ;;
    deb) printf 'apt-get install' ;;
    arch) printf 'pacman -U' ;;
    esac
}

_distro_gnome() {
    case "$1" in
    fedora | nobara | ubuntu | pop | debian) printf '1' ;;
    *) printf '0' ;;
    esac
}

distro_detect() {
    local file="${1:-${FS_DISTRO_FILE:-/etc/os-release}}"
    local id="" id_like="" variant="" fam="" pkg=""
    FS_DISTRO_SELECTED=""
    FS_DISTRO_FAMILY=""
    FS_DISTRO_ID=""
    FS_DISTRO_ID_LIKE=""
    FS_DISTRO_VARIANT=""
    FS_DISTRO_PKGMGR=""
    FS_DISTRO_LOCALPKG=""
    FS_DISTRO_FLATPAK_DEFAULT=""
    FS_DISTRO_GNOME=0
    if [[ ! -r "$file" ]]; then
        io_error "cannot read distro file: $file"
        return 1
    fi
    id="$(_distro_parse_value "$file" ID)"
    id_like="$(_distro_parse_value "$file" ID_LIKE)"
    variant="$(_distro_parse_value "$file" VARIANT_ID)"
    if [[ -z "$variant" ]]; then
        variant="$(_distro_parse_value "$file" VARIANT)"
    fi
    [[ -n "$id" ]] || {
        io_error "distro file has no ID: $file"
        return 1
    }
    fam="$(_distro_family_from_id "$id" "$id_like")"
    [[ -n "$fam" ]] || {
        io_error "unsupported distro: $id (id_like: ${id_like:-none})"
        return 1
    }
    if [[ -n "${FS_DISTRO_PKGMGR_OVERRIDE:-}" ]]; then
        pkg="$FS_DISTRO_PKGMGR_OVERRIDE"
    else
        pkg="$(_distro_pkgmgr "$fam")"
    fi
    FS_DISTRO_SELECTED="$file"
    FS_DISTRO_FAMILY="$fam"
    FS_DISTRO_ID="$id"
    FS_DISTRO_ID_LIKE="$id_like"
    FS_DISTRO_VARIANT="$variant"
    FS_DISTRO_PKGMGR="$pkg"
    FS_DISTRO_LOCALPKG="$(_distro_localpkg "$fam" "$pkg")"
    FS_DISTRO_FLATPAK_DEFAULT="flathub"
    FS_DISTRO_GNOME="$(_distro_gnome "$id")"
    return 0
}
