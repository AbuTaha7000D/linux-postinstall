#!/usr/bin/env bash
# tests/fixtures/mod_flatpak.sh - P5.2 fixture for the `flatpak` base module.
# Drives the REAL repo modules/ + profiles/ through `./setup install`.
# Covers: the flatpak backend dry-run rendering the flathub remote-add line
# BEFORE a single install batch (flatpaks.list content, pinned order), dry-run
# purity (no state dir, no backend invocation) with a fake flatpak binary
# proving nothing executes; real-mode mock run honoring the mock installed set
# (a pre-installed app is filtered from the batch); the family loadability gate
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
FAKE="$FX_TMP/fakebin/flatpak"

# fake flatpak binary: logs every invocation; usable by flatpak_supported.
cat >"$FAKE" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "flatpak $*" >>"${FS_FAKE_LOG:?}"
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
        export FS_FAKE_LOG="$FX_TMP/fake.log" PATH="$FX_TMP/fakebin:$PATH"
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

# real-mode mock run honoring installed-state: pre-seed ONE app as installed,
# so the batch installs only the missing two and marks the module done.
: >"$LOG"
: >"$INST"
printf 'com.mattjakeman.ExtensionManager\n' >"$INST"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/hreal"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export FS_MOCK_LOG="$LOG" FS_MOCK_INSTALLED="$INST"
    unset FS_YES FS_PROFILE FS_DRY_RUN FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes flatpak
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "flatpak real-mode mock rc" 0
fx_out 'profile: selection'
fx_out 'module: flatpak (none)'
fx_out '^== run complete ==$'
fx_out '1 ok'
if grep -qxF 'mock install com.bitwarden.desktop net.nokyan.Resources' "$LOG"; then
    fx_ok
else
    fx_bad "flatpak real batch did not filter pre-installed app"
    cat "$LOG"
fi
if grep -qxF 'com.bitwarden.desktop' "$INST"; then fx_ok; else fx_bad "mock installed missing bitwarden"; fi
if grep -qxF 'net.nokyan.Resources' "$INST"; then fx_ok; else fx_bad "mock installed missing resources"; fi
if grep -qxF 'com.mattjakeman.ExtensionManager' "$INST"; then fx_ok; else fx_bad "mock installed lost pre-seeded app"; fi
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