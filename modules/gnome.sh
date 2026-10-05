#!/usr/bin/env bash
# modules/gnome.sh - GNOME desktop settings.
#
# Every write goes through gsettings, and every one is skipped when the current
# value already matches, so this module is safe to re-run.
#
#   config/extensions.txt  extension uuids to enable (installed ones only)
#   config/favorites.txt   .desktop ids appended to the dock, in order
#   config/shortcuts.txt   "<name>|<command>|<accelerator>" custom keybindings
#   FS_THEME_NAME          GTK theme name (skipped when unset)
#   FS_CURSOR_NAME         cursor theme name (skipped when unset)
#
# Skips cleanly when gsettings is missing, when the session is not GNOME, or
# over SSH. Set FS_GNOME_FORCE=1 to run anyway.

install_gnome() {
    _gnome_ready || {
        log_info "not a GNOME session (or gsettings missing); skipping"
        return 0
    }

    _gnome_favorites
    _gnome_shortcuts
    _gnome_extensions
    _gnome_set org.gnome.desktop.interface gtk-theme "${FS_THEME_NAME:-}"
    _gnome_set org.gnome.desktop.interface cursor-theme "${FS_CURSOR_NAME:-}"
    _gnome_wallpaper
}

_gnome_ready() {
    have gsettings || return 1
    (( ${FS_GNOME_FORCE:-0} )) && return 0
    [[ -z "${SSH_CONNECTION:-}${SSH_TTY:-}" ]] || return 1
    [[ "${XDG_CURRENT_DESKTOP:-}" == *GNOME* ]] || return 1
    return 0
}

_gnome_get() {
    gsettings get "$1" "$2" 2>/dev/null
}

# gsettings prints strings wrapped in single quotes, so compare with and
# without them: a value this module wrote last time reads as unchanged.
_gnome_set() {
    local schema="$1" key="$2" want="$3" have
    [[ -n "$want" ]] || return 0
    have="$(_gnome_get "$schema" "$key")"
    if [[ "$have" == "'$want'" || "$have" == "$want" ]]; then
        log_info "unchanged: $schema $key"
        return 0
    fi
    run "set $key" gsettings set "$schema" "$key" "$want"
}

# Print one item per line. gsettings renders a string array as
# "['a', 'b']", and the empty array as "@as []".
_gnome_strv() {
    local raw
    raw="$(gsettings get "$1" "$2" 2>/dev/null)" || return 0
    [[ "$raw" == "@as []" ]] && return 0
    case "$raw" in
    "["*"]") ;;
    *) return 0 ;;
    esac
    raw="${raw#[}"
    raw="${raw%]}"
    raw="${raw//\'/}"
    raw="${raw//, /$'\n'}"
    printf '%s\n' "$raw"
    return 0
}

_gnome_strv_join() {
    local out="" item
    for item in "$@"; do
        out+="${out:+, }'$item'"
    done
    printf '[%s]' "$out"
}

# Append the configured .desktop ids to the dock, keeping whatever is already
# pinned and the order it is in.
_gnome_favorites() {
    local schema="org.gnome.shell" key="favorite-apps"
    local -a current=() want=() merged=()
    local item have seen

    mapfile -t want < <(read_list "$FS_ROOT/config/favorites.txt")
    mapfile -t current < <(_gnome_strv "$schema" "$key")

    merged=("${current[@]}")
    for item in "${want[@]}"; do
        seen=0
        for have in "${merged[@]}"; do
            if [[ "$have" == "$item" ]]; then seen=1; break; fi
        done
        ((seen)) || merged+=("$item")
    done

    ((${#merged[@]} == ${#current[@]})) && {
        log_info "unchanged: dock favorites"
        return 0
    }
    run "set dock favorites" gsettings set "$schema" "$key" "$(_gnome_strv_join "${merged[@]}")"
}

# Register each shortcut into the first free customN slot. An entry whose
# command is already bound is left alone, so a second run adds nothing.
_gnome_shortcuts() {
    local base="org.gnome.settings-daemon.plugins.media-keys"
    local sub="$base.custom-keybinding"
    local entry name command accel path bound slot=0
    local -a taken=()

    mapfile -t taken < <(_gnome_strv "$base" custom-keybindings)

    while IFS= read -r entry; do
        IFS='|' read -r name command accel <<<"$entry"
        [[ -n "${name:-}" && -n "${command:-}" && -n "${accel:-}" ]] ||
            die "malformed entry in config/shortcuts.txt: $entry"

        bound=""
        for path in "${taken[@]}"; do
            [[ "$(_gnome_get "$sub:$path/" command)" == "'$command'" ]] && bound="$path"
        done
        if [[ -n "$bound" ]]; then
            log_info "unchanged: shortcut $name"
            continue
        fi

        while :; do
            path="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom$slot/"
            slot=$((slot + 1))
            grep -qxF -- "$path" <<<"${taken[*]}" || break
            ((slot > 64)) && die "no free custom-keybinding slot left"
        done
        taken+=("$path")

        run "bind $name (name)" gsettings set "$sub:$path/" name "$name"
        run "bind $name (command)" gsettings set "$sub:$path/" command "$command"
        run "bind $name (accelerator)" gsettings set "$sub:$path/" binding "$accel"
        run "register $name" gsettings set "$base" custom-keybindings \
            "$(_gnome_strv_join "${taken[@]}")"
    done < <(read_list "$FS_ROOT/config/shortcuts.txt")
}

# Enable the configured extension uuids. A uuid whose extension is not
# installed is reported and skipped: installing it is the package manager's
# job (config/packages-gnome.txt), not gsettings'.
_gnome_extensions() {
    have gnome-extensions || {
        log_info "gnome-extensions not installed; skipping extensions"
        return 0
    }
    local uuid
    while IFS= read -r uuid; do
        if gnome-extensions list --enabled 2>/dev/null | grep -qxF "$uuid"; then
            log_info "already enabled: $uuid"
        elif gnome-extensions list --installed 2>/dev/null | grep -qxF "$uuid"; then
            run "enable extension $uuid" gnome-extensions enable "$uuid"
        else
            log_warn "extension not installed, skipping: $uuid"
        fi
    done < <(read_list "$FS_ROOT/config/extensions.txt")
}

_gnome_wallpaper() {
    local dir="${FS_WALLPAPER_DIR:-$FS_ROOT/assets/wallpaper}"
    local schema="org.gnome.desktop.background"
    local file dark

    file="$(find "$dir" -maxdepth 1 -type f -name '*.jpg' -print -quit 2>/dev/null || true)"
    [[ -n "$file" ]] || {
        log_info "no wallpaper in $dir; skipping"
        return 0
    }
    dark="$(find "$dir" -maxdepth 1 -type f -name '*dark*.jpg' -print -quit 2>/dev/null || true)"
    _gnome_set "$schema" picture-uri "file://$file"
    _gnome_set "$schema" picture-uri-dark "file://${dark:-$file}"
}
