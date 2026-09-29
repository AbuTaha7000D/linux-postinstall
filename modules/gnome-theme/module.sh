#!/usr/bin/env bash
# modules/gnome-theme/module.sh - metadata for the GNOME theme module (P6.4).
# Applies a GTK theme and a cursor theme to org.gnome.desktop.interface and
# dedupes the gtk-3.0 bookmarks file. The theme source is, in order of
# precedence: FS_THEME_NAME (explicit, trusted even if the theme dir is
# absent), exactly one theme dir under FS_THEME_SRC (default
# $HOME/.themes), or exactly one theme dir under FS_THEME_ASSETS_DIR
# (default $root/assets/themes); cursors mirror via FS_CURSOR_NAME /
# FS_CURSOR_SRC ($HOME/.icons) / FS_CURSOR_ASSETS_DIR ($root/assets/cursors).
# The icon theme is NEVER touched (prototype bug #5 fix: icons_and_cursors.sh
# force-reset user icons to Adwaita - P6.4 restores prototype fidelity).
# Hooks-only module (no package/flatpak lists): GNOME availability is
# guarded inside run() like gnome-base; whole-profile desktop gating is P6.5.
MODULE_ID=gnome-theme
MODULE_TITLE=GNOME theme configuration
MODULE_DESCRIPTION=GTK + cursor theme selection, bookmarks dedupe
MODULE_RISK=medium
MODULE_DEFAULT=on