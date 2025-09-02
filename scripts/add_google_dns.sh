#!/bin/bash
# Add Google DNS to /etc/resolv.conf, robust for all distros
set -e

RESOLV_CONF="/etc/resolv.conf"
BACKUP="/etc/resolv.conf.bak"

if [ -L "$RESOLV_CONF" ]; then
    echo "Warning: $RESOLV_CONF is a symlink. Not modifying to avoid breaking system DNS."
    ls -l "$RESOLV_CONF"

	for i in 3 2 1; do
    echo -ne "\rContinue in $i .. "
    sleep 1
	done
	echo -e "\n#################### Canceled! ####################"
    exit 1
fi

sudo cp "$RESOLV_CONF" "$BACKUP"
echo "Backup of $RESOLV_CONF created."

sudo rm "$RESOLV_CONF"
echo -e "nameserver 8.8.8.8\nnameserver 8.8.4.4" | sudo tee "$RESOLV_CONF" > /dev/null

# Check for chattr
if command -v chattr >/dev/null 2>&1; then
    sudo chattr +i "$RESOLV_CONF"
    echo "chattr +i applied to $RESOLV_CONF."
else
    echo "Warning: chattr not found, skipping immutable flag."
fi

# Check for NetworkManager
if systemctl list-unit-files | grep -q NetworkManager; then
    sudo systemctl restart NetworkManager
    echo "NetworkManager restarted."
else
    echo "Warning: NetworkManager not found, please restart your network service manually if needed."
fi

echo "Google DNS added."
for i in 3 2 1; do
    echo -ne "\rContinue in $i .. "
    sleep 1
done
echo -e "\n#################### Done! ####################"