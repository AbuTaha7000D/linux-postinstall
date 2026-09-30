# Export tree format

`./setup export <dir>` writes a self-contained, re-importable snapshot of the
selected profile. `./setup install --manifest <dir>` consumes it.

```sh
./setup export ./backup --profile desktop
./setup install --manifest ./backup            # replays profile 'desktop'
./setup install --manifest ./backup --profile minimal   # a profile in the tree
```

## Layout

```
export.meta                    metadata: format, version, family, profile
<profile>.conf                 the profile, with MODULE_DEPENDS already resolved
manifests/<id>.list            the module's system package ids, family-resolved
manifests/<id>.flatpaks.list   the module's flatpak ids
state/gsettings.list           tab-separated: schema, key, value
state/extensions.list          enabled extension UUIDs, one per line
state/fonts.list               tab-separated: font label, marker file path
files/<name>                   a managed block, extracted verbatim
files/index                    tab-separated: <name>, source path
```

Every file listed above is always written, empty when there was nothing to
record, so the tree shape does not depend on the host. `<id>` is the module id,
which the P4.2 invariant makes equal to the module directory's basename.

## Re-import semantics

`--manifest` replaces the profile source *and* the package source. A re-import
reads the module's ids from `manifests/`, never from the module tree, so it
reproduces what was exported even after the live lists have moved. That is the
point of the flag: `./setup install --profile desktop` answers "what would this
profile install today", and `--manifest` answers "what did this machine
actually install".

A module absent from `manifests/` contributes nothing. It does **not** fall back
to its live list, because a plan mixing an exported set with a live one would
be neither the export nor the profile and the user could not tell which ids
came from where.

Only the package and flatpak namespaces are replayed. `state/` and `files/` are
a record of the export for review, diffing and auditing; nothing reads them
back. Replaying managed blocks into `$HOME` is deliberately out of scope, and
`setup verify` does not read an export tree either — it audits the live system.

The exported `<profile>.conf` is the profile with `MODULE_DEPENDS` already
resolved, so a re-import plans the same module set. Note that this makes a
dependency-pulled module indistinguishable from a curated one in that file: the
P8.3 risk gate treats the tree's own ids as curated, so a future high-risk
module reached only through `MODULE_DEPENDS` would not be re-gated on the
strength of the export alone. (The P4.7 pre-seed filter still drops any
high/destructive module the profile does not name, and `dns`/`locale` are in no
profile, so nothing is exploitable today.)

## What is never exported

The exporter is an allowlist, so the following cannot reach the tree by
construction — there is no code path that reads them:

- the state root: run logs, backups, module registry, selection files, notes
- any non-exported keyring or downloaded file
- anything outside a `# BEGIN/END fedora-setup` block in a managed file, so
  unrelated user config in `~/.gitconfig`, `~/.bashrc` and the aliases file
  is not copied
- dependency and package caches

Managed files that are symlinks are skipped with a warning rather than
followed, so a link cannot pull an arbitrary file's contents into the tree.

The tree contains no timestamp, so two exports of the same state are
byte-identical and can be diffed or committed. The tool's own paths are written
`$HOME`-relative (`~/.gitconfig`), and so is the font marker column, so the
bookkeeping carries no home directory.
Captured *values* are recorded verbatim, and a wallpaper gsettings value
legitimately embeds an absolute `file://` URI — rewriting it would make the
snapshot inaccurate.

## Notes

- `export.meta` must be present; the directory is otherwise not recognized as
  an export tree. It is also the **completion marker** — it is written last, so
  a tree that has it is a tree whose every stage succeeded. A failed export
  leaves a partial directory that a re-import refuses.
- A symlinked tree root, and a symlinked list file inside it, are refused.
- If `--profile` is omitted on export, the profile defaults to `full`, which is
  comment-only in this repo — so an export with no `--profile` records zero
  modules and an empty tree. Pass `--profile` to get a useful snapshot.
- If `--profile` is omitted on re-import, the profile recorded in
  `export.meta` is used.
- Re-exporting into an existing export tree is allowed; a non-empty directory
  that is not an export tree is refused. A re-export **drops `export.meta`
  before its first write** and re-adds it at the end, so a refresh that fails
  part way leaves a tree that is refused — otherwise the previous run's marker
  would still describe the *previous* profile next to the new manifests, and a
  re-import would silently replay the old profile with no error anywhere. The
  drop happens after the output-path checks and **before the manifest loop**,
  which is where writing actually starts: dropping it next to the other
  setup — after the loop — is still a hole, because a failure on the second
  module has already rewritten the first module's manifests while the old
  marker is untouched, and the re-import then replays the old profile over the
  new ids. A run rejected during argument or profile validation has written
  nothing, so the previous good tree stays valid. Files from a wider previous
  export are left behind; the marker is the validity contract and a tree
  without one is refused wholesale, so they cannot be replayed.
- A dry run writes nothing and probes nothing: it lists every file it would
  write and never queries gsettings, extensions, fonts or the filesystem.
- A managed file whose `# BEGIN fedora-setup <name>` has no matching `# END` is
  skipped with a warning rather than copied to end-of-file, so a stray marker
  cannot pull surrounding user content into the tree. A file with **no** marker
  at all is simply a file with no block and is skipped silently — absence and
  truncation are different states, and conflating them makes every unconfigured
  file emit a warning next to a contradictory "no managed block" line.
- The block is located with `lib/fs.sh`'s own `_fs_validate_markers`,
  `_fs_locate` and `_fs_locate_ok`, not by a parser in `export.sh`. The
  exporter therefore refuses exactly the files `fs_managed_block` refuses —
  including a **second block with the same name**, which the writer rejects but
  a naive reader would concatenate into one "block" the tool would not manage.
  The wording of a refusal therefore comes from `lib/fs.sh`, not from
  `export.sh`.
