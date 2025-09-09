#!/bin/bash
# Set favorite apps in the GNOME dock

# safer bash
set -uo pipefail

# --- helpers ---
log() { echo "$*"; }
warn() { echo "[warn] $*" >&2; }

# ensure we have GNOME + gsettings
if ! command -v gsettings >/dev/null 2>&1 || [[ ! ${XDG_CURRENT_DESKTOP:-} =~ (GNOME|Unity) ]]; then
	log "This script requires GNOME and gsettings. Skipping favorite apps setup."
	exit 0
fi

log "Setting favorite apps in the dock..."

# 1) simple app names (case-insensitive matching)
app_names=(
	'gnome.Nautilus'
	'code'
	'firefox'
	'zapzap'
	'chrome'
	'bitwarden'
	'spotify'
	'strawberry'
	'Discord'
	'Thunderbird'
)

# search locations
xdg_local_apps="$HOME/.local/share/applications"
usr_apps="/usr/share/applications"
usr_local_apps="/usr/local/share/applications"
flatpak_apps_user="$HOME/.local/share/flatpak/exports/share/applications"
flatpak_apps_system="/var/lib/flatpak/exports/share/applications"
snap_apps="/var/lib/snapd/desktop/applications"

# Only primary search paths as requested (used first)
primary_search_dirs=(
	"$usr_apps"
	"/usr/local/share/applications"
	"$xdg_local_apps"
)

# Additional sources used when resolving Flatpak/Snap desktop files
extra_search_dirs=(
	"$flatpak_apps_user"
	"$flatpak_apps_system"
	"$snap_apps"
)

# Return first matching .desktop file path (case-insensitive) within provided dirs
find_desktop_in_dirs_ci() {
	local query="$1"; shift
	local dir
	for dir in "$@"; do
		[ -d "$dir" ] || continue
		# find first match, case-insensitive, not following symlinks recursion is fine at maxdepth 1
		local match
		match=$(find "$dir" -maxdepth 1 -type f -iname "*${query}*.desktop" 2>/dev/null | head -n1 || true)
		if [ -n "$match" ]; then
			echo "$match"
			return 0
		fi
	done
	return 1
}

# Resolve a simple name to a .desktop filename
resolve_desktop_filename() {
	local name="$1"
	local name_lc
	name_lc=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')

	# 1) Try primary search dirs by file name
	local path
	path=$(find_desktop_in_dirs_ci "$name" "${primary_search_dirs[@]}") || true
	if [ -n "$path" ]; then
		basename "$path"
		return 0
	fi

	# 2) Try Flatpak: look up installed app IDs and map to <id>.desktop
	if command -v flatpak >/dev/null 2>&1; then
		local fp_id
		# list application IDs; ignore runtimes; tolerate no installations
		while IFS= read -r fp_id; do
			[ -n "$fp_id" ] || continue
			local fp_id_lc
			fp_id_lc=$(printf '%s' "$fp_id" | tr '[:upper:]' '[:lower:]')
			case "$fp_id_lc" in
				*"$name_lc"*)
					# verify via flatpak info if possible
					if flatpak info "$fp_id" >/dev/null 2>&1; then
						# try to find the actual .desktop from known locations
						local candidate
						candidate=$(find_desktop_in_dirs_ci "$fp_id" "${primary_search_dirs[@]}" "${extra_search_dirs[@]}") || true
						if [ -n "$candidate" ]; then
							basename "$candidate"
							return 0
						fi
						# fallback to <id>.desktop
						printf '%s.desktop\n' "$fp_id"
						return 0
					fi
					;;
			esac
		done < <(flatpak list --app --columns=application 2>/dev/null | awk 'NF>0')
	fi

	# 3) Try Snap: search desktop entries shipped by snapd for matching package
	if command -v snap >/dev/null 2>&1; then
		local snap_pkg
		while IFS= read -r snap_pkg; do
			[ -n "$snap_pkg" ] || continue
			local snap_pkg_lc
			snap_pkg_lc=$(printf '%s' "$snap_pkg" | tr '[:upper:]' '[:lower:]')
			case "$snap_pkg_lc" in
				*"$name_lc"*)
					# snap desktop files usually look like snap.<pkg>.<command>.desktop
					local snap_path
					snap_path=$(find_desktop_in_dirs_ci "$snap_pkg" "$snap_apps") || true
					if [ -n "$snap_path" ]; then
						basename "$snap_path"
						return 0
					fi
					;;
			esac
		done < <(snap list 2>/dev/null | awk 'NR>1{print $1}' | awk 'NF>0')
	fi

	# Not found
	return 1
}

# Build favorites list
favorite_desktops=()
seen_map=""

add_unique_desktop() {
	local desktop="$1"
	# ensure it ends with .desktop
	case "$desktop" in
		*.desktop) ;;
		*) desktop="${desktop}.desktop" ;;
	esac
	# de-duplicate
	if printf '%s\n' "$seen_map" | grep -Fqx "$desktop"; then
		return 0
	fi
	seen_map=$(printf '%s\n%s' "$seen_map" "$desktop")
	favorite_desktops+=("$desktop")
}

for name in "${app_names[@]}"; do
	if desktop_file=$(resolve_desktop_filename "$name"); then
		add_unique_desktop "$desktop_file"
		log "Resolved '$name' -> $desktop_file"
	else
		warn "Could not resolve app name: $name"
	fi
done

# If nothing resolved, do not attempt to set
if [ ${#favorite_desktops[@]} -eq 0 ]; then
	warn "No favorites resolved. Skipping gsettings update."
	exit 0
fi

# Build gsettings value: array of quoted strings
# Example: ['org.gnome.Nautilus.desktop', 'code.desktop']
{
	printf "["
	for i in "${!favorite_desktops[@]}"; do
		printf "'%s'" "${favorite_desktops[$i]}"
		if [ "$i" -lt $((${#favorite_desktops[@]} - 1)) ]; then
			printf ", "
		fi
	done
	printf "]\n"
} | {
	read -r gsettings_value
	if ! gsettings set org.gnome.shell favorite-apps "$gsettings_value"; then
		warn "Error setting favorite apps in the dock"
		exit 1
	fi
}

log "Favorite apps set successfully!"
for i in 3 2 1; do
	printf "\rContinue in %s .. " "$i"
	sleep 1
	done
printf "\n#################### Done! ####################\n"