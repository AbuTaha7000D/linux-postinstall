#!/usr/bin/env bash
# lib/check.sh - `./setup check` preflight (P9.1).
# Depends on lib/io.sh; check_run additionally needs lib/distro.sh,
# lib/sudo.sh and lib/state.sh sourced first. Bash >= 4.3 safe (loop
# bounds from $#, every empty-array expansion guarded, no namerefs).
#
# READ-ONLY CONTRACT. A preflight creates no state root and escalates
# nothing. `state_init` is the only mkdir in the tree, so it is called ONLY
# when the state root already exists -- the P4.6 status registry is then read
# with state_module_check. A host that has never installed anything therefore
# keeps having no state dir after `check`; that is asserted, because an
# earlier revision called state_init unconditionally and silently created
# one. When the root DOES exist, state_init still creates its own four
# subdirectories (logs/ modules/ backups/ notes/) as part of validating it;
# that is state.sh's own behaviour inside a dir the user already has, and is
# the one creation this path can make. The probe itself is state.sh's own
# read-only `state_root_path`, so the path checked here and the path
# state_init would use cannot diverge. The probe RUNS in a subshell -- which is
# what makes a failure inside it visible at all -- and only its stdout is
# captured into a global; the FAIL row is then raised by the caller, OUTSIDE
# that subshell. Raising the row inside the substitution instead is the bug
# this shape exists to prevent: STATUS_WORST would be updated on the subshell's
# copy and lost, silently reporting PASS on a host with no resolvable state
# base. So the rule is: probe in the subshell, report in the caller.
# The privilege check renders sudo_detect's canonical policy globals and
# nothing else: it reads FS_SUDO_AVAILABLE together with FS_SUDO_PASSWORD
# so the password-required state is reported as itself rather than being
# flattened into the same answer as "no sudo at all", and it never runs a
# probe of its own. `sudo -n true` cannot prompt and cannot hang, and the
# prompting half (sudo_refresh) is deliberately NOT reached from here: a
# diagnostic that hung for a password would be unusable.
#
# EXIT CODE. The rule lives in lib/status.sh (shared with `setup verify`,
# P9.2) and is deliberately not restated as a second implementation here:
# one source of truth, the worst level found decides. Any FAIL -> rc1;
# otherwise rc0, WARNs included. A warning is by definition "degraded but not
# blocking", so folding WARN into a non-zero rc would make the word a lie.
# Concretely an offline host is rc0 (flathub/GitHub rows are WARN) while a
# missing sudo or an unknown distro is rc1.
#
# DRY RUN. FS_DRY_RUN=1 suppresses the two probes that leave the machine --
# the network HEAD requests and the sudo policy -- and reports those rows as
# "skipped (dry run probes nothing)" rather than guessing, so a dry-run
# report never asserts something it did not verify. Local, free probes
# (reading /etc/os-release, `command -v`, `df`) still run: they touch
# nothing and are the point of a preflight.
#
# SEAMS. FS_DISTRO_FILE (read-only os-release input) and FS_PKG_BACKEND are
# honored for consistency with every other command; FS_CHECK_MIN_FREE_MB
# (default 2048, positive integer or the default is used) and
# FS_CHECK_NET_TIMEOUT (default 5 seconds) are added by this task and are
# both load-bearing in tests/fixtures/check.sh. Network reachability is NOT
# given a seam: the probe client is selected from PATH (curl, then wget),
# so the offline/online/no-client arms are driven by PATH alone and the
# fixture needs no special-casing to reach them. FS_DISTRO_FAMILY is
# deliberately NOT honored here -- reporting what was actually detected is
# the entire job of this command, so detection always runs.

# lib/status.sh owns the levels and the row/verdict/exit-code rule; these
# aliases keep every row call in this file reading in check's own vocabulary.
_CHECK_PASS="$STATUS_PASS"
_CHECK_WARN="$STATUS_WARN"
_CHECK_FAIL="$STATUS_FAIL"
_CHECK_STATE_ROOT=""

_check_row() {
    status_row "$1" "$2" "$3"
}

_check_distro() {
    if ! distro_detect; then
        _check_row "$_CHECK_FAIL" "distro" "detection failed; see the error above"
        return 0
    fi
    if [[ -z "$FS_DISTRO_FAMILY" ]]; then
        _check_row "$_CHECK_FAIL" "distro" "unsupported family for id '$FS_DISTRO_ID'"
        return 0
    fi
    _check_row "$_CHECK_PASS" "distro" \
        "$FS_DISTRO_ID (family $FS_DISTRO_FAMILY, pkgmgr ${FS_DISTRO_PKGMGR:-unknown})"
    return 0
}

_check_pkgmgr() {
    local pm=""
    if [[ "${FS_PKG_BACKEND:-}" == "mock" ]]; then
        _check_row "$_CHECK_WARN" "pkgmgr" "not checked (FS_PKG_BACKEND=mock)"
        return 0
    fi
    pm="${FS_DISTRO_PKGMGR:-}"
    if [[ -z "$pm" ]]; then
        _check_row "$_CHECK_FAIL" "pkgmgr" "no package manager resolved for this distro"
        return 0
    fi
    if command -v "$pm" >/dev/null 2>&1; then
        _check_row "$_CHECK_PASS" "pkgmgr" "$pm present in PATH"
    else
        _check_row "$_CHECK_FAIL" "pkgmgr" "$pm not found in PATH; system modules cannot install"
    fi
    return 0
}

