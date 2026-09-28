#!/usr/bin/env bash
# tests/fixtures/mod_gnome.sh - P6.2 fixture for the `gnome-base` module.
# Drives the REAL repo modules/ + profiles/ through `./setup install`.
# Mock strategy: a PATH-visible fake `gsettings` answers `get` per key from
# a FAKE_KEY_FILE (schema-key|value lines; default @as [], so an unseeded
# get is the empty array -- matching a fresh profile) and logs every
# `get`/`set` to $FAKE_LOG; FS_WALLPAPER_ASSETS_DIR points at a scratch
# asset dir (or an empty one for the skip path); everything lives under
# FX_TMP. Covers: dry-run purity (exact `# would run:` plan, ZERO probes or
# writes, no state dir); non-GNOME desktop skip; gsettings-missing fail-
# closed; real-mode dock favorites MERGE (existing user app preserved,
# curated appended, dedupe); custom keybindings with first-free customN
# allocation (user custom0/custom2 untouched) + array merge preserving
# existing paths; command-signature idempotency (second run writes nothing,
# registered notices); user-has-command collision (skips, never clobbers);
# malformed shortcuts.list fail-closed rc1; wallpaper apply + skip paths.
# Usage: bash tests/fixtures/mod_gnome.sh  (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init
mkdir -p "$FX_TMP/fakebin" "$FX_TMP/notools" "$FX_TMP/wall" "$FX_TMP/wall-empty" "$FX_TMP/mods"
printf 'feedfeed\n' >"$FX_TMP/wall/adwaita.png"

printf 'P6.2 gnome-base module\n'

cat >"$FX_TMP/fakebin/gsettings" <<EOF
#!/usr/bin/env bash
: >>"\$FAKE_LOG" 2>/dev/null || :
case "\$1" in
    get)
        key="\$2/\$3"
        while IFS='' read -r line || [[ -n "\$line" ]]; do
            k="\${line%%|*}"
            [[ "\$k" == "\$key" ]] && { printf '%s\n' "\${line#*|}"; exit 0; }
        done <"\${FAKE_KEY_FILE:-/dev/null}"
        printf '%s\n' "\${FAKE_GET:-@as []}"
        exit 0
        ;;
    set)
        printf 'set %s %s %s\n' "\$2" "\$3" "\$4" >>"\$FAKE_LOG" 2>/dev/null || :
        exit 0
        ;;
    *) exit 0 ;;
esac
EOF
chmod +x "$FX_TMP/fakebin/gsettings"

SETUP="$ROOT/setup"
LOG="$FX_TMP/fake.log"
WP="file://$FX_TMP/wall/adwaita.png"
CK="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings"

