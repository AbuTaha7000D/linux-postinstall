#!/usr/bin/env bash
# modules/dev/module.sh - metadata for the developer-toolchains module.
# Pure system-package module (P7.3): no flatpaks.list, no hooks.sh, no
# verify() hook (system-row verification belongs to P9.2 `setup verify`,
# which talks to the pkg backend -- a hook-local query would be the P5.7
# NB-A trap).
# Exactly ONE of this module's package names diverges per family: pip is
# python3-pip on rpm/deb and python-pip on arch. That divergent name is
# declared ONLY in the per-family files and deliberately absent from
# packages.list: per lib/lists.sh a family file OVERRIDES only SAME-NAMED
# common entries, so naming both python3-pip and python-pip across a
# common+family pair would install BOTH, not swap one for the other.
# Everything else shares one name across the three families and lives in the
# common list -- including jupyter-notebook, which is NOT a divergent name
# (archlinux.org's package search returns no `jupyter` package at all, so an
# earlier `jupyter` row for arch would have broken the whole transaction with
# `target not found`). Every name here is a plain base-repo package (no
# RPM Fusion / no AUR). The runner batches the merged per-family set through
# the active family backend in a single transaction.
MODULE_ID=dev
MODULE_TITLE=Dev toolchains
MODULE_DESCRIPTION=Compiler toolchain, node, python pip and jupyter-notebook
MODULE_RISK=none
MODULE_DEFAULT=on