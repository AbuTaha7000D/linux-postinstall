#!/usr/bin/env bash
# tests/fixtures/mod_terminal.sh - P5.5 fixture for the `terminal` module.
# Drives the REAL repo modules/ + profiles/ through `./setup install`.
# Covers: hooks-only module (no package batch) through the runner; dry-run
# rendering the aliases/omp/theme/bashrc plan lines with ZERO writes; real
# sha256-verified oh-my-posh binary install (uppercase OMP-style checksum),
# theme install, aliases managed block, and .bashrc managed block that
# preserves every unmanaged line byte-for-byte (and never touches a legacy
# ~/.bashrc.bak); idempotent no-op re-run (already-installed version, empty
# local source => skip-before-source proof); wrong-version reinstall;
# sha256-mismatch fail-closed (rc1, no binary, no theme, no block, no
# temp residue); HOME=/ and HOME-unset fail-closed; unsupported arch; default
# path resolution from a scratch HOME; `setup list` row. Nothing outside
# FX_TMP + the real repo modules/profiles is touched. The task's
# "bash -l produces a prompt line" check is real-host [REAL] verification:
# this fixture proves the guarded init line is present and byte-exact.
# Usage: bash tests/fixtures/mod_terminal.sh  (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init
mkdir -p "$FX_TMP"

printf 'P5.5 terminal module\n'

SETUP="$ROOT/setup"
LOG="$FX_TMP/I/term.log"
INST="$FX_TMP/I/term.inst"
mkdir -p "$(dirname "$LOG")"
TERM_ARCH="amd64"

FAKE_BIN='#!/bin/sh
echo "23.9.0"
'
WRONG_BIN='#!/bin/sh
echo "23.8.0"
'
THEME_BODY='{"schema":"test-theme"}'

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
mkdir -p "$A"
export FS_TERM_ALIASES="$A_ALIASES" FS_BASHRC="$A_BASHRC"
export FS_OMP_BIN="$A_BIN" FS_OMP_THEME="$A_THEME"
term_run t_dry "terminal dry-run" 1
fx_out 'profile: selection'
fx_out 'module: terminal (low)'
fx_out '^== run complete ==$'
fx_out '1 ok'
fx_out "^# would run: merge fedora-setup aliases block into $A_ALIASES\$"
fx_out "^# would run: install oh-my-posh v23.9.0 (amd64) release binary (https://github.com/JanDeDobbeleer/oh-my-posh/releases/download/v23.9.0/posh-linux-amd64) into $A_BIN\$"
fx_out "^# would run: install oh-my-posh theme (https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/v23.9.0/themes/jandedobbeleer.omp.json) into $A_THEME\$"
fx_out "^# would run: merge fedora-setup terminal block into $A_BASHRC\$"
if [[ -e "$A_BIN" ]]; then fx_bad "dry-run wrote omp binary"; else fx_ok; fi
if [[ -e "$A_THEME" ]]; then fx_bad "dry-run wrote theme"; else fx_ok; fi
if [[ -e "$A_BASHRC" ]]; then fx_bad "dry-run wrote bashrc"; else fx_ok; fi
if [[ -e "$A_ALIASES" ]]; then fx_bad "dry-run wrote aliases"; else fx_ok; fi
if [[ -e "$FX_TMP/t_dry/.local/state/fedora-setup" ]]; then fx_bad "dry-run created state dir"; else fx_ok; fi
fx_empty "dry-run mock untouched" "$LOG"
unset FS_TERM_ALIASES FS_BASHRC FS_OMP_BIN FS_OMP_THEME

