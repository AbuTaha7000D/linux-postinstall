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
#                       end-to-end bootstrap of one profile, in five
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
#                            A io_info "module: <id> (<risk>)" line is
#                            printed per module; risks are remembered for
#                            the failure policy.
#                         3. BATCH -- plan_install (P3.8) is called at
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
#                         4. HOOKS + STATE -- per module, in the resolved
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
#                         5. SUMMARY -- io_summary "run complete" with
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
    local sid="" dir="" out="" p=""
    for sid in ${ids[@]+"${ids[@]}"}; do
        dir="$modules_dir/$sid"
        module_validate "$dir" "$family" || return 1
        risks[$sid]="$MODULE_RISK"
        io_info "module: $sid (${risks[$sid]})"
        out="$(list_packages "$dir" "$family")" || return 1
        if [[ -n "$out" ]]; then
            while IFS= read -r p; do
                pkgs+=("$p")
            done <<<"$out"
        fi
        out="$(list_flatpaks "$dir")" || return 1
        if [[ -n "$out" ]]; then
            while IFS= read -r p; do
                apps+=("$p")
            done <<<"$out"
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
            ( source "$dir/hooks.sh"; run ) || rc=$?
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