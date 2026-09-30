#!/usr/bin/env bash
# scripts/install-tools.sh - download the static-analysis tools into tools/ (P10.2).
# tools/ is gitignored (never committed).
#
# shellcheck is PINNED (v0.11.0) and SHA-256-verified. shfmt is downloaded via
# `dnf download` (latest from the configured repos) because Fedora does not
# publish stable per-release RPM URLs; the lint script pins the shfmt RULES
# (-i 4), which is what actually matters for reproducibility.
#
# Usage: bash scripts/install-tools.sh

set -euo pipefail

SHELLCHECK_VERSION="v0.11.0"
SHELLCHECK_URL="https://github.com/koalaman/shellcheck/releases/download/${SHELLCHECK_VERSION}/shellcheck-${SHELLCHECK_VERSION}.linux.x86_64.tar.xz"
SHELLCHECK_SHA256="8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198"

SHFMT_VERSION="3.7.0"
SHFMT_RPM="shfmt-3.7.0-5.fc41.x86_64.rpm"

_this="${BASH_SOURCE[0]}"
_this="$(readlink -f -- "$_this" 2>/dev/null || printf '%s' "$_this")"
ROOT="$(cd "$(dirname "$_this")/.." && pwd)"
DEST="$ROOT/tools"

if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ]]; then
    printf 'install-tools: only linux/x86_64 is supported (this host: %s/%s)\n' \
        "$(uname -s)" "$(uname -m)" >&2
    exit 1
fi

mkdir -p "$DEST"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

# --- shellcheck (static binary) ---
if [[ ! -x "$DEST/shellcheck" ]]; then
    printf 'downloading shellcheck %s...\n' "$SHELLCHECK_VERSION"
    curl -fsSL -o "$tmp/sc.tar.xz" "$SHELLCHECK_URL"
    echo "$SHELLCHECK_SHA256  $tmp/sc.tar.xz" | sha256sum -c - >/dev/null 2>&1 || {
        printf '%s\n' "shellcheck download checksum mismatch" >&2
        exit 1
    }
    tar -xJf "$tmp/sc.tar.xz" -C "$tmp"
    cp "$tmp/shellcheck-$SHELLCHECK_VERSION/shellcheck" "$DEST/shellcheck"
    chmod +x "$DEST/shellcheck"
fi
printf 'shellcheck: %s\n' "$("$DEST/shellcheck" --version 2>/dev/null | sed -n 's/^version: //p')"

# --- shfmt (extracted from the Fedora RPM; no root required) ---
if [[ ! -x "$DEST/shfmt" ]]; then
    printf 'downloading shfmt %s...\n' "$SHFMT_VERSION"
    ( cd "$tmp" && dnf download shfmt >/dev/null 2>&1 )
    rpm=$(ls "$tmp"/shfmt-*.rpm 2>/dev/null | head -1)
    if [[ -z "$rpm" ]]; then
        printf '%s\n' "shfmt download failed (dnf download shfmt)" >&2
        exit 1
    fi
    rpm2cpio "$rpm" | cpio -idm --quiet
    cp "$tmp/usr/bin/shfmt" "$DEST/shfmt"
    chmod +x "$DEST/shfmt"
fi
printf 'shfmt: %s\n' "$("$DEST/shfmt" --version 2>/dev/null || printf '%s' "$SHFMT_VERSION")"

printf 'installed tools at %s\n' "$DEST"
