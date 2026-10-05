#!/usr/bin/env bash
# modules/chrome/hooks.sh - run()/verify() for the Google Chrome module
# (P7.6). Sourced by lib/runner.sh inside a hook subshell, which has
# already exported FS_MODULE_FAMILY and run `module_load "$dir" strict`,
# so the metadata is this module's own and the family is never re-detected.
# Depends on lib/io.sh, lib/run.sh and the pkg layer (pkg_install_local),
# all of which the runner's install path has already sourced.
#
# The native path is a FLOATING-VERSION BUNDLE, resolved at run time: the
# vendor index gives an exact (URL, SHA-256) pair for google-chrome-stable
# and both fields come from the same stanza, so the bytes checked are the
# bytes the metadata described. See modules/chrome/module.sh for the URL
# table, the reason no version is pinned in this repo, and the explicit
# trust-boundary note: the SHA-256 check detects tampering and corruption
# in transit, but the index is trusted over HTTPS, NOT via a pinned GPG key
# (unlike P7.5). Do not call this signature verification. Because the index
# and the bundle arrive over the SAME TLS channel to dl.google.com, the digest
# does not compensate for that channel either: it buys corruption detection
# and a divergent mirror/CDN edge, nothing against a compromised vendor host
# or a CA.
#
# BOUNDED NETWORK: both fetches pass --timeout and --tries so a stalled
# vendor connection cannot hang the whole install run forever. The scheme is
# https in every URL by construction (the bases are file-level constants and
# only a repo-relative path is ever appended), which is why wget's
# non-portable --https-only flag is not needed.
#
# FAIL-CLOSED MATRIX (every one of these returns 1 and installs nothing):
#   - flatpak alternative selected -> the whole native path is skipped, not
#     an error, so the two paths can never run side by side in one run
#   - arch family -> warn + no-op (no official Arch package; the AUR needs
#     an AUR helper this tool does not manage)
#   - family other than rpm/deb -> error
#   - unsupported host architecture -> error
#   - wget or sha256sum missing -> error
#   - staging directory cannot be created -> error
#   - vendor index fetch fails, or is malformed, or has no
#     google-chrome-stable stanza, or the stanza has no digest -> error
#   - a resolved path is absolute, contains a `..` segment, or has
#     whitespace/control characters -> error
#   - bundle download fails -> error
#   - digest mismatch -> error, the downloaded file is removed and never
#     handed to the package manager
#   - the local install does not take effect -> error (see below)
#
# WHY THE INSTALL IS CHECKED BY POSTCONDITION, NOT BY rc. The P3
# `pkg_install_local` cannot report a failed install: rpm/deb call
# `run_sudo "install local package" -- ...` with no `--stop`, and run_cmd's
# keep-going default logs `command failed (rc=N)` and returns 0. A module
# that trusted that rc would report success, let the runner mark itself done
# and never retry a browser that was never installed. So the rc is treated as
# non-authoritative and the real gate is the postcondition, exactly like the
# established `pkg_add_repo` rule in lib/pkg.sh: a seam whose rc cannot be
# trusted is followed by a check of what it was supposed to produce. If
# `pkg_query_installed google-chrome-stable` is not rc0 after the call, this
# is a failure. Do not "simplify" this back to trusting the rc.
#
# WHAT THE POSTCONDITION DOES NOT CLAIM. It asks "is google-chrome-stable
# installed", not "did my command succeed". Two consequences worth knowing:
# a host that ALREADY has Chrome passes the check even if this run's install
# failed, because the user does have the browser (a version bump that
# silently did not happen is the one case this cannot detect); and forcing
# FS_PKG_BACKEND=mock for a real run makes this module FAIL, because
# mock_install_local records no package name to query. That is the honest
# outcome -- a mock run installs nothing, so nothing is installed -- and it
# is why the fixture drives the install path through the real rpm/deb seams.
##
# CLEANUP: the staging directory is removed on every exit path, and INT/TERM
# are trapped once it exists, so an interrupted run leaves no 142 MB bundle
# behind either (only an untrappable SIGKILL can).
#
# DRY-RUN, and the one honest limit of it. Dry-run renders the metadata
# fetch with the REAL, statically-derivable index URL (family + arch are
# known without touching the network), then the bundle download, then
# reports the local-install step. The bundle's own URL is deliberately NOT
# rendered: it only exists after resolving the index, and a side-effect-
# free dry run may not fetch it. So the second wget line carries the
# literal marker RESOLVED-AT-RUN-TIME instead of a fabricated URL, and the
# digest check plus pkg_install_local are named in the surrounding info
# lines rather than faked as commands. Dry-run therefore still writes
# nothing, creates no staging dir, and never reaches the network.
#
# WHY DRY-RUN DOES NOT CALL pkg_install_local: the P3 seam opens with
# `[[ ! -f "$file" ]]` (lib/pkg/{rpm,deb}.sh), so it requires a real file
# to already exist. A zero-write dry run has none, so calling it would
# either fail every dry run or force a write. Rather than weaken a
# reviewed P3 precondition for every other caller, the install step is
# reported instead of executed; the real path calls pkg_install_local
# normally. This is recorded as a known limitation, not a silent gap.
#
# Seams: FS_CHROME_FLATPAK, FS_CHROME_ARCH, FS_CHROME_DESKTOP_DIR.
set -euo pipefail

