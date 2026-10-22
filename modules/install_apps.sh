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

# Debian and Ubuntu share most package names, but Ubuntu's archive does not
# provide firefox-esr. Keep Debian's ESR package and use Ubuntu's firefox
# transitional package (which selects Ubuntu's supported Firefox delivery).
if [ "$dtype" = "debian" ]; then
    distro_id=""
    distro_like=""
    os_release_file="${OS_RELEASE_FILE:-/etc/os-release}"
    if [ -r "$os_release_file" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            case "$line" in
                ID=*) distro_id="${line#ID=}" ;;
                ID_LIKE=*) distro_like="${line#ID_LIKE=}" ;;
            esac
        done < "$os_release_file"
    fi
    distro_id="${distro_id%\"}"
    distro_id="${distro_id#\"}"
    distro_id="${distro_id%\'}"
    distro_id="${distro_id#\'}"
    distro_like="${distro_like%\"}"
    distro_like="${distro_like#\"}"
    distro_like="${distro_like%\'}"
    distro_like="${distro_like#\'}"
    if [ "$distro_id" = "ubuntu" ] || [[ " $distro_like " == *" ubuntu "* ]]; then
        for i in "${!package_list[@]}"; do
            if [ "${package_list[$i]}" = "firefox-esr" ]; then
                package_list[$i]="firefox"
                break
            fi
        done
    fi
fi

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

successes=()
failures=()
skips=()
plans=()
native_pending=()
declare -A native_present=()
declare -A native_planned=()

record_success() { successes+=("$1"); }
record_failure() { failures+=("$1: $2"); }
record_skip() { skips+=("$1: $2"); }
record_plan() { plans+=("$1"); }

echo "Installing system packages..."
for pkg in "${package_list[@]}"; do
    if pkg_probe "$pkg"; then
        native_present["$pkg"]=1
        record_skip "$pkg" "already installed"
    else
        rc=$?
        if [ "$rc" -eq 1 ]; then
            native_pending+=("$pkg")
            native_planned["$pkg"]=1
        else
            record_failure "$pkg" "could not determine installed state (package-manager probe failed)"
        fi
    fi
done

if [ "${#package_list[@]}" -eq 0 ]; then
    echo "No native packages listed in $package_file; skipping package install."
elif [ "${#native_pending[@]}" -gt 0 ]; then
    refresh_ok=1
    case "$dtype" in
        redhat) run_root dnf makecache || refresh_ok=0 ;;
        debian) run_root apt-get update || refresh_ok=0 ;;
        arch) : ;;
    esac
    if [ "$refresh_ok" -eq 0 ]; then
        for pkg in "${native_pending[@]}"; do
            record_failure "$pkg" "package index refresh failed"
        done
    else
        case "$dtype" in
            redhat) batch_cmd=(dnf install -y) ;;
            debian) batch_cmd=(apt-get install -y) ;;
            arch) batch_cmd=(pacman -S --needed --noconfirm) ;;
        esac
        batch_ok=0
        if run_root "${batch_cmd[@]}" "${native_pending[@]}"; then
            batch_ok=1
        fi
        for pkg in "${native_pending[@]}"; do
            if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
                record_plan "$pkg"
                continue
            fi
            if pkg_probe "$pkg"; then
                native_present["$pkg"]=1
                record_success "$pkg"
            elif [ "$?" -eq 2 ]; then
                record_failure "$pkg" "could not verify package installation"
            elif [ "${SUDO_AUTH_FAILED:-0}" = "1" ]; then
                record_failure "$pkg" "privileged operation unavailable (missing sudo or authentication failed)"
            else
                case "$dtype" in
                    redhat) install_cmd=(dnf install -y "$pkg") ;;
                    debian) install_cmd=(apt-get install -y "$pkg") ;;
                    arch) install_cmd=(pacman -S --needed --noconfirm "$pkg") ;;
                esac
                if run_root "${install_cmd[@]}" && pkg_probe "$pkg"; then
                    native_present["$pkg"]=1
                    record_success "$pkg"
                elif [ "${SUDO_AUTH_FAILED:-0}" = "1" ]; then
                    record_failure "$pkg" "privileged operation unavailable (missing sudo or authentication failed)"
                else
                    if [ "$batch_ok" -eq 0 ]; then
                        record_failure "$pkg" "batch transaction and individual retry failed"
                    else
                        record_failure "$pkg" "package manager returned success but verification and retry failed"
                    fi
                fi
            fi
        done
    fi
fi

# flatpak_probe <app>: 0 installed, 1 missing, 2 probe error.
flatpak_probe() {
    if [ -n "${SETUP_FLATPAK_PROBE:-}" ]; then
        if "$SETUP_FLATPAK_PROBE" "$1"; then return 0; else return $?; fi
    fi
    if flatpak info "$1" >/dev/null 2>&1 || flatpak info --user "$1" >/dev/null 2>&1; then
        return 0
    fi
    local system_out user_out system_missing=0 user_missing=0
    system_out=$(LC_ALL=C flatpak info "$1" 2>&1) || true
    user_out=$(LC_ALL=C flatpak info --user "$1" 2>&1) || true
    case "$system_out" in *"not installed"*|*"No such ref"*) system_missing=1 ;; esac
    case "$user_out" in *"not installed"*|*"No such ref"*) user_missing=1 ;; esac
    if [ "$system_missing" -eq 1 ] && [ "$user_missing" -eq 1 ]; then return 1; fi
    return 2
}

