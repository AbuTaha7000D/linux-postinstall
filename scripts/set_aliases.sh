#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADDITIONS_DIR="$SCRIPT_DIR/additions"

# Copy the dynamic shell_conf aliases to .bashrc
set -e


# Backup .bashrc before overwriting
if [ -f "$HOME/.bashrc" ]; then
    cp "$HOME/.bashrc" "$HOME/.bashrc.bak"
    echo "Backup of .bashrc created at ~/.bashrc.bak."
fi
cp "$ADDITIONS_DIR/shell_conf" "$HOME/.bashrc"
echo "Aliases from shell_conf have replaced .bashrc."

echo "Aliases set successfully!"
for i in 3 2 1; do
    echo -ne "\rContinue in $i .. "
    sleep 1
done
echo -e "\n#################### Done! ####################"