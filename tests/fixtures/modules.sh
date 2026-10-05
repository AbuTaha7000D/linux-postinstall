#!/usr/bin/env bash
# tests/fixtures/modules.sh - P4.1 fixture for lib/modules.sh (module
# contract + loader). Covers the P4.1 verification bullets directly: a
# minimal module dir parses, unknown metadata keys warn (and the load
# still succeeds), missing module dirs error, declared list-file naming
# is reported, hooks presence is discoverable without execution. Also
# proves textual (NOT sourced) parsing: module.sh contents are inert data
# that never execute in the loader; quote stripping; comment/blank
# tolerance; global reset between loads; MODULE_ID required + validated.
# Usage: bash tests/fixtures/modules.sh  (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init
mkdir -p "$FX_TMP/mods/hello" "$FX_TMP/mods/bare" "$FX_TMP/mods/warned" \
    "$FX_TMP/mods/withlists" "$FX_TMP/mods/hooked" "$FX_TMP/mods/noid" \
    "$FX_TMP/mods/badid" "$FX_TMP/mods/quoted" "$FX_TMP/mods/spaced"
FX_EXPECT="$FX_TMP/expect"

printf 'P4.1 module contract + loader\n'

cat >"$FX_TMP/mods/hello/module.sh" <<'EOF'
# hello module
MODULE_ID=hello
MODULE_TITLE="Hello Module"
MODULE_DESCRIPTION=A demo module
MODULE_RISK=low
MODULE_DEFAULT=on
MODULE_DEPENDS=core git
EOF

cat >"$FX_TMP/mods/bare/module.sh" <<'EOF'
MODULE_ID=bare
MODULE_TITLE=Bare
EOF

cat >"$FX_TMP/mods/warned/module.sh" <<'EOF'
MODULE_ID=warned
MODULE_TITLE=Still Loads
MODULE_BOGUS=1
_TOUCH_HIDDEN=2
EOF

cat >"$FX_TMP/mods/noid/module.sh" <<'EOF'
MODULE_TITLE=No Id
EOF

cat >"$FX_TMP/mods/badid/module.sh" <<'EOF'
MODULE_ID=bad id
MODULE_TITLE=Bad Id
EOF

cat >"$FX_TMP/mods/quoted/module.sh" <<'EOF'
MODULE_ID=quoted
MODULE_TITLE='Single Quoted'
MODULE_DESCRIPTION="Double Quoted"
EOF

cat >"$FX_TMP/mods/spaced/module.sh" <<'EOF'

   # a comment line

   MODULE_TITLE   =   spaced value   
MODULE_ID=spaced
EOF

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    module_load "$FX_TMP/mods/hello"
    printf '%s|%s|%s|%s|%s|%s\n' "$MODULE_ID" "$MODULE_TITLE" \
        "$MODULE_DESCRIPTION" "$MODULE_RISK" "$MODULE_DEFAULT" "$MODULE_DEPENDS"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "minimal module parses" 0
printf "hello|Hello Module|A demo module|low|on|core git\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "metadata captured exactly"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    module_load "$FX_TMP/mods/hello"
    module_load "$FX_TMP/mods/bare"
    printf '<%s><%s><%s><%s><%s>\n' "$MODULE_TITLE" "$MODULE_RISK" \
        "$MODULE_DEFAULT" "$MODULE_DESCRIPTION" "$MODULE_DEPENDS"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "bare module defaults rc0" 0
printf "<Bare><none><off><><>\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "defaults + cross-load reset"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    module_load "$FX_TMP/mods/warned"
    printf '%s|%s\n' "$MODULE_ID" "$MODULE_TITLE"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "unknown key warns, load succeeds" 0
fx_err "unknown metadata key"
fx_err "MODULE_BOGUS"
printf "warned|Still Loads\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "post-warning metadata intact"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    module_load "$FX_TMP/mods/does-not-exist"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "missing module dir errors" 1
fx_err "module directory not found"

