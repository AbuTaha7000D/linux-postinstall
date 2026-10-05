#!/usr/bin/env bash
# modules/terminal.sh - shell prompt, aliases, history.
#
# Writes three things, each idempotent:
#   ~/.config/postinstall/aliases   the alias list, sourced from ~/.bashrc
#   ~/.local/bin/oh-my-posh         pinned release binary, sha256-verified
#   ~/.local/bin/atuin              pinned release binary, sha256-verified
#
# Both binaries are checked for their pinned version first, so a re-run
# downloads nothing. ~/.bashrc is edited through a managed block (see
# lib/config.sh); the rest of that file is never touched.
#
# Override the pins with FS_OMP_VERSION / FS_ATUIN_VERSION, or pre-place the
# binaries in FS_BIN_SRC_DIR to install from local files instead of the
# network.

install_terminal() {
    local omp_version="${FS_OMP_VERSION:-v24.19.2}"
    local atuin_version="${FS_ATUIN_VERSION:-v18.9.0}"
    local bindir="$HOME/.local/bin"
    local omp="$bindir/oh-my-posh"
    local atuin="$bindir/atuin"
    local machine omp_arch atuin_triple

    machine="$(uname -m)"
    omp_arch="$(_goarch "$machine")" || die "no oh-my-posh release for $machine"
    atuin_triple="$(_atuin_triple "$machine")"

    run "create dirs" mkdir -p "$bindir" "$HOME/.config/postinstall"

    _install_verified_binary \
        "https://github.com/JanDeDobbeleer/oh-my-posh/releases/download/$omp_version/posh-linux-$omp_arch" \
        "$omp" "$omp --version" "${omp_version#v}"

    if [[ -n "$atuin_triple" ]]; then
        _install_verified_binary \
            "https://github.com/atuinsh/atuin/releases/download/$atuin_version/atuin-$atuin_triple-unknown-linux-gnu.tar.gz" \
            "$atuin" "$atuin --version" "${atuin_version#v}" tar
    else
        log_warn "no atuin release for $machine; skipping atuin"
    fi

    _term_theme

    local aliases="$HOME/.config/postinstall/aliases"
    local body
    body="$(read_list "$FS_ROOT/config/aliases.txt")"
    [[ -n "$body" ]] || die "config/aliases.txt is empty"
    printf '%s\n' "$body" | write_atomic "$aliases"

    {
        printf '[ -r %q ] && . %q\n' "$aliases" "$aliases"
        printf '[ -x %q ] && eval "$(%q init bash --config %q)"\n' \
            "$omp" "$omp" "$HOME/.config/oh-my-posh/theme.json"
        if [[ -n "$atuin_triple" ]]; then
            printf '[ -x %q ] && eval "$(%q init bash)"\n' "$atuin" "$atuin"
        fi
    } | write_block "$HOME/.bashrc" terminal
}

_goarch() {
    case "$1" in
    x86_64 | amd64) printf 'amd64' ;;
    aarch64 | arm64) printf 'arm64' ;;
    armv7l | armv6l | arm) printf 'arm' ;;
    *) return 1 ;;
    esac
}

_atuin_triple() {
    case "$1" in
    x86_64) printf 'x86_64' ;;
    aarch64 | arm64) printf 'aarch64' ;;
    *) return 0 ;;
    esac
}

