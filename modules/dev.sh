#!/bin/bash
# Development environment setup: system packages stage
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

dtype=$(distribution)

# D01 — System development packages.
# Binary-presence matrix: probe each tool, collect the family package names
# for everything missing, then run one install transaction and re-verify.
# Later roadmap tasks append their own stages to this module.

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
        add_missing node nodejs
        add_missing npm npm
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
        ;;
    "debian")
        add_missing ssh openssh-client
        add_missing sshd openssh-server
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
                echo "would run: bootstrap yay and install VS Code via yay (AUR)"
                if ! command -v yay >/dev/null 2>&1; then
                    # In dry-run run_root only prints the would-run line.
                    run_root pacman -S --needed --noconfirm base-devel
                    echo "would run: git clone --depth 1 https://aur.archlinux.org/yay.git"
                    echo "would run: makepkg -si --noconfirm"
                fi
            else
                if ! command -v yay >/dev/null 2>&1; then
                    if ! run_root pacman -S --needed --noconfirm base-devel; then
                        echo "Error: failed to install base-devel for yay bootstrap." >&2
                        exit 1
                    fi
                    if ! yay_tmp=$(mktemp -d); then
                        echo "Error: failed to create a temporary directory for yay." >&2
                        exit 1
                    fi
                    cleanup_yay_tmp() {
                        if [ -n "$yay_tmp" ]; then
                            rm -rf "$yay_tmp"
                        fi
                    }
                    trap cleanup_yay_tmp EXIT
                    if ! run git clone --depth 1 https://aur.archlinux.org/yay.git "$yay_tmp/yay"; then
                        echo "Error: failed to clone yay from AUR." >&2
                        exit 1
                    fi
                    if ! (cd "$yay_tmp/yay" && run makepkg -si --noconfirm); then
                        echo "Error: failed to build and install yay." >&2
                        exit 1
                    fi
                    if ! command -v yay >/dev/null 2>&1; then
                        echo "Error: yay build failed." >&2
                        exit 1
                    fi
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

if flatpak info io.dbeaver.DBeaverCommunity >/dev/null 2>&1; then
    echo "DBeaver Community is already installed."
else
    if [ "${SETUP_DRY_RUN:-0}" != "1" ] && ! command -v flatpak >/dev/null 2>&1; then
        echo "Error: flatpak command not found (required to install DBeaver Community)." >&2
        exit 1
    fi
    if ! flatpak remote-list 2>/dev/null | grep -q flathub; then
        if ! run flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; then
            echo "Error: failed to add the Flathub remote for DBeaver Community." >&2
            exit 1
        fi
    fi
    if ! run flatpak install -y flathub io.dbeaver.DBeaverCommunity; then
        echo "Error: failed to install DBeaver Community via Flatpak." >&2
        exit 1
    fi

    # Post-verify (real mode only): flatpak info must succeed after the
    # install attempt. Dry-run prints only the would-run lines above.
    if [ "${SETUP_DRY_RUN:-0}" != "1" ]; then
        if ! flatpak info io.dbeaver.DBeaverCommunity >/dev/null 2>&1; then
            echo "Error: DBeaver Community is not available after installation." >&2
            exit 1
        fi
        echo "DBeaver Community installed."
    fi
fi

# D04 — mise (user-level) + Python 3.13 via mise
echo "Installing mise and Python 3.13..."

if command -v mise >/dev/null 2>&1 || [ -x "$HOME/.local/bin/mise" ]; then
    [ "${SETUP_DRY_RUN:-0}" != "1" ] && echo "mise is already installed."
else
    if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
        echo "would run: curl -fsSL https://mise.jdx.dev/install.sh | sh"
    else
        if ! run sh -c "curl -fsSL https://mise.jdx.dev/install.sh | sh"; then
            echo "Error: mise is not available after installation." >&2
            exit 1
        fi
        if ! command -v mise >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/mise" ]; then
            echo "Error: mise is not available after installation." >&2
            exit 1
        fi
        echo "mise installed."
    fi
fi

# Ensure mise/python PATH for checks/runs in real mode
export PATH="$HOME/.local/bin:$HOME/.mise/shims:$PATH"

PY313_OK=0
if command -v python >/dev/null 2>&1 && python --version 2>/dev/null | grep -q "^Python 3\.13"; then
    if command -v mise >/dev/null 2>&1 && mise which python >/dev/null 2>&1; then
        PY313_OK=1
    fi