(
    set -euo pipefail
    mkdir -p "$FX_TMP/mods/nometa"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    module_load "$FX_TMP/mods/nometa"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "missing module.sh errors" 1
fx_err "module metadata missing"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    module_load "$FX_TMP/mods/noid"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "missing MODULE_ID errors" 1
fx_err "module metadata missing MODULE_ID"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    module_load "$FX_TMP/mods/badid"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "invalid MODULE_ID errors" 1
fx_err "invalid MODULE_ID"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    module_load "$FX_TMP/mods/quoted"
    printf '%s|%s\n' "$MODULE_TITLE" "$MODULE_DESCRIPTION"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "quoted values parse" 0
printf "Single Quoted|Double Quoted\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "quotes stripped from values"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    module_load "$FX_TMP/mods/spaced"
    printf '%s\n' "$MODULE_TITLE"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "whitespace/comment tolerant" 0
printf "spaced value\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "surrounding whitespace trimmed"

touch "$FX_TMP/mods/withlists/packages.list" \
    "$FX_TMP/mods/withlists/packages.rpm.list" \
    "$FX_TMP/mods/withlists/packages.deb.list" \
    "$FX_TMP/mods/withlists/packages.arch.list" \
    "$FX_TMP/mods/withlists/flatpaks.list"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    module_list_files "$FX_TMP/mods/withlists"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "list-file naming rc0 (all 5 present)" 0
printf "packages.list\npackages.rpm.list\npackages.deb.list\npackages.arch.list\nflatpaks.list\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "declared list files reported in MODULE_LIST_NAMES order"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    module_list_files "$FX_TMP/mods/bare"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "no list files -> empty rc0" 0
fx_empty "list-less module reports nothing" "$FX_OUT"

cat >"$FX_TMP/mods/hooked/hooks.sh" <<'EOF'
#!/usr/bin/env bash
run() { :; }
verify() { :; }
touch "$FX_TMP/HOOK_RAN"
EOF
printf 'MODULE_ID=hooked\nMODULE_TITLE=Hooked\n' >"$FX_TMP/mods/hooked/module.sh"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    module_has_hooks "$FX_TMP/mods/hooked"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "hooks present rc0" 0

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    module_has_hooks "$FX_TMP/mods/bare"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "hooks absent rc1" 1

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    module_has_hooks "$FX_TMP/mods/does-not-exist"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "hooks on missing dir errors" 1

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    module_load "$FX_TMP/mods/hooked"
    if declare -f run >/dev/null 2>&1; then
        printf 'leaked-run\n'
    fi
    if declare -f verify >/dev/null 2>&1; then
        printf 'leaked-verify\n'
    fi
    if [[ -e "$FX_TMP/HOOK_RAN" ]]; then
        printf 'hooks-executed\n'
    fi
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "loader never sources hooks" 0
fx_out_not "leaked-run"
fx_out_not "leaked-verify"
fx_out_not "hooks-executed"

# --- A1: the reserved not-applicable status the module contract defines ----
echo "--- cell: MODULE_HOOK_SKIP is the reserved 92"
(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    printf '%s\n' "$MODULE_HOOK_SKIP"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "contract constant readable" 0
printf '92\n' >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "MODULE_HOOK_SKIP must be 92"

# It must not collide with lib/verify.sh's own reserved signals: a run() and a
# verify() are different functions in the same hooks.sh, and one contract's
# vocabulary must never be readable as the other's.
(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/verify.sh"
    source "$ROOT/lib/modules.sh"
    printf '%s|%s|%s\n' "$_VERIFY_HOOK_NONE" "$_VERIFY_HOOK_UNDEFINED" "$MODULE_HOOK_SKIP"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "verify signals readable" 0
printf '90|91|92\n' >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "reserved statuses must stay distinct (90/91/92)"

true
fx_summary