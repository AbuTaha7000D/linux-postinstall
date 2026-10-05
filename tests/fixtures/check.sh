#!/usr/bin/env bash
# tests/fixtures/check.sh - P9.1 fixture for `./setup check` (preflight).
#
# Drives the real launcher through a hermetic PATH "farm" of REGULAR-FILE
# binaries, rebuilt per cell so no cell can inherit another's removals.
# The farm is the whole point: reachability is driven by PATH alone, so the
# offline / online / no-HTTP-client arms need no network seam at all, and the
# missing-sudo arm is a PATH that genuinely lacks sudo. Network cells use a
# fake curl/wget, never the real ones.
#
# `guard_fake` is the P8.1 lesson applied preemptively: a farm built from
# symlinks once leaked the real binary into a non-dry cell and mutated this
# machine. Here the leak would be quieter but just as false -- a real sudo or
# curl on the fake PATH turns a FAIL/WARN cell into a silent PASS. Every cell
# that leans on a fake asserts, from the same PATH the child will see, that
# the fake is a regular file and differs from the real binary, and the guard
# has a self-test proving it still rejects a leaky farm.
#
# Also pinned: the exit-code rule (worst level decides; WARN alone is rc0), the
# invariant that the printed verdict and the exit code can never disagree, that
# a fresh HOME gains no state root, and that a dry run probes nothing.
# Usage: bash tests/fixtures/check.sh  (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init
SETUP="$ROOT/setup"

printf 'P9.1 preflight check\n'

WHITELIST="bash sh dash awk gawk mktemp rm mv cp cat ls readlink dirname uname df id tr sed grep sort head wc cut chmod touch mkdir env sleep"

FARM="$FX_TMP/farm"
REAL_SNAP="$FX_TMP/real"
CALLS="$FX_TMP/probe.calls"

mkfarm() {
    local name dest
    rm -rf -- "$FARM"
    mkdir -p "$FARM" "$REAL_SNAP"
    for name in $WHITELIST; do
        dest="$(command -v "$name" 2>/dev/null)" || continue
        [[ -n "$dest" ]] || continue
        dest="$(readlink -f "$dest" 2>/dev/null)" || continue
        [[ -f "$dest" && ! -L "$dest" ]] || continue
        cp --remove-destination -- "$dest" "$FARM/$name" 2>/dev/null || continue
        [[ -f "$FARM/$name" && ! -L "$FARM/$name" ]] || continue
        cp --remove-destination -- "$dest" "$REAL_SNAP/$name" 2>/dev/null || :
    done
}

setfake() {
    local name="$1"
    shift
    rm -f -- "$FARM/$name"
    {
        printf '#!/usr/bin/env bash\n'
        printf '%s\n' "$*"
    } >"$FARM/$name"
    chmod +x "$FARM/$name"
}

guard_fake() {
    local name="$1" label="$2" want_bad="${3:-0}"
    local f="$FARM/$name" real="$REAL_SNAP/$name" bad=0
    if [[ -e "$f" ]]; then
        if [[ ! -f "$f" ]] || [[ -L "$f" ]]; then
            bad=1
        fi
        if [[ -f "$real" ]]; then
            if cmp -s -- "$f" "$real"; then
                bad=1
            fi
        fi
    fi
    if (( bad == want_bad )); then
        fx_ok
    else
        fx_bad "guard_fake: $name in the $label farm leaked (want_bad=$want_bad, bad=$bad)"
    fi
    return 0
}

farm_reset() {
    mkfarm
    : >"$CALLS"
    setfake curl "printf '%s\\n' \"\$*\" >>'$CALLS'"
    setfake sudo "printf '%s\\n' \"\$*\" >>'$FX_TMP/sudo.calls'
exit 0"
    setfake flatpak 'exit 0'
}

