#!/usr/bin/env bash
# tests/fixtures/mod_gnome_extensions.sh - P6.3 fixture for the
# `gnome-extensions` module.
# Drives the REAL repo modules/ + profiles/ through `./setup install`.
# Mock strategy: a PATH-visible fake `gnome-shell --version` (echoes
# $FAKE_SHELL_VERSION, logs the probe to $FAKE_LOG), a fake
# `gnome-extensions` that answers `list`/`list --enabled` from
# $FAKE_EXT_LIST / $FAKE_EXT_ENABLED and logs `enable <uuid>` (and appends
# the uuid to the enabled file, modeling real state evolution) to $FAKE_LOG,
# and a fake `xdg-open` that logs its invocation. Everything lives under
# FX_TMP. Covers: dry-run purity (exact `# would run:` plan: one mock
# install batch + two enable lines ++ at most two xdg-open lines under
# --browse; ZERO probes); family package routing (rpm ships both packages,
# deb and arch ship only the shared gnome-shell-extensions bundle); browse
# hard limit (a 3-URL browse.list opens exactly 2) and malformed-URL fail-
# closed; non-GNOME desktop skip; gnome-extensions-missing fail-closed;
# real-mode fresh install (both curated uuids enabled, exact enable cmds in
# $FAKE_LOG), partial install (not-installed uuid reported + skipped),
# idempotent re-run (installed AND enabled => zero enable cmds);
# incompatible-version warnings at shell 51 while still enabling (ROADMAP
# P6.3 verification: incompatible-extension message shown); compat-map seam
# override + missing-file + corrupt-row + unknown-version graceful paths;
# corrupt extensions.list uuid fail-closed (dry and real);
# `setup list` rows.
# Usage: bash tests/fixtures/mod_gnome_extensions.sh  (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init
mkdir -p "$FX_TMP/fakebin" "$FX_TMP/notools" "$FX_TMP/seam/modules/gnome-extensions" "$FX_TMP/seam/lib"

DDASH="dash-to-dock@micxgx.gmail.com"
DUTHEME="user-theme@gnome-shell-extensions.gcampax.github.com"
DEXTRA="openbar@neuromorph"
URL_DDASH="https://extensions.gnome.org/extension/307/dash-to-dock/"
URL_UTHEME="https://extensions.gnome.org/extension/19/user-themes/"

cat >"$FX_TMP/fakebin/gnome-shell" <<'EOF'
#!/usr/bin/env bash
: >>"${FAKE_LOG:-/dev/null}" 2>/dev/null || :
if [[ "$1" == --version ]]; then
    printf 'version\n' >>"${FAKE_LOG:-/dev/null}" 2>/dev/null || :
    printf '%s\n' "${FAKE_SHELL_VERSION:-GNOME Shell 50.5}"
fi
exit 0
EOF
chmod +x "$FX_TMP/fakebin/gnome-shell"

cat >"$FX_TMP/fakebin/gnome-extensions" <<'EOF'
#!/usr/bin/env bash
: >>"${FAKE_LOG:-/dev/null}" 2>/dev/null || :
case "$1" in
    list)
        printf 'list %s\n' "${2:-}" >>"${FAKE_LOG:-/dev/null}" 2>/dev/null || :
        if [[ "$2" == --enabled ]]; then
            cat "${FAKE_EXT_ENABLED:-/dev/null}" 2>/dev/null
        else
            cat "${FAKE_EXT_LIST:-/dev/null}" 2>/dev/null
        fi
        exit 0
        ;;
    enable)
        printf 'enable %s\n' "$2" >>"${FAKE_LOG:-/dev/null}" 2>/dev/null || :
        printf '%s\n' "$2" >>"${FAKE_EXT_ENABLED:-/dev/null}" 2>/dev/null || :
        exit 0
        ;;
    *) exit 0 ;;
esac
EOF
chmod +x "$FX_TMP/fakebin/gnome-extensions"