flatpak_native_equivalent() {
    case "$1" in
        org.mozilla.thunderbird_esr) echo thunderbird ;;
        com.obsproject.Studio) echo obs-studio ;;
        *) echo "" ;;
    esac
}

echo -e "\nInstalling Flatpak applications..."
flatpak_missing=()
if [ "${#flatpak_apps[@]}" -eq 0 ]; then
    echo "No Flatpak applications listed in $SCRIPT_DIR/config/flatpak.txt; skipping Flatpak installation."
fi
if [ "${SETUP_DRY_RUN:-0}" = "1" ] && [ "${#flatpak_apps[@]}" -gt 0 ]; then
    run_root flatpak remote-add --system --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
fi
for app in "${flatpak_apps[@]}"; do
    native=$(flatpak_native_equivalent "$app")
    if [ -n "$native" ]; then
        if [ -n "${native_present[$native]:-}" ]; then
            echo "Skipping Flatpak $app: native $native is installed."
            record_skip "$app" "equivalent native package $native is installed"
            continue
        elif [ "${SETUP_DRY_RUN:-0}" = "1" ] && [ -n "${native_planned[$native]:-}" ]; then
            echo "Skipping Flatpak $app: native $native will be installed by this run."
            record_skip "$app" "equivalent native package $native is planned"
            continue
        elif [ -z "${native_planned[$native]:-}" ]; then
            # The native equivalent may have been installed independently of
            # this package list. Probe it before deciding to install a duplicate.
            if pkg_probe "$native"; then
                native_present["$native"]=1
                echo "Skipping Flatpak $app: native $native is installed."
                record_skip "$app" "equivalent native package $native is installed"
                continue
            else
                rc=$?
                if [ "$rc" -eq 2 ]; then
                    record_failure "$app" "could not determine whether native equivalent $native is installed"
                    continue
                fi
            fi
        fi
    fi
    if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
        run_root flatpak install --system flathub "$app" -y
        record_plan "$app"
    elif ! command -v flatpak >/dev/null 2>&1; then
        record_failure "$app" "flatpak command is unavailable"
    elif flatpak_probe "$app"; then
        record_skip "$app" "already installed"
    else
        rc=$?
        if [ "$rc" -eq 1 ]; then
            flatpak_missing+=("$app")
        else
            record_failure "$app" "Flatpak installed-state probe failed"
        fi
    fi
done

if [ "${SETUP_DRY_RUN:-0}" != "1" ] && [ "${#flatpak_missing[@]}" -gt 0 ]; then
    if ! flatpak_remote_output=$(flatpak remotes --system 2>&1); then
        for app in "${flatpak_missing[@]}"; do
            record_failure "$app" "could not query system Flatpak remotes: $flatpak_remote_output"
        done
        flatpak_missing=()
    else
        flathub_found=0
        while IFS= read -r remote_line; do
            remote_name=${remote_line%%[[:space:]]*}
            if [ "$remote_name" = flathub ]; then
                flathub_found=1
                break
            fi
        done <<< "$flatpak_remote_output"
    fi
    if [ "${SETUP_DRY_RUN:-0}" != "1" ] && [ "${#flatpak_missing[@]}" -gt 0 ] && [ "$flathub_found" -eq 0 ]; then
        if ! run_root flatpak remote-add --system --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; then
            for app in "${flatpak_missing[@]}"; do
                record_failure "$app" "failed to add Flathub system remote"
            done
            flatpak_missing=()
        fi
    fi
    for app in "${flatpak_missing[@]}"; do
        if run_root flatpak install --system flathub "$app" -y && flatpak_probe "$app"; then
            record_success "$app"
        else
            record_failure "$app" "Flatpak install or post-install verification failed"
        fi
    done
fi

echo -e "\nInstalling Google Chrome and Visual Studio Code..."
vendor_packages=()
case "$dtype" in
    debian) vendor_packages=("code:VS Code" "google-chrome-stable:Google Chrome") ;;
    redhat) vendor_packages=("code:VS Code" "google-chrome-stable:Google Chrome") ;;
    arch) vendor_packages=("visual-studio-code-bin:VS Code" "google-chrome:Google Chrome") ;;
esac

