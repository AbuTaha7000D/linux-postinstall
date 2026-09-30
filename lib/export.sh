#!/usr/bin/env bash
# lib/export.sh - portable state manifest writer (P9.3).
# Depends on lib/io.sh, lib/lists.sh, lib/modules.sh, lib/profiles.sh,
# lib/fs.sh, lib/gnome.sh and lib/depgraph.sh (source them first).
# Bash >= 4.3 safe: loop bounds from $#, every empty-array expansion guarded, and
# it does use mapfile (4.0) and lib/fs.sh's `local -n` nameref helpers (4.3) --
# all at or above the floor, deliberately, to share the writer's block locator
# instead of re-deriving it. Read-only with respect to the system: it never
# installs, never marks, never backs up, never sudoes and never writes outside
# the output directory it is given. Its ONLY write is the export tree.
#
# WHAT IS EXPORTED, and the rule that decides it
# ------------------------------------------------
# ROADMAP P9 s7: "export scope creep -> keep to intentionally-managed state
# only, per the audit distinction". So the exporter is an ALLOWLIST, never a
# walk. It reads exactly four kinds of thing and nothing else:
#
#   1. Module metadata and list files, for the resolved module set only, read
#      through lib/lists.sh. A module's downloaded sources, vendored trees and
#      build scratch are never opened -- that is the "excludes dependencies"
#      half: a dependency is something the module fetched, not something the
#      module declares, and only declarations are exported.
#   2. The gsettings keys and GNOME extensions the tool itself writes, listed
#      in _EXPORT_GSETTINGS below. A user's unrelated desktop settings are
#      never read.
#   3. The installed nerd-font markers, using modules/fonts/hooks.sh's own
#      _font_marker builder so the exporter cannot invent a name the installer
#      never wrote.
#   4. The managed blocks named in _export_managed, and ONLY the block: the
#      region between the markers. Whatever the user wrote outside the markers
#      is never read, copied, or even buffered. This is the "secrets provably
#      excluded" property, and it is structural rather than a filter -- there
#      is no redaction step to get wrong and no denylist to keep current.
#
# WHAT IS NEVER READ, and that is the security property
# -----------------------------------------------------
# The state root. Not logs/, not backups/, not the module registry, not
# notes/, not a tool-owned GPG keyring, not the pinned fingerprint file. None
# of those are reachable from this file, so a secret that lands in any of them
# cannot reach the export tree. state_root_path is deliberately not even
# called. Symlinks are never followed out of an allowlisted target: a block is
# read from the target path itself, and a target that is a symlink is reported
# and skipped rather than dereferenced.
#
# TREE LAYOUT (the portable artifact; `install --manifest <dir>` reads it)
# -----------------------------------------------------------------------
#   <dir>/export.meta              key=value provenance, no timestamp (below)
#   <dir>/<profile>.conf           profile-shaped module ids, deps-first order
#   <dir>/manifests/<id>.list      resolved SYSTEM package ids for the family
#   <dir>/manifests/<id>.flatpaks.list
#                                  resolved flatpak ids
#   <dir>/state/gsettings.list     "schema<TAB>key<TAB>value" for managed keys
#   <dir>/state/extensions.list    enabled extension uuids
#   <dir>/state/fonts.list         installed nerd-font markers
#   <dir>/files/<name>             the managed block body, verbatim
#   <dir>/files/index              "name<TAB>~relative-source-path"
#
# <profile>.conf is deliberately profile-shaped (one id per line, the
# lib/lists.sh grammar) so the re-import reuses profile_load/profile_resolve
# unchanged rather than growing a second parser. The manifests/ lists are
# ALREADY family-resolved, so they carry no family and no per-family override
# logic: a re-import consumes the exact ids that were exported, which is what
# makes the round trip able to detect upstream drift instead of assuming it.
#
# THE MANAGED BLOCK
# ------------------
# files/<name> is the body BETWEEN the markers, never the file. The block is
# located with lib/fs.sh's OWN primitives -- _fs_validate_markers, _fs_locate,
# _fs_locate_ok -- not with a parser here. fs_managed_block owns the meaning of
# "the managed block"; re-deriving it in the reader is precisely how an auditor
# drifts from its writer, and the concrete cost is duplicate blocks: the writer
# demands EXACTLY one BEGIN and one END with END after BEGIN, so it refuses a
# file carrying two same-name blocks, while a naive reader happily concatenates
# both bodies into one "block" the tool would not manage. Sharing the code makes
# that class of drift unrepresentable rather than tested for.
# After _fs_validate_markers passes, _fs_locate_ok can only fail on the duplicate
# case -- two well-formed sequential pairs validate fine but leave _FS_BC at 2 --
# so there is deliberately no separate "unterminated" test here: that check is
# unreachable (the shared validator already ends with an open-state check) and a
# guard that never fires reads as protection while providing none.
# Three states stay distinct: no marker at all is silently "no block", the normal
# case on an unconfigured machine; a well-formed pair is the block; anything
# malformed is a warning plus a skip. Absence and truncation are different states,
# and conflating them made every block-less dotfile warn and then contradict
# itself with "no managed block".
# A refusal is therefore reported TWICE, on purpose: the shared validator logs
# its own [error] naming the offending region (that is the writer's wording, and
# it is the useful diagnosis), then this reader adds a [warn] saying the file is
# being skipped. Suppressing the first would hide the writer's diagnosis;
# treating it as fatal would abandon an export that is still perfectly valid. Do
# not "fix" the double line.
#
# DETERMINISM
# -----------
# No timestamp is written anywhere in the tree, so two exports of the same
# system state are byte-identical and the artifact can be diffed or committed.
# Creation time is recorded in the audit log instead, not in the artifact. That
# is a deliberate trade: provenance loses a timestamp, reproducibility gains
# byte-equality.
# The TOOL's own paths are rendered $HOME-relative -- files/index AND the font
# marker column -- so the tree's own bookkeeping carries no home directory. That
# is NOT true of captured VALUES: a wallpaper
# gsettings value legitimately embeds an absolute file:// URI, and it is
# recorded verbatim because rewriting it would make the snapshot a lie. So the
# tree is username-free in its own bookkeeping, not necessarily in the state it
# describes. The tree shape is also host-independent: every file listed above
# is always written, empty when there was nothing to record, so a non-GNOME
# export has the same shape as a GNOME one.
#
# COMPLETION
# ----------
# export.meta is written LAST, after the profile conf, the manifests, the GNOME
# snapshot, the font list and the managed blocks have all succeeded. That is the
# whole validity contract: `install --manifest` recognizes a tree by the presence
# of export.meta and nothing else, so a tree that is missing it is refused with
# "not an export tree". Writing it first -- which is the obvious order, since it
# is the header -- means a FAILED export leaves a directory that a re-import
# accepts and silently half-populates: the user gets rc 1, a tree on disk, and
# a later re-import that installs from it while omitting everything the failure
# stopped. The manifests are written before the stages that can fail, so a
# partial tree genuinely exists on disk; the completion marker is the only thing
# distinguishing it from a good one, which is exactly why it goes last.
# The marker must also be DROPPED first when re-exporting over an existing tree.
# Re-export is allowed, and "write last" alone does not cover it: the previous
# run's marker is still sitting there, so a refresh that fails part way leaves
# the OLD marker describing the OLD profile next to the NEW manifests. A
# re-import then accepts the tree and silently replays the previous profile
# instead of the one that was asked for -- the most dangerous failure this
# format has, because nothing reports an error anywhere.
# "First write" means the manifest loop, not the profile conf: that loop is
# where writing actually begins, and module_validate / list_packages /
# list_flatpaks can all fail inside it, one module at a time. Dropping the
# marker after that loop -- the obvious place, next to the other setup -- is
# still a hole, because a failure on module 2 has already rewritten module 1's
# manifests while the old marker is untouched: the tree then replays the OLD
# profile over the NEW ids, a combination that no export ever produced and
# nothing reports. So the drop happens after the outdir preflight and before
# the loop, and the window in which a partial tree is still recognizable is
# empty. It is deliberately NOT dropped during argument and profile validation,
# which writes nothing: a run rejected for a bad --profile must leave the
# previous good tree valid. Stale files from a wider previous export are left in
# place; the marker is the validity contract, and a tree without one is refused
# wholesale, so they cannot be replayed.
#
# DRY RUN
# --------
# A dry run writes nothing and PROBES NOTHING. gsettings and gnome-extensions
# are both live queries (lib/gnome.sh refuses them under FS_DRY_RUN), so the
# GNOME arm is reported as "not probed" instead of guessing. Every file that
# would be written is still named, so a dry run shows the shape of the tree.
#
# _export_managed            print "name<TAB>absolute-path" for each managed
#                            block this tool writes, in a stable order
# _export_managed_paths      resolve the allowlisted target paths, honouring
#                            the same seams and $HOME defaults the module hooks
#                            use, and fail closed the same way
# _export_block <path> <name>  print one managed block's body; rc1 when the
#                            block is absent or the file is unusable
# _export_rel <path>         render <path> as a $HOME-relative path for the
#                            index; never emits a raw home directory
# export_run <root> <outdir> <family> <profile> <modules_dir> <profiles_dir>
#                            write the whole tree; rc0, or rc1 on any refusal

