#!/usr/bin/env bash
# lib/runner.sh - module runner (P4.6).
# Depends, in source order, on: lib/io.sh, lib/run.sh (dry rendering +
# audit), lib/planner.sh and the pkg layer (plan_install dispatch), then
# lib/state.sh (module registry), lib/lists.sh, lib/modules.sh,
# lib/depgraph.sh, lib/profiles.sh (resolver), and lib/summary.sh (P9.5
# reporter, which owns the printed counts AND the exit code). runner_run
# calls state_init itself only in real mode, when the registry must be read
# or written.
# Dry-run (FS_DRY_RUN=1) touches nothing: no state_init, no registry
# reads/writes, no pkg probes; the skip state is not consulted, so a
# resumed run renders as a full run. Bash >= 4.3 safe (no namerefs;
# empty-array expansions guarded; assoc writes only, no iteration). Never
# touches /etc/sudoers; audit trail flows through run_cmd/run_sudo hooks
# and the pkg layer's operations (FS_LOG_FILE).
#
# runner_run <modules_dir> <profiles_dir> <name> <family> [module...]
#                       end-to-end bootstrap of one profile, in six
#                       stages:
#                         1. RESOLVE -- profile_resolve (P4.5) folds the
#                            profile plus any CLI module ids and closes
#                            over MODULE_DEPENDS, so the module set is
#                            deps-closed and deps-first (P4.4); errors
#                            here (bad ids, missing module, cycle) abort
#                            with rc1 before any side effect.
#                         2. PLAN -- for every selected module id
#                            MODULE_DIR/id is module_validate'd against
#                            <family> (the P4.2 list-usability gate: e.g.
#                            on rpm a module must declare packages.list,
#                            packages.rpm.list, or flatpaks.list), and its
#                            packages.list + packages.<family>.list
#                            entries (P4.3) go into the SYSTEM id set and
#                            flatpaks.list entries into the FLATPAK id
#                            set -- two namespaces, never one merged set.
#                            A module that declares the P7.5
#                            flatpak-alternative pair contributes ONLY
#                            its MODULE_FLATPAK_ALT_ID to the FLATPAK set
#                            and NOTHING to the SYSTEM set when its seam
#                            variable is truthy (module_flatpak_alt), so
#                            the alternative can never install alongside
#                            the native path: the module's SYSTEM list
#                            files are not even read, so a stale package
#                            id there can never reach a batch. The skip is
#                            scoped to the SYSTEM namespace -- the
#                            module's own flatpaks.list is still read, and
#                            is additive to whichever alternative it
#                            declares. A io_info "module: <id>
#                            (<risk>)" line is printed per module; risks
#                            are remembered for the failure policy.
#                         3. PREREQ (P7.5) -- per module, in the resolved
#                            deps-first order, prerepo.sh (if present) is
#                            sourced INSIDE a subshell and prerepo() is
#                            called once. This is the only hook that runs
#                            BEFORE the batch, so a module can add the
#                            repository its own packages.*.list entries
#                            resolve from; the subshell sandbox mirrors
#                            hooks.sh/run(), and both hook subshells are
#                            given FS_MODULE_FAMILY=<family> so a hook
#                            never re-detects the distro. BOTH hook
#                            subshells call `module_load <dir> strict`
#                            BEFORE sourcing the hook file, so a hook always
#                            sees its OWN module's metadata: without it the
#                            globals would still hold whatever the PLAN
#                            stage loaded last, and a prerepo() that asks
#                            `module_flatpak_alt` would silently answer for
#                            a different module. Unlike the hooks
#                            stage, prerepo() is NOT skipped for an
#                            already-completed module and the registry is
#                            not consulted at all: its contract is
#                            idempotent-and-always-run (the P3 add_repo
#                            primitives are --if-not-exists), which also
#                            self-heals a repository file that was removed
#                            after the module was marked done. Dry-run
#                            DOES call prerepo -- the hook renders its own
#                            steps -- so a dry run shows the repository
#                            work in the same place a real run does it.
#                            BOTH hook subshells are the CONDITION of an
#                            `if`, which SUSPENDS errexit inside them, so
#                            a hook must not lean on a bare `set -e` to
#                            stop itself: it has to guard the steps it
#                            cares about with `|| return 1`. That is not
#                            new to prerepo -- the hooks.sh stage has
#                            always behaved this way -- it is just written
#                            down now that a hook is allowed to refuse the
#                            whole run.
#                            A prerepo failure stops the run immediately
#                            ("module prerepo failed: <id>", rc1, no
#                            batch, no hooks, no summary) whatever the
#                            module's risk: the batch it precedes may
#                            depend on the repository the hook
#                            establishes, so a safe-continue would only
#                            cascade into a confusing "package batch
#                            failed". That includes a prerepo.sh that
#                            never defines prerepo(): it counts as a
#                            prerepo failure, NOT as the skippable
#                            per-module failure a missing run() is,
#                            because nothing has been installed when it
#                            is detected -- stopping there costs no work
#                            and no state, while continuing would install
#                            that module's packages anyway.
#                         4. BATCH -- plan_install (P3.8) is called at
#                            most ONCE PER NAMESPACE, not once for the
#                            whole run (P5.7 NB-A corrective fix): the
#                            SYSTEM set goes through the active family
#                            backend as before (dedupe -> diff against
#                            the system installed state -> single
#                            pkg_install_batch), while the FLATPAK set is
#                            routed to the flatpak backend in a subshell
#                            (FS_PKG_BACKEND=flatpak, self-restoring:
#                            _pkg_load re-selects on the name change, the
#                            caller's env is untouched). "packages batched
#                            once" therefore holds per backend. System
#                            runs BEFORE flatpak so a module such as core
#                            can install the flatpak CLI first. Note: the
#                            flatpak namespace gates on the flatpak
#                            backend's own flatpak_supported check (a
#                            bare `command -v flatpak`) even in dry-run,
#                            so a dry-run of a flatpak-bearing selection
#                            fails rc1 on a host without the flatpak
#                            binary in PATH. A failing
#                            system transaction aborts (`package batch
#                            failed`, rc1, no hooks run); a failing
#                            flatpak transaction aborts (`flatpak batch
#                            failed`, rc1, no hooks run, after the system
#                            batch committed). An empty namespace makes no
#                            call at all.
#                         5. HOOKS + STATE -- per module, in the resolved
#                            deps-first order: already-completed modules
#                            (state_module_check, real mode only) print
#                            "already completed: <id>" and are skipped for
#                            hook execution and marking; otherwise
#                            hooks.sh (if present) is sourced INSIDE a
#                            subshell and run() is called once (P4.1
#                            sandbox -- the module's hooks.sh never runs
#                            in the runner's own shell; a hooks.sh that
#                            does not define run() fails the module).
#                            Hook failures are logged ("module failed:
#                            <id>") and by default the run CONTINUES with
#                            the next module (safe-continue); a module
#                            whose MODULE_RISK is destructive instead
#                            stops the run immediately ("stopping run
#                            (destructive module <id>)", rc1, remaining
#                            modules not started, no end-of-run summary).
#                            On hook success the module is marked done in
#                            the registry (state_module_mark, real mode
#                            only; dry-run counts ok but writes nothing).
#                         6. SUMMARY (P9.5) -- every module outcome is
#                            RECORDED with lib/summary.sh
#                            (summary_module_ok/_skip/_fail) as it happens,
#                            and the end of the run hands the whole record to
#                            ONE reporter for both the printed line and the
#                            exit code (summary_report + summary_rc). The
#                            runner therefore keeps NO counter of its own: the
#                            "N ok / M skipped / K failed" it prints and the
#                            rc it returns are both derived from the same
#                            records, so they cannot disagree. rc0 iff no
#                            module failed; rc1 if any did. The abort paths
#                            above (prereq, batch, destructive stop) return
#                            rc1 WITHOUT a summary and never reach the
#                            reporter -- a reviewed P4.6/P7.5/P8.3 contract,
#                            and the reason is in lib/summary.sh: a run that
#                            never reached the module loop has no outcomes to
#                            report, and "0 ok . 0 failed" would read as
#                            success.
#                            State-mark failures abort rc1 fail-closed: the
#                            registry is authoritative, so a module that
#                            cannot be recorded stops the run without a
#                            summary (the batch has already committed).
#                       5b. NOT-APPLICABLE (A1). A hook whose run() returns
#                            the reserved MODULE_HOOK_SKIP status reports
#                            "nothing to do on this host", not success and
#                            not failure. The runner records the registry's
#                            `skipped` state (state_module_skip) and
#                            summary_module_skip, so the module is retried on
#                            the next run. It is NOT marked done: that is
#                            exactly the latch A1 removes, where a GNOME
#                            module gated off on a headless host was recorded
#                            complete and never retried. A skip is not a
#                            failure -- it never changes summary_rc -- and it
#                            never counts as ok. Every OTHER non-zero run()
#                            status is still a failure, including a
#                            destructive module's (which stops the run).
#                            Dry-run writes nothing, exactly as for `done`.
#                       <family> is the distro family (rpm|deb|arch) for
#                       the P4.3 overlay + P4.2 gate; distro detection is
#                       the caller/bootstrap's job (P2.3) -- the runner
#                       never reads /etc/os-release. The runner only
#                       constrains list usability per family; it does NOT
#                       validate that <family> itself is a known token --
#                       bootstrap/P4.7 owns the distro-level family gate.
#                       Hooks must perform
#                       side effects through run_cmd/run_sudo so dry-run
#                       stays side-effect-free; raw shell writes in a hook
#                       execute even under dry-run (module author error).
#                       Privileged hooks need no sudo bookkeeping of their
#                       own: the runner runs sudo_detect + sudo_refresh
#                       itself (PRIVILEGE STAGE below) whenever the resolved
#                       plan can escalate, so run_sudo already has policy.
#                       A hook must still escalate through run_sudo rather
#                       than a raw `sudo`, or it loses the fail-closed and
#                       audit-trail guarantees.
#                       Resolve/validate/plan errors print only io_error
#                       lines and return rc1 -- no writes, no state.
#
# PRIVILEGE STAGE (C1). Between the dry-run alert and the PREREQ stage the
# runner decides ONCE whether this run can escalate, and only then calls
# sudo_detect + sudo_refresh (lib/sudo.sh). Two inputs, both read from the
# plan this function has ALREADY resolved -- there is no second plan and no
# static analysis of module sources: (1) the SYSTEM namespace is the very
# `pkgs` array the batch below consumes (lib/pkg/flatpak.sh never
# escalates), and (2) a resolved module's own MODULE_PRIVILEGED=1
# declaration, which is how a hooks.sh/prerepo.sh says it needs privilege.
# So need_priv==0 implies the run provably cannot escalate, and skipping
# the refresh is then not a weaker guarantee but the correct one: a
# flatpak-only selection, or a hooks-only selection like gnome-base whose
# hooks touch only the user session, completes rc0 on a password-sudo host
# instead of aborting with "privileged steps cannot run" for a run that
# executes nothing privileged.
# The module-side input is DECLARATIVE, not inferred from the presence of
# hooks.sh/prerepo.sh. That inference was the first C1 revision's blocking
# defect: most shipped hooks do not escalate (apps, git, gnome-base,
# gnome-theme, terminal), so their privilege-free installs demanded a
# credential and failed when `sudo -v` could not succeed. A file's
# existence says nothing about what its run() does; only the module
# author knows that. See lib/modules.sh for the field and its validation.
# The decision deliberately stays HERE, in one place, rather than lazily at
# first escalation: run_sudo is a keep-going seam (run_cmd returns 0 for a
# failed command unless --stop), so a lazy refresh failure could be swallowed
# at a call site that lacks --stop and the run would continue past a
# credential it never obtained. One decision point makes fail-closed
# structural instead of per-call-site. It sits after resolve/validate and the
# RISK GATE, so a run refused for planning reasons never prompts, and before
# PREREQ/BATCH/hooks, so a failing refresh aborts before any mutation.
#
# RISK GATE (P8.3). The curated set is what a human actually asked for: the
# module args bootstrap passed (post-UI selection), or -- when it passed
# none -- the profile FILE's own ids via profile_load. The resolved set is
# that plus everything MODULE_DEPENDS drags in transitively. Any high/
# destructive module in the resolved set but NOT in the curated set is
# refused rc1 before any batch, prerepo, or hook: a single MODULE_DEPENDS
# line must never be able to put a destructive module on a system nobody
# named. This is a real P8.3 finding -- bootstrap's pre-seed filter
# (lib/bootstrap.sh) only walks the curated list, so before this gate a dep
# edge pulled `locale` into `--yes --profile minimal` and installed it with
# no consent at all. A module that WAS curated is a different case: the
# pre-seed filter drops it from the checklist with a loud io_alert and the
# run continues rc0 (the reviewed P4.7 contract), so the gate deliberately
# does not touch that path. The check runs after the plan loop because
# module_validate is what classifies risk, and planning is pure metadata
# reading -- no writes, no state, nothing privileged -- so rc1 here is as
# side-effect-free as a resolve error.
#
# A high/destructive module in a DRY RUN additionally prints a bold io_alert
# line, after the gate above so a refused module is never announced as
# something that would have happened.

