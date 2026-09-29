#!/usr/bin/env bash
# lib/runner.sh - module runner (P4.6).
# Depends, in source order, on: lib/io.sh, lib/run.sh (dry rendering +
# audit), lib/planner.sh and the pkg layer (plan_install dispatch), then
# lib/state.sh (module registry), lib/lists.sh, lib/modules.sh,
# lib/depgraph.sh, lib/profiles.sh (resolver). runner_run calls state_init
# itself only in real mode, when the registry must be read or written.
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
#                         6. SUMMARY -- io_summary "run complete" with
#                            "N ok", "N failed", "N skipped" counts. rc0
#                            iff every selected module ended done (hook
#                            success or already-completed); rc1 if any
#                            module failed (or the run was stopped).
#                            State-mark failures abort rc1 fail-closed: the
#                            registry is authoritative, so a module that
#                            cannot be recorded stops the run without a
#                            summary (the batch has already committed).
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
#                       Privileged hooks must also account for sudo state:
#                       run_sudo fails closed unless sudo_detect ran
#                       (lib/sudo.sh); privilege detection is the caller's
#                       job -- bootstrapped runs call it in P4.7. P5 hook
#                       authors: call sudo_detect before relying on
#                       run_sudo.
#                       Resolve/validate/plan errors print only io_error
#                       lines and return rc1 -- no writes, no state.

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
    local -a pkgs=() apps=()
    local sid="" dir="" out="" p="" alt=""
    for sid in ${ids[@]+"${ids[@]}"}; do
        dir="$modules_dir/$sid"
        module_validate "$dir" "$family" || return 1
        risks[$sid]="$MODULE_RISK"
        io_info "module: $sid (${risks[$sid]})"
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
    if (( ${#pkgs[@]} > 0 )); then
        plan_install "${pkgs[@]}" || {
            io_error "package batch failed"
            return 1
        }
    fi
    if (( ${#apps[@]} > 0 )); then
        (
            FS_PKG_BACKEND=flatpak
            export FS_PKG_BACKEND
            plan_install "${apps[@]}"
        ) || {
            io_error "flatpak batch failed"
            return 1
        }
    fi
    if (( FS_DRY_RUN != 1 && ${#ids[@]} > 0 )); then
        state_init || return 1
    fi
    local -i ok=0 failed=0 skipped=0
    local rc=0
    for sid in ${ids[@]+"${ids[@]}"}; do
        dir="$modules_dir/$sid"
        if (( FS_DRY_RUN != 1 )) && state_module_check "$sid"; then
            io_info "already completed: $sid"
            skipped+=1
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
            if (( rc != 0 )); then
                io_error "module failed: $sid"
                if [[ "${risks[$sid]:-none}" == destructive ]]; then
                    io_error "stopping run (destructive module $sid)"
                    return 1
                fi
                failed+=1
                continue
            fi
        fi
        if (( FS_DRY_RUN != 1 )); then
            state_module_mark "$sid" || return 1
        fi
        ok+=1
    done
    io_summary "run complete" "$ok ok" "$failed failed" "$skipped skipped"
    if (( failed > 0 )); then
        return 1
    fi
    return 0
}