#!/usr/bin/env bash
# tests/containers/smoke.sh - P10.3 container smoke test.
#
# Runs INSIDE a root container (fedora:latest / fedora:41 / debian:stable /
# archlinux:latest). Drives the REAL launcher against the REAL package
# backends of whatever distro the image is -- this is the [REAL] half of
# P10.3, the part no mock backend can stand in for. Asserts, in order:
#
#   1. `setup check` exits 0 and names this image's own distro id (a real
#      /etc/os-release read; the mock backend could not detect deb).
#   2. `install minimal --yes --dry-run` writes NOTHING. Proven by a
#      filesystem fingerprint (path|size|mtime) over the state root, $HOME,
#      /etc and the repo, before and after, plus an explicit
#      state-root-absent check. Fingerprint, not "no error": a dry-run
#      that silently wrote a file passes an rc-only test.
#   3. The dry-run render names the profile's modules and a system batch.
#   4. Where safe, a REAL `install minimal --yes` exits 0, marks both
#      modules in the registry, and names a real run log. Gated on
#      flatpak + network: a family without the flatpak binary is SKIPPED
#      WITH A PRINTED REASON, never silently reported as a pass.
#      If the install cannot finish inside FS_CTR_TIMEOUT the result is
#      INCONCLUSIVE, which is a FAILURE, not a pass -- see "Knobs" below.
#      A real install pulls >2GB from Flathub, so the deadline is an
#      environment limit, not a verdict on the tool.
#   5. GNOME-only modules are explicitly SKIPPED with a printed reason
#      (headless container: no session bus, no display, no gsettings
#      schema) rather than being claimed as covered.
#
# NOT a CI claim: a green run of this script proves the tool works in a
# container. It does NOT prove the GitHub Actions pipeline is green --
# only an actual workflow run on a GitHub runner does that. The two are
# recorded separately in the ROADMAP P10.3 ledger row.
#
# Usage (inside the container, repo mounted at /repo):
#   bash tests/containers/smoke.sh
#
# Knobs (env):
#   FS_CTR_REAL       1 = attempt the real install (default 1)
#   FS_CTR_TIMEOUT    seconds allowed for the real install (default 1800)
#   FS_CTR_FAMILY     the package family this image is EXPECTED to resolve
#                     to (rpm|deb|arch). When set, `setup check`'s own
#                     distro row must report it, so a distro-detection
#                     regression fails in the job that covers this image
#                     instead of silently asserting the wrong backend.
#                     Unset skips the assertion (hand-run).
#
# ON THE INCONCLUSIVE RESULT (deliberate, do not "fix" this):
#   The real install downloads >2GB from Flathub, and the CDN was measured
#   varying roughly 10x (the `summary` endpoint flatpak re-fetches per
#   transaction took 36s on one call and ~1s on the next; a full
#   3-app install was observed at 2.2GB / >50min without completing).
#   A fixed deadline therefore conflates "the tool is broken" with "the
#   CDN was slow", and reporting the first as the second is a false
#   statement about coverage.
#   So a timeout prints INCONCLUSIVE, skips the assertions it could not
#   reach, and is recorded as a FAILURE via fx_bad. It is NOT counted as
#   a pass: an unrun assertion reported as satisfied is the P9.5 "a true
#   statement about an empty set" lie. Mutating the fx_bad gate away
#   turns a timed-out run into "18 passed, 0 failed" with rc 0.
#
# Style: no comments inside function bodies (AGENTS.md); asserts come from
# tests/fixtures/lib.sh so the wording and the counter are the same ones
# every other suite in this repo uses.

set -uo pipefail

_this="${BASH_SOURCE[0]}"
if [[ -z "$_this" ]]; then
    printf 'cannot resolve tests/containers/smoke.sh\n' >&2
    exit 1
fi
_this="$(readlink -f -- "$_this" 2>/dev/null || printf '%s' "$_this")"
HERE="$(cd "$(dirname "$_this")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

# shellcheck source=../fixtures/lib.sh
. "$ROOT/tests/fixtures/lib.sh"

