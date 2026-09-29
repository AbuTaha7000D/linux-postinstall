#!/usr/bin/env bash
# tests/fixtures/mod_gnome_theme.sh - P6.4 fixture for the `gnome-theme`
# module. Drives the REAL repo modules/ + profiles/ through `./setup install`.
# Mock strategy (same as mod_gnome.sh): a PATH-visible fake `gsettings`
# answers `get` from a FAKE_KEY_FILE (schema-key|value lines; default @as [])
# and logs every `set` to $FAKE_LOG, so idempotency is provable by "no set
# logged". Bookmarks are real files under FX_TMP via the FS_GTK_BOOKMARKS_FILE
# seam. Covers: dry-run purity (exact `# would run:` plan incl. the escaped
# single-quoted gsettings value, ZERO probes/writes, no state dir); explicit
# FS_THEME_NAME / FS_CURSOR_NAME; auto-pick from FS_THEME_SRC and assets
# fallback; multiple-theme skip; non-GNOME skip; relative seam fail-closed rc1
# in both modes; gsettings-missing fail-closed; real-mode apply + bookmarks
# whole-line dedupe (first-seen, order kept, trailing-space variant treated as
# distinct, mode preserved, backup registered); exact idempotent re-run (no
# set, no write, no registry entry); absent bookmarks file skip (no mkdir);
# invalid theme name rc1; `setup list` shows the module (default on).
# Icon theme: asserted never to appear in any plan, log, or gsettings write.
# Also pins the two review blockers: blank-line and newline-only bookmarks
# dedupe as ordinary lines (no `bad array subscript` on empty lines), and a
# HOME-unset dry-run that plans cleanly instead of aborting on an unbound
# HOME (plus its clean fail-closed rc1 when no bookmarks seam exists).
# Usage: bash tests/fixtures/mod_gnome_theme.sh  (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init
mkdir -p "$FX_TMP/fakebin" "$FX_TMP/notools" \
    "$FX_TMP/themes/Dracula" "$FX_TMP/cursors/Bibata" \
    "$FX_TMP/assets_t/Sweet" "$FX_TMP/assetk/Bibata-Modern" \
    "$FX_TMP/themes2/Mint-Y-Dark" "$FX_TMP/themes2/Mint-Y" \
    "$FX_TMP/cursors2/Adwaita" "$FX_TMP/cursors2/DMZ-Black"
ln -sf "${DK_DIRNAME:-/usr/bin/dirname}" "$FX_TMP/notools/dirname"

printf 'P6.4 gnome-theme module\n'

cat >"$FX_TMP/fakebin/gsettings" <<'EOF'
#!/usr/bin/env bash
: >>"$FAKE_LOG" 2>/dev/null || :
case "$1" in
    get)
        key="$2/$3"
        while IFS='' read -r line || [[ -n "$line" ]]; do
            k="${line%%|*}"
            [[ "$k" == "$key" ]] && { printf '%s\n' "${line#*|}"; exit 0; }
        done <"${FAKE_KEY_FILE:-/dev/null}"
        printf '%s\n' "${FAKE_GET:-@as []}"
        exit 0
        ;;
    set)
        printf 'set %s %s %s\n' "$2" "$3" "$4" >>"$FAKE_LOG" 2>/dev/null || :
        exit 0
        ;;
    *) exit 0 ;;
esac
EOF
chmod +x "$FX_TMP/fakebin/gsettings"

SETUP="$ROOT/setup"
LOG="$FX_TMP/fake.log"

