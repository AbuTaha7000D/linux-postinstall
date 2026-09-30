#!/usr/bin/env bash
# lib/cli.sh - argument parsing and dispatch table for fedora-setup.
# Depends on lib/io.sh for io_error (source io.sh first).
# Global flags seed FS_* seams consumed by the bootstrap and every lib:
# FS_YES / FS_DRY_RUN / FS_VERBOSE / FS_DEBUG / FS_PROFILE / FS_LIST.
# --browse seeds FS_GNOME_BROWSE (module-scoped opt-in consumed only by
# the gnome-extensions module: open at most two curated extension pages).
# --force seeds FS_GNOME_FORCE (module-scoped opt-in consumed only by the
# GNOME capability gate gnome_require_capable: run every GNOME module even
# when the session looks non-GNOME / SSH / headless / gsettings-less).
#     FS_YES / FS_DRY_RUN / FS_VERBOSE / FS_DEBUG / FS_GNOME_BROWSE /
# FS_GNOME_FORCE each also honor a pre-set environment value (test seam);
# FS_PROFILE, FS_MANIFEST, FS_PULL and FS_LIST are unconditionally reset by
# cli_parse (seam-less by design). FS_PROFILE_SET records whether --profile was given
# EXPLICITLY, which FS_PROFILE alone cannot express: the bootstrap defaults an
# unset profile to "full", and a manifest re-import needs to tell "the user
# asked for full" from "nobody said anything".
# --pull seeds FS_PULL (P9.4: `update` only reports by default; this flag is
# the explicit opt-in that moves the working tree). Like FS_MANIFEST it is
# unconditionally reset by cli_parse (seam-less by design): an inherited
# FS_PULL=1 in the environment would reintroduce exactly the silent auto-pull
# lib/update.sh exists to remove. A caller that passes --pull to any command
# other than update is refused by the bootstrap.
# --manifest seeds FS_MANIFEST (P9.3: consume an exported tree instead of the
# live profile). It is a PATH, not a boolean, so cli_parse deliberately does
# not validate it here -- an unset, unreadable or non-conforming directory is
# the consumer's (bootstrap's) error to report, in the command that uses it.
# FS_LOG_FILE is deliberately NOT reset here, and P9.5 measured why the obvious
# hardening is wrong. It looks exactly like FS_PULL and FS_MANIFEST -- a path
# that redirects output -- so cli_parse was changed to clear it, on the
# reasoning that an inherited value lets a run append to a file the user never
# chose. That is a real effect, but it is the DOCUMENTED contract, not a hole:
# tests/fixtures/check.sh cell 23 asserts that `setup check` appends its table
# to an exported FS_LOG_FILE, so the variable is a deliberate audit seam, and a
# dry run honouring it is consistent rather than a violation (a dry run writes
# nothing to the SYSTEM; the user asked for this file). The rule this
# establishes: do not assume every redirecting variable is untrusted, and check
# whether a fixture already pins its meaning before treating it like the two
# that are.
#
# The asymmetry, stated rather than hidden: every command honours the exported
# path EXCEPT a real `install`, which calls io_init with this run's own
# state-root log (_fs_open_run_log) and therefore RE-POINTS the variable. The
# exported file keeps the lines emitted before that point and the summary names
# the state log, which is the one that holds the batches and hooks. That is
# deliberate -- the summary's artifacts clause must name a file that contains
# the run -- but it means "the seam applies to every command" is true for
# `check`, `verify`, `list` and dry runs, and only for the pre-install lines of
# a real `install`. Do not "fix" this by skipping io_init for install; the
# summary would then point at a log the hooks never reached.

_CLI_ENV_VERBOSE="${FS_VERBOSE:-0}"
_CLI_ENV_DEBUG="${FS_DEBUG:-0}"
_CLI_ENV_DRY_RUN="${FS_DRY_RUN:-0}"
_CLI_ENV_YES="${FS_YES:-0}"
_CLI_ENV_BROWSE="${FS_GNOME_BROWSE:-0}"
_CLI_ENV_FORCE="${FS_GNOME_FORCE:-0}"

_cli_known_cmd() {
    case "$1" in
        install|list|check|verify|export|update|help|version) return 0 ;;
        *) return 1 ;;
    esac
}

