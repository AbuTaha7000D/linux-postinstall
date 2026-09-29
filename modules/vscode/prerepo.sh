#!/usr/bin/env bash
# modules/vscode/prerepo.sh - P7.5 pre-batch hook for the vscode module.
#
# The runner (P7.5 stage 3) sources this file in a subshell and calls
# prerepo() after list collection and BEFORE the package batch, because the
# batch installs `code` from the repository this hook adds. It is the only
# module with a prerepo.sh; there is deliberately no hooks.sh.
#
# What prerepo() does, in order:
#   1. NO-OP when the flatpak alternative is selected (FS_VSCODE_FLATPAK
#      truthy, resolved through module_flatpak_alt so the runner and the
#      hook agree on one definition of "selected"): the flatpak id needs no
#      repository and no key, and taking this path must not leave a
#      privileged step behind.
#   2. NO-OP with a warning on arch: VS Code has no official Arch package
#      (the only AUR package, visual-studio-code-bin, needs an AUR helper or
#      a manual makepkg build), so there is nothing to add. The module
#      still ends up marked done, which is accurate: the decision for arch
#      is "nothing native, use the flatpak build".
#   3. Otherwise (rpm, deb): read the pinned fingerprint, download the
#      armored key to a temporary file (curl writes the file; nothing is
#      ever piped into gpg), read the key's PRIMARY-key fingerprint --
#      gpg emits `pub, fpr, uid, sub, fpr`, so the first fpr after the only
#      pub is the primary and a later one is a SUBKEY, a strictly weaker
#      trust anchor; a file holding more than one key is rejected outright
#      so a bundle can never smuggle an extra key past the check -- and
#      REFUSE to go further unless it matches the pin exactly. Only then is
#      the key installed (rpm --import, or gpg --dearmor into the
#      tool-owned keyring), the repository file written (--if-not-exists),
#      and the package metadata refreshed.
#
# FAIL-CLOSED DETAILS worth knowing before changing anything here:
#   - run_cmd/run_sudo return 0 for a failed command unless --stop is
#     passed, so every step whose failure must abort the module (fetch,
#     import, dearmor) uses --stop.
#   - pkg_add_repo's own rc is not trustworthy for a failed write: the P3
#     primitives call run_sudo without --stop, so a failed `install` is
#     swallowed. The repository file and the deb keyring are therefore
#     checked for existence and size after the call, so "the repository was
#     added" is verified rather than assumed.
#   - The metadata refresh in step 3 is not redundant: the deb backend
#     defers `apt-get update` to the next install by setting a flag, and
#     this hook runs in a SUBSHELL, so that flag cannot reach the runner's
#     later batch. pkg_update_metadata here is what makes a freshly added
#     deb repository usable; for rpm it is the same "refresh after adding a
#     repository" step, and dnf would do it during the install anyway.
#
# Dry-run: the download, the import and the repository add are rendered
# through run_cmd/run_sudo as `# would run:` lines and NOTHING is executed
# or written, so the fingerprint comparison has nothing to compare and is
# skipped -- the dry rendering shows the plan, not a verified result.
#
# Seams: FS_VSCODE_KEY_FILE (path to the pinned-fingerprint file, default
# <repo>/config/vscode-gpg.fingerprint) and FS_VSCODE_KEYRING (deb keyring
# destination, default /usr/share/keyrings/fedora-setup-vscode.gpg -- a
# tool-owned name, so this tool never overwrites a file it did not create).
#
# Dependencies: run_cmd/run_sudo (lib/run.sh), sudo_detect (lib/sudo.sh),
# pkg_add_repo/pkg_update_metadata (lib/pkg.sh), module_flatpak_alt
# (lib/modules.sh), io_debug/io_info/io_warn/io_error (lib/io.sh) -- all
# already sourced by the runner before this file is. A prerepo() failure
# stops the run immediately whatever the module's risk.

_VSCODE_KEY_URL="https://packages.microsoft.com/yumrepos/vscode/repodata/repomd.xml.key"
_VSCODE_RPM_BASEURL="https://packages.microsoft.com/yumrepos/vscode/"
_VSCODE_DEB_REPO="https://packages.microsoft.com/repos/code stable main"
_VSCODE_KEYRING="/usr/share/keyrings/fedora-setup-vscode.gpg"

_vscode_cleanup() {
    if [[ -n "${1:-}" ]]; then
        rm -f -- "$1"
    fi
    return 0
}

_vscode_pinned_fingerprint() {
    local file="${1:-}" line="" fp=""
    if [[ -z "$file" || ! -f "$file" || ! -r "$file" ]]; then
        io_error "vscode: pinned fingerprint file missing or unreadable: $file"
        return 1
    fi
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line#"${line%%[![:space:]]*}"}"
        case "$line" in
            "" | \#*) continue ;;
        esac
        fp="$line"
        break
    done <"$file"
    if [[ ! "$fp" =~ ^[0-9A-Fa-f]{40}$ ]]; then
        io_error "vscode: no 40-hex fingerprint in $file"
        return 1
    fi
    printf '%s\n' "${fp^^}"
    return 0
}

_vscode_key_fingerprint() {
    local keyfile="${1:-}" out="" line="" fp=""
    local -i keys=0
    if ! command -v gpg >/dev/null 2>&1; then
        io_error "vscode: gpg not found on PATH (needed to verify the repository key)"
        return 1
    fi
    if ! out="$(gpg --batch --no-default-keyring --show-keys --with-colons "$keyfile" 2>/dev/null)"; then
        io_error "vscode: cannot read the downloaded key with gpg"
        return 1
    fi
    while IFS= read -r line; do
        case "$line" in
            pub:*) keys+=1 ;;
            fpr:*)
                if (( keys == 1 )) && [[ -z "$fp" ]]; then
                    fp="${line#fpr:::::::::}"
                    fp="${fp%%:*}"
                fi
                ;;
        esac
    done <<<"$out"
    if [[ ! "$fp" =~ ^[0-9A-Fa-f]{40}$ ]]; then
        io_error "vscode: gpg reported no primary-key fingerprint for the downloaded key"
        return 1
    fi
    if (( keys != 1 )); then
        io_error "vscode: downloaded key holds $keys keys, expected exactly 1 (fingerprint $fp) -- refusing to import a bundle"
        return 1
    fi
    printf '%s\n' "${fp^^}"
    return 0
}

