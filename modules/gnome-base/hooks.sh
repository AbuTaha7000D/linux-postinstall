#!/usr/bin/env bash
# modules/gnome-base/hooks.sh - GNOME base configuration (P6.2).
# Sourced INSIDE the runner's hook subshell (lib/runner.sh stage 4); run()
# is called once. The runner provides io_*/run_cmd + FS_* seams; this hook
# sources lib/gnome.sh (gsettings layer) and lib/lists.sh (favorites.list
# parsing) itself. Every write goes through run_cmd (gnome_gsettings_set/
# gnome_strv_merge_set), so dry-run renders exact `# would run:` lines and
# never probes, and real runs are audited.
#
# run() guards the module exactly like the prototype did, plus a validation
# seam: no GNOME session (XDG_CURRENT_DESKTOP not matching *GNOME*) means
# graceful skip (io_info, rc0); no gsettings on PATH or a non-absolute
# FS_WALLPAPER_ASSETS_DIR means fail-closed (io_error, rc1) before anything
# else runs. Then, in order:
#   1. Favorites -- gnome_strv_merge_set org.gnome.shell favorite-apps
#      reads the current array, appends the curated favorites.list ids that
#      are missing (first-seen dedupe, existing order preserved) and writes
#      the merged array back; an idempotent run writes nothing.
#   2. Shortcuts -- each shortcuts.list entry (name|command|binding) is
#      registered as a media-keys custom keybinding WITHOUT clobbering user
#      bindings and in a fully idempotent way. Real mode reads the current
#      custom-keybindings array, records the numeric sibling ids that are
#      taken and the command of every registered binding, then walks the
#      curated list: an entry whose command already matches a registered
#      binding is skipped (io_info) -- never re-added, never overwritten --
#      and the remaining entries are written into the first free customN
#      slot (prototype bug #4 fix: allocation replaces the sed-based array
#      rewriting; first-free means a user's custom0..N bindings are never
#      touched). Dry-run cannot probe, so it plans slot-by-slot from
#      custom0 with the curated-only array (an approximation of the merge,
#      same convention as gnome_strv_merge_set). Slot allocation and the
#      array merge both go through gnome.sh, so the P6.1 keybindings merge
#      is the single writer of custom-keybindings. Curated duplicates
#      (same command, first-seen wins) collapse at parse time, mirroring
#      list_parse's dedupe so dry and real modes agree. Malformed lines
#      (not name|command|binding) fail rc1 before any write.
#   3. Wallpaper -- when FS_WALLPAPER_ASSETS_DIR (must be absolute if set;
#      default $root/assets/wallpaper) holds at least one regular file
#      *.jpg/*.jpeg/*.png/*.webp, apply its file:// URI to picture-uri and
#      picture-uri-dark; otherwise skip with io_info and no plan line. The
#      first regular-file match in sorted order wins (directories and
#      dangling names are ignored).
# Shortcut name/command/binding validation is delegated to
# gnome_gsettings_set's own GVariant value checks (control bytes /
# non-printable -> rc1), so a corrupt shortcuts.list fails loudly before
# any write.

