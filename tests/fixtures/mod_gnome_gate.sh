#!/usr/bin/env bash
# tests/fixtures/mod_gnome_gate.sh - P6.5 fixture for the shared GNOME
# capability gate (lib/gnome.sh gnome_require_capable) and the three modules'
# read-only verify() hooks (gnome-base, gnome-extensions, gnome-theme).
# Drives the REAL repo libs + modules through `./setup install` where it
# matters and calls the hook verify() directly in a subshell elsewhere.
# Mock strategy (same as mod_gnome.sh / mod_gnome_extensions.sh): a PATH-
# visible fake `gsettings` answers `get` from FAKE_KEY_FILE (schema-key|value
# lines; default @as []) and logs every `set` to $FAKE_LOG (never on a read),
# a fake `gnome-extensions` answers `list`/`list --enabled` from FAKE_EXT_LIST
# / FAKE_EXT_ENABLED, a fake `gnome-shell` echoes FAKE_SHELL_VERSION, and a
# `notools` dir with only dirname plays the gsettings-less machine.
# Covers (ROADMAP P6.5 verification): gate classification cells (still the
# machine-report contract -- not-a-GNOME-session, SSH session, no graphical
# session, gsettings not found, FS_GNOME_FORCE=1 override, ubuntu:GNOME and
# display-but-no-desktop capable cases); module-level skip through ./setup
# (headless and SSH both report "skipped (not GNOME)" with zero plan lines
# and zero probes); the adverse-case `--force` path -- CLI flag and env
# seam both override the gate in dry-run and render the normal plan; verify()
# re-gates, refuses to run in dry-run, and on a fully applied state reports
# "verify passed" (rc0), while a missing favorite / disabled-or-missing
# extension / drifted theme value / duplicate bookmark line each fail rc1
# with an io_error and never write anything.
# Usage: bash tests/fixtures/mod_gnome_gate.sh  (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init
mkdir -p "$FX_TMP/fakebin" "$FX_TMP/notools" "$FX_TMP/wall"
printf 'feedfeed\n' >"$FX_TMP/wall/adwaita.png"
ln -sf "${DK_DIRNAME:-/usr/bin/dirname}" "$FX_TMP/notools/dirname"

printf 'P6.5 gnome capability gate + verify hooks\n'

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

cat >"$FX_TMP/fakebin/gnome-shell" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == --version ]]; then
    printf '%s\n' "${FAKE_SHELL_VERSION:-GNOME Shell 50.5}"
fi
exit 0
EOF
chmod +x "$FX_TMP/fakebin/gnome-shell"

cat >"$FX_TMP/fakebin/gnome-extensions" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    list)
        if [[ "$2" == --enabled ]]; then
            cat "${FAKE_EXT_ENABLED:-/dev/null}" 2>/dev/null
        else
            cat "${FAKE_EXT_LIST:-/dev/null}" 2>/dev/null
        fi
        exit 0
        ;;
    *) exit 0 ;;
esac
EOF
chmod +x "$FX_TMP/fakebin/gnome-extensions"

SETUP="$ROOT/setup"
LOG="$FX_TMP/fake.log"
DDASH="dash-to-dock@micxgx.gmail.com"
DUTHEME="user-theme@gnome-shell-extensions.gcampax.github.com"
CK="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings"

# --- 1. gate classification (gnome_require_capable unit cells) ---
echo "--- cell: gate classification"

