#!/usr/bin/env bash
# scripts/install-tools.sh - download the static-analysis tools into tools/
# (P10.2; reworked by P11-R D1). tools/ is gitignored (never committed).
#
# BOTH tools are pinned by version AND SHA-256 and installed as plain static
# executables, so provisioning needs nothing but a Linux x86_64 host with
# curl, tar, xz and sha256sum -- plus the ordinary coreutils and sed it already
# assumed before D1 (cp, chmod, mv, rm, mkdir, mktemp, readlink, dirname,
# uname). Only the first four are CHECKED up front, because those are the ones
# whose absence produces a confusing failure far from the cause: xz is needed
# by `tar -xJf` and would otherwise only complain after the whole download. It
# is deliberately NOT distro-package-based, which is what makes the same script
# work on a Fedora workstation AND on the ubuntu-latest CI runner. The lint
# script pins the shfmt RULES (-i 4), which is what actually matters for
# reproducibility.
#
# WHY THIS CHANGED (P11-R D1, ROADMAP finding F2). shfmt used to be fetched
# with `dnf download shfmt` and unpacked with `rpm2cpio | cpio`. That chain is
# rpm-family-only and the CI lint job runs on ubuntu-latest, where dnf,
# rpm2cpio and cpio do not exist -- so the lint job could NEVER provision its
# own tooling. Worse, the failure was SILENT: the call was
#   ( cd "$tmp" && dnf download shfmt >/dev/null 2>&1 )
# under `set -e`, so the shell aborted with the failing command's own status
# (127, command not found) BEFORE the `shfmt download failed` guard below could
# print anything. CI therefore showed "downloading shfmt 3.7.0..." and then a
# bare red step with no explanation -- the guard was unreachable dead code on
# exactly the host it was written for. A `dnf download` is also UNPINNED (it
# takes whatever the configured repos currently offer), which silently
# contradicted the SHFMT_VERSION this script printed. shfmt publishes a static
# linux_amd64 release binary, so the rpm chain was never necessary on any
# distro; CI and a Fedora workstation now provision IDENTICAL, digest-verified
# bytes.
#
# The two digests below were measured from the official upstream GitHub release
# assets over HTTPS and confirmed by two independent transfers each. The same
# policy already pins shellcheck (v0.11.0) and bats-core (v1.14.0). The pin IS
# the defence: any future drift fails the checksum loudly instead of quietly
# linting with a different tool than the one the ledger recorded. These are
# download-integrity digests, NOT vendor signature verification.
#
# Every provisioning step below reports its own failure and exits non-zero
# explicitly. What the original defect had was not the absence of `set -e` but
# the SUPPRESSION of a diagnostic -- `>/dev/null 2>&1` around the download --
# so the stated property is the one that holds: no step here suppresses its own
# error output, and no step can be reported as successful without a
# postcondition confirming the effect. (`ROOT=`, `mkdir -p "$DEST"` and
# `mktemp -d` are not individually checked; each still prints its own message,
# which is the distinction that matters here.) Each install also re-checks the
# INSTALLED tool (digest for shfmt, which is the downloaded file verbatim; a
# working pinned-version query for shellcheck, whose extracted binary is not
# byte-identical to the tarball) so a partial or
# corrupted copy cannot be reported as a successful provisioning.
#
# Usage: bash scripts/install-tools.sh

set -euo pipefail

SHELLCHECK_VERSION="v0.11.0"
SHELLCHECK_URL="https://github.com/koalaman/shellcheck/releases/download/${SHELLCHECK_VERSION}/shellcheck-${SHELLCHECK_VERSION}.linux.x86_64.tar.xz"
SHELLCHECK_SHA256="8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198"

SHFMT_VERSION="v3.7.0"
SHFMT_URL="https://github.com/mvdan/sh/releases/download/${SHFMT_VERSION}/shfmt_${SHFMT_VERSION}_linux_amd64"
SHFMT_SHA256="0264c424278b18e22453fe523ec01a19805ce3b8ebf18eaf3aadc1edc23f42e3"

_this="${BASH_SOURCE[0]}"
_this="$(readlink -f -- "$_this" 2>/dev/null || printf '%s' "$_this")"
ROOT="$(cd "$(dirname "$_this")/.." && pwd)"
DEST="$ROOT/tools"

