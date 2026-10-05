#!/usr/bin/env bash
# modules/gnome-extensions/hooks.sh - GNOME Shell extension handling (P6.3).
# Sourced INSIDE the runner's hook subshell (lib/runner.sh stage 4); run()
# is called once. The runner provides io_*/run_cmd + FS_* seams; this hook
# sources lib/gnome.sh (probe layer) and lib/lists.sh (extensions.list /
# browse.list parsing) itself.
#
# run() strategy (prototype guard + ROADMAP P6.3):
#   1. Capability gate -- gnome_require_capable (P6.5): non-GNOME session,
#      SSH/headless context, or no gsettings on PATH means graceful skip
#      (io_info "skipped (not GNOME)", rc0); --force (FS_GNOME_FORCE=1)
#      overrides and runs anyway.
#   2. Tool gate -- gnome-extensions missing from PATH fails closed (rc1)
#      before anything else runs (only reachable once gsettings is present).
#   3. Real mode probes `gnome-shell --version` and the installed / enabled
#      extension uuids ONCE (both probes fail closed rc1: enabling safely
#      requires knowing the current state), then enables each curated
#      extensions.list uuid that is installed but not yet enabled through
#      run_cmd `gnome-extensions enable <uuid>` -- every enabled call is
#      audited; a re-run writes nothing (already-enabled uuids no-op).
#      Installed-but-not-curated uuids are never touched. A not-installed
#      curated uuid is reported (io_info) and skipped -- this module never
#      auto-installs a user extension.
#   4. Compatibility notes (report only, never a write): the probed shell
#      version is printed once; for each INSTALLED uuid that has a row in
#      the compat map (config/extensions.compat, FS_GNOME_COMPAT_FILE seam;
#      absent or malformed rows are dropped) whose shell-major window does
#      not contain the probed major, io_warn fires. An unparsable version
#      skips the notes (io_info) and never fails the module.
#   5. Browse (opt-in via --browse => FS_GNOME_BROWSE=1): at most the first
#      two browse.list URLs are opened, in order, once, SEQUENTIALLY through
#      run_cmd (prototype bug fix: the old script forked xdg-open in a loop
#      over 20 URLs). Even a longer browse.list never exceeds two. Real mode
#      skips opening when xdg-open is absent from PATH (io_info manual-open
#      hint); dry-run renders its plan lines unconditionally (same planning
#      convention as gnome-base's dry-mode slot approximation). Malformed
#      URLs (not http/https) fail rc1 before any open.
#   6. Dry-run cannot probe, so it plans `# would run: gnome-extensions
#      enable <uuid>` for every managed uuid in extensions.list order, skips
#      compatibility notes (io_info explaining why), and renders the browse
#      plan. Uuid validation ([A-Za-z0-9._@-]) happens in both modes so dry
#      and real agree; a malformed uuid fails rc1 before any write.
#   7. extensions.list itself is required (missing file fails loudly via
#      list_parse); an empty or comment-only file is a graceful no-op.
#   8. The core loop uses keep-going run_cmd (no --stop): a failed
#      `gnome-extensions enable` / probe is audited (run.log erring line,
#      io_error with the reason) but the module still returns 0 and the
#      runner marks it completed -- a swallowed failure is NOT retried
#      until the state registry is reset. Deliberate: consistent with the
#      established keep-going decision (AGENTS §12) and P6.2's gnome-base.
#   9. gnome_extensions_list output is treated as bare uuid lines (no
#      state/number columns); anything else is dropped by the uuid filter
#      (see lib/gnome.sh header).

run() {
    local root dir cfile="" browse=""
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || return 1
    source "$root/lib/gnome.sh"
    source "$root/lib/lists.sh"
    gnome_require_capable gnome-extensions || return "$MODULE_HOOK_SKIP"
    if ! gnome_extensions_available; then
        io_error "gnome-extensions: gnome-extensions not found on PATH"
        return 1
    fi
    dir="$root/modules/gnome-extensions"
    cfile="${FS_GNOME_COMPAT_FILE:-$root/config/extensions.compat}"
    if ((FS_DRY_RUN == 1)); then
        _gnome_ext_dry "$dir" || return 1
    else
        _gnome_ext_real "$dir" "$cfile" || return 1
    fi
    browse="${FS_GNOME_BROWSE:-0}"
    if [[ "$browse" == 1 ]]; then
        _gnome_ext_browse "$dir" || return 1
    fi
    return 0
}

