#!/bin/bash
# Install system and Flatpak applications for supported distros
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

dtype=$(distribution)

# Package lists
#
# Native packages live in config/packages/<family>.txt and Flatpak IDs in
# config/flatpak.txt (one entry per line; blank lines and text after '#' are
# ignored). A missing or unreadable list file is fatal before anything is
# installed; a readable list with no entries is skipped without invoking a
# package manager.

# cfg_load_list <file> <array-name>: load a required list file into <array>.
cfg_load_list() {
    local file="$1"
    local -n _cfg_out="$2"
    if [ ! -f "$file" ]; then
        echo "Error: required config file not found: $file" >&2
        exit 1
    fi
    if [ ! -r "$file" ]; then
        echo "Error: required config file is not readable: $file" >&2
        exit 1
    fi
    _cfg_out=()
    local line
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        if [ -n "$line" ]; then
            _cfg_out+=("$line")
        fi
    done < "$file"
    return 0
}

case "$dtype" in
    "redhat") package_file="$SCRIPT_DIR/config/packages/fedora.txt" ;;
    "debian") package_file="$SCRIPT_DIR/config/packages/debian.txt" ;;
    "arch")   package_file="$SCRIPT_DIR/config/packages/arch.txt" ;;
    *)
        echo "Unknown or unsupported distribution: $dtype" >&2
        exit 1
        ;;
esac

cfg_load_list "$package_file" package_list
cfg_load_list "$SCRIPT_DIR/config/flatpak.txt" flatpak_apps

# pkg_probe <package>: 0 installed, 1 missing, 2 probe error. Detection
# errors are never treated as absence. Probe output is read with LC_ALL=C so
# that the parsed absence text is locale-independent. SETUP_PKG_PROBE
# overrides detection in tests (called as: <probe> <package>).
pkg_probe() {
    if [ -n "${SETUP_PKG_PROBE:-}" ]; then
        if "$SETUP_PKG_PROBE" "$1"; then return 0; else return $?; fi
    fi
    local out
    case "$dtype" in
        "redhat")
            if ! command -v rpm >/dev/null 2>&1; then
                echo "Error: rpm not found; cannot detect installed packages." >&2
                return 2
            fi
            if out=$(LC_ALL=C rpm -q "$1" 2>&1); then return 0; fi
            # A few Fedora catalog names exist only as virtual provides
            # (`wget` is provided by `wget2-wget`), which `rpm -q "$1"` never
            # matches. Query a provide only for those known names so that an
            # unrelated installed package's capability cannot mask a real
            # package. Output is captured with LC_ALL=C because the absence
            # text below is matched literally (probe messages are localized).
            case "$1" in
                wget)
                    if LC_ALL=C rpm -q --whatprovides "$1" >/dev/null 2>&1; then return 0; fi
                    ;;
            esac
            case "$out" in
                *"is not installed"*) return 1 ;;
                *) echo "Error: rpm probe failed for '$1': $out" >&2; return 2 ;;
            esac
            ;;
        "debian")
            if ! command -v dpkg >/dev/null 2>&1; then
                echo "Error: dpkg not found; cannot detect installed packages." >&2
                return 2
            fi
            if out=$(LC_ALL=C dpkg -s "$1" 2>&1); then return 0; fi
            case "$out" in
                *"is not installed"*) return 1 ;;
                *) echo "Error: dpkg probe failed for '$1': $out" >&2; return 2 ;;
            esac
            ;;
        "arch")
            if ! command -v pacman >/dev/null 2>&1; then
                echo "Error: pacman not found; cannot detect installed packages." >&2
                return 2
            fi
            if out=$(LC_ALL=C pacman -Q "$1" 2>&1); then return 0; fi
            case "$out" in
                *"was not found"*) return 1 ;;
                *) echo "Error: pacman probe failed for '$1': $out" >&2; return 2 ;;
            esac
            ;;
    esac
}

echo "Installing system packages..."

missing_packages=()
declare -A planned_native=()
for pkg in "${package_list[@]}"; do
    if pkg_probe "$pkg"; then
        echo "$pkg is already installed."
    else
        rc=$?
        if [ "$rc" -eq 2 ]; then
            echo "Error: could not determine whether '$pkg' is installed." >&2
            exit 1
        fi
        missing_packages+=("$pkg")
        planned_native["$pkg"]=1
    fi
done

if [ "${#package_list[@]}" -eq 0 ]; then
    echo "No native packages listed in $package_file; skipping package install."
elif [ "${#missing_packages[@]}" -eq 0 ]; then
    echo "All native packages from $package_file are already installed."
