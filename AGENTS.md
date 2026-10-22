# Instructions for coding agents

## Project and architecture

This is a small personal Linux post-install and rebuild tool, not a universal
provisioning system. The `setup` Bash entry point parses the CLI, sets the
global dry-run flag, and owns the fixed full-install order and its overall
failure status. Shared functions belong in `lib/common.sh`; setup operations
belong in `modules/`; editable lists and shell configuration belong in
`config/`; bundled static files belong in `assets/`; user documentation lives
in `README.md` and `docs/`.

The CLI commands are `install` (also the no-argument default), `packages`,
`language`, `fonts`, `aliases`, `terminal`, `dev`, `gnome`, `shortcuts`,
`favorites`, `extensions`, `help`, and `version`. The current reported version
is defined in `setup`; verify it there rather than maintaining a second source.
The practical support scope is Fedora/Nobara, Debian 13 or newer, Ubuntu 24.04
LTS or newer, Linux Mint based on a supported Ubuntu release, and Arch/CachyOS.
This is not a claim that every derivative or release has been tested.

Keep Bash code explicit and proportional to this personal tool. Prefer the
existing family-specific package lists and shared helpers; do not add a
framework, dependency graph, generic state layer, or one-use helper library.
Keep installation stages and command behavior consistent with the existing
module and error-reporting conventions.

## Safety and behavior

- Preserve user changes. Inspect `git status` and relevant diffs before editing;
  do not reset, clean, stash, overwrite unrelated work, or treat untracked files
  as disposable.
- Do not run real package installs, vendor installers, privileged system
  changes, or host shell/locale/desktop configuration as tests. Use temporary
  homes and fake commands for behavior that can be isolated.
- Route privileged operations through `run_root` in `lib/common.sh`. Do not
  manipulate sudo timestamps; credentials expire under the system's sudo
  policy.
- Respect `SETUP_DRY_RUN=1` / `--dry-run`: print planned operations without
  invoking installers, authenticating sudo, writing files, or changing system
  state. Avoid state probes in dry-run when the module contract requires a
  printed plan instead.
- Required failures must return nonzero and be reported. Continue independent
  work only when safe, and report partial failures instead of claiming success.
  Make reruns predictable and preserve existing user data according to the
  module's documented backup or managed-block policy.
- The development command installs the OpenSSH client, and installs the server
  package only on Fedora/Arch-family systems where package installation does
  not automatically activate it. Debian-family systems must not install the
  server package implicitly. Setup must not enable or start SSH.
- Keep GNOME work gated as implemented: the full install runs the GNOME group
  only when `desktop_environment` detects GNOME; standalone GNOME modules
  report a successful skip outside GNOME.
- Do not reintroduce rejected behaviors: sudo timestamp invalidation, automatic
  repository updates, direct resolver replacement, immutable DNS files,
  destructive shell startup replacement, unconditional optional-tool
  initialization, fixed temporary installer directories, countdown sleeps,
  Oh My Posh, or non-official Starship installation.

## Changes, review, and validation

Work only on the requested scope. Do not create replacement planning or
completion trackers, or edit unrelated files unless the user explicitly asks.
Update the relevant user documentation when behavior or configuration changes.
If evidence is incomplete or docs disagree with code, inspect the execution
path, state what remains uncertain, and do not silently broaden the
implementation.

Before reporting a code change, run `bash -n` on changed scripts and
`git diff --check`, plus focused isolated checks for the affected behavior.
Smoke-check help, version, invalid CLI input, and dry-run when relevant. Report
checks that were not available or that still fail. Request independent Senior
review when the user or project workflow requires it; do not describe work as
approved before that review passes.

Do not stage, commit, push, merge, tag, or switch branches unless the user
explicitly authorizes that action. Finish with a concise account of files
changed, validation performed, limitations, and remaining findings.
