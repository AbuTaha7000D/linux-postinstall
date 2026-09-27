#!/usr/bin/env bash
# tests/fixtures/mod_terminal.sh - P5.5/P5.6 fixture for the `terminal` module.
# Drives the REAL repo modules/ + profiles/ through `./setup install`.
# Covers: hooks-only module (no package batch) through the runner; dry-run
# rendering the aliases/omp/theme/atuin/bashrc plan lines with ZERO writes;
# sha256-verified oh-my-posh binary install (real-shaped uppercase+CRLF
# no-filename sidecar) AND sha256-verified atuin archive install (real-shaped
# `<hash> *<name>` sidecar, tar extract); theme install, aliases managed block,
# and .bashrc managed block that preserves every unmanaged line byte-for-byte
# (and never touches a legacy ~/.bashrc.bak); idempotent no-op re-run
# (already-installed versions, empty local sources => skip-before-source
# proof); wrong-version reinstall; sha256-mismatch fail-closed (rc1, no
# binary, no theme, no block, no temp residue); HOME=/ and HOME-unset
# fail-closed; unsupported omp arch fails closed vs unsupported atuin arch
# warn+succeed (dry skip line + inert-by-guard block); aarch64 dry URL and
# real aarch64 extraction; atuin wrong-version reinstall backs up + records
# the registry while a fresh atuin keeps it empty; default path resolution
# from a scratch HOME; `setup list` row. Nothing outside FX_TMP + the real
# repo modules/profiles is touched.
# The task's "bash -l produces a prompt line" check is real-host [REAL]
# verification: this fixture proves the guarded init lines are present and
# byte-exact.
# Usage: bash tests/fixtures/mod_terminal.sh  (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init
mkdir -p "$FX_TMP"

printf 'P5.5/P5.6 terminal module\n'

SETUP="$ROOT/setup"
LOG="$FX_TMP/I/term.log"
INST="$FX_TMP/I/term.inst"
mkdir -p "$(dirname "$LOG")"
TERM_ARCH="amd64"
ATUIN_TRIPLE="x86_64"

FAKE_BIN='#!/bin/sh
echo "23.9.0"
'
WRONG_BIN='#!/bin/sh
echo "23.8.0"
'
FAKE_ATUIN='#!/bin/sh
echo "atuin 18.23.0 (78366dca8c4941731e06a2f81c0980cc2ccc3836)"
'
WRONG_ATUIN='#!/bin/sh
echo "atuin 18.22.0 (0000000000000000000000000000000000000000000000000000000000000000)"
'
THEME_BODY='{"schema":"test-theme"}'

ATUIN_TAR_PREFIX="atuin-$ATUIN_TRIPLE-unknown-linux-gnu"

mk_src() {
    local dst="$1" style="$2"
    mkdir -p "$dst"
    printf '%s' "$FAKE_BIN" >"$dst/posh-linux-amd64"
    local h
    h="$(sha256sum "$dst/posh-linux-amd64" | cut -d' ' -f1)"
    case "$style" in
        upper)
            printf '%s\r\n' "${h^^}" >"$dst/posh-linux-amd64.sha256"
            ;;
        lower)
            printf '%s  posh-linux-amd64\n' "$h" >"$dst/posh-linux-amd64.sha256"
            ;;
        wrong)
            printf '%s  posh-linux-amd64\n' \
                '0000000000000000000000000000000000000000000000000000000000000000' \
                >"$dst/posh-linux-amd64.sha256"
            ;;
    esac
    printf '%s\n' "$THEME_BODY" >"$dst/jandedobbeleer.omp.json"
}

mk_atuin_src() {
    local dst="$1" style="$2" triple="${3:-x86_64}"
    local name="atuin-$triple-unknown-linux-gnu"
    local tarfile="$dst/$name.tar.gz"
    local ardir="$FX_TMP/$RANDOM/atuin-arc"
    mkdir -p "$dst" "$ardir/$name"
    printf '%s' "$FAKE_ATUIN" >"$ardir/$name/atuin"
    chmod 0755 "$ardir/$name/atuin"
    tar -czf "$tarfile" -C "$ardir" "$name"
    local h
    h="$(sha256sum "$tarfile" | cut -d' ' -f1)"
    case "$style" in
        real)
            printf '%s *%s\n' "$h" "$name.tar.gz" >"$tarfile.sha256"
            ;;
        wrong)
            printf '%s *%s\n' \
                '0000000000000000000000000000000000000000000000000000000000000000' \
                "$name.tar.gz" >"$tarfile.sha256"
            ;;
    esac
    rm -rf -- "$ardir" 2>/dev/null || :
}

