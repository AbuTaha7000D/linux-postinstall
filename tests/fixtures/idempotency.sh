#!/usr/bin/env bash
# tests/fixtures/idempotency.sh - P6.6 sequential-run idempotency sweep.
# Drives the REAL repo modules/ through `./setup install --yes <id>` (explicit
# CLI id, NO profile wiring, mock pkg backend) against a persistent fake
# gsettings state (FAKE_KEY_FILE) and fake gnome-extensions enabled-state
# (FAKE_EXT_ENABLED), each sequential run using a FRESH scratch FS_HOME so the
# hooks execute every time (runner state is not what we measure -- the hooks'
# own compare-before-write is). The P6.6 contract is "second full run produces
# zero changes; gsettings/file diffs empty between run 2 and run 3":
#   * gnome-base: run 1 merges dock favorites exactly once + allocates the
#     four curated shortcuts + sets both wallpaper URIs; run 2 and run 3
#     against the post-run-1 state write NOTHING and leave the gsettings state
#     byte-identical (diff empty between R2 and R3).
#   * gnome-theme: run 1 dedupes the GTK bookmarks file once (theme compare
#     no-ops); run 2 and run 3 leave the file byte-identical.
#   * gnome-extensions: run 1 enables the curated installed uuids once; run 2
#     and run 3 issue no enable commands and leave the enabled-state file
#     byte-identical.
#   * shared-FS_HOME re-run: the runner-level "already completed" skip is the
#     whole-run no-op gate (P6.6 sweep documents it; P6.5 NB2 behavioral note).
# The fake gsettings models REAL gsettings faithfully: `set` PERSISTS the new
# value into FAKE_KEY_FILE (in-place overwrite, so re-reads reflect applied
# state exactly like dconf) and `get` returns string scalars single-quoted
# ('file:///x'), arrays/@as verbatim -- the quoting that makes a bare target
# equal to a quoted read. A FAKE peer with the naive verbatim model still
# lives in tests/fixtures/mod_gnome.sh (its own cells answer verbatim); this
# fixture is the faithful round-trip model. Known simplifications: fake `get`
# always exits 0 (real gsettings errors on an unknown key -- the fail-closed
# pre-write-read path is exercised by tests/fixtures/gnome.sh instead),
# and bare boolean/integer scalar values are NOT quoted (only string-like
# values are), so a future boolean/int write cannot false-pass a no-op.
# Usage: bash tests/fixtures/idempotency.sh  (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init
mkdir -p "$FX_TMP/fakebin" "$FX_TMP/wall" "$FX_TMP/modconf"
printf 'feedfeed\n' >"$FX_TMP/wall/adwaita.png"

printf 'P6.6 idempotency sweep\n'

SETUP="$ROOT/setup"
CK="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings"
WP="file://$FX_TMP/wall/adwaita.png"
LOG="$FX_TMP/idem.log"

cat >"$FX_TMP/fakebin/gsettings" <<EOF
#!/usr/bin/env bash
: >>"\$FAKE_LOG" 2>/dev/null || :
case "\$1" in
    get)
        key="\$2/\$3"
        v=""
        while IFS='' read -r line || [[ -n "\$line" ]]; do
            k="\${line%%|*}"
            if [[ "\$k" == "\$key" ]]; then
                v="\${line#*|}"
                break
            fi
        done <"\${FAKE_KEY_FILE:-/dev/null}"
        if [[ -z "\$v" ]]; then
            printf '%s\n' "\${FAKE_GET:-@as []}"
        else
            case "\$v" in
                "'"*|"["*|"@as"*|"[]"|true|false|[0-9]*|@*) ;;
                *) v="'\$v'" ;;
            esac
            printf '%s\n' "\$v"
        fi
        exit 0
        ;;
    set)
        printf 'set %s %s %s\n' "\$2" "\$3" "\$4" >>"\$FAKE_LOG" 2>/dev/null || :
        if [[ -f "\${FAKE_KEY_FILE:-}" ]]; then
            k="\$2/\$3"
            v="\$4"
            tmp="\${FAKE_KEY_FILE}.set.\$\$"
            : >"\$tmp"
            replaced=0
            while IFS='' read -r line || [[ -n "\$line" ]]; do
                kk="\${line%%|*}"
                if [[ "\$kk" == "\$k" ]]; then
                    if (( replaced == 0 )); then
                        printf '%s|%s\n' "\$k" "\$v" >>"\$tmp"
                        replaced=1
                    fi
                else
                    printf '%s\n' "\$line" >>"\$tmp"
                fi
            done <"\${FAKE_KEY_FILE}"
            if (( replaced == 0 )); then
                printf '%s|%s\n' "\$k" "\$v" >>"\$tmp"
            fi
            mv -f -- "\$tmp" "\${FAKE_KEY_FILE}"
        fi
        exit 0
        ;;
    *) exit 0 ;;
