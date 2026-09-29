#!/usr/bin/env bash
# lib/fs.sh - guarded, atomic filesystem helpers for fedora-setup.
# Depends on lib/io.sh for io_error. Backup registry entries use
# lib/state.sh (state_backup_add) when that library is loaded.
# Policy: fs_install and the managed-block helpers follow symlinked
# parent directories and replace a leaf symlink with a regular file
# (backing up the resolved content first). All writes are atomic via
# temp+rename, so an interrupted run can leave at most a *.XXXXXX
# temp file, never a partially written target. fs_dedupe_lines is the
# plain per-line dedupe primitive (first occurrence wins, order kept)
# used by the P6.4 gnome-theme bookmarks fix; its write is atomic and
# mode-preserving (_fs_write_atomic) and, like the managed-block helpers,
# a leaf symlink target is replaced by a regular file. Blank lines are
# ordinary lines: the first occurrence of every distinct value (including
# the empty line) is kept. It never parses, never inserts markers, and
# writes back only when duplicates were removed.

_fs_valid_name() {
    local name="$1"
    case "$name" in
        "" | "." | ".." | *[!A-Za-z0-9._-]*) return 1 ;;
    esac
    return 0
}

_fs_validate_markers() {
    local -n arr="$1"
    local i line name state="closed" region=""
    for ((i = 0; i < ${#arr[@]}; i++)); do
        line="${arr[i]}"
        case "$line" in
            "# BEGIN fedora-setup" | "# BEGIN fedora-setup " | "# END fedora-setup" | "# END fedora-setup ")
                io_error "malformed managed block marker: $line"
                return 1
                ;;
            "# BEGIN fedora-setup "*)
                name="${line#*# BEGIN fedora-setup}"
                name="${name# }"
                if [[ "$state" == "open" ]]; then
                    io_error "nested managed block ($name) inside ($region)"
                    return 1
                fi
                if ! _fs_valid_name "$name"; then
                    io_error "malformed managed block marker: $line"
                    return 1
                fi
                state="open"
                region="$name"
                ;;
            "# END fedora-setup "*)
                name="${line#*# END fedora-setup}"
                name="${name# }"
                if [[ "$state" != "open" ]]; then
                    io_error "orphan managed block end marker: $line"
                    return 1
                fi
                if [[ "$name" != "$region" ]]; then
                    io_error "crossing managed block markers ('$region' closed by '$name')"
                    return 1
                fi
                state="closed"
                region=""
                ;;
        esac
    done
    if [[ "$state" == "open" ]]; then
        io_error "unterminated managed block ($region)"
        return 1
    fi
    return 0
}

_fs_parent() {
    local path="$1"
    _FS_PARENT="${path%/*}"
    if [[ "$_FS_PARENT" == "$path" ]]; then
        _FS_PARENT="."
    elif [[ -z "$_FS_PARENT" ]]; then
        _FS_PARENT="/"
    fi
}