# verify() is the P6.5 read-only diagnostic (wired to `./setup verify` in
# P9.2): it re-gates, refuses to run in dry-run (verification reads probe the
# live extension list), then requires every curated extensions.list uuid to be
# BOTH installed and enabled -- rc1 when any is missing, else io_info "verify
# passed". read-only: never enables, never installs.
# The capability gate AND the absent gnome-extensions binary return lib/verify.sh's
# _VERIFY_HOOK_SKIP, NOT 0 and not 1: on such a host this hook checked nothing,
# so 0 would be the "verify() passed" the audit prints and 1 would report a
# missing optional tool as a broken install. lib/verify.sh is sourced for that
# constant under the same guard the other hooks use for lib/io.sh.
verify() {
    local root dir rc=0
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || return 1
    source "$root/lib/gnome.sh"
    source "$root/lib/lists.sh"
    declare -F _verify_hook >/dev/null 2>&1 || source "$root/lib/verify.sh"
    gnome_require_capable gnome-extensions || return "$_VERIFY_HOOK_SKIP"
    if ((FS_DRY_RUN == 1)); then
        io_info "gnome-extensions: verify is read-only; runs only in real mode"
        return 0
    fi
    if ! gnome_extensions_available; then
        io_info "gnome-extensions: gnome-extensions not found on PATH; cannot verify"
        return "$_VERIFY_HOOK_SKIP"
    fi
    dir="$root/modules/gnome-extensions"
    _gnome_ext_verify "$dir" || rc=1
    if ((rc == 0)); then
        io_info "gnome-extensions: verify passed"
    fi
    return "$rc"
}

