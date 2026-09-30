#!/usr/bin/env bash
# shellcheck disable=SC2209  # data file: MODULE_* values are strings, not commands
# modules/media/module.sh - metadata for the media-tools module (P7.2).
# Declarative module: OBS Studio is installed from the distro's own package
# where the base repos carry it (packages.deb.list / packages.arch.list =
# obs-studio) -- the "family-specific obs packaging where the distro
# differs" the phase mandates; the FILTER semantics of lib/lists.sh mean a
# family file overrides a same-named common entry and a comment-only family
# file contributes nothing. The rpm family has NO native obs-studio in base
# repos (rpmfusion-only), so packages.rpm.list is comment-only and rpm users
# get OBS via the flatpak alternative com.obsproject.Studio (or by enabling
# rpmfusion); the runner renders no system batch on rpm. The remaining
# curated media apps are GUI apps and follow the Flatpak-first owner rule
# (P5.7): flatpaks.list. P5.7 NB-A routing sends packages.*.list through the
# active FAMILY backend and flatpaks.list through the flatpak backend, system
# batch first. The flathub remote is ensured (--if-not-exists) ahead of every
# install transaction by the flatpak backend (lib/pkg/flatpak.sh, P3.6) and
# the flatpak CLI itself ships in core (P5.1) -- this module declares only
# package/app ids. hooks.sh provides run() (no-op) + read-only verify() over
# flatpaks.list only -- the native obs-studio row is left to P9.2 `setup
# verify`, which talks to the pkg backend; a hook-local native query would be
# the P5.7 NB-A trap (dispatch resolves the family backend).
MODULE_ID=media
MODULE_TITLE="Media tools"
MODULE_DESCRIPTION="OBS Studio + curated media flatpaks"
MODULE_RISK=none
MODULE_DEFAULT=on