gnome_run() {
    local state_dir="$1" label="$2" dry="${3:-0}" key_file="${4:-$FX_TMP/keys}"
    : >"$LOG"
    (   set -euo pipefail
        export FS_HOME="$FX_TMP/$state_dir"
        export PATH="$FX_TMP/fakebin:$PATH"
        export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
        export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
        export XDG_CURRENT_DESKTOP=GNOME
        export FAKE_LOG="$LOG" FAKE_KEY_FILE="$key_file"
        export FS_WALLPAPER_ASSETS_DIR="$FX_TMP/wall"
        if [[ "$dry" == 1 ]]; then export FS_DRY_RUN=1; fi
        unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
        "$SETUP" install --yes gnome-base
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "$label rc" 0
}

# --- 1. dry-run, wallpaper asset present: full plan, zero probes/writes ---
echo "--- cell: dry-run with asset"
: >"$FX_TMP/keys"
rm -rf "$FX_TMP/h_dry"
gnome_run h_dry "dry with asset" 1 "$FX_TMP/keys"
[[ $(grep -c '^# would run:' "$FX_OUT") == 16 ]] && fx_ok || fx_bad "dry plan is 16 lines (want 16, got $(grep -c '^# would run:' "$FX_OUT"))"
fx_out "# would run: gsettings set org.gnome.shell favorite-apps"
fx_out "custom-keybindings/custom3/ binding"
fx_out "custom-keybindings/custom0/"
fx_out "# would run: gsettings set org.gnome.desktop.background picture-uri file://$FX_TMP/wall/adwaita.png"
if [[ -e "$FX_TMP/h_dry/.local/state/fedora-setup" ]]; then fx_bad "dry-run created state dir"; else fx_ok; fi
[[ ! -s "$LOG" ]] && fx_ok || fx_bad "dry-run never probes or writes gsettings"

# --- 2. dry-run, no wallpaper asset: skip wallpaper, 14 plan lines ---
echo "--- cell: dry-run without asset"
grep -v wallpaper "$FX_OUT" >"$FX_TMP/out2" 2>/dev/null || :
rm -rf "$FX_TMP/h_dry2"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_dry2"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys"
    export FS_WALLPAPER_ASSETS_DIR="$FX_TMP/wall-empty"
    export FS_DRY_RUN=1
    unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes gnome-base
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "dry no-asset rc" 0
[[ $(grep -c '^# would run:' "$FX_OUT") == 14 ]] && fx_ok || fx_bad "no-asset dry plan is 14 lines (got $(grep -c '^# would run:' "$FX_OUT"))"
fx_out 'no wallpaper image in'
[[ ! -s "$LOG" ]] && fx_ok || fx_bad "no-asset dry-run never probes or writes"

# --- 3. dry-run, non-GNOME desktop: graceful skip, no plan ---
echo "--- cell: non-GNOME skip"
rm -rf "$FX_TMP/h_dry3"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_dry3"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export XDG_CURRENT_DESKTOP=KDE
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys"
    export FS_WALLPAPER_ASSETS_DIR="$FX_TMP/wall"
    export FS_DRY_RUN=1
    unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes gnome-base
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "non-GNOME skip rc" 0
[[ $(grep -c '^# would run:' "$FX_OUT") == 0 ]] && fx_ok || fx_bad "non-GNOME dry-run renders no plan"
fx_out "no GNOME session"

# --- 4. real mode: favorites merge + first-free + array merge + wallpaper ---
echo "--- cell: real fresh merge"
cat >"$FX_TMP/keys" <<EOD
org.gnome.shell/favorite-apps|['org.gnome.App1.desktop']
org.gnome.settings-daemon.plugins.media-keys/custom-keybindings|['$CK/custom0/', '$CK/custom2/']
org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CK/custom0//command|'user-terminal-launcher'
org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CK/custom2//command|'some-user-app'
EOD
rm -rf "$FX_TMP/h_real"
gnome_run h_real "real fresh" 0 "$FX_TMP/keys"
fx_out '^== run complete ==$'
fx_out '1 ok'
grep -Fqx "set org.gnome.shell favorite-apps ['org.gnome.App1.desktop', 'org.gnome.Nautilus.desktop', 'firefox.desktop']" "$LOG" && fx_ok || fx_bad "dock favorites merged (existing preserved, curated appended)"
grep -Fqx "set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CK/custom1/ name 'Resources'" "$LOG" && fx_ok || fx_bad "resources binding allocated to first-free custom1"
grep -Fqx "set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CK/custom3/ command 'gnome-control-center'" "$LOG" && fx_ok || fx_bad "settings binding allocated to custom3"
grep -Fqx "set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CK/custom5/ binding '<Alt>1'" "$LOG" && fx_ok || fx_bad "mic binding allocated to custom5"
grep -Fqx "set org.gnome.settings-daemon.plugins.media-keys custom-keybindings ['$CK/custom0/', '$CK/custom2/', '$CK/custom1/', '$CK/custom3/', '$CK/custom4/', '$CK/custom5/']" "$LOG" && fx_ok || fx_bad "keybindings array merged preserving user paths"
grep -Fqx "set org.gnome.desktop.background picture-uri $WP" "$LOG" && fx_ok || fx_bad "wallpaper picture-uri applied"
grep -Fqx "set org.gnome.desktop.background picture-uri-dark $WP" "$LOG" && fx_ok || fx_bad "wallpaper picture-uri-dark applied"

# --- 5. real idempotent re-run: already-applied state writes nothing ---
echo "--- cell: real idempotent re-run"
cat >"$FX_TMP/keys" <<EOD
org.gnome.shell/favorite-apps|['org.gnome.App1.desktop', 'org.gnome.Nautilus.desktop', 'firefox.desktop']
org.gnome.desktop.background/picture-uri|$WP
org.gnome.desktop.background/picture-uri-dark|$WP
org.gnome.settings-daemon.plugins.media-keys/custom-keybindings|['$CK/custom0/', '$CK/custom1/', '$CK/custom2/', '$CK/custom3/', '$CK/custom4/', '$CK/custom5/']
org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CK/custom0//command|'user-terminal-launcher'
org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CK/custom1//command|'flatpak run net.nokyan.Resources'
org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CK/custom2//command|'some-user-app'
org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CK/custom3//command|'gnome-control-center'
org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CK/custom4//command|'gnome-terminal'
org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CK/custom5//command|'amixer set Capture toggle'
EOD
rm -rf "$FX_TMP/h_idem"
gnome_run h_idem "real idempotent" 0 "$FX_TMP/keys"
[[ $(grep -c '^set ' "$LOG") == 0 ]] && fx_ok || fx_bad "idempotent re-run writes nothing"
fx_out 'already registered (gnome-terminal)'
fx_out 'already registered (flatpak run net.nokyan.Resources)'

# --- 6. real: user already bound one curated command -> skipped, not clobbered ---
echo "--- cell: user-command collision"
cat >"$FX_TMP/keys" <<EOD
org.gnome.shell/favorite-apps|['org.gnome.App1.desktop']
org.gnome.settings-daemon.plugins.media-keys/custom-keybindings|['$CK/custom0/']
org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CK/custom0//command|'gnome-terminal'
EOD
rm -rf "$FX_TMP/h_coll"
gnome_run h_coll "real collision" 0 "$FX_TMP/keys"
fx_out 'already registered (gnome-terminal)'
grep -c '^set .*custom1/ name' "$LOG" | grep -qx '1' && fx_ok || fx_bad "remaining curated fixed slots allocated first-free"
grep -Fqx "set org.gnome.settings-daemon.plugins.media-keys custom-keybindings ['$CK/custom0/', '$CK/custom1/', '$CK/custom2/', '$CK/custom3/']" "$LOG" && fx_ok || fx_bad "collision merge keeps user path, appends only the new ones"

# --- 7. malformed shortcuts.list fails closed ---
echo "--- cell: malformed shortcuts.list"
: >"$LOG"
rm -rf "$FX_TMP/seam"
mkdir -p "$FX_TMP/seam/lib" "$FX_TMP/seam/modules/gnome-base"
cp "$ROOT/modules/gnome-base/module.sh" "$ROOT/modules/gnome-base/favorites.list" \
    "$ROOT/modules/gnome-base/hooks.sh" "$FX_TMP/seam/modules/gnome-base/"
printf 'nopipes\n' >"$FX_TMP/seam/modules/gnome-base/shortcuts.list"
for f in io.sh run.sh gnome.sh lists.sh; do cp "$ROOT/lib/$f" "$FX_TMP/seam/lib/"; done
rm -rf "$FX_TMP/h_mal"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_mal"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$FX_TMP/seam/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys"
    export FS_WALLPAPER_ASSETS_DIR="$FX_TMP/wall"
    unset FS_YES FS_PROFILE FS_DISTRO_FILE FS_DRY_RUN 2>/dev/null || :
    "$SETUP" install --yes gnome-base
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "malformed list rc" 1
fx_err "malformed shortcuts.list line: nopipes"

# --- 8. gsettings missing on a GNOME desktop fails closed ---
echo "--- cell: gsettings missing"
: >"$LOG"
ln -sf "${DK_DIRNAME:-/usr/bin/dirname}" "$FX_TMP/notools/dirname"
rm -rf "$FX_TMP/h_notools"
(   set -euo pipefail
    export PATH="$FX_TMP/notools"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys"
    export FS_WALLPAPER_ASSETS_DIR="$FX_TMP/wall"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/modules/gnome-base/hooks.sh"
    run
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "gsettings missing rc" 1
fx_err "gnome-base: gsettings not found"

# --- 9. comment-only shortcuts.list: no-op, both modes, no merge render ---
echo "--- cell: empty shortcuts.list"
: >"$LOG"
mkdir -p "$FX_TMP/seam/lib" "$FX_TMP/seam/modules/gnome-base"
cp "$ROOT/modules/gnome-base/module.sh" "$ROOT/modules/gnome-base/favorites.list" \
    "$ROOT/modules/gnome-base/hooks.sh" "$FX_TMP/seam/modules/gnome-base/"
printf '# no shortcuts\n' >"$FX_TMP/seam/modules/gnome-base/shortcuts.list"
for f in io.sh run.sh gnome.sh lists.sh; do cp "$ROOT/lib/$f" "$FX_TMP/seam/lib/"; done
rm -rf "$FX_TMP/h_empty"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_empty"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$FX_TMP/seam/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys"
    export FS_WALLPAPER_ASSETS_DIR="$FX_TMP/wall"
    unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes gnome-base
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "empty shortcuts real rc" 0
grep -q 'custom-keybindings' "$LOG" && fx_bad "empty shortcuts: no keybindings merge" || fx_ok
rm -rf "$FX_TMP/h_empty_dry"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_empty_dry"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$FX_TMP/seam/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys"
    export FS_WALLPAPER_ASSETS_DIR="$FX_TMP/wall"
    export FS_DRY_RUN=1
    unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes gnome-base
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "empty shortcuts dry rc" 0
grep -q 'custom-keybindings' "$FX_OUT" && fx_bad "empty shortcuts dry renders no keybindings merge" || fx_ok

# --- 10. duplicate shortcut command: first-seen wins (list grammar parity) ---
echo "--- cell: duplicate shortcut command"
: >"$LOG"
cp "$ROOT/modules/gnome-base/module.sh" "$ROOT/modules/gnome-base/favorites.list" \
    "$ROOT/modules/gnome-base/hooks.sh" "$FX_TMP/seam/modules/gnome-base/"
cat >"$FX_TMP/seam/modules/gnome-base/shortcuts.list" <<EOD
Settings|gnome-control-center|<Super>I
Settings|gnome-control-center|<Super>I
Terminal|gnome-terminal|<Alt>T
EOD
rm -rf "$FX_TMP/h_dup"
: >"$FX_TMP/keys"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_dup"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$FX_TMP/seam/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys"
    export FS_WALLPAPER_ASSETS_DIR="$FX_TMP/wall"
    export FS_DRY_RUN=1
    unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes gnome-base
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "dup shortcuts dry rc" 0
[[ $(grep -c 'gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:' "$FX_OUT") == 6 ]] && fx_ok || fx_bad "dup shortcuts dry plans 2 bindings (got $(grep -c 'gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:' "$FX_OUT"))"
rm -rf "$FX_TMP/h_dup_r"
: >"$FX_TMP/keys"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_dup_r"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$FX_TMP/seam/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys"
    export FS_WALLPAPER_ASSETS_DIR="$FX_TMP/wall"
    unset FS_YES FS_PROFILE FS_DISTRO_FILE FS_DRY_RUN 2>/dev/null || :
    "$SETUP" install --yes gnome-base
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "dup shortcuts real rc" 0
[[ $(grep -c '^set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:' "$LOG") == 6 ]] && fx_ok || fx_bad "dup shortcuts real registers 2 bindings (got $(grep -c '^set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:' "$LOG"))"
fx_out 'duplicate shortcut command'

# --- 11. wallpaper default dir absent (seam unset): clean skip, no write ---
echo "--- cell: default wallpaper dir absent"
: >"$LOG"
rm -rf "$FX_TMP/h_nodef"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_nodef"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$FX_TMP/seam/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys"
    unset FS_YES FS_PROFILE FS_DISTRO_FILE FS_DRY_RUN FS_WALLPAPER_ASSETS_DIR 2>/dev/null || :
    "$SETUP" install --yes gnome-base
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "default wallpaper dir absent rc" 0
fx_out "no wallpaper asset dir"
grep -q 'picture-uri' "$LOG" && fx_bad "absent default wallpaper dir writes nothing" || fx_ok

# --- 12. directory named *.png and empty *.png are ignored (regular-file gate) ---
echo "--- cell: wallpaper regular-file gate"
: >"$LOG"
rm -rf "$FX_TMP/wallfake"
mkdir -p "$FX_TMP/wallfake/fake.png"
printf 'real\n' >"$FX_TMP/wallfake/real.png"
rm -rf "$FX_TMP/h_wg"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_wg"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$FX_TMP/seam/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys"
    export FS_WALLPAPER_ASSETS_DIR="$FX_TMP/wallfake"
    unset FS_YES FS_PROFILE FS_DISTRO_FILE FS_DRY_RUN 2>/dev/null || :
    "$SETUP" install --yes gnome-base
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "wallpaper regular-file gate rc" 0
grep -Fqx "set org.gnome.desktop.background picture-uri file://$FX_TMP/wallfake/real.png" "$LOG" && fx_ok || fx_bad "dir fake.png skipped, real.png picked for picture-uri"
grep -Fqx "set org.gnome.desktop.background picture-uri-dark file://$FX_TMP/wallfake/real.png" "$LOG" && fx_ok || fx_bad "dir fake.png skipped, real.png picked for picture-uri-dark"

# --- 13. relative FS_WALLPAPER_ASSETS_DIR rejected before any run ---
echo "--- cell: relative wallpaper dir rejected"
: >"$LOG"
(   set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys"
    export FS_WALLPAPER_ASSETS_DIR="relative/wall"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/modules/gnome-base/hooks.sh"
    run
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "relative wallpaper dir rc" 1
fx_err "must be absolute"
[[ ! -s "$LOG" ]] && fx_ok || fx_bad "no gsettings write before the dir rejection"
grep -q 'custom-keybinding\|favorite-apps\|picture-uri' "$FX_OUT" && fx_bad "no plan rendered before the dir rejection" || fx_ok
rm -rf "$FX_TMP/h_reldry"
(   set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys"
    export FS_WALLPAPER_ASSETS_DIR="relative/wall"
    export FS_DRY_RUN=1
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/modules/gnome-base/hooks.sh"
    run
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "relative wallpaper dir dry rc" 1
fx_err "must be absolute"
grep -q '^# would run:' "$FX_OUT" && fx_bad "relative dir in dry mode renders no plan" || fx_ok
[[ ! -s "$LOG" ]] && fx_ok || fx_bad "relative dir in dry mode never probes or writes"

# --- 14. curated command with stray quotes still matches the signature (NB5) ---
echo "--- cell: quoted curated command normalized"
: >"$LOG"
cp "$ROOT/modules/gnome-base/module.sh" "$ROOT/modules/gnome-base/favorites.list" \
    "$ROOT/modules/gnome-base/hooks.sh" "$FX_TMP/seam/modules/gnome-base/"
printf "Terminal|'gnome-terminal'|<Alt>T\n" >"$FX_TMP/seam/modules/gnome-base/shortcuts.list"
cat >"$FX_TMP/keys" <<EOD
org.gnome.settings-daemon.plugins.media-keys/custom-keybindings|['$CK/custom0/']
org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CK/custom0//command|'gnome-terminal'
EOD
rm -rf "$FX_TMP/h_quote"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_quote"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$FX_TMP/seam/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys"
    export FS_WALLPAPER_ASSETS_DIR="$FX_TMP/wall"
    unset FS_YES FS_PROFILE FS_DISTRO_FILE FS_DRY_RUN 2>/dev/null || :
    "$SETUP" install --yes gnome-base
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "quoted curated command rc" 0
fx_out "already registered ('gnome-terminal')"
[[ $(grep -c 'set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:' "$LOG") == 0 ]] && fx_ok || fx_bad "quoted curated command never re-registers over a match"

# --- list surface ---
echo "--- cell: setup list row ---"
printf 'NAME="Fedora Linux"\nID=fedora\nVERSION_ID="41"\nPRETTY_NAME="Fedora Linux 41"\n' >"$FX_TMP/os-release"
(   set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_MODULES_DIR="$ROOT/modules" FS_DISTRO_FILE="$FX_TMP/os-release"
    unset FS_YES FS_PROFILE FS_DISTRO_FAMILY 2>/dev/null || :
    "$SETUP" list gnome-base
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "setup list rc" 0
fx_out "gnome-base"

fx_summary