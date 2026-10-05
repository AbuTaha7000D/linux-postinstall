#!/usr/bin/env bash
# modules/dev.sh - third-party package repositories.
#
# Adds the Microsoft VS Code repository, verifying the signing key against the
# fingerprint pinned in config/vscode-gpg.fingerprint before the key is imported
# or the repo file is written. The key itself is downloaded at run time and
# never committed.
#
# On Arch, where VS Code has no official package, this logs and returns.

install_dev() {
    case "$FS_FAMILY" in
    rpm | deb) ;;
    *)
        log_info "no third-party repo to add on $FS_FAMILY; skipping"
        return 0
        ;;
    esac

    local key tmp=""
    key="$(_fetch_checked_key \
        "https://packages.microsoft.com/keys/microsoft.asc" \
        "$FS_ROOT/config/vscode-gpg.fingerprint" microsoft)" ||
        return 1

    case "$FS_FAMILY" in
    rpm) _dev_vscode_rpm ;;
    deb)
        tmp="$(mktemp -d)" || die "cannot create temp dir"
        _tmpdirs+=("$tmp")
        _dev_vscode_deb "$key" "$tmp"
        ;;
    esac

    run "refresh package index" $PKG_REFRESH
}

_dev_vscode_rpm() {
    local repo=/etc/yum.repos.d/vscode.repo
    if _repo_has "$repo" "packages.microsoft.com/yumrepos/vscode"; then
        log_info "unchanged: $repo"
        return 0
    fi
    printf '%s\n' \
        '[vscode]' \
        'name=Microsoft Visual Studio Code' \
        'baseurl=https://packages.microsoft.com/yumrepos/vscode' \
        'enabled=1' \
        'gpgcheck=1' \
        'gpgkey=https://packages.microsoft.com/keys/microsoft.asc' |
        run_root "add vscode repo" tee "$repo"
}

_dev_vscode_deb() {
    local key="$1" tmp="$2" keyring=/usr/share/keyrings/microsoft.gpg
    local list=/etc/apt/sources.list.d/vscode.list

    run "dearmor microsoft key" gpg --batch --yes --dearmor -o "$tmp/microsoft.gpg" "$key"
    run_root "install microsoft keyring" mv -f -- "$tmp/microsoft.gpg" "$keyring"

    if _repo_has "$list" "packages.microsoft.com/repos/code"; then
        log_info "unchanged: $list"
        return 0
    fi
    printf 'deb [arch=%s signed-by=%s] https://packages.microsoft.com/repos/code stable main\n' \
        "$(dpkg --print-architecture)" "$keyring" |
        run_root "add vscode repo" tee "$list"
}

_repo_has() {
    local file="$1" url="$2"
    [[ -f "$file" ]] || return 1
    grep -qsF -- "$url" "$file"
}

# _fetch_checked_key <key-url> <fingerprint-file> <label>
#
# Downloads the key to a temp file and prints its path. Returns 1 unless the
# file holds exactly one key whose primary fingerprint is the pinned one.
# Requiring exactly one key is what stops a bundle carrying the right key
# alongside another from passing.
_fetch_checked_key() {
    local url="$1" pin="$2" label="$3"
    local want out keys=0 fp="" tmp keyfile

    [[ -f "$pin" ]] || {
        log_error "$pin not found"
        return 1
    }
    want="$(awk '!/^[[:space:]]*#/ && NF {print toupper($1); exit}' "$pin")"
    if [[ ! "$want" =~ ^[0-9A-F]{40}$ ]]; then
        log_error "no 40-hex fingerprint in $pin"
        return 1
    fi
    have gpg || {
        log_error "gpg is required to verify the $label key"
        return 1
    }

    if ((FS_DRY_RUN)); then
        log_info "would fetch $label key from $url and verify $want"
        tmp="$(mktemp -d)" || return 1
        _tmpdirs+=("$tmp")
        printf '%s' "$tmp/$label.asc"
        return 0
    fi

    tmp="$(mktemp -d)" || return 1
    _tmpdirs+=("$tmp")
    keyfile="$tmp/$label.asc"
    run "fetch $label key" curl -fsSL --proto '=https' --max-time 120 -o "$keyfile" "$url"

    out="$(gpg --batch --no-default-keyring --show-keys --with-colons "$keyfile" 2>/dev/null)" || {
        log_error "cannot read the downloaded $label key with gpg"
        return 1
    }
    while IFS= read -r line; do
        case "$line" in
        pub:*) keys=$((keys + 1)) ;;
        fpr:*)
            if ((keys == 1)) && [[ -z "$fp" ]]; then
                fp="${line#fpr:::::::::}"
                fp="${fp%%:*}"
            fi
            ;;
        esac
    done <<<"$out"

    if ((keys != 1)); then
        log_error "the $label key file holds $keys keys, expected exactly 1"
        return 1
    fi
    if [[ "${fp^^}" != "$want" ]]; then
        log_error "$label key fingerprint mismatch: got ${fp:-none}, expected $want"
        return 1
    fi
    log_info "$label key fingerprint verified: $want"
    printf '%s' "$keyfile"
}
