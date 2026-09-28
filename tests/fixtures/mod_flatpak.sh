#!/usr/bin/env bash
# tests/fixtures/mod_flatpak.sh - P5.2 fixture for the `flatpak` base module.
# Drives the REAL repo modules/ + profiles/ through `./setup install`.
# Covers: the flatpak backend dry-run rendering the flathub remote-add line
# BEFORE a single install batch (flatpaks.list content, pinned order), dry-run
# purity (no state dir, no backend invocation) with a fake flatpak binary
# proving nothing executes; P5.7 NB-A routing: a real-mode run of the flatpak
# module (a flatpak-ONLY module) must NOT invoke the family package backend
# (mock log stays empty) and must route every app through the flatpak backend
# (stateful fake flatpak: pre-installed app filtered from the batch, the
# remaining apps installed and recorded); the family loadability gate
# (flatpaks.list satisfies every family; rpm and arch exercised); registry
# marks; `setup list` row.
# Nothing outside FX_TMP + the real repo modules/profiles is touched.
# Usage: bash tests/fixtures/mod_flatpak.sh  (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init
mkdir -p "$FX_TMP/I" "$FX_TMP/h" "$FX_TMP/fakebin"

printf 'P5.2 flatpak module\n'

SETUP="$ROOT/setup"
LOG="$FX_TMP/I/flatpak.log"
INST="$FX_TMP/I/flatpak.inst"
FAKEINST="$FX_TMP/I/flatpak.fakeinst"
FAKE="$FX_TMP/fakebin/flatpak"

# stateful fake flatpak: logs every invocation (FS_FAKE_LOG); `info`
# returns rc0 when the app is already in FS_FAKE_INSTALLED else rc1 (both
# the --user and --system probe scopes answer identically); `install`
# appends every app id to FS_FAKE_INSTALLED (so pending-filtering and
# resume stay idempotent). Dry-run never executes it (flatpak_supported is
# a bare `command -v`).
cat >"$FAKE" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "flatpak $*" >>"${FS_FAKE_LOG:?}"
case "${1:-}" in
    info)
        app="${3:-}"
        grep -qxF -- "$app" "$FS_FAKE_INSTALLED" 2>/dev/null
        exit $?
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

flatpak_cell() {
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
        "$SETUP" install --yes flatpak
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "$label rc" 0
    fx_out '^# would run: flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo$'
    fx_out '^# would run: flatpak install --user --noninteractive --assumeyes com.mattjakeman.ExtensionManager com.bitwarden.desktop net.nokyan.Resources$'
    # remote-add must precede the install batch
    local ri ii
    ri="$(grep -n '^# would run: flatpak remote-add' "$FX_OUT" | cut -d: -f1)"
    ii="$(grep -n '^# would run: flatpak install ' "$FX_OUT" | cut -d: -f1)"
    if [[ -n "$ri" && -n "$ii" && "$ri" -lt "$ii" ]]; then fx_ok; else fx_bad "$label order remote-add<install"; fi
    if grep -q '^# would run: flatpak install ' "$FX_OUT"; then
        local n
        n="$(grep -c '^# would run: flatpak install ' "$FX_OUT")"
        if (( n == 1 )); then fx_ok; else fx_bad "$label install batch single (got $n)"; fi
    fi
    # dry-run must never execute the flatpak binary
    fx_empty "$label dry never executed fakebin" "$FX_TMP/fake.log"
}

# flatpak-backend dry-run: family-agnostic flatpaks, exact render + order.
flatpak_cell rpm "flatpak dry-run rpm"
: >"$LOG"
flatpak_cell arch "flatpak dry-run arch"
fx_empty "flatpak dry-run recorded nothing" "$LOG"
if [[ -e "$FX_TMP/h/.local/state/fedora-setup" ]]; then fx_bad "flatpak dry-run created state dir"; else fx_ok; fi

# real-mode routing proof (P5.7 NB-A): the flatpak module has NO
# packages.list, so this run is flatpak-ONLY. The family backend must NOT
# be invoked (mock log stays empty) and every app must route through the
# flatpak backend via the stateful fake (a pre-installed app is filtered
# from the batch, the remaining two are installed and recorded).
REALLOG="$FX_TMP/fake-real.log"
: >"$LOG"
: >"$REALLOG"
: >"$INST"
: >"$FAKEINST"
printf 'com.mattjakeman.ExtensionManager\n' >"$FAKEINST"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/hreal"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export FS_MOCK_LOG="$LOG" FS_MOCK_INSTALLED="$INST"
    export FS_FAKE_LOG="$REALLOG" FS_FAKE_INSTALLED="$FAKEINST"
    export PATH="$FX_TMP/fakebin:$PATH"
    unset FS_YES FS_PROFILE FS_DRY_RUN FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes flatpak
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "flatpak real-mode routing rc" 0
fx_out 'profile: selection'
fx_out 'module: flatpak (none)'
fx_out '^== run complete ==$'
fx_out '1 ok'
fx_empty "flatpak-only run never invoked the family backend" "$LOG"
if grep -qxF 'flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo' "$REALLOG"; then
    fx_ok
else
    fx_bad "flatpak real batch missing remote-add"
    cat "$REALLOG"
fi
if grep -qxF 'flatpak install --user --noninteractive --assumeyes com.bitwarden.desktop net.nokyan.Resources' "$REALLOG"; then
    fx_ok
else
    fx_bad "flatpak real batch did not filter pre-installed app"
    cat "$REALLOG"
fi
if grep -qxF 'com.bitwarden.desktop' "$FAKEINST"; then fx_ok; else fx_bad "fake installed missing bitwarden"; fi
if grep -qxF 'net.nokyan.Resources' "$FAKEINST"; then fx_ok; else fx_bad "fake installed missing resources"; fi
if grep -qxF 'com.mattjakeman.ExtensionManager' "$FAKEINST"; then fx_ok; else fx_bad "fake installed lost pre-seeded app"; fi
fx_empty "mock family backend state untouched by flatpak run" "$INST"
if [[ -f "$FX_TMP/hreal/.local/state/fedora-setup/modules/flatpak" ]]; then fx_ok; else fx_bad "flatpak not marked done"; fi

# `setup list` row (hermetic, matches modules_list.sh convention)
(   set -euo pipefail
    export FS_HOME="$FX_TMP/hlist" FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    unset FS_PKG_BACKEND FS_DISTRO_FILE FS_YES FS_PROFILE 2>/dev/null || :
    "$SETUP" list
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "setup list rc" 0
if grep -q '^flatpak\b' "$FX_OUT"; then fx_ok; else fx_bad "flatpak row missing from list"; fi

fx_summary