_EXPORT_FORMAT=1

# The gsettings keys this tool writes, as "schema<TAB>key". Derived from the
# modules that own them: gnome-base (favorites, wallpaper, custom
# keybindings) and gnome-theme (gtk-theme, cursor-theme). A key the tool never
# writes is not snapshotted, which is what keeps the exporter off the user's
# unrelated desktop configuration.
_EXPORT_GSETTINGS=(
    "org.gnome.shell	favorite-apps"
    "org.gnome.desktop.interface	gtk-theme"
    "org.gnome.desktop.interface	cursor-theme"
    "org.gnome.desktop.background	picture-uri"
    "org.gnome.desktop.background	picture-uri-dark"
    "org.gnome.settings-daemon.plugins.media-keys	custom-keybindings"
)

_export_managed_paths() {
    local home="${HOME:-}" cfg="" bashrc="" aliases=""
    if [[ -n "${FS_GIT_CONFIG:-}" ]]; then
        cfg="$FS_GIT_CONFIG"
    elif [[ -n "$home" && "$home" != / ]]; then
        cfg="$home/.gitconfig"
    fi
    if [[ -n "${FS_BASHRC:-}" ]]; then
        bashrc="$FS_BASHRC"
    elif [[ -n "$home" && "$home" != / ]]; then
        bashrc="$home/.bashrc"
    fi
    if [[ -n "${FS_TERM_ALIASES:-}" ]]; then
        aliases="$FS_TERM_ALIASES"
    elif [[ -n "$home" && "$home" != / ]]; then
        aliases="$home/.local/share/fedora-setup/aliases"
    fi
    [[ -n "$cfg" ]] && printf 'git\t%s\n' "$cfg"
    [[ -n "$bashrc" ]] && printf 'terminal\t%s\n' "$bashrc"
    [[ -n "$aliases" ]] && printf 'aliases\t%s\n' "$aliases"
    return 0
}

