#!/usr/bin/env bash
# lib/pkg/mock.sh - simulated package backend for fedora-setup tests.
# Depends on lib/io.sh (errors) and lib/run.sh (dry rendering). Full
# seven-member contract as mock_<op>. A pure test seam with no real
# binaries: mock_supported always returns rc0. Two mounted seams:
#   FS_MOCK_INSTALLED  file listing installed packages (one per line);
#                      when unset the installed set is empty. Real-mode
#                      installs append here so downstream state (module
#                      tests, P3.9 verify) sees them installed.
#   FS_MOCK_LOG        recording file for every invocation; when set it
#                      must ALREADY be a regular writable file or the op
#                      halts with io_error (FS_LOG_INFRA pattern); when
#                      unset, nothing is recorded and mock keeps working.
# Records one line per callback: `mock query <pkg>`, `mock install
# <pkg>...` (single transaction after filtering installed), `mock
# update`, `mock install-local <file>`, `mock add-repo <id> <url>
# [key]`. Dry-run prints a single `# would run: mock <op> ...` line via
# run_cmd and performs NO recording and NO installed-set mutation and no
# probes (batch renders without filtering), mirroring family-backend
# behavior so downstream planners render identical shapes. No sudo, no
# /etc/sudoers, no fs writes outside the mounted seams.

mock_supported() {
    return 0
}

_mock_record() {
    local line="${1:-}"
    if [[ -z "${FS_MOCK_LOG:-}" ]]; then
        return 0
    fi
    if [[ ! -f "$FS_MOCK_LOG" || ! -w "$FS_MOCK_LOG" ]]; then
        io_error "mock log not usable: $FS_MOCK_LOG"
        return 1
    fi
    printf '%s\n' "$line" >>"$FS_MOCK_LOG"
    return 0
}

_mock_note_installed() {
    local pkg="${1:-}"
    if [[ -z "${FS_MOCK_INSTALLED:-}" ]]; then
        return 0
    fi
    if ! grep -qxF -- "$pkg" "$FS_MOCK_INSTALLED" 2>/dev/null; then
        printf '%s\n' "$pkg" >>"$FS_MOCK_INSTALLED"
    fi
    return 0
}

mock_query_installed() {
    local pkg="${1:-}"
    if [[ -z "$pkg" ]]; then
        io_error "query_installed requires a package name"
        return 1
    fi
    _mock_record "mock query $pkg" || return 1
    if [[ -f "${FS_MOCK_INSTALLED:-}" ]] && grep -qxF -- "$pkg" "$FS_MOCK_INSTALLED"; then
        return 0
    fi
    return 1
}

mock_list_installed() {
    if [[ -f "${FS_MOCK_INSTALLED:-}" ]]; then
        sort -u "$FS_MOCK_INSTALLED"
    fi
    return 0
}

mock_install_batch() {
    if ((FS_DRY_RUN == 1)); then
        run_cmd "mock install" "mock" "install" "$@"
        return 0
    fi
    if [[ "${FS_MOCK_BATCH_FAIL:-0}" == 1 ]]; then
        _mock_record "mock install FAIL ${*}" || return 1
        return 1
    fi
    local missing=()
    local pkg
    for pkg in "$@"; do
        if ! mock_query_installed "$pkg"; then
            missing+=("$pkg")
        fi
    done
    if ((${#missing[@]} == 0)); then
        return 0
    fi
    _mock_record "mock install ${missing[*]}" || return 1
    for pkg in "${missing[@]}"; do
        _mock_note_installed "$pkg"
    done
    return 0
}

mock_update_metadata() {
    if ((FS_DRY_RUN == 1)); then
        run_cmd "mock update" "mock" "update"
        return 0
    fi
    _mock_record "mock update" || return 1
    return 0
}

mock_install_local() {
    local file="${1:-}"
    if [[ -z "$file" ]]; then
        io_error "mock install_local requires a package file"
        return 1
    fi
    if ((FS_DRY_RUN == 1)); then
        run_cmd "mock install-local" "mock" "install-local" "$file"
        return 0
    fi
    [[ -f "$file" ]] || {
        io_error "mock local package file not found: $file"
        return 1
    }
    _mock_record "mock install-local $file" || return 1
    return 0
}

mock_add_repo() {
    local id="${1:-}" url="${2:-}" key="${3:-}"
    if [[ -z "$id" ]]; then
        io_error "mock add_repo requires a repo id"
        return 1
    fi
    if [[ -z "$url" ]]; then
        io_error "mock add_repo requires a repo url"
        return 1
    fi
    [[ "$id" =~ ^[A-Za-z0-9._-]+$ ]] || {
        io_error "invalid mock repo id: $id"
        return 1
    }
    [[ "$id" != '.' && "$id" != '..' ]] || {
        io_error "invalid mock repo id: $id"
        return 1
    }
    [[ "$url" != *$'\n'* && "$url" != *$'\r'* ]] || {
        io_error "invalid mock repo url: $url"
        return 1
    }
    local args=("add-repo" "$id" "$url")
    if [[ -n "$key" ]]; then
        args+=("$key")
    fi
    if ((FS_DRY_RUN == 1)); then
        run_cmd "mock add-repo" "mock" "${args[@]}"
        return 0
    fi
    _mock_record "mock ${args[*]}" || return 1
    return 0
}