esac
EOF
chmod +x "$FX_TMP/fakebin/gsettings"

cat >"$FX_TMP/fakebin/gnome-shell" <<EOF
#!/usr/bin/env bash
case "\$1" in
    --version) printf 'GNOME Shell 50.1\n'; exit 0 ;;
esac
exit 0
EOF
chmod +x "$FX_TMP/fakebin/gnome-shell"

cat >"$FX_TMP/fakebin/gnome-extensions" <<EOF
#!/usr/bin/env bash
printf 'vex %s\n' "\$1" >>"\$FAKE_EXT_LOG" 2>/dev/null || :
if [[ "\${1:-}" == list ]]; then
    if [[ "\${2:-}" == --enabled ]]; then
        cat "\${FAKE_EXT_ENABLED:-/dev/null}" 2>/dev/null || :
    else
        cat "\${FAKE_EXT_LIST:-/dev/null}" 2>/dev/null || :
    fi
    exit 0
fi
if [[ "\${1:-}" == enable ]]; then
    printf 'enable %s\n' "\${2:-}" >>"\$FAKE_EXT_LOG" 2>/dev/null || :
    grep -Fxq "\${2:-}" "\${FAKE_EXT_ENABLED:-/dev/null}" 2>/dev/null || printf '%s\n' "\${2:-}" >>"\${FAKE_EXT_ENABLED:-/dev/null}"
    exit 0
fi
exit 0
EOF
chmod +x "$FX_TMP/fakebin/gnome-extensions"

