#!/usr/bin/env bash
# tests/fixtures/mod_containers.sh - P7.4 fixture for the `containers` module.
# Drives the REAL repo modules/ + profiles/ through `./setup install`.
# Covers: (1) the family lists are correct for a module whose package names
# are identical on rpm, deb and arch (read-only list_packages cells pinning
# the exact merged set for all three families, plus a pin that no docker
# spelling -- docker, docker.io, moby-engine, docker-compose -- may appear in
# any family's set, the owner decision that Docker is out of scope for
# P7.4); (2) the owner decision that this module can never mutate users or
# groups, pinned structurally: the module ships no hooks.sh, so there is no
# run() step from which a usermod/gpasswd/groupadd could ever execute; (3)
# dry-run single batch per family (exact render line pinned, exactly one
# `# would run:` line, no foreign-backend render, no flatpak namespace, no
# backend binary ever executed, no state dir); (4) real-mode mock routing in
# one transaction, all four names marked installed, module marked done, and a
# second run over the same state skipped as already completed with no
# re-install; (5) the `setup list` row.
# Nothing outside FX_TMP + the real repo modules/profiles is touched.
# Usage: bash tests/fixtures/mod_containers.sh  (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init
mkdir -p "$FX_TMP/fakebin"

printf 'P7.4 containers module\n'

SETUP="$ROOT/setup"
CTDIR="$ROOT/modules/containers"
LOG="$FX_TMP/ct.log"
INST="$FX_TMP/ct.inst"
STUBLOG="$FX_TMP/stub.log"
STACK='podman buildah skopeo podman-compose'
NODOCKER='docker docker.io moby-engine docker-compose'

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

# owner decision (P7.4): no user/group mutation is ever automated, so the
# module must ship no hooks.sh -- with one absent there is no run() step from
# which usermod/gpasswd/groupadd could execute. Pinned so that adding such a
# step later has to be a conscious, reviewed change to this assert.
if [[ -e "$CTDIR/hooks.sh" ]]; then
    fx_bad "containers ships a hooks.sh (no user/group mutation may be automated)"
else
    fx_ok
fi

# family lists (read-only, direct lib/lists.sh call -- no setup run): the
# merged per-family set is pinned exactly, and no docker spelling may appear.
ct_map_cell() {
    local family="$1" label="$2" id
    MAP="$FX_TMP/map.$family"
    (   set -euo pipefail
        export FS_NO_COLOR=1
        source "$ROOT/lib/io.sh"
        source "$ROOT/lib/lists.sh"
        list_packages "$CTDIR" "$family"
    ) >"$MAP" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "$label rc" 0
    local got
    got="$(tr '\n' ' ' <"$MAP")"
    got="${got% }"
    if [[ "$got" == "$STACK" ]]; then fx_ok; else fx_bad "$label map (got [$got], want [$STACK])"; fi
    for id in $NODOCKER; do
        if grep -qxF -- "$id" "$MAP" 2>/dev/null; then
            fx_bad "$label declared docker package $id"
        else
            fx_ok
        fi
    done
}

ct_map_cell deb "containers list_packages deb"
ct_map_cell rpm "containers list_packages rpm"
ct_map_cell arch "containers list_packages arch"

# dry-run: ONE batch per family, family backend only, nothing executed.
ct_dry_cell() {
    local want_family="$1" want_backend="$2" label="$3" sysbatch="$4" badfam="$5"
    : >"$STUBLOG"
    (   set -euo pipefail
        export FS_HOME="$FX_TMP/hdry"
        export FS_PKG_BACKEND="$want_backend" FS_DISTRO_FAMILY="$want_family" FS_DRY_RUN=1
        export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
        export FS_STUB_LOG="$STUBLOG"
        export PATH="$FX_TMP/fakebin:$PATH"
        unset FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
        "$SETUP" install --yes containers
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

ct_dry_cell deb deb "containers dry-run deb" \
    '^# would run: sudo apt-get install -y podman buildah skopeo podman-compose$' \
    '^# would run: sudo pacman \|^# would run: sudo dnf[0-9]* '
ct_dry_cell rpm rpm "containers dry-run rpm" \
    '^# would run: sudo dnf5 install -y podman buildah skopeo podman-compose$' \
    '^# would run: sudo apt-get \|^# would run: sudo pacman '
ct_dry_cell arch arch "containers dry-run arch" \
    '^# would run: sudo pacman -S --noconfirm --needed podman buildah skopeo podman-compose$' \
    '^# would run: sudo apt-get \|^# would run: sudo dnf[0-9]* '
if [[ -e "$FX_TMP/hdry/.local/state/fedora-setup" ]]; then fx_bad "containers dry-run created state dir"; else fx_ok; fi

# real-mode routing: one transaction through the family (mock) backend, all
# four names marked installed, module marked done. No hooks.sh means no
# run() step, so nothing else may be invoked.
: >"$LOG"
: >"$INST"
: >"$STUBLOG"
(   set -euo pipefail
    export FS_HOME="$FX_TMP/hreal"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export FS_MOCK_LOG="$LOG" FS_MOCK_INSTALLED="$INST"
    export FS_STUB_LOG="$STUBLOG"
    unset FS_DRY_RUN FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes containers
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "containers real rc" 0
fx_out 'module: containers (none)'
fx_out '^== run complete ==$'
fx_out '1 ok'
if grep -qxF "mock install $STACK" "$LOG"; then
    fx_ok
else
    fx_bad "containers batch wrong (want one transaction with the podman stack)"
    cat "$LOG" >&2
fi
if [[ "$(grep -c '^mock install ' "$LOG")" == 1 ]]; then fx_ok; else fx_bad "containers batch not single"; fi
for id in $STACK; do
    if grep -qxF -- "$id" "$INST" 2>/dev/null; then fx_ok; else fx_bad "containers installed set missing $id"; fi
done
if [[ -f "$FX_TMP/hreal/.local/state/fedora-setup/modules/containers" ]]; then fx_ok; else fx_bad "containers not marked done"; fi
if [[ "$(wc -l <"$STUBLOG")" == 0 ]]; then fx_ok; else fx_bad "containers real run invoked a backend binary"; fi
(   set -euo pipefail
    export FS_HOME="$FX_TMP/hreal"
    export FS_PKG_BACKEND=mock FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    export FS_MOCK_LOG="$LOG" FS_MOCK_INSTALLED="$INST"
    export FS_STUB_LOG="$STUBLOG"
    unset FS_DRY_RUN FS_YES FS_PROFILE FS_DISTRO_FILE 2>/dev/null || :
    "$SETUP" install --yes containers
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "containers rerun rc" 0
fx_out 'already completed: containers'
fx_out '1 skipped'
if [[ "$(grep -c '^mock install ' "$LOG")" == 1 ]]; then fx_ok; else fx_bad "containers rerun installed again"; fi

# `setup list` row (hermetic, matches modules_list.sh convention)
(   set -euo pipefail
    export FS_HOME="$FX_TMP/hlist" FS_DISTRO_FAMILY=rpm
    export FS_MODULES_DIR="$ROOT/modules" FS_PROFILES_DIR="$ROOT/profiles"
    unset FS_PKG_BACKEND FS_DISTRO_FILE FS_YES FS_PROFILE 2>/dev/null || :
    "$SETUP" list
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "setup list rc" 0
if grep -q '^containers[[:space:]]Container tooling[[:space:]]none[[:space:]]on[[:space:]]-$' "$FX_OUT"; then fx_ok; else fx_bad "containers list row malformed"; fi

fx_summary