# --- 1. dry-run, explicit names + bookmarks present: exact plan, no side effects ---
echo "--- cell: dry-run explicit names + bookmarks"
: >"$LOG"
: >"$FX_TMP/keys"
printf 'file:///home/u/Github\nfile:///home/u/Github\n' >"$FX_TMP/bm_dry"
rm -rf "$FX_TMP/h_dry"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_dry"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys"
    export FS_THEME_NAME=Aurora FS_CURSOR_NAME=DMZ-Black
    export FS_GTK_BOOKMARKS_FILE="$FX_TMP/bm_dry"
    export FS_THEME_SRC="$FX_TMP/themes" FS_CURSOR_SRC="$FX_TMP/cursors"
    export FS_DRY_RUN=1
    unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes gnome-theme
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "dry explicit rc" 0
[[ $(grep -c '^# would run:' "$FX_OUT") == 3 ]] && fx_ok || fx_bad "dry plan is 3 lines (got $(grep -c '^# would run:' "$FX_OUT"))"
fx_out '# would run: gsettings set org.gnome.desktop.interface gtk-theme'
grep -Fq "gtk-theme \\'Aurora" "$FX_OUT" && fx_ok || fx_bad "dry plan quotes the GTK theme value"
grep -Fq "cursor-theme \\'DMZ-Black" "$FX_OUT" && fx_ok || fx_bad "dry plan quotes the cursor theme value"
grep -Fqx "# would run: dedupe gtk-3.0 bookmarks $FX_TMP/bm_dry" "$FX_OUT" && fx_ok || fx_bad "dry plan renders the bookmarks dedupe"
if grep -Fq 'icon-theme' "$FX_OUT"; then fx_bad "dry plan must not mention icon-theme"; else fx_ok; fi
fx_out "icon theme untouched"
fx_out "applying gtk-theme: Aurora"
fx_out "applying cursor-theme: DMZ-Black"
[[ ! -s "$LOG" ]] && fx_ok || fx_bad "dry-run never invokes gsettings"
[[ ! -e "$FX_TMP/h_dry/.local/state/fedora-setup" ]] && fx_ok || fx_bad "dry-run created a state dir"
[[ "$(cat "$FX_TMP/bm_dry")" == "$(printf 'file:///home/u/Github\nfile:///home/u/Github\n')" ]] && fx_ok || fx_bad "dry-run must not touch the bookmarks file"

# --- 2. dry-run, auto-pick theme+cursor from source dirs, no bookmarks file ---
echo "--- cell: dry-run auto-pick, no bookmarks"
: >"$LOG"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_dry2"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys"
    export FS_THEME_SRC="$FX_TMP/themes" FS_CURSOR_SRC="$FX_TMP/cursors"
    export FS_GTK_BOOKMARKS_FILE="$FX_TMP/no-such-dir/bm"
    export FS_DRY_RUN=1
    unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes gnome-theme
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "dry auto-pick rc" 0
[[ $(grep -c '^# would run:' "$FX_OUT") == 2 ]] && fx_ok || fx_bad "auto-pick dry plan is 2 lines (got $(grep -c '^# would run:' "$FX_OUT"))"
grep -Fq "gtk-theme \\'Dracula" "$FX_OUT" && fx_ok || fx_bad "auto-picked theme name is the single source dir"
grep -Fq "cursor-theme \\'Bibata" "$FX_OUT" && fx_ok || fx_bad "auto-picked cursor name is the single source dir"
fx_out "nothing to dedupe"
[[ ! -s "$LOG" ]] && fx_ok || fx_bad "auto-pick dry-run never invokes gsettings"
[[ ! -e "$FX_TMP/no-such-dir" ]] && fx_ok || fx_bad "missing bookmarks dir must never be created"

# --- 3. dry-run, assets fallback when no source dir ---
echo "--- cell: dry-run assets fallback"
: >"$LOG"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_dry3"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys"
    export FS_THEME_SRC="$FX_TMP/no-themes" FS_CURSOR_SRC="$FX_TMP/cursors"
    export FS_THEME_ASSETS_DIR="$FX_TMP/assets_t"
    export FS_GTK_BOOKMARKS_FILE="$FX_TMP/bm_dry"
    export FS_DRY_RUN=1
    unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes gnome-theme
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "dry assets rc" 0
grep -Fq "gtk-theme \\'Sweet" "$FX_OUT" && fx_ok || fx_bad "assets fallback picked the single assets theme"
[[ $(grep -c '^# would run:' "$FX_OUT") == 3 ]] && fx_ok || fx_bad "assets dry plan is 3 lines (got $(grep -c '^# would run:' "$FX_OUT"))"

