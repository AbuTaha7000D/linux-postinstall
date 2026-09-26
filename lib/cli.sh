#!/usr/bin/env bash
# lib/cli.sh - argument parsing and dispatch table for fedora-setup.
# Depends on lib/io.sh for io_error (source io.sh first).

_CLI_ENV_VERBOSE="${FS_VERBOSE:-0}"
_CLI_ENV_DEBUG="${FS_DEBUG:-0}"
_CLI_ENV_DRY_RUN="${FS_DRY_RUN:-0}"
_CLI_ENV_YES="${FS_YES:-0}"

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
    FS_PROFILE=""
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
  export    Export applied state to a manifest
  update    Update this tool
  help      Show this help text
  version   Print the version

Global flags:
  --yes        Skip confirmation prompts
  --dry-run    Preview actions without executing anything
  --verbose    More verbose output
  --debug      Debug-level output
  --profile P  Select profile P
  --list       Alias for the 'list' command
  -h, --help   Show this help text
HELP
}