_vscode_repo_file() {
    case "${1:-}" in
        rpm) printf '%s\n' "${FS_REPOS_DIR:-/etc/yum.repos.d}/vscode.repo" ;;
        deb) printf '%s\n' "${FS_SOURCES_DIR:-/etc/apt/sources.list.d}/vscode.list" ;;
        *) return 1 ;;
    esac
    return 0
}

_vscode_import_and_add() {
    local family="${1:-}" keyfile="${2:-}" keyarg="" repo=""
    if ! sudo_detect; then
        io_error "vscode: sudo state unavailable, cannot add the repository"
        return 1
    fi
    if [[ "$family" == rpm ]]; then
        run_sudo "vscode: import repository key" --stop -- rpm --import "$keyfile" || return 1
        pkg_add_repo vscode "$_VSCODE_RPM_BASEURL" || return 1
    else
        keyarg="${FS_VSCODE_KEYRING:-$_VSCODE_KEYRING}"
        run_sudo "vscode: install repository keyring" --stop -- \
            gpg --batch --yes --dearmor --output "$keyarg" "$keyfile" || return 1
        if [[ ! -s "$keyarg" ]]; then
            io_error "vscode: keyring was not written: $keyarg"
            return 1
        fi
        pkg_add_repo vscode "$_VSCODE_DEB_REPO" "$keyarg" || return 1
    fi
    repo="$(_vscode_repo_file "$family")" || return 1
    if [[ ! -s "$repo" ]]; then
        io_error "vscode: repository file was not written: $repo"
        return 1
    fi
    pkg_update_metadata || return 1
    return 0
}

_vscode_prerepo_real() {
    local family="${1:-}" root="" pinned="" keyfile="" found="" rc=0
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || return 1
    pinned="$(_vscode_pinned_fingerprint "${FS_VSCODE_KEY_FILE:-$root/config/vscode-gpg.fingerprint}")" || return 1
    if ! command -v curl >/dev/null 2>&1; then
        io_error "vscode: curl not found on PATH (needed to fetch the repository key)"
        return 1
    fi
    keyfile="$(mktemp "${TMPDIR:-/tmp}/fedora-setup-vscode-key.XXXXXX")" || return 1
    run_cmd "vscode: fetch repository key" --stop -- \
        curl -fsSL --proto '=https' --tlsv1.2 -o "$keyfile" "$_VSCODE_KEY_URL" || rc=$?
    if (( rc != 0 )); then
        _vscode_cleanup "$keyfile"
        return 1
    fi
    found="$(_vscode_key_fingerprint "$keyfile")" || {
        _vscode_cleanup "$keyfile"
        return 1
    }
    if [[ "$found" != "$pinned" ]]; then
        io_error "vscode: repository key fingerprint mismatch"
        io_error "vscode:   expected $pinned"
        io_error "vscode:   got      $found"
        io_error "vscode: refusing to trust the key; nothing was imported or added"
        _vscode_cleanup "$keyfile"
        return 1
    fi
    io_debug "vscode: repository key fingerprint verified: $found"
    _vscode_import_and_add "$family" "$keyfile" || rc=$?
    _vscode_cleanup "$keyfile"
    return "$rc"
}

_vscode_prerepo_dry() {
    local family="${1:-}" keyarg="" drykey="${TMPDIR:-/tmp}/fedora-setup-vscode-key.dry"
    run_cmd "vscode: fetch repository key" -- \
        curl -fsSL --proto '=https' --tlsv1.2 -o "$drykey" "$_VSCODE_KEY_URL" || return 1
    if [[ "$family" == rpm ]]; then
        run_sudo "vscode: import repository key" -- rpm --import "$drykey" || return 1
    else
        keyarg="${FS_VSCODE_KEYRING:-$_VSCODE_KEYRING}"
        run_sudo "vscode: install repository keyring" -- \
            gpg --batch --yes --dearmor --output "$keyarg" "$drykey" || return 1
    fi
    if [[ "$family" == rpm ]]; then
        pkg_add_repo vscode "$_VSCODE_RPM_BASEURL" || return 1
    else
        pkg_add_repo vscode "$_VSCODE_DEB_REPO" "$keyarg" || return 1
    fi
    pkg_update_metadata || return 1
    return 0
}

prerepo() {
    local family="${FS_MODULE_FAMILY:-}"
    if [[ -n "$(module_flatpak_alt)" ]]; then
        io_debug "vscode: flatpak alternative selected, no repository needed"
        return 0
    fi
    if [[ -z "$family" ]]; then
        io_error "vscode: FS_MODULE_FAMILY is not set (cannot choose a repository layout)"
        return 1
    fi
    case "$family" in
        rpm | deb) ;;
        arch)
            io_warn "vscode: no official Arch package (AUR visual-studio-code-bin needs an AUR helper); use FS_VSCODE_FLATPAK=1 for the flatpak build"
            return 0
            ;;
        *)
            io_error "vscode: unsupported family '$family'"
            return 1
            ;;
    esac
    if (( FS_DRY_RUN == 1 )); then
        _vscode_prerepo_dry "$family"
        return $?
    fi
    _vscode_prerepo_real "$family"
}
