#!/usr/bin/env bash
# modules/fonts.sh - Nerd Fonts.
#
# config/fonts.txt lists one font per line as "<label> <NerdFontAsset> <version>",
# for example:
#
#   FiraCode FiraCode v3.3.0
#
# Each entry is a pinned release zip from ryanoasis/nerd-fonts, verified
# against the digest pinned in config/fonts.sha256 and extracted into
# ~/.local/share/fonts. An entry whose files are already in place is skipped.

install_fonts() {
    local fonts_dir="${FS_FONTS_DIR:-$HOME/.local/share/fonts}"
    local entry label asset ver want tmp fresh=0

    run "create fonts dir" mkdir -p "$fonts_dir"

    while IFS= read -r entry; do
        read -r label asset ver <<<"$entry"
        [[ -n "${label:-}" && -n "${asset:-}" && -n "${ver:-}" ]] ||
            die "malformed entry in config/fonts.txt: $entry"

        if compgen -G "$fonts_dir/${asset}*.ttf" >/dev/null 2>&1; then
            log_info "already installed: $label ($ver)"
            continue
        fi

        if ((FS_DRY_RUN)); then
            log_info "would install: $label ($ver)"
            fresh=1
            continue
        fi

        want="$(awk -v a="${asset}@${ver}" '$2 == a {print $1; exit}' "$FS_ROOT/config/fonts.sha256")"
        [[ -n "$want" ]] || die "no pinned sha256 for ${asset}@${ver} in config/fonts.sha256"

        tmp="$fonts_dir/.${asset}.zip"
        run "download $label" curl -fsSL --proto '=https' --max-time 300 -o "$tmp" \
            "https://github.com/ryanoasis/nerd-fonts/releases/download/$ver/${asset}.zip"
        if ! printf '%s  %s\n' "$want" "$tmp" | sha256sum -c - >/dev/null 2>&1; then
            rm -f -- "$tmp"
            die "sha256 mismatch for ${asset}.zip; refusing to install $label"
        fi
        run "extract $label" unzip -oq "$tmp" -d "$fonts_dir"
        rm -f -- "$tmp"
        log_info "installed: $label ($ver)"
        fresh=1
    done < <(read_list "$FS_ROOT/config/fonts.txt")

    ((fresh)) || return 0
    ((FS_DRY_RUN)) && return 0
    if have fc-cache; then
        run "refresh font cache" fc-cache -f "$fonts_dir"
    else
        log_warn "fc-cache not found; fonts installed but not indexed"
    fi
}