# --- 4. dry-run, multiple themes in source: skip theme+cursor ---
echo "--- cell: dry-run multiple-theme skip"
: >"$LOG"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_dry4"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys"
    export FS_THEME_SRC="$FX_TMP/themes2" FS_CURSOR_SRC="$FX_TMP/cursors2"
    export FS_GTK_BOOKMARKS_FILE="$FX_TMP/bm_dry"
    export FS_DRY_RUN=1
    unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes gnome-theme
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "dry multi rc" 0
[[ $(grep -c '^# would run:' "$FX_OUT") == 1 ]] && fx_ok || fx_bad "only the bookmarks plan when themes are ambiguous (got $(grep -c '^# would run:' "$FX_OUT"))"
fx_out "multiple gtk-theme themes in"
fx_out "multiple cursor-theme themes in"
[[ ! -s "$LOG" ]] && fx_ok || fx_bad "multi-theme dry-run never invokes gsettings"

# --- 4b. HOME unset (headless dry-run): no unbound-variable panic ---
echo "--- cell: HOME unset dry-run"
: >"$LOG"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_nohome"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys"
    export FS_THEME_NAME=Aurora FS_CURSOR_NAME=DMZ-Black
    export FS_GTK_BOOKMARKS_FILE="$FX_TMP/bm_dry"
    export FS_DRY_RUN=1
    unset HOME FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes gnome-theme
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "HOME unset dry rc" 0
[[ $(grep -c '^# would run:' "$FX_OUT") == 3 ]] && fx_ok || fx_bad "HOME-unset dry plan is 3 lines (got $(grep -c '^# would run:' "$FX_OUT"))"
if grep -q 'unbound variable' "$FX_ERR"; then fx_bad "no unbound-variable panic without HOME"; else fx_ok; fi
[[ ! -s "$LOG" ]] && fx_ok || fx_bad "HOME-unset dry-run never invokes gsettings"

echo "--- cell: HOME unset, no bookmarks seam fails closed cleanly"
: >"$LOG"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_nohome2"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys"
    export FS_THEME_NAME=Aurora FS_CURSOR_NAME=DMZ-Black
    export FS_DRY_RUN=1
    unset HOME FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes gnome-theme
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
if [[ "$FX_BLOCK_RC" == 1 ]]; then fx_ok; else fx_bad "HOME unset + no bookmarks seam rc1"; fi
fx_err "requires FS_GTK_BOOKMARKS_FILE or a HOME"
if grep -q 'unbound variable' "$FX_ERR"; then fx_bad "fail-closed must be an io_error, not a panic"; else fx_ok; fi

# --- 5. dry-run, non-GNOME desktop: graceful skip ---
echo "--- cell: non-GNOME skip"
: >"$LOG"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_dry5"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export XDG_CURRENT_DESKTOP=KDE
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys"
    export FS_THEME_NAME=Aurora
    export FS_GTK_BOOKMARKS_FILE="$FX_TMP/bm_dry"
    export FS_DRY_RUN=1
    unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes gnome-theme
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "non-GNOME rc" 0
fx_out "no GNOME session"
[[ $(grep -c '^# would run:' "$FX_OUT") == 0 ]] && fx_ok || fx_bad "non-GNOME skip plans nothing"
[[ ! -s "$LOG" ]] && fx_ok || fx_bad "non-GNOME skip never invokes gsettings"

# --- 6. relative seams fail closed in dry AND real mode ---
echo "--- cell: relative seam fail-closed (dry)"
: >"$LOG"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_rc6"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys"
    export FS_GTK_BOOKMARKS_FILE="relative/bookmarks"
    export FS_DRY_RUN=1
    unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes gnome-theme
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
if [[ "$FX_BLOCK_RC" == 1 ]]; then fx_ok; else fx_bad "relative bookmarks dry rc1"; fi
fx_err "FS_GTK_BOOKMARKS_FILE must be absolute"
[[ $(grep -c '^# would run:' "$FX_OUT") == 0 ]] && fx_ok || fx_bad "no plan before the preflight failure"
[[ ! -s "$LOG" ]] && fx_ok || fx_bad "preflight failure never invokes gsettings"