# Themes are JSON that oh-my-posh reads, not something the shell executes, so
# this one is installed without a checksum.
_term_theme() {
    local theme="$HOME/.config/oh-my-posh/theme.json"
    local url="https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/jandedobbeleer.omp.json"
    local tmp

    [[ -f "$theme" ]] && {
        log_info "unchanged: $theme"
        return 0
    }
    run "create theme dir" mkdir -p "$HOME/.config/oh-my-posh"
    tmp="$theme.new.$$"
    if ((FS_DRY_RUN)); then
        log_info "would install theme: $theme"
        return 0
    fi
    if [[ -n "${FS_BIN_SRC_DIR:-}" && -f "$FS_BIN_SRC_DIR/theme.json" ]]; then
        run "copy theme" cp -- "$FS_BIN_SRC_DIR/theme.json" "$tmp"
    else
        run "download theme" curl -fsSL --proto '=https' --max-time 60 -o "$tmp" "$url"
    fi
    if ! mv -f -- "$tmp" "$theme"; then
        rm -f -- "$tmp"
        die "cannot install $theme"
    fi
    log_info "installed: $theme"
}

# _install_verified_binary <url> <dest> <version-cmd> <want-version> [untar]
#
# Downloads <url> and <url>.sha256 into a temp dir and refuses to install
# unless the digest matches. Skipped entirely when <dest> already reports the
# wanted version.
_install_verified_binary() {
    local url="$1" dest="$2" vercmd="$3" want="$4" untar="${5:-}"
    local tmpdir payload bin local_src="${FS_BIN_SRC_DIR:-}"

    if [[ -x "$dest" ]] && _version_is "$vercmd" "$want"; then
        log_info "already installed: $dest ($want)"
        return 0
    fi

    payload="$(basename -- "$url")"
    local -i local_copy=0
    if [[ -n "$local_src" && -f "$local_src/$payload" ]]; then
        local_copy=1
        log_info "using local copy: $local_src/$payload"
    fi

    if ((FS_DRY_RUN)); then
        # Nothing was fetched, so there is nothing to verify or move yet. Say
        # what a real run would do and let the rest of the module report.
        log_info "would download and verify $payload, then install to $dest"
        return 0
    fi

    tmpdir="$(mktemp -d)" || die "cannot create temp dir"
    _tmpdirs+=("$tmpdir")

    if ((local_copy)); then
        run "stage $payload" cp -- "$local_src/$payload" "$tmpdir/payload"
        [[ -f "$local_src/$payload.sha256" ]] &&
            cp -- "$local_src/$payload.sha256" "$tmpdir/payload.sha256"
    else
        run "download $payload" \
            curl -fsSL --proto '=https' --max-time 300 -o "$tmpdir/payload" "$url"
        run "download $payload.sha256" \
            curl -fsSL --proto '=https' --max-time 300 -o "$tmpdir/payload.sha256" "$url.sha256"
    fi
    bin="$tmpdir/payload"

    if [[ -f "$tmpdir/payload.sha256" ]]; then
        # Sidecar shapes differ per project: "<hex>  <file>", a bare "<HEX>"
        # token, "<hex> *file". The first field is the digest in all three.
        local got
        got="$(awk 'NR==1{print $1; exit}' "$tmpdir/payload.sha256")"
        if ! printf '%s  %s\n' "${got,,}" "$tmpdir/payload" | sha256sum -c - >/dev/null 2>&1; then
            die "sha256 mismatch for $payload; refusing to install"
        fi
        log_info "sha256 verified: $payload"
    elif ((local_copy)); then
        log_warn "no checksum next to the local $payload; installing unverified"
    else
        die "no .sha256 published for $url; refusing to install unverified"
    fi

    if [[ "$untar" == "tar" ]]; then
        run "extract $payload" tar -xzf "$tmpdir/payload" -C "$tmpdir"
        bin="$(find "$tmpdir" -type f -name "$(basename -- "$dest")" -print -quit)"
        [[ -n "$bin" ]] || die "no $(basename -- "$dest") inside the archive"
    fi

    run "install $(basename -- "$dest")" mv -f -- "$bin" "$dest"
    run "make $(basename -- "$dest") executable" chmod 0755 "$dest"
    log_info "installed: $dest"
}

_version_is() {
    local vercmd="$1" want="$2" got
    got="$($vercmd 2>/dev/null | head -1)" || return 1
    [[ "$got" == *"$want"* ]]
}
