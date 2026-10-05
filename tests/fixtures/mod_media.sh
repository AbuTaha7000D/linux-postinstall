#!/usr/bin/env bash
# tests/fixtures/mod_media.sh - P7.2 fixture for the `media` module.
# Drives the REAL repo modules/ + profiles/ through `./setup install`.
# Covers: (1) family-specific OBS packaging -- packages.deb.list /
# packages.arch.list declare the native `obs-studio` package (rendered as a
# single system batch by the family backend dry-run), while the rpm family
# declares NO native obs and renders NO system batch at all (mock log stays
# empty in real mode too), the documented rpmfusion/flatpak alternative
# living in packages.rpm.list + module.sh; (2) P5.7 NB-A routing: the system
# batch (obs-studio) goes through the FAMILY backend FIRST, the curated media
# flatpaks through the flatpak backend in ONE transaction, filtered against
# the pre-installed store; (3) dry-run purity (exact render lines: system
# batch before flatpak remote-add before single flatpak install, system batch
# absent on rpm, "would run" line count pinned, fake flatpak never executed,
# no state dir); (4) verify(): refuses dry-run without probing (rc0, both with
# no tools in PATH and with a working CLI present), passes against a
# fully-installed store and fails on missing apps (rc1) with the exact
# diagnostic lines, falls back to the --system scope for a system-only app
# (probe order pinned), fails closed when the flatpak CLI is absent from
# PATH, and is read-only in every probing cell (every fake-flatpak invocation
# must be an `info` probe -- allowlisted; the native obs-studio row is NOT
# verified here -- P9.2 `setup verify` handles system rows); (5) the
# `setup list` row.
# Nothing outside FX_TMP + the real repo modules/profiles is touched.
# Usage: bash tests/fixtures/mod_media.sh  (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init
mkdir -p "$FX_TMP/I" "$FX_TMP/h" "$FX_TMP/fakebin" "$FX_TMP/notools" "$FX_TMP/vlog"

printf 'P7.2 media module\n'

SETUP="$ROOT/setup"
LOG="$FX_TMP/I/media.log"
INST="$FX_TMP/I/media.inst"
FAKEINST="$FX_TMP/I/media.fakeinst"
FAKE="$FX_TMP/fakebin/flatpak"
NOTOOLS="$FX_TMP/notools"
VLOG="$FX_TMP/vlog/vfake.log"
MEDIA="org.kde.kdenlive io.mpv.Mpv org.audacityteam.Audacity"

# stateful fake flatpak (identical discipline to mod_apps.sh, scope-aware
# for the verify fallback cell): logs every invocation (FS_FAKE_LOG); `info`
# returns rc0 when the app is in FS_FAKE_INSTALLED, or -- for the `--system`
# probe scope only -- in FS_FAKE_SYSTEM, else rc1; `install` appends every
# app id to FS_FAKE_INSTALLED so pending-filtering and resume stay
# idempotent. Dry-run never executes it (flatpak_supported is a bare
# `command -v`).
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

# capability stubs for the dry family-backend cells: the backend is selected
# via `command -v` and never executed under dry-run (no queries, no writes).
# dnf/dnf5/rpm are stubbed too so the rpm cell that MUST render no system
# batch stays self-sufficient (host-independent red under an injected rpm
# row) instead of failing on backend noise.
cat >"$FX_TMP/fakebin/apt-get" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$FX_TMP/fakebin/apt-get"
cp "$FX_TMP/fakebin/apt-get" "$FX_TMP/fakebin/dpkg-query"
cp "$FX_TMP/fakebin/apt-get" "$FX_TMP/fakebin/pacman"
cp "$FX_TMP/fakebin/apt-get" "$FX_TMP/fakebin/dnf"
cp "$FX_TMP/fakebin/apt-get" "$FX_TMP/fakebin/dnf5"
cp "$FX_TMP/fakebin/apt-get" "$FX_TMP/fakebin/rpm"