if [[ ! -x "$ROOT/setup" ]]; then
    printf 'repo root not found (expected %s/setup)\n' "$ROOT" >&2
    exit 1
fi

export HOME="${HOME:-/root}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
STATE_ROOT="$XDG_STATE_HOME/fedora-setup"

if [[ "$(id -u)" != "0" ]]; then
    printf 'containers/smoke.sh: must run as root (uid 0); got uid %s\n' "$(id -u)" >&2
    exit 1
fi

fx_init "containers/smoke"

# --- fingerprint: path|size|mtime over the trees a run could write ---
# Deliberately not a content checksum: every write this tool makes is an
# atomic temp+rename, which always bumps mtime, so path+size+mtime
# distinguishes "wrote nothing" from "wrote something and cleaned up".
fingerprint() {
    local d
    for d in "$STATE_ROOT" "$HOME" /etc "$ROOT"; do
        if [[ ! -e "$d" ]]; then
            printf 'ABSENT %s\n' "$d"
            continue
        fi
        find "$d" -xdev -path '*/.git' -prune -o -printf '%p|%s|%T@\n' 2>/dev/null
    done | LC_ALL=C sort
}

# --- 1. setup check: real distro detection on this image ---
ctr_id="unknown"
ctr_family="unknown"
if [[ -r /etc/os-release ]]; then
    ctr_id="$(. /etc/os-release 2>/dev/null && printf '%s' "${ID:-unknown}")"
    ctr_family="$(. /etc/os-release 2>/dev/null && printf '%s' "${ID_LIKE:-$ID}")"
    printf 'info: container distro id=%s id_like=%s\n' "$ctr_id" "$ctr_family"
fi

# fx_rc executes the command for us and captures stdout/stderr into
# FX_OUT/FX_ERR, which is what fx_out/fx_out_not then grep.
fx_rc 0 "setup check exits 0" bash -c "cd '$ROOT' && ./setup check"
fx_out "preflight check" "$FX_OUT"
fx_out "PASS distro" "$FX_OUT"
fx_out_not "  - FAIL " "$FX_OUT"
if [[ "$ctr_id" != "unknown" ]]; then
    # Anchored: "distro: debian" must appear as the check's own row, not as
    # a substring of some other line (an unanchored `debian` would also be
    # satisfied by "id_like=debian" in our own info line, which is not
    # evidence the TOOL detected anything).
    fx_out "PASS distro: $ctr_id" "$FX_OUT"
fi

# The CI matrix declares which family each image is supposed to resolve to.
# Asserting it here turns that declaration into a real per-image check
# instead of decoration: if `lib/distro.sh` regressed and mapped debian to
# rpm, the job covering debian is the one that must notice, and a family
# mismatch means every dry-run assertion below ran against the wrong
# package manager. Unset (running the script by hand) skips the assertion.
if [[ -n "${FS_CTR_FAMILY:-}" ]]; then
    fx_out "family $FS_CTR_FAMILY" "$FX_OUT"
fi

# --- 2/3. dry-run: no writes, and the expected render ---
fp_before="$(fingerprint)"

# Capture the dry-run's own exit status without letting set -e style
# pipelines swallow it, and keep the transcript for the greps below.
dry_rc=0
dry_out="$(cd "$ROOT" && ./setup install --profile minimal --yes --dry-run 2>&1)" || dry_rc=$?
printf '%s\n' "$dry_out" >"$FX_OUT"

fp_after="$(fingerprint)"
if [[ "$fp_before" == "$fp_after" ]]; then
    fx_ok
else
    fx_bad "dry-run wrote nothing (filesystem fingerprint identical)"
    printf '  fingerprint diff before/after dry-run:\n' >&2
    diff <(printf '%s\n' "$fp_before") <(printf '%s\n' "$fp_after") >&2 || true
fi

if [[ -e "$STATE_ROOT" ]]; then
    fx_bad "dry-run created no state root"
else
    fx_ok
fi

