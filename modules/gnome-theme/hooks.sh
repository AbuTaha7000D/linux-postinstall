#!/usr/bin/env bash
# modules/gnome-theme/hooks.sh - GNOME theme + bookmarks dedupe (P6.4).
# Sourced INSIDE the runner's hook subshell (lib/runner.sh stage 4); run()
# is called once. The runner provides io_*/run_cmd + FS_* seams; this hook
# sources lib/gnome.sh (gsettings layer) and lib/fs.sh (fs_dedupe_lines)
# itself.
#
# Prototype lineage (both fixes are P6.4 explicit goals):
#   - scripts/gnome_themes.sh drove an interactive `select` over ~/.themes.
#     Interactive TUI selection does not survive the headless module model
#     (dry-run never probes, P4.7), so the P6.2/P6.4 replacement is an
#     explicit env override (FS_THEME_NAME) with an auto-pick fallback over
#     the same on-disk locations; FS_THEME_NAME wins and is trusted even
#     when no theme dir exists, so an operator that knows their theme name
#     is not forced to keep a ~/.themes copy (same trust as FS_GIT_USER_NAME).
#   - scripts/icons_and_cursors.sh force-reset a non-Adwaita icon theme back
#     to Adwaita every run (prototype bug #5). This module contains no
#     icon-theme write anywhere; `icon theme untouched` is always stated.
#   - scripts/icons_and_cursors.sh appended
#     `echo "file://$HOME/Github" >> ~/.config/gtk-3.0/bookmarks` on every
#     run, so the Nautilus bookmarks file accumulated duplicate lines. This
#     module dedupes gtk-3.0 bookmarks whole-line (first occurrence wins,
#     order kept) and adds no curated entries of its own.
#
# run() guards like its gnome siblings via gnome_require_capable (P6.5):
# non-GNOME session, SSH/headless context, or no gsettings on PATH -> graceful
# skip (io_info "skipped (not GNOME)", rc0); --force (FS_GNOME_FORCE=1)
# overrides and runs anyway. Every FS_* path seam below must be absolute when
# set (io_error, rc1, both modes, before anything runs). Then, in order:
#   1. GTK theme -- resolve the name (FS_THEME_NAME > one dir in FS_THEME_SRC
#      > one dir in FS_THEME_ASSETS_DIR > skip with io_info and no plan
#      line) and gnome_gsettings_set org.gnome.desktop.interface gtk-theme.
#   2. Cursor theme -- same resolution via FS_CURSOR_* for cursor-theme.
#   3. Bookmarks -- target "${FS_GTK_BOOKMARKS_FILE:-$HOME/.config/gtk-3.0/
#      bookmarks}" (FS_GTK_BOOKMARKS_FILE is the hermetic seam; HOME "/" or
#      unset with no seam fails closed, mirroring git). No file -> io_info,
#      rc0, nothing created (no mkdir, no curated adds). Dry-run renders the
#      single `# would run: dedupe gtk-3.0 bookmarks <file>` plan line when
#      the file exists (a stat, like the fonts/git dry plans); read and write
#      happen only in real mode. Real mode: fs_dedupe_lines backs up via the
#      registry, dedupes first-seen, preserves order and file mode, writes
#      back atomically only when duplicates were actually removed, and prints
#      the removed count; zero removed -> no write, no backup entry.
# gsettings string values are passed single-quoted ('Aurora', 'DMZ-Black') so
# real gsettings get/set agree for true idempotency; FS_THEME_NAME /
# FS_CURSOR_NAME values run through gnome_gsettings_set's GVariant validation
# (lib/gnome.sh): printable ASCII only -- tabs/newlines/CR and bytes outside
# 0x20-0x7E fail closed (io_error, rc1), while a single quote inside a name
# yields a value real gsettings rejects as malformed GVariant; that write is
# reported by the run layer and kept (rc0, keep-going), so a quoted name
# surfaces as a failed write in the audit log. The shell-level user-theme
# extension (which makes ~/.themes work on GNOME Shell >= 3.36) is NOT managed
# here: installing it is P6.3 territory (gnome-extensions curates the
# user-theme@gcampax extension) and the prototype's second key,
# org.gnome.shell.extensions.user-theme name, is also deliberately NOT written:
# it only takes effect when that extension is enabled and writing it would
# change the Shell theme the user already set in GNOME Tweaks. Themes the
# operator already picked remain active; this module only applies and never
# reads back existing theme state. The cursor seam uses `cursors`
# (FS_CURSOR_* / $root/assets/cursors) rather than `icons` so nothing here
# collides with the bookmark-icon assets tree (assets/icons/).
# Bash >= 4.3 safe.
#
# Keep-going: a failed gsettings write returns 0 to the runner (run_cmd
# policy) but the hook still returns rc0 after reporting, so one failed key
# does not abort the profile.

