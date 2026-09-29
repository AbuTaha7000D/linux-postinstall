#!/usr/bin/env bash
# modules/gnome-base/hooks.sh - GNOME base configuration (P6.2).
# Sourced INSIDE the runner's hook subshell (lib/runner.sh stage 4); run()
# is called once. The runner provides io_*/run_cmd + FS_* seams; this hook
# sources lib/gnome.sh (gsettings layer) and lib/lists.sh (favorites.list
# parsing) itself. Every write goes through run_cmd (gnome_gsettings_set/
# gnome_strv_merge_set), so dry-run renders exact `# would run:` lines and
# never probes, and real runs are audited.
#
# run() guards the module like the prototype did, plus a validation seam:
# gnome_require_capable (P6.5) decides -- a non-GNOME session (XDG_CURRENT_
# DESKTOP not matching *GNOME*), an SSH/headless context, or no gsettings on
# PATH all mean graceful skip (io_info "skipped (not GNOME)", rc0, nothing
# probed); --force (FS_GNOME_FORCE=1) overrides the skip and runs anyway.
# A non-absolute FS_WALLPAPER_ASSETS_DIR fails closed (io_error, rc1) before
# anything else runs. Then, in order:
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
    local root wdir
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || return 1
    source "$root/lib/gnome.sh"
    gnome_require_capable gnome-base || return 0
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

# verify() is the P6.5 read-only diagnostic (wired to `./setup verify` in
# P9.2): it re-gates, refuses to run in dry-run (verification reads probe
# dconf), then checks that the actual gsettings state matches what run()
# would apply -- every curated dock favorite is present in favorite-apps,
# every curated shortcut command signature is registered in custom-keybindings,
# and the wallpaper URI matches the picked asset (when a wallpaper dir with
# an image exists). Each check reports io_info on success or io_error on
# mismatch; rc1 when anything is missing, else io_info "verify passed".
verify() {
    local root rc=0
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || return 1
    source "$root/lib/gnome.sh"
    source "$root/lib/lists.sh"
    gnome_require_capable gnome-base || return 0
    if (( FS_DRY_RUN == 1 )); then
        io_info "gnome-base: verify is read-only; runs only in real mode"
        return 0
    fi
    _gnome_base_verify_favs "$root" || rc=1
    _gnome_base_verify_shortcuts "$root" || rc=1
    _gnome_base_verify_wallpaper "$root" || rc=1
    if (( rc == 0 )); then
        io_info "gnome-base: verify passed"
    fi
    return "$rc"
}

_gnome_base_verify_favs() {
    local root="$1" dir="$root/modules/gnome-base" fav="" e=""
    local rc=0 n=0 seen=0 out=""
    local -a want=() cur=()
    out="$(list_parse "$dir/favorites.list")" || return 1
    if [[ -n "$out" ]]; then
        while IFS= read -r fav; do
            want+=("$fav")
        done <<<"$out"
    fi
    if (( ${#want[@]} == 0 )); then
        io_info "gnome-base: verify: favorites.list empty; nothing to verify"
        return 0
    fi
    out="$(gnome_gsettings_get org.gnome.shell favorite-apps)" || return 1
    if [[ "$out" != "@as []" && "$out" != "[]" ]]; then
        while IFS= read -r e; do
            cur+=("$e")
        done <<<"$(gnome_strv_parse "$out")"
    fi
    for (( n = 0; n < ${#want[@]}; n++ )); do
        fav="${want[$n]}"
        seen=0
        for e in "${cur[@]}"; do
            if [[ "$e" == "$fav" ]]; then
                seen=1
                break
            fi
        done
        if (( seen == 0 )); then
            io_error "gnome-base: verify FAILED: dock favorite not applied: $fav"
            rc=1
        else
            io_info "gnome-base: verify ok: dock favorite present: $fav"
        fi
    done
    return "$rc"
}

_gnome_base_verify_shortcuts() {
    local root="$1" dir="$root/modules/gnome-base"
    local base="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"
    local array_path="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings"
    local array_schema="org.gnome.settings-daemon.plugins.media-keys"
    local line="" name="" command="" binding="" parsed="" p="" cmd="" sig="" out=""
    local -a want=()
    local -A seen=()
    local rc=0 n=0 i=0
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
        want+=("${command//\'/}")
    done <"$dir/shortcuts.list"
    if (( ${#want[@]} == 0 )); then
        io_info "gnome-base: verify: shortcuts.list empty; nothing to verify"
        return 0
    fi
    out="$(gnome_gsettings_get "$array_schema" custom-keybindings)" || return 1
    if [[ -n "$out" && "$out" != "@as []" && "$out" != "[]" ]]; then
        parsed="$(gnome_strv_parse "$out")" || return 1
        if [[ -n "$parsed" ]]; then
            while IFS= read -r p; do
                case "$p" in
                    "$array_path"/custom[0-9]*/)
                        i=0
                        cmd="$(gnome_gsettings_get "$base$p" command)" || i=$?
                        if (( i == 0 )); then
                            seen["${cmd//\'/}"]=1
                        fi
                        ;;
                esac
            done <<<"$parsed"
        fi
    fi
    for (( n = 0; n < ${#want[@]}; n++ )); do
        sig="${want[$n]}"
        if [[ -n "${seen[$sig]:-}" ]]; then
            io_info "gnome-base: verify ok: shortcut registered: $sig"
        else
            io_error "gnome-base: verify FAILED: shortcut not applied: $sig"
            rc=1
        fi
    done
    return "$rc"
}

_gnome_base_verify_wallpaper() {
    local root="$1" dir="${FS_WALLPAPER_ASSETS_DIR:-$root/assets/wallpaper}" img="" f="" uri="" cur="" rc=0
    if [[ ! -d "$dir" ]]; then
        io_info "gnome-base: verify: no wallpaper asset dir; nothing to verify"
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
        io_info "gnome-base: verify: no wallpaper image; nothing to verify"
        return 0
    fi
    uri="file://$img"
    cur="$(gnome_gsettings_get org.gnome.desktop.background picture-uri)" || rc=1
    if (( rc == 0 )); then
        if [[ "$cur" == "$uri" || "$cur" == "'$uri'" ]]; then
            io_info "gnome-base: verify ok: wallpaper picture-uri set"
        else
            io_error "gnome-base: verify FAILED: wallpaper picture-uri ($cur != $uri)"
            rc=1
        fi
    fi
    cur="$(gnome_gsettings_get org.gnome.desktop.background picture-uri-dark)" || rc=1
    if (( rc == 0 )); then
        if [[ "$cur" == "$uri" || "$cur" == "'$uri'" ]]; then
            io_info "gnome-base: verify ok: wallpaper picture-uri-dark set"
        else
            io_error "gnome-base: verify FAILED: wallpaper picture-uri-dark ($cur != $uri)"
            rc=1
        fi
    fi
    return "$rc"
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