_gnome_ext_verify() {
    local dir="$1" rc=0 uuid="" out=""
    local -a uuids=()
    local -A installed=() enabled=()
    local -i n=0
    _gnome_ext_uuids "$dir" uuids || return 1
    if ((${#uuids[@]} == 0)); then
        io_info "gnome-extensions: verify: extensions.list empty; nothing to verify"
        return 0
    fi
    out="$(gnome_extensions_list)" || return 1
    if [[ -n "$out" ]]; then
        while IFS= read -r uuid; do
            case "$uuid" in
            "" | *[!A-Za-z0-9._@-]*) continue ;;
            esac
            installed[$uuid]=1
        done <<<"$out"
    fi
    out="$(gnome_extensions_list --enabled)" || return 1
    if [[ -n "$out" ]]; then
        while IFS= read -r uuid; do
            case "$uuid" in
            "" | *[!A-Za-z0-9._@-]*) continue ;;
            esac
            enabled[$uuid]=1
        done <<<"$out"
    fi
    for ((n = 0; n < ${#uuids[@]}; n++)); do
        uuid="${uuids[$n]}"
        if [[ -z "${installed[$uuid]:-}" ]]; then
            io_error "gnome-extensions: verify FAILED: extension not installed: $uuid"
            rc=1
        elif [[ -z "${enabled[$uuid]:-}" ]]; then
            io_error "gnome-extensions: verify FAILED: extension not enabled: $uuid"
            rc=1
        else
            io_info "gnome-extensions: verify ok: extension installed+enabled: $uuid"
        fi
    done
    return "$rc"
}

_gnome_ext_uuids() {
    local dir="$1" out="" uuid=""
    local -n ref="$2"
    out="$(list_parse "$dir/extensions.list")" || return 1
    if [[ -n "$out" ]]; then
        while IFS= read -r uuid; do
            case "$uuid" in
            "" | *[!A-Za-z0-9._@-]*)
                io_error "gnome-extensions: invalid uuid in extensions.list: $uuid"
                return 1
                ;;
            esac
            ref+=("$uuid")
        done <<<"$out"
    fi
    return 0
}

_gnome_ext_dry() {
    local dir="$1" uuid="" n=0
    local -a uuids=()
    _gnome_ext_uuids "$dir" uuids || return 1
    if ((${#uuids[@]} == 0)); then
        io_info "gnome-extensions: extensions.list empty; no extensions to enable"
        return 0
    fi
    for ((n = 0; n < ${#uuids[@]}; n++)); do
        uuid="${uuids[$n]}"
        run_cmd "gnome-extensions enable $uuid" -- gnome-extensions enable "$uuid" || return 1
    done
    io_info "gnome-extensions: compatibility notes appear on the real run (dry-run never probes)"
    return 0
}

_gnome_ext_compat() {
    local cfile="$1" line="" uuid="" min="" max="" rest=""
    local -n minref="$2"
    local -n maxref="$3"
    [[ -f "$cfile" && -r "$cfile" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        case "$line" in
        "" | \#*) continue ;;
        esac
        case "$line" in
        *\|*\|*) ;;
        *) continue ;;
        esac
        uuid="${line%%|*}"
        rest="${line#*|}"
        min="${rest%%|*}"
        max="${rest#*|}"
        case "$uuid" in
        "" | *[!A-Za-z0-9._@-]*) continue ;;
        esac
        case "$min" in
        "" | *[!0-9]*) continue ;;
        esac
        case "$max" in
        "" | *[!0-9]*) continue ;;
        esac
        minref[$uuid]="$min"
        maxref[$uuid]="$max"
    done <"$cfile"
    return 0
}

_gnome_ext_real() {
    local dir="$1" cfile="$2" rc=0 uuid="" major="" version="" u=""
    local installed_out="" enabled_out=""
    local -a uuids=()
    local -A installed=() enabled=() cmin=() cmax=()
    local -i n=0
    _gnome_ext_uuids "$dir" uuids || return 1
    _gnome_ext_compat "$cfile" cmin cmax
    rc=0
    version="$(gnome_shell_version 2>&1)" || rc=$?
    if ((rc != 0)); then
        io_debug "gnome-extensions: shell version probe failed: ${version:-unknown reason}"
        version=""
    fi
    rc=0
    installed_out="$(gnome_extensions_list)" || rc=$?
    if ((rc != 0)); then
        io_error "gnome-extensions: cannot list installed extensions"
        return 1
    fi
    rc=0
    enabled_out="$(gnome_extensions_list --enabled)" || rc=$?
    if ((rc != 0)); then
        io_error "gnome-extensions: cannot list enabled extensions"
        return 1
    fi
    if [[ -n "$installed_out" ]]; then
        while IFS= read -r uuid; do
            case "$uuid" in
            "" | *[!A-Za-z0-9._@-]*) continue ;;
            esac
            installed[$uuid]=1
        done <<<"$installed_out"
    fi
    if [[ -n "$enabled_out" ]]; then
        while IFS= read -r uuid; do
            case "$uuid" in
            "" | *[!A-Za-z0-9._@-]*) continue ;;
            esac
            enabled[$uuid]=1
        done <<<"$enabled_out"
    fi
    if [[ -z "$version" ]]; then
        io_info "gnome-extensions: GNOME shell version unknown; compatibility notes skipped"
    else
        io_info "gnome-extensions: GNOME shell $version"
        major="${version%%.*}"
        case "$major" in
        "" | *[!0-9]*) ;;
        *)
            for u in "${!installed[@]}"; do
                [[ -n "${cmin[$u]:-}" ]] || continue
                if ((major < ${cmin[$u]} || major > ${cmax[$u]})); then
                    io_warn "gnome-extensions: $u may not be compatible with GNOME Shell $major (supports ${cmin[$u]}-${cmax[$u]})"
                fi
            done
            ;;
        esac
    fi
    if ((${#uuids[@]} == 0)); then
        io_info "gnome-extensions: extensions.list empty; no extensions to enable"
        return 0
    fi
    for ((n = 0; n < ${#uuids[@]}; n++)); do
        uuid="${uuids[$n]}"
        if [[ -z "${installed[$uuid]:-}" ]]; then
            io_info "gnome-extensions: $uuid not installed; skipping (install its distro package)"
            continue
        fi
        if [[ -n "${enabled[$uuid]:-}" ]]; then
            io_debug "gnome-extensions: $uuid already enabled; no-op"
            continue
        fi
        run_cmd "gnome-extensions enable $uuid" -- gnome-extensions enable "$uuid" || return 1
    done
    return 0
}

_gnome_ext_browse() {
    local dir="$1" out="" url="" n=0 limit=2
    out="$(list_parse "$dir/browse.list")" || return 1
    if [[ -z "$out" ]]; then
        io_info "gnome-extensions: browse.list empty; nothing to open"
        return 0
    fi
    while IFS= read -r url && ((n < limit)); do
        case "$url" in
        http://* | https://*) ;;
        *)
            io_error "gnome-extensions: invalid browse URL: $url"
            return 1
            ;;
        esac
        if ((FS_DRY_RUN == 0)) && ! command -v xdg-open >/dev/null 2>&1; then
            io_info "gnome-extensions: xdg-open not found; open manually: $url"
        else
            run_cmd "gnome-extensions browse $((n + 1))" -- xdg-open "$url" || return 1
        fi
        n=$((n + 1))
    done <<<"$out"
    return 0
}
