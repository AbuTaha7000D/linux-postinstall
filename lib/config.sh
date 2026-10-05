#!/usr/bin/env bash
# lib/config.sh - managed blocks in config files.
#
# Never rewrite a dotfile wholesale. Changes go between markers:
#
#   # BEGIN postinstall <name>
#   ...lines this tool owns...
#   # END postinstall <name>
#
# Everything outside the markers is left alone. If the block is already exactly
# right, nothing is written and no backup is taken, so re-running is a no-op.
# If it drifts, the previous file is copied to <file>.bak before being
# replaced.
#
# Sourced by setup; not executable on its own.

BLOCK_PREFIX="postinstall"

# block_name <file> <name> -- print the begin/end markers.
_block_markers() {
    printf '# BEGIN %s %s\n# END %s %s\n' "$BLOCK_PREFIX" "$1" "$BLOCK_PREFIX" "$1"
}

# block_present <file> <name> -- 0 when the file has a well-formed block.
block_present() {
    local file="$1" name="$2" begins ends
    begins="$(grep -c "^# BEGIN $BLOCK_PREFIX $name\$" -- "$file" 2>/dev/null || true)"
    ends="$(grep -c "^# END $BLOCK_PREFIX $name\$" -- "$file" 2>/dev/null || true)"
    [[ "$begins" == "1" && "$ends" == "1" ]]
}

# block_body <file> <name> -- print the current block body, or nothing.
block_body() {
    local file="$1" name="$2"
    block_present "$file" "$name" || return 1
    sed -n "/^# BEGIN $BLOCK_PREFIX $name\$/,/^# END $BLOCK_PREFIX $name\$/p" -- "$file" |
        sed '1d;$d'
}

# write_block <file> <name> -- replace the named block with stdin.
#
# Refuses to run when the file already has two blocks of the same name: that
# means the file is not one this tool can reason about, and rewriting it would
# silently drop one of them.
write_block() {
    local file="$1" name="$2"
    local want="" have="" begins

    want="$(cat)"
    [[ -n "$want" ]] || die "refusing to write an empty block to $file"

    begins="$(grep -c "^# BEGIN $BLOCK_PREFIX $name\$" -- "$file" 2>/dev/null || true)"
    if [[ "$begins" -gt 1 ]]; then
        die "$file has $begins '$name' blocks; merge them by hand first"
    fi

    if [[ -f "$file" ]]; then
        have="$(block_body "$file" "$name" || true)"
        if [[ "$have" == "$want" ]]; then
            log_info "unchanged: $file ($name)"
            return 0
        fi
    fi

    if ((FS_DRY_RUN)); then
        log_info "would update block: $file ($name)"
        return 0
    fi

    _backup_once "$file"
    {
        if block_present "$file" "$name"; then
            local line skip=0
            while IFS= read -r line || [[ -n "$line" ]]; do
                case "$line" in
                "# BEGIN $BLOCK_PREFIX $name") skip=1; continue ;;
                "# END $BLOCK_PREFIX $name") skip=0; continue ;;
                esac
                ((skip)) || printf '%s\n' "$line"
            done <"$file"
        elif [[ -f "$file" ]]; then
            cat -- "$file"
            printf '\n'
        fi
        printf '# BEGIN %s %s\n' "$BLOCK_PREFIX" "$name"
        printf '%s\n' "$want"
        printf '# END %s %s\n' "$BLOCK_PREFIX" "$name"
    } >"$file.new.$$" || {
        rm -f -- "$file.new.$$"
        die "cannot write $file"
    }
    mv -f -- "$file.new.$$" "$file" || {
        rm -f -- "$file.new.$$"
        die "cannot replace $file"
    }
    log_info "updated: $file ($name)"
}

_backup_once() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    cp -p -- "$file" "$file.bak" || die "cannot back up $file"
    log_info "backed up: $file -> $file.bak"
}
