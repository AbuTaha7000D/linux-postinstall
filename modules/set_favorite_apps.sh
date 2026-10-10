#!/bin/bash
# Set favorite apps in the GNOME dock from config/favorites.txt
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# --- helpers ---
log() { echo "$*"; }
warn() { echo "[warn] $*" >&2; }

# ensure we have GNOME + gsettings
if ! command -v gsettings >/dev/null 2>&1 || [ "$(desktop_environment)" != "gnome" ]; then
	log "This script requires GNOME and gsettings. Skipping favorite apps setup."
	exit 0
fi

# cfg_load_list <file> <array-name>: load a required list file into <array>.
# One entry per line; blank lines and text after '#' are ignored. Mirrors the
# install_apps.sh/gnome_extensions.sh convention; a missing or unreadable list
# is fatal. The file is only ever read, never written.
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

# Print the XDG application directories to search, one per line. Uses the XDG
# data dirs (each contributing an 'applications' subdirectory) plus the Flatpak
# and Snap exports for environments where those are not already on XDG_DATA_DIRS.
desktop_directories() {
	local d ifs_bak="$IFS" dirs
	printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/applications"
	dirs="${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
	local IFS=':'
	for d in $dirs; do
		[ -n "$d" ] && printf '%s\n' "${d%/}/applications"
	done
	IFS="$ifs_bak"
	printf '%s\n' \
		"$HOME/.local/share/flatpak/exports/share/applications" \
		"/var/lib/flatpak/exports/share/applications" \
		"/var/lib/snapd/desktop/applications"
}

# An app is pinnable iff its desktop file exists by exact name in one of the
# application directories. No package-manager probing and no fuzzy matching.
desktop_entry_exists() {
	local id="$1" dir
	while IFS= read -r dir; do
		[ -n "$dir" ] || continue
		if [ -f "$dir/$id" ]; then
			return 0
		fi
	done < <(desktop_directories)
	return 1
}

config_file="$SCRIPT_DIR/config/favorites.txt"
cfg_load_list "$config_file" favorites

if [ "${#favorites[@]}" -eq 0 ]; then
	log "No favorite apps listed in $config_file; skipping."
	exit 0
fi

# Build the filtered, de-duplicated list preserving configured order. Entries
# missing a desktop file are warned about and skipped, never removed from config.
available=()
seen=""
for entry in "${favorites[@]}"; do
	case "$entry" in
		*.desktop) id="$entry" ;;
		*) id="${entry}.desktop" ;;
	esac
	if printf '%s\n' "$seen" | grep -Fqx "$id"; then
		continue
	fi
	seen=$(printf '%s\n%s' "$seen" "$id")
	if desktop_entry_exists "$id"; then
		available+=("$id")
	else
		warn "Skipping '$id': no matching desktop entry found."
	fi
done

# An empty result must not clear or change the Dock.
if [ "${#available[@]}" -eq 0 ]; then
	warn "No configured favorite apps are available. Leaving the dock unchanged."
	exit 0
fi

# Build the gsettings value: a quoted array of the available IDs.
gsettings_value="["
for i in "${!available[@]}"; do
	gsettings_value+="'${available[$i]}'"
	if [ "$i" -lt $((${#available[@]} - 1)) ]; then
		gsettings_value+=", "
	fi
done
gsettings_value+="]"

# Dry-run: report the planned change and stop. Nothing is read or written.
if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
	run gsettings set org.gnome.shell favorite-apps "$gsettings_value"
	exit 0
fi

# Idempotency: skip the write when the Dock already matches the filtered list.
current=$(gsettings get org.gnome.shell favorite-apps 2>/dev/null || true)
current_ids=()
if [ -n "$current" ]; then
	while IFS= read -r cid; do
		[ -n "$cid" ] && current_ids+=("$cid")
	done < <(printf '%s' "$current" | grep -o "'[^']*'" | tr -d "'")
fi
if [ "${#current_ids[@]}" -eq "${#available[@]}" ]; then
	same=1
	for i in "${!available[@]}"; do
		if [ "${current_ids[$i]}" != "${available[$i]}" ]; then
			same=0
			break
		fi
	done
	if [ "$same" = "1" ]; then
		log "Favorite apps are already set. Nothing to do."
		exit 0
	fi
fi

if ! run gsettings set org.gnome.shell favorite-apps "$gsettings_value"; then
	warn "Error setting favorite apps in the dock"
	exit 1
fi

log "Favorite apps set successfully!"
