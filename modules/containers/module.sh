#!/usr/bin/env bash
# modules/containers/module.sh - metadata for the container-tooling module.
# Pure system-package module (P7.4): no flatpaks.list, no hooks.sh, no
# run() step and no verify() hook. Two reasons for the absent hooks:
#   1. OWNER DECISION (P7.4) - the module must never mutate users or
#      groups, so it has no run() step to do it from;
#   2. package-presence verification of a system row belongs to P9.2
#      `setup verify`, which talks to the pkg backend; a hook-local query
#      would be the P5.7 NB-A family trap.
#
# SCOPE: the podman stack only -- podman, buildah, skopeo, podman-compose.
# "compose" means podman-compose, the podman-native provider; no
# docker-compose plugin is installed.
#
# All four names are IDENTICAL on rpm, deb and arch (Ubuntu 26.04.1:
# podman 5.7.0, buildah 1.42.1, skopeo 1.21.0, podman-compose 1.5.0; all four
# in Arch extra; all four are long-standing Fedora base-repo packages), so
# they live in the common packages.list with no per-family override.
#
# DOCKER IS A DELIBERATE NON-GOAL for this module, for three reasons:
#   1. its package name is distro-specific and would need per-family
#      mapping (docker.io on deb, docker on arch) with no base-repo
#      equivalent confirmed on rpm -- Fedora ships moby-engine, and the
#      availability of a `docker` package name there could not be
#      established;
#   2. Docker's official packaging needs a third-party repository plus a
#      GPG key import, which belongs to a separately scoped repo-integration
#      task (P7.5 owns that shape for vscode), not here;
#   3. podman is rootless and daemonless, which is what this module ships.
# Anyone who wants Docker can install it themselves; the exact manual
# command is documentation only, never executed by this tool:
#   sudo usermod -aG docker "$USER"   # USER-INITIATED, not run by fedora-setup
#
# DOCKER GROUP MEMBERSHIP IS NEVER AUTOMATED. Membership of the `docker`
# group grants ROOT-EQUIVALENT host access (anyone in it can mount the host
# filesystem through the daemon), so this tool will not add, create or
# modify that group or any user's supplementary groups. If a future task
# ever adds an explicit, user-opted-in docker-group path, that privileged
# path must be MODULE_RISK=medium and must never become a silent mutation.
#
# ROOTLESS PREREQUISITE, DELIBERATELY NOT HANDLED HERE: podman's rootless
# mode needs a subordinate uid/gid range for the invoking user -- a
# `<user>:<start>:<count>` line in /etc/subuid and /etc/subgid. Those files
# are host uid/gid policy, so this tool does not create or edit them (same
# "never automate" reasoning as the docker group above); where a range is
# missing, rootless podman fails at newuidmap with `uid_map write failed:
# Operation not permitted` and the fix is the distro's own subuid management
# (USER-INITIATED, e.g. `sudo usermod --add-subuids ...`, never run by this
# tool). Diagnose with: grep "^$USER:" /etc/subuid /etc/subgid
#
# Because nothing here is privileged, MODULE_RISK stays `none`.
MODULE_ID=containers
MODULE_TITLE=Container tooling
MODULE_DESCRIPTION=Rootless podman, buildah, skopeo and podman-compose
MODULE_RISK=none
MODULE_DEFAULT=on