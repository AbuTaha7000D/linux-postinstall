#!/bin/bash
# Configure terminal theme (Oh My Posh + Bash)
set -e

# Check for required commands
for cmd in bash curl wget unzip; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: $cmd is required. Please install $cmd and try again." >&2
        exit 1
    fi
done

# Always set Bash as the default shell
if [ "$SHELL" != "/bin/bash" ] && [ "$SHELL" != "/usr/bin/bash" ]; then
    if command -v bash >/dev/null 2>&1; then
        echo "Setting Bash as the default shell..."
        chsh -s "$(command -v bash)"
        echo "Default shell changed to Bash."
    else
        echo "Warning: Bash not found, cannot set as default shell."
    fi
else
    echo "Bash is already the default shell."
fi

# Install Oh My Posh
if ! command -v oh-my-posh >/dev/null 2>&1; then
    echo "Installing Oh My Posh..."
    sudo wget https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/posh-linux-amd64 -O /usr/local/bin/oh-my-posh
    sudo chmod +x /usr/local/bin/oh-my-posh
fi
mkdir -p ~/.poshthemes
wget https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/themes.zip -O ~/.poshthemes/themes.zip
unzip -o ~/.poshthemes/themes.zip -d ~/.poshthemes
chmod u+rw ~/.poshthemes/*.json
rm ~/.poshthemes/themes.zip

# Add Oh My Posh init to Bash config if not present
BASHRC="$HOME/.bashrc"
if ! grep -q "oh-my-posh init bash" "$BASHRC"; then
    echo 'eval "$(oh-my-posh init bash --config ~/.poshthemes/montys.omp.json)"' >> "$BASHRC"
fi

echo "Terminal theme installed."
for i in 3 2 1; do
    echo -ne "\rContinue in $i .. "
    sleep 1
done
echo -e "\n#################### Done! ####################"