_export_block() {
    local path="${1:-}" name="${2:-}" body="" i
    if [[ -z "$path" || -z "$name" ]]; then
        io_error "_export_block requires a path and a name"
        return 1
    fi
    if [[ ! -e "$path" ]]; then
        return 1
    fi
    if [[ -L "$path" ]]; then
        io_warn "export: skipping symlinked managed file (not dereferenced): $path"
        return 1
    fi
    if [[ ! -f "$path" || ! -r "$path" ]]; then
        io_warn "export: managed file not a readable regular file: $path"
        return 1
    fi
    local -a lines=() mid=()
    if ! mapfile -t lines <"$path"; then
        io_warn "export: cannot read managed file: $path"
        return 1
    fi
    _fs_validate_markers lines || {
        io_warn "export: malformed managed block markers in $path; skipping"
        return 1
    }
    _fs_locate lines "# BEGIN fedora-setup $name" "# END fedora-setup $name"
    if (( _FS_BC > 0 || _FS_EC > 0 )); then
        _fs_locate_ok || {
            io_warn "export: malformed managed block ($name) in $path; skipping"
            return 1
        }
    fi
    if _fs_locate_ok; then
        for ((i = _FS_B + 1; i < _FS_E; i++)); do
            mid+=("${lines[i]}")
        done
        if (( ${#mid[@]} > 0 )); then
            body="$(printf '%s\n' "${mid[@]}")"
        fi
    fi
    if [[ -z "$body" ]]; then
        return 1
    fi
    printf '%s\n' "$body"
    return 0
}

_export_rel() {
    local path="${1:-}" home="${HOME:-}" rel=""
    if [[ -n "$home" && "$home" != / && "$path" == "$home"/* ]]; then
        rel="~${path#"$home"}"
    else
        rel="$path"
    fi
    printf '%s\n' "$rel"
    return 0
}

_export_mkdir() {
    local dir="${1:-}"
    if [[ -z "$dir" ]]; then
        io_error "export: empty directory path"
        return 1
    fi
    if [[ -L "$dir" ]]; then
        io_error "export: refusing to write through a symlink: $dir"
        return 1
    fi
    if [[ -e "$dir" && ! -d "$dir" ]]; then
        io_error "export: output path exists and is not a directory: $dir"
        return 1
    fi
    if ! mkdir -p -- "$dir" 2>/dev/null; then
        io_error "export: cannot create directory: $dir"
        return 1
    fi
    return 0
}

_export_write() {
    local path="${1:-}" body="${2:-}" tmp="" dir=""
    if (( $# < 2 )); then
        io_error "_export_write requires a path and a body"
        return 1
    fi
    dir="$(dirname -- "$path")"
    _export_mkdir "$dir" || return 1
    if [[ -L "$path" ]]; then
        io_error "export: refusing to write through a symlink: $path"
        return 1
    fi
    tmp="$(mktemp -- "$dir/.export.XXXXXX")" || {
        io_error "export: cannot create a temp file in: $dir"
        return 1
    }
    if [[ -n "$body" ]]; then
        printf '%s\n' "$body" >"$tmp" 2>/dev/null || {
            rm -f -- "$tmp" 2>/dev/null || :
            io_error "export: cannot write: $path"
            return 1
        }
    else
        : >"$tmp" 2>/dev/null || {
            rm -f -- "$tmp" 2>/dev/null || :
            io_error "export: cannot write: $path"
            return 1
        }
    fi
    if ! mv -fT -- "$tmp" "$path" 2>/dev/null; then
        rm -f -- "$tmp" 2>/dev/null || :
        io_error "export: cannot move into place: $path"
        return 1
    fi
    return 0
}

_export_gnome() {
    local outdir="${1:-}" entry="" schema="" key="" value="" rc=0
    local body="" ids="" ext="" list="" gnome_ok=0
    if gnome_require_capable "export"; then
        gnome_ok=1
    else
        io_info "export: gsettings snapshot skipped (not a GNOME session)"
    fi
    if (( gnome_ok == 1 )); then
        for entry in ${_EXPORT_GSETTINGS[@]+"${_EXPORT_GSETTINGS[@]}"}; do
            schema="${entry%%	*}"
            key="${entry#*	}"
            value="$(gnome_gsettings_get "$schema" "$key")" || {
                rc=1
                continue
            }
            if [[ "$value" == *$'\t'* ]]; then
                io_warn "export: gsettings value contains a tab, skipped: $schema $key"
                continue
            fi
            body="${body:+$body
}${schema}	${key}	${value}"
        done
        if (( rc != 0 )); then
            io_warn "export: some managed gsettings keys could not be read; the snapshot is partial"
        fi
    fi
    _export_write "$outdir/state/gsettings.list" "$body" || return 1
    ids=""
    if (( gnome_ok == 1 )); then
        if gnome_extensions_available; then
            ids="$(gnome_extensions_list --enabled)" || ids=""
            if [[ -z "$ids" ]]; then
                io_info "export: no enabled extensions reported"
            fi
        else
            io_info "export: gnome-extensions not available; enabled list is empty"
        fi
    fi
    _export_write "$outdir/state/extensions.list" "$ids" || return 1
    return 0
}

_export_fonts() {
    local outdir="${1:-}" root="${2:-}" cfg="" home="${HOME:-}" fonts_dir="" moddir="${3:-}"
    if [[ -z "$home" || "$home" == / ]]; then
        home=""
    fi
    fonts_dir="${FS_FONTS_DIR:-$home/.local/share/fonts}"
    cfg="${FS_NERDFONT_CONFIG:-$root/config/nerdfonts.list}"
    if [[ -z "$fonts_dir" ]]; then
        io_info "export: no HOME and no FS_FONTS_DIR; font list is empty"
        _export_write "$outdir/state/fonts.list" "" || return 1
        return 0
    fi
    if [[ ! -f "$moddir/fonts/hooks.sh" ]]; then
        io_warn "export: no fonts module hook at $moddir/fonts; font list is empty"
        _export_write "$outdir/state/fonts.list" "" || return 1
        return 0
    fi
    if [[ ! -f "$cfg" ]]; then
        io_info "export: no nerd font config at $cfg; font list is empty"
        _export_write "$outdir/state/fonts.list" "" || return 1
        return 0
    fi
    local list=""
    if ! list="$(
        set +e
        FS_FONTS_DIR="$fonts_dir"
        export FS_FONTS_DIR
        source "$moddir/fonts/hooks.sh" || exit 1
        label=""; asset=""; ver=""; marker=""; line=""
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ -n "$line" ]] || continue
            _run_nerd_entry "$line" || continue
            marker="$fonts_dir/$(_font_marker "$asset" "$ver")"
            [[ -f "$marker" ]] || continue
            printf '%s\t%s\n' "$label" "$(_export_rel "$marker")"
        done < <(list_parse "$cfg" 2>/dev/null)
        exit 0
    )"; then
        io_error "export: cannot read the font config: $cfg"
        return 1
    fi
    if ! list_parse "$cfg" >/dev/null 2>&1; then
        io_error "export: font config is not readable: $cfg"
        return 1
    fi
    _export_write "$outdir/state/fonts.list" "$list" || return 1
    return 0
}

_export_files() {
    local outdir="${1:-}" name="" path="" body="" index="" line=""
    while IFS=$'\t' read -r name path; do
        [[ -n "$name" && -n "$path" ]] || continue
        if (( FS_DRY_RUN == 1 )); then
            body=""
            io_info "would write: $outdir/files/$name"
        elif ! body="$(_export_block "$path" "$name")"; then
            io_info "export: no managed block '$name' in $path"
            continue
        fi
        if (( FS_DRY_RUN != 1 )); then
            _export_write "$outdir/files/$name" "$body" || return 1
        fi
        line="${name}	$(_export_rel "$path")"
        index="${index:+$index
}${line}"
    done < <(_export_managed_paths)
    if (( FS_DRY_RUN == 1 )); then
        io_info "would write: $outdir/files/index"
        return 0
    fi
    _export_write "$outdir/files/index" "$index" || return 1
    return 0
}

export_run() {
    if (( $# < 6 )); then
        io_error "export_run requires root, outdir, family, profile, modules_dir, profiles_dir"
        return 1
    fi
    local root="${1:-}" outdir="${2:-}" family="${3:-}" profile="${4:-}"
    local modules_dir="${5:-}" profiles_dir="${6:-}"
    local ids="" id="" dir="" pkgs="" apps="" meta=""
    local -i n=0
    if [[ -z "$outdir" ]]; then
        io_error "export requires an output directory"
        return 1
    fi
    if [[ ! -d "$modules_dir" ]]; then
        io_error "export: modules directory not found: $modules_dir"
        return 1
    fi
    profile_validate "$profiles_dir" "$profile" || return 1
    ids="$(profile_resolve "$modules_dir" "$profiles_dir" "$profile")" || return 1
    if [[ -z "$ids" ]]; then
        io_warn "export: profile '$profile' resolves to no modules; the tree will be empty"
    fi
    if (( FS_DRY_RUN != 1 )); then
        if [[ -e "$outdir" && ! -d "$outdir" ]]; then
            io_error "export: output path exists and is not a directory: $outdir"
            return 1
        fi
        if [[ -d "$outdir" && -n "$(ls -A -- "$outdir" 2>/dev/null)" && ! -f "$outdir/export.meta" ]]; then
            io_error "export: refusing to write into a non-empty directory that is not an export tree: $outdir"
            return 1
        fi
    fi
    if (( FS_DRY_RUN != 1 )); then
        _export_mkdir "$outdir" || return 1
        rm -f -- "$outdir/export.meta" || return 1
    fi
    while IFS= read -r id || [[ -n "$id" ]]; do
        [[ -n "$id" ]] || continue
        dir="$modules_dir/$id"
        module_validate "$dir" "$family" || return 1
        pkgs="$(list_packages "$dir" "$family")" || return 1
        if (( FS_DRY_RUN == 1 )); then
            io_info "would write: $outdir/manifests/$id.list ($(printf '%s\n' "$pkgs" | grep -c . || true) packages)"
            io_info "would write: $outdir/manifests/$id.flatpaks.list"
        else
            _export_write "$outdir/manifests/$id.list" "$pkgs" || return 1
            apps="$(list_flatpaks "$dir")" || return 1
            _export_write "$outdir/manifests/$id.flatpaks.list" "$apps" || return 1
        fi
        n=$(( n + 1 ))
    done <<<"$ids"
    meta="format=$_EXPORT_FORMAT
fs_version=${FS_VERSION:-unknown}
family=$family
profile=$profile
modules=$(printf '%s' "$ids" | tr '\n' ',')"
    if (( FS_DRY_RUN == 1 )); then
        io_info "would write: $outdir/export.meta"
        io_info "would write: $outdir/$profile.conf"
        io_info "would write: $outdir/state/gsettings.list"
        io_info "would write: $outdir/state/extensions.list"
        io_info "would write: $outdir/state/fonts.list"
        _export_files "$outdir" || return 1
        io_info "export (dry run): $n module(s) for profile '$profile'; nothing was written"
        return 0
    fi
    _export_write "$outdir/$profile.conf" "$ids" || return 1
    _export_gnome "$outdir" || return 1
    _export_fonts "$outdir" "$root" "$modules_dir" || return 1
    _export_files "$outdir" || return 1
    _export_write "$outdir/export.meta" "$meta" || return 1
    io_info "export: $n module(s) for profile '$profile' -> $outdir"
    return 0
}
