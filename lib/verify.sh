#!/usr/bin/env bash
# lib/verify.sh - `./setup verify` audit (P9.2).
# Depends on lib/io.sh, lib/status.sh; verify_run additionally needs
# lib/distro.sh, lib/lists.sh, lib/modules.sh, lib/depgraph.sh, lib/pkg.sh,
# lib/profiles.sh and lib/state.sh sourced first. depgraph is not optional:
# profile_resolve calls dep_toposort, so a --profile selection without it dies
# on a raw "command not found". Bash >= 4.3 safe (loop bounds from $#, every
# empty-array expansion guarded, no namerefs).
#
# WHAT IS CHECKED, AND WHO CHECKES IT. Two layers, deliberately separated by
# what is knowable rather than by preference:
#   * GENERIC checks are driven by the module's own declarative list files --
#     the SYSTEM list set via pkg_verify_packages (the P3.9 primitive, which
#     exists for exactly this) and the FLATPAK set via the flatpak backend.
#     Anything a list file can express is therefore covered for EVERY module,
#     including the ones with no hooks.sh at all, and the hook-local copies
#     in apps/media stop being the only way a flatpak is ever checked. The
#     P7.5 flatpak-alternative id is part of that set: when a module declares
#     MODULE_FLATPAK_ALT_ID and its seam is truthy, the runner puts that id in
#     the FLATPAK namespace, so verify has to ask about it too or a seam-on
#     module reports a clean sheet with no flatpak row at all. It is deduped
#     against the module's own flatpaks.list, because AGENTS s12 makes that
#     list ADDITIVE to the alternative -- additive, not duplicated.
#   * PER-MODULE verify() hooks cover what no list file can express:
#     gsettings values and extensions (gnome-*), fonts and managed dotfiles
#     (fonts/terminal/git), the Chrome desktop entry, and the dns/locale
#     system state. These hooks already existed (P6-P8) but nothing ever
#     CALLED them; wiring them is the other half of this task.
# The categories the ROADMAP lists map as: packages + flatpaks -> generic;
# gsettings/extensions/fonts/managed files -> hooks; repo files -> the
# flathub remote probe below, plus hook-owned repo state. A module that ships
# a repository through prerepo.sh and NO hooks.sh (vscode) therefore has no
# repo-file check: the repo path is not derivable from module metadata, and
# inventing a contract key for it is an AGENTS s13 architecture change, not a
# P9.2 decision. Recorded as a carried gap, not silently skipped.
#
# READ-ONLY. This tool never installs, never removes, never marks, never backs
# up and never calls sudo -- the functions that could (fs_backup, fs_install,
# fs_managed_block, state_module_mark, state_note, run_sudo, sudo_exec) are not
# even sourced on the verify path, and lib/run.sh and lib/sudo.sh are not
# sourced at all. It does not create the state root either: like check, it
# probes state_root_path and only calls state_init when a root already exists,
# so auditing a host that never installed anything leaves that host untouched.
# Two honest limits on that claim, stated rather than glossed: (a) on a state
# root that EXISTS but is empty, state_init creates the four subdirectories
# (backups/ logs/ modules/ notes/) -- the same behaviour lib/check.sh documents
# and accepts, and it is not a new root; (b) the audit shells out to the
# vendor's own read-only CLIs, and a third-party binary may initialise its own
# per-user cache on first use (a real `flatpak remotes`/`info` creates
# ~/.local/share/flatpak and ~/.cache/flatpak on a host that never ran flatpak).
# So the guarantee is "verify invokes no installing or removing subcommand",
# not "verify touches nothing on disk anywhere".
# Dry-run is NOT a purity concern here -- every probe is a read-only query and
# lib/pkg.sh's own header sanctions querying in dry mode -- so the generic
# checks run in dry mode. Hooks are the exception: each one self-refuses under
# FS_DRY_RUN and returns 0, and a 0 that means "I did not look" must never be
# rendered as PASS, so that rc 0 is reported as a skipped WARN rather than
# "verify() passed". The rewrite is deliberately limited to the rc==0 arm: a
# hook that reports anything else in dry mode (a failure, or one of the
# reserved 90/91 signals) still renders its own row, because downgrading those
# to "skipped" would hide a real finding.
#
# EXIT CODE. The rule is lib/status.sh's, not a second copy: any FAIL -> rc1,
# WARNs -> rc0. Every row and the verdict come from the same STATUS_WORST.
#
# ROWS. Two rows per module carry its id as a prefix -- "<id>:packages",
# "<id>:flatpaks", "<id>:hook" -- plus one bare "<id>" row for a module with
# nothing at all to look at. The prefix is load-bearing: several modules
# contribute a package row, and an unprefixed "FAIL packages:" cannot say which
# module failed. A generic layer that cannot determine its answer (an unreadable
# list) is a FAIL row, never a silently absent one, and a module with no list
# files and no verify() says so in one row instead of pretending to pass.
#
# A recorded module the tree no longer carries is a FAIL ROW, not an abort:
# the registry is a historical record of what an older version of this tool
# installed, so a stale entry is a fact to report about the machine, not a
# mistake by the user typing a command. Explicit ids and a --profile closure
# still fail closed with a message -- there the user named the module.
#
# SELECTION. Explicit ids beat everything; then --profile's resolved closure
# (deps included, so a profile audits what it would actually install); then
# the modules recorded in the P4.6 registry, which is what a user asking
# "verify" means on a machine that has been set up; and only when that
# registry is empty or absent does it fall back to every module in the tree.
# No selection UI and no risk gate: unlike install, verify executes nothing,
# so there is nothing destructive to consent to, and an audit that could
# prompt would be unauditable in a script.
#
# KNOWN LIMITATION, stated rather than papered over. A hook that cannot check
# its subject returns 0 (locale with no localectl, chrome on arch, the gnome
# hooks behind gnome_require_capable) because that is the hook contract
# written in P6-P8, and 0 is indistinguishable from a real pass. Those rows
# therefore render PASS. Distinguishing them needs a contract change (a WARN
# signal on the hook return), which is an owner decision, so it is carried
# rather than invented here; the generic layer is what keeps the gap small,
# since the declarative categories are still checked for those modules.