_CHROME_PKG=google-chrome-stable
_CHROME_DEB_BASE=https://dl.google.com/linux/chrome/deb
_CHROME_RPM_BASE=https://dl.google.com/linux/chrome/rpm/stable
_CHROME_TMP_PREFIX=fedora-setup-chrome
_CHROME_MARKER=RESOLVED-AT-RUN-TIME

_chrome_host_arch() {
    local m="${FS_CHROME_ARCH:-}"
    case "$m" in
    x86_64 | amd64)
        printf 'x86_64\n'
        return 0
        ;;
    aarch64 | arm64)
        printf 'aarch64\n'
        return 0
        ;;
    "")
        m="$(uname -m)"
        case "$m" in
        x86_64 | amd64) printf 'x86_64\n' ;;
        aarch64 | arm64) printf 'aarch64\n' ;;
        *)
            io_debug "chrome: unsupported host arch '$m'"
            return 1
            ;;
        esac
        return 0
        ;;
    *)
        io_debug "chrome: unsupported FS_CHROME_ARCH '$m'"
        return 1
        ;;
    esac
}

_chrome_deb_arch() {
    case "$1" in
    x86_64) printf 'amd64\n' ;;
    aarch64) printf 'arm64\n' ;;
    *) return 1 ;;
    esac
}

_chrome_rpm_arch() {
    case "$1" in
    x86_64 | aarch64) printf '%s\n' "$1" ;;
    *) return 1 ;;
    esac
}

_chrome_index_url() {
    case "$1" in
    deb) printf '%s/dists/stable/main/binary-%s/Packages\n' "$_CHROME_DEB_BASE" "$2" ;;
    rpm) printf '%s/%s/repodata/primary.xml.gz\n' "$_CHROME_RPM_BASE" "$2" ;;
    *) return 1 ;;
    esac
}

_chrome_path_ok() {
    local p="$1" seg=""
    if [[ -z "$p" ]]; then
        return 1
    fi
    if [[ "$p" == /* ]]; then
        return 1
    fi
    if [[ "$p" == *" "* || "$p" == *$'\t'* || "$p" == *$'\n'* || "$p" == *$'\r'* ]]; then
        return 1
    fi
    case "/$p/" in
    */../* | */./*) return 1 ;;
    esac
    while [[ "$p" == */* ]]; do
        seg="${p%%/*}"
        p="${p#*/}"
        if [[ -z "$seg" ]]; then
            return 1
        fi
    done
    return 0
}

_chrome_sha_ok() {
    [[ "$1" =~ ^[0-9a-f]{64}$ ]]
}

_chrome_sha256() {
    local out=""
    out="$(sha256sum -- "$1")" || return 1
    out="${out%% *}"
    if ! _chrome_sha_ok "$out"; then
        return 1
    fi
    printf '%s\n' "$out"
}