echo "--- cell: relative theme source fail-closed (real)"
: >"$LOG"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_rc6b"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys"
    export FS_THEME_SRC="themes/relative"
    unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes gnome-theme
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
if [[ "$FX_BLOCK_RC" == 1 ]]; then fx_ok; else fx_bad "relative theme source real rc1"; fi
fx_err "FS_THEME_SRC must be absolute"
[[ ! -s "$LOG" ]] && fx_ok || fx_bad "preflight failure never invokes gsettings"

# --- 7. real mode: apply theme+cursor, dedupe bookmarks, icon theme untouched ---
echo "--- cell: real apply + bookmarks dedupe"
: >"$LOG"
: >"$FX_TMP/keys7"
printf 'file:///home/u/Github\nfile:///home/u/Documents\nfile:///home/u/Github\nfile:///home/u/Downloads\nfile:///home/u/Github \nfile:///home/u/Github\n' >"$FX_TMP/bm7"
printf 'file:///home/u/Github\nfile:///home/u/Documents\nfile:///home/u/Downloads\nfile:///home/u/Github \n' >"$FX_TMP/bm7_expected"
chmod 640 "$FX_TMP/bm7"
rm -rf "$FX_TMP/h_real7"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_real7"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys7"
    export FS_THEME_NAME=Aurora FS_CURSOR_NAME=DMZ-Black
    export FS_GTK_BOOKMARKS_FILE="$FX_TMP/bm7"
    unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes gnome-theme
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "real apply rc" 0
grep -Fq "set org.gnome.desktop.interface gtk-theme 'Aurora'" "$LOG" && fx_ok || fx_bad "GTK theme applied"
grep -Fq "set org.gnome.desktop.interface cursor-theme 'DMZ-Black'" "$LOG" && fx_ok || fx_bad "cursor theme applied"
[[ $(grep -cF 'icon-theme' "$LOG") == 0 ]] && fx_ok || fx_bad "icon theme must never be written"
cmp -s "$FX_TMP/bm7_expected" "$FX_TMP/bm7" && fx_ok || fx_bad "bookmarks deduped (first-seen, order kept, trailing-space variant kept)"
[[ "$(stat -c %a "$FX_TMP/bm7")" == 640 ]] && fx_ok || fx_bad "bookmarks mode preserved"
fx_out "bookmarks deduplicated (2 duplicate"
fx_out "icon theme untouched"
[[ $(grep -cF 'icon-theme' "$FX_OUT") == 0 ]] && fx_ok || fx_bad "no icon-theme mention with hyphen anywhere"

# --- 8. real idempotent re-run: no set, no write, no registry entry ---
echo "--- cell: real idempotent re-run"
: >"$LOG"
printf 'file:///home/u/Github\nfile:///home/u/Documents\n' >"$FX_TMP/bm8"
cp "$FX_TMP/bm8" "$FX_TMP/bm8_copy"
printf '%s\n' "org.gnome.desktop.interface/gtk-theme|'Aurora'" \
    "org.gnome.desktop.interface/cursor-theme|'DMZ-Black'" >"$FX_TMP/keys8"
rm -rf "$FX_TMP/h_real8"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_real8"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys8"
    export FS_THEME_NAME=Aurora FS_CURSOR_NAME=DMZ-Black
    export FS_GTK_BOOKMARKS_FILE="$FX_TMP/bm8"
    unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes gnome-theme
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "idempotent rc" 0
[[ ! -s "$LOG" ]] && fx_ok || fx_bad "no gsettings write when already at target"
cmp -s "$FX_TMP/bm8_copy" "$FX_TMP/bm8" && fx_ok || fx_bad "already-deduped bookmarks must be byte-identical"
fx_out "already deduplicated; no write"
if grep -q "|$FX_TMP/bm8|" "$FX_TMP/h_real8/.local/state/fedora-setup/backups/registry" 2>/dev/null; then
    fx_bad "no backup registry entry for a no-write run"
else
    fx_ok
fi

