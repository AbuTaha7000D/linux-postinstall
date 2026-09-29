#!/usr/bin/env bash
# tests/fixtures/mod_dev.sh - P7.3 fixture for the `dev` module.
# Drives the REAL repo modules/ + profiles/ through `./setup install`.
# Covers: (1) family lists map package names correctly (read-only
# list_packages cells pinning the exact merged per-family set and proving
# NO cross-family name leakage -- python3-pip on rpm+deb vs python-pip on
# arch is exactly the divergence a family file can express: lib/lists.sh
# overrides only SAME-NAMED common entries, so a divergent name may appear in
# a family file and never in packages.list. `jupyter` -- the arch name an
# earlier draft wrongly assumed -- must appear in NO family's set: archlinux
# has no `jupyter` in any official repo or the AUR, and Fedora has none, so
# the name this module pins is `jupyter-notebook` on all three families
# (Debian does ship a `jupyter` metapackage; it is deliberately not used);
# (2) dry-run
# single batch per family (exact render line pinned: the merged per-family set
# in ONE `install -y` transaction, exactly one `# would run:` line, no
# foreign backend render, no flatpak namespace at all, no backend binary ever
# executed, no state dir); (3) real-mode mock routing with already-installed
# filtering (gcc+make pre-seeded are dropped from the single transaction, the
# rest are marked installed, module marked done) and a second run over the
# same state that is skipped as already completed and installs nothing again;
# (4) end-to-end divergent-name proof on arch (the real transaction carries
# python-pip and never python3-pip);
# (5) the `setup list` row.
# Nothing outside FX_TMP + the real repo modules/profiles is touched.
# Usage: bash tests/fixtures/mod_dev.sh  (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init
mkdir -p "$FX_TMP/fakebin"

printf 'P7.3 dev module\n'

SETUP="$ROOT/setup"
DEVDIR="$ROOT/modules/dev"
LOG="$FX_TMP/dev.log"
INST="$FX_TMP/dev.inst"
STUBLOG="$FX_TMP/stub.log"
COMMON='nodejs gcc make cmake clang jupyter-notebook'
RDEBSET="python3-pip $COMMON"
ARCHSET="python-pip $COMMON"

# capability stubs for the dry family-backend cells: the backend is selected
# via `command -v` and never executed under dry-run (no queries, no writes).
# Every stub records itself, so each dry cell can PROVE no package-manager
# binary was executed (no probes, no writes, no metadata refresh).
cat >"$FX_TMP/fakebin/apt-get" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "apt-get $*" >>"${FS_STUB_LOG:?}"
exit 0
EOF
chmod +x "$FX_TMP/fakebin/apt-get"
cp "$FX_TMP/fakebin/apt-get" "$FX_TMP/fakebin/dpkg-query"
cp "$FX_TMP/fakebin/apt-get" "$FX_TMP/fakebin/pacman"
cp "$FX_TMP/fakebin/apt-get" "$FX_TMP/fakebin/dnf"
cp "$FX_TMP/fakebin/apt-get" "$FX_TMP/fakebin/dnf5"
cp "$FX_TMP/fakebin/apt-get" "$FX_TMP/fakebin/rpm"

# family-list mapping (read-only, direct lib/lists.sh call -- no setup run):
# the merged per-family set is pinned exactly, and every other family's
# divergent name must be absent.
dev_map_cell() {
    local family="$1" want="$2" label="$3" absent="$4" id
    MAP="$FX_TMP/map.$family"
    (   set -euo pipefail
        export FS_NO_COLOR=1
        source "$ROOT/lib/io.sh"
        source "$ROOT/lib/lists.sh"
        list_packages "$DEVDIR" "$family"
    ) >"$MAP" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "$label rc" 0
    local got
    got="$(tr '\n' ' ' <"$MAP")"
    got="${got% }"
    if [[ "$got" == "$want" ]]; then fx_ok; else fx_bad "$label map (got [$got], want [$want])"; fi
    for id in $absent; do
        if grep -qxF -- "$id" "$MAP" 2>/dev/null; then
            fx_bad "$label leaked $id"
        else
            fx_ok
        fi
    done
}

dev_map_cell deb "$RDEBSET" "dev list_packages deb" "python-pip jupyter"
dev_map_cell rpm "$RDEBSET" "dev list_packages rpm" "python-pip jupyter"
dev_map_cell arch "$ARCHSET" "dev list_packages arch" "python3-pip jupyter"