media_dry_cell() {
    local want_family="$1" want_backend="$2" label="$3" sysbatch="$4" badfam="$5"
    : >"$LOG"
    : >"$FX_TMP/fake.log"
    (   set -euo pipefail
        export FS_HOME="$FX_TMP/h"
        export FS_PKG_BACKEND="$want_backend" FS_DISTRO_FAMILY="$want_family" FS_DRY_RUN=1
        export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
        export FS_MOCK_LOG="$LOG" FS_MOCK_INSTALLED="$INST"
        export FS_FAKE_LOG="$FX_TMP/fake.log" FS_FAKE_INSTALLED="$FAKEINST"
        export PATH="$FX_TMP/fakebin:$PATH"
        unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
        "$SETUP" install --yes media
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "$label rc" 0
    if [[ -z "$sysbatch" ]]; then
        fx_out_not "^# would run: sudo -- "
    else
        fx_out "$sysbatch"
    fi
    fx_out '^# would run: flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo$'
    fx_out "^# would run: flatpak install --user --noninteractive --assumeyes $MEDIA\$"
    local si="" ri="" ii=""
    si="$(grep -n "^# would run: sudo -- " "$FX_OUT" | cut -d: -f1 | head -1)"
    ri="$(grep -n '^# would run: flatpak remote-add' "$FX_OUT" | cut -d: -f1 | head -1)"
    ii="$(grep -n '^# would run: flatpak install ' "$FX_OUT" | cut -d: -f1 | head -1)"
    if [[ -z "$sysbatch" && -z "$si" && -n "$ri" && -n "$ii" && "$ri" -lt "$ii" ]]; then
        fx_ok
    elif [[ -n "$sysbatch" && -n "$si" && -n "$ri" && -n "$ii" && "$si" -lt "$ri" && "$ri" -lt "$ii" ]]; then
        fx_ok
    else
        fx_bad "$label order system<remote-add<install"
    fi
    if grep -q '^# would run: flatpak install ' "$FX_OUT"; then
        local n
        n="$(grep -c '^# would run: flatpak install ' "$FX_OUT")"
        if (( n == 1 )); then fx_ok; else fx_bad "$label install batch single (got $n)"; fi
    fi
    if grep -q "$badfam" "$FX_OUT"; then
        fx_bad "$label accidental non-family system render"
    else
        fx_ok
    fi
    local w
    w="$(grep -c '^# would run:' "$FX_OUT")"
    if [[ -z "$sysbatch" && "$w" == 2 ]]; then fx_ok; elif [[ -n "$sysbatch" && "$w" == 3 ]]; then fx_ok; else fx_bad "$label would-run lines (got $w, want ${sysbatch:+3}${sysbatch:-2})"; fi
    fx_empty "$label dry never executed fakebin" "$FX_TMP/fake.log"
}

# family-specific OBS packaging: deb/arch declare the native obs-studio
# system package, rpm declares none.
media_dry_cell deb deb "media dry-run deb" '^# would run: sudo -- apt-get install -y obs-studio$' '^# would run: sudo -- pacman \|^# would run: sudo -- dnf[0-9]* '
media_dry_cell arch arch "media dry-run arch" '^# would run: sudo -- pacman -S --noconfirm --needed obs-studio$' '^# would run: sudo -- apt-get \|^# would run: sudo -- dnf[0-9]* '
media_dry_cell rpm rpm "media dry-run rpm" "" '^# would run: sudo -- '
fx_empty "media dry-run recorded nothing" "$LOG"
if [[ -e "$FX_TMP/h/.local/state/fedora-setup" ]]; then fx_bad "media dry-run created state dir"; else fx_ok; fi

# real-mode deb routing proof (P5.7 NB-A): system batch (obs-studio) goes
# through the FAMILY backend (mock log) FIRST, then the media flatpaks
# through the fake flatpak in one filtered transaction (org.kde.kdenlive +
# io.mpv.Mpv pre-installed, org.audacityteam.Audacity installed); run() no-op
# hook executes; module marked done.
REALLOG="$FX_TMP/fake-real.log"
: >"$LOG"
: >"$REALLOG"
: >"$INST"
printf 'org.kde.kdenlive\nio.mpv.Mpv\n' >"$FAKEINST"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/hreal"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=deb
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export FS_MOCK_LOG="$LOG" FS_MOCK_INSTALLED="$INST"
    export FS_FAKE_LOG="$REALLOG" FS_FAKE_INSTALLED="$FAKEINST"
    export PATH="$FX_TMP/fakebin:$PATH"
    unset FS_YES FS_PROFILE FS_DRY_RUN FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes media
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "media real deb routing rc" 0
fx_out 'profile: selection'
fx_out 'module: media (none)'
fx_out '^== run complete ==$'
fx_out '^  - 1 modules ok · 0 skipped · 0 failed ·'
if grep -qxF 'mock install obs-studio' "$LOG"; then fx_ok; else fx_bad "media system batch missing obs-studio"; cat "$LOG"; fi
if grep -qxF 'flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo' "$REALLOG"; then
    fx_ok
else
    fx_bad "media real batch missing remote-add"
    cat "$REALLOG"
fi
if grep -qxF 'flatpak install --user --noninteractive --assumeyes org.audacityteam.Audacity' "$REALLOG"; then
    fx_ok
else
    fx_bad "media real batch did not filter pre-installed flatpaks"
    cat "$REALLOG"
fi
for a in $MEDIA; do
    if grep -qxF "$a" "$FAKEINST"; then fx_ok; else fx_bad "fake installed missing $a"; fi
done
if grep -qxF 'obs-studio' "$INST"; then fx_ok; else fx_bad "obs-studio not marked installed"; fi
# ordering WITHIN the flatpak log is pinned here; the system-first ordering
# (system batch before the flatpak batch) is pinned in the dry cells, where
# both renders land on ONE stdout stream -- line numbers from two independent
# log files share no timeline, so a cross-file comparison would be theatre.
rf1="$(grep -n '^flatpak remote-add' "$REALLOG" | cut -d: -f1 | head -1)"
rf2="$(grep -n '^flatpak install ' "$REALLOG" | cut -d: -f1 | head -1)"
if [[ -n "$rf1" && -n "$rf2" && "$rf1" -lt "$rf2" ]]; then fx_ok; else fx_bad "media real order remote-add<install"; fi
if [[ -f "$FX_TMP/hreal/.local/state/fedora-setup/modules/media" ]]; then fx_ok; else fx_bad "media not marked done"; fi

# real-mode rpm: NO native obs declared for the rpm family, so the family
# backend must NOT be invoked at all (mock log empty); flatpak batch still
# installs the curated media apps and the module completes.
: >"$LOG"
: >"$REALLOG"
: >"$FAKEINST"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/hrpm"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export FS_MOCK_LOG="$LOG" FS_MOCK_INSTALLED="$INST"
    export FS_FAKE_LOG="$REALLOG" FS_FAKE_INSTALLED="$FAKEINST"
    export PATH="$FX_TMP/fakebin:$PATH"
    unset FS_YES FS_PROFILE FS_DRY_RUN FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes media
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "media real rpm rc" 0
fx_out '^== run complete ==$'
fx_out '^  - 1 modules ok · 0 skipped · 0 failed ·'
fx_empty "media rpm run never invoked the family backend" "$LOG"
if grep -qxF 'flatpak install --user --noninteractive --assumeyes org.kde.kdenlive io.mpv.Mpv org.audacityteam.Audacity' "$REALLOG"; then
    fx_ok
else
    fx_bad "media rpm flatpak batch missing"
    cat "$REALLOG"
fi
if [[ -f "$FX_TMP/hrpm/.local/state/fedora-setup/modules/media" ]]; then fx_ok; else fx_bad "media rpm not marked done"; fi

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
    source "$ROOT/modules/media/hooks.sh"
    verify
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "verify dry rc" 0
fx_out "media: verify is read-only; runs only in real mode"
fx_empty "verify dry never probes" "$VLOG"

echo "--- cell: dry-run verify never probes even with a working CLI present"
: >"$VLOG"
(   set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_DRY_RUN=1
    export FS_FAKE_LOG="$VLOG" FS_FAKE_INSTALLED="$FAKEINST"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/modules/media/hooks.sh"
    verify
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "verify dry-with-cli rc" 0
fx_out "media: verify is read-only; runs only in real mode"
fx_empty "verify dry with CLI present never probes" "$VLOG"

echo "--- cell: verify passes on a fully-installed store"
: >"$VLOG"
printf '%s\n' $MEDIA >"$FAKEINST"
: >"$FX_TMP/I/media.system"
(   set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_DRY_RUN=0
    export FS_FAKE_LOG="$VLOG" FS_FAKE_INSTALLED="$FAKEINST" FS_FAKE_SYSTEM="$FX_TMP/I/media.system"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/modules/media/hooks.sh"
    verify
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "verify pass rc" 0
fx_out "media: verify ok: flatpak present: org.kde.kdenlive"
fx_out "media: verify ok: flatpak present: org.audacityteam.Audacity"
fx_out "media: verify passed"
if [[ "$(grep -c 'media: verify ok:' "$FX_OUT")" == 3 ]]; then fx_ok; else fx_bad "verify ok lines (got $(grep -c 'media: verify ok:' "$FX_OUT"))"; fi
log_only_info "passing verify read-only" "$VLOG"

echo "--- cell: verify falls back to the --system scope for a system-only app"
: >"$VLOG"
printf 'org.kde.kdenlive\norg.audacityteam.Audacity\n' >"$FAKEINST"
printf 'io.mpv.Mpv\n' >"$FX_TMP/I/media.system"
(   set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_DRY_RUN=0
    export FS_FAKE_LOG="$VLOG" FS_FAKE_INSTALLED="$FAKEINST" FS_FAKE_SYSTEM="$FX_TMP/I/media.system"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/modules/media/hooks.sh"
    verify
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "verify system-fallback rc" 0
fx_out "media: verify ok: flatpak present: io.mpv.Mpv"
fx_out "media: verify passed"
if grep -qxF 'flatpak info --user io.mpv.Mpv' "$VLOG"; then fx_ok; else fx_bad "fallback user probe missing"; fi
if grep -qxF 'flatpak info --system io.mpv.Mpv' "$VLOG"; then fx_ok; else fx_bad "fallback system probe missing"; fi
local_u="$(grep -n 'flatpak info --user io.mpv.Mpv' "$VLOG" | cut -d: -f1 | head -1)"
local_s="$(grep -n 'flatpak info --system io.mpv.Mpv' "$VLOG" | cut -d: -f1 | head -1)"
if [[ -n "$local_u" && -n "$local_s" && "$local_u" -lt "$local_s" ]]; then fx_ok; else fx_bad "fallback probe order user<system"; fi
log_only_info "fallback verify read-only" "$VLOG"

echo "--- cell: verify fails on missing apps"
: >"$VLOG"
printf 'org.kde.kdenlive\norg.audacityteam.Audacity\n' >"$FAKEINST"
: >"$FX_TMP/I/media.system"
(   set -euo pipefail
    export PATH="$FX_TMP/fakebin:$PATH"
    export FS_DRY_RUN=0
    export FS_FAKE_LOG="$VLOG" FS_FAKE_INSTALLED="$FAKEINST"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/modules/media/hooks.sh"
    verify
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "verify fail rc" 1
fx_out "media: verify ok: flatpak present: org.kde.kdenlive"
fx_err "media: verify FAILED: flatpak not installed: io.mpv.Mpv"
fx_out_not "media: verify passed"
if [[ "$(grep -c 'media: verify ok:' "$FX_OUT")" == 2 ]]; then fx_ok; else fx_bad "verify fail ok lines (got $(grep -c 'media: verify ok:' "$FX_OUT"))"; fi
log_only_info "failing verify read-only" "$VLOG"

echo "--- cell: verify SKIPS (rc 93) when the flatpak CLI is absent"
# rc is 93, lib/verify.sh's _VERIFY_HOOK_SKIP -- see the matching cell in
# tests/fixtures/mod_apps.sh for why this arm is a skip and not a failure.
(   set -euo pipefail
    export PATH="$NOTOOLS"
    export FS_DRY_RUN=0
    export FS_FAKE_LOG="$VLOG" FS_FAKE_INSTALLED="$FAKEINST"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/run.sh"
    source "$ROOT/modules/media/hooks.sh"
    verify
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "verify no-flatpak rc" 93
fx_out "media: verify: flatpak CLI not found; cannot verify"
fx_err_not "media: verify: flatpak CLI not found; cannot verify"

# `setup list` row (hermetic, matches modules_list.sh convention)
(   set -euo pipefail
    export FS_HOME="$FX_TMP/hlist" FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    unset FS_PKG_BACKEND FS_DISTRO_FILE FS_YES FS_PROFILE 2>/dev/null || :
    "$SETUP" list
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "setup list rc" 0
if grep -q '^media[[:space:]]Media tools[[:space:]]none[[:space:]]on[[:space:]]-$' "$FX_OUT"; then fx_ok; else fx_bad "media list row malformed"; fi

fx_summary