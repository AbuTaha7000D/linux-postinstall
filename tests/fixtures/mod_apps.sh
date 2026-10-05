#!/usr/bin/env bash
# tests/fixtures/mod_apps.sh - P7.1 fixture for the `apps` module.
# Drives the REAL repo modules/ + profiles/ through `./setup install`.
# Covers: (1) the flatpak backend dry-run rendering the flathub remote-add
# line BEFORE a single install batch of the full curated apps list (pinned
# order), dry-run purity (no state dir, fake flatpak never executed); (2)
# P5.7 NB-A routing: a real-mode run of the flatpak-ONLY apps module must
# NOT invoke the family package backend (mock log stays empty), routes
# every app through the flatpak backend (stateful fake flatpak: two
# pre-installed apps filtered from the batch, the rest installed and
# recorded in one transaction), the run() no-op hook executes cleanly, and
# the module is marked done; (3) verify(): refuses dry-run without probing
# (rc0, both with no tools in PATH and with a working CLI present), passes
# against a fully-installed store and fails on missing apps (rc1) with the
# exact diagnostic lines, falls back to the --system scope for a
# system-only app (probe order pinned), fails closed when the flatpak CLI
# is absent from PATH, and is read-only in every probing cell (every
# fake-flatpak invocation must be an `info` probe -- allowlisted);
# (4) the `setup list` row.
# Nothing outside FX_TMP + the real repo modules/profiles is touched.
# Usage: bash tests/fixtures/mod_apps.sh  (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init
mkdir -p "$FX_TMP/I" "$FX_TMP/h" "$FX_TMP/fakebin" "$FX_TMP/notools" "$FX_TMP/vlog"

printf 'P7.1 apps module\n'

SETUP="$ROOT/setup"
LOG="$FX_TMP/I/apps.log"
INST="$FX_TMP/I/apps.inst"
FAKEINST="$FX_TMP/I/apps.fakeinst"
FAKE="$FX_TMP/fakebin/flatpak"
NOTOOLS="$FX_TMP/notools"
VLOG="$FX_TMP/vlog/vfake.log"
APPS="org.mozilla.Thunderbird org.libreoffice.LibreOffice org.qbittorrent.qBittorrent com.discordapp.Discord org.gimp.GIMP org.videolan.VLC"

# stateful fake flatpak (modeled on mod_flatpak.sh's, scope-aware for the
# verify fallback cell): logs every invocation (FS_FAKE_LOG); `info`
# returns rc0 when the app is already in FS_FAKE_INSTALLED, or -- for the
# `--system` probe scope only -- in FS_FAKE_SYSTEM, else rc1 (so a
# system-only app is answerable only via the fallback arm); `install`
# appends every app id to FS_FAKE_INSTALLED so pending-filtering and
# resume stay idempotent. Dry-run never executes it (flatpak_supported is
# a bare `command -v`).
cat >"$FAKE" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "flatpak $*" >>"${FS_FAKE_LOG:?}"
case "${1:-}" in
    info)
        app="${3:-}"
        scope="${2:-}"
        if grep -qxF -- "$app" "$FS_FAKE_INSTALLED" 2>/dev/null; then
            exit 0
        fi
        if [[ "$scope" == "--system" ]]; then
            grep -qxF -- "$app" "${FS_FAKE_SYSTEM:-}" 2>/dev/null
            exit $?
        fi
        exit 1
        ;;
    install)
        shift
        for a in "$@"; do
            case "$a" in
                --*) continue ;;
            esac
            grep -qxF -- "$a" "$FS_FAKE_INSTALLED" 2>/dev/null || printf '%s\n' "$a" >>"$FS_FAKE_INSTALLED"
        done
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
EOF
chmod +x "$FAKE"