else
    echo "${#missing_packages[@]} missing native package(s); installing..."
    case "$dtype" in
        "redhat")
            if ! run_root dnf makecache; then
                echo "Error: dnf failed to refresh the package index (Fedora family)." >&2
                exit 1
            fi
            if ! run_root dnf install -y "${missing_packages[@]}"; then
                echo "Error: dnf failed to install the Fedora package set." >&2
                exit 1
            fi
            ;;
        "debian")
            if ! run_root apt-get update; then
                echo "Error: apt-get failed to refresh the package index (Debian family)." >&2
                exit 1
            fi
            if ! run_root apt-get install -y "${missing_packages[@]}"; then
                echo "Error: apt-get failed to install the Debian package set." >&2
                exit 1
            fi
            ;;
        "arch")
            if ! run_root pacman -Syu --noconfirm "${missing_packages[@]}"; then
                echo "Error: pacman failed to refresh and install the Arch package set." >&2
                exit 1
            fi
            ;;
    esac
fi

echo -e "\nInstalling Flatpak applications..."

# flatpak_probe <app>: 0 installed (user or system scope), 1 missing,
# 2 probe error. Detection errors are never treated as absence. Probe output
# is read with LC_ALL=C so the parsed absence text is locale-independent.
# SETUP_FLATPAK_PROBE overrides detection in tests.
flatpak_probe() {
    if [ -n "${SETUP_FLATPAK_PROBE:-}" ]; then
        if "$SETUP_FLATPAK_PROBE" "$1"; then return 0; else return $?; fi
    fi
    if flatpak info "$1" >/dev/null 2>&1; then return 0; fi
    if flatpak info --user "$1" >/dev/null 2>&1; then return 0; fi
    local out
    out=$(LC_ALL=C flatpak info "$1" 2>&1) || true
    case "$out" in
        *"not installed"*|*"No such ref"*) return 1 ;;
    esac
    out=$(LC_ALL=C flatpak info --user "$1" 2>&1) || true
    case "$out" in
        *"not installed"*|*"No such ref"*) return 1 ;;
    esac
    echo "Error: flatpak probe failed for '$1'." >&2
    return 2
}

# Explicit cross-source mappings: a Flatpak app is skipped when the same
# application is reliably installed natively. Keep this list small and exact.
flatpak_native_equivalent() {
    case "$1" in
        "org.mozilla.thunderbird_esr") echo "thunderbird" ;;
        "com.obsproject.Studio") echo "obs-studio" ;;
        *) echo "" ;;
    esac
}

if [ "${#flatpak_apps[@]}" -eq 0 ]; then
    echo "No Flatpak applications listed in config/flatpak.txt; skipping."
else
    if ! command -v flatpak >/dev/null 2>&1; then
        echo "Error: flatpak command not found (required to install Flatpak applications)." >&2
        exit 1
    fi

    if ! flatpak remotes --system | grep -qE '^flathub([[:space:]]|$)'; then
        if ! run_root flatpak remote-add --system --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; then
            echo "Error: failed to add the Flathub remote." >&2
            exit 1
        fi
    fi

    for app in "${flatpak_apps[@]}"; do
        native="$(flatpak_native_equivalent "$app")"
        if [ -n "$native" ]; then
            if pkg_probe "$native"; then
                echo "Skipping Flatpak $app: native $native is installed."
                continue
            else
                rc=$?
                if [ "$rc" -eq 2 ]; then
                    echo "Error: failed to detect native package '$native'." >&2
                    exit 1
                fi
                if [ -n "${planned_native[$native]:-}" ]; then
                    echo "Skipping Flatpak $app: native $native will be installed by this run."
                    continue
                fi
            fi
        fi
        if flatpak_probe "$app"; then
            echo "$app is already installed."
        else
            rc=$?
            if [ "$rc" -eq 2 ]; then
                echo "Error: failed to detect Flatpak app '$app'." >&2
                exit 1
            fi
            if ! run_root flatpak install --system flathub "$app" -y; then
                echo "Error: failed to install Flatpak app $app" >&2
                exit 1
            fi
        fi
    done
fi

echo -e "\nInstalling Google Chrome and Visual Studio Code..."

# The vendor packages below are published for x86_64 only. The check runs only
# on a path that is about to download one, so an already-installed setup on
# other architectures still succeeds.
require_vendor_arch() {
    local vendor_arch
    vendor_arch=$(uname -m)
    case "$vendor_arch" in
        x86_64) ;;
        *)
            echo "Error: Chrome and VS Code vendor installs support x86_64 only (detected: $vendor_arch)." >&2
            exit 1
            ;;
    esac
}