_fs_array_equal() {
    local -n a="$1"
    local -n b="$2"
    local i
    if (( ${#a[@]} != ${#b[@]} )); then
        return 1
    fi
    for ((i = 0; i < ${#a[@]}; i++)); do
        if [[ "${a[i]}" != "${b[i]}" ]]; then
            return 1
        fi
    done
    return 0
}

_fs_chain_ok() {
    local path="$1" cur="" seg i
    local -a segs=()
    if [[ "$path" != /* ]]; then
        io_error "refusing non-absolute path: $path"
        return 1
    fi
    case "$path" in
        *$'\n'* | *$'\r'* | *"/../"* | *"/..")
            io_error "refusing suspicious path: $path"
            return 1
            ;;
    esac
    path="${path#/}"
    IFS=/ read -r -a segs <<<"$path"
    for ((i = 0; i < ${#segs[@]}; i++)); do
        seg="${segs[i]}"
        if [[ -z "$seg" || "$seg" == ".." || "$seg" == "." ]]; then
            continue
        fi
        cur="$cur/$seg"
        if [[ -L "$cur" ]]; then
            io_error "refusing symlink in path chain: $cur"
            return 1
        fi
        if [[ -e "$cur" && ! -d "$cur" ]]; then
            io_error "non-directory in path chain: $cur"
            return 1
        fi
    done
    return 0
}

_fs_atomic_mv() {
    local dst="$1" tmp="$2"
    if [[ -d "$dst" ]]; then
        rm -f -- "$tmp" 2>/dev/null || :
        io_error "refusing to replace directory: $dst"
        return 1
    fi
    if mv -fT -- "$tmp" "$dst" 2>/dev/null; then
        return 0
    fi
    rm -f -- "$tmp" 2>/dev/null || :
    io_error "cannot move temp into place: $dst"
    return 1
}

fs_backup() {
    local src="${1:-}" base ts bkp target tmp i
    if [[ -z "$src" ]]; then
        io_error "fs_backup requires a source path"
        return 1
    fi
    [[ -f "$src" ]] || {
        io_error "cannot back up non-regular or missing path: $src"
        return 1
    }
    case "$src" in
        *"|"*) io_error "refusing path containing '|': $src"; return 1 ;;
    esac
    if [[ -z "${FS_STATE_DIR:-}" ]]; then
        io_error "fs_backup requires initialized state (lib/state.sh)"
        return 1
    fi
    target="$FS_STATE_DIR/backups/files"
    _fs_chain_ok "$target" || return 1
    if ! mkdir -p -- "$target" 2>/dev/null; then
        io_error "cannot create backups dir: $target"
        return 1
    fi
    _fs_chain_ok "$target" || return 1
    base="${src##*/}"
    printf -v ts '%(%Y%m%dT%H%M%S)T' -1
    bkp="$target/$base.$ts.$$"
    i=1
    while [[ -e "$bkp" ]]; do
        bkp="$target/$base.$ts.$$.$i"
        i=$(( i + 1 ))
    done
    tmp="$(mktemp -- "$target/fs-backup.XXXXXX" 2>/dev/null)" || {
        io_error "cannot create temp in: $target"
        return 1
    }
    if ! cp -p -- "$src" "$tmp" 2>/dev/null; then
        rm -f -- "$tmp" 2>/dev/null || :
        io_error "cannot copy source: $src"
        return 1
    fi
    if ! mv -fT -- "$tmp" "$bkp" 2>/dev/null; then
        rm -f -- "$tmp" 2>/dev/null || :
        io_error "cannot finalize backup: $bkp"
        return 1
    fi
    if declare -F state_backup_add >/dev/null 2>&1; then
        if ! state_backup_add "$src" "$bkp"; then
            rm -f -- "$bkp" 2>/dev/null || :
            io_error "backup registry update failed; removed $bkp"
            return 1
        fi
    fi
    printf '%s' "$bkp"
}

fs_install() {
    local src="${1:-}" dst="${2:-}" tmp
    if [[ -z "$src" || -z "$dst" ]]; then
        io_error "fs_install requires source and destination"
        return 1
    fi
    case "$dst" in
        *$'\n'* | *$'\r'* | */ | .. | ../* | *"/../"* | *"/..")
            io_error "invalid destination: $dst"
            return 1
            ;;
    esac
    [[ -f "$src" ]] || {
        io_error "source not found: $src"
        return 1
    }
    if [[ -d "$dst" ]]; then
        io_error "destination is a directory: $dst"
        return 1
    fi
    _fs_parent "$dst"
    if ! mkdir -p -- "$_FS_PARENT" 2>/dev/null; then
        io_error "cannot create parent dir for: $dst"
        return 1
    fi
    tmp="$(mktemp -- "${dst}.XXXXXX" 2>/dev/null)" || {
        io_error "cannot create temp for: $dst"
        return 1
    }
    if ! cp -p -- "$src" "$tmp" 2>/dev/null; then
        rm -f -- "$tmp" 2>/dev/null || :
        io_error "cannot copy source: $src"
        return 1
    fi
    if [[ -e "$dst" ]]; then
        if ! fs_backup "$dst" >/dev/null; then
            rm -f -- "$tmp" 2>/dev/null || :
            return 1
        fi
    fi
    _fs_atomic_mv "$dst" "$tmp"
}

_fs_locate() {
    local -n arr="$1"
    local begin="$2" end="$3" i
    _FS_B=-1
    _FS_E=-1
    _FS_BC=0
    _FS_EC=0
    for ((i = 0; i < ${#arr[@]}; i++)); do
        if [[ "${arr[i]}" == "$begin" ]]; then
            _FS_BC=$(( _FS_BC + 1 ))
            _FS_B=$i
        fi
        if [[ "${arr[i]}" == "$end" ]]; then
            _FS_EC=$(( _FS_EC + 1 ))
            _FS_E=$i
        fi
    done
}

_fs_locate_ok() {
    [[ "$_FS_BC" -eq 1 && "$_FS_EC" -eq 1 && "$_FS_E" -gt "$_FS_B" ]]
}

_fs_block_lines() {
    local content="$1"
    _FS_BLOCK=()
    if [[ -n "$content" ]]; then
        if [[ "$content" == *$'\n' ]]; then
            content="${content%$'\n'}"
        fi
        while [[ "$content" == *$'\n'* ]]; do
            _FS_BLOCK+=("${content%%$'\n'*}")
            content="${content#*$'\n'}"
        done
        _FS_BLOCK+=("$content")
    fi
}

_fs_write_atomic() {
    local file="$1" tmp mode=""
    local -a lines=()
    if (( $# > 1 )); then
        lines=("${@:2}")
    fi
    if [[ -f "$file" && ! -L "$file" ]]; then
        mode="$(stat -c %a -- "$file" 2>/dev/null)" || mode=""
    fi
    tmp="$(mktemp -- "${file}.XXXXXX" 2>/dev/null)" || {
        io_error "cannot create temp for: $file"
        return 1
    }
    if test "${#lines[@]}" -eq 0; then
        if ! : >"$tmp" 2>/dev/null; then
            rm -f -- "$tmp" 2>/dev/null || :
            io_error "cannot write temp: $tmp"
            return 1
        fi
    elif ! printf '%s\n' "${lines[@]}" >"$tmp" 2>/dev/null; then
        rm -f -- "$tmp" 2>/dev/null || :
        io_error "cannot write temp: $tmp"
        return 1
    fi
    if [[ -n "$mode" ]]; then
        if ! chmod "$mode" -- "$tmp" 2>/dev/null; then
            rm -f -- "$tmp" 2>/dev/null || :
            io_error "cannot preserve mode for: $file"
            return 1
        fi
    fi
    _fs_atomic_mv "$file" "$tmp"
}

fs_managed_block() {
    local file="${1:-}" name="${2:-}" content="${3:-}" begin end changed i
    local -a in=() out=() mid=()
    if [[ -z "$file" || -z "$name" ]]; then
        io_error "fs_managed_block requires a file and a name"
        return 1
    fi
    case "$file" in
        *$'\n'* | *$'\r'* | */ | .. | ../* | *"/../"* | *"/..")
            io_error "invalid managed block file: $file"
            return 1
            ;;
    esac
    if ! _fs_valid_name "$name"; then
        io_error "invalid managed block name"
        return 1
    fi
    begin="# BEGIN fedora-setup $name"
    end="# END fedora-setup $name"
    if [[ -e "$file" ]]; then
        [[ -f "$file" ]] || {
            io_error "managed block target not a regular file: $file"
            return 1
        }
        [[ -r "$file" ]] || {
            io_error "cannot read: $file"
            return 1
        }
        if ! mapfile -t in <"$file"; then
            io_error "cannot read: $file"
            return 1
        fi
        _fs_validate_markers in || return 1
    fi
    _fs_locate in "$begin" "$end"
    if [[ "$_FS_BC" -gt 0 || "$_FS_EC" -gt 0 || "$_FS_B" -ge 0 || "$_FS_E" -ge 0 ]]; then
        _fs_locate_ok || {
            io_error "malformed managed block ($name) in: $file"
            return 1
        }
    fi
    _fs_block_lines "$content"
    for ((i = 0; i < ${#_FS_BLOCK[@]}; i++)); do
        case "${_FS_BLOCK[i]}" in
            "# BEGIN fedora-setup" | "# BEGIN fedora-setup "* | "# END fedora-setup" | "# END fedora-setup "*)
                io_error "managed block content contains a marker line"
                return 1
                ;;
        esac
    done
    if _fs_locate_ok; then
        mid=()
        for ((i = _FS_B + 1; i < _FS_E; i++)); do
            mid+=("${in[i]}")
        done
        if _fs_array_equal mid _FS_BLOCK; then
            return 0
        fi
        out=()
        if (( _FS_B > 0 )); then
            out+=("${in[@]:0:_FS_B}")
        fi
        out+=("$begin")
        if (( ${#_FS_BLOCK[@]} > 0 )); then
            out+=("${_FS_BLOCK[@]}")
        fi
        out+=("$end")
        if (( _FS_E + 1 < ${#in[@]} )); then
            out+=("${in[@]:_FS_E+1}")
        fi
        changed=1
    else
        out=()
        if (( ${#in[@]} > 0 )); then
            out+=("${in[@]}")
        fi
        out+=("$begin")
        if (( ${#_FS_BLOCK[@]} > 0 )); then
            out+=("${_FS_BLOCK[@]}")
        fi
        out+=("$end")
        changed=1
    fi
    if (( changed )); then
        _fs_parent "$file"
        if ! mkdir -p -- "$_FS_PARENT" 2>/dev/null; then
            io_error "cannot create parent dir for: $file"
            return 1
        fi
        if [[ -e "$file" ]]; then
            fs_backup "$file" >/dev/null || return 1
        fi
        if (( ${#out[@]} > 0 )); then
            _fs_write_atomic "$file" "${out[@]}"
        else
            _fs_write_atomic "$file"
        fi
    fi
}

fs_managed_block_remove() {
    local file="${1:-}" name="${2:-}" begin end
    local -a in=() out=()
    if [[ -z "$file" || -z "$name" ]]; then
        io_error "fs_managed_block_remove requires a file and a name"
        return 1
    fi
    case "$file" in
        *$'\n'* | *$'\r'* | */ | .. | ../* | *"/../"* | *"/..")
            io_error "invalid managed block file: $file"
            return 1
            ;;
    esac
    if ! _fs_valid_name "$name"; then
        io_error "invalid managed block name"
        return 1
    fi
    if [[ ! -e "$file" ]]; then
        return 0
    fi
    [[ -f "$file" ]] || {
        io_error "managed block target not a regular file: $file"
        return 1
    }
    [[ -r "$file" ]] || {
        io_error "cannot read: $file"
        return 1
    }
    begin="# BEGIN fedora-setup $name"
    end="# END fedora-setup $name"
    if ! mapfile -t in <"$file"; then
        io_error "cannot read: $file"
        return 1
    fi
    _fs_validate_markers in || return 1
    _fs_locate in "$begin" "$end"
    if [[ "$_FS_BC" -gt 0 || "$_FS_EC" -gt 0 || "$_FS_B" -ge 0 || "$_FS_E" -ge 0 ]]; then
        _fs_locate_ok || {
            io_error "malformed managed block ($name) in: $file"
            return 1
        }
    else
        return 0
    fi
    out=()
    if (( _FS_B > 0 )); then
        out+=("${in[@]:0:_FS_B}")
    fi
    if (( _FS_E + 1 < ${#in[@]} )); then
        out+=("${in[@]:_FS_E+1}")
    fi
    fs_backup "$file" >/dev/null || return 1
    if (( ${#out[@]} > 0 )); then
        _fs_write_atomic "$file" "${out[@]}"
    else
        _fs_write_atomic "$file"
    fi
}

fs_dedupe_lines() {
    local file="${1:-}" line=""
    local -a in=() out=()
    local -A seen=()
    local -i i=0 dup=0
    if [[ -z "$file" ]]; then
        io_error "fs_dedupe_lines requires a file path"
        return 1
    fi
    case "$file" in
        *$'\n'* | *$'\r'* | */ | .. | ../* | *"/../"* | *"/..")
            io_error "invalid dedupe target: $file"
            return 1
            ;;
    esac
    [[ -f "$file" ]] || {
        io_error "cannot dedupe non-regular path: $file"
        return 1
    }
    [[ -r "$file" ]] || {
        io_error "cannot read: $file"
        return 1
    }
    if [[ -z "${FS_STATE_DIR:-}" ]]; then
        io_error "fs_dedupe_lines requires initialized state (lib/state.sh)"
        return 1
    fi
    if ! mapfile -t in <"$file"; then
        io_error "cannot read: $file"
        return 1
    fi
    for ((i = 0; i < ${#in[@]}; i++)); do
        line="${in[i]}"
        if [[ -n "${seen["L$line"]:-}" ]]; then
            dup=$(( dup + 1 ))
            continue
        fi
        seen["L$line"]=1
        out+=("$line")
    done
    if (( dup == 0 )); then
        printf '0\n'
        return 0
    fi
    fs_backup "$file" >/dev/null || return 1
    _fs_write_atomic "$file" "${out[@]}" || return 1
    printf '%d\n' "$dup"
}