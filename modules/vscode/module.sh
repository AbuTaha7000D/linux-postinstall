#!/usr/bin/env bash
# shellcheck disable=SC2209  # data file: MODULE_* values are strings, not commands
# modules/vscode/module.sh - metadata for the Visual Studio Code module.
#
# The only module so far that adds a THIRD-PARTY package repository, which
# is why it is shaped the way it is:
#
#   1. THE REPOSITORY MUST EXIST BEFORE THE PACKAGE INSTALLS. `code` is not
#      in any base repository, so the repo file has to be written before the
#      batch that installs it. hooks.sh runs AFTER the batch (P4.6), so this
#      module uses the P7.5 pre-batch hook prerepo.sh/prerepo() instead:
#      the runner calls it after list collection and before the batch, in a
#      subshell with the same sandbox rules as run(). There is deliberately
#      no hooks.sh -- a run() step would be the wrong place for a repository,
#      and an empty one would fail the module.
#
#   2. THE KEY IS PINNED, NOT TRUSTED. prerepo.sh downloads the armored key
#      and refuses to import anything whose primary-key fingerprint is not
#      the value committed in config/vscode-gpg.fingerprint (see that file
#      for the measured provenance and the re-verify recipe). The PRIMARY
#      fingerprint is the anchor, never a subkey's, and a key file holding
#      more than one key is refused outright, so the check cannot be
#      satisfied by a bundle whose first key is the expected one. This is
#      stricter than the vendor default: Microsoft's own config.repo in the
#      same directory ships gpgcheck=0 and repo_gpgcheck=0, i.e. it does not
#      check package signatures at all.
#
#   3. rpm AND deb NEED DIFFERENT KEY HANDLING, so the hook branches on the
#      family the runner resolved (FS_MODULE_FAMILY, set in the hook
#      subshell -- the hook never re-detects the distro):
#        rpm  rpm --import into the rpmdb, then the repo file with
#             gpgcheck=1 and no gpgkey= line (the key is already in the db);
#        deb  gpg --dearmor into a TOOL-OWNED keyring, then the sources
#             entry with signed-by=<that keyring> (the same one-line form
#             Microsoft's own instructions use).
#      A tool-owned keyring name is used rather than Microsoft's
#      /usr/share/keyrings/microsoft.gpg so this tool never overwrites a
#      file it did not create.
#
# REPOSITORY URLS (measured 2026-09-29; the pinned key and its
# re-verification recipe are in ../../config/vscode-gpg.fingerprint, which
# is committed with this module -- ROADMAP.md is gitignored and is not a
# place a reader can look). The task text's `vscode.repo` file name is
# stale: both
# https://packages.microsoft.com/yumrepos/code.repo and .../vscode.repo
# answer 404 today. What the vendor actually serves is a repository
# DIRECTORY plus a config.repo inside it, whose baseurl is the directory
# itself:
#   rpm  baseurl https://packages.microsoft.com/yumrepos/vscode/
#   deb  https://packages.microsoft.com/repos/code stable main
# Both are written by the P3 pkg layer (pkg_add_repo), which is
# --if-not-exists by contract, so a re-run never rewrites or duplicates a
# repo file, and the file name comes from the repo id (vscode.repo /
# vscode.list).
#
# FAMILY SCOPE (owner decision, P7.5):
#   rpm/deb  the official Microsoft repository and the `code` package --
#             the repository's own metadata (repodata primary.xml on rpm,
#             the dists Packages index on deb) lists `code` for
#             x86_64/aarch64/armv7hl and amd64 respectively.
#   arch     NOTHING is installed and no repository is added. VS Code has
#             no official Arch package: the AUR names this task assumed
#             (code, vscode, vscode-bin) are all absent from the AUR RPC
#             API, and the only live package is visual-studio-code-bin,
#             which needs an AUR helper (paru/yay) or a manual makepkg
#             build. Neither belongs in a bootstrap tool, so the flatpak
#             build below is the documented route. packages.arch.list
#             exists and is comment-only so the P4.2 list-usability gate
#             passes and the skip is explicit data, not an accident.
#
# THE FLATPAK ALTERNATIVE (owner decision, P7.5) is the single Flathub app
# id com.visualstudio.code, declared statically as the P7.5
# flatpak-alternative pair below. Setting FS_VSCODE_FLATPAK=1 (or true/yes/
# on) makes the module contribute ONLY that id to the flatpak namespace and
# nothing at all to the system namespace, so the two paths can never install
# side by side, and prerepo() becomes a no-op -- no repository, no key, no
# privileged step. The id was verified against the Flathub appstream API
# (com.visualstudio.code 200, org.visualstudio.code 404). This is also the
# route for arch.
#
# WHY MODULE_RISK=medium: the module changes where packages may come from
# on the machine (a new repository file in /etc) and adds a trusted signing
# key. It is not destructive -- it removes nothing, overwrites nothing
# (--if-not-exists), and `rpm --remove`/deleting one file reverses it --
# but it is a trust-surface change, not just a package install, so it does
# not get the `none` of a pure base-repo module.
#
# No verify() hook: whether `code` is actually installed is a system-row
# question for P9.2 `setup verify`, which asks the pkg backend; a hook-local
# query would be the P5.7 NB-A family trap. `./setup install --dry-run
# --yes vscode` is the way to see what would happen.
MODULE_ID=vscode
MODULE_TITLE="Visual Studio Code"
MODULE_DESCRIPTION="Official Microsoft code repository and key, or the flatpak build"
MODULE_RISK=medium
MODULE_DEFAULT=on
# WHY MODULE_PRIVILEGED=1: prerepo() imports a repository key into the rpmdb
# or a tool-owned deb keyring, which escalates. The runner reads this
# declaration (never the presence of prerepo.sh) to decide whether to
# establish the sudo credential up front.
MODULE_PRIVILEGED=1
MODULE_FLATPAK_ALT_ID=com.visualstudio.code
MODULE_FLATPAK_ALT_SEAM=FS_VSCODE_FLATPAK