OSREL="$FX_TMP/os-release"
printf 'ID=fedora\nVERSION_ID=42\nID_LIKE=rhel centos fedora\n' >"$OSREL"
OSREL_PLAN9="$FX_TMP/os-plan9"
printf 'ID=plan9\nVERSION_ID=4\n' >"$OSREL_PLAN9"
OSREL_NOID="$FX_TMP/os-noid"
printf 'VERSION_ID=42\n' >"$OSREL_NOID"

FX_BLOCK_RC=0
CHK_BACKEND="mock"
chk() {
    local want="$1" label="$2"
    shift 2
    : >"$CALLS"
    : >"$FX_TMP/sudo.calls"
    (   set -uo pipefail
        set +e
        env -i PATH="$FARM" FS_PKG_BACKEND="$CHK_BACKEND" FS_DISTRO_FILE="$OSREL" "$@"
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    fx_block_rc "$label rc" "$want"
}

# The table and the exit code are derived from the same worst level, so a
# mismatch is a real defect -- checked on every cell rather than a few.
agree() {
    local want="$1" label="$2"
    if grep -q '^  - FAIL ' "$FX_OUT" 2>/dev/null; then
        if (( want == 1 )) && grep -q 'preflight FAILED' "$FX_OUT"; then
            fx_ok
        else
            fx_bad "$label: FAIL row present but verdict/rc disagree (want $want, got $FX_BLOCK_RC)"
        fi
    elif grep -q '^  - WARN ' "$FX_OUT" 2>/dev/null; then
        if (( want == 0 )) && grep -q 'preflight OK with warnings' "$FX_OUT"; then
            fx_ok
        else
            fx_bad "$label: WARN rows present but verdict/rc disagree (want $want, got $FX_BLOCK_RC)"
        fi
    else
        if (( want == 0 )) && grep -qx '  - preflight OK' "$FX_OUT"; then
            fx_ok
        else
            fx_bad "$label: all-PASS but verdict/rc disagree (want $want, got $FX_BLOCK_RC)"
        fi
    fi
    return 0
}

probe_calls() {
    if [[ -s "$CALLS" ]]; then fx_ok; else fx_bad "$1: the network probe was never invoked"; fi
    return 0
}

no_probe_calls() {
    if [[ -s "$CALLS" ]]; then
        fx_bad "$1: a dry run must not probe, but the fake client was called:"
        sed 's/^/    /' "$CALLS" >&2
    else
        fx_ok
    fi
    return 0
}

no_sudo_escalation() {
    local bad=0 line
    if [[ ! -s "$FX_TMP/sudo.calls" ]]; then
        fx_bad "$1: sudo was never probed at all"
        return 0
    fi
    while IFS= read -r line; do
        [[ "$line" == "-n true" ]] || bad=1
    done <"$FX_TMP/sudo.calls"
    if (( bad == 0 )); then
        fx_ok
    else
        fx_bad "$1: sudo was invoked with something other than '-n true':"
        sed 's/^/    /' "$FX_TMP/sudo.calls" >&2
    fi
    return 0
}

# --- 1. all-PASS baseline (root, reachable, room on disk) -----------------

farm_reset
setfake dnf5 'exit 0'
CHK_BACKEND=""
chk 0 "all pass" HOME="$FX_TMP/h1" FS_EUID=0 FS_CHECK_MIN_FREE_MB=1 "$SETUP" check
CHK_BACKEND="mock"
guard_fake curl "all pass"
guard_fake sudo "all pass"
guard_fake dnf5 "all pass"
fx_out 'PASS distro: fedora (family rpm, pkgmgr dnf5)'
fx_out 'PASS privileges: running as root (euid 0); no sudo needed'
fx_out 'PASS flatpak: present in PATH'
fx_out 'PASS network:flathub: reachable'
fx_out 'PASS network:github: reachable'
fx_out 'PASS disk: .* free on / (need 1 MB)'
fx_out 'PASS modules: no state dir yet; nothing recorded as installed'
fx_out_not '^  - FAIL '
fx_out_not '^  - WARN '
agree 0 "all pass"
probe_calls "all pass"

# --- 2. offline: the fake client fails; still rc0, WARN only ---------------

farm_reset
setfake curl "printf '%s\\n' \"\$*\" >>'$CALLS'
exit 7"
chk 0 "offline" HOME="$FX_TMP/h2" FS_EUID=0 FS_CHECK_MIN_FREE_MB=1 "$SETUP" check
fx_out 'WARN network:flathub: unreachable (https://dl.flathub.org/repo/flathub.flatpakrepo)'
fx_out 'WARN network:github: unreachable (https://github.com)'
fx_out_not '^  - FAIL '
agree 0 "offline"
probe_calls "offline"

# --- 3. missing sudo, non-root -> FAIL, rc1 --------------------------------

farm_reset
rm -f -- "$FARM/sudo"
chk 1 "missing sudo" HOME="$FX_TMP/h3" FS_CHECK_MIN_FREE_MB=1 "$SETUP" check
fx_out 'FAIL privileges: not root and no sudo in PATH; privileged modules cannot run'
fx_out 'preflight FAILED: fix the FAIL rows above before installing'
agree 1 "missing sudo"

# --- 4. sudo present but needs a password -> WARN, rc0 ---------------------

farm_reset
setfake sudo "printf '%s\\n' \"\$*\" >>'$FX_TMP/sudo.calls'
exit 1"
chk 0 "sudo needs password" HOME="$FX_TMP/h4" FS_CHECK_MIN_FREE_MB=1 "$SETUP" check
guard_fake sudo "needs password"
fx_out 'WARN privileges: non-root; sudo requires a password, so privileged steps prompt for one'
fx_out_not '^  - FAIL privileges'
agree 0 "sudo needs password"
no_sudo_escalation "needs password"

# --- 5. passwordless sudo -> PASS, and never escalates --------------------

farm_reset
chk 0 "passwordless sudo" HOME="$FX_TMP/h5" FS_CHECK_MIN_FREE_MB=1 "$SETUP" check
guard_fake sudo "passwordless"
fx_out 'PASS privileges: non-root with passwordless sudo'
agree 0 "passwordless sudo"
no_sudo_escalation "passwordless"

# --- 6. unknown distro -> FAIL, rc1 ---------------------------------------

chk 1 "unknown distro" HOME="$FX_TMP/h6" FS_EUID=0 FS_DISTRO_FILE="$OSREL_PLAN9" \
    FS_CHECK_MIN_FREE_MB=1 "$SETUP" check
fx_err 'unsupported distro: plan9'
fx_out 'FAIL distro: detection failed'
agree 1 "unknown distro"

# --- 7. os-release with no ID -> FAIL -------------------------------------

chk 1 "distro file with no ID" HOME="$FX_TMP/h7" FS_EUID=0 FS_DISTRO_FILE="$OSREL_NOID" \
    FS_CHECK_MIN_FREE_MB=1 "$SETUP" check
fx_err 'distro file has no ID'
fx_out 'FAIL distro: detection failed'
agree 1 "distro file with no ID"

# --- 8. unreadable os-release -> FAIL -------------------------------------

chk 1 "unreadable distro file" HOME="$FX_TMP/h8" FS_EUID=0 \
    FS_DISTRO_FILE="$FX_TMP/does-not-exist" FS_CHECK_MIN_FREE_MB=1 "$SETUP" check
fx_err 'cannot read distro file'
fx_out 'FAIL distro: detection failed'
agree 1 "unreadable distro file"

# --- 9. FS_DISTRO_FAMILY must NOT short-circuit detection ----------------

chk 1 "FS_DISTRO_FAMILY ignored" HOME="$FX_TMP/h9" FS_EUID=0 FS_DISTRO_FAMILY=rpm \
    FS_DISTRO_FILE="$OSREL_PLAN9" FS_CHECK_MIN_FREE_MB=1 "$SETUP" check
fx_out 'FAIL distro: detection failed'
fx_err 'unsupported distro: plan9'
agree 1 "FS_DISTRO_FAMILY ignored"

# --- 10. a package manager named by the distro but absent -> FAIL --------

# CHK_BACKEND must not be mock here, or the row is skipped by design.
CHK_BACKEND=""
chk 1 "absent pkgmgr" HOME="$FX_TMP/h10" FS_EUID=0 FS_CHECK_MIN_FREE_MB=1 \
    FS_DISTRO_PKGMGR_OVERRIDE=definitely-not-a-real-pkgmgr "$SETUP" check
fx_out 'FAIL pkgmgr: definitely-not-a-real-pkgmgr not found in PATH'
agree 1 "absent pkgmgr"
CHK_BACKEND="mock"

# --- 10b. the mock backend skips the pkgmgr row with a WARN ---------------

chk 0 "mock backend" HOME="$FX_TMP/h10c" FS_EUID=0 FS_CHECK_MIN_FREE_MB=1 \
    "$SETUP" check
fx_out 'WARN pkgmgr: not checked (FS_PKG_BACKEND=mock)'
agree 0 "mock backend"

# --- 10c. a real package manager on the farm -> PASS ----------------------

setfake dnf5 'exit 0'
CHK_BACKEND=""
chk 0 "present pkgmgr" HOME="$FX_TMP/h10b" FS_EUID=0 FS_CHECK_MIN_FREE_MB=1 "$SETUP" check
guard_fake dnf5 "present pkgmgr"
fx_out 'PASS pkgmgr: dnf5 present in PATH'
agree 0 "present pkgmgr"
CHK_BACKEND="mock"

# --- 11. flatpak present -> PASS; absent -> WARN -------------------------

farm_reset
chk 0 "flatpak present" HOME="$FX_TMP/h11" FS_EUID=0 FS_CHECK_MIN_FREE_MB=1 "$SETUP" check
guard_fake flatpak "flatpak present"
fx_out 'PASS flatpak: present in PATH'
rm -f -- "$FARM/flatpak"
chk 0 "flatpak absent" HOME="$FX_TMP/h12" FS_EUID=0 FS_CHECK_MIN_FREE_MB=1 "$SETUP" check
fx_out 'WARN flatpak: not in PATH; GUI app modules will be skipped'
agree 0 "flatpak absent"

# --- 12. no HTTP client at all -> WARN, and NO probe is attempted ---------

farm_reset
rm -f -- "$FARM/curl"
chk 0 "no http client" HOME="$FX_TMP/h13" FS_EUID=0 FS_CHECK_MIN_FREE_MB=1 "$SETUP" check
fx_out 'WARN network: no curl or wget in PATH; reachability unknown'
fx_out_not 'network:flathub'
agree 0 "no http client"
no_probe_calls "no http client"

# --- 13. the wget arm is reachable (client chosen from PATH) -------------

farm_reset
rm -f -- "$FARM/curl"
setfake wget "printf '%s\\n' \"\$*\" >>'$CALLS'"
chk 0 "wget arm" HOME="$FX_TMP/h14" FS_EUID=0 FS_CHECK_MIN_FREE_MB=1 "$SETUP" check
guard_fake wget "wget arm"
fx_out 'PASS network:flathub: reachable'
fx_out 'PASS network:github: reachable'
agree 0 "wget arm"
probe_calls "wget arm"

# --- 14. disk: PASS above the floor, WARN below it ------------------------

farm_reset
chk 0 "disk pass" HOME="$FX_TMP/h15" FS_EUID=0 FS_CHECK_MIN_FREE_MB=1 "$SETUP" check
fx_out 'PASS disk: .* free on / (need 1 MB)'
chk 0 "disk warn" HOME="$FX_TMP/h16" FS_EUID=0 FS_CHECK_MIN_FREE_MB=999999999 "$SETUP" check
fx_out 'WARN disk: .* free on / (want 999999999 MB)'
agree 0 "disk warn"

# --- 15. bad seams fall back to defaults instead of misreporting ----------

chk 0 "bad min-free seam" HOME="$FX_TMP/h17" FS_EUID=0 FS_CHECK_MIN_FREE_MB=not-a-number \
    "$SETUP" check
fx_out 'PASS disk: .* free on / (need 2048 MB)'
chk 0 "bad net-timeout seam" HOME="$FX_TMP/h18" FS_EUID=0 FS_CHECK_MIN_FREE_MB=1 \
    FS_CHECK_NET_TIMEOUT=-9 "$SETUP" check
fx_out 'PASS network:flathub: reachable'
agree 0 "bad net-timeout seam"

# --- 16. df unavailable -> WARN, never a guess ---------------------------

farm_reset
rm -f -- "$FARM/df"
chk 0 "no df" HOME="$FX_TMP/h19" FS_EUID=0 FS_CHECK_MIN_FREE_MB=1 "$SETUP" check
fx_out 'WARN disk: cannot determine free space on /'
agree 0 "no df"

# --- 17. dry run probes nothing outside the machine -----------------------

farm_reset
chk 0 "dry run" HOME="$FX_TMP/h20" FS_DRY_RUN=1 FS_CHECK_MIN_FREE_MB=1 "$SETUP" check
fx_out 'WARN network: skipped (dry run probes nothing)'
fx_out 'WARN privileges: skipped (dry run probes nothing)'
no_probe_calls "dry run"
if [[ -s "$FX_TMP/sudo.calls" ]]; then
    fx_bad "dry run probed sudo"
else
    fx_ok
fi

# --- 18. dry run as root still reports the root arm (a local fact) --------

chk 0 "dry run root" HOME="$FX_TMP/h21" FS_EUID=0 FS_DRY_RUN=1 FS_CHECK_MIN_FREE_MB=1 \
    "$SETUP" check
fx_out 'PASS privileges: running as root'
no_probe_calls "dry run root"

# --- 19. a fresh HOME gains NO state root (read-only contract) -----------

farm_reset
chk 0 "fresh home" HOME="$FX_TMP/h22" FS_EUID=0 FS_CHECK_MIN_FREE_MB=1 "$SETUP" check
fx_out 'PASS modules: no state dir yet; nothing recorded as installed'
if [[ -e "$FX_TMP/h22/.local/state/fedora-setup" ]]; then
    fx_bad "check created a state root for a host that had none"
else
    fx_ok
fi

# --- 20. the P4.6 status registry is read, not invented ------------------

ST="$FX_TMP/h23/.local/state/fedora-setup"
mkdir -p "$ST/modules"
printf 'done 2026-01-01T00:00:00\n' >"$ST/modules/core"
printf 'done 2026-01-01T00:00:00\n' >"$ST/modules/terminal"
chk 0 "state registry read" HOME="$FX_TMP/h23" FS_EUID=0 FS_CHECK_MIN_FREE_MB=1 \
    "$SETUP" check
fx_out 'PASS modules: 2 recorded as installed: core terminal'

# --- 21. an unusable state root -> FAIL (confinement guard is load-bearing)

BASE="$FX_TMP/h24base"
mkdir -p "$BASE" "$FX_TMP/h24real"
ln -s "$FX_TMP/h24real" "$BASE/fedora-setup"
chk 1 "unusable state root" HOME="$FX_TMP/h24" XDG_STATE_HOME="$BASE" FS_EUID=0 \
    FS_CHECK_MIN_FREE_MB=1 "$SETUP" check
fx_err 'state path is a symlink'
fx_out 'FAIL state: state dir unusable; installs cannot record progress'
agree 1 "unusable state root"

# --- 21b. no resolvable state base -> FAIL (subshell-swallow regression) --
#
# `_check_state_root` once printed its path, so the caller captured it with a
# command substitution; the failure row it raised was then swallowed into the
# captured value and _CHECK_WORST was updated in a subshell copy. This cell
# pins the real answer, which is FAIL: a host that cannot resolve a state base
# cannot record install progress.

(   set -uo pipefail
    set +e
    env -i PATH="$FARM" FS_PKG_BACKEND=mock FS_DISTRO_FILE="$OSREL" FS_EUID=0 \
        FS_CHECK_MIN_FREE_MB=1 "$SETUP" check
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "no state base rc" 1
fx_out 'FAIL state: no state base: set HOME, XDG_STATE_HOME or FS_HOME'
fx_out_not 'PASS modules:'
agree 1 "no state base"

# --- 22. missing modules dir -> WARN -------------------------------------

chk 0 "missing modules dir" HOME="$FX_TMP/h25" FS_EUID=0 FS_MODULES_DIR="$FX_TMP/nope" \
    FS_CHECK_MIN_FREE_MB=1 "$SETUP" check
fx_out 'WARN modules: module directory not found'
agree 0 "missing modules dir"

# --- 23. the table is audit-logged when a log file is configured ---------

LOGF="$FX_TMP/check.log"
chk 0 "audit log" HOME="$FX_TMP/h26" FS_EUID=0 FS_CHECK_MIN_FREE_MB=1 \
    FS_LOG_FILE="$LOGF" "$SETUP" check
if grep -q 'preflight check' "$LOGF" 2>/dev/null; then
    fx_ok
else
    fx_bad "check summary was not audit-logged"
fi

# --- 24. guard_fake is not vacuous ---------------------------------------

LEAKY="$FX_TMP/leaky"
mkdir -p "$LEAKY"
ln -sf "$(readlink -f "$(command -v curl)")" "$LEAKY/curl" 2>/dev/null || :
if [[ -L "$LEAKY/curl" ]]; then
    FARM="$LEAKY"
    guard_fake curl "leaky" 1
else
    printf 'SKIP guard_fake self-test (could not create a symlink farm)\n' >&2
fi
farm_reset
guard_fake curl "real" 0

# --- 25. A2 byte identity: the preflight table must not change at all -----
#
# A2 adds a SKIP severity to lib/status.sh, which `check` shares. `check` has no
# skip-shaped rows, so the whole table must come out BYTE-IDENTICAL -- the three
# goldens below were captured from the tree BEFORE A2 and are pasted verbatim,
# including the rc line, so this is an oracle captured outside the change rather
# than a pin derived from the tree that is being pinned (which would certify
# nothing). A `check` that started emitting SKIP, or that reordered/relabelled a
# row, or that changed its verdict wording, fails here on the bytes.
#
# `cmp` is used, not `diff`, and the two normalizations are the ONLY edits: the
# fixture's own temp dir (it appears in the state row's base name) and the free
# disk figure, which is a property of the machine rather than of the code.
chk_norm() {
    sed -E "s#$FX_TMP#FX_TMP#g; s#[0-9]+ MB free on /#N MB free on /#g"
}

GOLDEN_PASS='== preflight check ==
  - PASS distro: fedora (family rpm, pkgmgr dnf5)
  - PASS pkgmgr: dnf5 present in PATH
  - PASS privileges: running as root (euid 0); no sudo needed
  - PASS flatpak: present in PATH
  - PASS network:flathub: reachable (https://dl.flathub.org/repo/flathub.flatpakrepo)
  - PASS network:github: reachable (https://github.com)
  - PASS disk: N MB free on / (need 1 MB)
  - PASS modules: no state dir yet; nothing recorded as installed
  - preflight OK
rc=0'

GOLDEN_WARN='== preflight check ==
  - PASS distro: fedora (family rpm, pkgmgr dnf5)
  - WARN pkgmgr: not checked (FS_PKG_BACKEND=mock)
  - PASS privileges: running as root (euid 0); no sudo needed
  - PASS flatpak: present in PATH
  - WARN network:flathub: unreachable (https://dl.flathub.org/repo/flathub.flatpakrepo); downloads and remotes will fail
  - WARN network:github: unreachable (https://github.com); downloads and remotes will fail
  - PASS disk: N MB free on / (need 1 MB)
  - PASS modules: no state dir yet; nothing recorded as installed
  - preflight OK with warnings
rc=0'

GOLDEN_FAIL='== preflight check ==
  - PASS distro: fedora (family rpm, pkgmgr dnf5)
  - WARN pkgmgr: not checked (FS_PKG_BACKEND=mock)
  - PASS privileges: running as root (euid 0); no sudo needed
  - PASS flatpak: present in PATH
  - WARN network:flathub: unreachable (https://dl.flathub.org/repo/flathub.flatpakrepo); downloads and remotes will fail
  - WARN network:github: unreachable (https://github.com); downloads and remotes will fail
  - PASS disk: N MB free on / (need 1 MB)
  - FAIL state: no state base: set HOME, XDG_STATE_HOME or FS_HOME, or installs cannot record progress
  - preflight FAILED: fix the FAIL rows above before installing
rc=1'

# A table plus its rc, normalized, compared against a pasted golden. On any
# mismatch the diff is printed: a byte-identity failure that only says "differ"
# teaches nothing about which byte moved.
byte_identical() {
    local label="$1" got="$2" want="$3"
    { cat "$got"; printf 'rc=%s\n' "$FX_BLOCK_RC"; } | chk_norm >"$FX_TMP/got.$label"
    if cmp -s -- "$FX_TMP/got.$label" <(printf '%s\n' "$want"); then
        fx_ok
    else
        fx_bad "$label: check output is NOT byte-identical to the pre-A2 golden:"
        diff -u <(printf '%s\n' "$want") "$FX_TMP/got.$label" 2>/dev/null | sed 's/^/    /' >&2
    fi
    return 0
}

farm_reset
setfake dnf5 'exit 0'
CHK_BACKEND=""
chk 0 "golden pass" HOME="$FX_TMP/g25a" FS_EUID=0 FS_CHECK_MIN_FREE_MB=1 "$SETUP" check
byte_identical "golden pass" "$FX_OUT" "$GOLDEN_PASS"

CHK_BACKEND="mock"
farm_reset
setfake dnf5 'exit 0'
setfake curl "printf '%s\\n' \"\$*\" >>'$CALLS'
exit 7"
chk 0 "golden warn" HOME="$FX_TMP/g25b" FS_EUID=0 FS_CHECK_MIN_FREE_MB=1 "$SETUP" check
byte_identical "golden warn" "$FX_OUT" "$GOLDEN_WARN"

CHK_BACKEND="mock"
farm_reset
setfake dnf5 'exit 0'
setfake curl "printf '%s\\n' \"\$*\" >>'$CALLS'
exit 7"
chk 1 "golden fail" FS_EUID=0 FS_CHECK_MIN_FREE_MB=1 "$SETUP" check
byte_identical "golden fail" "$FX_OUT" "$GOLDEN_FAIL"

# The explicit half of the same claim: no shape of the preflight table emits a
# SKIP row. The byte comparison above would already catch a new row, but it
# reports as a diff; this one names the defect.
farm_reset
setfake dnf5 'exit 0'
chk 0 "no skip rows" HOME="$FX_TMP/g25d" FS_EUID=0 FS_CHECK_MIN_FREE_MB=1 "$SETUP" check
fx_out_not '^  - SKIP '
grep -q '^  - SKIP ' "$FX_OUT" && fx_bad "check emitted a SKIP row" || fx_ok

# And the verdict must never offer the skip wording, which is the other half of
# "check has no skip states": a check run cannot print a skip count even if the
# severity existed.
farm_reset
setfake dnf5 'exit 0'
chk 0 "no skip verdict" HOME="$FX_TMP/g25e" FS_EUID=0 FS_CHECK_MIN_FREE_MB=1 "$SETUP" check
fx_out_not 'check(s) skipped'

fx_summary
