#!/usr/bin/env bash
# tests/fixtures/update.sh - P9.4 fixture for `./setup update`.
#
# Drives the REAL launcher against REAL git repositories built inside FX_TMP:
# one bare origin, a seed commit, and then real `git clone`s of it. Cloning (as
# opposed to `git init` + push per test repo) is what gives every test repo a
# genuine upstream ref and a shared, fast-forwardable history -- with independent
# histories pushed at one bare remote, every push after the first is rejected as
# a non-fast-forward and the repos silently end up with NO upstream, which made
# an early version of this fixture test "no upstream" in every cell that claimed
# to test something else. clone_repo therefore FAILS LOUD rather than continuing
# if a clone has no upstream: a fixture that cannot set up the state it is about
# to assert on reports its cells against the wrong precondition.
#
# Nothing here touches the repository this fixture runs from. `update` always
# passes `git -C "$root"`, and the cwd-independence cell asserts that directly
# by invoking the launcher from inside an UNRELATED git repository: if any code
# path ran git in the caller's cwd, that cell would report the other
# repository's state instead of the tool's own.
#
# The four states are pinned separately, because collapsing them is how an
# update tool talks a user into a bad merge: up-to-date, behind, ahead and
# diverged must each be reported distinctly, and only "behind" may fast-forward.
# The load-bearing refusal is divergence: every merge is --ff-only, so this tool
# can never be the thing that creates a merge commit in someone's checkout, and
# the cell checks for a leftover MERGE_HEAD as well as an unmoved HEAD.
#
# Two cells are about honesty rather than mechanics, and are the ones a reader
# should check first:
#   * a dry run must NOT claim to know the remote state (it cannot fetch, so
#     guessing from a stale ref would be confidently wrong), and must render a
#     RESOLVED-AT-RUN-TIME marker rather than a plausible-looking command;
#   * a fast-forward that exits 0 without moving HEAD must be reported as a
#     FAILURE, not as an update -- checked with a fake `git` that succeeds at
#     everything and silently does nothing on `merge`.
#
# No commit sha is ever asserted: shas depend on wall-clock commit times, so
# pinning one would make this fixture non-reproducible. The cells assert
# MESSAGES and RELATIVE facts (HEAD equals the upstream ref after a pull; the
# published file arrived; HEAD did not move when it must not).
#
# Usage: bash tests/fixtures/update.sh  (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init
printf 'P9.4 update\n'

ORIGIN="$FX_TMP/origin.git"
SEED="$FX_TMP/seed"
GPUB="$FX_TMP/publisher"
SETUP="$ROOT/setup"
FX_REPO="$ROOT"

# git needs an identity; without these the seed commit fails and every cell
# then reports "no upstream" instead of what it means to test.
GIT_ID=(-c user.email=fixture@example.invalid -c user.name=fixture)
REAL_GIT="$(command -v git)"

_git() { git "$@" >/dev/null 2>&1; }

# clone_repo <name> -- a fresh clone of origin, tracked in FX_REPO
clone_repo() {
    local name="$1"
    rm -rf -- "$FX_TMP/$name"
    git clone -q "$ORIGIN" "$FX_TMP/$name" 2>/dev/null
    FX_REPO="$FX_TMP/$name"
    if ! git -C "$FX_REPO" rev-parse --verify --quiet '@{u}' >/dev/null 2>&1; then
        fx_bad "fixture setup: clone '$name' has no upstream (every cell would be vacuous)"
        exit 1
    fi
}

# publish <message> -- add a commit to origin from the publisher clone, so every
# existing clone is now one behind.
publish() {
    local msg="${1:-upstream work}"
    printf 'published: %s\n' "$msg" >>"$FX_TMP/publisher/docs/published.md"
    _git -C "$GPUB" add -A
    _git -C "$GPUB" "${GIT_ID[@]}" commit -m "$msg"
    _git -C "$GPUB" push -q origin main
}