run() {
    local root
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || return 1
    source "$root/lib/gnome.sh"
    source "$root/lib/fs.sh"
    gnome_require_capable gnome-theme || return "$MODULE_HOOK_SKIP"
    _gnome_theme_preflight || return 1
    _gnome_theme_apply gtk-theme THEME "$root" || return 1
    _gnome_theme_apply cursor-theme CURSOR "$root" || return 1
    _gnome_theme_bookmarks "$root" || return 1
    io_info "gnome-theme: icon theme untouched (keeps the user's icon theme)"
    return 0
}

# verify() is the P6.5 read-only diagnostic (wired to `./setup verify` in
# P9.2): it re-gates, refuses to run in dry-run, then compares the actual
# gsettings theme values against what run() would apply and checks the GTK
# bookmarks file holds no duplicate whole lines. Each check reports io_info on
# success or io_error on mismatch; rc1 on any failure or probe error, else
# io_info "verify passed". Read-only: never writes, never backs up.
# The capability gate returns lib/verify.sh's _VERIFY_HOOK_SKIP, NOT 0: on a
# non-GNOME / SSH / gsettings-less host this hook checked nothing, and a 0
# there is the "verify() passed" the audit would have printed. lib/verify.sh is
# sourced for that constant under the same guard the other hooks use for
# lib/io.sh, so the contract is available when verify() is called directly too.
verify() {
    local root rc=0
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || return 1
    source "$root/lib/gnome.sh"
    source "$root/lib/fs.sh"
    declare -F _verify_hook >/dev/null 2>&1 || source "$root/lib/verify.sh"
    gnome_require_capable gnome-theme || return "$_VERIFY_HOOK_SKIP"
    if ((FS_DRY_RUN == 1)); then
        io_info "gnome-theme: verify is read-only; runs only in real mode"
        return 0
    fi
    _gnome_theme_preflight || return 1
    _gnome_theme_verify gtk-theme THEME "$root" || rc=1
    _gnome_theme_verify cursor-theme CURSOR "$root" || rc=1
    _gnome_theme_verify_bookmarks "$root" || rc=1
    if ((rc == 0)); then
        io_info "gnome-theme: verify passed"
    fi
    return "$rc"
}

