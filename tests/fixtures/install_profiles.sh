#!/usr/bin/env bash
# tests/fixtures/install_profiles.sh - P5.7 fixture for profile wiring.
# Drives the REAL repo modules/ + profiles/ + config/ through
# `./setup install --profile <name> --yes` against the mock backend.
# Covers: `minimal` (core+flatpak) and `desktop` (minimal+git+fonts+terminal)
# dry-run EXACT single batch + plan purity; real mock run end-to-end where
# the fonts (staged local source), git, and terminal (staged omp+atuin
# sources) hooks all execute through the runner and every module is marked;
# resume-run idempotence (already completed / skipped); second hook invocation
# (fonts/terminal/git re-execute against the same staged sources and managed
# files stay byte-stable). Real-host flatpak routing is a recorded limitation
# (see profiles/minimal.conf); this fixture is the load-bearing dry+mock
# evidence. The repo-pinned fonts checksum map (config/nerdfonts.sha256) is
# exercised in mod_fonts.sh; here fonts installs from the staged operator
# source with sibling sidecars.
# Nothing outside FX_TMP + the real repo modules/profiles/config is touched.
# Usage: bash tests/fixtures/install_profiles.sh  (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init
mkdir -p "$FX_TMP"

printf 'P5.7 profile wiring\n'

SETUP="$ROOT/setup"
LOG="$FX_TMP/I/p5.log"
INST="$FX_TMP/I/p5.inst"
mkdir -p "$(dirname "$LOG")"
: >"$LOG"
: >"$INST"

MIN_BATCH="gnupg2 fastfetch git curl wget vim fzf bat btop htop tmux unzip e2fsprogs flatpak"
FLATPAKS="com.mattjakeman.ExtensionManager com.bitwarden.desktop net.nokyan.Resources"
FONT_PKGS="google-noto-sans-fonts fira-code-fonts jetbrains-mono-fonts"
FULL_BATCH="$MIN_BATCH $FLATPAKS $FONT_PKGS"