cli_parse() {
    local args=("$@")
    local i=0 end_opts=0 saw_list=0
    FS_YES="$_CLI_ENV_YES"
    FS_DRY_RUN="$_CLI_ENV_DRY_RUN"
    FS_LIST=0
    FS_VERBOSE="$_CLI_ENV_VERBOSE"
    FS_DEBUG="$_CLI_ENV_DEBUG"
    FS_GNOME_BROWSE="$_CLI_ENV_BROWSE"
    FS_GNOME_FORCE="$_CLI_ENV_FORCE"
    FS_PROFILE=""
    FS_PROFILE_SET=0
    FS_MANIFEST=""
    FS_PULL=0
    FS_CMD=""
    FS_CMD_ARGS=()

    while (( i < $# )); do
        local tok="${args[$i]}"
        if (( end_opts == 0 )); then
            case "$tok" in
                --)
                    end_opts=1
                    i=$(( i + 1 ))
                    continue
                    ;;
                -h|--help)
                    FS_CMD="help"
                    i=$(( i + 1 ))
                    continue
                    ;;
                --yes)
                    FS_YES=1
                    i=$(( i + 1 ))
                    continue
                    ;;
                --dry-run)
                    FS_DRY_RUN=1
                    i=$(( i + 1 ))
                    continue
                    ;;
                --verbose)
                    FS_VERBOSE=1
                    i=$(( i + 1 ))
                    continue
                    ;;
                --debug)
                    FS_DEBUG=1
                    i=$(( i + 1 ))
                    continue
                    ;;
                --browse)
                    FS_GNOME_BROWSE=1
                    i=$(( i + 1 ))
                    continue
                    ;;
                --force)
                    FS_GNOME_FORCE=1
                    i=$(( i + 1 ))
                    continue
                    ;;
                --pull)
                    FS_PULL=1
                    i=$(( i + 1 ))
                    continue
                    ;;
                --list)
                    FS_LIST=1
                    saw_list=1
                    i=$(( i + 1 ))
                    continue
                    ;;
                --profile)
                    if (( i + 1 >= $# )); then
                        io_error "flag '--profile' requires a value"
                        return 1
                    fi
                    i=$(( i + 1 ))
                    FS_PROFILE="${args[$i]}"
                    FS_PROFILE_SET=1
                    i=$(( i + 1 ))
                    continue
                    ;;
                --manifest)
                    if (( i + 1 >= $# )); then
                        io_error "flag '--manifest' requires a directory"
                        return 1
                    fi
                    i=$(( i + 1 ))
                    FS_MANIFEST="${args[$i]}"
                    i=$(( i + 1 ))
                    continue
                    ;;
                -*) io_error "unknown flag: $tok"
                    return 1
                    ;;
                --*) io_error "unknown flag: $tok"
                    return 1
                    ;;
            esac
        fi
        if [[ -z "$FS_CMD" ]]; then
            if _cli_known_cmd "$tok"; then
                FS_CMD="$tok"
            else
                io_error "unknown command: $tok"
                return 1
            fi
        else
            FS_CMD_ARGS+=("$tok")
        fi
        i=$(( i + 1 ))
    done

    if [[ -z "$FS_CMD" ]]; then
        if (( saw_list )); then
            FS_CMD="list"
        else
            FS_CMD="help"
        fi
    fi
    return 0
}

cli_help() {
    cat <<'HELP'
fedora-setup - multi-distro workstation bootstrap

Usage:
  setup [GLOBAL FLAGS] COMMAND [ARGS...]

Commands:
  install   Apply selected modules/profiles
  list      List available modules and profiles
  check     Check prerequisites and system state
  verify    Verify applied configuration
  export    Write a re-importable snapshot of a profile to <dir>
  update    Report this tool's version and check for updates
  help      Show this help text
  version   Print the version

Global flags:
  --yes        Skip confirmation prompts
  --dry-run    Preview actions without executing anything
  --verbose    More verbose output
  --debug      Debug-level output
  --browse     Opt-in: gnome-extensions may open browse URLs (at most 2)
  --force      Opt-in: run GNOME modules even when not a GNOME session
  --profile P  Select profile P
  --manifest D Replay an exported tree instead of the live profile (install)
  --pull      Opt-in: let 'update' fast-forward this tool (default: report only)
  --list       Alias for the 'list' command
  -h, --help   Show this help text
HELP
}