_gnome_theme_preflight() {
    local i=0 v=""
    local -a sm=(FS_THEME_SRC FS_CURSOR_SRC FS_THEME_ASSETS_DIR FS_CURSOR_ASSETS_DIR FS_GTK_BOOKMARKS_FILE)
    local -a sv=("${FS_THEME_SRC:-}" "${FS_CURSOR_SRC:-}" "${FS_THEME_ASSETS_DIR:-}" "${FS_CURSOR_ASSETS_DIR:-}" "${FS_GTK_BOOKMARKS_FILE:-}")
    for ((i = 0; i < ${#sm[@]}; i++)); do
        v="${sv[i]}"
        if [[ -n "$v" && "$v" != /* ]]; then
            io_error "gnome-theme: ${sm[i]} must be absolute: $v"
            return 1
        fi
    done
    return 0
}

_gnome_theme_pick() {
    local dir="$1" f=""
    [[ -d "$dir" ]] || return 0
    for f in "$dir"/*; do
        [[ -d "$f" ]] || continue
        printf '%s\n' "${f##*/}"
    done
    return 0
}

_gnome_theme_apply() {
    local kind="$1" namekey="$2" root="$3"
    local schema="org.gnome.desktop.interface" key="$kind"
    local name="" src="" assets="" seam_var=""
    local -a list=()
    case "$namekey" in
    THEME)
        src="${FS_THEME_SRC:-${HOME:-}/.themes}"
        assets="${FS_THEME_ASSETS_DIR:-$root/assets/themes}"
        name="${FS_THEME_NAME:-}"
        ;;
    CURSOR)
        src="${FS_CURSOR_SRC:-${HOME:-}/.icons}"
        assets="${FS_CURSOR_ASSETS_DIR:-$root/assets/cursors}"
        name="${FS_CURSOR_NAME:-}"
        ;;
    esac
    if [[ -z "$name" ]]; then
        mapfile -t list < <(_gnome_theme_pick "$src")
        if ((${#list[@]} == 1)); then
            name="${list[0]}"
        elif ((${#list[@]} > 1)); then
            seam_var="FS_${namekey}_NAME"
            io_info "gnome-theme: multiple $kind themes in $src; set $seam_var to choose"
            return 0
        else
            mapfile -t list < <(_gnome_theme_pick "$assets")
            if ((${#list[@]} == 1)); then
                name="${list[0]}"
            elif ((${#list[@]} > 1)); then
                seam_var="FS_${namekey}_NAME"
                io_info "gnome-theme: multiple $kind themes in $assets; set $seam_var to choose"
                return 0
            fi
        fi
    fi
    if [[ -z "$name" ]]; then
        io_info "gnome-theme: no $kind selected (set FS_${namekey}_NAME or put exactly one theme dir in $src or $assets)"
        return 0
    fi
    io_info "gnome-theme: applying $kind: $name"
    gnome_gsettings_set "$schema" "$key" "'$name'" || return 1
    return 0
}

_gnome_theme_bookmarks() {
    local file="" n=0 rc=0
    file="${FS_GTK_BOOKMARKS_FILE:-}"
    if [[ -z "$file" ]]; then
        if [[ -z "${HOME:-}" || "$HOME" == "/" ]]; then
            io_error "gnome-theme: bookmarks path requires FS_GTK_BOOKMARKS_FILE or a HOME"
            return 1
        fi
        file="$HOME/.config/gtk-3.0/bookmarks"
    fi
    if [[ ! -e "$file" ]]; then
        io_info "gnome-theme: no GTK bookmarks file; nothing to dedupe"
        return 0
    fi
    if ((FS_DRY_RUN == 1)); then
        printf '# would run: dedupe gtk-3.0 bookmarks %q\n' "$file"
        return 0
    fi
    rc=0
    n="$(fs_dedupe_lines "$file")" || rc=$?
    if ((rc != 0)); then
        return 1
    fi
    if ((n == 0)); then
        io_info "gnome-theme: bookmarks already deduplicated; no write"
    else
        io_info "gnome-theme: bookmarks deduplicated ($n duplicate line(s) removed)"
    fi
    return 0
}

_gnome_theme_verify() {
    local kind="$1" namekey="$2" root="$3"
    local schema="org.gnome.desktop.interface" key="$kind"
    local name="" src="" assets="" cur="" seam_var=""
    local -a list=()
    case "$namekey" in
    THEME)
        src="${FS_THEME_SRC:-${HOME:-}/.themes}"
        assets="${FS_THEME_ASSETS_DIR:-$root/assets/themes}"
        name="${FS_THEME_NAME:-}"
        ;;
    CURSOR)
        src="${FS_CURSOR_SRC:-${HOME:-}/.icons}"
        assets="${FS_CURSOR_ASSETS_DIR:-$root/assets/cursors}"
        name="${FS_CURSOR_NAME:-}"
        ;;
    esac
    if [[ -z "$name" ]]; then
        mapfile -t list < <(_gnome_theme_pick "$src")
        if ((${#list[@]} == 1)); then
            name="${list[0]}"
        elif ((${#list[@]} > 1)); then
            seam_var="FS_${namekey}_NAME"
            io_info "gnome-theme: verify: multiple $kind themes in $src; set $seam_var to choose"
            return 0
        else
            mapfile -t list < <(_gnome_theme_pick "$assets")
            if ((${#list[@]} == 1)); then
                name="${list[0]}"
            elif ((${#list[@]} > 1)); then
                seam_var="FS_${namekey}_NAME"
                io_info "gnome-theme: verify: multiple $kind themes in $assets; set $seam_var to choose"
                return 0
            fi
        fi
    fi
    if [[ -z "$name" ]]; then
        io_info "gnome-theme: verify: no $kind selected; nothing to verify"
        return 0
    fi
    cur="$(gnome_gsettings_get "$schema" "$key")" || return 1
    if [[ "'$name'" == "$cur" ]]; then
        io_info "gnome-theme: verify ok: $kind = $name"
        return 0
    fi
    io_error "gnome-theme: verify FAILED: $kind is $cur, expected '$name'"
    return 1
}

_gnome_theme_verify_bookmarks() {
    local file="" line="" n=0
    local -A vd=()
    file="${FS_GTK_BOOKMARKS_FILE:-}"
    if [[ -z "$file" ]]; then
        if [[ -z "${HOME:-}" || "$HOME" == "/" ]]; then
            io_error "gnome-theme: bookmarks path requires FS_GTK_BOOKMARKS_FILE or a HOME"
            return 1
        fi
        file="$HOME/.config/gtk-3.0/bookmarks"
    fi
    if [[ ! -e "$file" ]]; then
        io_info "gnome-theme: verify: no GTK bookmarks file; nothing to verify"
        return 0
    fi
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ -n "${vd["L$line"]:-}" ]]; then
            n=$((n + 1))
        else
            vd["L$line"]=1
        fi
    done <"$file"
    if ((n == 0)); then
        io_info "gnome-theme: verify ok: bookmarks deduplicated"
        return 0
    fi
    io_error "gnome-theme: verify FAILED: bookmarks hold $n duplicate line(s)"
    return 1
}