fx_out "# would run:" "$FX_OUT"
fx_out "\[info\] module: core" "$FX_OUT"
fx_out "\[info\] module: flatpak" "$FX_OUT"

# The flatpak half of `minimal` is DOCUMENTED to fail rc1 in a container
# with no flatpak binary (lib/runner.sh:114-119), because the flatpak
# namespace gates on flatpak_supported even in dry-run. That is a
# deliberate contract, not a regression, so it is asserted by name --
# and asserted in the direction that matters: the run REFUSES loudly
# rather than reporting a completed install.
if command -v flatpak >/dev/null 2>&1; then
    if ((dry_rc == 0)); then
        fx_ok
    else
        fx_bad "dry-run exits 0 with flatpak present (got rc $dry_rc)"
        printf '  dry-run output:\n' >&2
        sed 's/^/    /' "$FX_OUT" >&2 2>/dev/null
    fi
    fx_out "flathub" "$FX_OUT"
    fx_out "run complete" "$FX_OUT"
    # An unresolvable selection must abort at RESOLVE, before any batch runs
    # and before the summary is ever printed. (This is a different stage from
    # the batch-failure abort asserted in the no-flatpak branch below; a
    # mutation that swallows a FAILED flatpak batch is caught there, where
    # the batch really fails. Verified: `plan_install ... || true` scores
    # 13 -> 10 on a no-flatpak image, three FAILs.)
    abort_rc=0
    abort_out="$(cd "$ROOT" && ./setup install --yes --dry-run no-such-module-xyz 2>&1)" || abort_rc=$?
    if ((abort_rc != 0)); then
        fx_ok
    else
        fx_bad "an unresolvable selection refuses rc!=0 (got rc 0)"
    fi
    printf '%s\n' "$abort_out" >"$FX_OUT"
    fx_out "module not found" "$FX_OUT"
    fx_out_not "run complete" "$FX_OUT"
else
    if ((dry_rc != 0)); then
        fx_ok
    else
        fx_bad "dry-run refuses rc!=0 without the flatpak binary (got rc 0)"
    fi
    fx_out "flatpak batch failed" "$FX_OUT"
    fx_out_not "run complete" "$FX_OUT"
    printf 'skip: the flatpak half of the dry-run (documented flatpak_supported gate; see lib/runner.sh:114-119)\n'
fi

# --- 4. real install, where safe ---
# The flatpak apps pull hundreds of MB from Flathub. Measured 2026-10-01:
# bulk CDN throughput is ~3 MB/s, but the `summary` endpoint that flatpak
# re-fetches per transaction took 36s on one call and fast on the next, so
# this step's wall time is dominated by an EXTERNAL service we do not
# control. A fixed `timeout` therefore conflates "the tool is broken" with
# "the CDN was slow" -- and it reports the first as the second, which is
# the exact lie §12 forbids.
#
# So the deadline is treated as an ENVIRONMENT limit, not an assertion:
# on timeout the step prints an explicit inconclusive result and is NOT
# counted as a pass. Only a run that actually completes is asserted.
# CI sets FS_CTR_TIMEOUT generously; raise it if a runner is slow.
if [[ "${FS_CTR_REAL:-1}" != "1" ]]; then
    printf 'skip: real install disabled (FS_CTR_REAL=%s)\n' "${FS_CTR_REAL:-1}"
elif ! command -v flatpak >/dev/null 2>&1; then
    printf 'skip: real install -- no flatpak binary in this image\n'
