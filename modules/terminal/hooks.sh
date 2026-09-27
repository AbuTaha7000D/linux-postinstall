#!/usr/bin/env bash
# modules/terminal/hooks.sh - prompt & aliases shell setup (P5.5, P2.5).
# Sourced INSIDE the runner's hook subshell (lib/runner.sh stage 4) and run()
# called once. Sources lib/fs.sh itself (fs_managed_block) because the runner
# does not. Writes two managed blocks (covenant, P2.5), never whole-file rc
# rewrites:
#   "aliases"  -> $FS_TERM_ALIASES (default ~/.local/share/fedora-setup/
#                 aliases), a standalone sourced-file of shell aliases;
#   "terminal" -> $FS_BASHRC (default ~/.bashrc): a guarded alias-source line
#                 plus a guarded oh-my-posh init eval line. An existing
#                 ~/.bashrc.bak (legacy artifact) is left byte-untouched.
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
# Idempotence: a $FS_OMP_BIN that is executable and already reports the
# pinned version is kept (no re-download), an existing theme file is kept,
# and matching managed blocks make the whole run a byte-stable no-op. Order
# inside the hook: aliases block, binary, theme, then the .bashrc block last
# as the commit point (integration is only merged once the artifacts exist).
# Dry-run prints `# would run:` plan lines (exact download URLs) for the
# fresh-install path and executes no mutating action, probes no state and
# writes nothing.
# Fail-closed before any write: unset HOME (or HOME of "/") with no seam
# overrides, a non-absolute or quote/newline-contaminated path, and an
# unsupported arch all abort with io_error. Temp files are mktemp-created in
# the target dir and always removed (normal and error paths). All
# downloads/copies/moves go through run_cmd --stop. Bash >= 4.3 safe (no
# namerefs beyond fs.sh's own).

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
    local ver="" arch="" src_dir="" repo_omp="" tmp="" tmp_sha="" want=""
    local omp_src="" theme_src="" bin_dir="" theme_dir="" skip_bin=0 ver_present=""
    local url_bin="" url_theme=""
    local aliases_body="" term_block="" aliases_q="" bin_q="" theme_q=""
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || return 1
    source "$root/lib/fs.sh"
    home="${HOME:-}"
    src_dir="${FS_OMP_SRC_DIR:-}"
    repo_omp="$root/assets/omp"
    ver="${FS_OMP_VERSION:-v23.9.0}"
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
        aliases_abs="$FS_TERM_ALIASES"
        bashrc_abs="$FS_BASHRC"
        bin_abs="$FS_OMP_BIN"
        theme_abs="$FS_OMP_THEME"
    else
        aliases_abs="${FS_TERM_ALIASES:-$home/.local/share/fedora-setup/aliases}"
        bashrc_abs="${FS_BASHRC:-$home/.bashrc}"
        bin_abs="${FS_OMP_BIN:-$home/.local/bin/oh-my-posh}"
        theme_abs="${FS_OMP_THEME:-$home/.config/oh-my-posh/themes/jandedobbeleer.omp.json}"
    fi
    for want in "$aliases_abs" "$bashrc_abs" "$bin_abs" "$theme_abs"; do
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
    url_bin="https://github.com/JanDeDobbeleer/oh-my-posh/releases/download/$ver/posh-linux-$arch"
    url_theme="https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/$ver/themes/jandedobbeleer.omp.json"
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
    term_block="[ -r $aliases_q ] && . $aliases_q"
    term_block+=$'\n'
    term_block+="[ -x $bin_q ] && eval \"\$($bin_q init bash --config $theme_q)\""
    if (( FS_DRY_RUN == 1 )); then
        printf '# would run: merge fedora-setup aliases block into %q\n' "$aliases_abs"
        printf '# would run: install oh-my-posh %s (%s) release binary (%s) into %q\n' "$ver" "$arch" "$url_bin" "$bin_abs"
        printf '# would run: install oh-my-posh theme (%s) into %q\n' "$url_theme" "$theme_abs"
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
    fs_managed_block "$bashrc_abs" "terminal" "$term_block" || return 1
}