# --- 9. real mode, absent bookmarks: skip, no mkdir ---
echo "--- cell: real absent bookmarks skip"
: >"$LOG"
rm -rf "$FX_TMP/h_real9" "$FX_TMP/no-bm-dir9"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_real9"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys8"
    export FS_THEME_NAME=Aurora
    export FS_GTK_BOOKMARKS_FILE="$FX_TMP/no-bm-dir9/bookmarks"
    unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes gnome-theme
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "absent bookmarks rc" 0
fx_out "nothing to dedupe"
[[ ! -e "$FX_TMP/no-bm-dir9" ]] && fx_ok || fx_bad "absent bookmarks dir must never be created"

# --- 9b. real mode, blank-line + newline-only bookmarks: empty line = ordinary line ---
echo "--- cell: blank line dedupe"
: >"$LOG"
: >"$FX_TMP/keysb"
printf 'file:///home/u/Github\n\nfile:///home/u/Github\n' >"$FX_TMP/bm_blank"
printf 'file:///home/u/Github\n\n' >"$FX_TMP/bm_blank_expected"
rm -rf "$FX_TMP/h_blank"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_blank"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keysb"
    export FS_THEME_NAME=Aurora
    export FS_GTK_BOOKMARKS_FILE="$FX_TMP/bm_blank"
    unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes gnome-theme
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "blank line dedupe rc" 0
cmp -s "$FX_TMP/bm_blank_expected" "$FX_TMP/bm_blank" && fx_ok || fx_bad "blank-line bookmarks deduped (empty line kept once)"
fx_out "bookmarks deduplicated (1 duplicate"
if grep -q 'bad array subscript' "$FX_ERR"; then fx_bad "no bad-array-subscript crash on empty lines"; else fx_ok; fi

echo "--- cell: newline-only bookmarks no-op"
: >"$LOG"
printf '\n' >"$FX_TMP/bm_nlonly"
cp "$FX_TMP/bm_nlonly" "$FX_TMP/bm_nlonly_copy"
rm -rf "$FX_TMP/h_nlonly"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_nlonly"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keysb"
    export FS_THEME_NAME=Aurora
    export FS_GTK_BOOKMARKS_FILE="$FX_TMP/bm_nlonly"
    unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes gnome-theme
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "newline-only rc" 0
cmp -s "$FX_TMP/bm_nlonly_copy" "$FX_TMP/bm_nlonly" && fx_ok || fx_bad "newline-only bookmarks file untouched"
fx_out "already deduplicated; no write"

# --- 10. gsettings missing: fail closed ---
echo "--- cell: gsettings missing"
: >"$LOG"
rm -rf "$FX_TMP/h_notools"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_notools"
    export PATH="$FX_TMP/notools"
    export XDG_CURRENT_DESKTOP=GNOME
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/modules/gnome-theme/hooks.sh"
    run
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "gsettings missing rc" 1
fx_err "gnome-theme: gsettings not found"

# --- 11. invalid theme name (newline) fails closed ---
echo "--- cell: invalid theme name"
: >"$LOG"
: >"$FX_TMP/keys11"
badname=$(printf 'Bad\ntheme')
rm -rf "$FX_TMP/h_real11"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_real11"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys11"
    export FS_THEME_NAME="$badname"
    unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes gnome-theme
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
if [[ "$FX_BLOCK_RC" == 1 ]]; then fx_ok; else fx_bad "invalid theme name rc1"; fi
fx_err "invalid value for gtk-theme"
[[ ! -s "$LOG" ]] && fx_ok || fx_bad "invalid value never reaches gsettings"

# --- 12. setup list shows gnome-theme, default on ---
echo "--- cell: setup list entry"
printf 'NAME="Fedora Linux"\nID=fedora\nVERSION_ID="44"\nPRETTY_NAME="Fedora Linux 44 (Workstation)"\n' >"$FX_TMP/os-release"
(   set -euo pipefail
    export FS_MODULES_DIR="$ROOT/modules" FS_DISTRO_FILE="$FX_TMP/os-release"
    unset FS_YES FS_PROFILE FS_DISTRO_FAMILY 2>/dev/null || :
    "$SETUP" list gnome-theme
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "setup list rc" 0
fx_out 'gnome-theme.*GNOME theme configuration.*medium.*on'

fx_summary