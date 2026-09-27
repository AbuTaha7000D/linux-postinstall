#!/usr/bin/env bash
# modules/flatpak/module.sh - metadata for the base-apps flatpak module.
# Installs a curated small set of GUI apps from Flathub. The flathub remote is
# ensured (--if-not-exists) ahead of every install transaction by the flatpak
# backend (lib/pkg/flatpak.sh, P3.6). The flatpak CLI itself comes from the
# core module's common packages (P5.1); this module only declares flatpaks.
# NOTE (P5.7 owner decision): the runner batches packages and flatpaks through
# ONE plan_install against the active backend; fixture/runtime routing of
# flatpaks to the flatpak backend on a real host is still to be decided.
MODULE_ID=flatpak
MODULE_TITLE=Flatpak apps
MODULE_DESCRIPTION=Flathub plus a curated base set of GUI applications
MODULE_RISK=none
MODULE_DEFAULT=on