prof_run() {
    local state_dir="$1" profile="$2" dry="${3:-0}"
    : >"$LOG"
    (
        set -euo pipefail
        export FS_HOME="$FX_TMP/$state_dir"
        export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
        export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
        export FS_MOCK_LOG="$LOG" FS_MOCK_INSTALLED="$INST"
        export HOME="$FX_TMP/nohome"
        if [[ "$dry" == 1 ]]; then export FS_DRY_RUN=1; fi
        unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
        "$SETUP" install --profile "$profile" --yes
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "$profile rc" 0
}

# === cell 1: minimal dry-run — exact single batch + purity ===
prof_run t_min_dry minimal 1
fx_out 'profile: minimal'
fx_out 'module: core (none)'
fx_out 'module: flatpak (none)'
fx_out '^== run complete ==$'
fx_out '2 ok'
fx_out "^# would run: mock install $MIN_BATCH $FLATPAKS\$"
if [[ -e "$FX_TMP/t_min_dry/.local/state/fedora-setup" ]]; then fx_bad "minimal dry created state dir"; else fx_ok; fi
if [[ -e "$FX_TMP/nohome" ]]; then fx_bad "minimal dry leaked into HOME"; else fx_ok; fi
fx_empty "minimal dry mock untouched" "$LOG"

# === cell 2: minimal real mock + resume idempotence ===
: >"$INST"
printf 'git\nhtop\ne2fsprogs\ncom.mattjakeman.ExtensionManager\n' >"$INST"
prof_run t_min_real minimal 0
fx_out 'profile: minimal'
fx_out '^== run complete ==$'
fx_out '2 ok'
if grep -qxF 'mock install gnupg2 fastfetch curl wget vim fzf bat btop tmux unzip flatpak com.bitwarden.desktop net.nokyan.Resources' "$LOG"; then fx_ok; else fx_bad "minimal real batch in log"; fi
for f in "$FX_TMP/t_min_real/.local/state/fedora-setup/modules/core" "$FX_TMP/t_min_real/.local/state/fedora-setup/modules/flatpak"; do
    if [[ -f "$f" ]]; then fx_ok; else fx_bad "minimal module not marked: $f"; fi
done
prof_run t_min_real minimal 0
fx_out 'already completed: core'
fx_out 'already completed: flatpak'
fx_out '2 skipped'
if [[ -f "$FX_TMP/t_min_real/.local/state/fedora-setup/modules/core" ]]; then fx_ok; else fx_bad "resume lost completion mark"; fi

# === cell 3: desktop dry-run — full batch incl fonts packages ===
prof_run t_desktop_dry desktop 1
fx_out 'profile: desktop'
fx_out 'module: core (none)'
fx_out 'module: flatpak (none)'
fx_out 'module: fonts (low)'
fx_out 'module: git (low)'
fx_out 'module: terminal (low)'
fx_out '^== run complete ==$'
fx_out '5 ok'
fx_out "^# would run: mock install $FULL_BATCH\$"
if grep -q '^# would run: mock install ' "$FX_OUT"; then
    n="$(grep -c '^# would run: mock install ' "$FX_OUT")"
    if (( n == 1 )); then fx_ok; else fx_bad "desktop dry single batch (got $n)"; fi
fi
if [[ -e "$FX_TMP/t_desktop_dry/.local/state/fedora-setup" ]]; then fx_bad "desktop dry created state dir"; else fx_ok; fi
if [[ -e "$FX_TMP/nohome" ]]; then fx_bad "desktop dry leaked into HOME"; else fx_ok; fi
fx_empty "desktop dry mock untouched" "$LOG"

# === cell 4: desktop real mock — e2e hooks fire for fonts/git/terminal ===
DESK="$FX_TMP/desk"
mkdir -p "$DESK" "$DESK/font-src" "$DESK/omp-src" "$DESK/atuin-src" "$DESK/xc"
FONTS_DIR="$DESK/fonts"
OMP_BIN="$DESK/omp"
OMP_THEME="$DESK/theme.json"
ATUIN_BIN="$DESK/atuin"
ALIASES="$DESK/aliases"
BASHRC="$DESK/bashrc"
GITCONF="$DESK/gitconfig"

FAKE_OMP='#!/bin/sh
echo "23.9.0"
'
printf '%s' "$FAKE_OMP" >"$DESK/omp-src/posh-linux-amd64"
printf '%s  posh-linux-amd64\n' "$(sha256sum "$DESK/omp-src/posh-linux-amd64" | awk '{print $1}')" >"$DESK/omp-src/posh-linux-amd64.sha256"
printf '%s\n' '{"schema":"test-theme"}' >"$DESK/omp-src/jandedobbeleer.omp.json"

FIRA_B64='UEsDBAoAAAAAAGNOO10AAAAAAAAAAAAAAAATABwARmlyYUNvZGUgTmVyZCBGb250L1VUCQAD2ry4atq8uGp1eAsAAQToAwAABOgDAABQSwMECgAAAAAAY047XaSfmukXAAAAFwAAACEAHABGaXJhQ29kZSBOZXJkIEZvbnQvRmlyYUNvZGVORi5vdGZVVAkAA9q8uGravLhqdXgLAAEE6AMAAAToAwAAZmFrZSBmb250IGdseXBocwpsaW5lMgpQSwECHgMKAAAAAABjTjtdAAAAAAAAAAAAAAAAEwAYAAAAAAAAABAA7UEAAAAARmlyYUNvZGUgTmVyZCBGb250L1VUBQAD2ry4anV4CwABBOgDAAAE6AMAAFBLAQIeAwoAAAAAAGNOO12kn5rpFwAAABcAAAAhABgAAAAAAAEAAACkgU0AAABGaXJhQ29kZSBOZXJkIEZvbnQvRmlyYUNvZGVORi5vdGZVVAUAA9q8uGp1eAsAAQToAwAABOgDAABQSwUGAAAAAAIAAgDAAAAAvwAAAAAA'
JB_B64='UEsDBAoAAAAAAGVOO10AAAAAAAAAAAAAAAAYABwASmV0QnJhaW5zTW9ubyBOZXJkIEZvbnQvVVQJAAPevLhq3ry4anV4CwABBOgDAAAE6AMAAFBLAwQKAAAAAABlTjtdxnfnIxYAAAAWAAAAKwAcAEpldEJyYWluc01vbm8gTmVyZCBGb250L0pldEJyYWluc01vbm9ORi50dGZVVAkAA968uGrevLhqdXgLAAEE6AMAAAToAwAAZmFrZSBqZXRicmFpbnMgZ2x5cGhzClBLAQIeAwoAAAAAAGVOO10AAAAAAAAAAAAAAAAYABgAAAAAAAAAEADtQQAAAABKZXRCcmFpbnNNb25vIE5lcmQgRm9udC9VVAUAA968uGp1eAsAAQToAwAABOgDAABQSwECHgMKAAAAAABlTjtdxnfnIxYAAAAWAAAAKwAYAAAAAAABAAAApIFSAAAASmV0QnJhaW5zTW9ubyBOZXJkIEZvbnQvSmV0QnJhaW5zTW9ub05GLnR0ZlVUBQAD3ry4anV4CwABBOgDAAAE6AMAAFBLBQYAAAAAAgACAM8AAADNAAAAAAA='
printf '%s' "$FIRA_B64" | base64 -d >"$DESK/font-src/FiraCode.zip"
printf '%s  FiraCode.zip\n' "$(sha256sum "$DESK/font-src/FiraCode.zip" | awk '{print $1}')" >"$DESK/font-src/FiraCode.zip.sha256"
printf '%s' "$JB_B64" | base64 -d >"$DESK/font-src/JetBrainsMono.zip"
printf '%s  JetBrainsMono.zip\n' "$(sha256sum "$DESK/font-src/JetBrainsMono.zip" | awk '{print $1}')" >"$DESK/font-src/JetBrainsMono.zip.sha256"

FAKE_ATUIN='#!/bin/sh
echo "atuin 18.23.0 (78366dca8c4941731e06a2f81c0980cc2ccc3836)"
'
mkdir -p "$DESK/arc/tmp/atuin-x86_64-unknown-linux-gnu"
printf '%s' "$FAKE_ATUIN" >"$DESK/arc/tmp/atuin-x86_64-unknown-linux-gnu/atuin"
chmod 0755 "$DESK/arc/tmp/atuin-x86_64-unknown-linux-gnu/atuin"
tar -czf "$DESK/atuin-src/atuin-x86_64-unknown-linux-gnu.tar.gz" -C "$DESK/arc/tmp" "atuin-x86_64-unknown-linux-gnu"
printf '%s *atuin-x86_64-unknown-linux-gnu.tar.gz\n' \
    "$(sha256sum "$DESK/atuin-src/atuin-x86_64-unknown-linux-gnu.tar.gz" | awk '{print $1}')" \
    >"$DESK/atuin-src/atuin-x86_64-unknown-linux-gnu.tar.gz.sha256"

desktop_run() {
    : >"$LOG"
    (
        set -euo pipefail
        export FS_HOME="$FX_TMP/t_desktop_real"
        export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
        export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
        export FS_MOCK_LOG="$LOG" FS_MOCK_INSTALLED="$INST"
        export FS_GIT_CONFIG="$GITCONF"
        export FS_FONTS_DIR="$FONTS_DIR" FS_NERDFONT_SRC_DIR="$DESK/font-src"
        export XDG_CACHE_HOME="$DESK/xc"
        export FS_TERM_ALIASES="$ALIASES" FS_BASHRC="$BASHRC"
        export FS_OMP_BIN="$OMP_BIN" FS_OMP_THEME="$OMP_THEME" FS_OMP_SRC_DIR="$DESK/omp-src"
        export FS_ATUIN_BIN="$ATUIN_BIN" FS_ATUIN_SRC_DIR="$DESK/atuin-src"
        export HOME="$FX_TMP/nohome"
        unset FS_YES FS_PROFILE FS_DRY_RUN FS_DISTRO_FILE 2>/dev/null || :
        "$SETUP" install --profile desktop --yes
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
}

: >"$INST"
printf 'curl\nhatop\n' >"$INST"
desktop_run
fx_block_rc "desktop real rc" 0
fx_out 'profile: desktop'
fx_out '^== run complete ==$'
fx_out '5 ok'
if grep -qxF 'mock install gnupg2 fastfetch git wget vim fzf bat btop htop tmux unzip e2fsprogs flatpak com.mattjakeman.ExtensionManager com.bitwarden.desktop net.nokyan.Resources google-noto-sans-fonts fira-code-fonts jetbrains-mono-fonts' "$LOG"; then fx_ok; else fx_bad "desktop real batch in log"; fi
fx_out 'installed nerd font: FiraCode Nerd Font (v3.3.0)'
fx_out 'installed nerd font: JetBrainsMono Nerd Font (v3.3.0)'
for f in "$FONTS_DIR/.fedora-setup-nerd-FiraCode-v3.3.0" "$FONTS_DIR/.fedora-setup-nerd-JetBrainsMono-v3.3.0"; do
    if [[ -e "$f" ]]; then fx_ok; else fx_bad "desktop fonts marker missing: $f"; fi
done
if grep -qxF '# BEGIN fedora-setup git' "$GITCONF" && grep -qxF '# END fedora-setup git' "$GITCONF"; then fx_ok; else fx_bad "desktop gitconfig block missing"; fi
if grep -q 'defaultBranch = main' "$GITCONF"; then fx_ok; else fx_bad "desktop gitconfig settings missing"; fi
if [[ -x "$OMP_BIN" ]] && [[ "$("$OMP_BIN" --version)" == "23.9.0" ]]; then fx_ok; else fx_bad "desktop omp binary missing/wrong"; fi
if [[ -x "$ATUIN_BIN" ]] && [[ "$("$ATUIN_BIN" --version)" == "atuin 18.23.0 "* ]]; then fx_ok; else fx_bad "desktop atuin binary missing/wrong"; fi
O_GUARD="[ -r '$ALIASES' ] && . '$ALIASES'"
O_OMPG="[ -x '$OMP_BIN' ] && eval \"\$('$OMP_BIN' init bash --config '$OMP_THEME')\""
O_ATUING="[ -x '$ATUIN_BIN' ] && eval \"\$('$ATUIN_BIN' init bash)\""
if grep -qxF "$O_GUARD" "$BASHRC" && grep -qxF "$O_OMPG" "$BASHRC" && grep -qxF "$O_ATUING" "$BASHRC"; then fx_ok; else fx_bad "desktop terminal block guards missing"; fi
for m in core flatpak fonts git terminal; do
    if [[ -f "$FX_TMP/t_desktop_real/.local/state/fedora-setup/modules/$m" ]]; then fx_ok; else fx_bad "desktop module not marked: $m"; fi
done

# resume: all five already completed -> 5 skipped, byte-stable
cp "$BASHRC" "$FX_TMP/desk.bashrc.snap"
cp "$GITCONF" "$FX_TMP/desk.gitconfig.snap"
desktop_run
fx_block_rc "desktop resume rc" 0
fx_out '5 skipped'
fx_out '^== run complete ==$'
if cmp -s "$BASHRC" "$FX_TMP/desk.bashrc.snap" && cmp -s "$GITCONF" "$FX_TMP/desk.gitconfig.snap"; then fx_ok; else fx_bad "desktop resume rewrote managed files"; fi

# second HOOK invocation: remove the per-asset install markers + binaries and
# unmark fonts+terminal, then re-run. The hooks re-execute against the same
# staged sources (fonts sibling-sidecar re-read, terminal re-install), the
# managed blocks re-merge byte-stably, and the three completed modules stay
# skipped. Pins the fonts digests re-read + managed-block no-op on run 2.
cp "$BASHRC" "$FX_TMP/desk.bashrc.snap2"
cp "$GITCONF" "$FX_TMP/desk.gitconfig.snap2"
rm -rf "$FONTS_DIR/.fedora-setup-nerd-FiraCode-v3.3.0" \
    "$FONTS_DIR/.fedora-setup-nerd-JetBrainsMono-v3.3.0" \
    "$OMP_BIN" "$OMP_THEME" "$ATUIN_BIN"
rm -f "$FX_TMP/t_desktop_real/.local/state/fedora-setup/modules/fonts" \
    "$FX_TMP/t_desktop_real/.local/state/fedora-setup/modules/terminal" \
    "$FX_TMP/t_desktop_real/.local/state/fedora-setup/modules/git"
desktop_run
fx_block_rc "desktop hook re-run rc" 0
fx_out '^== run complete ==$'
fx_out '3 ok'
fx_out '2 skipped'
fx_out 'already completed: core'
fx_out 'already completed: flatpak'
fx_out 'sha256 verified: FiraCode'
fx_out 'sha256 verified: JetBrainsMono'
fx_out 'installed nerd font: FiraCode Nerd Font (v3.3.0)'
fx_out 'installed nerd font: JetBrainsMono Nerd Font (v3.3.0)'
if ! grep -q '^mock install ' "$LOG"; then fx_ok; else fx_bad "hook re-run re-batched installed packages"; fi
if cmp -s "$BASHRC" "$FX_TMP/desk.bashrc.snap2" && cmp -s "$GITCONF" "$FX_TMP/desk.gitconfig.snap2"; then fx_ok; else fx_bad "hook re-run rewrote managed files"; fi
for m in fonts terminal; do
    if [[ -f "$FX_TMP/t_desktop_real/.local/state/fedora-setup/modules/$m" ]]; then fx_ok; else fx_bad "hook re-run module not re-marked: $m"; fi
done

fx_summary