run() {
    local root desktop wdir
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || return 1
    source "$root/lib/gnome.sh"
    desktop="${XDG_CURRENT_DESKTOP:-}"
    case "$desktop" in
        *GNOME*) ;;
        *) io_info "gnome-base: no GNOME session (XDG_CURRENT_DESKTOP='${desktop:-unset}'); skipping"
           return 0 ;;
    esac
    if ! gnome_gsettings_available; then
        io_error "gnome-base: gsettings not found on PATH"
        return 1
    fi
    wdir="${FS_WALLPAPER_ASSETS_DIR:-}"
    if [[ -n "$wdir" && "$wdir" != /* ]]; then
        io_error "gnome-base: FS_WALLPAPER_ASSETS_DIR must be absolute: $wdir"
        return 1
    fi
    source "$root/lib/lists.sh"
    _gnome_base_favorites "$root" || return 1
    _gnome_base_shortcuts "$root" || return 1
    _gnome_base_wallpaper "$root" || return 1
    return 0
}

_gnome_base_favorites() {
    local root="$1" dir="$root/modules/gnome-base" favs=() fav="" out=""
    out="$(list_parse "$dir/favorites.list")" || return 1
    if [[ -n "$out" ]]; then
        while IFS= read -r fav; do
            favs+=("$fav")
        done <<<"$out"
    fi
    if (( ${#favs[@]} == 0 )); then
        io_info "gnome-base: favorites.list has no entries; dock untouched"
        return 0
    fi
    gnome_strv_merge_set org.gnome.shell favorite-apps "${favs[@]}" || return 1
}

_gnome_base_shortcuts() {
    local root="$1" dir="$root/modules/gnome-base"
    local base="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"
    local array_path="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings"
    local array_schema="org.gnome.settings-daemon.plugins.media-keys"
    local line="" name="" command="" binding="" p="" idx="" cmd="" out="" parsed="" rc=0 sig=""
    local -a paths=() dname=() dcmd=() dbind=()
    local -A dseen=()
    local -i n=0 i=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        case "$line" in
            "" | \#*) continue ;;
        esac
        name="${line%%|*}"
        command="${line#*|}"
        command="${command%%|*}"
        binding="${line##*|}"
        if [[ -z "$name" || -z "$command" || -z "$binding" || "$line" != *\|*\|* ]]; then
            io_error "gnome-base: malformed shortcuts.list line: $line"
            return 1
        fi
        sig="${command//\'/}"
        if [[ -n "${dseen[$sig]:-}" ]]; then
            io_info "gnome-base: duplicate shortcut command ($command); first entry wins"
            continue
        fi
        dseen[$sig]=1
        dname+=("$name")
        dcmd+=("$command")
        dbind+=("$binding")
    done <"$dir/shortcuts.list"
    if (( FS_DRY_RUN == 1 )); then
        for (( n = 0; n < ${#dname[@]}; n++ )); do
            idx="$array_path/custom$n/"
            paths+=("$idx")
            gnome_gsettings_set "$base$idx" name "'${dname[$n]}'" || return 1
            gnome_gsettings_set "$base$idx" command "'${dcmd[$n]}'" || return 1
            gnome_gsettings_set "$base$idx" binding "'${dbind[$n]}'" || return 1
        done
        if (( ${#paths[@]} > 0 )); then
            gnome_custom_keybindings_merge_add "${paths[@]}" || return 1
        fi
        return 0
    fi
    local -A taken=() seen=()
    rc=0
    out="$(gnome_gsettings_get "$array_schema" custom-keybindings)" || return 1
    if [[ -n "$out" ]]; then
        parsed="$(gnome_strv_parse "$out")" || return 1
        if [[ -n "$parsed" ]]; then
            while IFS= read -r p; do
                case "$p" in
                    "$array_path"/custom[0-9]*/)
                        idx="${p#$array_path/custom}"
                        idx="${idx%/}"
                        case "$idx" in
                            *[!0-9]*) continue ;;
                        esac
                        taken[$idx]=1
                        rc=0
                        cmd="$(gnome_gsettings_get "$base$p" command)" || rc=$?
                        if (( rc == 0 )); then
                            seen["${cmd//\'/}"]=1
                        fi
                        ;;
                esac
            done <<<"$parsed"
        fi
    fi
    for (( n = 0; n < ${#dname[@]}; n++ )); do
        if [[ -n "${seen[${dcmd[$n]//\'/}]:-}" ]]; then
            io_info "gnome-base: shortcut already registered (${dcmd[$n]}); skipping"
            continue
        fi
        i=0
        while [[ -n "${taken[$i]:-}" ]]; do
            i+=1
        done
        taken[$i]=1
        seen["${dcmd[$n]//\'/}"]=1
        idx="$array_path/custom$i/"
        paths+=("$idx")
        gnome_gsettings_set "$base$idx" name "'${dname[$n]}'" || return 1
        gnome_gsettings_set "$base$idx" command "'${dcmd[$n]}'" || return 1
        gnome_gsettings_set "$base$idx" binding "'${dbind[$n]}'" || return 1
    done
    if (( ${#paths[@]} > 0 )); then
        gnome_custom_keybindings_merge_add "${paths[@]}" || return 1
    fi
    return 0
}

_gnome_base_wallpaper() {
    local root="$1" dir="${FS_WALLPAPER_ASSETS_DIR:-$root/assets/wallpaper}" img="" uri="" f=""
    if [[ ! -d "$dir" ]]; then
        io_info "gnome-base: no wallpaper asset dir; wallpaper untouched"
        return 0
    fi
    for f in "$dir"/*; do
        case "$f" in
            *.jpg|*.jpeg|*.png|*.webp)
                [[ -f "$f" ]] && { img="$f"; break; }
                ;;
        esac
    done
    if [[ -z "$img" ]]; then
        io_info "gnome-base: no wallpaper image in $dir; wallpaper untouched"
        return 0
    fi
    uri="file://$img"
    gnome_gsettings_set org.gnome.desktop.background picture-uri "$uri" || return 1
    gnome_gsettings_set org.gnome.desktop.background picture-uri-dark "$uri" || return 1
}