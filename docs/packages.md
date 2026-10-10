# `./setup packages`

Installs the native distribution packages, Flatpak applications, and vendor
applications (Chrome and VS Code) for the detected family. The command is
idempotent: for every entry it checks whether the software is already present
and only installs what is missing.

## Configuration files

| File | Purpose |
| --- | --- |
| `config/packages/fedora.txt` | Native packages for the Fedora / RHEL family (installed with `dnf`) |
| `config/packages/debian.txt` | Native packages for the Debian / Ubuntu family (installed with `apt-get`) |
| `config/packages/arch.txt` | Native packages for the Arch family (installed with `pacman`) |
| `config/flatpak.txt` | Flatpak application IDs installed from the system Flathub remote |

Each file holds one entry per line. Blank lines and everything from `#` to the
end of a line are ignored, so the files are safe to annotate.

Only the list for the detected family is read, plus `config/flatpak.txt`.

- A **missing or unreadable** required list file is fatal and prints the file
  name on stderr before anything is installed.
- A readable file that contains **only comments or blank lines** yields an
  empty list; the step prints a skip message and does not invoke a package
  manager.

## Detection and duplicate prevention

Native packages are detected with the family package manager (`rpm -q`, plus
`rpm -q --whatprovides` on Fedora for virtual provides such as `wget`; `dpkg -s`;
`pacman -Q`). Flatpak apps are detected in both the user and system
scopes (`flatpak info` and `flatpak info --user`). A probe that *errors* is
treated as fatal, never as proof that software is absent.

Some applications are available both as a native package and as a Flatpak. An
explicit, small mapping prevents installing the duplicate Flatpak when the
native application is reliably present:

| Flatpak ID | Native package | Behavior |
| --- | --- | --- |
| `org.mozilla.thunderbird_esr` | `thunderbird` | Skipped when the native package is installed |
| `com.obsproject.Studio` | `obs-studio` | Skipped when the native package is installed |

The native detection uses the package manager (not `command -v`), so a
same-named binary that is not the packaged application does not count.

`SETUP_PKG_PROBE` and `SETUP_FLATPAK_PROBE` override detection for tests
(called as `<probe> <name>`; exit 0 installed, 1 missing, 2 error).

## Family mappings

`config/packages/fedora.txt` is the source catalog. The Debian and Arch lists
use the equivalent package name for that family; entries that the supported
baseline cannot supply are omitted there (the corresponding header comment in
each file lists them). Supported Debian baseline: Debian 13 "trixie" / Ubuntu
24.04 LTS "noble" or newer.

| Source (Fedora) | Debian | Arch |
| --- | --- | --- |
| `firefox` | `firefox-esr` | `firefox` |
| `gcc-c++` | `g++` | `gcc` |
| `golang` | `golang-go` | `go` |
| `libvirt` | `libvirt-daemon-system` | `libvirt` |
| `ninja-build` | `ninja-build` | `ninja` |
| `nmap-ncat` | `ncat` | `nmap` |
| `nodejs22`, `nodejs24` | `nodejs` (once) | `nodejs` |
| `pandoc-cli` | `pandoc` | `pandoc` |
| `python3-pip` | `python3-pip` | `python-pip` |
| `python3` | `python3` | `python` |
| `qemu-kvm` | `qemu-system-x86` | `qemu-system-x86` |
| `vim-enhanced` | `vim` | `vim` |

Fedora has no standalone `npm` package: the npm CLI is provided by the
`nodejs22` / `nodejs24` entries already in the list (via `nodejsXX-npm`), so
the capability is installed without an ambiguous or duplicate package.

Entries intentionally omitted, by list:

- **Debian** (`config/packages/debian.txt`): `nodejs22` and `nodejs24` (use
  `nodejs`), `jupyterlab`, `typescript`, and `fastfetch` (absent from the
  Ubuntu 24.04 LTS baseline; available on Debian 13+ and Ubuntu 25.10+).
- **Arch** (`config/packages/arch.txt`): `nodejs22` and `nodejs24` (use
  `nodejs`), and `typescript`.

## Vendor applications

VS Code and Google Chrome are not distribution repository packages. They keep
their existing dedicated vendor step inside `modules/install_apps.sh`
(official `.deb`/`.rpm` downloads on Fedora/Debian, AUR on Arch) and are not
part of the repository package lists. The remaining vendor-only catalog names
(ChatGPT, Motrix Turbo, Warp Terminal, Zoom, .NET SDK) are out of scope for
this module.

## Arch behavior

On Arch the native transaction keeps its existing `pacman -Syu --noconfirm`
form.

## Dry run

`./setup --dry-run packages` performs only read-only detection, prints the
commands that would run, and changes nothing.
