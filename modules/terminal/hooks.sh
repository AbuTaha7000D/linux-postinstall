#!/usr/bin/env bash
# modules/terminal/hooks.sh - prompt, aliases & shell-history shell setup
# (P5.5, P5.6, P2.5). Sourced INSIDE the runner's hook subshell
# (lib/runner.sh stage 4) and run() called once. Sources lib/fs.sh itself
# (fs_managed_block) because the runner does not. Writes two managed blocks
# (covenant, P2.5), never whole-file rc rewrites:
#   "aliases"  -> $FS_TERM_ALIASES (default ~/.local/share/fedora-setup/
#                 aliases), a standalone sourced-file of shell aliases;
#   "terminal" -> $FS_BASHRC (default ~/.bashrc): a guarded alias-source line
#                 plus a guarded oh-my-posh init eval line plus a guarded
#                 atuin init eval line. An existing ~/.bashrc.bak (legacy
#                 artifact) is left byte-untouched.
# oh-my-posh: the pinned release binary ($FS_OMP_VERSION, default v23.9.0)
# for the host arch (x86_64->amd64, aarch64->arm64, armv7l/armv6l/arm->arm;
# $FS_OMP_ARCH overrides) is installed to $FS_OMP_BIN (default
# ~/.local/bin/oh-my-posh) only after its .sha256 sidecar verifies; a theme
# lands at $FS_OMP_THEME (default ~/.config/oh-my-posh/themes/
# jandedobbeleer.omp.json) and is referenced by the init line. The upstream
# .sha256 sidecar is a bare UPPERCASE hex token with a CRLF line ending (no
# filename); the token is truncated to the first field and CR-stripped before
# comparison, so both that shape and a `<hash>  <file>` line parse. The theme
# itself is downloaded/copied without a checksum (rendered, never executed);
# only the binary is checksum-verified. Source
# selection matches the fonts module: FS_OMP_SRC_DIR is authoritative when
# set (fail-fast if a needed asset is missing there), else the repo's
# assets/omp/ dir, else the network (curl --proto =https --max-time 300).
# atuin: pinned release binary archive ($FS_ATUIN_VERSION, default v18.23.0)
# for the host arch (x86_64 and aarch64 only; $FS_ATUIN_ARCH overrides the
# host triple, any other arch -> io_warn + skip, so an arm host keeps the
# working oh-my-posh module). The `atuin-<triple>-unknown-linux-gnu.tar.gz`
# archive + `.sha256` sidecar are downloaded/copied into a mktemp dir
# (FS_ATUIN_SRC_DIR authoritative-fail-fast > assets/atuin/ > network). The
# upstream atuin sidecar line is `<lowercase hex> *<filename>`; the token is
# truncated to the first field, CR-stripped and lowercased (handles that
# shape, an OMP-style bare `<HEX>` token, and a `<hash>  <file>` line alike)
# before the sha256 is verified against the archive. The verified binary is
# extracted from the archive into $FS_ATUIN_BIN (default ~/.local/bin/atuin),
# and a guarded `atuin init` eval line joins the "terminal" managed block.
# Removal ("uninstall documented"): delete $FS_ATUIN_BIN and drop the atuin
# line from the managed block; lib/fs.sh fs_managed_block_remove covers
# unattended removal of the block itself.
# Idempotence: a $FS_OMP_BIN that is executable and already reports the
# pinned version is kept (no re-download), the same version-check skips the
# atuin download/re-extract, an existing theme file is kept, and matching
# managed blocks make the whole run a byte-stable no-op. Order inside the
# hook: aliases block, oh-my-posh binary, theme, atuin, then the .bashrc
# block last as the commit point (integration is only merged once the
# artifacts exist).
# Dry-run prints `# would run:` plan lines (exact download URLs) for the
# fresh-install path and executes no mutating action, probes no state and
# writes nothing.
# Fail-closed before any write: unset HOME (or HOME of "/") with no seam
# overrides, a non-absolute or quote/newline-contaminated path, and an
# unsupported oh-my-posh arch all abort with io_error. Temp files are
# mktemp-created in the target dir and always removed (normal and error
# paths). All downloads/copies/moves/extractions go through run_cmd --stop.
# Bash >= 4.3 safe (no namerefs beyond fs.sh's own).