runner_run() {
    local modules_dir="${1:-}" profiles_dir="${2:-}" name="${3:-}" family="${4:-}"
    shift 4 2>/dev/null || {
        io_error "runner_run requires a modules dir, a profiles dir, a name, and a family"
        return 1
    }
    if [[ -z "$modules_dir" || -z "$profiles_dir" || -z "$name" || -z "$family" ]]; then
        io_error "runner_run requires a modules dir, a profiles dir, a name, and a family"
        return 1
    fi
    io_info "profile: $name"
    summary_reset
    local resolved=""
    resolved="$(profile_resolve "$modules_dir" "$profiles_dir" "$name" "$@")" || return 1
    local -a ids=()
    if [[ -n "$resolved" ]]; then
        local id=""
        while IFS= read -r id; do
            ids+=("$id")
        done <<<"$resolved"
    fi
    local -A risks=()
    local -A curated=()
    local -a cids=()
    local -a pkgs=() apps=()
    if (($# > 0)); then
        cids=("$@")
    else
        cids=()
        while IFS= read -r id; do
            [[ -n "$id" ]] && cids+=("$id")
        done < <(profile_load "$profiles_dir" "$name") || return 1
    fi
    local cid=""
    for cid in ${cids[@]+"${cids[@]}"}; do
        curated[$cid]=1
    done
    local -a pulled=()
    local sid="" pid="" dir="" out="" p="" alt="" priv=""
    local need_priv=0
    for sid in ${ids[@]+"${ids[@]}"}; do
        dir="$modules_dir/$sid"
        module_validate "$dir" "$family" || return 1
        risks[$sid]="$MODULE_RISK"
        priv="$MODULE_PRIVILEGED"
        io_info "module: $sid (${risks[$sid]})"
        if [[ "$priv" == "1" ]]; then
            need_priv=1
        fi
        case "${risks[$sid]}" in
        high | destructive)
            [[ -n "${curated[$sid]:-}" ]] || pulled+=("$sid")
            ;;
        esac
        alt="$(module_flatpak_alt)" || return 1
        if [[ -n "$alt" ]]; then
            apps+=("$alt")
        else
            out="$(list_packages "$dir" "$family")" || return 1
            if [[ -n "$out" ]]; then
                while IFS= read -r p; do
                    pkgs+=("$p")
                done <<<"$out"
            fi
        fi
        out="$(list_flatpaks "$dir")" || return 1
        if [[ -n "$out" ]]; then
            while IFS= read -r p; do
                apps+=("$p")
            done <<<"$out"
        fi
    done
    if ((${#pulled[@]} > 0)); then
        ptxt=""
        for pid in ${pulled[@]+"${pulled[@]}"}; do
            ptxt="$ptxt $pid"
        done
        io_error "high-risk module(s) pulled in transitively by a dependency:$ptxt"
        io_error "name them on the command line to run them, or drop the dependency"
        return 1
    fi
    if ((FS_DRY_RUN == 1)); then
        for sid in ${ids[@]+"${ids[@]}"}; do
            case "${risks[$sid]}" in
            high | destructive)
                io_alert "dry run: $sid is ${risks[$sid]}; a real run would change this system"
                ;;
            esac
        done
    fi
    if ((need_priv == 0)) && ((${#pkgs[@]} > 0)); then
        need_priv=1
    fi
    if ((need_priv > 0)) && [[ "${FS_PKG_BACKEND:-}" != mock ]]; then
        if ! declare -F sudo_detect >/dev/null 2>&1; then
            io_error "sudo policy is not loaded; refusing privileged work"
            return 1
        fi
        sudo_detect
        if ! sudo_refresh; then
            return 1
        fi
    fi
    for sid in ${ids[@]+"${ids[@]}"}; do
        dir="$modules_dir/$sid"
        if module_has_prerepo "$dir"; then
            if ! (
                FS_MODULE_FAMILY="$family"
                export FS_MODULE_FAMILY
                module_load "$dir" strict || exit 1
                source "$dir/prerepo.sh"
                prerepo
            ); then
                io_error "module prerepo failed: $sid"
                io_error "stopping run (prerepo failed for $sid)"
                return 1
            fi
        fi
    done
    if ((${#pkgs[@]} > 0)); then
        plan_install "${pkgs[@]}" || {
            io_error "package batch failed"
            return 1
        }
    fi
    if ((${#apps[@]} > 0)); then
        (
            FS_PKG_BACKEND=flatpak
            export FS_PKG_BACKEND
            plan_install "${apps[@]}"
        ) || {
            io_error "flatpak batch failed"
            return 1
        }
    fi
    if ((FS_DRY_RUN != 1 && ${#ids[@]} > 0)); then
        state_init || return 1
    fi
    local rc=0
    for sid in ${ids[@]+"${ids[@]}"}; do
        dir="$modules_dir/$sid"
        if ((FS_DRY_RUN != 1)) && state_module_check "$sid"; then
            io_info "already completed: $sid"
            summary_module_skip "$sid"
            continue
        fi
        if module_has_hooks "$dir"; then
            rc=0
            (
                FS_MODULE_FAMILY="$family"
                export FS_MODULE_FAMILY
                module_load "$dir" strict || exit 1
                source "$dir/hooks.sh"
                run
            ) || rc=$?
            if ((rc == MODULE_HOOK_SKIP)); then
                io_info "not applicable: $sid"
                if ((FS_DRY_RUN != 1)); then
                    state_module_skip "$sid" || return 1
                fi
                summary_module_skip "$sid"
                continue
            fi
            if ((rc != 0)); then
                io_error "module failed: $sid"
                if [[ "${risks[$sid]:-none}" == destructive ]]; then
                    io_error "stopping run (destructive module $sid)"
                    return 1
                fi
                summary_module_fail "$sid" "hook exited $rc"
                continue
            fi
        fi
        if ((FS_DRY_RUN != 1)); then
            state_module_mark "$sid" || return 1
        fi
        summary_module_ok "$sid"
    done
    summary_report
    summary_rc
}
