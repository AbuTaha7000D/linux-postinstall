#!/usr/bin/env bash
# modules/flatpak/module.sh - metadata for the base-apps flatpak module.
# Installs a curated small set of GUI apps from Flathub. The flathub remote is
# ensured (--if-not-exists) ahead of every install transaction by the flatpak
# backend (lib/pkg/flatpak.sh, P3.6). The flatpak CLI itself comes from the
# core module's common packages (P5.1); this module only declares flatpaks.
# P5.7 NB-A routing (corrective fix): the runner splits
# namespaces -- packages batch via the family backend, flatpaks via the
# flatpak backend (lib/pkg/flatpak.sh), system first so the flatpak CLI lands
# before any app install. Evidenced by tests/fixtures/{install_profiles,
# mod_flatpak,runner}.sh (mock + stateful fake flatpak).
MODULE_ID=flatpak
MODULE_TITLE=Flatpak apps
MODULE_DESCRIPTION=Flathub plus a curated base set of GUI applications
MODULE_RISK=none
MODULE_DEFAULT=on