# dry-run: ONE batch per family, family backend only, nothing executed.
dev_dry_cell() {
    local want_family="$1" want_backend="$2" label="$3" sysbatch="$4" badfam="$5"
    : >"$LOG"
    : >"$STUBLOG"
    (   set -euo pipefail
        export FS_HOME="$FX_TMP/hdry"
        export FS_PKG_BACKEND="$want_backend" FS_DISTRO_FAMILY="$want_family" FS_DRY_RUN=1
        export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
        export FS_STUB_LOG="$STUBLOG"
        export PATH="$FX_TMP/fakebin:$PATH"
        unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
        "$SETUP" install --yes dev
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "$label rc" 0
    fx_out "$sysbatch"
    fx_out_not "$badfam"
    fx_out_not '^# would run: flatpak '
    local n w
    n="$(grep -c '^# would run: sudo ' "$FX_OUT")"
    if (( n == 1 )); then fx_ok; else fx_bad "$label system batch single (got $n)"; fi
    w="$(grep -c '^# would run:' "$FX_OUT")"
    if (( w == 1 )); then fx_ok; else fx_bad "$label would-run lines (got $w, want 1)"; fi
    fx_empty "$label dry never executed a backend binary" "$STUBLOG"
}

dev_dry_cell deb deb "dev dry-run deb" \
    '^# would run: sudo apt-get install -y python3-pip nodejs gcc make cmake clang jupyter-notebook$' \
    '^# would run: sudo pacman \|^# would run: sudo dnf[0-9]* '
dev_dry_cell rpm rpm "dev dry-run rpm" \
    '^# would run: sudo dnf5 install -y python3-pip nodejs gcc make cmake clang jupyter-notebook$' \
    '^# would run: sudo apt-get \|^# would run: sudo pacman '
dev_dry_cell arch arch "dev dry-run arch" \
    '^# would run: sudo pacman -S --noconfirm --needed python-pip nodejs gcc make cmake clang jupyter-notebook$' \
    '^# would run: sudo apt-get \|^# would run: sudo dnf[0-9]* '
if [[ -e "$FX_TMP/hdry/.local/state/fedora-setup" ]]; then fx_bad "dev dry-run created state dir"; else fx_ok; fi

# real-mode deb routing with already-installed filtering: gcc + make are
# pre-seeded, so the single transaction carries the other five names; all
# seven end up installed and the module is marked done. The second run over
# the same state must not install anything again.
: >"$LOG"
: >"$INST"
printf 'gcc\nmake\n' >"$INST"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/hreal"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=deb
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export FS_MOCK_LOG="$LOG" FS_MOCK_INSTALLED="$INST"
    unset FS_DRY_RUN FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes dev
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "dev real deb rc" 0
fx_out 'module: dev (none)'
fx_out '^== run complete ==$'
fx_out '1 ok'
if grep -qxF "mock install python3-pip nodejs cmake clang jupyter-notebook" "$LOG"; then
    fx_ok
else
    fx_bad "dev deb batch wrong (want one filtered transaction)"
    cat "$LOG" >&2
fi
if [[ "$(grep -c '^mock install ' "$LOG")" == 1 ]]; then fx_ok; else fx_bad "dev deb batch not single"; fi
for id in $RDEBSET; do
    if grep -qxF -- "$id" "$INST" 2>/dev/null; then fx_ok; else fx_bad "dev installed set missing $id"; fi
done
if [[ -f "$FX_TMP/hreal/.local/state/fedora-setup/modules/dev" ]]; then fx_ok; else fx_bad "dev not marked done"; fi
: >"$STUBLOG"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/hreal"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=deb
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export FS_MOCK_LOG="$LOG" FS_MOCK_INSTALLED="$INST"
    unset FS_DRY_RUN FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes dev
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "dev rerun rc" 0
fx_out 'already completed: dev'
fx_out '1 skipped'
if [[ "$(grep -c '^mock install ' "$LOG")" == 1 ]]; then fx_ok; else fx_bad "dev rerun installed again"; fi

# real-mode arch: the divergent pip name reaches the transaction verbatim
# (and the deb-only spelling never does); same module/state asserts as the
# deb cell so the two families cannot drift apart unnoticed.
: >"$LOG"
: >"$INST"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/harch"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=arch
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export FS_MOCK_LOG="$LOG" FS_MOCK_INSTALLED="$INST"
    unset FS_DRY_RUN FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes dev
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "dev real arch rc" 0
fx_out 'module: dev (none)'
fx_out '^== run complete ==$'
fx_out '1 ok'
if grep -qxF "mock install $ARCHSET" "$LOG"; then
    fx_ok
else
    fx_bad "dev arch batch wrong (want python-pip name)"
    cat "$LOG" >&2
fi
for id in python3-pip jupyter; do
    if grep -qxF -- "$id" "$INST" 2>/dev/null; then fx_bad "dev arch installed non-arch name $id"; else fx_ok; fi
done
if [[ -f "$FX_TMP/harch/.local/state/fedora-setup/modules/dev" ]]; then fx_ok; else fx_bad "dev arch not marked done"; fi

# `setup list` row (hermetic, matches modules_list.sh convention)
(   set -euo pipefail
    export FS_HOME="$FX_TMP/hlist" FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    unset FS_PKG_BACKEND FS_DISTRO_FILE FS_YES FS_PROFILE 2>/dev/null || :
    "$SETUP" list
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "setup list rc" 0
if grep -q '^dev[[:space:]]Dev toolchains[[:space:]]none[[:space:]]on[[:space:]]-$' "$FX_OUT"; then fx_ok; else fx_bad "dev list row malformed"; fi

fx_summary