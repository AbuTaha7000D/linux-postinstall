#!/usr/bin/env bash
# tests/fixtures/mod_fonts.sh - P5.4 fixture for the `fonts` module.
# Drives the REAL repo modules/ + profiles/ + config/ through ./setup install.
# Covers: per-family font-package batch (exact rendered line, family
# precision); nerd-font dry-run listing the EXACT pinned download URLs +
# extract + fc-cache plan (in order, after the package batch, with zero
# writes); local-source real install (embedded reproducible zip fixtures,
# sha256-verified) landing files + per-asset markers; hook-level re-run skip
# (markers present -> no re-copy/extract, marker mtime stable); sha256
# mismatch fail-closed (module failed, rc1); mock installed-state for the
# package half; `setup list` rows. XDG_CACHE_HOME is redirected to scratch so
# fc-cache never touches the real user cache. Nothing outside FX_TMP + the
# real repo modules/profiles/config is touched; no network is ever hit
# (local-source seam).
# Usage: bash tests/fixtures/mod_fonts.sh  (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init
mkdir -p "$FX_TMP/I" "$FX_TMP/h" "$FX_TMP/ff" "$FX_TMP/fonts" "$FX_TMP/xc"

printf 'P5.4 fonts module\n'

SETUP="$ROOT/setup"
LOG="$FX_TMP/I/fonts.log"
INST="$FX_TMP/I/fonts.inst"
FONTS="$FX_TMP/fonts"

FIRA_B64='UEsDBAoAAAAAAGNOO10AAAAAAAAAAAAAAAATABwARmlyYUNvZGUgTmVyZCBGb250L1VUCQAD2ry4atq8uGp1eAsAAQToAwAABOgDAABQSwMECgAAAAAAY047XaSfmukXAAAAFwAAACEAHABGaXJhQ29kZSBOZXJkIEZvbnQvRmlyYUNvZGVORi5vdGZVVAkAA9q8uGravLhqdXgLAAEE6AMAAAToAwAAZmFrZSBmb250IGdseXBocwpsaW5lMgpQSwECHgMKAAAAAABjTjtdAAAAAAAAAAAAAAAAEwAYAAAAAAAAABAA7UEAAAAARmlyYUNvZGUgTmVyZCBGb250L1VUBQAD2ry4anV4CwABBOgDAAAE6AMAAFBLAQIeAwoAAAAAAGNOO12kn5rpFwAAABcAAAAhABgAAAAAAAEAAACkgU0AAABGaXJhQ29kZSBOZXJkIEZvbnQvRmlyYUNvZGVORi5vdGZVVAUAA9q8uGp1eAsAAQToAwAABOgDAABQSwUGAAAAAAIAAgDAAAAAvwAAAAAA'
JB_B64='UEsDBAoAAAAAAGVOO10AAAAAAAAAAAAAAAAYABwASmV0QnJhaW5zTW9ubyBOZXJkIEZvbnQvVVQJAAPevLhq3ry4anV4CwABBOgDAAAE6AMAAFBLAwQKAAAAAABlTjtdxnfnIxYAAAAWAAAAKwAcAEpldEJyYWluc01vbm8gTmVyZCBGb250L0pldEJyYWluc01vbm9ORi50dGZVVAkAA968uGrevLhqdXgLAAEE6AMAAAToAwAAZmFrZSBqZXRicmFpbnMgZ2x5cGhzClBLAQIeAwoAAAAAAGVOO10AAAAAAAAAAAAAAAAYABgAAAAAAAAAEADtQQAAAABKZXRCcmFpbnNNb25vIE5lcmQgRm9udC9VVAUAA968uGp1eAsAAQToAwAABOgDAABQSwECHgMKAAAAAABlTjtdxnfnIxYAAAAWAAAAKwAYAAAAAAABAAAApIFSAAAASmV0QnJhaW5zTW9ubyBOZXJkIEZvbnQvSmV0QnJhaW5zTW9ub05GLnR0ZlVUBQAD3ry4anV4CwABBOgDAAAE6AMAAFBLBQYAAAAAAgACAM8AAADNAAAAAAA='