_term_arch() {
    local m
    case "${FS_OMP_ARCH:-}" in
        amd64 | arm64 | arm)
            printf '%s' "$FS_OMP_ARCH"
            return 0
            ;;
        "") ;;
        *) return 1 ;;
    esac
    m="$(uname -m)"
    case "$m" in
        x86_64) printf 'amd64' ;;
        aarch64 | arm64) printf 'arm64' ;;
        armv7l | armv6l | arm) printf 'arm' ;;
        *) return 1 ;;
    esac
}

_term_path_ok() {
    case "$1" in
        *"'"* | *$'\n'* | *$'\r'*) return 1 ;;
    esac
    return 0
}

run() {
    local root="" home="" aliases_abs="" bashrc_abs="" bin_abs="" theme_abs=""
    local atuin_abs="" atuin_ver="" atuin_triple="" atuin_bin_dir="" atuin_src=""
    local atuin_skip=0 atuin_ver_present="" atuin_ver_tok="" atuin_tmpdir=""
    local atuin_tmp_tar="" atuin_tmp_sha="" atuin_extracted=""
    local ver="" arch="" src_dir="" repo_omp="" tmp="" tmp_sha="" want=""
    local omp_src="" theme_src="" bin_dir="" theme_dir="" skip_bin=0 ver_present=""
    local url_bin="" url_theme="" url_atuin=""
    local aliases_body="" term_block="" aliases_q="" bin_q="" theme_q="" atuin_q=""
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || return 1
    source "$root/lib/fs.sh"
    home="${HOME:-}"
    src_dir="${FS_OMP_SRC_DIR:-}"
    repo_omp="$root/assets/omp"
    ver="${FS_OMP_VERSION:-v23.9.0}"
    atuin_ver="${FS_ATUIN_VERSION:-v18.23.0}"
    if [[ -z "$home" || "$home" == "/" ]]; then
        [[ -n "${FS_TERM_ALIASES:-}" ]] || {
            io_error "terminal aliases require HOME or FS_TERM_ALIASES"
            return 1
        }
        [[ -n "${FS_BASHRC:-}" ]] || {
            io_error "terminal block requires HOME or FS_BASHRC"
            return 1
        }
        [[ -n "${FS_OMP_BIN:-}" ]] || {
            io_error "oh-my-posh binary requires HOME or FS_OMP_BIN"
            return 1
        }
        [[ -n "${FS_OMP_THEME:-}" ]] || {
            io_error "oh-my-posh theme requires HOME or FS_OMP_THEME"
            return 1
        }
        [[ -n "${FS_ATUIN_BIN:-}" ]] || {
            io_error "atuin binary requires HOME or FS_ATUIN_BIN"
            return 1
        }
        aliases_abs="$FS_TERM_ALIASES"
        bashrc_abs="$FS_BASHRC"
        bin_abs="$FS_OMP_BIN"
        theme_abs="$FS_OMP_THEME"
        atuin_abs="$FS_ATUIN_BIN"
    else
        aliases_abs="${FS_TERM_ALIASES:-$home/.local/share/fedora-setup/aliases}"
        bashrc_abs="${FS_BASHRC:-$home/.bashrc}"
        bin_abs="${FS_OMP_BIN:-$home/.local/bin/oh-my-posh}"
        theme_abs="${FS_OMP_THEME:-$home/.config/oh-my-posh/themes/jandedobbeleer.omp.json}"
        atuin_abs="${FS_ATUIN_BIN:-$home/.local/bin/atuin}"
    fi
    for want in "$aliases_abs" "$bashrc_abs" "$bin_abs" "$theme_abs" "$atuin_abs"; do
        case "$want" in
            /*) ;;
            *) io_error "terminal paths must be absolute: $want"; return 1 ;;
        esac
        _term_path_ok "$want" || {
            io_error "terminal path contains a quote or newline: $want"
            return 1
        }
    done
    arch="$(_term_arch)" || {
        io_error "unsupported architecture for oh-my-posh"
        return 1
    }
    case "${FS_ATUIN_ARCH:-}" in
        x86_64 | aarch64) atuin_triple="$FS_ATUIN_ARCH" ;;
        "") case "$(uname -m)" in
                x86_64) atuin_triple="x86_64" ;;
                aarch64 | arm64) atuin_triple="aarch64" ;;
                *) atuin_triple="" ;;
            esac ;;
        *) atuin_triple="" ;;
    esac
    url_bin="https://github.com/JanDeDobbeleer/oh-my-posh/releases/download/$ver/posh-linux-$arch"
    url_theme="https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/$ver/themes/jandedobbeleer.omp.json"
    url_atuin="https://github.com/atuinsh/atuin/releases/download/$atuin_ver/atuin-$atuin_triple-unknown-linux-gnu.tar.gz"
    aliases_body="alias ll='ls -la'"
    aliases_body+=$'\n'
    aliases_body+="alias la='ls -A'"
    aliases_body+=$'\n'
    aliases_body+="alias grep='grep --color=auto'"
    aliases_body+=$'\n'
    aliases_body+="alias egrep='egrep --color=auto'"
    aliases_body+=$'\n'
    aliases_body+="alias less='less -R'"
    printf -v aliases_q "'%s'" "$aliases_abs"
    printf -v bin_q "'%s'" "$bin_abs"
    printf -v theme_q "'%s'" "$theme_abs"
    printf -v atuin_q "'%s'" "$atuin_abs"
    term_block="[ -r $aliases_q ] && . $aliases_q"
    term_block+=$'\n'
    term_block+="[ -x $bin_q ] && eval \"\$($bin_q init bash --config $theme_q)\""
    term_block+=$'\n'
    term_block+="[ -x $atuin_q ] && eval \"\$($atuin_q init bash)\""
    if (( FS_DRY_RUN == 1 )); then
        printf '# would run: merge fedora-setup aliases block into %q\n' "$aliases_abs"
        printf '# would run: install oh-my-posh %s (%s) release binary (%s) into %q\n' "$ver" "$arch" "$url_bin" "$bin_abs"
        printf '# would run: install oh-my-posh theme (%s) into %q\n' "$url_theme" "$theme_abs"
        if [[ -n "$atuin_triple" ]]; then
            printf '# would run: install atuin %s (%s) release binary (%s) into %q\n' "$atuin_ver" "$atuin_triple" "$url_atuin" "$atuin_abs"
        else
            printf '# would run: skip atuin (no release for this host arch)\n'
        fi
        printf '# would run: merge fedora-setup terminal block into %q\n' "$bashrc_abs"
        return 0
    fi
    fs_managed_block "$aliases_abs" "aliases" "$aliases_body" || return 1
    skip_bin=0
    if [[ -x "$bin_abs" ]]; then
        ver_present="$("$bin_abs" --version 2>/dev/null)" || ver_present=""
        if [[ "$ver_present" == "${ver#v}" ]]; then
            io_info "oh-my-posh already installed: $bin_abs"
            skip_bin=1
        else
            io_warn "replacing oh-my-posh (installed: ${ver_present:-unknown}, pinned: $ver)"
        fi
    fi
    if (( skip_bin != 1 )); then
        bin_dir="${bin_abs%/*}"
        run_cmd "oh-my-posh bin dir" --stop "mkdir" "-p" "--" "$bin_dir" || return 1
        tmp="$(mktemp -- "$bin_dir/.oh-my-posh.XXXXXX")" 2>/dev/null || {
            io_error "cannot create temp in: $bin_dir"
            return 1
        }
        tmp_sha="$tmp.sha"
        omp_src=""
        if [[ -n "$src_dir" ]]; then
            omp_src="$src_dir/posh-linux-$arch"
        elif [[ -f "$repo_omp/posh-linux-$arch" ]]; then
            omp_src="$repo_omp/posh-linux-$arch"
        fi
        if [[ -n "$omp_src" ]]; then
            [[ -f "$omp_src" ]] || {
                io_error "local oh-my-posh source missing: $omp_src"
                rm -f -- "$tmp" "$tmp_sha" 2>/dev/null || :
                return 1
            }
            run_cmd "oh-my-posh binary copy" --stop "cp" "--" "$omp_src" "$tmp" || {
                rm -f -- "$tmp" "$tmp_sha" 2>/dev/null || :
                return 1
            }
            if [[ -f "${omp_src}.sha256" ]]; then
                run_cmd "oh-my-posh checksum copy" --stop "cp" "--" "${omp_src}.sha256" "$tmp_sha" || {
                    rm -f -- "$tmp" "$tmp_sha" 2>/dev/null || :
                    return 1
                }
            fi
        else
            command -v curl >/dev/null 2>&1 || {
                io_error "curl is required for oh-my-posh binary download"
                rm -f -- "$tmp" "$tmp_sha" 2>/dev/null || :
                return 1
            }
            run_cmd "oh-my-posh binary download" --stop "curl" "-fsSL" "--proto" "=https" \
                "--max-time" "300" "-o" "$tmp" "$url_bin" || {
                    rm -f -- "$tmp" "$tmp_sha" 2>/dev/null || :
                    return 1
                }
            run_cmd "oh-my-posh checksum download" --stop "curl" "-fsSL" "--proto" "=https" \
                "--max-time" "300" "-o" "$tmp_sha" "$url_bin.sha256" || {
                    rm -f -- "$tmp" "$tmp_sha" 2>/dev/null || :
                    return 1
                }
        fi
        [[ -f "$tmp_sha" ]] || {
            io_error "no checksum available for oh-my-posh ($arch); refusing unverified install"
            rm -f -- "$tmp" "$tmp_sha" 2>/dev/null || :
            return 1
        }
        want="$(cut -d' ' -f1 -- "$tmp_sha" 2>/dev/null)" || {
            io_error "cannot read checksum for oh-my-posh ($arch)"
            rm -f -- "$tmp" "$tmp_sha" 2>/dev/null || :
            return 1
        }
        want="$(printf '%s' "$want" | tr -d '\r')" || {
            io_error "cannot normalize checksum for oh-my-posh ($arch)"
            rm -f -- "$tmp" "$tmp_sha" 2>/dev/null || :
            return 1
        }
        want="$(printf '%s' "$want" | tr '[:upper:]' '[:lower:]')" || {
            io_error "cannot lowercase checksum for oh-my-posh ($arch)"
            rm -f -- "$tmp" "$tmp_sha" 2>/dev/null || :
            return 1
        }
        command -v sha256sum >/dev/null 2>&1 || {
            io_error "sha256sum is required for oh-my-posh binary verification"
            rm -f -- "$tmp" "$tmp_sha" 2>/dev/null || :
            return 1
        }
        if ! printf '%s  %s\n' "$want" "$tmp" | sha256sum -c - >/dev/null 2>&1; then
            io_error "sha256 mismatch for oh-my-posh binary ($arch)"
            rm -f -- "$tmp" "$tmp_sha" 2>/dev/null || :
            return 1
        fi
        io_info "sha256 verified: oh-my-posh ($arch)"
        if [[ -e "$bin_abs" ]]; then
            if ! fs_backup "$bin_abs" >/dev/null; then
                rm -f -- "$tmp" "$tmp_sha" 2>/dev/null || :
                return 1
            fi
        fi
        run_cmd "oh-my-posh binary install" --stop "mv" "-fT" "--" "$tmp" "$bin_abs" || {
            rm -f -- "$tmp" "$tmp_sha" 2>/dev/null || :
            return 1
        }
        run_cmd "oh-my-posh binary mode" --stop "chmod" "0755" "$bin_abs" || {
            rm -f -- "$tmp_sha" 2>/dev/null || :
            return 1
        }
        rm -f -- "$tmp" "$tmp_sha" 2>/dev/null || :
    fi
    if [[ -f "$theme_abs" ]]; then
        io_info "oh-my-posh theme already present: $theme_abs"
    else
        theme_dir="${theme_abs%/*}"
        run_cmd "oh-my-posh theme dir" --stop "mkdir" "-p" "--" "$theme_dir" || return 1
        theme_src=""
        if [[ -n "$src_dir" ]]; then
            theme_src="$src_dir/jandedobbeleer.omp.json"
        elif [[ -f "$repo_omp/jandedobbeleer.omp.json" ]]; then
            theme_src="$repo_omp/jandedobbeleer.omp.json"
        fi
        if [[ -n "$theme_src" ]]; then
            [[ -f "$theme_src" ]] || {
                io_error "local oh-my-posh theme missing: $theme_src"
                return 1
            }
            run_cmd "oh-my-posh theme install" --stop "cp" "--" "$theme_src" "$theme_abs" || return 1
        else
            command -v curl >/dev/null 2>&1 || {
                io_error "curl is required for oh-my-posh theme download"
                return 1
            }
            tmp="$(mktemp -- "$theme_dir/.oh-my-posh-theme.XXXXXX")" 2>/dev/null || {
                io_error "cannot create temp in: $theme_dir"
                return 1
            }
            run_cmd "oh-my-posh theme download" --stop "curl" "-fsSL" "--proto" "=https" \
                "--max-time" "300" "-o" "$tmp" "$url_theme" || {
                    rm -f -- "$tmp" 2>/dev/null || :
                    return 1
                }
            run_cmd "oh-my-posh theme install" --stop "mv" "-fT" "--" "$tmp" "$theme_abs" || {
                rm -f -- "$tmp" 2>/dev/null || :
                return 1
            }
        fi
    fi
    if [[ -z "$atuin_triple" ]]; then
        io_warn "atuin has no release for this host arch; skipping"
    else
        atuin_skip=0
        if [[ -x "$atuin_abs" ]]; then
            atuin_ver_present="$("$atuin_abs" --version 2>/dev/null)" || atuin_ver_present=""
            atuin_ver_tok="${atuin_ver_present#atuin }"
            atuin_ver_tok="${atuin_ver_tok%% *}"
            if [[ "$atuin_ver_tok" == "${atuin_ver#v}" ]]; then
                io_info "atuin already installed: $atuin_abs"
                atuin_skip=1
            else
                io_warn "replacing atuin (installed: ${atuin_ver_tok:-unknown}, pinned: $atuin_ver)"
            fi
        fi
        if (( atuin_skip != 1 )); then
            atuin_bin_dir="${atuin_abs%/*}"
            run_cmd "atuin bin dir" --stop "mkdir" "-p" "--" "$atuin_bin_dir" || return 1
            atuin_tmpdir="$(mktemp -d -- "$atuin_bin_dir/.atuin.XXXXXX")" 2>/dev/null || {
                io_error "cannot create temp dir in: $atuin_bin_dir"
                return 1
            }
            atuin_tmp_tar="$atuin_tmpdir/atuin.tar.gz"
            atuin_tmp_sha="$atuin_tmpdir/atuin.tar.gz.sha256"
            atuin_src=""
            if [[ -n "${FS_ATUIN_SRC_DIR:-}" ]]; then
                atuin_src="$FS_ATUIN_SRC_DIR/atuin-$atuin_triple-unknown-linux-gnu.tar.gz"
            elif [[ -f "$root/assets/atuin/atuin-$atuin_triple-unknown-linux-gnu.tar.gz" ]]; then
                atuin_src="$root/assets/atuin/atuin-$atuin_triple-unknown-linux-gnu.tar.gz"
            fi
            if [[ -n "$atuin_src" ]]; then
                [[ -f "$atuin_src" ]] || {
                    io_error "local atuin archive missing: $atuin_src"
                    rm -rf -- "$atuin_tmpdir" 2>/dev/null || :
                    return 1
                }
                run_cmd "atuin archive copy" --stop "cp" "--" "$atuin_src" "$atuin_tmp_tar" || {
                    rm -rf -- "$atuin_tmpdir" 2>/dev/null || :
                    return 1
                }
                if [[ -f "${atuin_src}.sha256" ]]; then
                    run_cmd "atuin checksum copy" --stop "cp" "--" "${atuin_src}.sha256" "$atuin_tmp_sha" || {
                        rm -rf -- "$atuin_tmpdir" 2>/dev/null || :
                        return 1
                    }
                fi
            else
                command -v curl >/dev/null 2>&1 || {
                    io_error "curl is required for atuin archive download"
                    rm -rf -- "$atuin_tmpdir" 2>/dev/null || :
                    return 1
                }
                run_cmd "atuin archive download" --stop "curl" "-fsSL" "--proto" "=https" \
                    "--max-time" "300" "-o" "$atuin_tmp_tar" "$url_atuin" || {
                        rm -rf -- "$atuin_tmpdir" 2>/dev/null || :
                        return 1
                    }
                run_cmd "atuin checksum download" --stop "curl" "-fsSL" "--proto" "=https" \
                    "--max-time" "300" "-o" "$atuin_tmp_sha" "$url_atuin.sha256" || {
                        rm -rf -- "$atuin_tmpdir" 2>/dev/null || :
                        return 1
                    }
            fi
            [[ -f "$atuin_tmp_sha" ]] || {
                io_error "no checksum available for atuin ($atuin_triple); refusing unverified install"
                rm -rf -- "$atuin_tmpdir" 2>/dev/null || :
                return 1
            }
            want="$(cut -d' ' -f1 -- "$atuin_tmp_sha" 2>/dev/null)" || {
                io_error "cannot read checksum for atuin ($atuin_triple)"
                rm -rf -- "$atuin_tmpdir" 2>/dev/null || :
                return 1
            }
            want="$(printf '%s' "$want" | tr -d '\r')" || {
                io_error "cannot normalize checksum for atuin ($atuin_triple)"
                rm -rf -- "$atuin_tmpdir" 2>/dev/null || :
                return 1
            }
            want="$(printf '%s' "$want" | tr '[:upper:]' '[:lower:]')" || {
                io_error "cannot lowercase checksum for atuin ($atuin_triple)"
                rm -rf -- "$atuin_tmpdir" 2>/dev/null || :
                return 1
            }
            command -v sha256sum >/dev/null 2>&1 || {
                io_error "sha256sum is required for atuin archive verification"
                rm -rf -- "$atuin_tmpdir" 2>/dev/null || :
                return 1
            }
            if ! printf '%s  %s\n' "$want" "$atuin_tmp_tar" | sha256sum -c - >/dev/null 2>&1; then
                io_error "sha256 mismatch for atuin archive ($atuin_triple)"
                rm -rf -- "$atuin_tmpdir" 2>/dev/null || :
                return 1
            fi
            io_info "sha256 verified: atuin ($atuin_triple)"
            run_cmd "atuin archive extract" --stop "tar" "-xzf" "$atuin_tmp_tar" "-C" "$atuin_tmpdir" || {
                rm -rf -- "$atuin_tmpdir" 2>/dev/null || :
                return 1
            }
            atuin_extracted="$atuin_tmpdir/atuin-$atuin_triple-unknown-linux-gnu/atuin"
            [[ -f "$atuin_extracted" ]] || {
                io_error "atuin archive missing expected binary: atuin-$atuin_triple-unknown-linux-gnu/atuin"
                rm -rf -- "$atuin_tmpdir" 2>/dev/null || :
                return 1
            }
            run_cmd "atuin binary mode" --stop "chmod" "0755" "$atuin_extracted" || {
                rm -rf -- "$atuin_tmpdir" 2>/dev/null || :
                return 1
            }
            if [[ -e "$atuin_abs" ]]; then
                if ! fs_backup "$atuin_abs" >/dev/null; then
                    rm -rf -- "$atuin_tmpdir" 2>/dev/null || :
                    return 1
                fi
            fi
            run_cmd "atuin binary install" --stop "mv" "-fT" "--" "$atuin_extracted" "$atuin_abs" || {
                rm -rf -- "$atuin_tmpdir" 2>/dev/null || :
                return 1
            }
            rm -rf -- "$atuin_tmpdir" 2>/dev/null || :
        fi
    fi
    fs_managed_block "$bashrc_abs" "terminal" "$term_block" || return 1
}