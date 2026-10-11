#!/bin/bash
# Install and enable the approved GNOME Shell extensions from
# config/gnome-extensions.txt, downloading a version compatible with the
# running GNOME Shell from extensions.gnome.org.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# GNOME Shell extensions are optional outside GNOME. This module uses
# gnome-extensions for state queries; it does not depend on gsettings.
if [ "$(desktop_environment)" != "gnome" ]; then
    echo "Skipping GNOME extensions: GNOME desktop not detected."
    exit 0
fi

# cfg_load_list <file> <array-name>: load a required list file into <array>.
# One entry per line; blank lines and text after '#' are ignored. Mirrors the
# install_apps.sh convention; a missing or unreadable list is fatal.
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

if ! command -v gnome-extensions >/dev/null 2>&1; then
    echo "Error: gnome-extensions not found; cannot manage GNOME extensions." >&2
    exit 1
fi

# Reading the compatibility data returned by extensions.gnome.org needs JSON
# parsing; python3 is already a dependency of the dev module.
if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: python3 not found; it is required to read GNOME extension compatibility data." >&2
    exit 1
fi

# Detect the running GNOME Shell major version. Nothing is hardcoded: the value
# reported by the local shell is used to select and validate a compatible
# release. Falls back to gnome-extensions when gnome-shell is not on PATH.
detect_shell_major() {
    local out="" major=""
    if command -v gnome-shell >/dev/null 2>&1; then
        out=$(gnome-shell --version 2>/dev/null) || out=""
    fi
    if [ -z "$out" ] && command -v gnome-extensions >/dev/null 2>&1; then
        out=$(gnome-extensions version 2>/dev/null) || out=""
    fi
    if [[ "$out" =~ ([0-9]+) ]]; then
        major="${BASH_REMATCH[1]}"
    fi
    if [ -z "$major" ]; then
        return 1
    fi
    printf '%s\n' "$major"
}

if ! shell_major=$(detect_shell_major); then
    echo "Error: could not determine the running GNOME Shell version." >&2
    exit 1
fi

config_file="$SCRIPT_DIR/config/gnome-extensions.txt"
cfg_load_list "$config_file" extensions

if [ "${#extensions[@]}" -eq 0 ]; then
    echo "No GNOME extensions listed in $config_file; skipping."
    exit 0
fi

EGO_BASE="https://extensions.gnome.org"

# Read the shell state before changing anything. If either query fails, extension
# presence is unknown and the module must not treat that as “not installed”.
if ! installed_all=$(gnome-extensions list 2>/dev/null); then
    echo "Error: could not read the installed GNOME extensions." >&2
    exit 1
fi
if ! enabled_all=$(gnome-extensions list --enabled 2>/dev/null); then
    echo "Error: could not read the enabled GNOME extensions." >&2
    exit 1
fi

list_contains() {
    local list="$1" wanted="$2" line
    while IFS= read -r line; do
        [ "$line" = "$wanted" ] && return 0
    done <<< "$list"
    return 1
}

is_installed() { list_contains "$installed_all" "$1"; }
is_enabled() { list_contains "$enabled_all" "$1"; }

# Re-read the shell state after a change; never trust an exit code alone.
verify_installed() {
    local current
    current=$(gnome-extensions list 2>/dev/null) || return 2
    list_contains "$current" "$1"
}
verify_enabled() {
    local current
    current=$(gnome-extensions list --enabled 2>/dev/null) || return 2
    list_contains "$current" "$1"
}

# parse_ego_response <major>: read an extension-info JSON document on stdin and
# print "<compatible 0|1>\t<download_url>". Compatible is 1 only when the
# declared shell_version_map contains the detected major; a download_url alone
# does not prove compatibility. Exits nonzero on malformed JSON.
parse_ego_response() {
    python3 -c '
import json, sys
major = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(3)
if not isinstance(data, dict):
    sys.exit(3)
svm = data.get("shell_version_map") or {}
if not isinstance(svm, dict):
    sys.exit(3)
url = data.get("download_url") or ""
print(("1" if major in svm else "0") + "\t" + str(url))
' "$1"
}

tmp_dir=""
cleanup_tmp() {
    if [ -n "$tmp_dir" ] && [ -d "$tmp_dir" ]; then
        rm -rf "$tmp_dir"
    fi
}
trap cleanup_tmp EXIT

echo "GNOME Shell $shell_major detected; managing ${#extensions[@]} extensions."

