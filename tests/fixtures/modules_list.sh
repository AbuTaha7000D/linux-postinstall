#!/usr/bin/env bash
# tests/fixtures/modules_list.sh - P4.2 fixture for module validation
# (lib/modules.sh) + the wired `./setup list` command (lib/bootstrap.sh).
# Covers the P4.2 verification bullets: an invalid fixture module yields
# a clear validation error (unknown key / unsupported family for the
# resolved family / MODULE_ID-vs-dirname mismatch / unknown DEPENDS
# referral / duplicate ids at the raw load level), and `./setup list`
# renders id\ttitle\trisk\tdefault\tstatus for a valid fixture set,
# sorted by id, with status from the state registry. Runs WITHOUT sudo
# or real system state: FS_MODULES_DIR (module-dir override seam) +
# FS_HOME (state root) + FS_DISTRO_FAMILY (family) + fake package lists.
# Usage: bash tests/fixtures/modules_list.sh  (exit 0 on success)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/fixtures/lib.sh"
fx_init
mkdir -p "$FX_TMP/mods/alpha" "$FX_TMP/mods/beta" "$FX_TMP/mods/hooksonly" \
    "$FX_TMP/mods/badkey" "$FX_TMP/mods/archonly" "$FX_TMP/mods/renamed" \
    "$FX_TMP/mods/gamma" "$FX_TMP/mods/dup1" "$FX_TMP/mods/dup2" \
    "$FX_TMP/mods/destruct" "$FX_TMP/mods/multi" "$FX_TMP/mods/upper" \
    "$FX_TMP/mods/norisk" "$FX_TMP/mods/defaultyes" "$FX_TMP/mods/badtab" \
    "$FX_TMP/mods/aaa" "$FX_TMP/mods/bbb" "$FX_TMP/mods/ccc" "$FX_TMP/mods/zzz" \
    "$FX_TMP/validset" "$FX_TMP/invalidset" "$FX_TMP/graphset" "$FX_TMP/empty"
FX_EXPECT="$FX_TMP/expect"
FX_HOME_T="$FX_TMP/home"

printf 'P4.2 module validation + setup list\n'

cat >"$FX_TMP/mods/alpha/module.sh" <<'EOF'
MODULE_ID=alpha
MODULE_TITLE=Alpha Module
MODULE_DESCRIPTION=First module
MODULE_RISK=low
MODULE_DEFAULT=on
MODULE_DEPENDS=beta
EOF
touch "$FX_TMP/mods/alpha/packages.list"

cat >"$FX_TMP/mods/beta/module.sh" <<'EOF'
MODULE_ID=beta
MODULE_TITLE=Beta Module
MODULE_DESCRIPTION=Second module
MODULE_RISK=none
MODULE_DEFAULT=off
EOF
touch "$FX_TMP/mods/beta/flatpaks.list"

cat >"$FX_TMP/mods/hooksonly/module.sh" <<'EOF'
MODULE_ID=hooksonly
MODULE_TITLE=Hooks Only
MODULE_RISK=low
MODULE_DEFAULT=off
EOF

cat >"$FX_TMP/mods/badkey/module.sh" <<'EOF'
MODULE_ID=badkey
MODULE_TITLE=Bad Key
MODULE_RISK=low
MODULE_DEFAULT=off
MODULE_BOGUS=1
EOF

cat >"$FX_TMP/mods/archonly/module.sh" <<'EOF'
MODULE_ID=archonly
MODULE_TITLE=Arch Only
MODULE_RISK=low
MODULE_DEFAULT=off
EOF
touch "$FX_TMP/mods/archonly/packages.arch.list"

cat >"$FX_TMP/mods/renamed/module.sh" <<'EOF'
MODULE_ID=original
MODULE_TITLE=Renamed Dir
MODULE_RISK=low
MODULE_DEFAULT=off
EOF

cat >"$FX_TMP/mods/gamma/module.sh" <<'EOF'
MODULE_ID=gamma
MODULE_TITLE=Ghost Dep
MODULE_RISK=low
MODULE_DEFAULT=off
MODULE_DEPENDS=ghost
EOF

cat >"$FX_TMP/mods/dup1/module.sh" <<'EOF'
MODULE_ID=double
MODULE_TITLE=Dup One
MODULE_RISK=none
MODULE_DEFAULT=off
EOF