_chrome_parse_deb() {
    local file="$1" line="" fn="" sha="" inside=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == 'Package: '* ]]; then
            if ((inside == 1)); then
                break
            fi
            if [[ "${line#Package: }" == "$_CHROME_PKG" ]]; then
                inside=1
            fi
            continue
        fi
        if ((inside != 1)); then
            continue
        fi
        case "$line" in
        Filename:\ *) fn="${line#Filename: }" ;;
        SHA256:\ *) sha="${line#SHA256: }" ;;
        esac
    done <"$file"
    if ((inside != 1)); then
        io_error "chrome: no $_CHROME_PKG stanza in the deb index"
        return 1
    fi
    if [[ -z "$fn" ]]; then
        io_error "chrome: $_CHROME_PKG stanza has no Filename"
        return 1
    fi
    if [[ -z "$sha" ]]; then
        io_error "chrome: $_CHROME_PKG stanza has no SHA256"
        return 1
    fi
    if ! _chrome_path_ok "$fn"; then
        io_error "chrome: refusing unsafe Filename from the deb index"
        return 1
    fi
    if ! _chrome_sha_ok "$sha"; then
        io_error "chrome: refusing a non-sha256 digest from the deb index"
        return 1
    fi
    printf '%s/%s %s\n' "$_CHROME_DEB_BASE" "$fn" "$sha"
}

_chrome_parse_rpm() {
    local file="$1" arch="$2" line="" rest="" href="" sha="" inside=0
    if ! command -v gzip >/dev/null 2>&1; then
        io_error "chrome: gzip is required to read the rpm index"
        return 1
    fi
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == *'<package '* ]]; then
            inside=0
        fi
        if [[ "$line" == *"<name>$_CHROME_PKG</name>"* ]]; then
            inside=1
            continue
        fi
        if ((inside != 1)); then
            continue
        fi
        if [[ "$line" == *'<checksum type="sha256"'* ]]; then
            rest="${line#*>}"
            sha="${rest%%</checksum>*}"
        fi
        if [[ "$line" == *'<location href="'* ]]; then
            rest="${line#*href=\"}"
            href="${rest%%\"*}"
        fi
        if [[ -n "$href" && -n "$sha" ]]; then
            break
        fi
    done < <(gzip -dc -- "$file" 2>/dev/null)
    if [[ -z "$href" ]]; then
        io_error "chrome: no $_CHROME_PKG location in the rpm index"
        return 1
    fi
    if [[ -z "$sha" ]]; then
        io_error "chrome: $_CHROME_PKG has no sha256 checksum in the rpm index"
        return 1
    fi
    if ! _chrome_path_ok "$href"; then
        io_error "chrome: refusing unsafe location from the rpm index"
        return 1
    fi
    if ! _chrome_sha_ok "$sha"; then
        io_error "chrome: refusing a non-sha256 checksum from the rpm index"
        return 1
    fi
    printf '%s/%s/%s %s\n' "$_CHROME_RPM_BASE" "$arch" "$href" "$sha"
}