cat >"$FX_TMP/fakebin/xdg-open" <<'EOF'
#!/usr/bin/env bash
printf 'xdg-open %s\n' "$*" >>"${FAKE_LOG:-/dev/null}" 2>/dev/null || :
exit 0
EOF
chmod +x "$FX_TMP/fakebin/xdg-open"

SETUP="$ROOT/setup"
LOG="$FX_TMP/fake.log"

seam_lib() {
    for f in io.sh run.sh gnome.sh lists.sh; do
        cp "$ROOT/lib/$f" "$FX_TMP/seam/lib/"
    done
    mkdir -p "$FX_TMP/seam/modules/gnome-extensions"
    cp "$ROOT/modules/gnome-extensions/module.sh" "$ROOT/modules/gnome-extensions/hooks.sh" \
        "$ROOT/modules/gnome-extensions/extensions.list" \
        "$ROOT/modules/gnome-extensions/browse.list" \
        "$FX_TMP/seam/modules/gnome-extensions/"
    cp "$ROOT/config/extensions.compat" "$FX_TMP/seam/compat"
}

ext_run() {
    local state_dir="$1" label="$2" dry="${3:-0}" fam="${4:-rpm}" extra="${5:-}"
    : >"$LOG"
    local -a extra_env=()
    if [[ -n "$extra" ]]; then
        while IFS= read -r kv; do
            [[ -n "$kv" ]] && extra_env+=("$kv")
        done <<<"$extra"
    fi
    rm -rf "$FX_TMP/$state_dir"
    (   set -euo pipefail
        export FS_HOME="$FX_TMP/$state_dir"
        export PATH="$FX_TMP/fakebin:$PATH"
        export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY="$fam"
        export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
        export XDG_CURRENT_DESKTOP=GNOME
        export FAKE_LOG="$LOG" FAKE_SHELL_VERSION="${FAKE_SHELL_VERSION:-GNOME Shell 50.5}"
        export FAKE_EXT_LIST="$FX_TMP/ext_list" FAKE_EXT_ENABLED="$FX_TMP/ext_enabled"
        if [[ "$dry" == 1 ]]; then export FS_DRY_RUN=1; fi
        unset FS_YES FS_PROFILE FS_DISTRO_FILE FS_GNOME_BROWSE FS_GNOME_COMPAT_FILE 2>/dev/null || :
        for kv in "${extra_env[@]}"; do export "$kv"; done
        "$SETUP" install --yes gnome-extensions
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "$label rc" 0
}

printf 'P6.3 gnome-extensions module\n'
: >"$FX_TMP/ext_list"
: >"$FX_TMP/ext_enabled"

# --- 1. dry-run rpm: plan = mock install (both pkgs) + 2 enables + no probes ---
echo "--- cell: dry rpm core plan"
ext_run h_dry "dry rpm" 1 rpm
[[ $(grep -c '^# would run:' "$FX_OUT") == 3 ]] && fx_ok || fx_bad "dry rpm plan is 3 lines (got $(grep -c '^# would run:' "$FX_OUT"))"
grep -Fqx "# would run: mock install gnome-shell-extension-dash-to-dock gnome-shell-extension-user-theme" "$FX_OUT" && fx_ok || fx_bad "rpm family batch installs both packaged extensions"
[[ $(grep -c '^# would run: gnome-extensions enable' "$FX_OUT") == 2 ]] && fx_ok || fx_bad "dry plan enables exactly the 2 curated uuids (got $(grep -c '^# would run: gnome-extensions enable' "$FX_OUT"))"
grep -Fqx "# would run: gnome-extensions enable $DDASH" "$FX_OUT" && fx_ok || fx_bad "dry plan enables dash-to-dock"
grep -Fqx "# would run: gnome-extensions enable $DUTHEME" "$FX_OUT" && fx_ok || fx_bad "dry plan enables user-theme"
n_dash="$(grep -n -F "# would run: gnome-extensions enable $DDASH" "$FX_OUT" | cut -d: -f1)"
n_utheme="$(grep -n -F "# would run: gnome-extensions enable $DUTHEME" "$FX_OUT" | cut -d: -f1)"
[[ -n "$n_dash" && -n "$n_utheme" && "$n_dash" -lt "$n_utheme" ]] && fx_ok || fx_bad "dry plan enables curated uuids in extensions.list order"
fx_out "compatibility notes appear on the real run"
[[ ! -s "$LOG" ]] && fx_ok || fx_bad "dry rpm never probes or writes"
if [[ -e "$FX_TMP/h_dry/.local/state/fedora-setup" ]]; then fx_bad "dry rpm created state dir"; else fx_ok; fi

# --- 2. dry-run deb + arch family: shared bundle only ---
echo "--- cell: dry deb family"
ext_run h_deb "dry deb" 1 deb
grep -Fqx "# would run: mock install gnome-shell-extensions" "$FX_OUT" && fx_ok || fx_bad "deb family installs only the shared bundle"
[[ $(grep -c '^# would run: gnome-extensions enable' "$FX_OUT") == 2 ]] && fx_ok || fx_bad "deb dry still plans both curated enables"
echo "--- cell: dry arch family"
ext_run h_arch "dry arch" 1 arch
grep -Fqx "# would run: mock install gnome-shell-extensions" "$FX_OUT" && fx_ok || fx_bad "arch family installs only the shared bundle"
[[ $(grep -c '^# would run: gnome-extensions enable' "$FX_OUT") == 2 ]] && fx_ok || fx_bad "arch dry still plans both curated enables"

# --- 3. dry-run --browse: exactly the two curated URLs, sequentially, no exec ---
echo "--- cell: dry browse"
ext_run h_browse "dry browse" 1 rpm "FS_GNOME_BROWSE=1"
[[ $(grep -c '^# would run: xdg-open' "$FX_OUT") == 2 ]] && fx_ok || fx_bad "dry browse renders exactly 2 xdg-open lines (got $(grep -c '^# would run: xdg-open' "$FX_OUT"))"
grep -Fqx "# would run: xdg-open $URL_DDASH" "$FX_OUT" && fx_ok || fx_bad "browse opens dash-to-dock page first"
grep -Fqx "# would run: xdg-open $URL_UTHEME" "$FX_OUT" && fx_ok || fx_bad "browse opens user-themes page second"
first_browse="$(grep -n '^# would run: xdg-open' "$FX_OUT" | head -1 | cut -d: -f1)"
last_enable="$(grep -n '^# would run: gnome-extensions enable' "$FX_OUT" | tail -1 | cut -d: -f1)"
[[ -n "$last_enable" && "$first_browse" -gt "$last_enable" ]] && fx_ok || fx_bad "browse is planned after the enable steps"
[[ ! -s "$LOG" ]] && fx_ok || fx_bad "dry browse never opens or probes xdg-open"

# --- 4. browse.list with 3 URLs still opens at most 2 ---
echo "--- cell: browse hard limit 2"
seam_lib
printf '%s\n%s\nhttps://extensions.gnome.org/extension/999/nope/' "$URL_DDASH" "$URL_UTHEME" \
    >"$FX_TMP/seam/modules/gnome-extensions/browse.list"
rm -rf "$FX_TMP/h_limit"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_limit"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$FX_TMP/seam/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_SHELL_VERSION="GNOME Shell 50.5"
    export FAKE_EXT_LIST="$FX_TMP/ext_list" FAKE_EXT_ENABLED="$FX_TMP/ext_enabled"
    export FS_DRY_RUN=1 FS_GNOME_BROWSE=1
    unset FS_YES FS_PROFILE FS_DISTRO_FILE FS_GNOME_COMPAT_FILE 2>/dev/null || :
    "$SETUP" install --yes gnome-extensions
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "browse limit rc" 0
[[ $(grep -c '^# would run: xdg-open' "$FX_OUT") == 2 ]] && fx_ok || fx_bad "3-URL browse.list still opens exactly 2"
grep -Fqx "# would run: xdg-open $URL_UTHEME" "$FX_OUT" && fx_ok || fx_bad "second curated page still opened"
grep -q "extension/999/nope" "$FX_OUT" && fx_bad "third browse URL never planned" || fx_ok

# --- 5. malformed browse URL fails closed ---
echo "--- cell: malformed browse url"
printf 'ftp://nope\n' >"$FX_TMP/seam/modules/gnome-extensions/browse.list"
: >"$LOG"
rm -rf "$FX_TMP/h_badurl"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_badurl"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$FX_TMP/seam/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_SHELL_VERSION="GNOME Shell 50.5"
    export FAKE_EXT_LIST="$FX_TMP/ext_list" FAKE_EXT_ENABLED="$FX_TMP/ext_enabled"
    export FS_DRY_RUN=1 FS_GNOME_BROWSE=1
    unset FS_YES FS_PROFILE FS_DISTRO_FILE FS_GNOME_COMPAT_FILE 2>/dev/null || :
    "$SETUP" install --yes gnome-extensions
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "malformed browse url rc" 1
fx_err "invalid browse URL: ftp://nope"

# --- 5b. real-mode --browse via the CLI flag: exactly 2 ordered opens, third never opened ---
echo "--- cell: real browse via --browse flag"
printf '%s\n%s\n%s\n' "$URL_DDASH" "$URL_UTHEME" "https://extensions.gnome.org/extension/999/nope/" \
    >"$FX_TMP/seam/modules/gnome-extensions/browse.list"
printf "%s\n%s\n%s\n" "$DDASH" "$DUTHEME" "$DEXTRA" >"$FX_TMP/ext_list"
: >"$FX_TMP/ext_enabled"
: >"$LOG"
rm -rf "$FX_TMP/h_rbrowse"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_rbrowse"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$FX_TMP/seam/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_SHELL_VERSION="GNOME Shell 50.5"
    export FAKE_EXT_LIST="$FX_TMP/ext_list" FAKE_EXT_ENABLED="$FX_TMP/ext_enabled"
    unset FS_YES FS_PROFILE FS_DISTRO_FILE FS_DRY_RUN FS_GNOME_BROWSE FS_GNOME_COMPAT_FILE 2>/dev/null || :
    "$SETUP" install --yes --browse gnome-extensions
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "real --browse flag rc" 0
[[ $(grep -c '^xdg-open ' "$LOG") == 2 ]] && fx_ok || fx_bad "real --browse opens exactly 2 urls (got $(grep -c '^xdg-open ' "$LOG"))"
n_dd="$(grep -n -F "xdg-open $URL_DDASH" "$LOG" | head -1 | cut -d: -f1)"
n_ut="$(grep -n -F "xdg-open $URL_UTHEME" "$LOG" | head -1 | cut -d: -f1)"
[[ -n "$n_dd" && -n "$n_ut" && "$n_dd" -lt "$n_ut" ]] && fx_ok || fx_bad "real --browse opens curated urls in browse.list order"
grep -F "extension/999/nope" "$LOG" && fx_bad "third browse url never opened in real mode" || fx_ok
grep -Fqx "enable $DDASH" "$LOG" && fx_ok || fx_bad "real --browse still runs the enable phase before browsing"
grep -Fqx "enable $DUTHEME" "$LOG" && fx_ok || fx_bad "real --browse enables the full curated set"

# --- 6. non-GNOME desktop: graceful skip, no plan ---
echo "--- cell: non-GNOME skip"
cp "$ROOT/modules/gnome-extensions/module.sh" "$ROOT/modules/gnome-extensions/hooks.sh" \
    "$ROOT/modules/gnome-extensions/extensions.list" "$ROOT/modules/gnome-extensions/browse.list" \
    "$FX_TMP/seam/modules/gnome-extensions/"
rm -rf "$FX_TMP/h_kde"
: >"$LOG"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_kde"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$FX_TMP/seam/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export XDG_CURRENT_DESKTOP=KDE
    export FAKE_LOG="$LOG" FAKE_SHELL_VERSION="GNOME Shell 50.5"
    export FAKE_EXT_LIST="$FX_TMP/ext_list" FAKE_EXT_ENABLED="$FX_TMP/ext_enabled"
    export FS_DRY_RUN=1
    unset FS_YES FS_PROFILE FS_DISTRO_FILE FS_GNOME_BROWSE FS_GNOME_COMPAT_FILE 2>/dev/null || :
    "$SETUP" install --yes gnome-extensions
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "non-GNOME skip rc" 0
[[ $(grep -c '^# would run:' "$FX_OUT") == 0 ]] && fx_ok || fx_bad "non-GNOME dry renders no plan"
fx_out "no GNOME session"

# --- 7. gnome-extensions missing: fail closed before anything (real) ---
echo "--- cell: gnome-extensions missing"
: >"$LOG"
ln -sf "${DK_DIRNAME:-/usr/bin/dirname}" "$FX_TMP/notools/dirname"
(   set -euo pipefail
    export PATH="$FX_TMP/notools"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_SHELL_VERSION="GNOME Shell 50.5"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/modules/gnome-extensions/hooks.sh"
    run
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "gnome-extensions missing rc" 1
fx_err "gnome-extensions: gnome-extensions not found"
[[ ! -s "$LOG" ]] && fx_ok || fx_bad "no probe happens before the missing-tool gate"

# --- 8. real fresh install: both curated uuids enabled, exact cmds, notes ---
echo "--- cell: real fresh install"
printf "%s\n%s\n%s\n" "$DDASH" "$DUTHEME" "$DEXTRA" >"$FX_TMP/ext_list"
: >"$FX_TMP/ext_enabled"
ext_run h_real "real fresh" 0 rpm
grep -Fqx "list " "$LOG" && fx_ok || fx_bad "real mode probes installed set once"
grep -Fqx "list --enabled" "$LOG" && fx_ok || fx_bad "real mode probes enabled set once"
grep -Fqx "version" "$LOG" && fx_ok || fx_bad "real mode probes shell version"
grep -Fqx "enable $DDASH" "$LOG" && fx_ok || fx_bad "dash-to-dock enabled"
grep -Fqx "enable $DUTHEME" "$LOG" && fx_ok || fx_bad "user-theme enabled"
grep -Fqx "enable $DEXTRA" "$LOG" && fx_bad "non-curated installed extension never enabled by the module" || fx_ok
fx_out "GNOME shell 50.5"
[[ $(grep -c 'may not be compatible' "$FX_OUT") == 0 ]] && fx_ok || fx_bad "in-window shell version triggers no compatibility warnings"
fx_out_not "not installed; skipping"

# --- 9. real partial install: not-installed uuid reported and skipped ---
echo "--- cell: real partial install"
printf "%s\n" "$DDASH" >"$FX_TMP/ext_list"
: >"$FX_TMP/ext_enabled"
ext_run h_part "real partial" 0 rpm
grep -Fqx "enable $DDASH" "$LOG" && fx_ok || fx_bad "installed curated uuid enabled"
grep -Fqx "enable $DUTHEME" "$LOG" && fx_bad "not-installed uuid never enabled" || fx_ok
fx_out "$DUTHEME not installed; skipping"

# --- 10. real idempotent re-run: already enabled => zero enable cmds ---
echo "--- cell: real idempotent re-run"
printf "%s\n%s\n%s\n" "$DDASH" "$DUTHEME" "$DEXTRA" >"$FX_TMP/ext_list"
printf "%s\n%s\n" "$DDASH" "$DUTHEME" >"$FX_TMP/ext_enabled"
ext_run h_idem "real idempotent" 0 rpm
[[ $(grep -c '^enable ' "$LOG") == 0 ]] && fx_ok || fx_bad "idempotent re-run enables nothing"
fx_out "GNOME shell 50.5"

# --- 11. incompatible shell 51: warnings shown AND enables still happen ---
echo "--- cell: incompatible shell version"
printf "%s\n%s\n%s\n" "$DDASH" "$DUTHEME" "$DEXTRA" >"$FX_TMP/ext_list"
: >"$FX_TMP/ext_enabled"
FAKE_SHELL_VERSION="GNOME Shell 51.0" ext_run h_incompat "real shell51" 0 rpm
[[ $(grep -c 'may not be compatible' "$FX_ERR") == 2 ]] && fx_ok || fx_bad "both curated uuids flagged incompatible at shell 51 (got $(grep -c 'may not be compatible' "$FX_ERR"))"
fx_err "$DDASH may not be compatible with GNOME Shell 51"
fx_err "$DUTHEME may not be compatible with GNOME Shell 51"
grep -Fqx "enable $DDASH" "$LOG" && fx_ok || fx_bad "incompatible but installed uuid still enabled"
grep -Fqx "enable $DUTHEME" "$LOG" && fx_ok || fx_bad "incompatible but installed uuid still enabled (2)"
fx_out "GNOME shell 51.0"

# --- 12. compat seam override: custom map, one row hangs out of window ---
echo "--- cell: compat seam override"
printf "%s|46|49\n" "$DDASH" >"$FX_TMP/seam/compat"
: >"$FX_TMP/ext_enabled"
FAKE_SHELL_VERSION="GNOME Shell 50.5" ext_run h_seam "real compat seam" 0 rpm "FS_GNOME_COMPAT_FILE=$FX_TMP/seam/compat"
[[ $(grep -c 'may not be compatible' "$FX_ERR") == 1 ]] && fx_ok || fx_bad "seam map flags only dash-to-dock (got $(grep -c 'may not be compatible' "$FX_ERR"))"
fx_err "$DDASH may not be compatible with GNOME Shell 50 (supports 46-49)"
grep -Fqx "enable $DDASH" "$LOG" && fx_ok || fx_bad "seam-map incompatible uuid still enabled"

# --- 13. compat file missing: graceful, notes still work, no crash ---
echo "--- cell: compat file missing"
printf "%s\n%s\n%s\n" "$DDASH" "$DUTHEME" "$DEXTRA" >"$FX_TMP/ext_list"
: >"$FX_TMP/ext_enabled"
FAKE_SHELL_VERSION="GNOME Shell 50.5" ext_run h_nocompat "real missing compat" 0 rpm "FS_GNOME_COMPAT_FILE=$FX_TMP/seam/nope"
[[ $(grep -c 'may not be compatible' "$FX_ERR") == 0 ]] && fx_ok || fx_bad "no compat file => no warnings"
grep -Fqx "enable $DDASH" "$LOG" && fx_ok || fx_bad "enable still works with no compat file"

# --- 14. corrupt compat row + unparsable shell version: graceful skip ---
echo "--- cell: corrupt compat + unknown version"
printf 'garbage-no-pipes\n%s||50\n%s|50\n' "$DDASH" "$DUTHEME" >"$FX_TMP/seam/compat"
: >"$FX_TMP/ext_enabled"
FAKE_SHELL_VERSION="junk version" ext_run h_corrupt "real corrupt compat" 0 rpm "FS_GNOME_COMPAT_FILE=$FX_TMP/seam/compat"
fx_out "GNOME shell version unknown; compatibility notes skipped"
[[ $(grep -c 'may not be compatible' "$FX_ERR") == 0 ]] && fx_ok || fx_bad "corrupt map + unknown version => no warnings"
grep -Fqx "enable $DDASH" "$LOG" && fx_ok || fx_bad "enables still happen with unknown version"

# --- 15. corrupt extensions.list uuid fails closed (real, no writes) ---
echo "--- cell: corrupt extensions.list real"
printf 'bad uuid!\n' >"$FX_TMP/seam/modules/gnome-extensions/extensions.list"
: >"$LOG"
rm -rf "$FX_TMP/h_badlist"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_badlist"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$FX_TMP/seam/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_SHELL_VERSION="GNOME Shell 50.5"
    export FAKE_EXT_LIST="$FX_TMP/ext_list" FAKE_EXT_ENABLED="$FX_TMP/ext_enabled"
    unset FS_YES FS_PROFILE FS_DISTRO_FILE FS_DRY_RUN FS_GNOME_BROWSE FS_GNOME_COMPAT_FILE 2>/dev/null || :
    "$SETUP" install --yes gnome-extensions
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "corrupt extensions.list real rc" 1
fx_err "invalid uuid in extensions.list: bad uuid!"
[[ $(grep -c '^enable ' "$LOG") == 0 ]] && fx_ok || fx_bad "no enable write before the corrupt-uuid rejection"

# --- 16. corrupt extensions.list fails closed in dry too, zero plan ---
echo "--- cell: corrupt extensions.list dry"
: >"$LOG"
rm -rf "$FX_TMP/h_badlist2"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_badlist2"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$FX_TMP/seam/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export XDG_CURRENT_DESKTOP=GNOME
    export FAKE_LOG="$LOG" FAKE_SHELL_VERSION="GNOME Shell 50.5"
    export FAKE_EXT_LIST="$FX_TMP/ext_list" FAKE_EXT_ENABLED="$FX_TMP/ext_enabled"
    export FS_DRY_RUN=1
    unset FS_YES FS_PROFILE FS_DISTRO_FILE FS_GNOME_BROWSE FS_GNOME_COMPAT_FILE 2>/dev/null || :
    "$SETUP" install --yes gnome-extensions
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "corrupt extensions.list dry rc" 1
fx_err "invalid uuid in extensions.list: bad uuid!"
[[ $(grep -c '^# would run: gnome-extensions enable' "$FX_OUT") == 0 ]] && fx_ok || fx_bad "corrupt uuid renders no enable plan"

# --- 17. real mode --browse with xdg-open missing: manual-open hint, no exec ---
echo "--- cell: browse without xdg-open"
: >"$FX_TMP/ext_enabled"
mkdir -p "$FX_TMP/noxdg"
cp "$ROOT/lib/io.sh" "$ROOT/lib/run.sh" "$ROOT/lib/gnome.sh" "$ROOT/lib/lists.sh" "$FX_TMP/noxdg/"
ln -sf "${DK_DIRNAME:-/usr/bin/dirname}" "$FX_TMP/noxdg/dirname"
ln -sf "${DK_CAT:-/usr/bin/cat}" "$FX_TMP/noxdg/cat"
ln -sf "${DK_ENV:-/usr/bin/env}" "$FX_TMP/noxdg/env"
ln -sf "${BASH:-/usr/bin/bash}" "$FX_TMP/noxdg/bash"
cp "$FX_TMP/fakebin/gnome-shell" "$FX_TMP/fakebin/gnome-extensions" "$FX_TMP/noxdg/"
: >"$LOG"
(   set -euo pipefail
    export PATH="$FX_TMP/noxdg"
    export XDG_CURRENT_DESKTOP=GNOME
    export FS_GNOME_BROWSE=1
    export FAKE_LOG="$LOG" FAKE_SHELL_VERSION="GNOME Shell 50.5"
    export FAKE_EXT_LIST="$FX_TMP/ext_list" FAKE_EXT_ENABLED="$FX_TMP/ext_enabled"
    unset FS_DRY_RUN FS_GNOME_COMPAT_FILE 2>/dev/null || :
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/modules/gnome-extensions/hooks.sh"
    run
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "real browse no xdg rc" 0
fx_out "xdg-open not found; open manually: $URL_DDASH"
fx_out "xdg-open not found; open manually: $URL_UTHEME"
grep -q '^xdg-open' "$LOG" && fx_bad "no xdg-open executed when binary absent" || fx_ok
grep -Fqx "enable $DDASH" "$LOG" && fx_ok || fx_bad "manual-hint browse still enables the curated set"

# --- 18. setup list rows ---
echo "--- cell: setup list"
printf 'NAME="Fedora Linux"\nID=fedora\nVERSION_ID="44"\nPRETTY_NAME="Fedora Linux 44 (Workstation)"\n' >"$FX_TMP/os-release"
rm -rf "$FX_TMP/h_list"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/h_list"
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_MODULES_DIR="$ROOT/modules" FS_DISTRO_FILE="$FX_TMP/os-release"
    unset FS_YES FS_PROFILE FS_DISTRO_FAMILY 2>/dev/null || :
    "$SETUP" list gnome-extensions
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "setup list rc" 0
fx_out 'gnome-extensions.*GNOME Shell extensions.*medium.*on'

fx_summary