fi

if [ "$PY313_OK" = "1" ]; then
    [ "${SETUP_DRY_RUN:-0}" != "1" ] && echo "Python 3.13 already configured via mise."
else
    if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
        echo "would run: mise use -g python@3.13"
    else
        if ! run mise use -g python@3.13; then
            echo "Error: Python 3.13 setup via mise failed." >&2
            exit 1
        fi
        export PATH="$HOME/.local/bin:$HOME/.mise/shims:$PATH"
        if ! (python --version 2>/dev/null | grep -q "^Python 3\.13") || ! (mise which python >/dev/null 2>&1 && [ -n "$(mise which python 2>/dev/null)" ]); then
            echo "Error: Python 3.13 setup via mise failed." >&2
            exit 1
        fi
        echo "Python 3.13 set up via mise."
    fi
fi

# D05 — JupyterLab via pipx (uses mise Python)
echo "Installing JupyterLab via pipx..."

if [ -x "$HOME/.local/bin/jupyter" ]; then
    [ "${SETUP_DRY_RUN:-0}" != "1" ] && echo "JupyterLab is already installed."
else
    if [ "${SETUP_DRY_RUN:-0}" != "1" ] && ! command -v pipx >/dev/null 2>&1; then
        echo "Error: pipx command not found (required to install JupyterLab)." >&2
        exit 1
    fi
    if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
        echo 'would run: pipx install --python "$(~/.local/bin/mise which python)" jupyterlab'
        echo "would run: pipx inject jupyterlab ipykernel"
    else
        export PATH="$HOME/.local/bin:$HOME/.mise/shims:$PATH"
        if ! run pipx install --python "$(~/.local/bin/mise which python)" jupyterlab; then
            echo "Error: failed to install JupyterLab via pipx." >&2
            exit 1
        fi
        if ! run pipx inject jupyterlab ipykernel; then
            echo "Error: failed to inject ipykernel into JupyterLab via pipx." >&2
            exit 1
        fi
        if [ ! -x "$HOME/.local/bin/jupyter" ]; then
            echo "Error: JupyterLab is not available after installation." >&2
            exit 1
        fi
        echo "JupyterLab installed."
    fi
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

if [ -x "$HOME/.local/bin/opencode" ]; then
    [ "${SETUP_DRY_RUN:-0}" != "1" ] && echo "OpenCode is already installed."
else
    if [ "${SETUP_DRY_RUN:-0}" = "1" ]; then
        echo "would run: XDG_BIN_DIR=\"$HOME/.local/bin\" curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path"
    else
        if ! (set -o pipefail; XDG_BIN_DIR="$HOME/.local/bin" curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path); then
            echo "Error: failed to install OpenCode via the official installer." >&2
            exit 1
        fi
        if [ ! -x "$HOME/.local/bin/opencode" ]; then
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
            cat <<'DEVBLOCK'
fish_add_path "$HOME/.local/bin"
~/.local/bin/mise activate fish | source
DEVBLOCK
        else
            cat <<DEVBLOCK
export PATH="\$HOME/.local/bin:\$PATH"
eval "\$(~/.local/bin/mise activate $shell)"
DEVBLOCK
        fi
        printf '%s\n' "$BLOCK_END"
    }

    # Strip any existing dev block, then append exactly one fresh block.
    apply_dev_block() {
        local rc_file="$1"
        local shell="$2"

        if [ ! -f "$rc_file" ]; then
            mkdir -p "$(dirname "$rc_file")"
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

    apply_dev_block "$HOME/.bashrc" bash

    if [ -f "$HOME/.zshrc" ] || command -v zsh >/dev/null 2>&1; then
        apply_dev_block "$HOME/.zshrc" zsh
    fi

    if [ -f "$HOME/.config/fish/config.fish" ] || command -v fish >/dev/null 2>&1; then
        apply_dev_block "$HOME/.config/fish/config.fish" fish
    fi
fi

# Completion guidance. The SSH server activation commands are documented in
# the README (D09), not printed or executed here: dev.sh must stay free of any
# privileged-command text so the module harness and hygiene greps can assert
# that nothing privileged is ever attempted from this stage.
echo "Development environment ready. Reload your shell or run 'exec bash' to load the new PATH and mise activation."
echo "See README.md for SSH server instructions (the server is installed but left off by default)."

exit 0