idem_run() {
    local state="$1" label="$2" module="$3" key_file="${4:-}"
    : >"$LOG"
    (   set -euo pipefail
        export FS_HOME="$FX_TMP/$state"
        export PATH="$FX_TMP/fakebin:$PATH"
        export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
        export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
        export XDG_CURRENT_DESKTOP=GNOME
        export FS_WALLPAPER_ASSETS_DIR="$FX_TMP/wall"
        export FAKE_LOG="$LOG" FAKE_KEY_FILE="$key_file"
        export FAKE_EXT_LOG="$LOG" FAKE_EXT_LIST="$FX_TMP/ext.list" FAKE_EXT_ENABLED="$FX_TMP/ext.enabled"
        unset FS_YES FS_PROFILE FS_DISTRO_FILE FS_DRY_RUN FS_THEME_NAME FS_CURSOR_NAME \
            FS_THEME_SRC FS_CURSOR_SRC FS_THEME_ASSETS_DIR FS_CURSOR_ASSETS_DIR \
            FS_GTK_BOOKMARKS_FILE 2>/dev/null || :
        "$SETUP" install --yes "$module"
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "$label rc" 0
}

# --- 1. gnome-base: R1 merges once, R2==R3 zero-change ---
echo "--- cell: gnome-base sequential-run sweep"
cat >"$FX_TMP/keys" <<EOD
org.gnome.shell/favorite-apps|['org.gnome.App1.desktop']
org.gnome.settings-daemon.plugins.media-keys/custom-keybindings|@as []
EOD
idem_run s_base1 "gnome-base run1" gnome-base "$FX_TMP/keys"
fx_out '^== run complete ==$'
fx_out '^  - 1 modules ok · 0 skipped · 0 failed ·'
grep -Fqx "set org.gnome.shell favorite-apps ['org.gnome.App1.desktop', 'org.gnome.Nautilus.desktop', 'firefox.desktop']" "$LOG" && fx_ok || fx_bad "R1: dock favorites merged exactly once"
grep -c '^set .*custom[0-9]/ command ' "$LOG" | grep -qx '4' && fx_ok || fx_bad "R1: four curated shortcuts registered (no dup)"
grep -c 'firefox.desktop' "$LOG" | grep -qx '1' && fx_ok || fx_bad "R1: no duplicate dock entries"
grep -Fqx "set org.gnome.desktop.background picture-uri $WP" "$LOG" && fx_ok || fx_bad "R1: wallpaper picture-uri applied"
grep -Fqx "set org.gnome.desktop.background picture-uri-dark $WP" "$LOG" && fx_ok || fx_bad "R1: wallpaper picture-uri-dark applied"
cp "$FX_TMP/keys" "$FX_TMP/keys-r1"
grep -Fq "org.gnome.shell/favorite-apps|['org.gnome.App1.desktop', 'org.gnome.Nautilus.desktop', 'firefox.desktop']" "$FX_TMP/keys-r1" && fx_ok || fx_bad "R1: merged favorites persisted into state"
grep -Fq "org.gnome.desktop.background/picture-uri|$WP" "$FX_TMP/keys-r1" && fx_ok || fx_bad "R1: wallpaper persisted into state"
cp "$FX_TMP/keys-r1" "$FX_TMP/keys-before-r2"
idem_run s_base2 "gnome-base run2" gnome-base "$FX_TMP/keys-r1"
[[ $(grep -c '^set ' "$LOG") == 0 ]] && fx_ok || fx_bad "R2: zero writes on applied state"
diff -u "$FX_TMP/keys-before-r2" "$FX_TMP/keys-r1" >/dev/null && fx_ok || fx_bad "R2: gsettings state diff empty vs pre-run"
cp "$FX_TMP/keys-r1" "$FX_TMP/keys-before-r3"
idem_run s_base3 "gnome-base run3" gnome-base "$FX_TMP/keys-r1"
[[ $(grep -c '^set ' "$LOG") == 0 ]] && fx_ok || fx_bad "R3: zero writes on applied state"
diff -u "$FX_TMP/keys-before-r3" "$FX_TMP/keys-r1" >/dev/null && fx_ok || fx_bad "R3: gsettings state diff empty vs pre-run"
sort "$FX_TMP/keys-before-r2" | md5sum >"$FX_TMP/s2.md5"
sort "$FX_TMP/keys-before-r3" | md5sum >"$FX_TMP/s3.md5"
diff -u "$FX_TMP/s2.md5" "$FX_TMP/s3.md5" >/dev/null && fx_ok || fx_bad "R2==R3: gsettings-state diff empty"

# --- 2. gnome-theme: R1 dedupes once, R2==R3 zero-change ---
echo "--- cell: gnome-theme sequential-run sweep"
printf 'file:///home/u/Documents\nfile:///home/u/Music\nfile:///home/u/Documents\nfile:///home/u/Pictures\nfile:///home/u/Downloads\n' >"$FX_TMP/bm"
cat >"$FX_TMP/keys-theme" <<EOD
org.gnome.desktop.interface/gtk-theme|'Aurora'
org.gnome.desktop.interface/cursor-theme|'Yaru'
EOD
: >"$LOG"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/s_theme1"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys-theme"
    export FS_GTK_BOOKMARKS_FILE="$FX_TMP/bm"
    export FS_THEME_NAME=Aurora FS_CURSOR_NAME=Yaru
    unset FS_YES FS_PROFILE FS_DISTRO_FILE FS_DRY_RUN 2>/dev/null || :
    "$SETUP" install --yes gnome-theme
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "gnome-theme run1 rc" 0
tee "$FX_TMP/bm-r1" <"$FX_TMP/bm" >/dev/null
fx_out 'bookmarks deduplicated (1 duplicate line(s) removed)'
[[ $(grep -c '^set ' "$LOG") == 0 ]] && fx_ok || fx_bad "T-R1: theme compare no-op (zero writes)"
printf 'file:///home/u/Documents\nfile:///home/u/Music\nfile:///home/u/Pictures\nfile:///home/u/Downloads\n' >"$FX_TMP/bm-expected"
diff -u "$FX_TMP/bm-expected" "$FX_TMP/bm" >/dev/null && fx_ok || fx_bad "T-R1: bookmarks deduped first-seen"
: >"$LOG"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/s_theme2"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys-theme"
    export FS_GTK_BOOKMARKS_FILE="$FX_TMP/bm"
    export FS_THEME_NAME=Aurora FS_CURSOR_NAME=Yaru
    unset FS_YES FS_PROFILE FS_DISTRO_FILE FS_DRY_RUN 2>/dev/null || :
    "$SETUP" install --yes gnome-theme
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "gnome-theme run2 rc" 0
tee "$FX_TMP/bm-r2" <"$FX_TMP/bm" >/dev/null
[[ $(grep -c '^set ' "$LOG") == 0 ]] && fx_ok || fx_bad "T-R2: zero writes"
diff -u "$FX_TMP/bm-r1" "$FX_TMP/bm-r2" >/dev/null && fx_ok || fx_bad "T-R2: bookmarks byte-identical VS R1"
: >"$LOG"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/s_theme3"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys-theme"
    export FS_GTK_BOOKMARKS_FILE="$FX_TMP/bm"
    export FS_THEME_NAME=Aurora FS_CURSOR_NAME=Yaru
    unset FS_YES FS_PROFILE FS_DISTRO_FILE FS_DRY_RUN 2>/dev/null || :
    "$SETUP" install --yes gnome-theme
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "gnome-theme run3 rc" 0
tee "$FX_TMP/bm-r3" <"$FX_TMP/bm" >/dev/null
[[ $(grep -c '^set ' "$LOG") == 0 ]] && fx_ok || fx_bad "T-R3: zero writes"
diff -u "$FX_TMP/bm-r2" "$FX_TMP/bm-r3" >/dev/null && fx_ok || fx_bad "T-R2==R3: bookmarks diff empty"

# --- 3. gnome-extensions: R1 enables once, R2==R3 zero-change ---
echo "--- cell: gnome-extensions sequential-run sweep"
printf 'dash-to-dock@micxgx.gmail.com\nuser-theme@gnome-shell-extensions.gcampax.github.com\n' >"$FX_TMP/ext.list"
: >"$FX_TMP/ext.enabled"
cp "$FX_TMP/ext.enabled" "$FX_TMP/ext.enabled-before"
idem_ext() {
    local state="$1" label="$2"
    : >"$LOG"
    (   set -euo pipefail
        export FS_HOME="$FX_TMP/$state"
        export PATH="$FX_TMP/fakebin:$PATH"
        export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
        export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
        export XDG_CURRENT_DESKTOP=GNOME
        export FAKE_LOG="$LOG" FAKE_EXT_LOG="$LOG" FAKE_EXT_LIST="$FX_TMP/ext.list" FAKE_EXT_ENABLED="$FX_TMP/ext.enabled"
        unset FS_YES FS_PROFILE FS_DISTRO_FILE FS_DRY_RUN FS_GNOME_BROWSE 2>/dev/null || :
        "$SETUP" install --yes gnome-extensions
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "$label rc" 0
}
idem_ext s_ext1 "gnome-extensions run1"
fx_out '^== run complete ==$'
fx_out '^  - 1 modules ok · 0 skipped · 0 failed ·'
grep -Fqx 'enable dash-to-dock@micxgx.gmail.com' "$LOG" && fx_ok || fx_bad "E-R1: dash-to-dock enabled first"
grep -Fqx 'enable user-theme@gnome-shell-extensions.gcampax.github.com' "$LOG" && fx_ok || fx_bad "E-R1: user-theme enabled once"
printf 'dash-to-dock@micxgx.gmail.com\nuser-theme@gnome-shell-extensions.gcampax.github.com\n' >"$FX_TMP/ext.enabled-expected"
diff -u "$FX_TMP/ext.enabled-expected" "$FX_TMP/ext.enabled" >/dev/null && fx_ok || fx_bad "E-R1: enabled state persisted exactly once"
idem_ext s_ext2 "gnome-extensions run2"
cp "$FX_TMP/ext.enabled" "$FX_TMP/ext.enabled-r2"
[[ $(grep -c '^enable ' "$LOG") == 0 ]] && fx_ok || fx_bad "E-R2: zero enable commands"
idem_ext s_ext3 "gnome-extensions run3"
cp "$FX_TMP/ext.enabled" "$FX_TMP/ext.enabled-r3"
[[ $(grep -c '^enable ' "$LOG") == 0 ]] && fx_ok || fx_bad "E-R3: zero enable commands"
diff -u "$FX_TMP/ext.enabled-r2" "$FX_TMP/ext.enabled-r3" >/dev/null && fx_ok || fx_bad "E-R2==R3: enabled-state diff empty"

# --- 4. shared FS_HOME re-run is skipped at runner level (whole-run no-op) ---
echo "--- cell: shared-state re-run skipped"
cat >"$FX_TMP/keys-shared" <<EOD
org.gnome.shell/favorite-apps|['org.gnome.App1.desktop']
org.gnome.settings-daemon.plugins.media-keys/custom-keybindings|@as []
EOD
: >"$LOG"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/s_shared"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export XDG_CURRENT_DESKTOP=GNOME
    export FS_WALLPAPER_ASSETS_DIR="$FX_TMP/wall"
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys-shared"
    unset FS_YES FS_PROFILE FS_DISTRO_FILE FS_DRY_RUN 2>/dev/null || :
    "$SETUP" install --yes gnome-base
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "shared run1 rc" 0
: >"$LOG"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/s_shared"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export XDG_CURRENT_DESKTOP=GNOME
    export FS_WALLPAPER_ASSETS_DIR="$FX_TMP/wall"
    export FAKE_LOG="$LOG" FAKE_KEY_FILE="$FX_TMP/keys-shared"
    unset FS_YES FS_PROFILE FS_DISTRO_FILE FS_DRY_RUN 2>/dev/null || :
    "$SETUP" install --yes gnome-base
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "shared run2 rc" 0
fx_out 'already completed: gnome-base'
fx_out '^  - 0 modules ok · 1 skipped · 0 failed ·'
[[ $(grep -c '^set ' "$LOG") == 0 ]] && fx_ok || fx_bad "shared re-run: zero writes"

fx_summary