apps_dry_cell() {
    local want_family="$1" label="$2"
    : >"$LOG"
    : >"$FX_TMP/fake.log"
    (   set -euo pipefail
        export FS_HOME="$FX_TMP/h"
        export FS_PKG_BACKEND=flatpak FS_DISTRO_FAMILY="$want_family" FS_DRY_RUN=1
        export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
        export FS_MOCK_LOG="$LOG" FS_MOCK_INSTALLED="$INST"
        export FS_FAKE_LOG="$FX_TMP/fake.log" FS_FAKE_INSTALLED="$FAKEINST"
        export PATH="$FX_TMP/fakebin:$PATH"
        unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
        "$SETUP" install --yes apps
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "$label rc" 0
    fx_out '^# would run: flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo$'
    fx_out "^# would run: flatpak install --user --noninteractive --assumeyes $APPS\$"
    local ri ii
    ri="$(grep -n '^# would run: flatpak remote-add' "$FX_OUT" | cut -d: -f1)"
    ii="$(grep -n '^# would run: flatpak install ' "$FX_OUT" | cut -d: -f1)"
    if [[ -n "$ri" && -n "$ii" && "$ri" -lt "$ii" ]]; then fx_ok; else fx_bad "$label order remote-add<install"; fi
    if grep -q '^# would run: flatpak install ' "$FX_OUT"; then
        local n
        n="$(grep -c '^# would run: flatpak install ' "$FX_OUT")"
        if (( n == 1 )); then fx_ok; else fx_bad "$label install batch single (got $n)"; fi
    fi
    local w
    w="$(grep -c '^# would run:' "$FX_OUT")"
    if (( w == 2 )); then fx_ok; else fx_bad "$label would-run lines (got $w, want 2)"; fi
    fx_empty "$label dry never executed fakebin" "$FX_TMP/fake.log"
}

# flatpak-backend dry-run: family-agnostic flatpaks, exact render + order.
apps_dry_cell rpm "apps dry-run rpm"
apps_dry_cell arch "apps dry-run arch"
fx_empty "apps dry-run recorded nothing" "$LOG"
if [[ -e "$FX_TMP/h/.local/state/fedora-setup" ]]; then fx_bad "apps dry-run created state dir"; else fx_ok; fi

# real-mode routing proof (P5.7 NB-A): the apps module has NO packages.list,
# so this run is flatpak-ONLY. The family backend must NOT be invoked (mock
# log stays empty); two pre-installed apps are filtered from the batch, the
# remaining four install through the stateful fake in ONE transaction, the
# run() no-op hook executes, and the module is marked done.
REALLOG="$FX_TMP/fake-real.log"
: >"$LOG"
: >"$REALLOG"
: >"$INST"
: >"$FAKEINST"
printf 'org.mozilla.Thunderbird\ncom.discordapp.Discord\n' >"$FAKEINST"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/hreal"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export FS_MOCK_LOG="$LOG" FS_MOCK_INSTALLED="$INST"
    export FS_FAKE_LOG="$REALLOG" FS_FAKE_INSTALLED="$FAKEINST"
    export PATH="$FX_TMP/fakebin:$PATH"
    unset FS_YES FS_PROFILE FS_DRY_RUN FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes apps
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "apps real-mode routing rc" 0
fx_out 'profile: selection'
fx_out 'module: apps (none)'
fx_out '^== run complete ==$'
fx_out '^  - 1 modules ok · 0 skipped · 0 failed ·'
fx_empty "apps-only run never invoked the family backend" "$LOG"
if grep -qxF 'flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo' "$REALLOG"; then
    fx_ok
else
    fx_bad "apps real batch missing remote-add"
    cat "$REALLOG"
fi
if grep -qxF 'flatpak install --user --noninteractive --assumeyes org.libreoffice.LibreOffice org.qbittorrent.qBittorrent org.gimp.GIMP org.videolan.VLC' "$REALLOG"; then
    fx_ok
else
    fx_bad "apps real batch did not filter pre-installed apps"
    cat "$REALLOG"
fi
for a in $APPS; do
    if grep -qxF "$a" "$FAKEINST"; then fx_ok; else fx_bad "fake installed missing $a"; fi
done
fx_empty "mock family backend state untouched by apps run" "$INST"
if [[ -f "$FX_TMP/hreal/.local/state/fedora-setup/modules/apps" ]]; then fx_ok; else fx_bad "apps not marked done"; fi

# verify() is read-only; its cells drive the hook directly (P6.5 pattern).
# log_only_info asserts every logged fake-flatpak invocation is an `info`
# probe (allowlist -- any install/remote-add/update/etc. line fails).
log_only_info() {
    local label="$1" file="$2"
    if grep -qv '^flatpak info ' "$file"; then
        fx_bad "$label (non-info lines in fake log)"
        cat "$file"
    else
        fx_ok
    fi
}

echo "--- cell: verify refuses dry-run without probing (no flatpak in PATH)"
: >"$VLOG"
(   set -euo pipefail
    export PATH="$NOTOOLS"
    export FS_DRY_RUN=1
    export FS_FAKE_LOG="$VLOG" FS_FAKE_INSTALLED="$FAKEINST"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/modules/apps/hooks.sh"
    verify
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "verify dry rc" 0
fx_out "apps: verify is read-only; runs only in real mode"
fx_empty "verify dry never probes" "$VLOG"

echo "--- cell: dry-run verify never probes even with a working CLI present"
: >"$VLOG"
(   set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_DRY_RUN=1
    export FS_FAKE_LOG="$VLOG" FS_FAKE_INSTALLED="$FAKEINST"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/modules/apps/hooks.sh"
    verify
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "verify dry-with-cli rc" 0
fx_out "apps: verify is read-only; runs only in real mode"
fx_empty "verify dry with CLI present never probes" "$VLOG"

echo "--- cell: verify passes on a fully-installed store"
: >"$VLOG"
printf '%s\n' $APPS >"$FAKEINST"
: >"$FX_TMP/I/apps.system"
(   set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_DRY_RUN=0
    export FS_FAKE_LOG="$VLOG" FS_FAKE_INSTALLED="$FAKEINST" FS_FAKE_SYSTEM="$FX_TMP/I/apps.system"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/modules/apps/hooks.sh"
    verify
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "verify pass rc" 0
fx_out "apps: verify ok: flatpak present: org.mozilla.Thunderbird"
fx_out "apps: verify ok: flatpak present: org.videolan.VLC"
fx_out "apps: verify passed"
if [[ "$(grep -c 'apps: verify ok:' "$FX_OUT")" == 6 ]]; then fx_ok; else fx_bad "verify ok lines (got $(grep -c 'apps: verify ok:' "$FX_OUT"))"; fi
log_only_info "passing verify read-only" "$VLOG"

echo "--- cell: verify falls back to the --system scope for a system-only app"
: >"$VLOG"
printf '%s\n' org.mozilla.Thunderbird org.libreoffice.LibreOffice org.qbittorrent.qBittorrent com.discordapp.Discord org.gimp.GIMP >"$FAKEINST"
printf 'org.videolan.VLC\n' >"$FX_TMP/I/apps.system"
(   set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_DRY_RUN=0
    export FS_FAKE_LOG="$VLOG" FS_FAKE_INSTALLED="$FAKEINST" FS_FAKE_SYSTEM="$FX_TMP/I/apps.system"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/modules/apps/hooks.sh"
    verify
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "verify system-fallback rc" 0
fx_out "apps: verify ok: flatpak present: org.videolan.VLC"
fx_out "apps: verify passed"
if grep -qxF 'flatpak info --user org.videolan.VLC' "$VLOG"; then fx_ok; else fx_bad "fallback user probe missing"; fi
if grep -qxF 'flatpak info --system org.videolan.VLC' "$VLOG"; then fx_ok; else fx_bad "fallback system probe missing"; fi
local_u="$(grep -n 'flatpak info --user org.videolan.VLC' "$VLOG" | cut -d: -f1 | head -1)"
local_s="$(grep -n 'flatpak info --system org.videolan.VLC' "$VLOG" | cut -d: -f1 | head -1)"
if [[ -n "$local_u" && -n "$local_s" && "$local_u" -lt "$local_s" ]]; then fx_ok; else fx_bad "fallback probe order user<system"; fi
log_only_info "fallback verify read-only" "$VLOG"

echo "--- cell: verify fails on missing apps"
: >"$VLOG"
printf 'org.mozilla.Thunderbird\norg.libreoffice.LibreOffice\norg.qbittorrent.qBittorrent\n' >"$FAKEINST"
: >"$FX_TMP/I/apps.system"
(   set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_DRY_RUN=0
    export FS_FAKE_LOG="$VLOG" FS_FAKE_INSTALLED="$FAKEINST"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/modules/apps/hooks.sh"
    verify
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "verify fail rc" 1
fx_out "apps: verify ok: flatpak present: org.mozilla.Thunderbird"
fx_err "apps: verify FAILED: flatpak not installed: com.discordapp.Discord"
fx_err "apps: verify FAILED: flatpak not installed: org.gimp.GIMP"
fx_err "apps: verify FAILED: flatpak not installed: org.videolan.VLC"
fx_out_not "apps: verify passed"
if [[ "$(grep -c 'apps: verify ok:' "$FX_OUT")" == 3 ]]; then fx_ok; else fx_bad "verify fail ok lines (got $(grep -c 'apps: verify ok:' "$FX_OUT"))"; fi
log_only_info "failing verify read-only" "$VLOG"

echo "--- cell: verify SKIPS (rc 93) when the flatpak CLI is absent"
# rc is 93, lib/verify.sh's _VERIFY_HOOK_SKIP, and the reason is io_info not
# io_error: this arm did not look at the install, so reporting it as a failure
# would be a FAIL row for an audit that never ran -- the same false-PASS shape
# inverted. The literal 93 is pinned; the distinctness of the reserved values
# is pinned in tests/fixtures/verify.sh.
(   set -euo pipefail
    export PATH="$NOTOOLS"
    export FS_DRY_RUN=0
    export FS_FAKE_LOG="$VLOG" FS_FAKE_INSTALLED="$FAKEINST"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/modules/apps/hooks.sh"
    verify
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "verify no-flatpak rc" 93
fx_out "apps: verify: flatpak CLI not found; cannot verify"
fx_err_not "apps: verify: flatpak CLI not found; cannot verify"

# `setup list` row (hermetic, matches modules_list.sh convention)
(   set -euo pipefail
    export FS_HOME="$FX_TMP/hlist" FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    unset FS_PKG_BACKEND FS_DISTRO_FILE FS_YES FS_PROFILE 2>/dev/null || :
    "$SETUP" list
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "setup list rc" 0
if grep -q '^apps[[:space:]]Desktop apps[[:space:]]none[[:space:]]on[[:space:]]-$' "$FX_OUT"; then fx_ok; else fx_bad "apps list row malformed"; fi

fx_summary