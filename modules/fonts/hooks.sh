#!/usr/bin/env bash
# modules/fonts/hooks.sh - Nerd Fonts installer (P5.4).
# Sourced INSIDE the runner's hook subshell (lib/runner.sh stage 4) and run()
# called once. Sources lib/lists.sh for list_parse (runner already provides
# io_* and run_cmd); re-sourcing is idempotent.
# Entries (config/nerdfonts.list, or $FS_NERDFONT_CONFIG) are
# `label:asset:version`; each asset fetches a pinned release zip
#   https://github.com/ryanoasis/nerd-fonts/releases/download/<version>/<asset>.zip
# (plus the matching .sha256), verifies the digest, extracts into
# $FS_FONTS_DIR (default ~/.local/share/fonts), then touches a per-asset
# marker so a re-run skips already-installed sets. fc-cache rescans the
# target fonts dir once per run only when something new was installed;
# the network/download and extraction steps run through run_cmd --stop so a
# failure aborts the module (no marker, module failed).
# Source selection: FS_NERDFONT_SRC_DIR is authoritative when set (fail-fast
# if a named asset is missing there — hermetic test seam and offline override);
# otherwise the repo's assets/fonts/ directory if the asset exists there;
# otherwise the network (curl --proto =https, with --max-time). The .sha256
# is REQUIRED for network installs and verified when present locally; a local
# zip without a checksum installs with a warning (operator-provided asset).
# Dry-run prints `# would run:` download/extract/fc-cache plan lines (the
# exact download URLs are listed) with the SAME entry parsing/validation as
# real mode, and executes nothing, probes nothing, writes nothing.
# Malformed entries are skipped with a warning in both modes.
# Fail-closed: empty/unset HOME without FS_FONTS_DIR, a fonts_dir of "/",
# and HOME of "/" all abort before any write. Temp files are mktemp-created
# inside the fonts dir and always removed (normal and error paths).
# Bash >= 4.3 safe (no namerefs beyond lists.sh's own).

_run_nerd_entry() {
    local entry="$1"
    [[ "$entry" == *:*:* ]] || return 1
    label="${entry%%:*}"
    rest="${entry#*:}"
    asset="${rest%%:*}"
    ver="${rest#*:}"
    [[ -n "$label" && -n "$asset" && -n "$ver" ]] || return 1
    case "$asset" in
        *[!A-Za-z0-9._-]* | "") return 1 ;;
    esac
    case "$ver" in
        *[!A-Za-z0-9._-]* | "") return 1 ;;
    esac
}

