#!/bin/bash
# Manage the project's alias block in shell rc files (idempotent, non-destructive).
# Alias definitions live in additions/aliases/: one file per shell plus a shared
# distro fragment. This module only detects targets, composes the managed block,
# validates it, backs up once, and replaces the block atomically.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

BLOCK_BEGIN="# >>> linux-postinstall aliases >>>"
BLOCK_END="# <<< linux-postinstall aliases <<<"
ALIASES_DIR="$SCRIPT_DIR/additions/aliases"
FAMILY="$(distribution)"

# Shell config files that can receive the block.
shell_target() {
    case "$1" in
        bash) printf '%s\n' "$HOME/.bashrc" ;;
        zsh)  printf '%s\n' "$HOME/.zshrc" ;;
        fish) printf '%s\n' "$HOME/.config/fish/config.fish" ;;
    esac
}

# A shell is a target when its rc file already exists or its binary is present.
shell_wanted() {
    case "$1" in
        bash) return 0 ;;
        zsh)  [ -f "$HOME/.zshrc" ] || command -v zsh >/dev/null 2>&1 ;;
        fish) [ -f "$HOME/.config/fish/config.fish" ] || command -v fish >/dev/null 2>&1 ;;
    esac
}

# Print the selected shell's alias file followed by the shared distro fragment.
compose_fragment() {
    local shell="$1"
    cat "$ALIASES_DIR/$shell"
    case "$FAMILY" in
        debian|redhat|arch) cat "$ALIASES_DIR/distro/$FAMILY" ;;
    esac
}

# Print every line outside the managed block. Exit nonzero on a malformed
# marker state (BEGIN without END, orphan END, or a nested BEGIN).
strip_blocks() {
    local file="$1"
    awk -v b="$BLOCK_BEGIN" -v e="$BLOCK_END" '
        $0 == b { if (inside) bad = 1; inside = 1; next }
        $0 == e { if (!inside) bad = 1; else inside = 0; next }
        { if (!inside) print }
        END { if (inside) bad = 1; if (bad) exit 1 }
    ' "$file"
}

# Nearest existing ancestor directory, used for the writability check.
find_existing_dir() {
    local d="$1"
    while [ ! -d "$d" ] && [ "$d" != "/" ] && [ "$d" != "." ]; do
        d="$(dirname "$d")"
    done
    printf '%s\n' "$d"
}

target_writable() {
    local f="$1" dir
    dir="$(dirname "$f")"
    # The destination directory must be able to receive the staging file.
    if [ -d "$dir" ]; then
        [ -w "$dir" ] || return 1
    else
        [ -w "$(find_existing_dir "$dir")" ] || return 1
    fi
    # Existing files must also be readable and writable.
    if [ -e "$f" ]; then
        [ -r "$f" ] || return 1
        [ -w "$f" ] || return 1
    fi
    return 0
}

# Read-only validation: symlinks, malformed blocks, and writability.
validate_target() {
    local f="$1"
    if [ -L "$f" ]; then
        echo "Error: refusing to modify symlinked file: $f" >&2
        return 1
    fi
    if [ -e "$f" ] && [ ! -f "$f" ]; then
        echo "Error: not a regular file: $f" >&2
        return 1
    fi
    if [ -f "$f" ] && ! strip_blocks "$f" >/dev/null; then
        echo "Error: malformed linux-postinstall alias block in $f" >&2
        return 1
    fi
    if ! target_writable "$f"; then
        echo "Error: not writable: $f" >&2
        return 1
    fi
    return 0
}

# Fragment-only syntax validation with the real interpreter, when available.
validate_fragment() {
    local shell="$1" interp
    local -a flags
    interp="$(command -v "$shell" 2>/dev/null || true)"
    [ -n "$interp" ] || return 0
    case "$shell" in
        bash) flags=(--noprofile --norc -n) ;;
        zsh)  flags=(-f -n) ;;
        fish) flags=(--no-config --no-execute) ;;
    esac
    if ! compose_fragment "$shell" | "$interp" "${flags[@]}" 2>/dev/null; then
        echo "Error: generated alias block failed $shell syntax validation" >&2
        return 1
    fi
    return 0
}