_check_privileges() {
    local euid="${FS_EUID:-$EUID}"
    if ((euid == 0)); then
        _check_row "$_CHECK_PASS" "privileges" "running as root (euid 0); no sudo needed"
        return 0
    fi
    if ((FS_DRY_RUN == 1)); then
        _check_row "$_CHECK_WARN" "privileges" "skipped (dry run probes nothing)"
        return 0
    fi
    sudo_detect
    if ((FS_SUDO_AVAILABLE == 1)) && ((FS_SUDO_PASSWORD != 1)); then
        _check_row "$_CHECK_PASS" "privileges" "non-root with passwordless sudo"
    elif ((FS_SUDO_AVAILABLE == 1)); then
        _check_row "$_CHECK_WARN" "privileges" "non-root; sudo requires a password, so privileged steps prompt for one"
    else
        _check_row "$_CHECK_FAIL" "privileges" "not root and no sudo in PATH; privileged modules cannot run"
    fi
    return 0
}

_check_flatpak() {
    if command -v flatpak >/dev/null 2>&1; then
        _check_row "$_CHECK_PASS" "flatpak" "present in PATH"
    else
        _check_row "$_CHECK_WARN" "flatpak" "not in PATH; GUI app modules will be skipped"
    fi
    return 0
}

_check_http_client() {
    if command -v curl >/dev/null 2>&1; then
        printf 'curl'
    elif command -v wget >/dev/null 2>&1; then
        printf 'wget'
    else
        printf ''
    fi
}

_check_probe_url() {
    local url="$1" client="$2" tmo="$3"
    case "$client" in
    curl) curl -fsS -I -o /dev/null --max-time "$tmo" -- "$url" >/dev/null 2>&1 ;;
    wget) wget -q --spider --timeout="$tmo" -- "$url" >/dev/null 2>&1 ;;
    *) return 2 ;;
    esac
}

_check_net_one() {
    local label="$1" url="$2" client="$3" tmo="$4"
    if _check_probe_url "$url" "$client" "$tmo"; then
        _check_row "$_CHECK_PASS" "network:$label" "reachable ($url)"
    else
        _check_row "$_CHECK_WARN" "network:$label" "unreachable ($url); downloads and remotes will fail"
    fi
    return 0
}

_check_network() {
    local client tmo=""
    if ((FS_DRY_RUN == 1)); then
        _check_row "$_CHECK_WARN" "network" "skipped (dry run probes nothing)"
        return 0
    fi
    client="$(_check_http_client)"
    if [[ -z "$client" ]]; then
        _check_row "$_CHECK_WARN" "network" "no curl or wget in PATH; reachability unknown"
        return 0
    fi
    tmo="${FS_CHECK_NET_TIMEOUT:-5}"
    if [[ ! "$tmo" =~ ^[0-9]+$ ]] || ((tmo < 1)); then
        tmo=5
    fi
    _check_net_one "flathub" "https://dl.flathub.org/repo/flathub.flatpakrepo" "$client" "$tmo"
    _check_net_one "github" "https://github.com" "$client" "$tmo"
    return 0
}

_check_disk() {
    local want="${FS_CHECK_MIN_FREE_MB:-2048}" free=""
    if [[ ! "$want" =~ ^[0-9]+$ ]] || ((want < 1)); then
        want=2048
    fi
    free="$(df -Pm / 2>/dev/null | awk 'NR==2 {print $4}')"
    if [[ ! "$free" =~ ^[0-9]+$ ]]; then
        _check_row "$_CHECK_WARN" "disk" "cannot determine free space on /"
        return 0
    fi
    if ((free >= want)); then
        _check_row "$_CHECK_PASS" "disk" "$free MB free on / (need $want MB)"
    else
        _check_row "$_CHECK_WARN" "disk" "$free MB free on / (want $want MB); installs may fail"
    fi
    return 0
}

_check_state_root() {
    _CHECK_STATE_ROOT="$(state_root_path)" || {
        _CHECK_STATE_ROOT=""
        return 1
    }
    return 0
}

_check_installed() {
    local dir="$1" id="" n=0
    local -a done_ids=()
    if [[ ! -d "$dir" ]]; then
        _check_row "$_CHECK_WARN" "modules" "module directory not found: $dir"
        return 0
    fi
    if ! _check_state_root; then
        _check_row "$_CHECK_FAIL" "state" \
            "no state base: set HOME, XDG_STATE_HOME or FS_HOME, or installs cannot record progress"
        return 0
    fi
    if [[ ! -d "$_CHECK_STATE_ROOT" ]]; then
        _check_row "$_CHECK_PASS" "modules" "no state dir yet; nothing recorded as installed"
        return 0
    fi
    FS_STATE_BASE=""
    FS_STATE_DIR=""
    if ! state_init; then
        _check_row "$_CHECK_FAIL" "state" "state dir unusable; installs cannot record progress"
        return 0
    fi
    for id in "$dir"/*; do
        [[ -d "$id" ]] || continue
        id="${id##*/}"
        [[ "${id:0:1}" == "." ]] && continue
        if state_module_check "$id"; then
            done_ids+=("$id")
            n=$((n + 1))
        fi
    done
    if ((n == 0)); then
        _check_row "$_CHECK_PASS" "modules" "none recorded as installed yet"
    else
        _check_row "$_CHECK_PASS" "modules" "$n recorded as installed: ${done_ids[*]}"
    fi
    return 0
}

check_run() {
    local root="${1:-}"
    if [[ -z "$root" ]]; then
        io_error "check_run requires the repository root"
        return 1
    fi
    status_reset
    _check_distro
    _check_pkgmgr
    _check_privileges
    _check_flatpak
    _check_network
    _check_disk
    _check_installed "${FS_MODULES_DIR:-$root/modules}"
    status_report "preflight check" "preflight" "before installing"
    status_rc
}