cat >"$FX_TMP/mods/dup2/module.sh" <<'EOF'
MODULE_ID=double
MODULE_TITLE=Dup Two
MODULE_RISK=none
MODULE_DEFAULT=off
EOF

cat >"$FX_TMP/mods/destruct/module.sh" <<'EOF'
MODULE_ID=destruct
MODULE_TITLE=Destructive Risk
MODULE_RISK=destructive
MODULE_DEFAULT=on
EOF

cat >"$FX_TMP/mods/multi/module.sh" <<'EOF'
MODULE_ID=multi
MODULE_TITLE=Multi Risk
MODULE_RISK=low medium
MODULE_DEFAULT=off
MODULE_DEPENDS=ghost
EOF

cat >"$FX_TMP/mods/upper/module.sh" <<'EOF'
MODULE_ID=upper
MODULE_TITLE=Upper Risk
MODULE_RISK=HIGH
MODULE_DEFAULT=off
MODULE_DEPENDS=ghost
EOF

cat >"$FX_TMP/mods/norisk/module.sh" <<'EOF'
MODULE_ID=norisk
MODULE_TITLE=No Risk
MODULE_RISK=
MODULE_DEFAULT=off
MODULE_DEPENDS=ghost
EOF

cat >"$FX_TMP/mods/defaultyes/module.sh" <<'EOF'
MODULE_ID=defaultyes
MODULE_TITLE=Bad Default
MODULE_RISK=low
MODULE_DEFAULT=yes
MODULE_DEPENDS=ghost
EOF

cat >"$FX_TMP/mods/badtab/module.sh" <<'EOF'
MODULE_ID=badtab
MODULE_TITLE=Bad	Title
MODULE_RISK=low
MODULE_DEFAULT=off
MODULE_DEPENDS=ghost
EOF

cat >"$FX_TMP/mods/aaa/module.sh" <<'EOF'
MODULE_ID=aaa
MODULE_TITLE=AAA
MODULE_RISK=none
MODULE_DEFAULT=off
EOF

cat >"$FX_TMP/mods/bbb/module.sh" <<'EOF'
MODULE_ID=bbb
MODULE_TITLE=BBB
MODULE_RISK=none
MODULE_DEFAULT=off
EOF

cat >"$FX_TMP/mods/ccc/module.sh" <<'EOF'
MODULE_ID=ccc
MODULE_TITLE=CCC
MODULE_RISK=none
MODULE_DEFAULT=off
EOF

cat >"$FX_TMP/mods/zzz/module.sh" <<'EOF'
MODULE_ID=zzz
MODULE_TITLE=ZZZ
MODULE_RISK=none
MODULE_DEFAULT=off
MODULE_DEPENDS=aaa
EOF

cp -r "$FX_TMP/mods/alpha" "$FX_TMP/mods/beta" "$FX_TMP/mods/hooksonly" "$FX_TMP/validset/"
cp -r "$FX_TMP/mods/alpha" "$FX_TMP/mods/badkey" "$FX_TMP/mods/archonly" \
    "$FX_TMP/mods/renamed" "$FX_TMP/invalidset/"
