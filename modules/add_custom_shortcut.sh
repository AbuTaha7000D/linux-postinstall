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
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [ -z "$line" ] && continue
        local IFS=$'\t'
        local -a fields=()
        read -r -a fields <<< "$line"
        if [ "${#fields[@]}" -ne 3 ]; then
            echo "Error: $file line $lineno: expected 3 tab-separated fields (name, keybinding, command), got ${#fields[@]}" >&2
            exit 1
        fi
        local name="${fields[0]}" binding="${fields[1]}" command="${fields[2]}"
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
    current_bindings=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)
    new_binding="custom$(echo "$current_bindings" | grep -o 'custom[0-9]*' | sed 's/custom//' | sort -n | tail -n 1 | awk '{print $1+1}')"
    [ -z "$new_binding" ] && new_binding="custom0"
    if [[ "$current_bindings" != "@as []" ]]; then
        existing_bindings=$(echo "$current_bindings" | grep -o 'custom[0-9]*')
        for custom_binding in $existing_bindings; do
            existing_name=$(gsettings get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/$custom_binding/ name | sed "s/'//g")
            existing_command=$(gsettings get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/$custom_binding/ command | sed "s/'//g")
            existing_binding=$(gsettings get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/$custom_binding/ binding | sed "s/'//g")
            if [[ "$existing_name" == "$name" ]] || [[ "$existing_command" == "$command" ]] || [[ "$existing_binding" == "$binding" ]]; then
                echo "Shortcut with name, command, or binding already exists, skipping."
                return 0
            fi
        done
    fi
    if [[ "$current_bindings" == "@as []" ]]; then
        run gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "['/$new_binding/']"
    else
        updated_bindings=$(echo "$current_bindings" | sed "s/]$/, '\/\$new_binding\/'']/")
        run gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$updated_bindings"
    fi
    run gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/$new_binding/ name "$name"
    run gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/$new_binding/ command "$command"
    if ! run gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/$new_binding/ binding "$binding"; then
        echo "Error creating shortcut: $name"
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

for i in "${!names[@]}"; do
    if ! add_shortcut "${names[$i]}" "${commands[$i]}" "${bindings[$i]}"; then
        echo "Error adding shortcut: ${names[$i]}" >&2
        exit 1
    fi
done

echo "Shortcuts added successfully."
