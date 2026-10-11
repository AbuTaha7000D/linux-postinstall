#!/bin/bash
# Add custom GNOME shortcuts from config/shortcuts.txt
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# ensure we have GNOME + gsettings
if ! command -v gsettings >/dev/null 2>&1 || [ "$(desktop_environment)" != "gnome" ]; then
    echo "This script requires GNOME and gsettings. Skipping custom shortcut setup."
    exit 0
fi

# load_shortcuts <file> <names-ref> <bindings-ref> <commands-ref>:
# load config/shortcuts.txt into three parallel arrays. One shortcut per line,
# three tab-separated fields (name, keybinding, command); blank lines and text
# after '#' are ignored and surrounding whitespace is trimmed. Mirrors the
# cfg_load_list convention: a missing or unreadable file is fatal, and a data
# line without exactly three non-empty fields is fatal (naming the file and
# line). The file is only ever read, never written.
load_shortcuts() {
    local file="$1"
    local -n _names="$2" _bindings="$3" _commands="$4"
    if [ ! -f "$file" ]; then
        echo "Error: required config file not found: $file" >&2
        exit 1
    fi
    if [ ! -r "$file" ]; then
        echo "Error: required config file is not readable: $file" >&2
        exit 1
    fi
    _names=(); _bindings=(); _commands=()
    local lineno=0 line
    while IFS= read -r line || [ -n "$line" ]; do
        lineno=$((lineno + 1))
        line="${line%%#*}"
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue

        # Split on literal tabs so empty or trailing columns are not collapsed
        # as they would be when tab is used as IFS whitespace with read -a.
        if [[ "$line" != *$'\t'* ]]; then
            echo "Error: $file line $lineno: expected 3 tab-separated fields (name, keybinding, command)" >&2
            exit 1
        fi
        local name="${line%%$'\t'*}" remainder="${line#*$'\t'}" binding command
        if [[ "$remainder" != *$'\t'* ]]; then
            echo "Error: $file line $lineno: expected 3 tab-separated fields (name, keybinding, command)" >&2
            exit 1
        fi
        binding="${remainder%%$'\t'*}"
        command="${remainder#*$'\t'}"
        if [[ "$command" == *$'\t'* ]]; then
            echo "Error: $file line $lineno: expected 3 tab-separated fields (name, keybinding, command)" >&2
            exit 1
        fi
        name="${name#"${name%%[![:space:]]*}"}"; name="${name%"${name##*[![:space:]]}"}"
        binding="${binding#"${binding%%[![:space:]]*}"}"; binding="${binding%"${binding##*[![:space:]]}"}"
        command="${command#"${command%%[![:space:]]*}"}"; command="${command%"${command##*[![:space:]]}"}"
        if [ -z "$name" ] || [ -z "$binding" ] || [ -z "$command" ]; then
            echo "Error: $file line $lineno: name, keybinding, and command must all be non-empty" >&2
            exit 1
        fi
        _names+=("$name"); _bindings+=("$binding"); _commands+=("$command")
    done < "$file"
    return 0
}

add_shortcut() {
    local name="$1"
    local command="$2"
    local binding="$3"
    local current_bindings remaining_bindings custom_binding next_index=0 new_binding new_path
    local existing_name existing_command existing_binding updated_bindings base_bindings
    local root_path="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings"
    local schema="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding"
    local -a existing_bindings=()
    local -A used_indices=()

    if ! current_bindings=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings); then
        echo "Error: could not read the current custom keybindings." >&2
        return 1
    fi
    remaining_bindings="$current_bindings"
    while [[ "$remaining_bindings" =~ custom([0-9]+) ]]; do
        existing_bindings+=("${BASH_REMATCH[0]}")
        used_indices["${BASH_REMATCH[1]}"]=1
        remaining_bindings="${remaining_bindings#*"${BASH_REMATCH[0]}"}"
    done

    for custom_binding in "${existing_bindings[@]}"; do
        local existing_path="$root_path/$custom_binding/"
        if ! existing_name=$(gsettings get "$schema:$existing_path" name) ||
            ! existing_command=$(gsettings get "$schema:$existing_path" command) ||
            ! existing_binding=$(gsettings get "$schema:$existing_path" binding); then
            echo "Error: could not inspect existing GNOME shortcut $custom_binding." >&2
            return 1
        fi
        existing_name="${existing_name#\'}"; existing_name="${existing_name%\'}"
        existing_command="${existing_command#\'}"; existing_command="${existing_command%\'}"
        existing_binding="${existing_binding#\'}"; existing_binding="${existing_binding%\'}"
        if [[ "$existing_name" == "$name" ]] || [[ "$existing_command" == "$command" ]] || [[ "$existing_binding" == "$binding" ]]; then
            echo "Shortcut with name, command, or binding already exists, skipping."
            return 0
        fi
    done

    while [ -n "${used_indices[$next_index]:-}" ]; do
        next_index=$((next_index + 1))
    done
    new_binding="custom$next_index"
    new_path="$root_path/$new_binding/"

    # Configure the relocatable shortcut before publishing its path in the
    # active keybinding list, so failed property writes do not leave a broken
    # entry in custom-keybindings.
    if ! run gsettings set "$schema:$new_path" name "$name"; then
        echo "Error setting the name for shortcut: $name" >&2
        return 1
    fi
    if ! run gsettings set "$schema:$new_path" command "$command"; then
        echo "Error setting the command for shortcut: $name" >&2
        return 1
    fi
    if ! run gsettings set "$schema:$new_path" binding "$binding"; then
        echo "Error setting the keybinding for shortcut: $name" >&2
        return 1
    fi

    if [[ "$current_bindings" == "@as []" || "$current_bindings" == "[]" ]]; then
        updated_bindings="['$new_path']"
    else
        if [[ "$current_bindings" == "@as "* ]]; then
            base_bindings="${current_bindings#@as }"
        else
            base_bindings="$current_bindings"
        fi
        updated_bindings="${base_bindings%]}, '$new_path']"
    fi
    if ! run gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$updated_bindings"; then
        echo "Error registering shortcut: $name" >&2
        return 1
    fi
}

config_file="$SCRIPT_DIR/config/shortcuts.txt"
load_shortcuts "$config_file" names bindings commands

if [ "${#names[@]}" -eq 0 ]; then
    echo "No shortcuts listed in $config_file; skipping."
    exit 0
fi

if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
    names_list=$(printf '%s, ' "${names[@]}")
    echo "would run: add GNOME custom shortcuts (${names_list%, }) via gsettings"
    exit 0
fi

failures=0
for i in "${!names[@]}"; do
    if ! add_shortcut "${names[$i]}" "${commands[$i]}" "${bindings[$i]}"; then
        echo "Error adding shortcut: ${names[$i]}" >&2
        failures=$((failures + 1))
    fi
done

if [ "$failures" -gt 0 ]; then
    echo "Shortcut setup incomplete: $failures shortcut(s) failed; remaining entries were still attempted." >&2
    exit 1
fi
echo "Shortcuts added or already present."