_VERIFY_FAMILY=""
_VERIFY_MODULES_DIR=""
_VERIFY_PROFILES_DIR=""

_verify_need_root() {
    local root="${1:-}"
    if [[ -z "$root" ]]; then
        io_error "verify_run requires the repository root"
        return 1
    fi
    return 0
}

# _verify_registry_ids prints the ids recorded as installed, sorted. The
# registry is read only when a state root already exists; a host with no
# state has nothing recorded, which is a normal state, not an error.
_verify_registry_ids() {
    local root="" id=""
    root="$(state_root_path)" || return 0
    if [[ ! -d "$root" ]]; then
        return 0
    fi
    FS_STATE_BASE=""
    FS_STATE_DIR=""
    if ! state_init; then
        io_error "state dir unusable; cannot read the module registry"
        return 1
    fi
    for id in "$root/modules"/*; do
        [[ -f "$id" ]] || continue
        id="${id##*/}"
        [[ "${id:0:1}" == "." ]] && continue
        if state_module_check "$id"; then
            printf '%s\n' "$id"
        fi
    done | LC_ALL=C sort -u
    return 0
}

_verify_all_ids() {
    local dir=""
    for dir in "$_VERIFY_MODULES_DIR"/*; do
        [[ -d "$dir" ]] || continue
        [[ "${dir##*/}" == .* ]] && continue
        printf '%s\n' "${dir##*/}"
    done | LC_ALL=C sort
}