cp -r "$FX_TMP/mods/alpha" "$FX_TMP/mods/beta" "$FX_TMP/mods/gamma" "$FX_TMP/graphset/"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    module_validate "$FX_TMP/mods/alpha" rpm
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "validate good module rc0" 0
fx_empty "good module silent" "$FX_OUT"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    module_validate "$FX_TMP/mods/badkey" rpm
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "validate unknown-key module rejects rc1" 1
fx_err "unknown metadata key"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    module_validate "$FX_TMP/mods/archonly" rpm
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "validate wrong-family module rejects rc1" 1
fx_err "no package list usable on family 'rpm'"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    module_validate "$FX_TMP/mods/archonly" arch
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "validate matching-family module rc0" 0

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    module_validate "$FX_TMP/mods/renamed" rpm
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "validate id/dirname mismatch rejects rc1" 1
fx_err "does not match directory name"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    module_validate "$FX_TMP/mods/hooksonly" rpm
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "validate hooks-only module rc0" 0

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    module_validate "$FX_TMP/mods/destruct" rpm
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "validate destructive-risk module rc0" 0

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    module_validate "$FX_TMP/mods/multi" rpm
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "validate compound risk value rejects rc1" 1
fx_err "invalid MODULE_RISK 'low medium'"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    module_validate "$FX_TMP/mods/upper" rpm
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "validate non-lowercase risk rejects rc1" 1
fx_err "invalid MODULE_RISK 'HIGH'"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    module_validate "$FX_TMP/mods/norisk" rpm
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "validate empty risk rejects rc1" 1
fx_err "invalid MODULE_RISK ''"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    module_validate "$FX_TMP/mods/defaultyes" rpm
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "validate non-on/off default rejects rc1" 1
fx_err "invalid MODULE_DEFAULT 'yes'"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    module_validate "$FX_TMP/mods/badtab" rpm
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "validate tab in title rejects rc1" 1
fx_err "must not contain control characters"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    module_validate_set "$FX_TMP/mods/aaa" "$FX_TMP/mods/bbb" "$FX_TMP/mods/ccc" "$FX_TMP/mods/zzz"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "validate_set dep matching first sorted id rc0" 0

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    module_validate_set "$FX_TMP/mods/alpha" "$FX_TMP/mods/beta"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "validate_set good graph rc0" 0

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    module_validate_set "$FX_TMP/mods/alpha" "$FX_TMP/mods/beta" "$FX_TMP/mods/gamma"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "validate_set unknown dep rejects rc1" 1
fx_err "gamma depends on unknown module 'ghost'"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    module_validate_set "$FX_TMP/mods/dup1" "$FX_TMP/mods/dup2"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "validate_set duplicate ids rejects rc1" 1
fx_err "duplicate module id 'double'"

(
    set -euo pipefail
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/modules.sh"
    module_depends "$FX_TMP/mods/alpha"
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "module_depends prints referrals" 0
printf "beta\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "depends content"

(
    set -euo pipefail
    export FS_HOME="$FX_HOME_T"
    source "$ROOT/lib/io.sh"
    source "$ROOT/lib/state.sh"
    state_init
    state_module_mark alpha
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "state pre-mark alpha rc0" 0

(
    set -euo pipefail
    cd "$ROOT"
    export FS_MODULES_DIR="$FX_TMP/validset" FS_HOME="$FX_HOME_T" FS_DISTRO_FAMILY=rpm
    "$ROOT/setup" list
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "setup list valid set rc0" 0
printf "alpha\tAlpha Module\tlow\ton\tdone\nbeta\tBeta Module\tnone\toff\t-\nhooksonly\tHooks Only\tlow\toff\t-\n" >"$FX_EXPECT"
cmp "$FX_EXPECT" "$FX_OUT" >/dev/null 2>&1 && fx_ok || fx_bad "list table exact (sorted, status from registry)"

(
    set -euo pipefail
    cd "$ROOT"
    export FS_MODULES_DIR="$FX_TMP/invalidset" FS_HOME="$FX_HOME_T" FS_DISTRO_FAMILY=rpm
    "$ROOT/setup" list
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "setup list invalid set rejects rc1" 1
fx_empty "no partial table on invalid set" "$FX_OUT"
fx_err "unknown metadata key"
fx_err "no package list usable on family 'rpm'"
fx_err "does not match directory name"

(
    set -euo pipefail
    cd "$ROOT"
    export FS_MODULES_DIR="$FX_TMP/graphset" FS_HOME="$FX_HOME_T" FS_DISTRO_FAMILY=rpm
    "$ROOT/setup" list
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "setup list invalid graph rejects rc1" 1
fx_empty "no partial table on invalid graph" "$FX_OUT"
fx_err "gamma depends on unknown module 'ghost'"

(
    set -euo pipefail
    cd "$ROOT"
    export FS_MODULES_DIR="$FX_TMP/empty" FS_HOME="$FX_HOME_T" FS_DISTRO_FAMILY=rpm
    "$ROOT/setup" list
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "setup list empty module set rc0" 0
fx_empty "empty set prints nothing" "$FX_OUT"

(
    set -euo pipefail
    cd "$ROOT"
    export FS_MODULES_DIR="$FX_TMP/does-not-exist" FS_HOME="$FX_HOME_T" FS_DISTRO_FAMILY=rpm
    "$ROOT/setup" list
) >"$FX_OUT" 2>"$FX_ERR"
FX_BLOCK_RC=$?
fx_block_rc "setup list missing module dir rejects rc1" 1
fx_err "modules directory not found"

fx_summary