if [[ "${BASH_VERSINFO[0]:-0}" -lt 4 || ("${BASH_VERSINFO[0]:-0}" -eq 4 && "${BASH_VERSINFO[1]:-0}" -lt 3) ]]; then
    printf 'install-tools: bash >= 4.3 is required (this host: %s)\n' "${BASH_VERSION:-unknown}" >&2
    exit 1
fi

if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ]]; then
    printf 'install-tools: only linux/x86_64 is supported (this host: %s/%s)\n' \
        "$(uname -s)" "$(uname -m)" >&2
    printf 'install-tools: both pinned assets are published as amd64/x86_64 release binaries only\n' >&2
    exit 1
fi

# Report every missing prerequisite at once, by name. Without this the script
# failed later and less clearly: `tar -xJf` needs the xz binary, which a minimal
# image may lack, and the only symptom was tar's own complaint mid-download.
missing=()
for _tool in curl tar xz sha256sum; do
    command -v "$_tool" >/dev/null 2>&1 || missing+=("$_tool")
done
if ((${#missing[@]} > 0)); then
    printf 'install-tools: missing required provisioning tool(s): %s\n' "${missing[*]}" >&2
    printf 'install-tools: this script only downloads pinned release binaries; it installs no packages.\n' >&2
    exit 1
fi

mkdir -p "$DEST"
tmp="$(mktemp -d)"
_STAGE=""
trap 'rm -rf -- "$tmp"; if [[ -n "${_STAGE:-}" ]]; then rm -f -- "$_STAGE" 2>/dev/null || :; fi' EXIT INT TERM

# Install one verified tool into tools/ as an ATOMIC write: stage a sibling temp
# file in the SAME directory, mark it executable there, then rename over the
# destination. The rename is the only step that changes what tools/ contains, so
# a FAILING run can never leave a half-written executable behind -- the repo's
# rule for every write this project makes. An INTERRUPTED one can leave the
# staging file, which is why the EXIT/INT/TERM trap above removes it and why the
# name follows the repo's `*.XXXXXX` convention.
#
# The staging name comes from mktemp, so it is unpredictable and created with
# O_EXCL. That is not decoration. A predictable name derived from the pid
# (`$dest.install.$$`) is a path an attacker can pre-create as a SYMLINK, and
# `cp -- src symlink` writes THROUGH it: measured, a 24-byte file outside tools/
# grew to the full 2.9MB tool while the script printed nothing and exited 0. The
# destination side needs no such care, because `mv -f` replaces a symlink rather
# than following it.
#
# It also reports its own failure instead of leaning on `set -e`. A bare `cp`
# was the last step in this script that could abort carrying nothing but the
# shell's own "cp: cannot create regular file ...: Permission denied", with no
# install-tools: diagnostic, which is the very failure mode D1 exists to remove
# (an aborted step whose reason never reaches the operator).
_install_tool() {
    local src="$1" dest="$2" label="$3" stage
    if ! stage="$(mktemp "$DEST/.tool-install.XXXXXX")"; then
        printf 'install-tools: could not create a staging file in %s\n' "$DEST" >&2
        printf 'install-tools: check that %s exists and is writable, then re-run\n' "$DEST" >&2
        exit 1
    fi
    _STAGE="$stage"
    if ! cp -- "$src" "$stage"; then
        printf 'install-tools: could not stage %s into %s\n' "$label" "$DEST" >&2
        printf 'install-tools: check free space and permissions on %s, then re-run\n' "$DEST" >&2
        rm -f -- "$stage" 2>/dev/null || :
        _STAGE=""
        exit 1
    fi
    if ! chmod 0755 "$stage"; then
        printf 'install-tools: could not make the staged %s executable\n' "$label" >&2
        rm -f -- "$stage" 2>/dev/null || :
        _STAGE=""
        exit 1
    fi
    if ! mv -f -- "$stage" "$dest"; then
        printf 'install-tools: could not install %s into %s\n' "$label" "$DEST" >&2
        rm -f -- "$stage" 2>/dev/null || :
        _STAGE=""
        exit 1
    fi
    _STAGE=""
}

# --- shellcheck (static binary from the upstream release tarball) ---
if [[ ! -x "$DEST/shellcheck" ]]; then
    printf 'downloading shellcheck %s...\n' "$SHELLCHECK_VERSION"
    if ! curl -fsSL -o "$tmp/sc.tar.xz" "$SHELLCHECK_URL"; then
        printf 'install-tools: shellcheck download failed: %s\n' "$SHELLCHECK_URL" >&2
        exit 1
    fi
    if ! printf '%s  %s\n' "$SHELLCHECK_SHA256" "$tmp/sc.tar.xz" | sha256sum -c - >/dev/null 2>&1; then
        printf 'install-tools: shellcheck checksum mismatch (expected %s); refusing to install\n' \
            "$SHELLCHECK_SHA256" >&2
        exit 1
    fi
    if ! tar -xJf "$tmp/sc.tar.xz" -C "$tmp"; then
        printf 'install-tools: shellcheck archive extraction failed: %s\n' "$tmp/sc.tar.xz" >&2
        exit 1
    fi
    if [[ ! -f "$tmp/shellcheck-${SHELLCHECK_VERSION}/shellcheck" ]]; then
        printf 'install-tools: shellcheck archive did not contain shellcheck-%s/shellcheck\n' \
            "$SHELLCHECK_VERSION" >&2
        exit 1
    fi
    _install_tool "$tmp/shellcheck-${SHELLCHECK_VERSION}/shellcheck" "$DEST/shellcheck" "shellcheck"
fi

# Postcondition: the tool that will actually be executed is the pinned one.
_sc_version="$("$DEST/shellcheck" --version 2>/dev/null | sed -n 's/^version: //p' || true)"
if [[ "$_sc_version" != "${SHELLCHECK_VERSION#v}" ]]; then
    printf 'install-tools: installed shellcheck reports version [%s], expected [%s]; refusing to continue\n' \
        "$_sc_version" "${SHELLCHECK_VERSION#v}" >&2
    printf 'install-tools: if it was already present, remove %s and re-run to reinstall the pinned build\n' \
        "$DEST/shellcheck" >&2
    exit 1
fi
printf 'shellcheck: %s\n' "$_sc_version"

# --- shfmt (static binary from the upstream release; no rpm anywhere) ---
if [[ ! -x "$DEST/shfmt" ]]; then
    printf 'downloading shfmt %s...\n' "$SHFMT_VERSION"
    if ! curl -fsSL -o "$tmp/shfmt" "$SHFMT_URL"; then
        printf 'install-tools: shfmt download failed: %s\n' "$SHFMT_URL" >&2
        exit 1
    fi
    if ! printf '%s  %s\n' "$SHFMT_SHA256" "$tmp/shfmt" | sha256sum -c - >/dev/null 2>&1; then
        printf 'install-tools: shfmt checksum mismatch (expected %s); refusing to install\n' \
            "$SHFMT_SHA256" >&2
        exit 1
    fi
    _install_tool "$tmp/shfmt" "$DEST/shfmt" "shfmt"
fi

# Postcondition: shfmt IS the downloaded file, so re-verify the INSTALLED copy
# rather than trusting that `cp` wrote all of it.
if ! printf '%s  %s\n' "$SHFMT_SHA256" "$DEST/shfmt" | sha256sum -c - >/dev/null 2>&1; then
    printf 'install-tools: installed shfmt does not match the pinned digest %s\n' \
        "$SHFMT_SHA256" >&2
    printf 'install-tools: if it was already present, remove %s and re-run to reinstall the pinned build\n' \
        "$DEST/shfmt" >&2
    exit 1
fi
_fmt_version="$("$DEST/shfmt" --version 2>/dev/null || true)"
if [[ "$_fmt_version" != "$SHFMT_VERSION" ]]; then
    printf 'install-tools: installed shfmt reports version [%s], expected [%s]; refusing to continue\n' \
        "$_fmt_version" "$SHFMT_VERSION" >&2
    printf 'install-tools: a shfmt left by the pre-D1 `dnf download` path reports no version at all;\n' >&2
    printf 'install-tools: remove %s and re-run to install the pinned static build.\n' "$DEST/shfmt" >&2
    exit 1
fi
printf 'shfmt: %s\n' "$_fmt_version"

printf 'installed tools at %s\n' "$DEST"