if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
    case "$dtype" in
        "debian")
            echo "would run: download and install VS Code and Google Chrome via apt-get"
            ;;
        "redhat")
            echo "would run: download and install VS Code and Google Chrome via dnf"
            ;;
        "arch")
            echo "would run: install VS Code and Google Chrome via yay (AUR)"
            ;;
    esac
else
    if ! vendor_tmp=$(mktemp -d); then
        echo "Error: failed to create a temporary download directory." >&2
        exit 1
    fi
    cleanup_vendor_tmp() {
        if [ -n "$vendor_tmp" ]; then
            rm -rf "$vendor_tmp"
        fi
    }
    trap cleanup_vendor_tmp EXIT

    case "$dtype" in
    "debian")
        # VS Code
        if ! dpkg -s code &>/dev/null; then
            require_vendor_arch
            if ! run wget -O "$vendor_tmp/vscode.deb" "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64"; then
                echo "Error: failed to download the VS Code .deb package." >&2
                exit 1
            fi
            if ! run_root apt-get install -y "$vendor_tmp/vscode.deb"; then
                echo "Error: failed to install the VS Code .deb package." >&2
                exit 1
            fi
            echo "VS Code installed."
        else
            echo "VS Code is already installed."
        fi
        # Chrome
        if ! dpkg -s google-chrome-stable &>/dev/null; then
            require_vendor_arch
            if ! run wget -O "$vendor_tmp/chrome.deb" "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"; then
                echo "Error: failed to download the Google Chrome .deb package." >&2
                exit 1
            fi
            if ! run_root apt-get install -y "$vendor_tmp/chrome.deb"; then
                echo "Error: failed to install the Google Chrome .deb package." >&2
                exit 1
            fi
            echo "Google Chrome installed."
        else
            echo "Google Chrome is already installed."
        fi
        ;;
    "redhat")
        # VS Code (.rpm download; no repo file is written)
        if ! rpm -q code &>/dev/null; then
            require_vendor_arch
            if ! run wget -O "$vendor_tmp/vscode.rpm" "https://code.visualstudio.com/sha/download?build=stable&os=linux-rpm-x64"; then
                echo "Error: failed to download the VS Code .rpm package." >&2
                exit 1
            fi
            if ! run_root dnf install -y "$vendor_tmp/vscode.rpm"; then
                echo "Error: failed to install the VS Code .rpm package." >&2
                exit 1
            fi
            echo "VS Code installed."
        else
            echo "VS Code is already installed."
        fi
        # Chrome
        if ! rpm -q google-chrome-stable &>/dev/null; then
            require_vendor_arch
            if ! run wget -O "$vendor_tmp/chrome.rpm" "https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm"; then
                echo "Error: failed to download the Google Chrome .rpm package." >&2
                exit 1
            fi
            if ! run_root dnf install -y "$vendor_tmp/chrome.rpm"; then
                echo "Error: failed to install the Google Chrome .rpm package." >&2
                exit 1
            fi
            echo "Google Chrome installed."
        else
            echo "Google Chrome is already installed."
        fi
        ;;
    "arch")
        # AUR installs need the yay helper; bootstrapping it is intentionally
        # not done here, so a missing helper fails with instructions.
        if ! pacman -Qi visual-studio-code-bin &>/dev/null || ! pacman -Qi google-chrome &>/dev/null; then
            require_vendor_arch
            if ! command -v yay &>/dev/null; then
                echo "Error: yay is required to install VS Code and Chrome from the AUR, but it was not found." >&2
                echo "Install yay manually (https://wiki.archlinux.org/title/AUR_helper), then rerun this script." >&2
                exit 1
            fi
        fi
        # VS Code
        if ! pacman -Qi visual-studio-code-bin &>/dev/null; then
            if ! run yay -S --needed --noconfirm visual-studio-code-bin; then
                echo "Error: failed to install visual-studio-code-bin via yay." >&2
                exit 1
            fi
            echo "VS Code installed."
        else
            echo "VS Code is already installed."
        fi
        # Chrome
        if ! pacman -Qi google-chrome &>/dev/null; then
            if ! run yay -S --needed --noconfirm google-chrome; then
                echo "Error: failed to install google-chrome via yay." >&2
                exit 1
            fi
            echo "Google Chrome installed."
        else
            echo "Google Chrome is already installed."
        fi
        ;;
    esac
fi

echo -e "\nAll system, Flatpak, Chrome, and VS Code steps processed.\n"
echo -e "\n#################### Done! ####################"
