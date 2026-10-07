#!/bin/bash
# Install fonts from additions/fonts
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

FONT_DIR="$SCRIPT_DIR/additions/fonts"

if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
    echo "would run: copy additions/fonts to ~/.fonts and refresh the font cache (fc-cache)"
    exit 0
fi

if [ ! -d "$FONT_DIR" ]; then
    echo "Error: Font directory '$FONT_DIR' does not exist." >&2
    exit 1
fi

run mkdir -p "$HOME/.fonts/"
run cp -r "$FONT_DIR"/* "$HOME/.fonts/"
if ! run fc-cache -f -v; then
    echo "Error updating font cache" >&2
    exit 1
fi
echo "Fonts installed successfully!"
