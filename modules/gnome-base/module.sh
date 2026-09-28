#!/usr/bin/env bash
# modules/gnome-base/module.sh - metadata for the GNOME base module (P6.2).
# Merges a curated set of dock favorites into org.gnome.shell favorite-apps
# without disturbing existing user favorites (P6.2 verification: the dock
# contains existing plus new), registers the four custom shortcuts carried
# over from the prototype (Resources / Settings / Terminal / Toggle Mic) as
# relocatable-schema keybindings through the P6.1 merge (prototype bug #4
# fix: read->merge->write, never sed text surgery) and applies a wallpaper
# from assets/wallpaper (or FS_WALLPAPER_ASSETS_DIR) when an image is
# present. Favorites list is favorites.list; shortcuts are declared one per
# line as name|command|binding in shortcuts.list; both are parsed with the
# shared list grammar (comments/blank lines ignored, whole-line entries).
# Hooks-only module (no package/flatpak lists): the P4.2 family gate passes
# because no declared list files exist; running the module needs no distro
# packages. GNOME availability (gsettings on PATH + XDG_CURRENT_DESKTOP
# matching *GNOME*) is guarded inside run(), mirroring the prototype's own
# guard; desktop-gating for whole profiles arrives with P6.5.
MODULE_ID=gnome-base
MODULE_TITLE=GNOME base configuration
MODULE_DESCRIPTION=Favorite-apps merge, custom shortcuts, wallpaper
MODULE_RISK=low
MODULE_DEFAULT=on