# run_setup <label> <expected-rc> [<VAR=val>...] -- <setup args...>
# FX_BLOCK_RC carries the process status; stdout/stderr land in FX_OUT/FX_ERR.
# HOME is pinned so nothing can reach the real user's dotfiles.
run_setup() {
    local label="${1:-}" want="${2:-}"
    shift 2
    local -a envs=() args=()
    while [[ $# -gt 0 && "$1" != "--" ]]; do
        envs+=("$1")
        shift
    done
    shift || :
    args=("$@")
    (   set -uo pipefail
        set +e
        env -i PATH="/usr/bin:/bin" HOME="$FX_TMP/home" \
            "${envs[@]+"${envs[@]}"}" "$SETUP" "${args[@]+"${args[@]}"}"
    ) >"$FX_OUT" 2>"$FX_ERR"
    FX_BLOCK_RC=$?
    if [[ -n "${FX_DEBUG_CELL:-}" && "$label" == "$FX_DEBUG_CELL" ]]; then
        { echo "=== $label rc=$FX_BLOCK_RC"; echo "--- stdout"; cat "$FX_OUT"; echo "--- stderr"; cat "$FX_ERR"; } >&2
    fi
    if [[ -n "$label" ]]; then
        fx_block_rc "$label rc" "$want"
    fi
    return 0
}

# run_update <repo> <label> <expected-rc> [<VAR=val>...] -- <args...>
# Points SETUP at that repo's own launcher. The launcher resolves ITS OWN root
# from $0, which is what makes `git -C "$root"` the only correct place to run
# git -- and what the cwd-independence cell below then depends on.
run_update() {
    local repo="${1:-}" label="${2:-}" want="${3:-}"
    shift 3
    local -a envs=() args=()
    while [[ $# -gt 0 && "$1" != "--" ]]; do
        envs+=("$1")
        shift
    done
    shift || :
    args=(update "$@")
    FX_REPO="$repo"
    SETUP="$repo/setup"
    run_setup "$label" "$want" "${envs[@]+"${envs[@]}"}" -- "${args[@]}"
}

# ---------------------------------------------------------------- setup

mkdir -p "$FX_TMP/home"
_git init -q --bare "$ORIGIN"
rm -rf -- "$SEED"
mkdir -p "$SEED"
tar -C "$ROOT" --exclude=.git --exclude=tests -cf - . | tar -C "$SEED" -xf -
_git -C "$SEED" init -q --initial-branch=main
_git -C "$SEED" "${GIT_ID[@]}" add -A -f
_git -C "$SEED" "${GIT_ID[@]}" commit -m "seed"
_git -C "$SEED" remote add origin "$ORIGIN"
_git -C "$SEED" push -q -u origin main
_git clone -q "$ORIGIN" "$GPUB"
if ! git -C "$GPUB" rev-parse --verify --quiet '@{u}' >/dev/null 2>&1; then
    fx_bad "fixture setup: the publisher clone has no upstream"
    exit 1
fi

# ------------------------------------------- 1. version and identity reported

clone_repo up2date
run_update "$FX_REPO" "up-to-date" 0 --
fx_out 'fedora-setup 0[.]1[.]0-dev'
fx_out 'update: commit '
fx_out 'branch main'
fx_out 'working tree is clean'
fx_out 'already current with the remote'

# --------------------------------- 2. behind: reported, and NOT pulled silently

clone_repo behind
publish "upstream one"
run_update "$FX_REPO" "behind reports without --pull" 0 --
fx_out '1 commit[(]s[)] behind the remote'
fx_out 're-run with --pull'
if grep -q 'Fast-forward\|updating [0-9a-f]' "$FX_OUT" "$FX_ERR"; then
    fx_bad "update moved the working tree without --pull (the silent auto-pull this replaces)"
else
    fx_ok
fi
# valid HERE and only here: this clone was made before publish(), so the file's
# absence is real evidence. Later clones already contain it (see the dirty2 and
# dry-run cells, which check HEAD and the remote-tracking ref instead).
if [[ -e "$FX_REPO/docs/published.md" ]]; then
    fx_bad "the behind run fast-forwarded anyway"
else
    fx_ok
fi

# ------------------------------------------- 3. behind + --pull fast-forwards

before_head="$(git -C "$FX_REPO" rev-parse HEAD)"
run_update "$FX_REPO" "behind with --pull" 0 -- --pull
fx_out 'fast-forwarding'
fx_out 'update: updated to '
if [[ "$before_head" != "$(git -C "$FX_REPO" rev-parse HEAD)" ]]; then fx_ok; else fx_bad "--pull did not move HEAD"; fi
if [[ -e "$FX_REPO/docs/published.md" ]]; then fx_ok; else fx_bad "the published file did not arrive"; fi
# The cell verifies the postcondition ITSELF rather than trusting the tool's own
# "updated to <sha>" line: after a correct pull the clone is no longer behind.
if [[ "$(git -C "$FX_REPO" rev-list --count HEAD..'@{u}')" == "0" ]]; then
    fx_ok
else
    fx_bad "after the pull the clone is still behind the remote"
fi

# ------------------------------------------------- 4. up-to-date + --pull is a no-op

head_now="$(git -C "$FX_REPO" rev-parse HEAD)"
run_update "$FX_REPO" "up-to-date with --pull" 0 -- --pull
fx_out 'nothing to pull'
if [[ "$head_now" == "$(git -C "$FX_REPO" rev-parse HEAD)" ]]; then fx_ok; else fx_bad "a no-op pull moved HEAD"; fi

# ---------------------------------------------------------------- 5. ahead

clone_repo ahead
printf 'local only\n' >>"$FX_REPO/docs/published.md"
_git -C "$FX_REPO" add -A
_git -C "$FX_REPO" "${GIT_ID[@]}" commit -m "local only"
run_update "$FX_REPO" "ahead of the remote" 0 --
fx_out 'already current, and 1 commit[(]s[)] ahead of the remote'
ahead_head="$(git -C "$FX_REPO" rev-parse HEAD)"
run_update "$FX_REPO" "ahead with --pull" 0 -- --pull
fx_out 'already current, and 1 commit[(]s[)] ahead of the remote'
if [[ "$ahead_head" == "$(git -C "$FX_REPO" rev-parse HEAD)" ]]; then fx_ok; else fx_bad "--pull moved a branch that was AHEAD of the remote"; fi
if [[ -z "$(git -C "$FX_REPO" status --porcelain)" ]]; then fx_ok; else fx_bad "--pull dirtied a branch with nothing to pull"; fi

# ------------------------------------------------------------- 6. diverged

clone_repo diverged
publish "upstream two"
printf 'local only\n' >>"$FX_REPO/docs/published.md"
_git -C "$FX_REPO" add -A
_git -C "$FX_REPO" "${GIT_ID[@]}" commit -m "local only"
run_update "$FX_REPO" "diverged is reported distinctly" 0 --
fx_out 'diverged - 1 commit[(]s[)] behind and 1 commit[(]s[)] ahead of the remote'
fx_out 'resolve the divergence'
div_head="$(git -C "$FX_REPO" rev-parse HEAD)"
run_update "$FX_REPO" "diverged with --pull is refused" 1 -- --pull
fx_err 'only fast-forwards'
if [[ "$div_head" == "$(git -C "$FX_REPO" rev-parse HEAD)" ]]; then
    fx_ok
else
    fx_bad "--pull moved a diverged branch"
fi
if [[ -e "$FX_REPO/.git/MERGE_HEAD" ]]; then
    fx_bad "a merge was started on a diverged branch"
else
    fx_ok
fi

# ------------------------------------------------ 7. an unclean tree is refused

clone_repo dirty
printf 'edit\n' >>"$FX_REPO/setup"
run_update "$FX_REPO" "modified tracked file is refused" 1 --
fx_err 'working tree is not clean'
fx_out 'setup'

clone_repo untracked
printf 'stray\n' >"$FX_REPO/stray.txt"
run_update "$FX_REPO" "untracked file is refused" 1 -- --pull
fx_err 'working tree is not clean'
fx_out 'stray[.]txt'

# the refusal must happen BEFORE the fetch: an unclean tree must never be
# fast-forwarded, so this cell proves the pull did not happen at all
clone_repo dirty2
publish "upstream three"
printf 'edit\n' >>"$FX_REPO/setup"
dirty2_head="$(git -C "$FX_REPO" rev-parse HEAD)"
dirty2_remote="$(git -C "$FX_REPO" rev-parse '@{u}')"
run_update "$FX_REPO" "unclean tree is not pulled even with --pull" 1 -- --pull
fx_err 'working tree is not clean'
if [[ "$dirty2_head" == "$(git -C "$FX_REPO" rev-parse HEAD)" ]]; then fx_ok; else fx_bad "an unclean tree was fast-forwarded anyway"; fi
if [[ "$dirty2_remote" == "$(git -C "$FX_REPO" rev-parse '@{u}')" ]]; then fx_ok; else fx_bad "the refusal happened after the fetch, not before"; fi

# ------------------------------------------- 8. not a git working tree

rm -rf -- "$FX_TMP/plain"
mkdir -p "$FX_TMP/plain"
tar -C "$ROOT" --exclude=.git --exclude=tests -cf - . | tar -C "$FX_TMP/plain" -xf -
run_update "$FX_TMP/plain" "not a git checkout" 1 --
fx_err 'not a git working tree'

# ------------------------------------------------------- 9. no git in PATH

clone_repo nopath
mkdir -p "$FX_TMP/nogit-bin"
for b in bash dirname readlink; do
    ln -sf "$(command -v "$b")" "$FX_TMP/nogit-bin/$b" 2>/dev/null || :
done
run_update "$FX_REPO" "git missing from PATH" 1 PATH="$FX_TMP/nogit-bin" --
fx_err 'git not found in PATH'

# ------------------------------------------------- 10. detached HEAD / no upstream

clone_repo detached
_git -C "$FX_REPO" checkout -q --detach HEAD
det_head="$(git -C "$FX_REPO" rev-parse HEAD)"
run_update "$FX_REPO" "detached HEAD" 0 --
fx_out 'on a detached HEAD'
# detached is NOT "no upstream configured": the advice must differ, because
# `git branch --set-upstream-to` is impossible while detached.
fx_err 'HEAD is detached, so there is no branch to compare against'
if grep -q 'set-upstream-to' "$FX_OUT" "$FX_ERR"; then
    fx_bad "a detached HEAD was told to set an upstream"
else
    fx_ok
fi
if [[ "$det_head" == "$(git -C "$FX_REPO" rev-parse HEAD)" ]]; then fx_ok; else fx_bad "the detached report moved HEAD"; fi
run_update "$FX_REPO" "detached HEAD with --pull is refused" 1 -- --pull
fx_err 'needs a branch'
if [[ "$det_head" == "$(git -C "$FX_REPO" rev-parse HEAD)" ]]; then fx_ok; else fx_bad "--pull moved a detached HEAD"; fi

clone_repo noupstream
_git -C "$FX_REPO" branch --unset-upstream
_git -C "$FX_REPO" remote set-url origin "$FX_TMP/does-not-exist.git"
run_update "$FX_REPO" "no upstream" 0 --
fx_err 'no upstream tracking branch is configured'
run_update "$FX_REPO" "no upstream with --pull is refused" 1 -- --pull
fx_err 'needs an upstream tracking branch'

# -------------------------------------------- 11. cwd never decides the repo

clone_repo elsewhere
mkdir -p "$FX_TMP/other"
_git init -q --initial-branch=other "$FX_TMP/other"
printf 'stray\n' >"$FX_TMP/other/dirty.txt"
(
    cd "$FX_TMP/other" || exit 1
    env -i PATH="/usr/bin:/bin" HOME="$FX_TMP/home" "$FX_REPO/setup" update
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "run from an unrelated checkout rc" 0
fx_out 'already current'
if grep -q 'working tree is not clean' "$FX_OUT" "$FX_ERR"; then
    fx_bad "update inspected the caller's cwd instead of the tool's own repository"
else
    fx_ok
fi

# --------------------------------------------------------- 12. dry-run honesty

clone_repo dryrun
publish "upstream four"
dry_before="$(git -C "$FX_REPO" rev-parse HEAD)"
dry_remote="$(git -C "$FX_REPO" rev-parse '@{u}')"
run_update "$FX_REPO" "dry run renders the plan" 0 -- --pull --dry-run
fx_out 'would run: git -C .* fetch'
fx_out 'would run: git -C .* merge --ff-only RESOLVED-AT-RUN-TIME'
fx_out 'were NOT performed'
# A dry run cannot fetch, so it must NOT claim to know the remote state. A stale
# ref would let it print "already current" about a machine that is behind.
if grep -q 'already current\|commit(s) behind' "$FX_OUT" "$FX_ERR"; then
    fx_bad "the dry run claimed a remote state it cannot know without fetching"
else
    fx_ok
fi
if [[ "$dry_before" == "$(git -C "$FX_REPO" rev-parse HEAD)" ]]; then fx_ok; else fx_bad "the dry run moved HEAD"; fi
if [[ -z "$(git -C "$FX_REPO" status --porcelain)" ]]; then fx_ok; else fx_bad "the dry run dirtied the working tree"; fi
if [[ "$dry_remote" == "$(git -C "$FX_REPO" rev-parse '@{u}')" ]]; then
    fx_ok
else
    fx_bad "the dry run fetched: the remote-tracking ref moved"
fi
run_update "$FX_REPO" "dry run without --pull" 0 -- --dry-run
fx_out 'would run: git -C .* fetch'
if grep -q 'would run: .*merge' "$FX_OUT" "$FX_ERR"; then
    fx_bad "a dry run rendered a merge that was never requested"
else
    fx_ok
fi

# ---------------------------- 12b. a dry run must not invoke git AT ALL

# The strongest available oracle for "probes nothing" is a git that RECORDS every
# invocation. Asserting only the consequences (refs unmoved) cannot see a read:
# adding a real `git rev-parse` into the dry-run branch leaves refs, HEAD and the
# tree untouched, so a suite that checks those stays green while the promise is
# broken. The same shim pins the positive fact too -- that a plain report DOES
# fetch -- rather than leaving it to be inferred from a printed message.
clone_repo probed
mkdir -p "$FX_TMP/recbin"
cat >"$FX_TMP/recbin/git" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FS_UPDATE_GIT_LOG"
exec "@REAL_GIT@" "$@"
FAKE
sed -i "s#@REAL_GIT@#$REAL_GIT#" "$FX_TMP/recbin/git"
chmod +x "$FX_TMP/recbin/git"
probe_log="$FX_TMP/git-probes.log"
: >"$probe_log"
run_update "$FX_REPO" "dry run" 0 PATH="$FX_TMP/recbin:/usr/bin:/bin" FS_UPDATE_GIT_LOG="$probe_log" -- --dry-run
if [[ -s "$probe_log" ]]; then
    fx_bad "a dry run invoked git: $(head -n 1 "$probe_log")"
    sed -n '1,3p' "$probe_log" >&2
else
    fx_ok
fi
# and the positive control: without --dry-run the same tool does fetch, so the
# empty log above is the dry run's doing and not a shim that never runs.
run_update "$FX_REPO" "a real report does fetch" 0 PATH="$FX_TMP/recbin:/usr/bin:/bin" FS_UPDATE_GIT_LOG="$probe_log" --
if grep -q 'fetch' "$probe_log"; then
    fx_ok
else
    fx_bad "the recording shim saw no fetch at all, so the dry-run cell proves nothing"
    sed -n '1,5p' "$probe_log" >&2
fi

# ------------------- 12c. an IGNORED untracked file must not be clobbered

# Measured behaviour, not a hypothetical: for an incoming file at a path the user
# already holds untracked, an untracked-but-NOT-ignored path is reported by
# `status --porcelain` (so the tree is already refused) and git itself refuses the
# merge; an untracked-and-IGNORED path is reported by NOTHING and the merge
# SUCCEEDS, replacing the local file. --ff-only does not save it, the collision
# is inside the fast-forward, and the HEAD==upstream postcondition is satisfied
# because HEAD did move -- so a successful run silently destroys a file.
# The oracle is the CONTENT plus git's own refs, never the tool's messages.
clone_repo clobber
# upstream ignores the path and then adds a file there. The add must be -f: a
# plain `git add -A` is itself blocked by the ignore rule, so the file would never
# enter the incoming commits and the cell would test nothing (this is exactly what
# the first version of this cell did).
printf 'downloads/\n' >>"$FX_TMP/publisher/.gitignore"
_git -C "$GPUB" add -A
_git -C "$GPUB" "${GIT_ID[@]}" commit -m "ignore downloads"
mkdir -p "$GPUB/downloads"
printf 'UPSTREAM VERSION\n' >"$GPUB/downloads/pkg.deb"
_git -C "$GPUB" add -f downloads/pkg.deb
_git -C "$GPUB" "${GIT_ID[@]}" commit -m "add a file at an ignored path"
_git -C "$GPUB" push -q origin main
# the precondition is asserted, not assumed: the incoming commit really does add
# this path, and locally the path really is invisible to status --porcelain.
if git -C "$GPUB" ls-tree -r --name-only HEAD | grep -q '^downloads/pkg\.deb$'; then
    fx_ok
else
    fx_bad "precondition: upstream does not add downloads/pkg.deb"
fi
mkdir -p "$FX_TMP/clobber/downloads"
printf 'MY LOCAL WORK\n' >"$FX_TMP/clobber/downloads/pkg.deb"
# the precondition the defect needs, asserted rather than assumed
if [[ -z "$(git -C "$FX_TMP/clobber" status --porcelain)" ]]; then
    fx_ok
else
    fx_bad "precondition: the clobbering file should be invisible to status --porcelain"
fi
if git -C "$FX_TMP/clobber" check-ignore -q downloads/pkg.deb; then fx_ok; else fx_bad "precondition: the path is not ignored"; fi
clob_head="$(git -C "$FX_TMP/clobber" rev-parse HEAD)"
run_update "$FX_TMP/clobber" "an ignored untracked file is not clobbered" 1 -- --pull
fx_err 'would overwrite your untracked file'
fx_err 'downloads/pkg.deb'
if [[ "MY LOCAL WORK" == "$(cat "$FX_TMP/clobber/downloads/pkg.deb" 2>/dev/null)" ]]; then
    fx_ok
else
    fx_bad "the local file was destroyed by the fast-forward"
fi
if [[ "$clob_head" == "$(git -C "$FX_TMP/clobber" rev-parse HEAD)" ]]; then fx_ok; else fx_bad "the merge happened despite the collision"; fi

# ------------------- 12d. a DANGLING SYMLINK is on disk, even though -e says no

# `-e` FOLLOWS symlinks, so it is false for a dangling one. A symlink into an
# unmounted drive, or into a file not created yet, is exactly what users hold
# under assets/wallpaper/ and downloads/, and git replaces it silently with rc 0.
# The cell asserts the asymmetry itself (`-L` true, `-e` false) before running,
# because without it the cell would pass for the wrong reason.
clone_repo dangling
mkdir -p "$GPUB/assets/wallpaper"
printf 'UPSTREAM IMAGE\n' >"$GPUB/assets/wallpaper/bg.png"
_git -C "$GPUB" add -f assets/wallpaper/bg.png
_git -C "$GPUB" "${GIT_ID[@]}" commit -m "add an image at an ignored path"
_git -C "$GPUB" push -q origin main
mkdir -p "$FX_TMP/dangling/assets/wallpaper"
ln -s /mnt/not-mounted/bg.png "$FX_TMP/dangling/assets/wallpaper/bg.png"
if [[ -L "$FX_TMP/dangling/assets/wallpaper/bg.png" ]]; then
    fx_ok
else
    fx_bad "precondition: the local path is not a symlink"
fi
if [[ ! -e "$FX_TMP/dangling/assets/wallpaper/bg.png" ]]; then
    fx_ok
else
    fx_bad "precondition: -e is true here, so the dangling case is not exercised"
fi
if [[ -z "$(git -C "$FX_TMP/dangling" status --porcelain)" ]]; then
    fx_ok
else
    fx_bad "precondition: the symlink is visible to status --porcelain"
fi
if git -C "$FX_TMP/dangling" check-ignore -q assets/wallpaper/bg.png; then fx_ok; else fx_bad "precondition: the path is not ignored"; fi
dang_head="$(git -C "$FX_TMP/dangling" rev-parse HEAD)"
run_update "$FX_TMP/dangling" "a dangling symlink is not clobbered" 1 -- --pull
fx_err 'would overwrite your untracked file'
fx_err 'assets/wallpaper/bg.png'
if [[ -L "$FX_TMP/dangling/assets/wallpaper/bg.png" ]]; then
    fx_ok
else
    fx_bad "the fast-forward replaced the dangling symlink with a regular file"
fi
if [[ "/mnt/not-mounted/bg.png" == "$(readlink "$FX_TMP/dangling/assets/wallpaper/bg.png" 2>/dev/null)" ]]; then
    fx_ok
else
    fx_bad "the symlink target was rewritten"
fi
if [[ "$dang_head" == "$(git -C "$FX_TMP/dangling" rev-parse HEAD)" ]]; then fx_ok; else fx_bad "the merge happened despite the collision"; fi

# ------------------ 12e. the tracked-file test must ask git LITERALLY

# `--` ends option parsing but does NOT disable pathspec magic, so
# `ls-files --error-unmatch -- pkg1?2.deb` is answered by the tracked
# `pkg1x2.deb` and reports "tracked" for a path that is not tracked at all. The
# guard then concludes there is nothing to lose and lets git overwrite the local
# file. `--literal-pathspecs` is a git GLOBAL option -- after the subcommand git
# rejects it with a usage error (rc 129) -- so the fix has to move it in front of
# `ls-files`, which is why this cell pins the behaviour and not just the message.
clone_repo globpath
printf 'TRACKED SIBLING\n' >"$GPUB/pkg1x2.deb"
_git -C "$GPUB" add -f pkg1x2.deb
_git -C "$GPUB" "${GIT_ID[@]}" commit -m "add the tracked sibling"
_git -C "$GPUB" push -q origin main
# the victim must track the sibling BEFORE it holds the untracked glob-mate
clone_repo globpath
printf 'UPSTREAM VERSION\n' >"$GPUB/pkg1?2.deb"
_git -C "$GPUB" add -f 'pkg1?2.deb'
_git -C "$GPUB" "${GIT_ID[@]}" commit -m "add a file whose name is a glob"
_git -C "$GPUB" push -q origin main
printf 'MY LOCAL WORK\n' >"$FX_TMP/globpath/pkg1?2.deb"
if git -C "$FX_TMP/globpath" ls-files --error-unmatch -- 'pkg1x2.deb' >/dev/null 2>&1; then
    fx_ok
else
    fx_bad "precondition: the glob-mate is not tracked, so the pathspec hole cannot open"
fi
if [[ -z "$(git -C "$FX_TMP/globpath" status --porcelain)" ]]; then
    fx_ok
else
    fx_bad "precondition: the local file is visible to status --porcelain"
fi
# check-ignore is ITSELF a pathspec command, so this query needs --no-index: with
# a glob pathspec it matches the tracked `pkg1x2.deb` in the index and reports
# "not ignored", which is how this cell first failed. Neither :(literal) nor
# --literal-pathspecs is usable here -- check-ignore rejects both outright
# ("pathspec magic not supported by this command") -- so --no-index is the only
# correct way to ask about one literal path.
if git -C "$FX_TMP/globpath" check-ignore -q --no-index 'pkg1?2.deb'; then
    fx_ok
else
    fx_bad "precondition: the path is not ignored"
fi
# and the hazard is asserted rather than assumed: the DEFAULT query lies
if git -C "$FX_TMP/globpath" check-ignore -q 'pkg1?2.deb' >/dev/null 2>&1; then
    fx_bad "precondition: a glob pathspec no longer confuses check-ignore, so this cell proves less than it claims"
else
    fx_ok
fi
# the hole itself, asserted on git and not on the tool: the DEFAULT (glob)
# pathspec answers rc 0 for a path that is not tracked
if git -C "$FX_TMP/globpath" ls-files --error-unmatch -- 'pkg1?2.deb' >/dev/null 2>&1; then
    fx_ok
else
    fx_bad "precondition: a glob pathspec no longer matches pkg1x2.deb, so this cell is vacuous"
fi
if git -C "$FX_TMP/globpath" ls-files --literal-pathspecs --error-unmatch -- 'pkg1?2.deb' >/dev/null 2>&1; then
    fx_bad "precondition: --literal-pathspecs after the subcommand was accepted (git should reject it)"
else
    fx_ok
fi
glob_head="$(git -C "$FX_TMP/globpath" rev-parse HEAD)"
run_update "$FX_TMP/globpath" "a glob-named untracked file is not clobbered" 1 -- --pull
fx_err 'would overwrite your untracked file'
fx_err 'pkg1?2.deb'
if [[ "MY LOCAL WORK" == "$(cat "$FX_TMP/globpath/pkg1?2.deb" 2>/dev/null)" ]]; then
    fx_ok
else
    fx_bad "a glob pathspec hid the collision and the local file was destroyed"
fi
if [[ "$glob_head" == "$(git -C "$FX_TMP/globpath" rev-parse HEAD)" ]]; then fx_ok; else fx_bad "the merge happened despite the collision"; fi

# ---------------- 12f. a TRACKED file the fast-forward modifies is not a collision

# The false-refusal direction, asserted with STATE and not with the tool's own
# words. Upstream edits a file that exists locally AND is tracked: nothing is at
# risk, so the pull must succeed and the edit must land. A guard that treats
# "exists on disk" as sufficient -- one that has lost the tracked-file test --
# refuses this perfectly legitimate update.
printf 'tracked\n' >"$GPUB/docs/tracked-target.txt"
_git -C "$GPUB" add -A
_git -C "$GPUB" "${GIT_ID[@]}" commit -m "add a file the victim already tracks"
_git -C "$GPUB" push -q origin main
clone_repo trackedmod
if git -C "$FX_REPO" ls-files --error-unmatch -- docs/tracked-target.txt >/dev/null 2>&1; then
    fx_ok
else
    fx_bad "precondition: docs/tracked-target.txt is not tracked locally"
fi
if [[ -z "$(git -C "$FX_REPO" status --porcelain)" ]]; then
    fx_ok
else
    fx_bad "precondition: the tree should be clean"
fi
mod_head="$(git -C "$FX_REPO" rev-parse HEAD)"
printf 'UPSTREAM EDIT\n' >"$GPUB/docs/tracked-target.txt"
_git -C "$GPUB" add -A
_git -C "$GPUB" "${GIT_ID[@]}" commit -m "modify a tracked file"
_git -C "$GPUB" push -q origin main
run_update "$FX_REPO" "a tracked modification is not a collision" 0 -- --pull
if [[ "$mod_head" != "$(git -C "$FX_REPO" rev-parse HEAD)" ]]; then
    fx_ok
else
    fx_bad "--pull did not move HEAD on a tracked modification"
fi
if grep -q 'UPSTREAM EDIT' "$FX_REPO/docs/tracked-target.txt"; then
    fx_ok
else
    fx_bad "the upstream modification to a tracked file did not land"
fi
if [[ "$(git -C "$FX_REPO" rev-list --count HEAD..'@{u}')" == "0" ]]; then
    fx_ok
else
    fx_bad "after the pull the clone is still behind the remote"
fi

# ------------------------------ 13. --pull is not an environment variable

# The whole point of the flag is that the pull is an explicit act. An inherited
# FS_PULL=1 must be ignored exactly like an inherited FS_MANIFEST is.
clone_repo envpull
publish "upstream five"
env_head="$(git -C "$FX_REPO" rev-parse HEAD)"
run_update "$FX_REPO" "inherited FS_PULL=1 does not pull" 0 FS_PULL=1 --
fx_out 'behind the remote'
if [[ "$env_head" == "$(git -C "$FX_REPO" rev-parse HEAD)" ]]; then
    fx_ok
else
    fx_bad "an inherited FS_PULL=1 moved the working tree"
fi

# ------------------------- 13b. a bogus FS_PULL must fail CLOSED, not open

# The pull gate is the single guard protecting the one mutating operation, and
# what matters about it is its DIRECTION on bad input: anything that is not
# exactly "1" must mean "do not pull". cli.sh is the only writer, so this cannot
# be reached through the launcher and the two values that actually occur would
# never test it -- an `(( 10#$x != 1 ))` guard passes every one of those while
# failing OPEN on `yes`, which is why update_run is called directly here.
# HEAD is the oracle (file presence is useless: this clone already has the
# published file from an earlier publish).
clone_repo boguspull
publish "upstream for the bogus-pull cell"
bogus_head="$(git -C "$FX_REPO" rev-parse HEAD)"
for bogus in "yes" "" "2" "true" "01"; do
    _out="$(
        env -i PATH="/usr/bin:/bin" HOME="$FX_TMP/home" \
            FS_PULL="$bogus" FS_DRY_RUN=0 FS_VERBOSE=0 FS_DEBUG=0 FS_YES=0 \
            bash -c 'source "$1/lib/io.sh"; source "$1/lib/run.sh"; source "$1/lib/update.sh"; update_run "$2"' \
            _ "$ROOT" "$FX_REPO" 2>&1
    )"
    if printf '%s' "$_out" | grep -q 'behind the remote'; then
        fx_ok
    else
        fx_bad "FS_PULL='$_bogus' did not report the remote state: $_out"
    fi
done
if [[ "$bogus_head" == "$(git -C "$FX_REPO" rev-parse HEAD)" ]]; then
    fx_ok
else
    fx_bad "a bogus FS_PULL moved the working tree (the guard failed OPEN)"
fi

# ---------------------------------------- 14. --pull belongs to update only

clone_repo misuse
run_setup "--pull with install" 1 -- install --pull --dry-run --yes --profile minimal
fx_err "only valid with the 'update' command"
run_setup "--pull with check" 1 -- check --pull
fx_err "only valid with the 'update' command"
run_setup "--pull with verify" 1 -- verify --pull
fx_err "only valid with the 'update' command"

# ---------------------- 15. a merge that lies: the postcondition must catch it

clone_repo liar
publish "upstream six"
mkdir -p "$FX_TMP/fakebin"
cat >"$FX_TMP/fakebin/git" <<'FAKE'
#!/usr/bin/env bash
for a in "$@"; do
    if [[ "$a" == "merge" ]]; then
        exit 0
    fi
done
exec "@REAL_GIT@" "$@"
FAKE
sed -i "s#@REAL_GIT@#$REAL_GIT#" "$FX_TMP/fakebin/git"
chmod +x "$FX_TMP/fakebin/git"
liar_head="$(git -C "$FX_REPO" rev-parse HEAD)"
run_update "$FX_REPO" "a git that exits 0 without fast-forwarding" 1 PATH="$FX_TMP/fakebin:/usr/bin:/bin" -- --pull
fx_err 'fast-forward reported success but HEAD is'
if [[ "$liar_head" == "$(git -C "$FX_REPO" rev-parse HEAD)" ]]; then fx_ok; else fx_bad "the fake git moved HEAD after all"; fi

# ------------------------------------------------------ 16. a failing fetch

clone_repo badremote
_git -C "$FX_REPO" remote set-url origin "$FX_TMP/does-not-exist.git"
run_update "$FX_REPO" "an unreachable remote is an error" 1 --
fx_err 'fetch failed'

# ------------------------------------------- 17. `update` creates no state root

# check and verify both promise not to manufacture one; `update` must not either.
clone_repo stateless
state_home="$FX_TMP/u-state"
run_update "$FX_REPO" "no state root is created" 0 HOME="$state_home" --
if [[ -e "$state_home" ]]; then
    fx_bad "update created a state root at $state_home"
else
    fx_ok
fi

# ------------------------------- 17b. a count with a leading zero is not octal

# bash reads a leading-zero literal as OCTAL, so `(( behind == 0 ))` on git's
# "08" is an arithmetic error, not a comparison. `rev-list --count` never emits
# one today, so this cell pins the 10# hardening as a property rather than
# leaving it as an untested precaution: the validator is the only thing between
# git's stdout and (( )), and a tool that reports a number it cannot parse should
# say so rather than fail with a shell error.
clone_repo octal
mkdir -p "$FX_TMP/octalbin"
cat >"$FX_TMP/octalbin/git" <<'FAKE'
#!/usr/bin/env bash
for a in "$@"; do
    if [[ "$a" == rev-list ]]; then
        for b in "$@"; do
            if [[ "$b" == HEAD..* ]]; then
                printf '08\n'
                exit 0
            fi
            if [[ "$b" == *..HEAD ]]; then
                printf '0\n'
                exit 0
            fi
        done
    fi
done
exec "@REAL_GIT@" "$@"
FAKE
sed -i "s#@REAL_GIT@#$REAL_GIT#" "$FX_TMP/octalbin/git"
chmod +x "$FX_TMP/octalbin/git"
run_update "$FX_REPO" "a leading-zero commit count" 0 PATH="$FX_TMP/octalbin:/usr/bin:/bin" --
fx_out '[^0-9]8 commit[(]s[)] behind the remote'
if grep -q 'value too great for base\|arithmetic' "$FX_OUT" "$FX_ERR"; then
    fx_bad "the commit count was read as octal"
else
    fx_ok
fi

# ---------------------------------------------------- 18. no stray arguments

clone_repo strays
run_update "$FX_REPO" "update rejects a stray argument" 1 -- stray
fx_err 'update takes no arguments'

# ---------------------------------------------------- 19. the help text

SETUP="$ROOT/setup"
run_setup "update is in the help text" 0 -- help
fx_out '^  update    '

fx_summary