vendor_probe() {
    local out rc
    case "$dtype" in
        debian)
            if dpkg -s "$1" >/dev/null 2>&1; then return 0; else rc=$?; fi
            out=$(dpkg -s "$1" 2>&1) || true
            case "$out" in *"is not installed"*) return 1 ;; esac
            ;;
        redhat)
            if rpm -q "$1" >/dev/null 2>&1; then return 0; else rc=$?; fi
            out=$(rpm -q "$1" 2>&1) || true
            case "$out" in *"is not installed"*) return 1 ;; esac
            ;;
        arch)
            if pacman -Qi "$1" >/dev/null 2>&1; then return 0; else rc=$?; fi
            out=$(pacman -Qi "$1" 2>&1) || true
            case "$out" in *"was not found"*) return 1 ;; esac
            ;;
    esac
    echo "Error: could not determine whether vendor package '$1' is installed: ${out:-probe exited $rc}." >&2
    return 2
}

if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
    case "$dtype" in
        debian) echo "would run: download and install VS Code and Google Chrome via apt-get" ;;
        redhat) echo "would run: download and install VS Code and Google Chrome via dnf" ;;
        arch) echo "would run: bootstrap yay if needed and install VS Code and Google Chrome via yay (AUR)" ;;
    esac
    record_plan "Vendor applications (VS Code and Google Chrome)"
else
    vendor_arch=$(uname -m 2>/dev/null || echo unknown)
    vendor_tmp=""
    cleanup_vendor_tmp() {
        if [ -n "$vendor_tmp" ]; then
            if rm -rf "$vendor_tmp"; then
                vendor_tmp=""
            else
                return 1
            fi
        fi
        return 0
    }
    trap cleanup_vendor_tmp EXIT
    for vendor_entry in "${vendor_packages[@]}"; do
        pkg=${vendor_entry%%:*}
        label=${vendor_entry#*:}
        if vendor_probe "$pkg"; then
            record_skip "$label" "already installed"
            continue
        else
            rc=$?
            if [ "$rc" -eq 2 ]; then
                record_failure "$label" "installed-state probe failed"
                continue
            fi
        fi
        if [ "$vendor_arch" != x86_64 ]; then
            record_failure "$label" "vendor installers support x86_64 only (detected: $vendor_arch)"
            continue
        fi
        if [ "${SUDO_AUTH_FAILED:-0}" = "1" ]; then
            record_failure "$label" "privileged operation unavailable during an earlier step (missing sudo or authentication failed)"
            continue
        fi
        case "$dtype" in
            arch)
                if ! ensure_yay; then
                    record_failure "$label" "AUR helper yay is unavailable and could not be bootstrapped"
                elif ! run yay -S --needed --noconfirm "$pkg"; then
                    record_failure "$label" "AUR installation or verification failed"
                elif vendor_probe "$pkg"; then
                    record_success "$label"
                else
                    record_failure "$label" "AUR command returned success but verification failed"
                fi
                ;;
            *)
                if [ -z "$vendor_tmp" ]; then
                    if ! vendor_tmp=$(mktemp -d); then
                        vendor_tmp=""
                    fi
                fi
                if [ -z "$vendor_tmp" ]; then
                    record_failure "$label" "could not create temporary download directory"
                    continue
                fi
                if [ "$dtype" = debian ]; then
                    if [ "$pkg" = code ]; then
                        url="https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64"
                        file="$vendor_tmp/vscode.deb"
                    else
                        url="https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
                        file="$vendor_tmp/chrome.deb"
                    fi
                    install_cmd=(apt-get install -y "$file")
                else
                    if [ "$pkg" = code ]; then
                        url="https://code.visualstudio.com/sha/download?build=stable&os=linux-rpm-x64"
                        file="$vendor_tmp/vscode.rpm"
                    else
                        url="https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm"
                        file="$vendor_tmp/chrome.rpm"
                    fi
                    install_cmd=(dnf install -y "$file")
                fi
                if ! run wget -O "$file" "$url"; then
                    record_failure "$label" "vendor download failed"
                elif ! run_root "${install_cmd[@]}"; then
                    record_failure "$label" "vendor package installation failed"
                elif vendor_probe "$pkg"; then
                    record_success "$label"
                else
                    record_failure "$label" "package manager returned success but verification failed"
                fi
                ;;
        esac
    done
    if [ -n "$vendor_tmp" ]; then
        if ! cleanup_vendor_tmp; then
            record_failure "vendor temporary files" "could not remove the temporary download directory"
        fi
    fi
fi

echo
echo "Package installation results:"
for item in "${successes[@]}"; do echo "  INSTALLED: $item"; done
for item in "${skips[@]}"; do echo "  SKIPPED: $item"; done
for item in "${plans[@]}"; do echo "  PLANNED: $item"; done
for item in "${failures[@]}"; do echo "  FAILED: $item" >&2; done
if [ "${#failures[@]}" -gt 0 ]; then
    echo "Package installation incomplete: ${#failures[@]} failure(s), ${#successes[@]} installed, ${#skips[@]} skipped, ${#plans[@]} planned." >&2
    exit 1
fi
if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
    echo "Dry-run complete: plan shown; no installations performed."
else
    echo "Package installation complete: ${#successes[@]} installed, ${#skips[@]} skipped."
fi
