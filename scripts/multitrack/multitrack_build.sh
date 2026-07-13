#!/usr/bin/env bash
# =============================================================================
# multitrack_build.sh — single-builder FIFO BUILD QUEUE for the multi-track
#                       pipeline (§11.4.167-F). §11.4.119 / §11.4.116 /
#                       §11.4.77 / §11.4.133 / §12.7 / §12.8 / §12.9 / §12.11 /
#                       §11.4.6 / §11.4.121.
# -----------------------------------------------------------------------------
# Purpose:
#   Serialize AOSP rebuilds across N parallel work-stream tracks onto ONE
#   builder (§11.4.167-F: "Build queue — ONE builder"). Tracks `enqueue` a
#   rebuild request; a single `run-next` worker pops the FIFO head under an
#   flock so at most ONE heavy AOSP build ever runs at a time (the §12.7/§12.8
#   never-two-concurrent-heavy-builds invariant, made mechanical). The ONLY
#   sanctioned build path is invoked — `bash scripts/build_maxres.sh` (§12.11
#   dynamic-max-resource, containerized §12.9) when present, else
#   `bash scripts/build.sh` — always with `--skip-pull --skip-tests --skip-ota`.
#
#   SAFETY (why this is testable NOW without launching a heavy build):
#     `run-next` is DRY-RUN BY DEFAULT — it acquires+releases the build.lock,
#     runs a read-only free-space pre-check, and PRINTS the sanctioned build
#     command it WOULD run, but launches NOTHING. The real launch path is gated
#     behind BOTH the `--execute` flag AND an explicit `MT_BUILD_EXECUTE=1`
#     environment authorization (a §12.7/§12.8/§12.9 host-safety guard so a
#     42 GB containerized AOSP build is never started by accident or by a test).
#     `--execute` without `MT_BUILD_EXECUTE=1` is REFUSED (exit 5) BEFORE any
#     lock is taken or any queue item is popped.
#
#   FREE-SPACE PRE-CHECK (§11.4.77 / §11.4.167-G): before a build the worker
#     reports `df` free space and LOGS which regenerable directories it WOULD
#     prune (`out/`, `$OUT_DIR_COMMON_BASE`) to make room — it NEVER deletes
#     anything (pruning regenerable build output is a deliberate, separate
#     operator/driver action, not a side effect of a status/dry-run).
#
# Registry (§11.4.116 substrate — plain-text, single source of truth):
#   .ws_state/build_queue.tsv     FIFO queue, one request per line:
#                                 <epoch>\t<track>\t<iso>  (line order == FIFO).
#   .ws_state/build.lock          the flock target — ONE builder at a time.
#   .ws_state/build_events.jsonl  append-only audit stream (ENQUEUE / DEQUEUE /
#                                 RUN-NEXT / FREESPACE / EXECUTE) — never rewritten.
#
# Usage:
#   multitrack_build.sh enqueue <track>        # append a rebuild request (idempotent)
#   multitrack_build.sh status                 # show the FIFO queue + builder-lock state
#   multitrack_build.sh run-next [--execute]   # dry-run: acquire lock, free-space
#                                              # check, print the build cmd it WOULD
#                                              # run (peek — non-destructive).
#                                              # --execute launches the real build
#                                              # ONLY if MT_BUILD_EXECUTE=1 (else exit 5).
#   multitrack_build.sh dequeue                # pop the FIFO head WITHOUT building
#                                              # (advance/skip; used after a build,
#                                              # and by the anti-bluff test).
#   multitrack_build.sh help
#
# Exit codes: 0 ok · 2 usage · 3 queue-empty (nothing to build / dequeue —
#             informational, not an error) · 4 free-space-blocked (execute path
#             only) · 5 --execute not authorized (MT_BUILD_EXECUTE!=1) ·
#             1 internal error.
#
# Inputs (env):
#   MT_REPO_ROOT        repo-root override (default: resolved from script dir).
#   MT_WS_STATE         state dir (default <repo>/.ws_state) — TEST points this
#                       at a TEMP copy so the real .ws_state is never touched.
#   MT_BUILD_QUEUE      queue file (default $MT_WS_STATE/build_queue.tsv).
#   MT_BUILD_LOCK       flock target (default $MT_WS_STATE/build.lock).
#   MT_BUILD_EVENTS     event log  (default $MT_WS_STATE/build_events.jsonl).
#   MT_BUILD_OUT_DIR    build-output dir for the free-space check (default <repo>/out).
#   MT_BUILD_MIN_FREE_GB  desired free GiB before a build (default 158 = 138 for
#                       one out/ + 20 headroom, §11.4.167-G).
#   MT_BUILD_EXECUTE    "1" authorizes the REAL build launch under `--execute`.
#                       ANY other value keeps run-next inert (host-safety default).
#   MT_LOCK_WAIT        flock -w seconds (default 10).
#   MT_HOLDER_PID       pid recorded in events (default $PPID).
#
# Outputs:  human-readable lines on stdout; queue TSV + JSONL under MT_WS_STATE.
# Side-effects:  writes ONLY under MT_WS_STATE (queue + lock + events). NEVER
#   deletes a build artifact, NEVER mounts/formats a drive, NEVER launches a
#   build unless BOTH `--execute` AND MT_BUILD_EXECUTE=1 are set (§12.7/§12.8/
#   §12.9/§11.4.133). NEVER touches credentials (§11.4.10).
# Dependencies:  bash, awk, flock, df, date, mkdir, mv, tail.
# Cross-references:  scripts/multitrack/multitrack.sh (entrypoint);
#   scripts/multitrack/multitrack_device_lock.sh (sibling arbiter shape);
#   scripts/multitrack/multitrack_registry.sh (registry accessor);
#   scripts/multitrack/multitrack_claim.sh (§11.4.176-A claim registry);
#   scripts/build_maxres.sh + scripts/build.sh (the ONLY sanctioned build paths);
#   scripts/multitrack/test_multitrack_queue_claim.sh (anti-bluff proof);
#   docs/scripts/multitrack_build.md.
# =============================================================================