# === cell B: real happy path (uppercase OMP-style checksum, local source) ===
B="$FX_TMP/B"
B_SRC="$B/src"
B_ALIASES="$B/aliases"
B_BASHRC="$B/bashrc"
B_BAK="$B_BASHRC.bak"
B_BIN="$B/bin/oh-my-posh"
B_THEME="$B/themes/jandedobbeleer.omp.json"
mkdir -p "$B"
mk_src "$B_SRC" upper
printf 'export EDITOR=vim\n' >"$B_BASHRC"
printf '# legacy backup from the old prototype\nexport CUSTOM=keep\n' >"$B_BAK"
cp "$B_BAK" "$FX_TMP/B.bak.snap"
export FS_TERM_ALIASES="$B_ALIASES" FS_BASHRC="$B_BASHRC"
export FS_OMP_BIN="$B_BIN" FS_OMP_THEME="$B_THEME" FS_OMP_SRC_DIR="$B_SRC"
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
if grep -qxF "$B_GUARD" "$B_BASHRC"; then fx_ok; else fx_bad "aliases sourcing guard missing"; fi
if grep -qxF "$B_OMPG" "$B_BASHRC"; then fx_ok; else fx_bad "omp guarded init missing"; fi
if [[ -f "$FX_TMP/t_real/.local/state/fedora-setup/backups/registry" ]]; then fx_ok; else fx_bad "changed bashrc produced no backup entry"; fi
if cmp -s "$B_BAK" "$FX_TMP/B.bak.snap"; then fx_ok; else fx_bad "legacy .bashrc.bak touched"; fi
fx_empty "real happy mock untouched" "$LOG"
unset FS_TERM_ALIASES FS_BASHRC FS_OMP_BIN FS_OMP_THEME FS_OMP_SRC_DIR

# === cell C: idempotent no-op (right version, matching blocks, empty source) ===
C="$FX_TMP/C"
C_SRC="$C/src"
C_ALIASES="$C/aliases"
C_BASHRC="$C/bashrc"
C_BIN="$C/bin/oh-my-posh"
C_THEME="$C/themes/jandedobbeleer.omp.json"
mkdir -p "$C_SRC" "$C/bin" "$C/themes"
{
    printf '%s\n' 'preexisting.line = keepme'
    printf '%s\n' '# BEGIN fedora-setup terminal'
    printf "%s\n" "[ -r '$C_ALIASES' ] && . '$C_ALIASES'"
    printf "%s\n" "[ -x '$C_BIN' ] && eval \"\$('$C_BIN' init bash --config '$C_THEME')\""
    printf '%s\n' '# END fedora-setup terminal'
} >"$C_BASHRC"
{
    printf '%s\n' '# BEGIN fedora-setup aliases'
    printf '%s\n' "alias ll='ls -la'" "alias la='ls -A'" "alias grep='grep --color=auto'" "alias egrep='egrep --color=auto'" "alias less='less -R'"
    printf '%s\n' '# END fedora-setup aliases'
} >"$C_ALIASES"
printf '%s' "$FAKE_BIN" >"$C_BIN"
chmod 0755 "$C_BIN"
printf '%s\n' "$THEME_BODY" >"$C_THEME"
cp "$C_BASHRC" "$FX_TMP/C.bashrc.snap"
cp "$C_ALIASES" "$FX_TMP/C.aliases.snap"
cp "$C_BIN" "$FX_TMP/C.bin.snap"
cp "$C_THEME" "$FX_TMP/C.theme.snap"
export FS_TERM_ALIASES="$C_ALIASES" FS_BASHRC="$C_BASHRC"
export FS_OMP_BIN="$C_BIN" FS_OMP_THEME="$C_THEME" FS_OMP_SRC_DIR="$C_SRC"
term_run t_skip "terminal no-op skip" 0
fx_out '1 ok'
fx_out 'oh-my-posh already installed'
if cmp -s "$C_BASHRC" "$FX_TMP/C.bashrc.snap" && cmp -s "$C_ALIASES" "$FX_TMP/C.aliases.snap"; then fx_ok; else fx_bad "skip cell rewrote managed blocks"; fi
if cmp -s "$C_BIN" "$FX_TMP/C.bin.snap" && cmp -s "$C_THEME" "$FX_TMP/C.theme.snap"; then fx_ok; else fx_bad "skip cell rewrote binary/theme"; fi
if [[ -e "$FX_TMP/t_skip/.local/state/fedora-setup/backups/registry" ]]; then fx_bad "no-op skip created backup entry"; else fx_ok; fi
unset FS_TERM_ALIASES FS_BASHRC FS_OMP_BIN FS_OMP_THEME FS_OMP_SRC_DIR