# _verify_resolve prints the audit set, one id per line, already validated
# against the module tree. rc1 on a bad id, a missing module, or a profile
# that will not resolve -- the same fail-loud contract as install.
_verify_resolve() {
    local root="$1" out="" id="" dir=""
    local -a ids=()
    local -a want=()
    want=(${FS_CMD_ARGS[@]+"${FS_CMD_ARGS[@]}"})
    if ((${#want[@]} > 0)); then
        for id in "${want[@]}"; do
            module_valid_id "$id" || {
                io_error "invalid module id: $id"
                return 1
            }
            [[ -d "$_VERIFY_MODULES_DIR/$id" ]] || {
                io_error "module not found: $id"
                return 1
            }
            ids+=("$id")
        done
    elif [[ -n "${FS_PROFILE:-}" ]]; then
        out="$(profile_resolve "$_VERIFY_MODULES_DIR" "$_VERIFY_PROFILES_DIR" "$FS_PROFILE")" || return 1
        if [[ -n "$out" ]]; then
            while IFS= read -r id; do
                [[ -n "$id" ]] || continue
                ids+=("$id")
            done <<<"$out"
        fi
    else
        out="$(_verify_registry_ids)" || return 1
        if [[ -n "$out" ]]; then
            while IFS= read -r id; do
                [[ -n "$id" ]] || continue
                if [[ -d "$_VERIFY_MODULES_DIR/$id" ]]; then
                    ids+=("$id")
                else
                    ids+=("!$id")
                fi
            done <<<"$out"
        else
            while IFS= read -r id; do
                [[ -n "$id" ]] || continue
                ids+=("$id")
            done < <(_verify_all_ids)
        fi
    fi
    ((${#ids[@]} > 0)) || {
        io_error "no modules to verify"
        return 1
    }
    for id in "${ids[@]}"; do
        if [[ "${id:0:1}" == "!" ]]; then
            printf '%s\n' "$id"
            continue
        fi
        dir="$_VERIFY_MODULES_DIR/$id"
        module_validate "$dir" "$_VERIFY_FAMILY" || return 1
        printf '%s\n' "$id"
    done
    return 0
}

# _verify_system_packages checks the module's SYSTEM list set. The
# flatpak-alternative pair suppresses it exactly as the runner's PLAN stage
# does: a truthy seam means the module contributes nothing to the SYSTEM
# namespace, so its SYSTEM list files are not even read and a stale native id
# in them can never be reported as missing.
_verify_system_packages() {
    local id="$1" dir="$2" alt="" out="" p="" missing=""
    alt="$(module_flatpak_alt)" || return 1
    if [[ -n "$alt" ]]; then
        return 0
    fi
    out="$(list_packages "$dir" "$_VERIFY_FAMILY")" || return 1
    [[ -n "$out" ]] || return 0
    local -a pkgs=()
    while IFS= read -r p; do
        [[ -n "$p" ]] || continue
        pkgs+=("$p")
    done <<<"$out"
    ((${#pkgs[@]} > 0)) || return 0
    if ! pkg_supported; then
        status_row "$STATUS_WARN" "$id:packages" \
            "cannot check ${#pkgs[@]} package(s): no package backend available"
        return 0
    fi
    while IFS= read -r p; do
        case "$p" in
        "missing: "*) missing+="${p#missing: } " ;;
        esac
    done < <(pkg_verify_packages "${pkgs[@]}" 2>/dev/null) || :
    if [[ -n "$missing" ]]; then
        status_row "$STATUS_FAIL" "$id:packages" "missing: ${missing% }"
    else
        status_row "$STATUS_PASS" "$id:packages" "all ${#pkgs[@]} present"
    fi
    return 0
}

_verify_flatpaks() {
    local id="$1" dir="$2" out="" app="" alt="" missing=""
    local NEWLINE=$'\n'
    out="$(list_flatpaks "$dir")" || return 1
    alt="$(module_flatpak_alt)" || return 1
    if [[ -n "$alt" ]]; then
        if [[ -z "$out" ]] || ! grep -qxF -- "$alt" <<<"$out"; then
            out="${out:+$out$NEWLINE}$alt"
        fi
    fi
    [[ -n "$out" ]] || return 0
    local -a apps=()
    while IFS= read -r app; do
        [[ -n "$app" ]] || continue
        apps+=("$app")
    done <<<"$out"
    ((${#apps[@]} > 0)) || return 0
    if ! command -v flatpak >/dev/null 2>&1; then
        status_row "$STATUS_WARN" "$id:flatpaks" \
            "cannot check ${#apps[@]} app(s): flatpak CLI not in PATH"
        return 0
    fi
    for app in "${apps[@]}"; do
        if ! (
            FS_PKG_BACKEND=flatpak
            export FS_PKG_BACKEND
            pkg_query_installed "$app"
        ) >/dev/null 2>&1; then
            missing+="$app "
        fi
    done
    if [[ -n "$missing" ]]; then
        status_row "$STATUS_FAIL" "$id:flatpaks" "not installed: ${missing% }"
    else
        status_row "$STATUS_PASS" "$id:flatpaks" "all ${#apps[@]} present"
    fi
    return 0
}

# _VERIFY_HOOK_NONE / _VERIFY_HOOK_UNDEFINED are this file's OWN "not
# applicable" signals. They are 90/91 and RESERVED: every other value is a hook
# verdict, because a module's verify() is free to return anything and an audit
# that reinterprets a hook's failure as "there is no hook" is worse than no
# audit. An earlier revision used 2/3 and a verify() returning 2 was reported as
# WARN "module has no verify() hook" with rc 0 -- a real failure downgraded to
# a warning and a clean exit. 90/91 are never used by any shipped hook (all of
# them return 0 or 1) and are documented here so a future module does not
# adopt them by accident; even that residual collision fails LOUD (a "no
# verify() hook" WARN), never silent.
_VERIFY_HOOK_NONE=90
_VERIFY_HOOK_UNDEFINED=91

# _verify_hook runs a module's verify() in a subshell, mirroring the runner's
# hook protocol exactly: FS_MODULE_FAMILY is EXPORTED so the hook never
# re-detects the distro, and module_load runs BEFORE the hook file is sourced
# so the hook sees its OWN metadata rather than whatever loaded last. The
# `|| exit 1` guards matter because the caller runs this as the RIGHT-HAND SIDE
# of `||`, which suspends errexit for the whole subshell, so a hook must not lean
# on a bare `set -e` to stop itself. lib/runner.sh's hooks stage is the
# right-hand side of `||` too, for the same reason.
_verify_hook() {
    local dir="$1" rc=0
    if ! module_has_hooks "$dir"; then
        return "$_VERIFY_HOOK_NONE"
    fi
    (
        FS_MODULE_FAMILY="$_VERIFY_FAMILY"
        export FS_MODULE_FAMILY
        module_load "$dir" strict || exit 1
        source "$dir/hooks.sh"
        declare -F verify >/dev/null 2>&1 || exit "$_VERIFY_HOOK_UNDEFINED"
        verify
    )
    rc=$?
    return "$rc"
}

# _verify_remote is the repo-file check that IS derivable: AGENTS s3 makes
# `flatpak remote-add --if-not-exists flathub` a precondition for every
# flatpak install, so a missing remote is the one repository failure a
# read-only audit can prove. It is a single direct read-only `flatpak remotes`
# call rather than a backend call because the backend op table has no remote
# query and adding one would mean every backend growing a function it has no
# use for (carried as a P3 ticket). WARN, not FAIL: a host with no flatpak at
# all is not broken, it just has no remotes to be missing.
_verify_remote() {
    local remotes="" name=""
    if ! command -v flatpak >/dev/null 2>&1; then
        return 0
    fi
    remotes="$(flatpak remotes --columns=name 2>/dev/null)" || remotes=""
    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        if [[ "$name" == "flathub" ]]; then
            status_row "$STATUS_PASS" "repo:flathub" "remote present"
            return 0
        fi
    done <<<"$remotes"
    status_row "$STATUS_WARN" "repo:flathub" \
        "remote flathub is not configured; every flatpak install will fail"
    return 0
}

_verify_one() {
    local dir="$1" id="$2" rc=0 before=0 generic=0
    module_load "$dir" strict || {
        status_row "$STATUS_FAIL" "$id" "module metadata is invalid"
        return 0
    }
    before=${#STATUS_ROWS[@]}
    _verify_system_packages "$id" "$dir" || status_row "$STATUS_FAIL" \
        "$id:packages" "the package list could not be read"
    _verify_flatpaks "$id" "$dir" || status_row "$STATUS_FAIL" \
        "$id:flatpaks" "the flatpak list could not be read"
    generic=$((${#STATUS_ROWS[@]} - before))
    rc=0
    _verify_hook "$dir" || rc=$?
    if ((rc == _VERIFY_HOOK_NONE && generic == 0)); then
        status_row "$STATUS_WARN" "$id" \
            "nothing to verify (no list files, no verify() hook)"
        return 0
    fi
    case "$rc" in
    0)
        if ((${FS_DRY_RUN:-0} == 1)); then
            status_row "$STATUS_WARN" "$id:hook" \
                "skipped (dry run; the hook refuses to probe)"
        else
            status_row "$STATUS_PASS" "$id:hook" "verify() passed"
        fi
        ;;
    "$_VERIFY_HOOK_NONE")
        status_row "$STATUS_WARN" "$id:hook" "module has no verify() hook"
        ;;
    "$_VERIFY_HOOK_UNDEFINED")
        status_row "$STATUS_WARN" "$id:hook" "hooks.sh defines no verify()"
        ;;
    *)
        status_row "$STATUS_FAIL" "$id:hook" "verify() reported problems (rc $rc)"
        ;;
    esac
    return 0
}

verify_run() {
    local root="${1:-}" id_list="" id="" dir=""
    _verify_need_root "$root" || return 1
    _VERIFY_MODULES_DIR="${FS_MODULES_DIR:-$root/modules}"
    _VERIFY_PROFILES_DIR="${FS_PROFILES_DIR:-$root/profiles}"
    if [[ ! -d "$_VERIFY_MODULES_DIR" ]]; then
        io_error "modules directory not found: $_VERIFY_MODULES_DIR"
        return 1
    fi
    if [[ -z "${FS_DISTRO_FAMILY:-}" ]]; then
        if ! declare -F distro_detect >/dev/null 2>&1; then
            io_error "verify needs lib/distro.sh sourced (or FS_DISTRO_FAMILY set)"
            return 1
        fi
        distro_detect || return 1
    fi
    _VERIFY_FAMILY="${FS_DISTRO_FAMILY:-}"
    case "$_VERIFY_FAMILY" in
    rpm | deb | arch) ;;
    *)
        io_error "unsupported family: $_VERIFY_FAMILY"
        return 1
        ;;
    esac
    id_list="$(_verify_resolve "$root")" || return 1
    status_reset
    _verify_remote
    while IFS= read -r id; do
        [[ -n "$id" ]] || continue
        if [[ "${id:0:1}" == "!" ]]; then
            status_row "$STATUS_FAIL" "${id:1}" \
                "recorded as installed, but the module directory is gone"
            continue
        fi
        dir="$_VERIFY_MODULES_DIR/$id"
        _verify_one "$dir" "$id"
    done <<<"$id_list"
    status_report "verify" "verify" "or re-run install for them"
    status_rc
}
