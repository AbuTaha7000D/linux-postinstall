#!/usr/bin/env bash
# tests/fixtures/lists.sh - P4.3 fixture for the declarative list-file
# parsers (lib/lists.sh). Covers the P4.3 verification bullet: fixture
# lists (comments, dupes, family override) produce the documented merged
# result. No real system state: fixtures live under FX_TMP; parse-only
# (no writes, no sudo, no installs). Usage: bash tests/fixtures/lists.sh

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init
mkdir -p "$FX_TMP/mod/common" "$FX_TMP/mod/fam" "$FX_TMP/mod/archonly" "$FX_TMP/mod/none" \
    "$FX_TMP/mod/commentfam" "$FX_TMP/mod/commentcommon" "$FX_TMP/mod/bothempty"
FX_EXPECT="$FX_TMP/expect"

printf 'P4.3 list-file parsers\n'

printf 'vim\n\n# comment\n  # indented comment\ngit\ncurl\r\nvim\nnvim' \
    >"$FX_TMP/mod/common/packages.list"

printf 'vim\nalpha\nbeta\n' >"$FX_TMP/mod/fam/packages.list"
printf 'beta\nfirefox\ngamma\nfirefox\n' >"$FX_TMP/mod/fam/packages.rpm.list"
printf 'org.bar.app\norg.bar.app\norg.foo.app\n' >"$FX_TMP/mod/fam/flatpaks.list"

printf 'x\ny\n' >"$FX_TMP/mod/archonly/packages.arch.list"

printf 'git # tool\nvim\n' >"$FX_TMP/inline.list"

printf 'vim\ngit\n' >"$FX_TMP/mod/commentfam/packages.list"
printf '# no packages on rpm\n  # still none\n' >"$FX_TMP/mod/commentfam/packages.rpm.list"

printf '# only comments\n' >"$FX_TMP/mod/commentcommon/packages.list"
printf 'x\ny\n' >"$FX_TMP/mod/commentcommon/packages.rpm.list"

touch "$FX_TMP/mod/bothempty/packages.list" "$FX_TMP/mod/bothempty/packages.rpm.list"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/lists.sh"
    list_parse "$FX_TMP/mod/common/packages.list"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "single list parses rc0" 0
printf "vim\ngit\ncurl\nnvim\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "comments/blank/dupe/CRLF/no-eol"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/lists.sh"
    list_packages "$FX_TMP/mod/common" rpm
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "packages without override rc0" 0
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "no-override = common parse"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/lists.sh"
    list_packages "$FX_TMP/mod/fam" rpm
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "family merge rc0" 0
printf "beta\nfirefox\ngamma\nvim\nalpha\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "family-first override precedence"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/lists.sh"
    list_packages "$FX_TMP/mod/fam" deb
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "unoverridden family keeps common rc0" 0
printf "vim\nalpha\nbeta\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "other-family untouched"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/lists.sh"
    list_packages "$FX_TMP/mod/fam" arch
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "arch without override rc0" 0
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "arch = common"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/lists.sh"
    list_flatpaks "$FX_TMP/mod/fam"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "flatpak namespace rc0" 0
printf "org.bar.app\norg.foo.app\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "flatpak dedupe first-seen, separate from packages"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/lists.sh"
    list_packages "$FX_TMP/mod/archonly" arch
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "family-only module on its family rc0" 0
printf "x\ny\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "family-only parse"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/lists.sh"
    list_packages "$FX_TMP/mod/archonly" rpm
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "family-only module on other family rc0" 0
fx_empty "other-family = empty" "$FX_OUT"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/lists.sh"
    list_packages "$FX_TMP/mod/none" rpm
    list_flatpaks "$FX_TMP/mod/none"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "listless module empty rc0" 0
fx_empty "no lists = empty" "$FX_OUT"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/lists.sh"
    list_packages "$FX_TMP/mod/fam" ""
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "empty family = common only rc0" 0
printf "vim\nalpha\nbeta\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "empty-family path"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/lists.sh"
    list_parse "$FX_TMP/inline.list"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "inline comment kept rc0" 0
printf "git # tool\nvim\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "inline comment not stripped (documented)"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/lists.sh"
    list_parse "$FX_TMP/does-not-exist.list"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "parse missing file rejects rc1" 1
fx_err "list file missing or not a regular file"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/lists.sh"
    list_packages "$FX_TMP/mod/commentfam" rpm
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "empty family list over common rc0" 0
printf "vim\ngit\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "comment-only family file = common only, no blank"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/lists.sh"
    list_packages "$FX_TMP/mod/commentcommon" rpm
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "empty common with family list rc0" 0
printf "x\ny\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "comment-only common + family = family only, no blank"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/lists.sh"
    list_packages "$FX_TMP/mod/bothempty" rpm
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "both empty lists rc0" 0
fx_empty "zero-byte both = nothing, no blank" "$FX_OUT"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/lists.sh"
    list_parse
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "parse without arg rejects rc1" 1
fx_err "requires a file path"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/lists.sh"
    list_packages
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "packages without dir rejects rc1" 1
fx_err "requires a module directory"

 (
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/lists.sh"
    list_flatpaks
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "flatpaks without dir rejects rc1" 1
fx_err "requires a module directory"

fx_summary