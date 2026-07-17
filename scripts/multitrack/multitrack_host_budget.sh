#!/bin/sh
# =============================================================================
# multitrack_host_budget.sh — host-safety AGGREGATE spawn/launch budget guard
#     for the multi-track ruler-bridge worker pool (RB-02).
# -----------------------------------------------------------------------------
# Purpose:
#   A shared guard the ruler's spawn + launch layers MUST call BEFORE creating
#   any per-track worker (a headless `claude -p ...` process, or an
#   interactively-attached track session). It answers exactly one question —
#   "is it safe to start one more worker right now?" — by checking THREE
#   independent conditions, ALL of which must hold:
#     (a) pool cap      — live worker count < MT_MAX_WORKERS (default 4, one
#                          per /mnt/trackN). No --force/--no-cap escape exists
#                          anywhere in this file.
#     (b) build-quiet   — no heavy build (`m -j` / gradle / build_maxres / the
#                          JVM compile-daemon family) is currently in flight,
#                          per the CLAUDE.md §12.7/§12.8 concurrency-hardening
#                          precedent (a spawned worker plus a live AOSP/gradle
#                          build is exactly the concurrent-heavy-consumer
#                          pattern §12.8 already forbids for `m -j` itself).
#     (c) §12.6 budget  — the PROJECTED aggregate RSS of (live workers + one
#                          more) stays inside the host-safety lib's 60%-of-RAM
#                          ceiling (HOST_SAFETY_BUDGET_GB), using the SAME
#                          host_safe_parallel_jobs() arithmetic the AOSP build
#                          path already relies on (no parallel/duplicate
#                          memory-budget mechanism is invented here).
#
#   This file is CONSTITUTION-LAYER and PROJECT-AGNOSTIC (§11.4.28/§11.4.35):
#   it contains no project name, no device serial, no package id, no region
#   string. Every project-specific value (repo root, which host-safety-lib
#   copy to source, the worker/build process signatures) is resolved via env
#   overrides with documented, honest fallbacks — never guessed (§11.4.6).
#
# Usage (SOURCED, not executed — this is a pure function library, exactly
#   like scripts/lib/host_session_safety.sh; sourcing it has NO side effects
#   beyond defining the functions/vars below and, if resolvable, sourcing the
#   host-safety lib):
#     . /path/to/multitrack_host_budget.sh
#     if mt_host_budget_can_spawn; then
#         : # proceed to spawn one more worker
#     else
#         rc=$?
#         echo "refused (rc=$rc): see stdout reason line" >&2
#     fi
#
#   mt_host_budget_can_spawn accepts ONE optional argument — a caller-supplied
#   current live-worker count (e.g. from RB-05's session registry, which will
#   be authoritative once it lands). When omitted, the guard auto-detects the
#   live count via `pgrep -f "$MT_HOST_BUDGET_WORKER_PGREP_PATTERN"` so it is
#   independently usable (by `multitrack-up` today, before RB-05 exists).
#     mt_host_budget_can_spawn           # auto-detect via pgrep
#     mt_host_budget_can_spawn "$N"      # caller supplies the live count
#
# Exit codes (from mt_host_budget_can_spawn):
#   0 = ALLOW.
#   1 = REFUSE — pool at MT_MAX_WORKERS cap.
#   2 = REFUSE — heavy build in flight (pgrep build-pattern matched).
#   3 = REFUSE — projected aggregate RSS would exceed the §12.6 60% budget.
#   4 = REFUSE — host-safety lib could not be resolved/sourced (honest
#       degrade; NEVER a fake-pass — §11.4.6).
#   A human-readable reason string is always printed on stdout (ALLOW lines
#   too, so callers/tests can capture the full decision with `$( )`).
#
# Inputs (env, all optional, all with documented defaults):
#   HOST_SAFETY_LIB                     — explicit path to host_session_safety.sh.
#                                          Wins unconditionally over the
#                                          resolution chain below.
#   MT_REPO_ROOT                        — consumer project root, used only to
#                                          derive the fallback host-safety-lib
#                                          path scripts/lib/host_session_safety.sh
#                                          under it (per CLAUDE.md §12.6).
#   MT_MAX_WORKERS                      — pool cap (default 4).
#   MT_HOST_BUDGET_WORKER_RSS_GB        — estimated peak RSS per worker, GB
#                                          (default 2 — a headless `claude -p`
#                                          process plus its MCP-server fleet;
#                                          documented estimate, not a measured
#                                          fact, exactly like the existing
#                                          host_safe_build_jobs() per_job_gb=6
#                                          default for AOSP Soong jobs).
#   MT_HOST_BUDGET_BUILD_PGREP_PATTERN  — pgrep -f pattern identifying a heavy
#                                          build in flight (default below).
#   MT_HOST_BUDGET_WORKER_PGREP_PATTERN — pgrep -f pattern identifying a live
#                                          ruler-spawned worker process
#                                          (default matches RB-05's planned
#                                          `claude -p --output-format
#                                          stream-json` invocation).
#
# Outputs: human-readable ALLOW/REFUSE line on stdout from
#   mt_host_budget_can_spawn; no files written; no state persisted (this file
#   is a pure decision function, not a registry — §11.4.116 registries, if
#   any, are the CALLER's responsibility).
#
# Side-effects: NONE beyond reading /proc/meminfo (via the sourced host-safety
#   lib) and running `pgrep` (read-only process census). Never spawns a
#   process, never touches a device, never writes to disk, never touches
#   credentials (§11.4.10).
#
# Dependencies: sh (POSIX), pgrep, wc, awk (transitively, via the sourced
#   host-safety lib), the host-safety lib itself
#   (scripts/lib/host_session_safety.sh in the consumer project as of this
#   writing — no constitution-submodule mirror exists yet, verified 2026-07-06:
#   `ls constitution/scripts/lib/` -> No such file or directory).
#
# Cross-references: CLAUDE.md §12.6 (60% memory-budget ceiling) / §12.7
#   (AOSP -j2 cap) / §12.8 (concurrency hardening — the JVM-daemon regex this
#   file's build-pattern default is aligned with); docs/superpowers/plans/
#   ruler_bridge_plan.md RB-02 (this PWU's authoritative spec) + RB-05
#   (the future headless-spawn caller); scripts/lib/host_session_safety.sh
#   (host_safe_parallel_jobs, HOST_SAFETY_BUDGET_GB); §11.4.69 (feature class
#   `boot_service` — this guard IS a boot/launch-time positive-evidence gate);
#   §11.4.18 (this doc block); §11.4.35 (constitution-vs-project layering —
#   this file lives in the constitution layer, project-agnostic).
#
# Companion doc: docs/scripts/multitrack_host_budget.md is NOT authored by
#   this PWU (flagged for the conductor — as of this writing NONE of this
#   file's 11 sibling scripts under constitution/scripts/multitrack/ have a
#   docs/scripts/*.md companion either, so this is a pre-existing gap, not a
#   regression introduced here; see the RB-02 report for the explicit flag).
# =============================================================================

