# linux-postinstall

A small post-install script for my own Linux machines. One entry point, plain
text config, no state files. Run it on a fresh machine, or run it again on an
old one, and it works out what is still missing.

```
./setup                 # packages, then every module in config/modules.txt
./setup modules git     # just the git module
./setup --dry-run       # print every command, change nothing
```

Supported: Fedora and other RHEL-like systems, Debian/Ubuntu and other
Debian-like systems, and Arch.

## How it works

`setup` detects the distro, installs the package lists for it, then runs each
module in `config/modules.txt`. Every step checks the current state before
acting, so a second run reports `already installed` and `unchanged` and touches
nothing.

Two rules the modules follow:

- **Idempotent.** Rerunning is always safe. A version that already matches is
  left alone.
- **Refuses to guess.** Downloaded binaries are checked against a pinned
  SHA-256 in `config/fonts.sha256` before being installed. A mismatch stops that
  module with an error rather than installing something unverified.

There is no database, ledger, or import/export step. State is the machine
itself.

## Layout

```
setup              entry point and CLI
check.sh           validation; ./check.sh
lib/
  common.sh        logging, run/run_root, read_list, write_atomic
  packages.sh      distro detection, package and Flatpak install
  config.sh        managed blocks in config files, with backups
  modules.sh       module discovery and execution
config/            plain text, one item per line
modules/           one file per module, defines install_<id>
assets/wallpaper/  optional, used by the gnome module
```

## Config files

Every file in `config/` is plain text, one item per line, with `#` for comments.
Edit them and rerun; there is nothing else to regenerate.

| File | Purpose |
| --- | --- |
| `packages.txt` | packages for every distro |
| `packages-rpm.txt` | extra packages for RHEL-like |
| `packages-deb.txt` | extra packages for Debian-like |
| `packages-arch.txt` | extra packages for Arch |
| `packages-gnome.txt` | GNOME-specific packages, added when GNOME is present |
| `flatpak.txt` | Flatpak applications |
| `modules.txt` | which modules run by default, and in what order |
| `aliases.txt` | shell aliases written to a sourced file |
| `fonts.txt` / `fonts.sha256` | Nerd Fonts and their pinned digests |
| `gitconfig.txt` | settings added to `~/.gitconfig` |
| `favorites.txt`, `shortcuts.txt`, `extensions.txt` | GNOME settings |

## Modules

| Module | Does |
| --- | --- |
| `git` | sets git aliases and options in a managed block in `~/.gitconfig` |
| `terminal` | oh-my-posh and atuin, aliases, prompt setup in `~/.bashrc` |
| `fonts` | pinned Nerd Fonts into `~/.local/share/fonts`, then `fc-cache` |
| `gnome` | favourites, keyboard shortcuts, extensions, theme, wallpaper |
| `dev` | VS Code from Microsoft's repo, verified by GPG key fingerprint |
| `dns` | DNS resolver; **opt-in**, changes system settings |
| `locale` | system locale; **opt-in**, changes system settings |

`dns` and `locale` change system-wide settings and are not in
`config/modules.txt`. Run them deliberately:

```
./setup install dns
./setup install locale
```

## Managed blocks

When a module edits a file you also own, like `~/.bashrc` or `~/.gitconfig`, it
writes a single block between markers and leaves the rest of the file alone:

```bash
# BEGIN postinstall terminal
...
# END postinstall terminal
```

On the next run the block is replaced, not appended, so it cannot grow. Your own
lines outside the markers are preserved. The first time a file is touched, a
timestamped backup is written next to it.

## Sudo

Packages and anything else that needs root go through `sudo` only when needed.
If you are not root and have no `sudo`, the script says so and stops instead of
half-installing.

## Dry run

`--dry-run` prints every command it would run, including the `sudo` calls, and
changes nothing: no packages, no downloads, no edits. Use it to see what a run
would do.

```
./setup --dry-run
./setup --dry-run install terminal
```

## Validation

```
./check.sh          # everything
./check.sh syntax   # bash -n over every script
./check.sh unit     # the unit checks
```

`check.sh` uses temporary directories and fake package managers, so it touches
neither this machine nor the network. It covers distro detection, config list
parsing, package and Flatpak install, module selection and failure propagation,
managed blocks, verified binary install, dry-run non-mutation, and CLI parsing.

## Adding a module

Create `modules/<id>.sh` defining a single function named after the file:

```bash
install_<id>() {
    read_list "$FS_ROOT/config/<id>.txt" | while IFS= read -r item; do
        [[ -n "$item" ]] || continue
        run "do something with $item" some-command -- "$item"
    done
}
```

Add `id` to `config/modules.txt` to include it in the default run, or leave it
out and call it directly with `./setup modules <id>`. A module that fails is
reported and the run exits non-zero, but the modules after it still run.

Useful pieces from `lib/common.sh`:

- `run "label" cmd ...` — log the command, run it, fail loudly on error
- `run_root "label" cmd ...` — the same, under `sudo` when needed
- `read_list path` — read a config file, dropping blanks and `#` comments
- `write_atomic path` — write to a temp file and rename, so readers never see a
  half-written file
- `write_block path id` — replace a `# BEGIN`/`# END postinstall <id>` block
- `log_info`, `log_warn`, `log_error`, `die`

Use `run` rather than calling commands directly. It is what makes the output
readable and `--dry-run` work.