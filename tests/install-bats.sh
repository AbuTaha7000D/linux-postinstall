#!/usr/bin/env bash
# tests/install-bats.sh - pinned download of bats-core into tests/bats/ (P10.1).
# Avoids submodule friction (ROADMAP P10 risk note): the CI install step and
# tests/run both call this when the vendored copy is absent.
#
# Pinned to a specific release tag. Bump BATS_VERSION to upgrade; the version
# is recorded here so a reviewer can see exactly what is being pulled.

set -euo pipefail

BATS_VERSION="v1.14.0"
BATS_URL="https://github.com/bats-core/bats-core/archive/refs/tags/${BATS_VERSION}.tar.gz"
BATS_SHA256="bb537b70b15b732f6d8827dd6578e3d8ce166636ce1f18ea9a074184fcce9177"

_this="${BASH_SOURCE[0]}"
_this="$(readlink -f -- "$_this" 2>/dev/null || printf '%s' "$_this")"
ROOT="$(cd "$(dirname "$_this")/.." && pwd)"
DEST="$ROOT/tests/bats"

if [[ -x "$DEST/bin/bats" ]]; then
    printf 'bats %s already installed at %s\n' "$("$DEST/bin/bats" --version 2>/dev/null || printf '%s' "$BATS_VERSION")" "$DEST"
    exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

printf 'downloading bats-core %s...\n' "$BATS_VERSION"
curl -fsSL -o "$tmp/bats.tar.gz" "$BATS_URL"

# Verify the download against a pinned digest before extracting (§9 security
# stance: a pinned version is not a pinned artifact without a checksum).
echo "$BATS_SHA256  $tmp/bats.tar.gz" | sha256sum -c - >/dev/null 2>&1 || {
    printf '%s\n' "bats download checksum mismatch" >&2
    exit 1
}

tar -xzf "$tmp/bats.tar.gz" -C "$tmp" --strip-components=1
rm -f -- "$tmp/bats.tar.gz"

rm -rf -- "$DEST"
mkdir -p -- "$DEST"
# --strip-components=1 puts the release contents directly in $tmp
cp -a "$tmp/." "$DEST/"
chmod +x "$DEST/bin/bats"

printf 'installed %s at %s\n' "$("$DEST/bin/bats" --version)" "$DEST"
