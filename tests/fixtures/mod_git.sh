#!/usr/bin/env bash
# tests/fixtures/mod_git.sh - P5.3 fixture for the `git` configuration module.
# Drives the REAL repo modules/ + profiles/ through `./setup install`.
# Covers: hooks-only module (no package batch) through the runner; dry-run
# rendering the merge plan line with ZERO file writes; real-mode managed-block
# creation; merge semantics (existing [user]/[core] sections preserved
# byte-for-byte, block appended once); optional identity applied only when
# both env vars are set; second-run idempotence via the registry (already
# completed) and via an untouched file when the block already matches; risk
# line; `setup list` row. Nothing outside FX_TMP + the real repo
# modules/profiles is touched.
# Usage: bash tests/fixtures/mod_git.sh  (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init
mkdir -p "$FX_TMP/I" "$FX_TMP/h" "$FX_TMP/g"

printf 'P5.3 git module\n'

SETUP="$ROOT/setup"
LOG="$FX_TMP/I/git.log"
INST="$FX_TMP/I/git.inst"
GITCFG="$FX_TMP/g/.gitconfig"
ID_NAME="Ada Lovelace"
ID_EMAIL="ada@example.test"

git_run() {
    local state_dir="$1" label="$2" dry="${3:-0}"
    : >"$LOG"
    : >"$INST"
    (   set -euo pipefail
        export FS_HOME="$FX_TMP/$state_dir"
        export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
        export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
        export FS_MOCK_LOG="$LOG" FS_MOCK_INSTALLED="$INST"
        export FS_GIT_CONFIG="$GITCFG"
        export FS_GIT_USER_NAME="$ID_NAME" FS_GIT_USER_EMAIL="$ID_EMAIL"
        if [[ "$dry" == 1 ]]; then export FS_DRY_RUN=1; fi
        unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
        "$SETUP" install --yes git
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "$label rc" 0
}

# dry-run: renders the plan line, writes nothing, no state dir
rm -rf "$FX_TMP/g"
: >"$INST"
git_run h_dry "git dry-run" 1
fx_out "^# would run: merge fedora-setup git block into $GITCFG\$"
if [[ -e "$GITCFG" ]]; then fx_bad "dry-run wrote gitconfig"; else fx_ok; fi
if [[ -e "$FX_TMP/h_dry/.local/state/fedora-setup" ]]; then fx_bad "dry-run created state dir"; else fx_ok; fi

# real-mode fresh creation with identity from env
rm -rf "$FX_TMP/h_real" "$FX_TMP/g"
mkdir -p "$FX_TMP/g"
git_run h_real "git real fresh"
fx_out 'profile: selection'
fx_out 'module: git (low)'
fx_out '^== run complete ==$'
fx_out '^  - 1 modules ok · 0 skipped · 0 failed ·'
if [[ -f "$GITCFG" ]]; then
    fx_ok
else
    fx_bad "gitconfig not created"
fi
if grep -qxF '# BEGIN fedora-setup git' "$GITCFG" && grep -qxF '# END fedora-setup git' "$GITCFG"; then
    fx_ok
else
    fx_bad "managed block markers missing"
fi
for key in $'\tdefaultBranch = main' $'\tconflictstyle = zdiff3' $'\tcolorMoved = zebra' $'\tui = auto' $'\tname = Ada Lovelace' $'\temail = ada@example.test'; do
    if grep -qxF "$key" "$GITCFG"; then fx_ok; else fx_bad "gitconfig missing: $key"; fi
done
if [[ -f "$FX_TMP/h_real/.local/state/fedora-setup/modules/git" ]]; then fx_ok; else fx_bad "git not marked done"; fi

# merge: pre-seeded user keys + unrelated section survive, block appended once
: >"$GITCFG"
cat >"$GITCFG" <<EOF
[user]
	name = Alice Example
	email = alice@example.test
[core]
	editor = vim
EOF
rm -rf "$FX_TMP/h_merge"
git_run h_merge "git merge preserves"
if grep -qxF $'\tname = Alice Example' "$GITCFG"; then fx_ok; else fx_bad "existing name lost"; fi
if grep -qxF $'\temail = alice@example.test' "$GITCFG"; then fx_ok; else fx_bad "existing email lost"; fi
if grep -qxF $'\teditor = vim' "$GITCFG"; then fx_ok; else fx_bad "existing core.editor lost"; fi
if (( $(grep -c '^# BEGIN fedora-setup git' "$GITCFG") == 1 )); then fx_ok; else fx_bad "block duplicated"; fi
if grep -qxF $'\tname = Ada Lovelace' "$GITCFG"; then fx_ok; else fx_bad "managed identity name missing"; fi
if grep -qxF $'\tname = Alice Example' "$GITCFG"; then fx_ok; else fx_bad "managed identity overwrote existing"; fi

# identity is optional and injection-safe: CR/LF or trailing-backslash values
# are rejected (io_warn) and [user] skipped, existing markers intact
printf '# BEGIN fedora-setup git\n[none]\n\terminal = x\n# END fedora-setup git\n' >"$GITCFG"
rm -rf "$FX_TMP/h_noident"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_noident"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export FS_MOCK_LOG="$LOG" FS_MOCK_INSTALLED="$INST"
    export FS_GIT_CONFIG="$GITCFG"
    unset FS_GIT_USER_NAME FS_GIT_USER_EMAIL FS_YES FS_PROFILE FS_DRY_RUN FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes git
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "git no-identity rc" 0
if grep -q '^\[user\]' "$GITCFG"; then fx_bad "managed [user] without identity env"; else fx_ok; fi
if grep -q 'erminal = x' "$GITCFG"; then fx_bad "old block junk not replaced"; else fx_ok; fi
if (( $(grep -c '^# BEGIN fedora-setup git' "$GITCFG") == 1 )); then fx_ok; else fx_bad "no-identity block count"; fi
if grep -qxF $'\tdefaultBranch = main' "$GITCFG"; then fx_ok; else fx_bad "no-identity settings missing"; fi

# CR/LF injection attempt: no [user], no forged section, still rc0 with a warn
: >"$GITCFG"
rm -rf "$FX_TMP/h_inject"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_inject"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export FS_MOCK_LOG="$LOG" FS_MOCK_INSTALLED="$INST"
    export FS_GIT_CONFIG="$GITCFG"
    export FS_GIT_USER_NAME=$'Eve\n[core]\n\thooksPath = /tmp/evil' FS_GIT_USER_EMAIL='eve@example.test'
    unset FS_YES FS_PROFILE FS_DRY_RUN FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes git
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "git injection rc" 0
fx_err 'skipping \[user\]'
if grep -q '^\[user\]' "$GITCFG"; then fx_bad "forged [user] present"; else fx_ok; fi
if grep -q 'hooksPath' "$GITCFG"; then fx_bad "forged core.hooksPath present"; else fx_ok; fi
if grep -qxF $'\tdefaultBranch = main' "$GITCFG"; then fx_ok; else fx_bad "injection cell lost settings"; fi

# trailing-backslash rejection
: >"$GITCFG"
rm -rf "$FX_TMP/h_slash"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_slash"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export FS_MOCK_LOG="$LOG" FS_MOCK_INSTALLED="$INST"
    export FS_GIT_CONFIG="$GITCFG"
    export FS_GIT_USER_NAME='Ada\' FS_GIT_USER_EMAIL='ada@example.test'
    unset FS_YES FS_PROFILE FS_DRY_RUN FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes git
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "git trailing-backslash rc" 0
if grep -q '^\[user\]' "$GITCFG"; then fx_bad "backslash identity applied"; else fx_ok; fi

# matching block already present: hook re-runs, file byte-identical, NO new
# backup-registry entry (fs_managed_block no-write path)
: >"$GITCFG"
cat >"$GITCFG" <<EOF
some.otherkey = keepme
# BEGIN fedora-setup git
[init]
	defaultBranch = main
[merge]
	conflictstyle = zdiff3
[diff]
	colorMoved = zebra
[color]
	ui = auto
[user]
	name = Ada Lovelace
	email = ada@example.test
# END fedora-setup git
EOF
cp "$GITCFG" "$FX_TMP/g/.gitconfig.match"
rm -rf "$FX_TMP/h_match"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_match"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export FS_MOCK_LOG="$LOG" FS_MOCK_INSTALLED="$INST"
    export FS_GIT_CONFIG="$GITCFG"
    export FS_GIT_USER_NAME="$ID_NAME" FS_GIT_USER_EMAIL="$ID_EMAIL"
    unset FS_YES FS_PROFILE FS_DRY_RUN FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes git
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "git matching block rc" 0
if cmp -s "$GITCFG" "$FX_TMP/g/.gitconfig.match" 2>/dev/null; then
    fx_ok
else
    fx_bad "matching block re-ran caused a write"
fi
if [[ -f "$FX_TMP/h_match/.local/state/fedora-setup/backups/registry" ]]; then
    fx_bad "matching block created a backup entry (expected none)"
else
    fx_ok
fi

# second run idempotent: registry skips, file byte-identical
cp "$GITCFG" "$FX_TMP/g/.gitconfig.prev"
git_run h_merge "git second run idempotent"
fx_out 'already completed: git'
fx_out '^  - 0 modules ok · 1 skipped · 0 failed ·'
if cmp -s "$GITCFG" "$FX_TMP/g/.gitconfig.prev" 2>/dev/null; then
    fx_ok
else
    fx_bad "gitconfig changed on second run"
fi

# `setup list` row (hermetic, matches modules_list.sh convention)
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_list" FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    unset FS_PKG_BACKEND FS_DISTRO_FILE FS_YES FS_PROFILE FS_GIT_USER_NAME FS_GIT_USER_EMAIL 2>/dev/null || :
    "$SETUP" list
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "setup list rc" 0
if grep -q '^git\b' "$FX_OUT"; then fx_ok; else fx_bad "git row missing from list"; fi

fx_summary