# ---------------------------------------------------------------------------
# Resolve + source the host-safety lib. Resolution order (never guessed,
# §11.4.6 — verified by direct inspection of this checkout on 2026-07-06):
#   1. $HOST_SAFETY_LIB  — explicit override, always wins.
#   2. constitution-submodule mirror at ../lib/host_session_safety.sh
#      relative to this file's own directory, IF one has been created by a
#      later PWU. (Does not exist yet: `constitution/scripts/lib/` is
#      absent as of this writing.)
#   3. the consumer-project copy at
#      ${MT_REPO_ROOT:-<derived from git rev-parse --show-toplevel>}/scripts/
#      lib/host_session_safety.sh, per CLAUDE.md §12.6.
# Absence of the lib is an HONEST non-zero refusal from
# mt_host_budget_can_spawn (exit 4) — this file NEVER fakes a PASS/ALLOW
# verdict when it cannot certify the §12.6 budget (§11.4.6 no-fake-pass).
# ---------------------------------------------------------------------------
MT_HB_SELF=$0
case "$MT_HB_SELF" in
    */*) MT_HB_DIR=${MT_HB_SELF%/*} ;;
    *)   MT_HB_DIR=. ;;
esac

_mt_hb_derive_repo_root() {
    if [ -n "${MT_REPO_ROOT:-}" ]; then
        printf '%s\n' "$MT_REPO_ROOT"
        return 0
    fi
    if command -v git >/dev/null 2>&1; then
        ( cd "$MT_HB_DIR" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null ) && return 0
    fi
    return 1
}

_mt_hb_resolve_host_safety_lib() {
    if [ -n "${HOST_SAFETY_LIB:-}" ] && [ -f "$HOST_SAFETY_LIB" ]; then
        printf '%s\n' "$HOST_SAFETY_LIB"
        return 0
    fi
    _mt_hb_const_mirror="$MT_HB_DIR/../lib/host_session_safety.sh"
    if [ -f "$_mt_hb_const_mirror" ]; then
        printf '%s\n' "$_mt_hb_const_mirror"
        unset _mt_hb_const_mirror
        return 0
    fi
    unset _mt_hb_const_mirror
    _mt_hb_root=$(_mt_hb_derive_repo_root) || _mt_hb_root=""
    if [ -n "$_mt_hb_root" ] && [ -f "$_mt_hb_root/scripts/lib/host_session_safety.sh" ]; then
        printf '%s\n' "$_mt_hb_root/scripts/lib/host_session_safety.sh"
        unset _mt_hb_root
        return 0
    fi
    unset _mt_hb_root
    return 1
}

MT_HOST_BUDGET_LIB_MISSING=""
MT_HOST_BUDGET_LIB_PATH=$(_mt_hb_resolve_host_safety_lib) || {
    MT_HOST_BUDGET_LIB_MISSING=1
    printf '%s\n' "[multitrack_host_budget] REFUSE-DEGRADE: host-safety lib not found (checked \$HOST_SAFETY_LIB, constitution mirror ${MT_HB_DIR}/../lib/host_session_safety.sh, consumer scripts/lib/host_session_safety.sh under \$MT_REPO_ROOT or git toplevel). mt_host_budget_can_spawn will refuse (exit 4) rather than fake-pass a §12.6 certification it cannot make." >&2
}

if [ -z "$MT_HOST_BUDGET_LIB_MISSING" ]; then
    # shellcheck source=/dev/null
    . "$MT_HOST_BUDGET_LIB_PATH"
fi

# ---------------------------------------------------------------------------
# Configuration (env-overridable, honest documented defaults — §11.4.6).
# ---------------------------------------------------------------------------
# >>MT_MAX_WORKERS_CLAMP
# Pool cap. Default 4 (one per /mnt/trackN in the current 4-track layout).
# May be raised on a documented big-RAM host by exporting MT_MAX_WORKERS
# before sourcing this file. There is NO --force / --no-cap flag anywhere in
# this file — raising the cap is the ONLY override path, and it is a
# deliberate, visible env-var change, never a silent bypass.
MT_MAX_WORKERS="${MT_MAX_WORKERS:-4}"
# <<MT_MAX_WORKERS_CLAMP

# Estimated peak RSS per worker, in GB. Documented engineering estimate (not
# a measured fact) — same status as host_safe_build_jobs()'s per_job_gb=6
# default for AOSP Soong jobs. A headless `claude -p` process plus its
# MCP-server fleet is expected to peak in the low single-digit GB range
# (CLAUDE.md §12.1 forensic note: "each MCP consumes 100-500 MB", 20+ can be
# spawned per session). 2 GB/worker is a conservative mid estimate pending a
# captured measurement from a real RB-05 spawn (tracked as a follow-up, not
# invented as fact here).
MT_HOST_BUDGET_WORKER_RSS_GB="${MT_HOST_BUDGET_WORKER_RSS_GB:-2}"

# >>MT_BUILD_PGREP_GUARD
# Heavy-build detection pattern. Aligned with the CLAUDE.md §12.7/§12.8
# concurrency-hardening precedent (host_check_aosp_preflight's JVM-daemon
# regex in scripts/lib/host_session_safety.sh) plus the AOSP `m -j` /
# containerised `build_maxres` entry points themselves. I3 fix: the default
# previously omitted 4 tokens of the project's own documented §12.8b
# "complete" JVM-daemon set (`gradle-launcher`, `ScalaCompileDaemon`,
# `GroovyCompileDaemon`, `kotlin-compiler-embeddable`) -- an independent
# review found a worker spawn could proceed concurrently with one of those
# four processes alive without this build-guard firing, narrower protection
# than the project's own documented complete pattern for the same
# concurrency-hardening concern this doc-comment cites as its precedent.
MT_HOST_BUDGET_BUILD_PGREP_PATTERN="${MT_HOST_BUDGET_BUILD_PGREP_PATTERN:-m -j|gradle|build_maxres|GradleDaemon|GradleWorkerMain|gradle-launcher|KotlinCompileDaemon|ScalaCompileDaemon|GroovyCompileDaemon|kotlin-compiler-embeddable}"
# <<MT_BUILD_PGREP_GUARD

# Live-worker detection pattern (auto-detect fallback when the caller does
# not supply an explicit count). Matches RB-05's planned headless-spawn
# invocation (`claude -p --output-format stream-json --verbose`) so that,
# once RB-05 lands, real workers are counted correctly out of the box.
MT_HOST_BUDGET_WORKER_PGREP_PATTERN="${MT_HOST_BUDGET_WORKER_PGREP_PATTERN:-claude .*--output-format[= ]stream-json}"

# ---------------------------------------------------------------------------
# Internal helpers.
# ---------------------------------------------------------------------------
_mt_host_budget_live_worker_count() {
    # Read-only process census. `pgrep -f PATTERN | wc -l` is 0 whether
    # pgrep exits 1 (no match) or prints nothing — no special-casing needed.
    pgrep -f "$MT_HOST_BUDGET_WORKER_PGREP_PATTERN" 2>/dev/null | wc -l | tr -d ' '
}

# >>MT_HB_STRICT_BUILD_FILTER (paired §1.1 mutation target — the strict-filter
#   toggle IS the RB-02 pgrep-footgun fix. The value below is a PLAIN internal
#   constant, DELIBERATELY NOT env-overridable (no `${...:-1}`) so it is NOT an
#   operator escape hatch (§11.4.69 no-escape-hatch). The paired test seds a
#   THROWAWAY copy of this file flipping `=1` to `=0` to reproduce the pre-fix
#   footgun (RED, §11.4.115) and to prove the guard catches the negation (§1.1);
#   do NOT remove this marker and do NOT set it to 0 in the shipped file.)
_mt_hb_strict_build_filter=1
# <<MT_HB_STRICT_BUILD_FILTER

# >>MT_HB_LIVENESS_GATE (paired §1.1 mutation target — the liveness-gate toggle IS
#   the §11.4.201/§11.4.180 vanished-PID FALSE-REFUSE fix. Like the strict-filter
#   above, a PLAIN internal constant, DELIBERATELY NOT env-overridable (no
#   `${...:-1}` write) so it is NOT an operator escape hatch (§11.4.69). When 1 the
#   empty/unreadable-cmdline branch of _mt_host_budget_heavy_build_running skips a
#   DEAD/vanished matched PID (the fix); the paired
#   test_multitrack_host_budget_rb02_pgrep.sh + the CM-MULTITRACK-GUARD-VANISHED-
#   PID-LIVENESS meta-mutation sed a THROWAWAY copy flipping `=1` to `=0`, reverting
#   the branch to the pre-fix UNCONDITIONAL REFUSE, to reproduce the footgun (RED,
#   §11.4.115) and prove the guard catches the negation (§1.1). Do NOT remove this
#   marker and do NOT set it to 0 in the shipped file. The read below uses `:-1`
#   defensively so a DELETED constant still defaults to the SAFE fix-active state.)
_mt_hb_liveness_gate=1
# <<MT_HB_LIVENESS_GATE

# _mt_host_budget_heavy_build_running — TRUE iff a GENUINE heavy build is in
#   flight. RB-02 pgrep-footgun fix (§12.12 / forensic FACT 2026-07-13,
#   captured in qa-results/multitrack/rb02_pgrep_footgun_*):
#     `pgrep -f "$PATTERN"` matches the alternation regex as a SUBSTRING of every
#     process's FULL command line, so a process that merely MENTIONS a build
#     token — WITHOUT being a build — false-matches and made this guard REFUSE on
#     EVERY live spawn (zero real builds). The three real false-positive classes
#     (all captured live): (a) a pattern-CARRIER — a process whose args literally
#     contain the whole `m -j|gradle|...` alternation string (this guard's own
#     caller invoked with the pattern; a launcher/monitor/test/`claude -p` worker
#     whose prompt QUOTES the pgrep pattern); (b) a multitrack ENGINE process
#     (orchestrator/monitor/launcher/guard — cmdline contains `multitrack`);
#     (c) a `claude`/`claude -p`/stream-json WORKER whose prompt blob embeds a
#     build token (a worker is NEVER itself a build — the real build is a CHILD
#     process: soong_build/ninja/kati/java `GradleDaemon`, whose OWN cmdline
#     genuinely invokes the token and is NOT excluded). The fix re-reads each
#     matched PID's REAL cmdline from /proc and excludes those three classes plus
#     this guard's own process + its parent.
#   LIVENESS-GATED SAFE-BY-DEFAULT (§11.4.201 assert-the-REAL-condition /
#   §11.4.180 liveness-PROVEN / §11.4.101 reversible-safe / §12.8 strictness): a
#   matched PID whose /proc/<pid>/cmdline is UNREADABLE or EMPTY is FIRST
#   liveness-probed with `kill -0` (the stubbable _mt_host_budget_pid_alive seam)
#   before it is counted as a build:
#     - DEAD/vanished PID (the pgrep→/proc read RACE — `pgrep -f` matched a
#       TRANSIENT PID from the spawn pipeline that exited before the /proc read;
#       a real soong/gradle build runs for MINUTES and does NOT vanish between
#       pgrep and the read) => provably NOT a live heavy build => SKIP it. This
#       removes the RB-02 vanished-PID FALSE-REFUSE footgun that made the guard
#       REFUSE every worker spawn on a host with ZERO real builds (forensic FACT
#       2026-07-15; a captured `/proc/<pid>/cmdline: No such file` race).
#     - LIVE process (kill -0 ok) whose cmdline is unreadable/empty (a rare
#       permission/kernel race on a genuine LIVE process) => conservatively
#       counted AS a build (return 0 => REFUSE) — a refused spawn is safe +
#       retried; wrongly ALLOWING a spawn during a real build is the harm. The
#       refusal PRINTS its resolved evidence (the real pid + why) per §11.4.201(5).
#   A false-POSITIVE refusal (blocking a spawn while no build runs) is a §11.4.1
#   FAIL-bluff exactly as a false-negative ALLOW is a PASS-bluff — the liveness
#   gate makes the refusal assert the REAL condition (a LIVE build), not a proxy.
#   A genuine soong/gradle/containerised build carries NONE of the
#   carrier/engine/worker markers AND does not vanish, so it still matches — the
#   exclusion + liveness gate remove ONLY the footgun, never a real build
#   (§11.4.6, proven by the paired test_multitrack_host_budget_rb02_pgrep.sh
#   RED→GREEN + §1.1 self-check, incl. its unreadable-live/unreadable-vanished
#   scenarios).
# Read one PID's full command line (NUL-separated argv -> single-spaced). A
# named seam (§11.4.108) so the paired hermetic test can stub it deterministically
# alongside a fake `pgrep` — no real process, no spawn-timing flake. Default reads
# the real /proc; empty output => unreadable/vanished (handled by the caller under
# the LIVENESS GATE — a DEAD pid is skipped, a LIVE pid is a conservative REFUSE,
# §11.4.201). Never writes anything (§11.4.128 read-only).
_mt_host_budget_pid_cmdline() {
    tr '\0' ' ' < "/proc/$1/cmdline" 2>/dev/null
}

# _mt_host_budget_pid_alive — PROVE one matched PID is actually ALIVE (§11.4.201
#   assert-the-real-condition / §11.4.180 liveness-PROVEN-via-kill-0). Gates the
#   empty/unreadable-cmdline branch of _mt_host_budget_heavy_build_running: a
#   DEAD/vanished PID (the `pgrep -f`→/proc read race) CANNOT be a live heavy
#   build, so it MUST NOT be counted as one. A named seam (§11.4.108) — like
#   _mt_host_budget_pid_cmdline above — so the paired hermetic test stubs it
#   DETERMINISTICALLY (no dependence on whether some arbitrary host PID happens to
#   exist, §11.4.50), while the default is the real `kill -0` probe. Returns 0 iff
#   the PID is live AND signalable by this user — i.e. OUR OWN build/worker
#   processes, exactly the set this guard's §12.6 budget protects. Honest boundary
#   (§11.4.6): a live process we CANNOT signal (another user's process under
#   `hidepid`, EPERM) reads as not-ours and is skipped — an accepted corner, since
#   this guard gates OUR user.slice spawns against OUR builds. `kill -0` sends NO
#   signal — read-only census (§11.4.128).
_mt_host_budget_pid_alive() {
    kill -0 "$1" 2>/dev/null
}

_mt_host_budget_heavy_build_running() {
    _mt_hb_pids=$(pgrep -f "$MT_HOST_BUDGET_BUILD_PGREP_PATTERN" 2>/dev/null)
    [ -n "$_mt_hb_pids" ] || return 1        # no pattern match at all => no build

    if [ "${_mt_hb_strict_build_filter:-1}" != "1" ]; then
        # pre-fix naive path (§1.1 mutation target): ANY substring match => a
        # "build", the exact RB-02 footgun. The shipped file keeps
        # _mt_hb_strict_build_filter=1 so this branch is never taken in
        # production; the paired test flips it on a throwaway copy.
        return 0
    fi

    _mt_hb_self=$$
    _mt_hb_ppid=${PPID:-0}
    for _mt_hb_pid in $_mt_hb_pids; do
        case "$_mt_hb_pid" in ''|*[!0-9]*) continue ;; esac
        # never count THIS guard's own process or its parent (self/sibling footgun)
        [ "$_mt_hb_pid" = "$_mt_hb_self" ] && continue
        [ "$_mt_hb_pid" = "$_mt_hb_ppid" ] && continue
        # read the matched PID's REAL full cmdline (via the stubbable seam).
        _mt_hb_cl=$(_mt_host_budget_pid_cmdline "$_mt_hb_pid")
        if [ -z "$_mt_hb_cl" ]; then
            # matched but cmdline gone/unreadable. §11.4.201/§11.4.180: PROVE
            # liveness before counting it as a build. A DEAD/vanished PID (the
            # `pgrep -f`→/proc read RACE — a transient PID that exited between the
            # match and the read) CANNOT be a live heavy build => SKIP it. This
            # removes the RB-02 vanished-PID FALSE-REFUSE footgun (a false-POSITIVE
            # refusal is a §11.4.1 FAIL-bluff). A real soong/gradle build runs for
            # minutes and does NOT vanish, so it stays caught.
            if [ "${_mt_hb_liveness_gate:-1}" = "1" ] && ! _mt_host_budget_pid_alive "$_mt_hb_pid"; then
                # dead/vanished PID => provably NOT a live build; skip it.
                continue
            fi
            # LIVE process (kill -0 ok) with an unreadable/empty cmdline (rare
            # permission/kernel race), OR the liveness gate is mutated off:
            # conservatively treat as a real build => REFUSE (safe reversible
            # default, §11.4.101 / §12.8). Report the RESOLVED evidence (§11.4.201(5)).
            printf '%s\n' "[multitrack_host_budget] REFUSE: pid $_mt_hb_pid matched the build pattern and is LIVE (kill -0 ok) but its /proc/$_mt_hb_pid/cmdline is unreadable/empty -- conservatively counted as a real build (safe default §11.4.201/§12.8)." >&2
            unset _mt_hb_self _mt_hb_ppid _mt_hb_pid _mt_hb_cl _mt_hb_pids
            return 0
        fi
        # exclude a pattern-CARRIER: cmdline literally contains the whole
        # alternation pattern string (a real build never carries the `|`-joined
        # alternation as its own argv — only a quoter/launcher/prompt does).
        case "$_mt_hb_cl" in *"$MT_HOST_BUDGET_BUILD_PGREP_PATTERN"*) continue ;; esac
        # exclude a multitrack ENGINE process (orchestrator/monitor/launcher/guard)
        case "$_mt_hb_cl" in *multitrack*) continue ;; esac
        # exclude a `claude`/`claude -p`/stream-json WORKER (prompt-carrier; the
        # real build, if any, is its CHILD process with its own matching cmdline).
        case "$_mt_hb_cl" in
            claude\ *|*/claude\ *|*"claude -p"*|*stream-json*) continue ;;
        esac
        # survivor: a genuine heavy-build process => REFUSE.
        unset _mt_hb_self _mt_hb_ppid _mt_hb_pid _mt_hb_cl _mt_hb_pids
        return 0
    done
    # every match was an excluded footgun carrier => no real build in flight.
    unset _mt_hb_self _mt_hb_ppid _mt_hb_pid _mt_hb_cl _mt_hb_pids
    return 1
}