printf '%s' "$FIRA_B64" | base64 -d >"$FX_TMP/ff/FiraCode.zip"
printf '%s' "$JB_B64" | base64 -d >"$FX_TMP/ff/JetBrainsMono.zip"
sha256sum "$FX_TMP/ff/FiraCode.zip" | awk '{print $1}' >"$FX_TMP/ff/FiraCode.zip.sha256"
sha256sum "$FX_TMP/ff/JetBrainsMono.zip" | awk '{print $1}' >"$FX_TMP/ff/JetBrainsMono.zip.sha256"

pkg_cell() {
    local want_family="$1" want_batch="$2" label="$3"
    : >"$LOG"
    : >"$INST"
    (   set -euo pipefail
        export FS_HOME="$FX_TMP/h"
        export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY="$want_family" FS_DRY_RUN=1
        export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
        export FS_MOCK_LOG="$LOG" FS_MOCK_INSTALLED="$INST"
        export FS_FONTS_DIR="$FONTS" FS_NERDFONT_SRC_DIR="$FX_TMP/ff"
        unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
        "$SETUP" install --yes fonts
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "$label rc" 0
    fx_out "^# would run: mock install $want_batch\$"
    if grep -q '^# would run: mock install ' "$FX_OUT"; then
        local n
        n="$(grep -c '^# would run: mock install ' "$FX_OUT")"
        if (( n == 1 )); then fx_ok; else fx_bad "$label single batch (got $n)"; fi
    fi
}

pkg_cell rpm 'google-noto-sans-fonts fira-code-fonts jetbrains-mono-fonts' "fonts pkg rpm"
pkg_cell deb 'fonts-firacode fonts-jetbrains-mono fonts-noto-core' "fonts pkg deb"
pkg_cell arch 'noto-fonts ttf-firacode ttf-jetbrains-mono' "fonts pkg arch"
fx_empty "fonts package dry recorded nothing" "$LOG"
if [[ -e "$FX_TMP/h/.local/state/fedora-setup" ]]; then fx_bad "fonts pkg dry created state dir"; else fx_ok; fi

# nerd-font dry-run: package batch line, then exact download/extract plan per
# entry in config order, then ONE fc-cache plan line; nothing written.
: >"$LOG"
: >"$INST"
rm -rf "$FONTS"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_dry"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm FS_DRY_RUN=1
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export FS_MOCK_LOG="$LOG" FS_MOCK_INSTALLED="$INST"
    export FS_FONTS_DIR="$FONTS"
    unset FS_NERDFONT_SRC_DIR FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes fonts
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "fonts nerd dry rc" 0
fx_out '^# would run: mock install google-noto-sans-fonts fira-code-fonts jetbrains-mono-fonts$'
fx_out '^# would run: download https://github.com/ryanoasis/nerd-fonts/releases/download/v3\.3\.0/FiraCode.zip$'
fx_out '^# would run: verify sha256 and extract FiraCode into '"$FONTS"''
fx_out '^# would run: download https://github.com/ryanoasis/nerd-fonts/releases/download/v3\.3\.0/JetBrainsMono.zip$'
fx_out '^# would run: verify sha256 and extract JetBrainsMono into '"$FONTS"''
fx_out '^# would run: fc-cache (incremental) once per changed set$'
if (( $(grep -c '^# would run: download ' "$FX_OUT") == 2 )); then fx_ok; else fx_bad "nerd dry: not exactly 2 downloads"; fi
if [[ -e "$FONTS" ]]; then fx_bad "nerd dry created fonts dir"; else fx_ok; fi
if [[ -e "$FX_TMP/h_dry/.local/state/fedora-setup" ]]; then fx_bad "nerd dry created state dir"; else fx_ok; fi

# real local-source run: package half via mock, nerd half from FF source
: >"$LOG"
: >"$INST"
rm -rf "$FX_TMP/h_real" "$FONTS" "$FX_TMP/xc"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_real"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export FS_MOCK_LOG="$LOG" FS_MOCK_INSTALLED="$INST"
    export FS_FONTS_DIR="$FONTS" FS_NERDFONT_SRC_DIR="$FX_TMP/ff"
    export XDG_CACHE_HOME="$FX_TMP/xc"
    unset FS_YES FS_PROFILE FS_DRY_RUN FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes fonts
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "fonts real rc" 0
fx_out 'profile: selection'
fx_out 'module: fonts (low)'
fx_out '^== run complete ==$'
fx_out '1 ok'
fx_out 'installed nerd font: FiraCode Nerd Font (v3.3.0)'
fx_out 'installed nerd font: JetBrainsMono Nerd Font (v3.3.0)'
fx_out 'sha256 verified: FiraCode'
fx_out 'sha256 verified: JetBrainsMono'
if grep -qxF 'mock install google-noto-sans-fonts fira-code-fonts jetbrains-mono-fonts' "$LOG"; then fx_ok; else fx_bad "fonts real package batch"; fi
for pkg in google-noto-sans-fonts fira-code-fonts jetbrains-mono-fonts; do
    if grep -qxF "$pkg" "$INST"; then fx_ok; else fx_bad "fonts installed set missing $pkg"; fi
done
for f in \
    "$FONTS/.fedora-setup-nerd-FiraCode-v3.3.0" \
    "$FONTS/.fedora-setup-nerd-JetBrainsMono-v3.3.0" \
    "$FONTS/FiraCode Nerd Font/FiraCodeNF.otf" \
    "$FONTS/JetBrainsMono Nerd Font/JetBrainsMonoNF.ttf"; do
    if [[ -e "$f" ]]; then fx_ok; else fx_bad "fonts expected file missing: $f"; fi
done
if grep -qxF 'fake font glyphs' "$FONTS/FiraCode Nerd Font/FiraCodeNF.otf"; then fx_ok; else fx_bad "fixture otf content wrong"; fi
if grep -qxF 'fake jetbrains glyphs' "$FONTS/JetBrainsMono Nerd Font/JetBrainsMonoNF.ttf"; then fx_ok; else fx_bad "fixture ttf content wrong"; fi
fonts_ls="$(cd "$FONTS" && ls -A | LC_ALL=C sort | tr '\n' ' ')"
if [[ "$fonts_ls" == ".fedora-setup-nerd-FiraCode-v3.3.0 .fedora-setup-nerd-JetBrainsMono-v3.3.0 FiraCode Nerd Font JetBrainsMono Nerd Font " ]]; then
    fx_ok
else
    fx_bad "fonts dir has unexpected residue (got: $fonts_ls)"
fi
if [[ -f "$FX_TMP/h_real/.local/state/fedora-setup/modules/fonts" ]]; then fx_ok; else fx_bad "fonts not marked done"; fi

# hook-level re-run skip: FRESH home, SAME fonts dir with markers -> no
# re-copy/extract, marker mtime stable
mtime1="$(stat -c %Y "$FONTS/.fedora-setup-nerd-FiraCode-v3.3.0")"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_real2"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export FS_MOCK_LOG="$LOG" FS_MOCK_INSTALLED="$INST"
    export FS_FONTS_DIR="$FONTS" FS_NERDFONT_SRC_DIR="$FX_TMP/ff"
    export XDG_CACHE_HOME="$FX_TMP/xc"
    unset FS_YES FS_PROFILE FS_DRY_RUN FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes fonts
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "fonts re-run rc" 0
fx_out 'nerd font already installed: FiraCode Nerd Font (v3.3.0)'
fx_out 'nerd font already installed: JetBrainsMono Nerd Font (v3.3.0)'
mtime2="$(stat -c %Y "$FONTS/.fedora-setup-nerd-FiraCode-v3.3.0")"
if [[ "$mtime1" == "$mtime2" ]]; then fx_ok; else fx_bad "re-run re-wrote marker"; fi

# local zip WITHOUT a checksum: warn + install (operator-provided asset); a
# fresh disjoint suffix so the missing-checkum path is actually exercised.
mkdir -p "$FX_TMP/ffn"
cp -p "$FX_TMP/ff/FiraCode.zip" "$FX_TMP/ffn/FiraCode.zip"
cp -p "$FX_TMP/ff/JetBrainsMono.zip" "$FX_TMP/ffn/JetBrainsMono.zip"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_ncs"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export FS_MOCK_LOG="$LOG" FS_MOCK_INSTALLED="$INST"
    export FS_FONTS_DIR="$FX_TMP/fonts_ncs" FS_NERDFONT_SRC_DIR="$FX_TMP/ffn"
    export XDG_CACHE_HOME="$FX_TMP/xc"
    unset FS_YES FS_PROFILE FS_DRY_RUN FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes fonts
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "fonts no-checksum rc" 0
fx_err 'has no .sha256; installing unverified (operator-provided)'
fx_out 'installed nerd font: FiraCode Nerd Font (v3.3.0)'
fx_out 'installed nerd font: JetBrainsMono Nerd Font (v3.3.0)'
if [[ -f "$FX_TMP/fonts_ncs/.fedora-setup-nerd-FiraCode-v3.3.0" ]]; then fx_ok; else fx_bad "no-checksum install marker missing"; fi

# failing unzip -> run_cmd --stop aborts: module failed, rc1, NO marker,
# NO 'installed nerd font' line, no leftover temps.
mkdir -p "$FX_TMP/fakebin"
printf '#!/bin/sh\nexit 42\n' >"$FX_TMP/fakebin/unzip"
chmod +x "$FX_TMP/fakebin/unzip"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_unz"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export FS_MOCK_LOG="$LOG" FS_MOCK_INSTALLED="$INST"
    export FS_FONTS_DIR="$FX_TMP/fonts_unz" FS_NERDFONT_SRC_DIR="$FX_TMP/ff"
    export PATH="$FX_TMP/fakebin:$PATH"
    unset FS_YES FS_PROFILE FS_DRY_RUN FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes fonts
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "fonts failing unzip rc" 1
fx_err 'module failed: fonts'
if grep -q 'installed nerd font' "$FX_OUT"; then fx_bad "unzip-fail wrote installed line"; else fx_ok; fi
if [[ -e "$FX_TMP/fonts_unz/.fedora-setup-nerd-FiraCode-v3.3.0" ]]; then fx_bad "unzip-fail wrote marker"; else fx_ok; fi
if [[ ! -d "$FX_TMP/fonts_unz" ]]; then fx_bad "unzip-fail dir missing for residue check"; elif ls -A "$FX_TMP/fonts_unz" | grep -q '^\.'; then fx_bad "unzip-fail left temp residue"; else fx_ok; fi

# HOME=/ with no FS_FONTS_DIR -> fail-closed before any write
(   set -euo pipefail
    export HOME=/
    export FS_HOME="$FX_TMP/h_home"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export FS_MOCK_LOG="$LOG" FS_MOCK_INSTALLED="$INST"
    export XDG_CACHE_HOME="$FX_TMP/xc"
    unset FS_FONTS_DIR FS_YES FS_PROFILE FS_DRY_RUN FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes fonts
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "fonts HOME=/ rc" 1
fx_err 'requires FS_FONTS_DIR or a real HOME'

# FS_FONTS_DIR=/ -> fail-closed before any write
(   set -euo pipefail
    export FS_FONTS_DIR=/
    export FS_HOME="$FX_TMP/h_fd"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export FS_MOCK_LOG="$LOG" FS_MOCK_INSTALLED="$INST"
    export XDG_CACHE_HOME="$FX_TMP/xc"
    unset FS_YES FS_PROFILE FS_DRY_RUN FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes fonts
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "fonts FS_FONTS_DIR=/ rc" 1
fx_err 'refusing nerd fonts target'

# EMPTY config (FS_NERDFONT_CONFIG seam) -> clean no-op: rc0, no download
# plan lines, dry mode, package batch still renders.
: >"$FX_TMP/empty.lst"
(   set -euo pipefail
    export FS_NERDFONT_CONFIG="$FX_TMP/empty.lst"
    export FS_HOME="$FX_TMP/h_empty"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm FS_DRY_RUN=1
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export FS_MOCK_LOG="$LOG" FS_MOCK_INSTALLED="$INST"
    export FS_FONTS_DIR="$FX_TMP/fonts_empty"
    unset FS_YES FS_PROFILE FS_NERDFONT_SRC_DIR FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes fonts
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "fonts empty config rc" 0
fx_out '^# would run: mock install google-noto-sans-fonts fira-code-fonts jetbrains-mono-fonts$'
if grep -q 'would run: download' "$FX_OUT"; then fx_bad "empty config rendered downloads"; else fx_ok; fi
if grep -q 'would run: fc-cache' "$FX_OUT"; then fx_bad "empty config rendered fc-cache"; else fx_ok; fi

# malformed entries (colon-less + space-in-asset) skipped in BOTH modes, with
# the same warn; the valid line still installs (real) / plans (dry).
printf 'FiraCode Nerd Font:FiraCode:v3.3.0\nNoColons\nLbl:Bad Asset:v1\n' >"$FX_TMP/mixed.lst"
(   set -euo pipefail
    export FS_NERDFONT_CONFIG="$FX_TMP/mixed.lst"
    export FS_HOME="$FX_TMP/h_mix_dry"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm FS_DRY_RUN=1
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export FS_MOCK_LOG="$LOG" FS_MOCK_INSTALLED="$INST"
    export FS_FONTS_DIR="$FX_TMP/fonts_mix_dry"
    unset FS_YES FS_PROFILE FS_NERDFONT_SRC_DIR FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes fonts
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "fonts malformed dry rc" 0
fx_out '^# would run: download https://github.com/ryanoasis/nerd-fonts/releases/download/v3\.3\.0/FiraCode.zip$'
fx_err 'skipping malformed nerd font entry: NoColons'
fx_err 'skipping malformed nerd font entry: Lbl:Bad Asset:v1'
if grep -q 'would run: download.*Bad Asset\|would run: download.*NoColons' "$FX_OUT"; then fx_bad "malformed dry rendered plan"; else fx_ok; fi
if (( $(grep -c '^# would run: download ' "$FX_OUT") == 1 )); then fx_ok; else fx_bad "malformed dry download count"; fi
(   set -euo pipefail
    export FS_NERDFONT_CONFIG="$FX_TMP/mixed.lst"
    export FS_HOME="$FX_TMP/h_mix"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export FS_MOCK_LOG="$LOG" FS_MOCK_INSTALLED="$INST"
    export FS_FONTS_DIR="$FX_TMP/fonts_mix" FS_NERDFONT_SRC_DIR="$FX_TMP/ff"
    export XDG_CACHE_HOME="$FX_TMP/xc"
    unset FS_YES FS_PROFILE FS_DRY_RUN FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes fonts
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "fonts malformed real rc" 0
fx_out '^== run complete ==$'
fx_out 'installed nerd font: FiraCode Nerd Font (v3.3.0)'
fx_err 'skipping malformed nerd font entry: NoColons'
fx_err 'skipping malformed nerd font entry: Lbl:Bad Asset:v1'
if [[ -f "$FX_TMP/fonts_mix/.fedora-setup-nerd-FiraCode-v3.3.0" ]]; then fx_ok; else fx_bad "malformed real: valid marker missing"; fi
if [[ -e "$FX_TMP/fonts_mix/.fedora-setup-nerd-NoColons-NoColons" ]]; then fx_bad "malformed real: colonless marker"; else fx_ok; fi

# sha256 mismatch is fail-closed: module failed, run rc1, NO marker/files, no residue
printf '%064d\n' 0 >"$FX_TMP/ff/FiraCode.zip.sha256"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_bad"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export FS_MOCK_LOG="$LOG" FS_MOCK_INSTALLED="$INST"
    export FS_FONTS_DIR="$FX_TMP/fonts_bad" FS_NERDFONT_SRC_DIR="$FX_TMP/ff"
    export XDG_CACHE_HOME="$FX_TMP/xc"
    unset FS_YES FS_PROFILE FS_DRY_RUN FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes fonts
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "fonts checksum mismatch rc" 1
fx_err 'sha256 mismatch for FiraCode.zip'
fx_err 'module failed: fonts'
if [[ -e "$FX_TMP/fonts_bad/.fedora-setup-nerd-FiraCode-v3.3.0" ]]; then fx_bad "mismatch wrote marker"; else fx_ok; fi
if [[ -e "$FX_TMP/fonts_bad/FiraCode Nerd Font" ]]; then fx_bad "mismatch extracted before verify"; else fx_ok; fi
if [[ ! -d "$FX_TMP/fonts_bad" ]]; then fx_bad "mismatch dir missing for residue check"; elif ls -A "$FX_TMP/fonts_bad" | grep -q '^\.'; then fx_bad "mismatch left temp residue"; else fx_ok; fi
printf '%s\n' "$(sha256sum "$FX_TMP/ff/FiraCode.zip" | awk '{print $1}')" >"$FX_TMP/ff/FiraCode.zip.sha256"

# setup list shows all four real modules
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_list" FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    unset FS_PKG_BACKEND FS_DISTRO_FILE FS_YES FS_PROFILE FS_FONTS_DIR FS_NERDFONT_SRC_DIR 2>/dev/null || :
    "$SETUP" list
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "setup list rc" 0
for m in core flatpak git fonts; do
    if grep -q "^$m\b" "$FX_OUT"; then fx_ok; else fx_bad "$m row missing from list"; fi
done

fx_summary