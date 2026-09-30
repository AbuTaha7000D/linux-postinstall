#!/usr/bin/env bash
# shellcheck disable=SC2209  # data file: MODULE_* values are strings, not commands
# modules/apps/module.sh - metadata for the curated desktop-apps module.
# A purely declarative flatpak module (P7.1): flatpaks.list drives the
# install. The flathub remote is ensured (--if-not-exists) ahead of every
# install transaction by the flatpak backend (lib/pkg/flatpak.sh, P3.6) and
# the flatpak CLI itself ships in core (P5.1) -- this module declares only
# app ids. P5.7 NB-A routing sends flatpaks.list through the flatpak
# backend in a single batch. hooks.sh exists because P7.1 adds a read-only
# verify() hook: run() is a documented no-op (the runner already performed
# the flatpak batch at stage 3) and verify() confirms every curated app is
# installed (flatpak info --user then --system) without writing anything.
MODULE_ID=apps
MODULE_TITLE="Desktop apps"
MODULE_DESCRIPTION="Curated Flatpak desktop applications"
MODULE_RISK=none
MODULE_DEFAULT=on