# === cell D: wrong installed version triggers reinstall ===
D="$FX_TMP/D"
D_SRC="$D/src"
D_BIN="$D/bin/oh-my-posh"
D_THEME="$D/themes/jandedobbeleer.omp.json"
D_BASHRC="$D/bashrc"
D_ALIASES="$D/aliases"
mkdir -p "$D" "$D/bin"
mk_src "$D_SRC" lower
printf '%s' "$WRONG_BIN" >"$D_BIN"
chmod 0755 "$D_BIN"
export FS_TERM_ALIASES="$D_ALIASES" FS_BASHRC="$D_BASHRC"
export FS_OMP_BIN="$D_BIN" FS_OMP_THEME="$D_THEME" FS_OMP_SRC_DIR="$D_SRC"
term_run t_reinst "terminal wrong-version reinstall" 0
fx_out '1 ok'
fx_err 'replacing oh-my-posh'
if cmp -s "$D_BIN" "$D_SRC/posh-linux-amd64"; then fx_ok; else fx_bad "wrong-version bin not replaced"; fi
if cmp -s "$D_THEME" "$D_SRC/jandedobbeleer.omp.json"; then fx_ok; else fx_bad "theme not installed on reinstall"; fi
if [[ -f "$FX_TMP/t_reinst/.local/state/fedora-setup/backups/registry" ]]; then fx_ok; else fx_bad "reinstall produced no backup entry for the replaced binary"; fi
unset FS_TERM_ALIASES FS_BASHRC FS_OMP_BIN FS_OMP_THEME FS_OMP_SRC_DIR

# === cell E: sha256 mismatch fails closed, no residue ===
E="$FX_TMP/E"
E_SRC="$E/src"
E_BIN="$E/bin/oh-my-posh"
E_THEME="$E/themes/jandedobbeleer.omp.json"
E_BASHRC="$E/bashrc"
E_ALIASES="$E/aliases"
mkdir -p "$E"
mk_src "$E_SRC" wrong
export FS_TERM_ALIASES="$E_ALIASES" FS_BASHRC="$E_BASHRC"
export FS_OMP_BIN="$E_BIN" FS_OMP_THEME="$E_THEME" FS_OMP_SRC_DIR="$E_SRC"
term_run t_mismatch "terminal sha mismatch" 0 "" 1
fx_block_rc "terminal sha mismatch rc" 1
fx_err 'sha256 mismatch for oh-my-posh binary'
fx_err 'module failed: terminal'
fx_out '0 ok'
fx_out '1 failed'
if [[ -e "$E_BIN" ]]; then fx_bad "mismatch installed binary"; else fx_ok; fi
if [[ -e "$E_THEME" ]]; then fx_bad "mismatch installed theme"; else fx_ok; fi
if [[ -e "$E_BASHRC" ]]; then fx_bad "mismatch merged bashrc block"; else fx_ok; fi
if [[ -e "$E/bin" ]]; then
    if [[ -z "$(ls -A "$E/bin")" ]]; then fx_ok; else fx_bad "mismatch left temp residue"; fi
else
    fx_ok
fi
if [[ -f "$FX_TMP/t_mismatch/.local/state/fedora-setup/modules/terminal" ]]; then fx_bad "failed module marked done"; else fx_ok; fi
unset FS_TERM_ALIASES FS_BASHRC FS_OMP_BIN FS_OMP_THEME FS_OMP_SRC_DIR

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
mkdir -p "$I" "$I_SRC"
mk_src "$I_SRC" upper
IDEF_BIN="$I/.local/bin/oh-my-posh"
IDEF_THEME="$I/.config/oh-my-posh/themes/jandedobbeleer.omp.json"
IDEF_ALIASES="$I/.local/share/fedora-setup/aliases"
IDEF_BASHRC="$I/.bashrc"
export FS_OMP_SRC_DIR="$I_SRC"
term_run t_idefault "terminal default paths" 0 "$I" 0
fx_out '1 ok'
if [[ -x "$IDEF_BIN" ]]; then fx_ok; else fx_bad "default-path binary missing"; fi
if cmp -s "$IDEF_BIN" "$I_SRC/posh-linux-amd64"; then fx_ok; else fx_bad "default-path binary content"; fi
if [[ -f "$IDEF_THEME" ]]; then fx_ok; else fx_bad "default-path theme missing"; fi
if grep -qxF '# BEGIN fedora-setup aliases' "$IDEF_ALIASES"; then fx_ok; else fx_bad "default-path aliases missing"; fi
IDEF_OMPG="[ -x '$IDEF_BIN' ] && eval \"\$('$IDEF_BIN' init bash --config '$IDEF_THEME')\""
if grep -qxF "$IDEF_OMPG" "$IDEF_BASHRC"; then fx_ok; else fx_bad "default-path guard missing"; fi
if [[ "$(ls -A "$I/.local/bin")" == "oh-my-posh" ]]; then fx_ok; else fx_bad "default-path bin dir residue"; fi
unset FS_OMP_SRC_DIR

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

fx_summary