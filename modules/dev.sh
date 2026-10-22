#!/bin/bash
# Development environment setup: system packages stage
set -e

script_path="${BASH_SOURCE[0]}"
case "$script_path" in */*) ;; *) script_path="./$script_path" ;; esac
SCRIPT_DIR="$(cd "${script_path%/*}/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

dtype=$(distribution)

# Package manager and sudo are bootstrap prerequisites: every supported family
# uses its native manager through run_root, which requires sudo. These cannot
# be installed safely by this module if they are themselves missing.
case "$dtype" in
    redhat) package_manager=dnf ;;
    debian) package_manager=apt-get ;;
    arch) package_manager=pacman ;;
    *)
        echo "Unknown or unsupported distribution: $dtype" >&2
        exit 1
        ;;
esac
if [ "${SETUP_DRY_RUN:-0}" != "1" ]; then
    if ! command -v "$package_manager" >/dev/null 2>&1; then
        echo "Error: required package manager '$package_manager' is unavailable; install it before running setup dev." >&2
        exit 1
    fi
    if ! command -v sudo >/dev/null 2>&1; then
        echo "Error: sudo is required for privileged development package installation, but was not found." >&2
        exit 1
    fi
fi

# D01 — System development packages.
# Binary-presence matrix: probe each tool, collect the family package names
# for everything missing, then run one install transaction and re-verify.
# Remaining installation stages follow below in their fixed order.

echo "Installing development system packages..."

missing_packages=()
missing_bins=()

# add_missing <binary> <package>: append <package> to the missing list (and
# remember <binary> for post-install verification) when <binary> is not on
# PATH. Duplicate packages are collapsed so e.g. Arch's single openssh
# package is never listed twice.
add_missing() {
    local binary="$1" pkg="$2"
    if command -v "$binary" >/dev/null 2>&1; then
        return 0
    fi
    case " ${missing_packages[*]:-} " in
        *" $pkg "*) ;;
        *) missing_packages+=("$pkg") ;;
    esac
    missing_bins+=("$binary")
}

case "$dtype" in
    "redhat")
        node_npm_package=$(fedora_node_npm_package)
        add_missing ssh openssh-clients
        add_missing sshd openssh-server
        add_missing git git
        add_missing gcc gcc
        add_missing g++ gcc-c++
        add_missing clang clang
        add_missing make make
        add_missing cmake cmake
        add_missing gdb gdb
        add_missing python3 python3
        add_missing pip3 python3-pip
        add_missing pipx pipx
        add_missing node "$node_npm_package"
        add_missing npm "$node_npm_package"
        add_missing go golang
        add_missing vim vim
        add_missing nvim neovim
        add_missing fzf fzf
        add_missing rg ripgrep
        add_missing fd fd-find
        add_missing jq jq
        add_missing tmux tmux
        add_missing sqlite3 sqlite
        add_missing psql postgresql
        add_missing curl curl
        add_missing wget wget
        add_missing flatpak flatpak
        add_missing mkdir coreutils
        add_missing cat coreutils
        add_missing tail coreutils
        add_missing ln coreutils
        add_missing mktemp coreutils
        add_missing mkfifo coreutils
        add_missing mv coreutils
        add_missing rm coreutils
        add_missing chmod coreutils
        add_missing tr coreutils
        add_missing uname coreutils
        add_missing bash bash
        add_missing sh bash
        add_missing grep grep
        add_missing sed sed
        add_missing which which
        add_missing tar tar
        ;;
    "debian")
        add_missing ssh openssh-client
        add_missing git git
        add_missing gcc gcc
        add_missing g++ g++
        add_missing clang clang
        add_missing make make
        add_missing cmake cmake
        add_missing gdb gdb
        add_missing python3 python3
        add_missing pip3 python3-pip
        add_missing pipx pipx
        add_missing node nodejs
        add_missing npm npm
        add_missing go golang-go
        add_missing vim vim
        add_missing nvim neovim
        add_missing fzf fzf
        add_missing rg ripgrep
        add_missing fdfind fd-find
        add_missing jq jq
        add_missing tmux tmux
        add_missing sqlite3 sqlite3
        add_missing psql postgresql-client
        add_missing curl curl
        add_missing wget wget
        add_missing flatpak flatpak
        add_missing mkdir coreutils
        add_missing cat coreutils
        add_missing tail coreutils
        add_missing ln coreutils
        add_missing mktemp coreutils
        add_missing mkfifo coreutils
        add_missing mv coreutils
        add_missing rm coreutils
        add_missing chmod coreutils
        add_missing tr coreutils
        add_missing uname coreutils
        add_missing bash bash
        add_missing sh dash
        add_missing grep grep
        add_missing sed sed
        add_missing which which
        add_missing tar tar
        # Debian exception: python3-venv has no dedicated binary probe and is
        # always appended; apt-get is idempotent when the venv support is
        # already present, so an extra update+install is harmless.
        missing_packages+=(python3-venv)
        ;;
    "arch")
        add_missing ssh openssh
        add_missing sshd openssh
        add_missing git git
        add_missing gcc gcc
        add_missing g++ gcc
        add_missing clang clang
        add_missing make make
        add_missing cmake cmake
        add_missing gdb gdb
        add_missing python3 python
        add_missing pip3 python-pip
        add_missing pipx python-pipx
        add_missing node nodejs
        add_missing npm npm
        add_missing go go
        add_missing vim vim
        add_missing nvim neovim
        add_missing fzf fzf
        add_missing rg ripgrep
        add_missing fd fd
        add_missing jq jq
        add_missing tmux tmux
        add_missing sqlite3 sqlite
        add_missing psql postgresql
        add_missing curl curl
        add_missing wget wget
        add_missing flatpak flatpak
        add_missing mkdir coreutils
        add_missing cat coreutils
        add_missing tail coreutils
        add_missing ln coreutils
        add_missing mktemp coreutils
        add_missing mkfifo coreutils
        add_missing mv coreutils
        add_missing rm coreutils
        add_missing chmod coreutils
        add_missing tr coreutils
        add_missing uname coreutils
        add_missing bash bash
        add_missing sh bash
        add_missing grep grep
        add_missing sed sed
        add_missing which which
        add_missing tar tar
        ;;
    *)
        echo "Unknown or unsupported distribution: $dtype" >&2
        exit 1
        ;;
esac

if [ "${#missing_packages[@]}" -gt 0 ]; then
    echo "${#missing_packages[@]} missing development package(s): ${missing_packages[*]}"
    case "$dtype" in
        "redhat")
            if ! run_root dnf makecache; then
                echo "Error: dnf failed to refresh the package index (Fedora family)." >&2
                exit 1
            fi
            if ! run_root dnf install -y "${missing_packages[@]}"; then
                echo "Error: dnf failed to install the development package set." >&2
                exit 1
            fi
            ;;
        "debian")
            if ! run_root apt-get update; then
                echo "Error: apt-get failed to refresh the package index (Debian family)." >&2
                exit 1
            fi
            if ! run_root apt-get install -y "${missing_packages[@]}"; then
                echo "Error: apt-get failed to install the development package set." >&2
                exit 1
            fi
            ;;
        "arch")
            # Arch: --needed skips already-installed packages; a full -Syu
            # system upgrade is never forced by this stage.
            if ! run_root pacman -S --needed --noconfirm "${missing_packages[@]}"; then
                echo "Error: pacman failed to install the development package set (Arch family)." >&2
                exit 1
            fi
            ;;
    esac

    # Post-install verification (real mode only): every binary that was
    # missing must now resolve. A partial or fake install is fatal.
    if [ "${SETUP_DRY_RUN:-0}" != "1" ]; then
        still_missing=()
        for binary in "${missing_bins[@]}"; do
            if ! command -v "$binary" >/dev/null 2>&1; then
                still_missing+=("$binary")
            fi
        done
        if [ "${#still_missing[@]}" -gt 0 ]; then
            echo "Error: development tools still missing after install: ${still_missing[*]}" >&2
            exit 1
        fi
        echo "All development system packages verified."
    fi
else
    echo "Development system packages are already installed."
fi
# D02 — Visual Studio Code (official vendor build on Fedora/Debian, AUR
# visual-studio-code-bin via yay on Arch, with automatic yay bootstrap).

echo "Installing Visual Studio Code..."

# The vendor packages are published for x86_64 only. The check runs only
# on a path that is about to download one, so an already-installed setup
# on other architectures still succeeds.
require_vendor_arch() {
    local vendor_arch
    vendor_arch=$(uname -m)
    case "$vendor_arch" in
        x86_64) ;;
        *)
            echo "Error: VS Code vendor installs support x86_64 only (detected: $vendor_arch)." >&2
            exit 1
            ;;
    esac
}

if command -v code >/dev/null 2>&1; then
    echo "VS Code is already installed."
else
    case "$dtype" in
        "redhat")
            if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
                echo "would run: download and install VS Code via dnf"
            else
                require_vendor_arch
                if ! vendor_tmp=$(mktemp -d); then
                    echo "Error: failed to create a temporary download directory." >&2
                    exit 1
                fi
                cleanup_vendor_tmp() {
                    if [ -n "$vendor_tmp" ]; then
                        rm -rf "$vendor_tmp"
                    fi
                }
                trap cleanup_vendor_tmp EXIT
                if ! run wget -O "$vendor_tmp/vscode.rpm" "https://code.visualstudio.com/sha/download?build=stable&os=linux-rpm-x64"; then
                    echo "Error: failed to download the VS Code .rpm package." >&2
                    exit 1
                fi
                if ! run_root dnf install -y "$vendor_tmp/vscode.rpm"; then
                    echo "Error: failed to install the VS Code .rpm package." >&2
                    exit 1
                fi
            fi
            ;;
        "debian")
            if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
                echo "would run: download and install VS Code via apt"
            else
                require_vendor_arch
                if ! vendor_tmp=$(mktemp -d); then
                    echo "Error: failed to create a temporary download directory." >&2
                    exit 1
                fi
                cleanup_vendor_tmp() {
                    if [ -n "$vendor_tmp" ]; then
                        rm -rf "$vendor_tmp"
                    fi
                }
                trap cleanup_vendor_tmp EXIT
                if ! run wget -O "$vendor_tmp/vscode.deb" "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64"; then
                    echo "Error: failed to download the VS Code .deb package." >&2
                    exit 1
                fi
                if ! run_root apt-get install -y "$vendor_tmp/vscode.deb"; then
                    echo "Error: failed to install the VS Code .deb package." >&2
                    exit 1
                fi
            fi
            ;;
        "arch")
            if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
                echo "would run: bootstrap yay if needed and install VS Code via yay (AUR)"
                ensure_yay
            else
                if ! ensure_yay; then
                    echo "Error: failed to bootstrap the yay AUR helper." >&2
                    exit 1
                fi
                if ! run yay -S --needed --noconfirm visual-studio-code-bin; then
                    echo "Error: failed to install visual-studio-code-bin via yay." >&2
                    exit 1
                fi
            fi
            ;;
        *)
            echo "Unknown or unsupported distribution: $dtype" >&2
            exit 1
            ;;
    esac

    # Post-verify (real mode only): command -v code must resolve after the
    # install attempt. Dry-run prints only the would-run lines above and
    # never claims success.
    if [ "${SETUP_DRY_RUN:-0}" != "1" ]; then
        if ! command -v code >/dev/null 2>&1; then
            echo "Error: VS Code is not available after installation." >&2
            exit 1
        fi
        echo "VS Code installed."
    fi
fi

# D03 — DBeaver Community via Flatpak/Flathub. flatpak itself is part of the
# D01 system set; a missing flatpak command after that stage is fatal.

echo "Installing DBeaver Community..."

if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
    echo 'would run: flatpak info --user io.dbeaver.DBeaverCommunity (skip if installed)'
    echo "would run: flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo"
    echo "would run: flatpak install --user -y flathub io.dbeaver.DBeaverCommunity"
else
    if ! command -v flatpak >/dev/null 2>&1; then
        echo "Error: flatpak command not found (required to install DBeaver Community)." >&2
        exit 1
    fi
    if flatpak info --user io.dbeaver.DBeaverCommunity >/dev/null 2>&1; then
        echo "DBeaver Community is already installed for this user."
    else
        if ! flatpak remote-list --user 2>/dev/null | grep -q flathub; then
            if ! run flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; then
                echo "Error: failed to add the Flathub remote for DBeaver Community." >&2
                exit 1
            fi
        fi
        if ! run flatpak install --user -y flathub io.dbeaver.DBeaverCommunity; then
            echo "Error: failed to install DBeaver Community via Flatpak." >&2
            exit 1
        fi

        # Post-verify using the same per-user scope as the installation.
        if ! flatpak info --user io.dbeaver.DBeaverCommunity >/dev/null 2>&1; then
            echo "Error: DBeaver Community is not available after installation." >&2
            exit 1
        fi
        echo "DBeaver Community installed."
    fi
fi

# D04 — mise (user-level) + Python 3.13 via mise
echo "Installing mise and Python 3.13..."

mise_bin=""
resolve_mise() {
    if [ -x "$HOME/.local/bin/mise" ]; then
        mise_bin="$HOME/.local/bin/mise"
    elif command -v mise >/dev/null 2>&1; then
        mise_bin="$(command -v mise)"
    else
        mise_bin=""
    fi
}
resolve_mise

if [ -n "$mise_bin" ]; then
    [ "${SETUP_DRY_RUN:-0}" != "1" ] && echo "mise is already installed."
else
    if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
        echo "would run: curl -fsSL https://mise.jdx.dev/install.sh | sh"
        mise_bin="$HOME/.local/bin/mise"
    else
        if ! run sh -c "curl -fsSL https://mise.jdx.dev/install.sh | sh"; then
            echo "Error: mise is not available after installation." >&2
            exit 1
        fi
        resolve_mise
        if [ -z "$mise_bin" ]; then
            echo "Error: mise is not available after installation." >&2
            exit 1
        fi
        echo "mise installed."
    fi
fi

# Use the same resolved executable for all checks and commands. The shims
# directory remains first so Python selected by mise resolves consistently.
if [ -n "$mise_bin" ] && [ "${SETUP_DRY_RUN:-0}" != "1" ]; then
    export PATH="${mise_bin%/*}:$HOME/.local/bin:$HOME/.mise/shims:$PATH"
fi

PY313_OK=0
if [ "${SETUP_DRY_RUN:-0}" != "1" ]; then
    if command -v python >/dev/null 2>&1 && python --version 2>/dev/null | grep -q "^Python 3\.13"; then
        if [ -n "$mise_bin" ] && "$mise_bin" which python >/dev/null 2>&1; then
            PY313_OK=1
        fi
    fi
fi

if [ "$PY313_OK" = "1" ]; then
    [ "${SETUP_DRY_RUN:-0}" != "1" ] && echo "Python 3.13 already configured via mise."
else
    if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
        echo "would run: $mise_bin use -g python@3.13"
    else
        if ! run "$mise_bin" use -g python@3.13; then
            echo "Error: Python 3.13 setup via mise failed." >&2
            exit 1
        fi
        export PATH="${mise_bin%/*}:$HOME/.local/bin:$HOME/.mise/shims:$PATH"
        if ! (python --version 2>/dev/null | grep -q "^Python 3\.13") || ! ("$mise_bin" which python >/dev/null 2>&1 && [ -n "$("$mise_bin" which python 2>/dev/null)" ]); then
            echo "Error: Python 3.13 setup via mise failed." >&2
            exit 1
        fi
        echo "Python 3.13 set up via mise."
    fi
fi

# D05 — JupyterLab via pipx (uses mise Python; ipykernel is checked separately)
echo "Installing JupyterLab via pipx..."

if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
    if [ ! -x "$HOME/.local/bin/jupyter" ]; then
        echo "would run: pipx install --python \"\$($mise_bin which python)\" jupyterlab"
    else
        echo "would run: skip pipx install (JupyterLab is present)"
    fi
    echo "would run: check pipx runpip jupyterlab show ipykernel and inject only if missing"
else
    if ! command -v pipx >/dev/null 2>&1; then
        echo "Error: pipx command not found (required to verify or install JupyterLab)." >&2
        exit 1
    fi
    export PATH="${mise_bin%/*}:$HOME/.local/bin:$HOME/.mise/shims:$PATH"
    if [ ! -x "$HOME/.local/bin/jupyter" ]; then
        if ! run pipx install --python "$("$mise_bin" which python)" jupyterlab; then
            echo "Error: failed to install JupyterLab via pipx." >&2
            exit 1
        fi
    fi
    if ! pipx runpip jupyterlab show ipykernel >/dev/null 2>&1; then
        if ! run pipx inject jupyterlab ipykernel; then
            echo "Error: failed to inject ipykernel into JupyterLab via pipx." >&2
            exit 1
        fi
    fi
    if ! pipx runpip jupyterlab show ipykernel >/dev/null 2>&1; then
        echo "Error: ipykernel is not available in the JupyterLab environment after injection." >&2
        exit 1
    fi
    if [ ! -x "$HOME/.local/bin/jupyter" ]; then
        echo "Error: JupyterLab is not available after installation." >&2
        exit 1
    fi
    echo "JupyterLab and ipykernel verified."
fi

# D06 — Codex via npm user-prefix
echo "Installing Codex via npm..."

if [ "${SETUP_DRY_RUN:-0}" != "1" ]; then
    mkdir -p "$HOME/.local"
fi

# Managed npm user-prefix: ~/.npmrc must end up with exactly one
# `prefix=$HOME/.local` line. Existing prefix= lines are stripped and the
# managed one is appended; every unrelated line is preserved. The check runs
# in both modes, so dry-run only reports the change and never mutates HOME.
managed_prefix="prefix=$HOME/.local"
npmrc_ok=0
if [ -f "$HOME/.npmrc" ] && grep -qxF "$managed_prefix" "$HOME/.npmrc" 2>/dev/null \
    && [ "$(grep -c '^prefix=' "$HOME/.npmrc" 2>/dev/null)" -eq 1 ]; then
    npmrc_ok=1
fi
if [ "$npmrc_ok" = "0" ]; then
    if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
        echo "would run: set $managed_prefix in ~/.npmrc"
    else
        if [ -f "$HOME/.npmrc" ]; then
            sed -i '/^prefix=/d' "$HOME/.npmrc"
        else
            : > "$HOME/.npmrc"
        fi
        printf '%s\n' "$managed_prefix" >> "$HOME/.npmrc"
    fi
fi

if [ -x "$HOME/.local/bin/codex" ]; then
    [ "${SETUP_DRY_RUN:-0}" != "1" ] && echo "Codex is already installed."
else
    if [ "${SETUP_DRY_RUN:-0}" != "1" ] && ! command -v npm >/dev/null 2>&1; then
        echo "Error: npm command not found (required to install Codex)." >&2
        exit 1
    fi
    if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
        echo "would run: npm install -g --prefix \"$HOME/.local\" @openai/codex"
    else
        if ! run npm install -g --prefix "$HOME/.local" @openai/codex; then
            echo "Error: failed to install Codex via npm." >&2
            exit 1
        fi
        if [ ! -x "$HOME/.local/bin/codex" ]; then
            echo "Error: Codex is not available after installation." >&2
            exit 1
        fi
        echo "Codex installed."
    fi
fi

# D07 — OpenCode CLI via the official installer. The pipeline runs
# unprivileged as the current user. The subshell scopes `set -o pipefail` so a
# curl failure is caught too, without changing this module's global set -e
# behavior; `set -e` is suppressed inside the if-test either way.
echo "Installing OpenCode CLI..."

opencode_bin="$HOME/.opencode/bin/opencode"
if [ -x "$opencode_bin" ]; then
    [ "${SETUP_DRY_RUN:-0}" != "1" ] && echo "OpenCode is already installed."
else
    if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
        echo "would run: curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path"
        echo "would run: add $HOME/.opencode/bin to the managed shell PATH"
    else
        if ! (set -o pipefail; curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path); then
            echo "Error: failed to install OpenCode via the official installer." >&2
            exit 1
        fi
        if [ ! -x "$opencode_bin" ]; then
            echo "Error: OpenCode is not available after installation." >&2
            exit 1
        fi
        echo "OpenCode installed."
    fi
fi

# D08 — Debian fd symlink, managed dev rc block, and completion guidance.
echo "Setting up development shell configuration..."

# Debian ships the find-tool binary as `fdfind`; give the user an `fd`
# command in ~/.local/bin (user-level only). Fedora/Arch already provide
# `fd` from their packages, so this stage is Debian-only and idempotent.
if [ "$dtype" = "debian" ] && command -v fdfind >/dev/null 2>&1 && [ ! -e "$HOME/.local/bin/fd" ]; then
    if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
        run ln -s "$(command -v fdfind)" "$HOME/.local/bin/fd"
    else
        mkdir -p "$HOME/.local/bin"
        if ! run ln -s "$(command -v fdfind)" "$HOME/.local/bin/fd"; then
            echo "Error: failed to create the fd symlink in ~/.local/bin." >&2
            exit 1
        fi
    fi
fi

# Managed dev rc block (PATH + mise activation), mirroring
# modules/set_aliases.sh: one delimited block per rc file, stripped and
# re-appended on every run. The markers differ from the aliases block, so
# the two blocks coexist without ever duplicating each other.
BLOCK_BEGIN="# >>> linux-postinstall dev >>>"
BLOCK_END="# <<< linux-postinstall dev <<<"

# Dry-run: report the rc targets, write nothing.
if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
    echo "would run: write linux-postinstall dev block to $HOME/.bashrc"
    if [ -f "$HOME/.zshrc" ] || command -v zsh >/dev/null 2>&1; then
        echo "would run: write linux-postinstall dev block to $HOME/.zshrc"
    fi
    if [ -f "$HOME/.config/fish/config.fish" ] || command -v fish >/dev/null 2>&1; then
        echo "would run: write linux-postinstall dev block to $HOME/.config/fish/config.fish"
    fi
else
    # Emit the managed block for one shell: PATH plus mise activation.
    emit_dev_block() {
        local shell="$1"
        printf '%s\n' "$BLOCK_BEGIN"
        if [ "$shell" = "fish" ]; then
            local fish_mise_bin="${mise_bin//\\/\\\\}"
            fish_mise_bin="${fish_mise_bin//\'/\\\'}"
            local fish_opencode_dir="${HOME}/.opencode/bin"
            fish_opencode_dir="${fish_opencode_dir//\\/\\\\}"
            fish_opencode_dir="${fish_opencode_dir//\'/\\\'}"
            cat <<'DEVBLOCK'
fish_add_path "$HOME/.local/bin"
DEVBLOCK
            printf "fish_add_path '%s'\n" "$fish_opencode_dir"
            printf "'%s' activate fish | source\n" "$fish_mise_bin"
        else
            local bash_mise_bin
            printf -v bash_mise_bin '%q' "$mise_bin"
            cat <<DEVBLOCK
export PATH="\$HOME/.opencode/bin:\$HOME/.local/bin:\$PATH"
eval "\$($bash_mise_bin activate $shell)"
DEVBLOCK
        fi
        printf '%s\n' "$BLOCK_END"
    }

    # Strip any existing dev block, then append exactly one fresh block.
    apply_dev_block() {
        local rc_file="$1"
        local shell="$2"

        if [ ! -f "$rc_file" ]; then
            local rc_dir="${rc_file%/*}"
            mkdir -p "$rc_dir"
            : > "$rc_file"
        fi

        run sed -i "/^$(printf '%s' "$BLOCK_BEGIN")\$/,/^$(printf '%s' "$BLOCK_END")\$/d" "$rc_file"

        if [ -s "$rc_file" ] && [ -n "$(tail -n1 "$rc_file")" ]; then
            printf '\n' >> "$rc_file"
        fi
        {
            emit_dev_block "$shell"
        } >> "$rc_file"
        echo "Dev shell block written to $rc_file."
    }

    rc_targets=("$HOME/.bashrc")
    if [ -f "$HOME/.zshrc" ] || command -v zsh >/dev/null 2>&1; then
        rc_targets+=("$HOME/.zshrc")
    fi
    if [ -f "$HOME/.config/fish/config.fish" ] || command -v fish >/dev/null 2>&1; then
        rc_targets+=("$HOME/.config/fish/config.fish")
    fi

    # Refuse symlinks (including broken links) and malformed/duplicate marker
    # pairs before touching any startup file. This avoids both link detachment
    # by sed -i and sed's unmatched-range deletion through end-of-file.
    validate_dev_rc() {
        local rc_file="$1" line line_no=0 begin_line=0 end_line=0 begin_count=0 end_count=0 malformed_marker=0
        if [ -L "$rc_file" ]; then
            echo "Error: refusing to rewrite symlinked shell startup file: $rc_file" >&2
            return 1
        fi
        [ -e "$rc_file" ] || return 0
        while IFS= read -r line || [ -n "$line" ]; do
            line_no=$((line_no + 1))
            if [[ "$line" == *"$BLOCK_BEGIN"* ]]; then
                begin_count=$((begin_count + 1))
                begin_line="$line_no"
                [ "$line" = "$BLOCK_BEGIN" ] || malformed_marker=1
            elif [[ "$line" == *"$BLOCK_END"* ]]; then
                end_count=$((end_count + 1))
                end_line="$line_no"
                [ "$line" = "$BLOCK_END" ] || malformed_marker=1
            fi
        done < "$rc_file"
        if [ "$malformed_marker" -eq 1 ] || [ "$begin_count" -ne "$end_count" ] || [ "$begin_count" -gt 1 ] || { [ "$begin_count" -eq 1 ] && [ "$begin_line" -ge "$end_line" ]; }; then
            echo "Error: malformed linux-postinstall dev markers in $rc_file; no shell startup files were changed." >&2
            return 1
        fi
    }
    for rc_file in "${rc_targets[@]}"; do
        if ! validate_dev_rc "$rc_file"; then
            exit 1
        fi
    done
    for rc_file in "${rc_targets[@]}"; do
        case "$rc_file" in
            "$HOME/.bashrc") rc_shell=bash ;;
            "$HOME/.zshrc") rc_shell=zsh ;;
            *) rc_shell=fish ;;
        esac
        apply_dev_block "$rc_file" "$rc_shell"
    done
fi

# Completion guidance. The SSH server activation commands are documented in
# the README (D09), not printed or executed here: dev.sh must stay free of any
# privileged-command text so the module harness and hygiene greps can assert
# that nothing privileged is ever attempted from this stage.
echo "Development environment ready. Reload your shell or run 'exec bash' to load the new PATH and mise activation."
echo "See README.md for SSH server instructions (the server is installed but left off by default)."

exit 0