failures=()
skips=()
seen_uuids=()
for uuid in "${extensions[@]}"; do
    if [[ " ${seen_uuids[*]} " == *" $uuid "* ]]; then
        echo "$uuid is duplicated in the configuration; skipping the duplicate entry."
        continue
    fi
    seen_uuids+=("$uuid")

    if is_enabled "$uuid"; then
        echo "$uuid is already installed and enabled."
        skips+=("$uuid: already installed and enabled")
        continue
    fi

    if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
        if is_installed "$uuid"; then
            echo "would run: gnome-extensions enable $uuid"
        else
            echo "would run: curl -fsSL $EGO_BASE/extension-info/?uuid=$uuid&shell_version=$shell_major, then gnome-extensions install --force <downloaded zip>, then gnome-extensions enable $uuid"
        fi
        continue
    fi

    if ! is_installed "$uuid"; then
        if ! command -v curl >/dev/null 2>&1; then
            echo "Error: curl is required to download GNOME extension $uuid." >&2
            failures+=("$uuid: curl is unavailable")
            continue
        fi
        if ! response=$(curl -fsS "$EGO_BASE/extension-info/?uuid=$uuid&shell_version=$shell_major"); then
            echo "Error: failed to fetch extension info for $uuid from extensions.gnome.org." >&2
            failures+=("$uuid: extension metadata download failed")
            continue
        fi
        if ! parsed=$(printf '%s' "$response" | parse_ego_response "$shell_major"); then
            echo "Error: extensions.gnome.org returned unreadable data for $uuid." >&2
            failures+=("$uuid: extension metadata was invalid")
            continue
        fi
        IFS=$'\t' read -r compatible download_url <<< "$parsed"
        if [ "$compatible" != "1" ]; then
            echo "Error: $uuid has no release compatible with GNOME Shell $shell_major." >&2
            failures+=("$uuid: no compatible release")
            continue
        fi
        if [ -z "$download_url" ]; then
            echo "Error: extensions.gnome.org provided no download URL for $uuid." >&2
            failures+=("$uuid: metadata omitted the download URL")
            continue
        fi
        if [ -z "$tmp_dir" ] && ! tmp_dir=$(mktemp -d); then
            echo "Error: failed to create a temporary download directory for $uuid." >&2
            failures+=("$uuid: temporary directory creation failed")
            continue
        fi
        bundle="$tmp_dir/$uuid.shell-extension.zip"
        if ! run curl -fsSL "$EGO_BASE$download_url" -o "$bundle"; then
            echo "Error: failed to download $uuid." >&2
            failures+=("$uuid: extension download failed")
            continue
        fi
        if ! run gnome-extensions install --force "$bundle"; then
            echo "Error: failed to install $uuid." >&2
            failures+=("$uuid: extension installation failed")
            continue
        fi
        if verify_installed "$uuid"; then
            installed_all+=$'\n'"$uuid"
            echo "$uuid installed."
        else
            verify_rc=$?
            if [ "$verify_rc" -eq 2 ]; then
                echo "Error: could not verify whether $uuid was installed." >&2
                failures+=("$uuid: installed state could not be queried")
            else
                echo "Error: $uuid was downloaded but is not installed." >&2
                failures+=("$uuid: post-install verification failed")
            fi
            continue
        fi
    fi

    if ! run gnome-extensions enable "$uuid"; then
        echo "Error: failed to enable $uuid." >&2
        failures+=("$uuid: enable command failed")
        continue
    fi
    if verify_enabled "$uuid"; then
        enabled_all+=$'\n'"$uuid"
    else
        verify_rc=$?
        if [ "$verify_rc" -eq 2 ]; then
            echo "Error: could not verify whether $uuid was enabled." >&2
            failures+=("$uuid: enabled state could not be queried")
        else
            echo "Error: $uuid is installed but could not be enabled." >&2
            failures+=("$uuid: enable verification failed")
        fi
        continue
    fi

    if ! extension_info=$(gnome-extensions info "$uuid" 2>/dev/null); then
        echo "Error: could not verify the final state of $uuid." >&2
        failures+=("$uuid: final-state query failed")
        continue
    fi
    extension_state=""
    while IFS= read -r info_line; do
        case "$info_line" in
            *State:*) extension_state="${info_line#*State:}"; extension_state="${extension_state#${extension_state%%[![:space:]]*}}" ;;
        esac
    done <<< "$extension_info"
    if [ "$extension_state" = "OUT OF DATE" ]; then
        echo "Error: $uuid is out of date for GNOME Shell $shell_major." >&2
        failures+=("$uuid: installed release is out of date")
        continue
    fi
    echo "$uuid enabled."
done

if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
    echo "GNOME extension dry-run complete; no changes made."
elif [ "${#failures[@]}" -gt 0 ]; then
    echo "GNOME extension setup incomplete: ${#failures[@]} failure(s); remaining extensions were still attempted." >&2
    for failure in "${failures[@]}"; do echo "  FAILED: $failure" >&2; done
    exit 1
else
    echo "GNOME extensions are up to date."
fi