run() {
    local family="${FS_MODULE_FAMILY:-}" alt="" host="" arch="" ext="" idx=""
    local tmp="" stage="" parsed="" url="" sha="" actual=""
    if ! alt="$(module_flatpak_alt)"; then
        io_error "chrome: could not resolve the flatpak alternative; refusing to pick a side"
        return 1
    fi
    if [[ -n "$alt" ]]; then
        io_info "chrome: flatpak alternative '$alt' selected; native bundle skipped"
        return 0
    fi
    if [[ "$family" == "arch" ]]; then
        io_warn "chrome: no native Arch package exists (the AUR needs an AUR helper); skipping the native bundle -- set FS_CHROME_FLATPAK=1 for the flatpak"
        return 0
    fi
    if [[ "$family" != "rpm" && "$family" != "deb" ]]; then
        io_error "chrome: no native bundle path for family '$family'"
        return 1
    fi
    host="$(_chrome_host_arch)" || {
        io_error "chrome: unsupported host architecture; refusing to guess a vendor bundle"
        return 1
    }
    if [[ "$family" == "deb" ]]; then
        arch="$(_chrome_deb_arch "$host")" || return 1
        ext=deb
    else
        arch="$(_chrome_rpm_arch "$host")" || return 1
        ext=rpm
    fi
    idx="$(_chrome_index_url "$family" "$arch")" || return 1
    if ((FS_DRY_RUN == 1)); then
        tmp="${TMPDIR:-/tmp}/${_CHROME_TMP_PREFIX}.XXXXXX"
        stage="$tmp/$_CHROME_PKG.$ext"
        run_cmd "fetch chrome metadata" --stop -- wget -q --timeout=300 --tries=2 -O "$tmp/index" "$idx" || return 1
        io_info "chrome: the bundle url and its sha256 resolve from that index at run time; the digest is then checked before any install"
        run_cmd "download chrome bundle" --stop -- wget -q --timeout=300 --tries=2 -O "$stage" "$_CHROME_MARKER" || return 1
        io_info "chrome: the real run then installs that file with the $(pkg_backend) backend via pkg_install_local"
        return 0
    fi
    if ! command -v wget >/dev/null 2>&1; then
        io_error "chrome: wget not found; it is required to fetch the vendor index and bundle"
        return 1
    fi
    if ! command -v sha256sum >/dev/null 2>&1; then
        io_error "chrome: sha256sum not found; it is required to verify the bundle digest"
        return 1
    fi
    if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/${_CHROME_TMP_PREFIX}.XXXXXX")"; then
        io_error "chrome: cannot create a staging directory"
        return 1
    fi
    trap 'rm -rf -- "$tmp"' INT TERM
    if ! run_cmd "fetch chrome metadata" --stop -- wget -q --timeout=300 --tries=2 -O "$tmp/index" "$idx"; then
        rm -rf -- "$tmp"
        return 1
    fi
    if [[ "$family" == "deb" ]]; then
        if ! parsed="$(_chrome_parse_deb "$tmp/index")"; then
            rm -rf -- "$tmp"
            return 1
        fi
    else
        if ! parsed="$(_chrome_parse_rpm "$tmp/index" "$arch")"; then
            rm -rf -- "$tmp"
            return 1
        fi
    fi
    url="${parsed%% *}"
    sha="${parsed##* }"
    stage="$tmp/$_CHROME_PKG.$ext"
    if ! run_cmd "download chrome bundle" --stop -- wget -q --timeout=300 --tries=2 -O "$stage" "$url"; then
        rm -rf -- "$tmp"
        return 1
    fi
    if ! actual="$(_chrome_sha256 "$stage")"; then
        io_error "chrome: could not compute the downloaded bundle digest"
        rm -rf -- "$tmp"
        return 1
    fi
    if [[ "$actual" != "$sha" ]]; then
        io_error "chrome: bundle digest mismatch (index says $sha, download gave $actual); refusing to install"
        rm -rf -- "$tmp"
        return 1
    fi
    io_debug "chrome: bundle digest verified ($sha)"
    if ! pkg_install_local "$stage"; then
        rm -rf -- "$tmp"
        return 1
    fi
    if ! pkg_query_installed "$_CHROME_PKG"; then
        io_error "chrome: pkg_install_local returned but $_CHROME_PKG is still not installed; the local-install rc is not authoritative, so this is a failure"
        rm -rf -- "$tmp"
        return 1
    fi
    rm -rf -- "$tmp"
    return 0
}

verify() {
    local dir="" f="" alt="" root
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || return 1
    declare -F _verify_hook >/dev/null 2>&1 || source "$root/lib/verify.sh"
    if ((FS_DRY_RUN == 1)); then
        io_info "chrome: verify is read-only; runs only in real mode"
        return 0
    fi
    if ! alt="$(module_flatpak_alt)"; then
        return 1
    fi
    if [[ -n "$alt" ]]; then
        io_info "chrome: the flatpak alternative is selected; the desktop-entry check covers the native bundle only"
        return "$_VERIFY_HOOK_SKIP"
    fi
    if [[ "${FS_MODULE_FAMILY:-}" == "arch" ]]; then
        io_info "chrome: no native Arch bundle is installed; nothing to verify"
        return "$_VERIFY_HOOK_SKIP"
    fi
    dir="${FS_CHROME_DESKTOP_DIR:-/usr/share/applications}"
    for f in "$dir/google-chrome.desktop" "$dir/com.google.Chrome.desktop"; do
        if [[ -f "$f" ]]; then
            io_info "chrome: verify ok: desktop entry present: $f"
            return 0
        fi
    done
    io_error "chrome: verify FAILED: no chrome desktop entry in $dir (looked for google-chrome.desktop and com.google.Chrome.desktop)"
    return 1
}