run() {
    local root fonts_dir src_dir repo_assets config_file
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || return 1
    source "$root/lib/lists.sh"
    fonts_dir="${FS_FONTS_DIR:-}"
    if [[ -z "$fonts_dir" ]]; then
        [[ -n "${HOME:-}" && "${HOME}" != "/" ]] || {
            io_error "nerd fonts target requires FS_FONTS_DIR or a real HOME"
            return 1
        }
        fonts_dir="$HOME/.local/share/fonts"
    fi
    if [[ "$fonts_dir" == "/" || "$fonts_dir" == "" ]]; then
        io_error "refusing nerd fonts target: $fonts_dir"
        return 1
    fi
    repo_assets="$root/assets/fonts"
    config_file="${FS_NERDFONT_CONFIG:-$root/config/nerdfonts.list}"
    src_dir="${FS_NERDFONT_SRC_DIR:-}"
    local entries_out="" line=""
    entries_out="$(list_parse "$config_file")" || return 1
    [[ -z "$entries_out" ]] && return 0
    local -a entries=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -n "$line" ]] && entries+=("$line")
    done <<<"$entries_out"
    if (( FS_DRY_RUN == 1 )); then
        local label="" asset="" ver="" rest="" planned=0
        for line in "${entries[@]}"; do
            if ! _run_nerd_entry "$line"; then
                io_warn "skipping malformed nerd font entry: $line"
                continue
            fi
            printf '# would run: download https://github.com/ryanoasis/nerd-fonts/releases/download/%s/%s.zip\n' "$ver" "$asset"
            printf '# would run: verify sha256 and extract %s into %s\n' "$asset" "$fonts_dir"
            planned=$(( planned + 1 ))
        done
        if (( planned > 0 )); then
            printf '# would run: fc-cache (incremental) once per changed set\n'
        fi
        return 0
    fi
    local -i installed_new=0
    local label="" asset="" ver="" rest="" zip_path="" tmp_zip="" tmp_sha="" want=""
    local curl_url=""
    local marker=""
    for line in "${entries[@]}"; do
        if ! _run_nerd_entry "$line"; then
            io_warn "skipping malformed nerd font entry: $line"
            continue
        fi
        marker="$fonts_dir/.fedora-setup-nerd-${asset}-${ver}"
        if [[ -f "$marker" ]]; then
            io_info "nerd font already installed: $label ($ver)"
            continue
        fi
        if ! mkdir -p -- "$fonts_dir" 2>/dev/null; then
            io_error "cannot create fonts dir: $fonts_dir"
            return 1
        fi
        tmp_zip="$(mktemp -- "${fonts_dir}/.$asset.$ver.XXXXXX")" 2>/dev/null || {
            io_error "cannot create temp in: $fonts_dir"
            return 1
        }
        tmp_sha="$tmp_zip.sha"
        zip_path=""
        if [[ -n "$src_dir" ]]; then
            zip_path="$src_dir/${asset}.zip"
        elif [[ -f "$repo_assets/${asset}.zip" ]]; then
            zip_path="$repo_assets/${asset}.zip"
        fi
        if [[ -n "$zip_path" ]]; then
            [[ -f "$zip_path" ]] || {
                io_error "local nerd font source missing: $zip_path"
                rm -f -- "$tmp_zip" 2>/dev/null || :
                return 1
            }
            cp -p -- "$zip_path" "$tmp_zip" 2>/dev/null || {
                io_error "cannot copy $zip_path"
                rm -f -- "$tmp_zip" 2>/dev/null || :
                return 1
            }
            if [[ -f "${zip_path}.sha256" ]]; then
                cp -p -- "${zip_path}.sha256" "$tmp_sha" 2>/dev/null || {
                    io_error "cannot copy ${zip_path}.sha256"
                    rm -f -- "$tmp_zip" 2>/dev/null || :
                    return 1
                }
            fi
        else
            command -v curl >/dev/null 2>&1 || {
                io_error "curl is required for nerd font downloads"
                rm -f -- "$tmp_zip" 2>/dev/null || :
                return 1
            }
            curl_url="https://github.com/ryanoasis/nerd-fonts/releases/download/$ver/${asset}.zip"
            run_cmd "nerd font download" --stop "curl" "-fsSL" "--proto" "=https" \
                "--max-time" "300" "-o" "$tmp_zip" "$curl_url" || {
                    rm -f -- "$tmp_zip" 2>/dev/null || :
                    return 1
                }
            run_cmd "nerd font checksum" --stop "curl" "-fsSL" "--proto" "=https" \
                "--max-time" "300" "-o" "$tmp_sha" "$curl_url.sha256" || {
                    rm -f -- "$tmp_zip" "$tmp_sha" 2>/dev/null || :
                    return 1
                }
        fi
        if [[ -f "$tmp_sha" ]]; then
            want="$(cut -d' ' -f1 -- "$tmp_sha" 2>/dev/null)" || {
                io_error "cannot read checksum for ${asset}.zip"
                rm -f -- "$tmp_zip" "$tmp_sha" 2>/dev/null || :
                return 1
            }
            if ! printf '%s  %s\n' "$want" "$tmp_zip" | sha256sum -c - >/dev/null 2>&1; then
                io_error "sha256 mismatch for ${asset}.zip"
                rm -f -- "$tmp_zip" "$tmp_sha" 2>/dev/null || :
                return 1
            fi
            io_info "sha256 verified: $asset"
        elif [[ -z "$zip_path" ]]; then
            io_error "no checksum available for ${asset}.zip; refusing unverified download"
            rm -f -- "$tmp_zip" 2>/dev/null || :
            return 1
        else
            io_warn "local ${asset}.zip has no .sha256; installing unverified (operator-provided)"
        fi
command -v unzip >/dev/null 2>&1 || {
            io_error "unzip is required for nerd font extraction"
            rm -f -- "$tmp_zip" "$tmp_sha" 2>/dev/null || :
            return 1
        }
        run_cmd "nerd font extract" --stop "unzip" "-oq" "$tmp_zip" "-d" "$fonts_dir" || {
            rm -f -- "$tmp_zip" "$tmp_sha" 2>/dev/null || :
            return 1
        }
        rm -f -- "$tmp_zip" "$tmp_sha" 2>/dev/null || :
        if ! : >"$marker" 2>/dev/null; then
            io_error "cannot write marker: $marker"
            return 1
        fi
        io_info "installed nerd font: $label ($ver)"
        installed_new=$(( installed_new + 1 ))
    done
    if (( installed_new > 0 )); then
        if command -v fc-cache >/dev/null 2>&1; then
            run_cmd "font cache refresh" --stop "fc-cache" "$fonts_dir" || {
                io_error "fc-cache failed"
                return 1
            }
        else
            io_warn "fc-cache unavailable; font file install succeeded unindexed"
        fi
    fi
}