term_run() {
    local state_dir="$1" label="$2" dry="${3:-0}" home_extra="${4:-}" exp_rc="${5:-0}"
    : >"$LOG"
    : >"$INST"
    (
        set -euo pipefail
        export FS_HOME="$FX_TMP/$state_dir"
        export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
        export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
        export FS_MOCK_LOG="$LOG" FS_MOCK_INSTALLED="$INST"
        export FS_OMP_ARCH="$TERM_ARCH"
        export FS_ATUIN_ARCH="${FS_ATUIN_ARCH:-$ATUIN_TRIPLE}"
        export HOME="$FX_TMP/nohome"
        [[ -z "$home_extra" ]] || export HOME="$home_extra"
        if [[ "$dry" == 1 ]]; then export FS_DRY_RUN=1; fi
        unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
        "$SETUP" install --yes terminal
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "$label rc" "$exp_rc"
}

# === cell A: dry-run renders plan lines, writes nothing ===
A="$FX_TMP/A"
A_ALIASES="$A/aliases"
A_BASHRC="$A/bashrc"
A_BIN="$A/bin/oh-my-posh"
A_THEME="$A/themes/jandedobbeleer.omp.json"
A_ATUIN_BIN="$A/bin/atuin"
mkdir -p "$A"
export FS_TERM_ALIASES="$A_ALIASES" FS_BASHRC="$A_BASHRC"
export FS_OMP_BIN="$A_BIN" FS_OMP_THEME="$A_THEME"
export FS_ATUIN_BIN="$A_ATUIN_BIN"
term_run t_dry "terminal dry-run" 1
fx_out 'profile: selection'
fx_out 'module: terminal (low)'
fx_out '^== run complete ==$'
fx_out '1 ok'
fx_out "^# would run: merge fedora-setup aliases block into $A_ALIASES\$"
fx_out "^# would run: install oh-my-posh v23.9.0 (amd64) release binary (https://github.com/JanDeDobbeleer/oh-my-posh/releases/download/v23.9.0/posh-linux-amd64) into $A_BIN\$"
fx_out "^# would run: install oh-my-posh theme (https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/v23.9.0/themes/jandedobbeleer.omp.json) into $A_THEME\$"
fx_out "^# would run: install atuin v18.23.0 ($ATUIN_TRIPLE) release binary (https://github.com/atuinsh/atuin/releases/download/v18.23.0/$ATUIN_TAR_PREFIX.tar.gz) into $A_ATUIN_BIN\$"
fx_out "^# would run: merge fedora-setup terminal block into $A_BASHRC\$"
if [[ -e "$A_BIN" ]]; then fx_bad "dry-run wrote omp binary"; else fx_ok; fi
if [[ -e "$A_THEME" ]]; then fx_bad "dry-run wrote theme"; else fx_ok; fi
if [[ -e "$A_ATUIN_BIN" ]]; then fx_bad "dry-run wrote atuin binary"; else fx_ok; fi
if [[ -e "$A_BASHRC" ]]; then fx_bad "dry-run wrote bashrc"; else fx_ok; fi
if [[ -e "$A_ALIASES" ]]; then fx_bad "dry-run wrote aliases"; else fx_ok; fi
if [[ -e "$FX_TMP/t_dry/.local/state/fedora-setup" ]]; then fx_bad "dry-run created state dir"; else fx_ok; fi
fx_empty "dry-run mock untouched" "$LOG"
unset FS_TERM_ALIASES FS_BASHRC FS_OMP_BIN FS_OMP_THEME FS_ATUIN_BIN

# === cell B: real happy path (uppercase OMP-style checksum, local source) ===
B="$FX_TMP/B"
B_SRC="$B/src"
B_ALIASES="$B/aliases"
B_BASHRC="$B/bashrc"
B_BAK="$B_BASHRC.bak"
B_BIN="$B/bin/oh-my-posh"
B_THEME="$B/themes/jandedobbeleer.omp.json"
B_ATUIN_BIN="$B/bin/atuin"
B_ATUIN_SRC="$B/atuin-src"
mkdir -p "$B"
mk_src "$B_SRC" upper
mk_atuin_src "$B_ATUIN_SRC" real
printf 'export EDITOR=vim\n' >"$B_BASHRC"
printf '# legacy backup from the old prototype\nexport CUSTOM=keep\n' >"$B_BAK"
cp "$B_BAK" "$FX_TMP/B.bak.snap"
export FS_TERM_ALIASES="$B_ALIASES" FS_BASHRC="$B_BASHRC"
export FS_OMP_BIN="$B_BIN" FS_OMP_THEME="$B_THEME" FS_OMP_SRC_DIR="$B_SRC"
export FS_ATUIN_BIN="$B_ATUIN_BIN" FS_ATUIN_SRC_DIR="$B_ATUIN_SRC"
term_run t_real "terminal real happy" 0
fx_out '1 ok'
if [[ -f "$FX_TMP/t_real/.local/state/fedora-setup/modules/terminal" ]]; then fx_ok; else fx_bad "terminal not marked done"; fi
if [[ -x "$B_BIN" ]]; then fx_ok; else fx_bad "omp binary not executable"; fi
if cmp -s "$B_BIN" "$B_SRC/posh-linux-amd64"; then fx_ok; else fx_bad "omp binary content mismatch"; fi
if [[ "$("$B_BIN" --version)" == *23.9.0* ]]; then fx_ok; else fx_bad "omp binary version"; fi
if cmp -s "$B_THEME" "$B_SRC/jandedobbeleer.omp.json"; then fx_ok; else fx_bad "theme content mismatch"; fi
if grep -qxF '# BEGIN fedora-setup aliases' "$B_ALIASES" && grep -qxF '# END fedora-setup aliases' "$B_ALIASES"; then fx_ok; else fx_bad "aliases markers missing"; fi
for al in "alias ll='ls -la'" "alias la='ls -A'" "alias grep='grep --color=auto'" "alias egrep='egrep --color=auto'" "alias less='less -R'"; do
    if grep -qxF "$al" "$B_ALIASES"; then fx_ok; else fx_bad "aliases missing: $al"; fi
done
if (( $(grep -c '^# BEGIN fedora-setup aliases' "$B_ALIASES") == 1 )); then fx_ok; else fx_bad "aliases block duplicated"; fi
if grep -qxF '# BEGIN fedora-setup terminal' "$B_BASHRC" && grep -qxF '# END fedora-setup terminal' "$B_BASHRC"; then fx_ok; else fx_bad "bashrc markers missing"; fi
if grep -qxF 'export EDITOR=vim' "$B_BASHRC"; then fx_ok; else fx_bad "pre-existing bashrc line lost"; fi
B_GUARD="[ -r '$B_ALIASES' ] && . '$B_ALIASES'"
B_OMPG="[ -x '$B_BIN' ] && eval \"\$('$B_BIN' init bash --config '$B_THEME')\""
B_ATUING="[ -x '$B_ATUIN_BIN' ] && eval \"\$('$B_ATUIN_BIN' init bash)\""
if grep -qxF "$B_GUARD" "$B_BASHRC"; then fx_ok; else fx_bad "aliases sourcing guard missing"; fi
if grep -qxF "$B_OMPG" "$B_BASHRC"; then fx_ok; else fx_bad "omp guarded init missing"; fi
if grep -qxF "$B_ATUING" "$B_BASHRC"; then fx_ok; else fx_bad "atuin guarded init missing"; fi
if [[ -x "$B_ATUIN_BIN" ]]; then fx_ok; else fx_bad "atuin binary not executable"; fi
if [[ "$("$B_ATUIN_BIN" --version)" == "atuin 18.23.0 "* ]]; then fx_ok; else fx_bad "atuin binary version"; fi
if [[ -f "$FX_TMP/t_real/.local/state/fedora-setup/backups/registry" ]]; then fx_ok; else fx_bad "changed bashrc produced no backup entry"; fi
if cmp -s "$B_BAK" "$FX_TMP/B.bak.snap"; then fx_ok; else fx_bad "legacy .bashrc.bak touched"; fi
fx_empty "real happy mock untouched" "$LOG"
unset FS_TERM_ALIASES FS_BASHRC FS_OMP_BIN FS_OMP_THEME FS_OMP_SRC_DIR FS_ATUIN_BIN FS_ATUIN_SRC_DIR

# === cell C: idempotent no-op (right versions, matching blocks, empty sources) ===
C="$FX_TMP/C"
C_SRC="$C/src"
C_ALIASES="$C/aliases"
C_BASHRC="$C/bashrc"
C_BIN="$C/bin/oh-my-posh"
C_THEME="$C/themes/jandedobbeleer.omp.json"
C_ATUIN_BIN="$C/bin/atuin"
mkdir -p "$C_SRC" "$C/bin" "$C/themes"
{
    printf '%s\n' 'preexisting.line = keepme'
    printf '%s\n' '# BEGIN fedora-setup terminal'
    printf "%s\n" "[ -r '$C_ALIASES' ] && . '$C_ALIASES'"
    printf "%s\n" "[ -x '$C_BIN' ] && eval \"\$('$C_BIN' init bash --config '$C_THEME')\""
    printf "%s\n" "[ -x '$C_ATUIN_BIN' ] && eval \"\$('$C_ATUIN_BIN' init bash)\""
    printf '%s\n' '# END fedora-setup terminal'
} >"$C_BASHRC"
{
    printf '%s\n' '# BEGIN fedora-setup aliases'
    printf '%s\n' "alias ll='ls -la'" "alias la='ls -A'" "alias grep='grep --color=auto'" "alias egrep='egrep --color=auto'" "alias less='less -R'"
    printf '%s\n' '# END fedora-setup aliases'
} >"$C_ALIASES"
printf '%s' "$FAKE_BIN" >"$C_BIN"
chmod 0755 "$C_BIN"
printf '%s' "$FAKE_ATUIN" >"$C_ATUIN_BIN"
chmod 0755 "$C_ATUIN_BIN"
printf '%s\n' "$THEME_BODY" >"$C_THEME"
cp "$C_BASHRC" "$FX_TMP/C.bashrc.snap"
cp "$C_ALIASES" "$FX_TMP/C.aliases.snap"
cp "$C_BIN" "$FX_TMP/C.bin.snap"
cp "$C_THEME" "$FX_TMP/C.theme.snap"
cp "$C_ATUIN_BIN" "$FX_TMP/C.atuin.snap"
export FS_TERM_ALIASES="$C_ALIASES" FS_BASHRC="$C_BASHRC"
export FS_OMP_BIN="$C_BIN" FS_OMP_THEME="$C_THEME" FS_OMP_SRC_DIR="$C_SRC"
export FS_ATUIN_BIN="$C_ATUIN_BIN" FS_ATUIN_SRC_DIR="$C_SRC"
term_run t_skip "terminal no-op skip" 0
fx_out '1 ok'
fx_out 'oh-my-posh already installed'
fx_out 'atuin already installed'
if cmp -s "$C_BASHRC" "$FX_TMP/C.bashrc.snap" && cmp -s "$C_ALIASES" "$FX_TMP/C.aliases.snap"; then fx_ok; else fx_bad "skip cell rewrote managed blocks"; fi
if cmp -s "$C_BIN" "$FX_TMP/C.bin.snap" && cmp -s "$C_THEME" "$FX_TMP/C.theme.snap"; then fx_ok; else fx_bad "skip cell rewrote binary/theme"; fi
if cmp -s "$C_ATUIN_BIN" "$FX_TMP/C.atuin.snap"; then fx_ok; else fx_bad "skip cell rewrote atuin binary"; fi
if [[ -e "$FX_TMP/t_skip/.local/state/fedora-setup/backups/registry" ]]; then fx_bad "no-op skip created backup entry"; else fx_ok; fi
unset FS_TERM_ALIASES FS_BASHRC FS_OMP_BIN FS_OMP_THEME FS_OMP_SRC_DIR FS_ATUIN_BIN FS_ATUIN_SRC_DIR

# === cell D: wrong installed version triggers reinstall ===
D="$FX_TMP/D"
D_SRC="$D/src"
D_BIN="$D/bin/oh-my-posh"
D_THEME="$D/themes/jandedobbeleer.omp.json"
D_BASHRC="$D/bashrc"
D_ALIASES="$D/aliases"
D_ATUIN_BIN="$D/bin/atuin"
D_ATUIN_SRC="$D/atuin-src"
mkdir -p "$D" "$D/bin"
mk_src "$D_SRC" lower
mk_atuin_src "$D_ATUIN_SRC" real
printf '%s' "$WRONG_BIN" >"$D_BIN"
chmod 0755 "$D_BIN"
export FS_TERM_ALIASES="$D_ALIASES" FS_BASHRC="$D_BASHRC"
export FS_OMP_BIN="$D_BIN" FS_OMP_THEME="$D_THEME" FS_OMP_SRC_DIR="$D_SRC"
export FS_ATUIN_BIN="$D_ATUIN_BIN" FS_ATUIN_SRC_DIR="$D_ATUIN_SRC"
term_run t_reinst "terminal wrong-version reinstall" 0
fx_out '1 ok'
fx_err 'replacing oh-my-posh'
if cmp -s "$D_BIN" "$D_SRC/posh-linux-amd64"; then fx_ok; else fx_bad "wrong-version bin not replaced"; fi
if cmp -s "$D_THEME" "$D_SRC/jandedobbeleer.omp.json"; then fx_ok; else fx_bad "theme not installed on reinstall"; fi
if [[ -x "$D_ATUIN_BIN" ]] && [[ "$("$D_ATUIN_BIN" --version)" == "atuin 18.23.0 "* ]]; then fx_ok; else fx_bad "atuin not installed alongside reinstall"; fi
if [[ -f "$FX_TMP/t_reinst/.local/state/fedora-setup/backups/registry" ]]; then fx_ok; else fx_bad "reinstall produced no backup entry for the replaced binary"; fi
unset FS_TERM_ALIASES FS_BASHRC FS_OMP_BIN FS_OMP_THEME FS_OMP_SRC_DIR FS_ATUIN_BIN FS_ATUIN_SRC_DIR

# === cell E: sha256 mismatch fails closed, no residue ===
E="$FX_TMP/E"
E_SRC="$E/src"
E_BIN="$E/bin/oh-my-posh"
E_THEME="$E/themes/jandedobbeleer.omp.json"
E_BASHRC="$E/bashrc"
E_ALIASES="$E/aliases"
E_ATUIN_BIN="$E/bin/atuin"
mkdir -p "$E"
mk_src "$E_SRC" wrong
export FS_TERM_ALIASES="$E_ALIASES" FS_BASHRC="$E_BASHRC"
export FS_OMP_BIN="$E_BIN" FS_OMP_THEME="$E_THEME" FS_OMP_SRC_DIR="$E_SRC"
export FS_ATUIN_BIN="$E_ATUIN_BIN"
term_run t_mismatch "terminal sha mismatch" 0 "" 1
fx_block_rc "terminal sha mismatch rc" 1
fx_err 'sha256 mismatch for oh-my-posh binary'
fx_err 'module failed: terminal'
fx_out '0 ok'
fx_out '1 failed'
if [[ -e "$E_BIN" ]]; then fx_bad "mismatch installed binary"; else fx_ok; fi
if [[ -e "$E_THEME" ]]; then fx_bad "mismatch installed theme"; else fx_ok; fi
if [[ -e "$E_ATUIN_BIN" ]]; then fx_bad "mismatch installed atuin (must abort before atuin step)"; else fx_ok; fi
if [[ -e "$E_BASHRC" ]]; then fx_bad "mismatch merged bashrc block"; else fx_ok; fi
if [[ -e "$E/bin" ]]; then
    if [[ -z "$(ls -A "$E/bin")" ]]; then fx_ok; else fx_bad "mismatch left temp residue"; fi
else
    fx_ok
fi
if [[ -f "$FX_TMP/t_mismatch/.local/state/fedora-setup/modules/terminal" ]]; then fx_bad "failed module marked done"; else fx_ok; fi
unset FS_TERM_ALIASES FS_BASHRC FS_OMP_BIN FS_OMP_THEME FS_OMP_SRC_DIR FS_ATUIN_BIN

# === cell F: HOME=/ (no HOME-derived targets) fails closed ===
F="$FX_TMP/F"
F_ALIASES="$F/aliases"
F_BASHRC="$F/bashrc"
mkdir -p "$F"
: >"$LOG"
(
    set -euo pipefail
    export FS_HOME="$FX_TMP/t_home" FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export FS_MOCK_LOG="$LOG" FS_MOCK_INSTALLED="$INST"
    export FS_OMP_ARCH="$TERM_ARCH" HOME="/"
    export FS_TERM_ALIASES="$F_ALIASES" FS_BASHRC="$F_BASHRC"
    unset FS_OMP_BIN FS_OMP_THEME FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes terminal
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "terminal HOME=/ rc" 1
fx_err 'oh-my-posh binary requires HOME or FS_OMP_BIN'
if [[ -e "$F_BASHRC" ]]; then fx_bad "HOME=/ merged bashrc block"; else fx_ok; fi

# === cell G: HOME unset (no seams at all) fails closed ===
(
    set -euo pipefail
    export FS_HOME="$FX_TMP/t_nohome" FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export FS_MOCK_LOG="$LOG" FS_MOCK_INSTALLED="$INST"
    export FS_OMP_ARCH="$TERM_ARCH"
    unset HOME FS_TERM_ALIASES FS_BASHRC FS_OMP_BIN FS_OMP_THEME 2>/dev/null || :
    unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes terminal
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "terminal HOME-unset rc" 1
fx_err 'terminal aliases require HOME or FS_TERM_ALIASES'

# === cell H: unsupported arch fails closed (dry) ===
H="$FX_TMP/H"
H_ALIASES="$H/aliases"
H_BASHRC="$H/bashrc"
H_BIN="$H/bin/oh-my-posh"
H_THEME="$H/themes/jandedobbeleer.omp.json"
mkdir -p "$H"
TERM_ARCH="s390x"
export FS_TERM_ALIASES="$H_ALIASES" FS_BASHRC="$H_BASHRC"
export FS_OMP_BIN="$H_BIN" FS_OMP_THEME="$H_THEME"
term_run t_arch "terminal unsupported arch" 1 "" 1
fx_block_rc "terminal unsupported arch rc" 1
fx_err 'unsupported architecture for oh-my-posh'
if [[ -e "$H_BIN" || -e "$H_THEME" || -e "$H_BASHRC" ]]; then fx_bad "arch fail wrote files"; else fx_ok; fi
TERM_ARCH="amd64"
unset FS_TERM_ALIASES FS_BASHRC FS_OMP_BIN FS_OMP_THEME

# === cell I: default paths derived from HOME ===
I="$FX_TMP/h_def"
I_SRC="$FX_TMP/I/src"
I_ASRC="$FX_TMP/I/atuin-src"
mkdir -p "$I" "$I_SRC"
mk_src "$I_SRC" upper
mk_atuin_src "$I_ASRC" real
IDEF_BIN="$I/.local/bin/oh-my-posh"
IDEF_THEME="$I/.config/oh-my-posh/themes/jandedobbeleer.omp.json"
IDEF_ALIASES="$I/.local/share/fedora-setup/aliases"
IDEF_BASHRC="$I/.bashrc"
IDEF_ATUIN="$I/.local/bin/atuin"
export FS_OMP_SRC_DIR="$I_SRC"
export FS_ATUIN_SRC_DIR="$I_ASRC"
term_run t_idefault "terminal default paths" 0 "$I" 0
fx_out '1 ok'
if [[ -x "$IDEF_BIN" ]]; then fx_ok; else fx_bad "default-path binary missing"; fi
if cmp -s "$IDEF_BIN" "$I_SRC/posh-linux-amd64"; then fx_ok; else fx_bad "default-path binary content"; fi
if [[ -f "$IDEF_THEME" ]]; then fx_ok; else fx_bad "default-path theme missing"; fi
if [[ -x "$IDEF_ATUIN" ]]; then fx_ok; else fx_bad "default-path atuin binary missing"; fi
if [[ "$("$IDEF_ATUIN" --version)" == "atuin 18.23.0 "* ]]; then fx_ok; else fx_bad "default-path atuin version"; fi
if grep -qxF '# BEGIN fedora-setup aliases' "$IDEF_ALIASES"; then fx_ok; else fx_bad "default-path aliases missing"; fi
IDEF_OMPG="[ -x '$IDEF_BIN' ] && eval \"\$('$IDEF_BIN' init bash --config '$IDEF_THEME')\""
IDEF_ATUING="[ -x '$IDEF_ATUIN' ] && eval \"\$('$IDEF_ATUIN' init bash)\""
if grep -qxF "$IDEF_OMPG" "$IDEF_BASHRC"; then fx_ok; else fx_bad "default-path guard missing"; fi
if grep -qxF "$IDEF_ATUING" "$IDEF_BASHRC"; then fx_ok; else fx_bad "default-path atuin guard missing"; fi
if [[ "$(ls -A "$I/.local/bin" | wc -l)" == "2" ]]; then fx_ok; else fx_bad "default-path bin dir residue"; fi
unset FS_OMP_SRC_DIR FS_ATUIN_SRC_DIR

# === cell J: `setup list` row ===
(
    set -euo pipefail
    export FS_HOME="$FX_TMP/h_list" FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    unset FS_PKG_BACKEND FS_DISTRO_FILE FS_YES FS_PROFILE 2>/dev/null || :
    "$SETUP" list
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "setup list rc" 0
if grep -q '^terminal\b' "$FX_OUT"; then fx_ok; else fx_bad "terminal row missing from list"; fi

# === cell K: non-absolute target path fails closed (dry) ===
K="$FX_TMP/K"
K_BASHRC="$K/bashrc"
K_BIN="/tmp/terminal-k-bin"
K_THEME="/tmp/terminal-k-theme.json"
mkdir -p "$K" "$K/bin"
export FS_TERM_ALIASES="relative/aliases" FS_BASHRC="$K_BASHRC"
export FS_OMP_BIN="$K_BIN" FS_OMP_THEME="$K_THEME"
term_run t_relpath "terminal relative path" 1 "" 1
fx_err 'terminal paths must be absolute: relative/aliases'
if [[ -e "$K/bin" ]]; then
    if [[ -z "$(ls -A "$K/bin")" ]]; then fx_ok; else fx_bad "relative-path guard wrote files"; fi
else
    fx_ok
fi
unset FS_TERM_ALIASES FS_BASHRC FS_OMP_BIN FS_OMP_THEME

# === cell L: quote-in-path fails closed (dry) ===
L="$FX_TMP/L"
L_ALIASES="$L/aliases"
L_BASHRC="$L/bashrc"
L_BIN="/tmp/terminal-l-bin"
L_THEME="$L/a'b/theme.json"
mkdir -p "$L"
export FS_TERM_ALIASES="$L_ALIASES" FS_BASHRC="$L_BASHRC"
export FS_OMP_BIN="$L_BIN" FS_OMP_THEME="$L_THEME"
term_run t_quote "terminal quote path" 1 "" 1
fx_err 'terminal path contains a quote or newline: '
if [[ -e "$L_ALIASES" || -e "$L_BASHRC" ]]; then fx_bad "quote-path guard wrote files"; else fx_ok; fi
unset FS_TERM_ALIASES FS_BASHRC FS_OMP_BIN FS_OMP_THEME

# === cell M: local source without sidecar refuses unverified install ===
M="$FX_TMP/M"
M_SRC="$M/src"
M_BIN="$M/bin/oh-my-posh"
M_THEME="$M/themes/jandedobbeleer.omp.json"
M_BASHRC="$M/bashrc"
M_ALIASES="$M/aliases"
mkdir -p "$M" "$M_SRC" "$M/bin"
printf '%s' "$FAKE_BIN" >"$M_SRC/posh-linux-amd64"
printf '%s\n' "$THEME_BODY" >"$M_SRC/jandedobbeleer.omp.json"
export FS_TERM_ALIASES="$M_ALIASES" FS_BASHRC="$M_BASHRC"
export FS_OMP_BIN="$M_BIN" FS_OMP_THEME="$M_THEME" FS_OMP_SRC_DIR="$M_SRC"
term_run t_nosha "terminal no sidecar" 0 "" 1
fx_err 'no checksum available for oh-my-posh'
fx_err 'module failed: terminal'
if [[ -e "$M_BIN" ]]; then fx_bad "unverified binary installed"; else fx_ok; fi
if [[ -e "$M/bin" ]]; then
    if [[ -z "$(ls -A "$M/bin")" ]]; then fx_ok; else fx_bad "no-sidecar left temp residue"; fi
else
    fx_ok
fi
unset FS_TERM_ALIASES FS_BASHRC FS_OMP_BIN FS_OMP_THEME FS_OMP_SRC_DIR

# === cell N: atuin sha256 mismatch fails closed (omp already installed) ===
N="$FX_TMP/N"
N_SRC="$N/src"
N_ASRC="$N/atuin-src"
N_BIN="$N/bin/oh-my-posh"
N_THEME="$N/themes/jandedobbeleer.omp.json"
N_ATUIN_BIN="$N/bin/atuin"
N_BASHRC="$N/bashrc"
N_ALIASES="$N/aliases"
mkdir -p "$N"
mk_src "$N_SRC" lower
mk_atuin_src "$N_ASRC" wrong
export FS_TERM_ALIASES="$N_ALIASES" FS_BASHRC="$N_BASHRC"
export FS_OMP_BIN="$N_BIN" FS_OMP_THEME="$N_THEME" FS_OMP_SRC_DIR="$N_SRC"
export FS_ATUIN_BIN="$N_ATUIN_BIN" FS_ATUIN_SRC_DIR="$N_ASRC"
term_run t_amismatch "terminal atuin sha mismatch" 0 "" 1
fx_err 'sha256 mismatch for atuin archive'
fx_err 'module failed: terminal'
fx_out '0 ok'
fx_out '1 failed'
if cmp -s "$N_BIN" "$N_SRC/posh-linux-amd64"; then fx_ok; else fx_bad "omp should be installed before atuin failure"; fi
if [[ -e "$N_ATUIN_BIN" ]]; then fx_bad "atuin mismatch installed binary"; else fx_ok; fi
if [[ -e "$N_BASHRC" ]]; then fx_bad "atuin mismatch merged bashrc block"; else fx_ok; fi
if ls -d "$N/bin"/.atuin.* >/dev/null 2>&1; then fx_bad "atuin mismatch left staging residue"; else fx_ok; fi
if [[ -e "$N/bin" ]]; then
    if [[ "$(ls -A "$N/bin")" == "oh-my-posh" ]]; then fx_ok; else fx_bad "atuin mismatch left temp residue"; fi
else
    fx_bad "atuin mismatch missing omp bin dir"
fi
if [[ -f "$FX_TMP/t_amismatch/.local/state/fedora-setup/modules/terminal" ]]; then fx_bad "atuin-failed module marked done"; else fx_ok; fi
unset FS_TERM_ALIASES FS_BASHRC FS_OMP_BIN FS_OMP_THEME FS_OMP_SRC_DIR FS_ATUIN_BIN FS_ATUIN_SRC_DIR

# === cell O: unsupported atuin arch warns + succeeds (omp still installed) ===
O="$FX_TMP/O"
O_SRC="$O/src"
O_BIN="$O/bin/oh-my-posh"
O_THEME="$O/themes/jandedobbeleer.omp.json"
O_ATUIN_BIN="$O/bin/atuin"
O_BASHRC="$O/bashrc"
O_ALIASES="$O/aliases"
mkdir -p "$O"
mk_src "$O_SRC" lower
export FS_TERM_ALIASES="$O_ALIASES" FS_BASHRC="$O_BASHRC"
export FS_OMP_BIN="$O_BIN" FS_OMP_THEME="$O_THEME" FS_OMP_SRC_DIR="$O_SRC"
export FS_ATUIN_BIN="$O_ATUIN_BIN" FS_ATUIN_ARCH="riscv"
term_run t_atuinarch "terminal atuin unsupported arch" 0
fx_out '1 ok'
fx_err 'atuin has no release for this host arch; skipping'
if cmp -s "$O_BIN" "$O_SRC/posh-linux-amd64"; then fx_ok; else fx_bad "omp not installed when atuin skipped"; fi
if [[ -e "$O_ATUIN_BIN" ]]; then fx_bad "unsupported atuin arch installed binary"; else fx_ok; fi
O_ATUING="[ -x '$O_ATUIN_BIN' ] && eval \"\$('$O_ATUIN_BIN' init bash)\""
if grep -qxF "$O_ATUING" "$O_BASHRC"; then fx_ok; else fx_bad "atuin guard line not in merged block (must be inert-by-guard)"; fi
if grep -qxF '# BEGIN fedora-setup terminal' "$O_BASHRC"; then fx_ok; else fx_bad "bashrc block missing with atuin skipped"; fi
unset FS_TERM_ALIASES FS_BASHRC FS_OMP_BIN FS_OMP_THEME FS_OMP_SRC_DIR FS_ATUIN_BIN FS_ATUIN_ARCH

# === cell P: FS_ATUIN_VERSION seam renders in the dry plan ===
P="$FX_TMP/P"
P_ALIASES="$P/aliases"
P_BASHRC="$P/bashrc"
P_BIN="$P/bin/oh-my-posh"
P_THEME="$P/themes/jandedobbeleer.omp.json"
P_ATUIN_BIN="$P/bin/atuin"
mkdir -p "$P"
export FS_TERM_ALIASES="$P_ALIASES" FS_BASHRC="$P_BASHRC"
export FS_OMP_BIN="$P_BIN" FS_OMP_THEME="$P_THEME"
export FS_ATUIN_BIN="$P_ATUIN_BIN" FS_ATUIN_VERSION="v1.9.9" FS_ATUIN_ARCH="x86_64"
term_run t_aseam "terminal atuin version seam" 1
fx_out "^# would run: install atuin v1.9.9 ($ATUIN_TRIPLE) release binary (https://github.com/atuinsh/atuin/releases/download/v1.9.9/atuin-$ATUIN_TRIPLE-unknown-linux-gnu.tar.gz) into $P_ATUIN_BIN\$"
unset FS_TERM_ALIASES FS_BASHRC FS_OMP_BIN FS_OMP_THEME FS_ATUIN_BIN FS_ATUIN_VERSION FS_ATUIN_ARCH

# === cell Q: aarch64 dry plan renders the aarch64 release URL ===
Q="$FX_TMP/Q"
Q_ALIASES="$Q/aliases"
Q_BASHRC="$Q/bashrc"
Q_BIN="$Q/bin/oh-my-posh"
Q_THEME="$Q/themes/jandedobbeleer.omp.json"
Q_ATUIN_BIN="$Q/bin/atuin"
mkdir -p "$Q"
export FS_TERM_ALIASES="$Q_ALIASES" FS_BASHRC="$Q_BASHRC"
export FS_OMP_BIN="$Q_BIN" FS_OMP_THEME="$Q_THEME"
export FS_ATUIN_BIN="$Q_ATUIN_BIN" FS_ATUIN_ARCH="aarch64"
term_run t_aarch "terminal aarch64 dry" 1
fx_out '1 ok'
fx_out "^# would run: install atuin v18.23.0 (aarch64) release binary (https://github.com/atuinsh/atuin/releases/download/v18.23.0/atuin-aarch64-unknown-linux-gnu.tar.gz) into $Q_ATUIN_BIN\$"
if [[ -e "$Q_ATUIN_BIN" || -e "$Q_BASHRC" || -e "$Q_ALIASES" ]]; then fx_bad "aarch64 dry wrote files"; else fx_ok; fi
unset FS_TERM_ALIASES FS_BASHRC FS_OMP_BIN FS_OMP_THEME FS_ATUIN_BIN FS_ATUIN_ARCH

# === cell R: aarch64 archive actually extracts the aarch64 layout ===
R="$FX_TMP/R"
R_SRC="$R/src"
R_ASRC="$R/atuin-src"
R_BIN="$R/bin/oh-my-posh"
R_THEME="$R/themes/jandedobbeleer.omp.json"
R_ATUIN_BIN="$R/bin/atuin"
R_BASHRC="$R/bashrc"
R_ALIASES="$R/aliases"
mkdir -p "$R"
mk_src "$R_SRC" lower
mk_atuin_src "$R_ASRC" real aarch64
export FS_TERM_ALIASES="$R_ALIASES" FS_BASHRC="$R_BASHRC"
export FS_OMP_BIN="$R_BIN" FS_OMP_THEME="$R_THEME" FS_OMP_SRC_DIR="$R_SRC"
export FS_ATUIN_BIN="$R_ATUIN_BIN" FS_ATUIN_SRC_DIR="$R_ASRC" FS_ATUIN_ARCH="aarch64"
term_run t_aarchreal "terminal aarch64 real" 0
fx_out '1 ok'
if [[ -x "$R_ATUIN_BIN" ]]; then fx_ok; else fx_bad "aarch64 atuin binary not executable"; fi
if [[ "$("$R_ATUIN_BIN" --version)" == "atuin 18.23.0 "* ]]; then fx_ok; else fx_bad "aarch64 atuin binary version"; fi
R_ATUING="[ -x '$R_ATUIN_BIN' ] && eval \"\$('$R_ATUIN_BIN' init bash)\""
if grep -qxF "$R_ATUING" "$R_BASHRC"; then fx_ok; else fx_bad "aarch64 atuin guard missing"; fi
if ls -d "$R/bin"/.atuin.* >/dev/null 2>&1; then fx_bad "aarch64 staging residue"; else fx_ok; fi
unset FS_TERM_ALIASES FS_BASHRC FS_OMP_BIN FS_OMP_THEME FS_OMP_SRC_DIR FS_ATUIN_BIN FS_ATUIN_SRC_DIR FS_ATUIN_ARCH

# === cell S: unsupported atuin arch renders a skip line in dry ===
S="$FX_TMP/S"
S_ALIASES="$S/aliases"
S_BASHRC="$S/bashrc"
S_BIN="$S/bin/oh-my-posh"
S_THEME="$S/themes/jandedobbeleer.omp.json"
S_ATUIN_BIN="$S/bin/atuin"
mkdir -p "$S"
export FS_TERM_ALIASES="$S_ALIASES" FS_BASHRC="$S_BASHRC"
export FS_OMP_BIN="$S_BIN" FS_OMP_THEME="$S_THEME"
export FS_ATUIN_BIN="$S_ATUIN_BIN" FS_ATUIN_ARCH="riscv"
term_run t_aduinskp "terminal atuin dry skip" 1 "" 0
fx_out '1 ok'
fx_out '^# would run: skip atuin (no release for this host arch)$'
if [[ -e "$S_ATUIN_BIN" ]]; then fx_bad "dry skip wrote atuin binary"; else fx_ok; fi
unset FS_TERM_ALIASES FS_BASHRC FS_OMP_BIN FS_OMP_THEME FS_ATUIN_BIN FS_ATUIN_ARCH

# === cell T: wrong-version atuin reinstall backs up + records registry ===
T="$FX_TMP/T"
T_SRC="$T/src"
T_ASRC="$T/atuin-src"
T_ALIASES="$T/aliases"
T_BASHRC="$T/bashrc"
T_BIN="$T/bin/oh-my-posh"
T_THEME="$T/themes/jandedobbeleer.omp.json"
T_ATUIN_BIN="$T/bin/atuin"
mkdir -p "$T_SRC" "$T/bin" "$T/themes"
mk_src "$T_SRC" lower
mk_atuin_src "$T_ASRC" real
{
    printf '%s\n' '# BEGIN fedora-setup aliases'
    printf '%s\n' "alias ll='ls -la'" "alias la='ls -A'" "alias grep='grep --color=auto'" "alias egrep='egrep --color=auto'" "alias less='less -R'"
    printf '%s\n' '# END fedora-setup aliases'
} >"$T_ALIASES"
{
    printf '%s\n' '# BEGIN fedora-setup terminal'
    printf "%s\n" "[ -r '$T_ALIASES' ] && . '$T_ALIASES'"
    printf "%s\n" "[ -x '$T_BIN' ] && eval \"\$('$T_BIN' init bash --config '$T_THEME')\""
    printf "%s\n" "[ -x '$T_ATUIN_BIN' ] && eval \"\$('$T_ATUIN_BIN' init bash)\""
    printf '%s\n' '# END fedora-setup terminal'
} >"$T_BASHRC"
printf '%s' "$FAKE_BIN" >"$T_BIN"
chmod 0755 "$T_BIN"
printf '%s' "$WRONG_ATUIN" >"$T_ATUIN_BIN"
chmod 0755 "$T_ATUIN_BIN"
printf '%s\n' "$THEME_BODY" >"$T_THEME"
cp "$T_BASHRC" "$FX_TMP/T.bashrc.snap"
export FS_TERM_ALIASES="$T_ALIASES" FS_BASHRC="$T_BASHRC"
export FS_OMP_BIN="$T_BIN" FS_OMP_THEME="$T_THEME" FS_OMP_SRC_DIR="$T_SRC"
export FS_ATUIN_BIN="$T_ATUIN_BIN" FS_ATUIN_SRC_DIR="$T_ASRC"
term_run t_awrong "terminal atuin wrong-version reinstall" 0
fx_out '1 ok'
fx_out 'oh-my-posh already installed'
fx_err 'replacing atuin'
if [[ "$("$T_ATUIN_BIN" --version)" == "atuin 18.23.0 "* ]]; then fx_ok; else fx_bad "wrong-version atuin not replaced"; fi
if cmp -s "$T_BASHRC" "$FX_TMP/T.bashrc.snap"; then fx_ok; else fx_bad "atuin reinstall rewrote matching block"; fi
if [[ -f "$FX_TMP/t_awrong/.local/state/fedora-setup/backups/registry" ]]; then fx_ok; else fx_bad "atuin reinstall produced no backup entry for the replaced binary"; fi
unset FS_TERM_ALIASES FS_BASHRC FS_OMP_BIN FS_OMP_THEME FS_OMP_SRC_DIR FS_ATUIN_BIN FS_ATUIN_SRC_DIR

# === cell U: fresh atuin with matching block adds NO backup entry ===
U="$FX_TMP/U"
U_SRC="$U/src"
U_ASRC="$U/atuin-src"
U_ALIASES="$U/aliases"
U_BASHRC="$U/bashrc"
U_BIN="$U/bin/oh-my-posh"
U_THEME="$U/themes/jandedobbeleer.omp.json"
U_ATUIN_BIN="$U/bin/atuin"
mkdir -p "$U_SRC" "$U/bin" "$U/themes"
mk_src "$U_SRC" lower
mk_atuin_src "$U_ASRC" real
{
    printf '%s\n' '# BEGIN fedora-setup aliases'
    printf '%s\n' "alias ll='ls -la'" "alias la='ls -A'" "alias grep='grep --color=auto'" "alias egrep='egrep --color=auto'" "alias less='less -R'"
    printf '%s\n' '# END fedora-setup aliases'
} >"$U_ALIASES"
{
    printf '%s\n' '# BEGIN fedora-setup terminal'
    printf "%s\n" "[ -r '$U_ALIASES' ] && . '$U_ALIASES'"
    printf "%s\n" "[ -x '$U_BIN' ] && eval \"\$('$U_BIN' init bash --config '$U_THEME')\""
    printf "%s\n" "[ -x '$U_ATUIN_BIN' ] && eval \"\$('$U_ATUIN_BIN' init bash)\""
    printf '%s\n' '# END fedora-setup terminal'
} >"$U_BASHRC"
printf '%s' "$FAKE_BIN" >"$U_BIN"
chmod 0755 "$U_BIN"
printf '%s\n' "$THEME_BODY" >"$U_THEME"
cp "$U_BASHRC" "$FX_TMP/U.bashrc.snap"
export FS_TERM_ALIASES="$U_ALIASES" FS_BASHRC="$U_BASHRC"
export FS_OMP_BIN="$U_BIN" FS_OMP_THEME="$U_THEME" FS_OMP_SRC_DIR="$U_SRC"
export FS_ATUIN_BIN="$U_ATUIN_BIN" FS_ATUIN_SRC_DIR="$U_ASRC"
term_run u_fresh "terminal fresh atuin matching block" 0
fx_out '1 ok'
fx_out 'oh-my-posh already installed'
if [[ "$("$U_ATUIN_BIN" --version)" == "atuin 18.23.0 "* ]]; then fx_ok; else fx_bad "fresh atuin not installed"; fi
if cmp -s "$U_BASHRC" "$FX_TMP/U.bashrc.snap"; then fx_ok; else fx_bad "fresh atuin rewrote matching block"; fi
if [[ -e "$FX_TMP/u_fresh/.local/state/fedora-setup/backups/registry" ]]; then fx_bad "fresh atuin no-op created backup entry"; else fx_ok; fi
unset FS_TERM_ALIASES FS_BASHRC FS_OMP_BIN FS_OMP_THEME FS_OMP_SRC_DIR FS_ATUIN_BIN FS_ATUIN_SRC_DIR

fx_summary