else
    printf 'info: running REAL install of profile minimal (up to %ss; flatpak pulls ~1GB from Flathub)\n' \
        "${FS_CTR_TIMEOUT:-1800}"
    real_rc=0
    real_out="$(cd "$ROOT" && timeout "${FS_CTR_TIMEOUT:-1800}" ./setup install --profile minimal --yes 2>&1)" || real_rc=$?
    printf '%s\n' "$real_out" >"$FX_OUT"
    if ((real_rc == 124)); then
        # 124 = the timeout killed it. NOT a tool verdict: the transcript
        # shows the flatpak batch mid-download, which is a network wait.
        printf 'INCONCLUSIVE: real install exceeded %ss while Flathub was downloading.\n' \
            "${FS_CTR_TIMEOUT:-1800}"
        printf '  This is an environment limit, not a pass and not a tool failure.\n'
        printf '  The tool was still working when the deadline hit (transcript below).\n'
        tail -n 5 "$FX_OUT" | sed 's/^/    /'
        FS_CTR_REAL_INCONCLUSIVE=1
    elif ((real_rc != 0)); then
        fx_bad "real install minimal exits 0 (got rc $real_rc)"
        printf '  real install output:\n' >&2
        sed 's/^/    /' "$FX_OUT" >&2 2>/dev/null
        FS_CTR_REAL_INCONCLUSIVE=1
    else
        fx_out "run complete" "$FX_OUT"
        fx_out "  - 2 modules ok" "$FX_OUT"
        fx_out "artifacts in " "$FX_OUT"
    fi
    if [[ -d "$STATE_ROOT/modules" ]]; then
        fx_ok
    else
        if [[ "${FS_CTR_REAL_INCONCLUSIVE:-0}" != "1" ]]; then
            fx_bad "real install wrote the module registry ($STATE_ROOT/modules)"
        fi
    fi
    if compgen -G "$STATE_ROOT/logs/run-*.log" >/dev/null 2>&1; then
        fx_ok
    else
        if [[ "${FS_CTR_REAL_INCONCLUSIVE:-0}" != "1" ]]; then
            fx_bad "real install produced a run log under $STATE_ROOT/logs"
        fi
    fi
    # Idempotency on a REAL installed host: a second run must skip both
    # already-installed modules. This is the strongest container-only
    # check available -- the mock suite cannot reach it. Only meaningful
    # once the first install actually completed, so a timed-out first run
    # skips it rather than reporting a meaningless failure.
    if [[ "${FS_CTR_REAL_INCONCLUSIVE:-0}" == "1" ]]; then
        printf 'skip: idempotency re-run -- the first install did not complete, so there is no installed state to resume from\n'
    else
        second_rc=0
        second_out="$(cd "$ROOT" && timeout "${FS_CTR_TIMEOUT:-1800}" ./setup install --profile minimal --yes 2>&1)" || second_rc=$?
        printf '%s\n' "$second_out" >"$FX_OUT"
        if ((second_rc == 0)); then
            fx_ok
        else
            fx_bad "second real install exits 0 (got rc $second_rc)"
            printf '  second-run output:\n' >&2
            sed 's/^/    /' "$FX_OUT" >&2 2>/dev/null
        fi
        fx_out "already completed" "$FX_OUT"
        # fx_* captures into $FX_OUT and only prints it on failure, so a
        # green run leaves no transcript of what the run actually did. Print
        # it: the assert count proves the strings were present, but a reader
        # (and a reviewer) must be able to SEE them.
        printf -- '--- idempotency re-run transcript ---\n'
        sed 's/^/  | /' "$FX_OUT"
    fi
fi

# --- 5. GNOME: explicitly not covered, with a reason ---
# Never claim a headless container exercised the GNOME path. The P6.5
# capability gate skips these modules anyway (no gsettings, no session
# bus); saying so out loud is the entire point of this block.
printf 'skip: GNOME modules (gnome-base/gnome-extensions/gnome-theme) --\n'
printf '  headless container has no session bus, display, or gsettings schema;\n'
printf '  the P6.5 capability gate skips them by design and this suite does\n'
printf '  not claim coverage of them.\n'

# An inconclusive real install must NOT report green. The asserts above were
# skipped, not satisfied, so a summary of "N passed, 0 failed" would be a
# false claim about coverage -- the P9.5 "a true statement about an empty
# set" lie. Count it as a failure and name it, so CI goes red on a slow CDN
# instead of quietly testing less than it reports.
if [[ "${FS_CTR_REAL_INCONCLUSIVE:-0}" == "1" ]]; then
    fx_bad "real install completed (inconclusive: network deadline, not a pass)"
fi

fx_summary