# ---------------------------------------------------------------------------
# Public: mt_host_budget_can_spawn [live_count]
# ---------------------------------------------------------------------------
mt_host_budget_can_spawn() {
    if [ -n "$MT_HOST_BUDGET_LIB_MISSING" ]; then
        printf '%s\n' "REFUSE: host-safety lib unavailable (see the source-time message above) -- refusing to certify a §12.6 budget without it. No fake-pass (§11.4.6)."
        return 4
    fi

    _mt_hb_live="${1:-}"
    if [ -z "$_mt_hb_live" ]; then
        _mt_hb_live=$(_mt_host_budget_live_worker_count)
    fi
    _mt_hb_live=${_mt_hb_live:-0}

    if [ "$_mt_hb_live" -ge "$MT_MAX_WORKERS" ]; then
        printf '%s\n' "REFUSE: pool at cap ($_mt_hb_live/$MT_MAX_WORKERS live workers matching '$MT_HOST_BUDGET_WORKER_PGREP_PATTERN') -- MT_MAX_WORKERS clamp. No --force/--no-cap escape exists."
        unset _mt_hb_live
        return 1
    fi

    if _mt_host_budget_heavy_build_running; then
        printf '%s\n' "REFUSE: heavy build in flight (pgrep -f '$MT_HOST_BUDGET_BUILD_PGREP_PATTERN' matched) -- refusing to spawn a worker while m -j/gradle/build_maxres is running (CLAUDE.md §12.7/§12.8)."
        unset _mt_hb_live
        return 2
    fi

    _mt_hb_projected=$((_mt_hb_live + 1))
    _mt_hb_safe_max=$(host_safe_parallel_jobs "$MT_HOST_BUDGET_WORKER_RSS_GB")
    if [ "$_mt_hb_projected" -gt "$_mt_hb_safe_max" ]; then
        printf '%s\n' "REFUSE: projected aggregate RSS ($_mt_hb_projected workers x ${MT_HOST_BUDGET_WORKER_RSS_GB}GB) would exceed the §12.6 60%-of-RAM budget-derived cap of $_mt_hb_safe_max workers (HOST_SAFETY_BUDGET_GB=${HOST_SAFETY_BUDGET_GB:-0}GB)."
        unset _mt_hb_live _mt_hb_projected _mt_hb_safe_max
        return 3
    fi

    printf '%s\n' "ALLOW: $_mt_hb_projected/$MT_MAX_WORKERS workers projected, within the §12.6 budget (budget-derived cap $_mt_hb_safe_max workers at ${MT_HOST_BUDGET_WORKER_RSS_GB}GB/worker, HOST_SAFETY_BUDGET_GB=${HOST_SAFETY_BUDGET_GB:-0}GB)."
    unset _mt_hb_live _mt_hb_projected _mt_hb_safe_max
    return 0
}