(   set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export XDG_CURRENT_DESKTOP=KDE
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_require_capable gate-demo
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "gate not-GNOME rc" 1
fx_out "gate-demo: skipped (not GNOME) (not a GNOME session (XDG_CURRENT_DESKTOP='KDE'))"

(   set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    unset XDG_CURRENT_DESKTOP DISPLAY WAYLAND_DISPLAY 2>/dev/null || :
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_require_capable gate-demo
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "gate headless rc" 1
fx_out "gate-demo: skipped (not GNOME) (no graphical session)"

(   set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export XDG_CURRENT_DESKTOP=GNOME
    export SSH_CONNECTION="127.0.0.1 51842 127.0.0.1 22"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_require_capable gate-demo
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "gate ssh rc" 1
fx_out "gate-demo: skipped (not GNOME) (SSH session)"

(   set -euo pipefail
    export PATH="$FX_TMP/notools"
    export XDG_CURRENT_DESKTOP=GNOME
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_require_capable gate-demo
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "gate gsettings-missing rc" 1
fx_out "gate-demo: skipped (not GNOME) (gsettings not found)"

(   set -euo pipefail
    export PATH="$FX_TMP/notools:$PATH"
    export XDG_CURRENT_DESKTOP=KDE
    export FS_GNOME_FORCE=1
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_require_capable gate-demo
    printf 'capable\n'
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "gate force rc" 0
fx_out 'capable'
fx_out_not 'skipped (not GNOME)'

(   set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export XDG_CURRENT_DESKTOP=ubuntu:GNOME
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_require_capable gate-demo
    printf 'capable\n'
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "gate ubuntu-gnome rc" 0
fx_out 'capable'

(   set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    unset XDG_CURRENT_DESKTOP 2>/dev/null || :
    export DISPLAY=:0
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/gnome.sh"
    gnome_require_capable gate-demo
    printf 'capable\n'
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "gate display-no-desktop rc" 0
fx_out 'capable'

# --- 2. headless machine: module skips through ./setup, no plan, no probe ---
echo "--- cell: headless module skip"
: >"$LOG"
rm -rf "$FX_TMP/h_hd"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_hd"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    unset XDG_CURRENT_DESKTOP DISPLAY WAYLAND_DISPLAY 2>/dev/null || :
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys"
    export FS_WALLPAPER_ASSETS_DIR="$FX_TMP/wall"
    export FS_DRY_RUN=1
    unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes gnome-base
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "headless module rc" 0
fx_out "gnome-base: skipped (not GNOME) (no graphical session)"
[[ $(grep -c '^# would run:' "$FX_OUT") == 0 ]] && fx_ok || fx_bad "headless skip renders no plan"
[[ ! -s "$LOG" ]] && fx_ok || fx_bad "headless skip never probes or writes"

# --- 3. SSH session: gnome-theme skips through ./setup ---
echo "--- cell: ssh module skip"
: >"$LOG"
rm -rf "$FX_TMP/h_ssh"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_ssh"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export XDG_CURRENT_DESKTOP=GNOME
    export SSH_CONNECTION="127.0.0.1 51842 127.0.0.1 22"
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys"
    export FS_THEME_NAME=Aurora FS_CURSOR_NAME=DMZ-Black
    export FS_GTK_BOOKMARKS_FILE="$FX_TMP/bm"
    export FS_DRY_RUN=1
    unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes gnome-theme
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "ssh module rc" 0
fx_out "gnome-theme: skipped (not GNOME) (SSH session)"
[[ $(grep -c '^# would run:' "$FX_OUT") == 0 ]] && fx_ok || fx_bad "ssh skip renders no plan"
[[ ! -s "$LOG" ]] && fx_ok || fx_bad "ssh skip never probes or writes"

# --- 4. adverse case --force via the CLI flag: gate bypassed, normal plan ---
echo "--- cell: --force flag bypasses the gate (dry)"
: >"$LOG"
rm -rf "$FX_TMP/h_frc"
: >"$FX_TMP/keys"
printf 'file:///home/u/Github\n' >"$FX_TMP/bm"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_frc"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export XDG_CURRENT_DESKTOP=KDE
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys"
    export FS_WALLPAPER_ASSETS_DIR="$FX_TMP/wall"
    export FS_DRY_RUN=1
    unset FS_YES FS_PROFILE FS_DISTRO_FILE FS_GNOME_FORCE 2>/dev/null || :
    "$SETUP" install --yes --force gnome-base
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "force flag rc" 0
fx_out_not "skipped (not GNOME)"
[[ $(grep -c '^# would run:' "$FX_OUT") -ge 1 ]] && fx_ok || fx_bad "forced dry-run renders the normal plan"
[[ ! -s "$LOG" ]] && fx_ok || fx_bad "forced dry-run never probes or writes"

# --- 5. adverse case FS_GNOME_FORCE=1 env seam: same override ---
echo "--- cell: FS_GNOME_FORCE env seam bypasses the gate (dry)"
: >"$LOG"
rm -rf "$FX_TMP/h_frce"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_frce"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export XDG_CURRENT_DESKTOP=KDE
    export FS_GNOME_FORCE=1
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys"
    export FS_THEME_NAME=Aurora FS_CURSOR_NAME=DMZ-Black
    export FS_GTK_BOOKMARKS_FILE="$FX_TMP/no-bm/bm"
    export FS_DRY_RUN=1
    unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes gnome-theme
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "force env rc" 0
fx_out_not "skipped (not GNOME)"
[[ $(grep -c '^# would run:' "$FX_OUT") == 2 ]] && fx_ok || fx_bad "forced gtk+cursor dry plan is 2 lines (got $(grep -c '^# would run:' "$FX_OUT"))"
[[ ! -s "$LOG" ]] && fx_ok || fx_bad "forced env dry-run never probes or writes"

# --- 6. verify() re-gates and refuses dry-run ---
echo "--- cell: verify gated (non-GNOME) and dry-run refuse"
(   set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export XDG_CURRENT_DESKTOP=KDE
    export FS_DRY_RUN=0
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/modules/gnome-base/hooks.sh"
    verify
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "verify gated rc" 0
fx_out "gnome-base: skipped (not GNOME) (not a GNOME session"

: >"$LOG"
(   set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys"
    export FS_WALLPAPER_ASSETS_DIR="$FX_TMP/wall"
    export FS_DRY_RUN=1
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/modules/gnome-base/hooks.sh"
    verify
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "verify dry rc" 0
fx_out "verify is read-only; runs only in real mode"
[[ ! -s "$LOG" ]] && fx_ok || fx_bad "verify dry-run never probes"

# --- 7. gnome-base verify passes on fully applied state ---
echo "--- cell: gnome-base verify pass"
: >"$LOG"
cat >"$FX_TMP/keys" <<EOD
org.gnome.shell/favorite-apps|['org.gnome.Nautilus.desktop', 'firefox.desktop']
org.gnome.desktop.background/picture-uri|file://$FX_TMP/wall/adwaita.png
org.gnome.desktop.background/picture-uri-dark|file://$FX_TMP/wall/adwaita.png
org.gnome.settings-daemon.plugins.media-keys/custom-keybindings|['$CK/custom0/', '$CK/custom1/', '$CK/custom2/', '$CK/custom3/']
org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CK/custom0//command|'flatpak run net.nokyan.Resources'
org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CK/custom1//command|'gnome-control-center'
org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CK/custom2//command|'gnome-terminal'
org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CK/custom3//command|'amixer set Capture toggle'
EOD
(   set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys"
    export FS_WALLPAPER_ASSETS_DIR="$FX_TMP/wall"
    export FS_DRY_RUN=0
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/modules/gnome-base/hooks.sh"
    verify
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "gnome-base verify pass rc" 0
fx_out "gnome-base: verify ok: dock favorite present: firefox.desktop"
fx_out "gnome-base: verify ok: shortcut registered: gnome-control-center"
fx_out "gnome-base: verify ok: wallpaper picture-uri set"
fx_out "gnome-base: verify passed"
[[ ! -s "$LOG" ]] && fx_ok || fx_bad "verify must never write gsettings"

# --- 7b. gnome-base verify passes when the stored URI is single-quoted (the
# real `gsettings get` rendering for string scalars) ---
echo "--- cell: gnome-base verify pass quoted-URI (real get rendering)"
: >"$LOG"
cat >"$FX_TMP/keys_q" <<EOD
org.gnome.shell/favorite-apps|['org.gnome.Nautilus.desktop', 'firefox.desktop']
org.gnome.desktop.background/picture-uri|'file://$FX_TMP/wall/adwaita.png'
org.gnome.desktop.background/picture-uri-dark|'file://$FX_TMP/wall/adwaita.png'
org.gnome.settings-daemon.plugins.media-keys/custom-keybindings|['$CK/custom0/', '$CK/custom1/', '$CK/custom2/', '$CK/custom3/']
org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CK/custom0//command|'flatpak run net.nokyan.Resources'
org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CK/custom1//command|'gnome-control-center'
org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CK/custom2//command|'gnome-terminal'
org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CK/custom3//command|'amixer set Capture toggle'
EOD
(   set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys_q"
    export FS_WALLPAPER_ASSETS_DIR="$FX_TMP/wall"
    export FS_DRY_RUN=0
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/modules/gnome-base/hooks.sh"
    verify
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "gnome-base verify pass quoted-URI rc" 0
fx_out "gnome-base: verify ok: wallpaper picture-uri set"
fx_out "gnome-base: verify ok: wallpaper picture-uri-dark set"
fx_out "gnome-base: verify passed"
[[ ! -s "$LOG" ]] && fx_ok || fx_bad "verify quoted-URI must never write gsettings"

# --- 8. gnome-base verify fails on a fresh (unapplied) state, rc1, no writes ---
echo "--- cell: gnome-base verify fail"
: >"$LOG"
: >"$FX_TMP/keys_fresh"
(   set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys_fresh"
    export FS_WALLPAPER_ASSETS_DIR="$FX_TMP/wall"
    export FS_DRY_RUN=0
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/modules/gnome-base/hooks.sh"
    verify
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "gnome-base verify fail rc" 1
fx_err "verify FAILED: dock favorite not applied: org.gnome.Nautilus.desktop"
fx_err "verify FAILED: shortcut not applied:"
fx_err "verify FAILED: wallpaper picture-uri"
[[ ! -s "$LOG" ]] && fx_ok || fx_bad "failing verify must never write gsettings"

# --- 9. gnome-extensions verify: installed+enabled pass, missing pieces fail ---
echo "--- cell: gnome-extensions verify pass"
printf '%s\n%s\n' "$DDASH" "$DUTHEME" >"$FX_TMP/ext_list"
cp "$FX_TMP/ext_list" "$FX_TMP/ext_enabled"
(   set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_EXT_LIST="$FX_TMP/ext_list" FAKE_EXT_ENABLED="$FX_TMP/ext_enabled"
    export FS_DRY_RUN=0
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/modules/gnome-extensions/hooks.sh"
    verify
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "ext verify pass rc" 0
fx_out "verify ok: extension installed+enabled: $DDASH"
fx_out "gnome-extensions: verify passed"

echo "--- cell: gnome-extensions verify fail (disabled)"
printf '%s\n' "$DDASH" >"$FX_TMP/ext_enabled"
(   set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_EXT_LIST="$FX_TMP/ext_list" FAKE_EXT_ENABLED="$FX_TMP/ext_enabled"
    export FS_DRY_RUN=0
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/modules/gnome-extensions/hooks.sh"
    verify
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "ext verify disabled rc" 1
fx_err "verify FAILED: extension not enabled: $DUTHEME"

echo "--- cell: gnome-extensions verify fail (not installed)"
printf '%s\n' "$DDASH" >"$FX_TMP/ext_list"
(   set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_EXT_LIST="$FX_TMP/ext_list" FAKE_EXT_ENABLED="$FX_TMP/ext_enabled"
    export FS_DRY_RUN=0
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/modules/gnome-extensions/hooks.sh"
    verify
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "ext verify not-installed rc" 1
fx_err "verify FAILED: extension not installed: $DUTHEME"

# --- 10. gnome-theme verify: applied values pass, drift fails, dupes fail ---
echo "--- cell: gnome-theme verify pass"
printf 'file:///home/u/Github\nfile:///home/u/Documents\n' >"$FX_TMP/bm_deduped"
: >"$LOG"
cat >"$FX_TMP/keys_theme" <<'EOD'
org.gnome.desktop.interface/gtk-theme|'Aurora'
org.gnome.desktop.interface/cursor-theme|'DMZ-Black'
EOD
(   set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys_theme"
    export FS_THEME_NAME=Aurora FS_CURSOR_NAME=DMZ-Black
    export FS_GTK_BOOKMARKS_FILE="$FX_TMP/bm_deduped"
    export FS_DRY_RUN=0
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/modules/gnome-theme/hooks.sh"
    verify
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "theme verify pass rc" 0
fx_out "gnome-theme: verify ok: gtk-theme = Aurora"
fx_out "gnome-theme: verify ok: cursor-theme = DMZ-Black"
fx_out "gnome-theme: verify ok: bookmarks deduplicated"
fx_out "gnome-theme: verify passed"
[[ ! -s "$LOG" ]] && fx_ok || fx_bad "theme verify must never write gsettings"

echo "--- cell: gnome-theme verify fail (drifted value)"
: >"$LOG"
printf '%s\n' "org.gnome.desktop.interface/gtk-theme|'Yaru'" \
    "org.gnome.desktop.interface/cursor-theme|'DMZ-Black'" >"$FX_TMP/keys_drift"
(   set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys_drift"
    export FS_THEME_NAME=Aurora FS_CURSOR_NAME=DMZ-Black
    export FS_GTK_BOOKMARKS_FILE="$FX_TMP/bm_deduped"
    export FS_DRY_RUN=0
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/modules/gnome-theme/hooks.sh"
    verify
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "theme verify drift rc" 1
fx_err "verify FAILED: gtk-theme is 'Yaru', expected 'Aurora'"

echo "--- cell: gnome-theme verify fail (bookmark dupes)"
printf 'file:///home/u/Github\nfile:///home/u/Github\n' >"$FX_TMP/bm_dup"
(   set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys_theme"
    export FS_THEME_NAME=Aurora FS_CURSOR_NAME=DMZ-Black
    export FS_GTK_BOOKMARKS_FILE="$FX_TMP/bm_dup"
    export FS_DRY_RUN=0
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/modules/gnome-theme/hooks.sh"
    verify
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "theme verify dup rc" 1
fx_err "verify FAILED: bookmarks hold 1 duplicate line(s)"
[[ ! -s "$LOG" ]] && fx_ok || fx_bad "failing theme verify must never write gsettings"

# --- 11. --force makes a drifty module run again; verify stays readonly ---
echo "--- cell: help lists --force"
(   set -euo pipefail
    unset FS_YES FS_PROFILE FS_DISTRO_FILE FS_GNOME_FORCE 2>/dev/null || :
    "$SETUP" --help
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "help rc" 0
fx_out --force

fx_summary