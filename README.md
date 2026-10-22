# Linux Post-Install

A personal Linux post-install and rebuild tool. It installs the packages,
applications, development tools, shell setup, fonts, and optional GNOME settings
used on the author's systems. It is a small Bash project, not a universal
provisioning framework; signing in to applications and accounts remains manual.

The version printed by `./setup version` is **v3.1.0** (defined in `setup`).

## Supported systems and requirements

The project targets these distribution families and baselines:

- Fedora and Nobara.
- Debian 13 (trixie) or newer.
- Ubuntu 24.04 LTS (noble) or newer; Linux Mint releases based on a supported
  Ubuntu version.
- Arch Linux and CachyOS.

Derivative support depends on its `/etc/os-release` identity and compatible
repositories; this is not a claim that every release or derivative has been
tested. For Arch/CachyOS, when Chrome or VS Code is missing, `./setup packages`
and `./setup dev` bootstrap the `yay` AUR helper automatically through the
shared `ensure_yay` helper in `lib/common.sh` if it is not installed. Chrome
and VS Code vendor installers support x86_64 only. The Debian-family package
list retains `firefox-esr` for Debian and selects Ubuntu's `firefox`;
`fastfetch` is omitted because it is unavailable in the Ubuntu 24.04 baseline.

Run the launcher as a regular user with Bash. Privileged steps use `sudo` on
demand, through the system's normal sudo timestamp policy. A working native
package manager and network connection are needed for installation. GNOME is
needed only for GNOME-specific configuration. The tool does not install
packages when run with `--dry-run`.

## Get started

```bash
git clone https://github.com/AbuTaha7000D/linux-postinstall.git
cd linux-postinstall
./setup --dry-run       # inspect the full planned run
./setup                 # same as ./setup install
```

Run an individual command with `./setup <command>`. `--dry-run` is global and
may appear before or after the command:

```bash
./setup --dry-run packages
./setup terminal --dry-run
./setup help
./setup version
```

The CLI accepts one command at a time. `-h`/`--help` and `-v`/`--version` are
also accepted; unsupported options, unknown commands, and extra commands fail
with a usage hint.

## Commands

| Command | Purpose |
| --- | --- |
| `install` (default) | Full sequence described below. |
| `packages` | Install configured native packages, Flatpak applications, Chrome, and VS Code. |
| `language` | Select English or Arabic and update the system locale configuration. |
| `fonts` | Copy bundled fonts into the user's font directory and refresh the font cache. |
| `aliases` | Install the configured managed alias block for detected shells. |
| `terminal` | Select Bash, Zsh, or Fish; install/configure Atuin and Starship; set the login shell. |
| `dev` | Install the development toolchain and applications, then configure the managed dev shell block. |
| `gnome` | Run wallpaper, favorites, shortcuts, and extensions steps. |
| `shortcuts` | Register configured custom GNOME keyboard shortcuts. |
| `favorites` | Set the GNOME dock favorites from installed desktop entries. |
| `extensions` | Install and enable configured GNOME Shell extensions. |
| `help` | Print CLI usage. |
| `version` | Print the current version. |

See the command guides for details: [installation](docs/install.md),
[packages](docs/packages.md), [language](docs/language.md), [fonts](docs/fonts.md),
[aliases](docs/aliases.md), [terminal](docs/terminal.md), [development](docs/dev.md),
and [GNOME configuration](docs/gnome.md). The GNOME commands also have focused
guides for [favorites](docs/favorites.md) and
[shortcuts](docs/shortcuts.md).

## Full installation

`./setup` and `./setup install` run these steps in order:

1. Packages and applications.
2. Language.
3. Fonts.
4. Aliases.
5. Terminal and default shell.
6. Development environment.
7. On GNOME only: wallpaper, favorites, shortcuts, then extensions.

If a general step fails, the launcher names it, returns its failure status, and
stops before later general steps. The GNOME group attempts all four independent
steps, reports failures, and returns nonzero if any failed. The packages step
also continues independent application installs where safe, summarizes
successes, failures, and skips, and returns nonzero for an incomplete result.
Completed changes are not rolled back. A successful command prints a completion
message; it is not printed after a reported failure.

`--dry-run` propagates to the modules, which print planned operations without
installation, sudo authentication, or configuration writes. Modules may still
read local configuration or inspect state when their dry-run behavior requires
it; see each command guide for specific details.

## Configuration and bundled files

- `config/packages/fedora.txt`, `debian.txt`, and `arch.txt` list native
  packages. Use one package name per line; blank lines and `#` comments are
  ignored.
- `config/flatpak.txt` lists Flatpak application IDs.
- `config/aliases/` contains shell-specific and distro-specific alias text.
- `config/starship.toml` is installed as `~/.config/starship.toml` by
  `./setup terminal`; an existing file is backed up once before replacement.
- `config/favorites.txt`, `config/shortcuts.txt`, and
  `config/gnome-extensions.txt` configure GNOME favorites, keyboard shortcuts,
  and extensions, respectively.
- `assets/fonts/` contains bundled fonts. `assets/wallpaper/wallpaper.jpg` is
  the wallpaper used by the GNOME step.

The development command installs the OpenSSH client. On Fedora and Arch-family
systems it also installs the server package without enabling or starting it. On
Debian-family systems it leaves the server package out because package
installation can activate the SSH service. To install and activate one there,
do so explicitly:

```bash
# Fedora, Arch, or CachyOS
sudo systemctl enable --now sshd

# Debian, Ubuntu, or Linux Mint
sudo apt install openssh-server
sudo systemctl enable --now ssh
```

## Limitations and validation

The project supports explicit distro families and package baselines, not every
Linux distribution. Vendor package availability, repository configuration,
desktop state, and external installers can vary. A successful isolated test or
static check does not establish that every fresh Fedora, Debian, Ubuntu, Mint,
Arch, or CachyOS installation has been exercised. Review the command-specific
guides for prerequisites and known limitations before running a step.

The project does not automatically sign in to applications, enable SSH, or
configure GNOME when GNOME is not detected by the full install.

## License

MIT. See [LICENSE](LICENSE).
