#!/bin/bash
# Install user fonts from assets/fonts
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

FONT_DIR="$SCRIPT_DIR/assets/fonts"
FONT_DEST="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"

if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
    echo "would run: mkdir -p \"$FONT_DEST\""
    echo "would run: cp -r \"$FONT_DIR\"/* \"$FONT_DEST\"/"
    echo "would run: fc-cache -f"
    exit 0
fi

if [ ! -d "$FONT_DIR" ]; then
    echo "Error: Font directory '$FONT_DIR' does not exist." >&2
    exit 1
fi

if [ -z "$(ls -A "$FONT_DIR" 2>/dev/null)" ]; then
    echo "Error: No font files found in '$FONT_DIR'." >&2
    exit 1
fi

if ! command -v fc-cache >/dev/null 2>&1; then
    echo "Error: fc-cache (fontconfig) not found. Install fontconfig and re-run." >&2
    exit 1
fi

if ! run mkdir -p "$FONT_DEST"; then
    echo "Error: Failed to create font directory '$FONT_DEST'." >&2
    exit 1
fi

if ! run cp -r "$FONT_DIR"/* "$FONT_DEST"/; then
    echo "Error: Failed to copy fonts from '$FONT_DIR' to '$FONT_DEST'." >&2
    exit 1
fi

if ! run fc-cache -f; then
    echo "Error: Fonts were copied to '$FONT_DEST' but the font cache was not refreshed." >&2
    exit 1
fi

echo "Fonts installed successfully!"
