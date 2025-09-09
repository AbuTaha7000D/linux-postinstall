#!/bin/bash
# Install fonts from additions/fonts
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FONT_DIR="$SCRIPT_DIR/additions/fonts"

if [ ! -d "$FONT_DIR" ]; then
    echo "Error: Font directory '$FONT_DIR' does not exist." >&2
    exit 1
fi

mkdir -p "$HOME/.fonts/"
cp -r "$FONT_DIR"/* "$HOME/.fonts/"
fc-cache -f -v
if [ $? -eq 0 ]; then
    echo "Fonts installed successfully!"
else
    echo "Error updating font cache" >&2
    exit 1
fi
for i in 3 2 1; do
    echo -ne "\rContinue in $i .. "
    sleep 1
done
echo -e "\n#################### Done! ####################"
