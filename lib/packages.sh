#!/usr/bin/env bash
# lib/packages.sh - distro detection, package and Flatpak installation.
#
# Three families, one explicit case statement each. Everything the rest of the
# project needs to know about the host is exported here:
#
#   FS_FAMILY   rpm | deb | arch
#   FS_DISTRO   the ID from /etc/os-release (for messages)
#   PKG_INSTALL "<cmd> <args>"   the install command for this family
#   PKG_QUERY   "<cmd> <args>"   prints a version for one installed package
#   PKG_REFRESH "<cmd> <args>"   refreshes the package index
#
# Overridable for tests: FS_OS_RELEASE points at a different os-release file,
# FS_PKG_BIN overrides the detected package manager binary.
#
# Sourced by setup; not executable on its own.

detect_distro() {
    local os_file="${FS_OS_RELEASE:-/etc/os-release}"
    local id="" id_like=""

    [[ -r "$os_file" ]] || die "cannot read $os_file"
    id="$(_os_field "$os_file" ID)"
    id_like="$(_os_field "$os_file" ID_LIKE)"
    [[ -n "$id" ]] || die "no ID in $os_file"

    case "$id" in
    fedora | nobara | rhel | centos | rocky | almalinux | ol | amzn) FS_FAMILY="rpm" ;;
    debian | ubuntu | linuxmint | pop | zorin | elementary | kali | mx) FS_FAMILY="deb" ;;
    arch | archlinux | cachyos | endeavouros | manjaro | garuda | arcolinux) FS_FAMILY="arch" ;;
    *)
        case "$id_like" in
        *fedora* | *rhel* | *centos*) FS_FAMILY="rpm" ;;
        *debian* | *ubuntu*) FS_FAMILY="deb" ;;
        *arch*) FS_FAMILY="arch" ;;
        *) die "unsupported distro: $id (ID_LIKE: ${id_like:-none})" ;;
        esac
        ;;
    esac
    FS_DISTRO="$id"

    case "$FS_FAMILY" in
    rpm)
        local mgr="${FS_PKG_BIN:-}"
        if [[ -z "$mgr" ]]; then
            if have dnf5; then mgr="dnf5"; else mgr="dnf"; fi
        fi
        have "$mgr" || die "no supported package manager found (expected dnf5 or dnf)"
        PKG_INSTALL="$mgr install -y"
        PKG_QUERY="rpm -q"
        PKG_REFRESH="$mgr -y makecache --refresh"
        ;;
    deb)
        have apt-get || die "apt-get not found"
        PKG_INSTALL="apt-get install -y"
        PKG_QUERY="dpkg-query -W -f=\${db:Status-Status}\${Package}=\${Version}"
        PKG_REFRESH="apt-get update"
        ;;
    arch)
        have pacman || die "pacman not found"
        PKG_INSTALL="pacman -S --needed --noconfirm"
        PKG_QUERY="pacman -Q"
        PKG_REFRESH="pacman -Sy --noconfirm"
        ;;
    esac
    export FS_FAMILY FS_DISTRO PKG_INSTALL PKG_QUERY PKG_REFRESH
    log_info "distro: $FS_DISTRO ($FS_FAMILY, $PKG_INSTALL)"
}

_os_field() {
    local file="$1" key="$2" line
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^"$key"=(.*)$ ]] || continue
        line="${BASH_REMATCH[1]}"
        line="${line%\"}"; line="${line#\"}"
        line="${line%\'}"; line="${line#\'}"
        printf '%s' "$line"
        return 0
    done <"$file"
    return 0
}

pkg_installed() {
    case "$FS_FAMILY" in
    rpm) rpm -q "$1" >/dev/null 2>&1 ;;
    deb) [[ "$(dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null)" == "installed" ]] ;;
    arch) pacman -Q "$1" >/dev/null 2>&1 ;;
    esac
}

# package_files -- the list files to read: the shared one, plus this family's
# one when it exists. Both are plain text, one package name per line.
package_files() {
    printf '%s\n' "$FS_ROOT/config/packages.txt"
    local family_file="$FS_ROOT/config/packages-$FS_FAMILY.txt"
    [[ -f "$family_file" ]] && printf '%s\n' "$family_file"
    return 0
}

# install_packages <file>... -- install every package listed in the given files.
# A package already installed is skipped, so re-running is cheap and safe.
install_packages() {
    local file pkg wanted=() missing=()
    local -A seen=()

    for file in "$@"; do
        while IFS= read -r pkg; do
            [[ -n "$pkg" ]] || continue
            [[ -n "${seen[$pkg]:-}" ]] && continue
            seen[$pkg]=1
            wanted+=("$pkg")
        done < <(read_list "$file")
    done

    if ((${#wanted[@]} == 0)); then
        log_info "no packages configured"
        return 0
    fi

    for pkg in "${wanted[@]}"; do
        if pkg_installed "$pkg"; then
            log_info "already installed: $pkg"
        else
            missing+=("$pkg")
        fi
    done

    if ((${#missing[@]} == 0)); then
        log_info "all ${#wanted[@]} package(s) already installed"
        return 0
    fi

    run_root "install packages" $PKG_INSTALL "${missing[@]}"
}

# install_flatpaks <file> -- install every Flatpak id listed in the file,
# after making sure the Flathub remote exists.
install_flatpaks() {
    local file="$1" app missing=()
    local -A seen=()

    have flatpak || {
        log_warn "flatpak not installed; skipping $(basename -- "$file")"
        return 0
    }

    while IFS= read -r app; do
        [[ -n "$app" ]] || continue
        [[ -n "${seen[$app]:-}" ]] && continue
        seen[$app]=1
        if flatpak info "$app" >/dev/null 2>&1; then
            log_info "already installed: $app"
        else
            missing+=("$app")
        fi
    done < <(read_list "$file")

    if ((${#missing[@]} == 0)); then
        log_info "no flatpaks to install"
        return 0
    fi

    run "add flathub remote" flatpak remote-add --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo
    run "install flatpaks" flatpak install -y flathub "${missing[@]}"
}