set -euo pipefail

MTB_SELF=$0
case "$MTB_SELF" in
    */*) MTB_DIR=${MTB_SELF%/*} ;;
    *)   MTB_DIR=. ;;
esac

MTB_REPO_ROOT=${MT_REPO_ROOT:-$(cd "$MTB_DIR/../.." 2>/dev/null && pwd || printf '.')}
MT_WS_STATE=${MT_WS_STATE:-$MTB_REPO_ROOT/.ws_state}
MTB_QUEUE=${MT_BUILD_QUEUE:-$MT_WS_STATE/build_queue.tsv}
MTB_LOCK=${MT_BUILD_LOCK:-$MT_WS_STATE/build.lock}
MTB_EVENTS=${MT_BUILD_EVENTS:-$MT_WS_STATE/build_events.jsonl}
MTB_OUT_DIR=${MT_BUILD_OUT_DIR:-$MTB_REPO_ROOT/out}
MTB_MIN_FREE_GB=${MT_BUILD_MIN_FREE_GB:-158}
MT_LOCK_WAIT=${MT_LOCK_WAIT:-10}
MTB_HOLDER_PID=${MT_HOLDER_PID:-$PPID}
MTB_TAB=$(printf '\t')

_now() { date +%s; }
_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# JSON-safe: strip embedded double-quotes so the JSONL line stays well-formed.
_jsan() { printf '%s' "${1:-}" | tr '"' "'"; }

# _event EVENT TRACK NOTE -> append one JSONL audit line (never rewritten).
_event() {
    printf '{"ts":%s,"iso":"%s","event":"%s","track":"%s","pid":%s,"note":"%s"}\n' \
        "$(_now)" "$(_iso)" "$(_jsan "$1")" "$(_jsan "$2")" "$MTB_HOLDER_PID" "$(_jsan "$3")" \
        >> "$MTB_EVENTS"
}

_ensure_dirs() {
    mkdir -p "$MT_WS_STATE" 2>/dev/null || { echo "FATAL: cannot create $MT_WS_STATE" >&2; exit 1; }
    [ -e "$MTB_QUEUE" ]  || : > "$MTB_QUEUE"
    [ -e "$MTB_LOCK" ]   || : > "$MTB_LOCK"
    [ -e "$MTB_EVENTS" ] || : > "$MTB_EVENTS"
}

# Reject empty / tab / newline track tokens (would corrupt the TSV / JSONL).
_validate_track() {
    _vt=$1
    [ -n "$_vt" ] || { echo "usage: track id must be non-empty" >&2; exit 2; }
    case "$_vt" in
        *"$MTB_TAB"*) echo "invalid track '$_vt': contains a TAB" >&2; exit 2 ;;
    esac
    if [ "$(printf '%s' "$_vt" | wc -l | tr -d ' ')" != "0" ]; then
        echo "invalid track '$_vt': contains a newline" >&2; exit 2
    fi
}

# The sanctioned build command (string form). Generic contract (§11.4.28): a
# consuming project supplies it via the `build.command` config key, exported by
# its config layer (or launcher) as MT_BUILD_COMMAND. When that env is unset a
# documented default fallback auto-detects the conventional build scripts under
# the repo root (§12.11 maxres preferred, else the plain build script).
_build_cmd() {
    if [ -n "${MT_BUILD_COMMAND:-}" ]; then
        printf '%s' "$MT_BUILD_COMMAND"
    elif [ -x "$MTB_REPO_ROOT/scripts/build_maxres.sh" ]; then
        printf 'bash scripts/build_maxres.sh --skip-pull --skip-tests --skip-ota'
    else
        printf 'bash scripts/build.sh --skip-pull --skip-tests --skip-ota'
    fi
}

# integer GiB available on the filesystem that holds $1 (0 on any failure).
_free_gb() {
    _fg_p=$1
    _fg_kb=$(df -Pk "$_fg_p" 2>/dev/null | awk 'NR==2{print $4+0; exit}') || _fg_kb=0
    [ -n "$_fg_kb" ] || _fg_kb=0
    printf '%s' "$(( _fg_kb / 1024 / 1024 ))"
}

# Report free space + LOG regenerable prune candidates. Deletes NOTHING (§11.4.77).
# Returns 10 if free < desired (caller decides: dry-run ignores, execute blocks).
_freespace_report() {
    _fr_root=$1
    _fr_free=$(_free_gb "$_fr_root")
    printf 'FREESPACE: %sGiB free on filesystem of %s (desired >= %sGiB)\n' \
        "$_fr_free" "$_fr_root" "$MTB_MIN_FREE_GB"
    _fr_found=0
    if [ -d "$MTB_OUT_DIR" ]; then
        printf 'WOULD-PRUNE (regenerable §11.4.77, NOT deleted): %s\n' "$MTB_OUT_DIR"
        _fr_found=1
    fi
    if [ -n "${OUT_DIR_COMMON_BASE:-}" ] && [ -d "${OUT_DIR_COMMON_BASE:-}" ]; then
        printf 'WOULD-PRUNE (regenerable §11.4.77, NOT deleted): %s\n' "$OUT_DIR_COMMON_BASE"
        _fr_found=1
    fi
    [ "$_fr_found" = 1 ] || printf 'WOULD-PRUNE: (none — no regenerable out/ dirs under %s)\n' "$_fr_root"
    _event FREESPACE "" "free=${_fr_free}GiB desired=${MTB_MIN_FREE_GB}GiB prune_candidates=$_fr_found"
    if [ "$_fr_free" -lt "$MTB_MIN_FREE_GB" ]; then return 10; fi
    return 0
}

_queue_len() { awk 'END{print NR+0}' "$MTB_QUEUE" 2>/dev/null || printf '0'; }
_queue_has() { awk -F'\t' -v t="$1" '$2==t{f=1} END{exit f?0:1}' "$MTB_QUEUE" 2>/dev/null; }
_queue_head() { awk -F'\t' 'NR==1{print $2; exit}' "$MTB_QUEUE" 2>/dev/null || true; }

# --- commands -----------------------------------------------------------------
cmd_enqueue() {
    _validate_track "$1"
    _en_track=$1
    _ensure_dirs
    _en_rc=0
    (
        flock -w "$MT_LOCK_WAIT" 9 || { echo "FATAL: build queue busy (flock timeout)" >&2; exit 1; }
        if _queue_has "$_en_track"; then
            _en_pos=$(awk -F'\t' -v t="$_en_track" '$2==t{print NR; exit}' "$MTB_QUEUE")
            printf 'ALREADY-QUEUED (idempotent): %s at position %s\n' "$_en_track" "$_en_pos"
            exit 0
        fi
        printf '%s\t%s\t%s\n' "$(_now)" "$_en_track" "$(_iso)" >> "$MTB_QUEUE"
        _event ENQUEUE "$_en_track" "appended-to-fifo"
        printf 'ENQUEUED: %s (queue length now %s)\n' "$_en_track" "$(_queue_len)"
    ) 9<"$MTB_LOCK" || _en_rc=$?
    return "$_en_rc"
}

cmd_status() {
    _ensure_dirs
    printf '== build queue (%s) ==\n' "$MTB_QUEUE"
    if [ -s "$MTB_QUEUE" ]; then
        printf 'POS  TRACK                ENQUEUED\n'
        awk -F'\t' '{ printf "%-4d %-20s %s\n", NR, $2, $3 }' "$MTB_QUEUE"
    else
        printf '(empty)\n'
    fi
    printf 'queue length: %s\n' "$(_queue_len)"
    # builder-lock liveness: a non-blocking flock tells us if a build holds it.
    if flock -n 9; then
        printf 'builder lock: FREE (no build running)\n'
    else
        printf 'builder lock: HELD (a build is running)\n'
    fi 9<"$MTB_LOCK"
}

cmd_dequeue() {
    _ensure_dirs
    _dq_rc=0
    (
        flock -w "$MT_LOCK_WAIT" 9 || { echo "FATAL: build queue busy (flock timeout)" >&2; exit 1; }
        _dq_head=$(_queue_head)
        if [ -z "$_dq_head" ]; then
            printf 'QUEUE EMPTY: nothing to dequeue\n'
            exit 3
        fi
        # pop the FIFO head atomically (keep tail from line 2).
        tail -n +2 "$MTB_QUEUE" > "$MTB_QUEUE.tmp.$$" && mv -f "$MTB_QUEUE.tmp.$$" "$MTB_QUEUE"
        _event DEQUEUE "$_dq_head" "popped-fifo-head-no-build"
        printf 'DEQUEUED (not built): %s (queue length now %s)\n' "$_dq_head" "$(_queue_len)"
    ) 9<"$MTB_LOCK" || _dq_rc=$?
    return "$_dq_rc"
}

cmd_run_next() {
    _rn_execute=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --execute) _rn_execute=1 ;;
            --dry-run) _rn_execute=0 ;;
            *) echo "run-next: unknown arg '$1'" >&2; exit 2 ;;
        esac
        shift
    done

    # §12.7/§12.8/§12.9 host-safety guard: refuse a REAL launch unless BOTH the
    # flag AND the explicit env authorization are present — BEFORE any lock/pop.
    if [ "$_rn_execute" = 1 ] && [ "${MT_BUILD_EXECUTE:-0}" != 1 ]; then
        echo "REFUSED: run-next --execute requires MT_BUILD_EXECUTE=1 (host-safety §12.7/§12.8/§12.9);" >&2
        echo "         no MT_BUILD_EXECUTE=1 -> NOT launching a heavy AOSP build. Use dry-run (no --execute)" >&2
        echo "         to preview, or 'dequeue' to advance the FIFO without building." >&2
        _event RUN-NEXT "" "execute-refused-no-MT_BUILD_EXECUTE"
        exit 5
    fi

    _ensure_dirs
    _rn_rc=0
    (
        flock -w "$MT_LOCK_WAIT" 9 || { echo "FATAL: builder lock busy — another build holds it (flock timeout)" >&2; exit 1; }

        _rn_fs=0
        _freespace_report "$MTB_OUT_DIR" || _rn_fs=$?

        _rn_head=$(_queue_head)
        if [ -z "$_rn_head" ]; then
            printf 'QUEUE EMPTY: nothing to build\n'
            exit 3
        fi

        _rn_cmd=$(_build_cmd)

        if [ "$_rn_execute" = 1 ]; then
            # ---- authorized REAL build path (gated by MT_BUILD_EXECUTE=1) -----
            # This is intentionally the ONLY place a heavy build can start, and
            # only when the operator explicitly authorized it. Never reached by
            # the anti-bluff test (which never sets MT_BUILD_EXECUTE).
            if [ "$_rn_fs" = 10 ]; then
                echo "BLOCKED: insufficient free space for a build (see FREESPACE above);" >&2
                echo "         free regenerable out/ dirs (§11.4.77) then retry. NOT building." >&2
                _event RUN-NEXT "$_rn_head" "execute-blocked-freespace"
                exit 4
            fi
            tail -n +2 "$MTB_QUEUE" > "$MTB_QUEUE.tmp.$$" && mv -f "$MTB_QUEUE.tmp.$$" "$MTB_QUEUE"
            _event EXECUTE "$_rn_head" "launching-sanctioned-build"
            printf 'EXECUTE: building track %s via: %s\n' "$_rn_head" "$_rn_cmd"
            cd "$MTB_REPO_ROOT" || { echo "FATAL: cannot cd $MTB_REPO_ROOT" >&2; exit 1; }
            # shellcheck disable=SC2086  # _rn_cmd is our own trusted sanctioned string
            exec $_rn_cmd
        fi

        # ---- DRY-RUN (default): non-destructive preview; launches NOTHING -----
        _event RUN-NEXT "$_rn_head" "dry-run-peek-no-launch"
        printf 'DRY-RUN: next build is track %s\n' "$_rn_head"
        printf 'WOULD-RUN (in %s): %s\n' "$MTB_REPO_ROOT" "$_rn_cmd"
        printf 'NOTE: launched nothing. Re-run with --execute AND MT_BUILD_EXECUTE=1 to build,\n'
        printf '      or run "dequeue" to advance the FIFO without building.\n'
        if [ "$_rn_fs" = 10 ]; then
            printf 'WARN: free space below desired %sGiB — a real build would need pruning first.\n' "$MTB_MIN_FREE_GB"
        fi
    ) 9<"$MTB_LOCK" || _rn_rc=$?
    return "$_rn_rc"
}

usage() {
cat <<'EOF'
multitrack_build.sh — single-builder FIFO build queue (§11.4.167-F)

  enqueue <track>        append a rebuild request (idempotent — dedups)
  status                 show the FIFO queue + builder-lock state
  run-next [--execute]   DRY-RUN by default: acquire lock, free-space check,
                         print the sanctioned build command it WOULD run (peek).
                         --execute launches the real build ONLY if MT_BUILD_EXECUTE=1.
  dequeue                pop the FIFO head WITHOUT building (advance/skip)
  help                   this help

Env : MT_WS_STATE  MT_BUILD_QUEUE  MT_BUILD_LOCK  MT_BUILD_EXECUTE  MT_BUILD_MIN_FREE_GB
Exit: 0 ok · 2 usage · 3 queue-empty · 4 freespace-blocked · 5 execute-not-authorized · 1 error
See docs/scripts/multitrack_build.md
EOF
}

[ $# -ge 1 ] || { usage >&2; exit 2; }
MTB_CMD=$1; shift
MTB_RC=0
case "$MTB_CMD" in
    enqueue)  [ $# -eq 1 ] || { echo "usage: enqueue <track>" >&2; exit 2; }; cmd_enqueue "$@" || MTB_RC=$? ;;
    status)   [ $# -eq 0 ] || { echo "usage: status" >&2; exit 2; };          cmd_status       || MTB_RC=$? ;;
    run-next) cmd_run_next "$@" || MTB_RC=$? ;;
    dequeue)  [ $# -eq 0 ] || { echo "usage: dequeue" >&2; exit 2; };         cmd_dequeue      || MTB_RC=$? ;;
    help|--help|-h) usage ;;
    *) echo "multitrack_build: unknown command '$MTB_CMD'" >&2; usage >&2; exit 2 ;;
esac
exit "$MTB_RC"