# Write the cleaned file plus one fresh block, staged next to the target and
# swapped in atomically. The staging file is created exclusively with mktemp so
# a predictable path can never be pre-created, followed, or clobbered.
# Replacement preserves the existing file's security metadata: for existing
# targets the staging file is a `cp -a` copy of the target, so mode, ownership,
# ACLs, extended attributes, and SELinux context carry over (and any
# preservation failure aborts before the target is replaced). New files are
# created owner-only (0600) by policy. Failure leaves earlier targets updated
# (no rollback).
TMP_FILES=()
cleanup_temps() {
    local t
    for t in "${TMP_FILES[@]}"; do
        if [ -n "$t" ]; then
            rm -f "$t"
        fi
    done
    return 0
}
trap cleanup_temps EXIT

write_block() {
    local shell="$1" f="$2" dir tmp
    dir="$(dirname "$f")"
    mkdir -p "$dir"
    # Exclusive, unpredictable staging file in the destination directory, so a
    # pre-existing path can never be followed or clobbered. mktemp creates it
    # owner-only (0600); existing targets then receive their metadata via cp -a.
    tmp="$(mktemp -- "$dir/.linux-postinstall.XXXXXX")"
    TMP_FILES+=("$tmp")
    if [ -f "$f" ]; then
        # Stage a metadata-preserving copy, then rewrite its contents in place.
        cp -a -- "$f" "$tmp"
        strip_blocks "$f" > "$tmp"
    fi
    {
        printf '%s\n' "$BLOCK_BEGIN"
        compose_fragment "$shell"
        printf '%s\n' "$BLOCK_END"
    } >> "$tmp"
    mv -f "$tmp" "$f"
    echo "Alias block written to $f."
}

main() {
    case "$FAMILY" in
        debian|redhat|arch) ;;
        *) echo "Warning: unsupported distribution; writing shell aliases without distro aliases." >&2 ;;
    esac

    local -a shells=() files=()
    local s f i
    for s in bash zsh fish; do
        if shell_wanted "$s"; then
            shells+=("$s")
            files+=("$(shell_target "$s")")
        fi
    done

    # Phase A: read-only validation of every target before any mutation.
    for s in "${shells[@]}"; do
        if [ ! -f "$ALIASES_DIR/$s" ]; then
            echo "Error: missing alias definition file: $ALIASES_DIR/$s" >&2
            exit 1
        fi
    done
    case "$FAMILY" in
        debian|redhat|arch)
            if [ ! -f "$ALIASES_DIR/distro/$FAMILY" ]; then
                echo "Error: missing distro alias file: $ALIASES_DIR/distro/$FAMILY" >&2
                exit 1
            fi
            ;;
    esac
    for ((i = 0; i < ${#shells[@]}; i++)); do
        validate_target "${files[$i]}" || exit 1
    done
    for s in "${shells[@]}"; do
        validate_fragment "$s" || exit 1
    done

    if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
        for ((i = 0; i < ${#shells[@]}; i++)); do
            f="${files[$i]}"
            if [ -e "$f" ]; then
                echo "would run: back up $f to $f.linux-postinstall.bak (if missing)"
            fi
            echo "would run: write linux-postinstall alias block to $f"
        done
        return 0
    fi

    # Phase B: one-time backup, never overwriting an existing backup. Uses a
    # metadata-preserving copy; failure aborts before any target is modified.
    for ((i = 0; i < ${#shells[@]}; i++)); do
        f="${files[$i]}"
        if [ -e "$f" ] && [ ! -e "$f.linux-postinstall.bak" ]; then
            cp -a -- "$f" "$f.linux-postinstall.bak"
        fi
    done

    # Phase C: write in stable order bash -> zsh -> fish.
    for ((i = 0; i < ${#shells[@]}; i++)); do
        write_block "${shells[$i]}" "${files[$i]}"
    done

    echo "Aliases set successfully!"
}

main
