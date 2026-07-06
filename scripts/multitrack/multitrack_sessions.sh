#!/bin/sh
# =============================================================================
# multitrack_sessions.sh — RB-05 headless-spawn primitive for the multi-track
#     ruler-bridge: programmatically SPAWN / DRIVE / RESUME / STATUS / STOP a
#     per-track headless `claude` worker.
# -----------------------------------------------------------------------------
# Purpose:
#   THE core new primitive that lets the ruler (Track-1 conductor) drive a
#   per-track worker without a human at a terminal. It:
#     (1) sources the RB-02 host-safety AGGREGATE budget guard
#         (multitrack_host_budget.sh) and REFUSES a spawn the guard refuses --
#         there is NO --force / --no-cap escape here (§12.6/§11.4.133);
#     (2) resolves the worker's working directory for the target track via the
#         RB-01 resolver (multitrack_resolve_worktree.sh resolve <alias> ->
#         /mnt/trackN/<project>), overridable by MT_WORKER_CWD / --cwd for
#         device-independent testing (§11.4.3);
#     (3) `unset ANTHROPIC_API_KEY` before launch -- the §2 precedence trap:
#         a live ANTHROPIC_API_KEY overrides subscription/provider auth in
#         `-p` headless mode, silently billing the wrong account;
#     (4) sets the SELECTED alias's auth from the SELECTOR parameters
#         (env MT_WORKER_ALIAS + MT_WORKER_CONFIG_DIR, or --alias/--config-dir)
#         -> CLAUDE_CONFIG_DIR + CLAUDE_CODE_OAUTH_TOKEN. The selector is a
#         FIRST-CLASS parameter: NO alias is hardcoded here. RB-06's balancer
#         chooses/reuses WHICH alias backs each spawn by setting these -- this
#         file does NOT bake any balancing/selection policy;
#     (5) launches `claude -p --output-format stream-json --verbose` (headless),
#         captures the `session_id` from the FIRST system/init event, and reads
#         SUCCESS from the terminal `result` event's `is_error`/`subtype` --
#         AUTHORITATIVELY, NEVER from the process exit code (a worker can exit
#         non-zero on a SUCCESSFUL result and vice-versa);
#     (6) persists {alias, session_id, cwd, pid, status} per track to the
#         agent-registry substrate (append-only events.jsonl + an atomically
#         write-temp-then-rename per-track snapshot, §11.4.116);
#     (7) `resume <session_id>` re-invokes `claude --resume <session_id>` in the
#         SAME cwd + SAME config-dir/env as the spawn (recovered from the
#         registry snapshot) -- the §1 storage-collision gotcha: resume MUST
#         reuse the spawn cwd+config-dir or the session cannot be found.
#
#   CONSTITUTION-LAYER + PROJECT-AGNOSTIC (§11.4.28 / §11.4.35): no project
#   name, no device serial, no package id, no region string, no hardcoded
#   alias. Every project-specific value is env-overridable with honest,
#   documented fallbacks -- never guessed (§11.4.6).
#
#   ANTI-BLUFF / HOST-SAFETY: this file spawns a REAL process (the worker), so
#   the whole thing is proven device-AND-account-INDEPENDENTLY against a MOCK
#   `claude` on the test's scratch PATH (scripts/multitrack/rb05_fixtures/
#   mock_claude.sh) -- NO real `claude`, NO real token, NO network, NO real
#   worker in the test (§11.4.98 / §12.6 / §11.4.133). A real-token smoke is a
#   SEPARATE, later, operator-gated step -- explicitly NOT this file's job.
#
# Usage (EXECUTED, not sourced):
#   multitrack_sessions.sh spawn  <track-alias> [--cwd DIR] [--alias A]
#                                  [--config-dir DIR] [-- <extra claude args>]
#   multitrack_sessions.sh drive  <session_id>  [-- <extra claude args>]
#   multitrack_sessions.sh resume <session_id>  [--cwd DIR] [--alias A]
#                                  [--config-dir DIR] [-- <extra claude args>]
#   multitrack_sessions.sh status [<track-alias>]
#   multitrack_sessions.sh stop   <track-alias|session_id>
#   multitrack_sessions.sh -h | --help
#
# Inputs (env, all optional except where noted):
#   MT_WORKER_ALIAS       auth SELECTOR: which alias's config backs the spawn
#                         (provider or account alias; RB-06 sets this). No
#                         hardcoded default -- absence => rely on the ambient
#                         CLAUDE_CONFIG_DIR / logged-in default.
#   MT_WORKER_CONFIG_DIR  auth SELECTOR: CLAUDE_CONFIG_DIR for the selected
#                         alias (its per-alias config/token store).
#   MT_WORKER_OAUTH_TOKEN optional CLAUDE_CODE_OAUTH_TOKEN for the alias
#                         (NEVER logged -- §11.4.10; redacted in all output).
#   MT_WORKER_CWD         override the resolved worker cwd (testability /
#                         explicit placement). Wins over the RB-01 resolver.
#   MT_SESSIONS_DIR       registry root (events.jsonl + tracks/<track>.json).
#                         Default ${XDG_RUNTIME_DIR:-/tmp}/<repo-basename>/
#                         multitrack/sessions.
#   MT_CLAUDE_BIN         the worker CLI name/path (default `claude`). The test
#                         points this (via PATH) at the mock.
#   MT_SPAWN_TIMEOUT      seconds bound on ONE worker invocation (default 120).
#   MT_REPO_ROOT          consumer project root (else git toplevel from here).
#   HOST_SAFETY_LIB       forwarded to the RB-02 budget guard (host-safety lib).
#
# Outputs: PASS/decision/verdict lines on stdout; a per-invocation captured
#   stream-json transcript + parsed {session_id,is_error,subtype} under the
#   registry dir; append-only events.jsonl; per-track snapshot json.
#
# Side-effects: spawns ONE bounded worker process per spawn/drive/resume;
#   writes ONLY under MT_SESSIONS_DIR; unsets ANTHROPIC_API_KEY in the CHILD
#   env only; NEVER touches a device; NEVER prints a credential.
#
# Dependencies: sh (POSIX), sed, awk, date, mktemp; `timeout` (optional, used
#   if present); constitution/scripts/multitrack/multitrack_host_budget.sh
#   (RB-02, sourced); constitution/scripts/multitrack/multitrack_resolve_worktree.sh
#   (RB-01, invoked as a subprocess for cwd resolution).
#
# Cross-references: docs/superpowers/plans/ruler_bridge_plan.md RB-05;
#   scripts/multitrack/test_multitrack_sessions_spawn.sh (RED/GREEN polarity
#   driver); scripts/multitrack/rb05_fixtures/ (mock_claude.sh + golden fixtures);
#   §11.4.116 (agent-registry events.jsonl + snapshot); §11.4.107(10)
#   (self-validated parser: golden-good accept / golden-bad reject); §11.4.10
#   (credential redaction); §11.4.18 (this doc block); §11.4.35 (constitution
#   layer). Companion doc docs/scripts/multitrack_sessions.md is NOT authored by
#   this PWU (flagged for the conductor -- none of this file's sibling scripts
#   under constitution/scripts/multitrack/ have a docs/scripts/*.md companion
#   either; pre-existing gap, not a regression here).
# =============================================================================

set -u

# ---------------------------------------------------------------------------
# self-location (POSIX $0; sourced-sibling resolution not needed -- executed).
# ---------------------------------------------------------------------------
MTS_SELF=$0
case "$MTS_SELF" in
    */*) MTS_DIR=${MTS_SELF%/*} ;;
    *)   MTS_DIR=. ;;
esac

MTS_BUDGET_LIB="$MTS_DIR/multitrack_host_budget.sh"
MTS_RESOLVER="$MTS_DIR/multitrack_resolve_worktree.sh"

_mts_repo_root() {
    if [ -n "${MT_REPO_ROOT:-}" ]; then printf '%s\n' "$MT_REPO_ROOT"; return 0; fi
    ( cd "$MTS_DIR" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null )
}

MTS_CLAUDE_BIN="${MT_CLAUDE_BIN:-claude}"
MTS_SPAWN_TIMEOUT="${MT_SPAWN_TIMEOUT:-120}"

# registry root (§11.4.116).
_mts_sessions_dir() {
    if [ -n "${MT_SESSIONS_DIR:-}" ]; then printf '%s\n' "$MT_SESSIONS_DIR"; return 0; fi
    _rr=$(_mts_repo_root); _base=$(basename "${_rr:-project}")
    printf '%s\n' "${XDG_RUNTIME_DIR:-/tmp}/$_base/multitrack/sessions"
}
MTS_DIR_REG=$(_mts_sessions_dir)
MTS_EVENTS="$MTS_DIR_REG/events.jsonl"
MTS_TRACKS="$MTS_DIR_REG/tracks"

# ---------------------------------------------------------------------------
# stream-json parser (SELF-VALIDATED, §11.4.107(10)).
#   mts_capture_session_id <stream>  -> print session_id from the FIRST
#       system/init event; exit 3 if none (golden-bad missing_id REJECTED).
#   mts_parse_result <stream>        -> print "<is_error> <subtype>" from the
#       terminal result event; exit 3 if no result OR is_error missing
#       (golden-bad truncated REJECTED).
#   mts_result_ok <stream>           -> AUTHORITATIVE success verdict, read
#       from result.is_error (NOT the process exit code): rc 0 iff a result
#       event exists AND is_error==false.
# ---------------------------------------------------------------------------
_mts_json_str() { sed -n 's/.*"'"$1"'":"\([^"]*\)".*/\1/p' | head -n1; }

# §RB-05 session_id capture from the FIRST system/init event.
mts_capture_session_id() {
    _sid=$(grep '"type":"system"' "$1" 2>/dev/null | grep '"subtype":"init"' \
             | head -n1 | _mts_json_str session_id)
    if [ -z "$_sid" ]; then return 3; fi
    printf '%s\n' "$_sid"
}

mts_parse_result() {
    _rline=$(grep '"type":"result"' "$1" 2>/dev/null | tail -n1)
    [ -n "$_rline" ] || return 3
    _rerr=$(printf '%s\n' "$_rline" | sed -n 's/.*"is_error":\(true\|false\).*/\1/p' | head -n1)
    [ -n "$_rerr" ] || return 3   # truncated result (no is_error) REJECTED
    _rsub=$(printf '%s\n' "$_rline" | _mts_json_str subtype)
    printf '%s %s\n' "$_rerr" "${_rsub:-unknown}"
}

# §RB-05 SUCCESS is read AUTHORITATIVELY from result.is_error, NOT $?.
mts_result_ok() {
    _pr=$(mts_parse_result "$1") || return 3
    _mts_is_error=${_pr%% *}
    if [ "$_mts_is_error" = "false" ]; then return 0; fi
    return 1
}

# ---------------------------------------------------------------------------
# registry helpers (§11.4.116): append-only events.jsonl + atomic per-track snap.
# ---------------------------------------------------------------------------
_mts_now() { date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z"; }
_mts_json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

_mts_event() {
    # $1=event $2=track $3=alias $4=session_id $5=cwd $6=pid $7=is_error $8=subtype $9=status
    mkdir -p "$MTS_DIR_REG" 2>/dev/null || true
    printf '{"ts":"%s","event":"%s","track":"%s","alias":"%s","session_id":"%s","cwd":"%s","pid":"%s","is_error":"%s","subtype":"%s","status":"%s"}\n' \
        "$(_mts_now)" "$1" "$(_mts_json_escape "$2")" "$(_mts_json_escape "$3")" \
        "$(_mts_json_escape "$4")" "$(_mts_json_escape "$5")" "$6" "$7" \
        "$(_mts_json_escape "$8")" "$9" >> "$MTS_EVENTS"
}

_mts_snapshot() {
    # atomic write-temp-then-rename per-track snapshot.
    _t="$1"; _a="$2"; _sid="$3"; _cwd="$4"; _pid="$5"; _st="$6"; _cfg="$7"
    mkdir -p "$MTS_TRACKS" 2>/dev/null || true
    _tmp="$MTS_TRACKS/.$_t.json.tmp.$$"
    printf '{"track":"%s","alias":"%s","session_id":"%s","cwd":"%s","config_dir":"%s","pid":"%s","status":"%s","updated":"%s"}\n' \
        "$(_mts_json_escape "$_t")" "$(_mts_json_escape "$_a")" "$(_mts_json_escape "$_sid")" \
        "$(_mts_json_escape "$_cwd")" "$(_mts_json_escape "$_cfg")" "$_pid" "$_st" "$(_mts_now)" \
        > "$_tmp" && mv -f "$_tmp" "$MTS_TRACKS/$_t.json"
}

# number of live (non-stopped) session records -- the authoritative live-worker
# count handed to the RB-02 budget guard (RB-02 doc: "caller-supplied count").
_mts_live_count() {
    _n=0
    [ -d "$MTS_TRACKS" ] || { printf '0\n'; return 0; }
    for _f in "$MTS_TRACKS"/*.json; do
        [ -e "$_f" ] || continue
        _s=$(grep '"status"' "$_f" 2>/dev/null | _mts_json_str status)
        case "$_s" in stopped|"") : ;; *) _n=$((_n+1)) ;; esac
    done
    printf '%s\n' "$_n"
}

# recover cwd/config-dir/alias for a session_id from the snapshots (resume).
_mts_lookup_by_session() {
    # $1=session_id ; emits "<track>\t<cwd>\t<config_dir>\t<alias>" or rc 3.
    [ -d "$MTS_TRACKS" ] || return 3
    for _f in "$MTS_TRACKS"/*.json; do
        [ -e "$_f" ] || continue
        _fs=$(grep '"session_id"' "$_f" 2>/dev/null | _mts_json_str session_id)
        if [ "$_fs" = "$1" ]; then
            _ft=$(_mts_json_str track < "$_f")
            _fc=$(_mts_json_str cwd < "$_f")
            _fg=$(_mts_json_str config_dir < "$_f")
            _fa=$(_mts_json_str alias < "$_f")
            printf '%s\t%s\t%s\t%s\n' "$_ft" "$_fc" "$_fg" "$_fa"
            return 0
        fi
    done
    return 3
}

# ---------------------------------------------------------------------------
# cwd resolution: MT_WORKER_CWD / --cwd wins; else the RB-01 resolver.
# ---------------------------------------------------------------------------
_mts_resolve_cwd() {
    # $1=track-alias  $2=explicit-cwd-or-empty
    if [ -n "$2" ]; then printf '%s\n' "$2"; return 0; fi
    if [ -n "${MT_WORKER_CWD:-}" ]; then printf '%s\n' "$MT_WORKER_CWD"; return 0; fi
    # RB-01 resolver (invoked as a subprocess; bash script, own interpreter).
    if [ -x "$MTS_RESOLVER" ]; then
        _w=$("$MTS_RESOLVER" resolve "$1" 2>/dev/null) && [ -n "$_w" ] && { printf '%s\n' "$_w"; return 0; }
    fi
    return 3
}

# ---------------------------------------------------------------------------
# the worker launch (shared by spawn / drive / resume). Runs the SELECTED-alias
# auth in the CHILD env only: ANTHROPIC_API_KEY unset (the §2 precedence trap),
# CLAUDE_CONFIG_DIR / CLAUDE_CODE_OAUTH_TOKEN from the selector. Captures the
# newline-delimited stream-json to <stream>. Returns the child's raw exit code
# (which is NOT the success signal -- callers use mts_result_ok).
# ---------------------------------------------------------------------------
_mts_run_worker() {
    _cwd="$1"; _cfg="$2"; _tok="$3"; _stream="$4"; shift 4
    # bounded runtime (§12 host-safety). `timeout` if available, else direct.
    if command -v timeout >/dev/null 2>&1; then _to="timeout $MTS_SPAWN_TIMEOUT"; else _to=""; fi
    (
        cd "$_cwd" 2>/dev/null || exit 97
        unset ANTHROPIC_API_KEY                         # §2 precedence trap
        [ -n "$_cfg" ] && { CLAUDE_CONFIG_DIR="$_cfg"; export CLAUDE_CONFIG_DIR; }
        [ -n "$_tok" ] && { CLAUDE_CODE_OAUTH_TOKEN="$_tok"; export CLAUDE_CODE_OAUTH_TOKEN; }
        # shellcheck disable=SC2086
        exec $_to "$MTS_CLAUDE_BIN" "$@"
    ) > "$_stream" 2>/dev/null
}

# ---------------------------------------------------------------------------
# spawn
# ---------------------------------------------------------------------------
cmd_spawn() {
    _alias_track="${1:-}"; shift 2>/dev/null || true
    [ -n "$_alias_track" ] || { echo "spawn: missing <track-alias>" >&2; return 2; }
    _opt_cwd=""; _opt_cfg="${MT_WORKER_CONFIG_DIR:-}"; _opt_alias="${MT_WORKER_ALIAS:-}"
    _opt_tok="${MT_WORKER_OAUTH_TOKEN:-}"
    while [ $# -gt 0 ]; do
        case "$1" in
            --cwd) _opt_cwd="${2:-}"; shift 2 ;;
            --config-dir) _opt_cfg="${2:-}"; shift 2 ;;
            --alias) _opt_alias="${2:-}"; shift 2 ;;
            --) shift; break ;;
            *) break ;;
        esac
    done

    # (1) RB-02 host-safety budget guard BEFORE any spawn. No --force.
    if [ ! -f "$MTS_BUDGET_LIB" ]; then
        echo "REFUSE: RB-02 budget guard missing ($MTS_BUDGET_LIB) -- no fake-pass (§11.4.6)" >&2
        return 4
    fi
    # shellcheck source=/dev/null
    . "$MTS_BUDGET_LIB"
    _live=$(_mts_live_count)
    _budget=$(mt_host_budget_can_spawn "$_live"); _brc=$?
    printf 'BUDGET: %s\n' "$_budget"
    if [ "$_brc" -ne 0 ]; then
        echo "REFUSE: budget guard rc=$_brc -- spawn refused before launch (§12.6; no-force policy)" >&2
        return "$_brc"
    fi

    # (2) resolve the worker cwd for the track (RB-01 resolver / override).
    _cwd=$(_mts_resolve_cwd "$_alias_track" "$_opt_cwd") || {
        echo "REFUSE: could not resolve worker cwd for '$_alias_track' (set MT_WORKER_CWD/--cwd or a live worktree)" >&2
        return 3
    }

    # (5) launch headless + capture the stream-json transcript.
    _stream="$MTS_DIR_REG/spawn_${_alias_track}_$$.jsonl"
    mkdir -p "$MTS_DIR_REG" 2>/dev/null || true
    _mts_run_worker "$_cwd" "$_opt_cfg" "$_opt_tok" "$_stream" \
        -p --output-format stream-json --verbose "$@"
    _child_rc=$?   # NOT the success signal -- see mts_result_ok.
    _spawn_pid=$$

    # session_id from the first init (mandatory).
    _sid=$(mts_capture_session_id "$_stream") || {
        echo "FAIL: no session_id captured from init (child_rc=$_child_rc)" >&2
        return 6
    }
    _pr=$(mts_parse_result "$_stream") || { echo "FAIL: no terminal result event" >&2; return 6; }
    _is_error=${_pr%% *}; _subtype=${_pr##* }

    # persist (§11.4.116).
    _mts_event spawn "$_alias_track" "$_opt_alias" "$_sid" "$_cwd" "$_spawn_pid" "$_is_error" "$_subtype" running
    _mts_snapshot "$_alias_track" "$_opt_alias" "$_sid" "$_cwd" "$_spawn_pid" running "$_opt_cfg"

    # (5) AUTHORITATIVE success from result.is_error, NEVER $child_rc.
    printf 'SPAWN: track=%s alias=%s session_id=%s cwd=%s is_error=%s subtype=%s child_rc=%s\n' \
        "$_alias_track" "${_opt_alias:-<ambient>}" "$_sid" "$_cwd" "$_is_error" "$_subtype" "$_child_rc"
    if mts_result_ok "$_stream"; then
        echo "OK: spawn SUCCESS read from result.is_error=false (child_rc=$_child_rc ignored)"
        return 0
    fi
    echo "FAIL: worker result.is_error=$_is_error subtype=$_subtype (child_rc=$_child_rc)" >&2
    return 1
}

# ---------------------------------------------------------------------------
# resume -- reuse the SAME cwd + config-dir as the spawn (the §1 gotcha).
# ---------------------------------------------------------------------------
cmd_resume() {
    _sid="${1:-}"; shift 2>/dev/null || true
    [ -n "$_sid" ] || { echo "resume: missing <session_id>" >&2; return 2; }
    _opt_cwd=""; _opt_cfg="${MT_WORKER_CONFIG_DIR:-}"; _opt_tok="${MT_WORKER_OAUTH_TOKEN:-}"; _track=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --cwd) _opt_cwd="${2:-}"; shift 2 ;;
            --config-dir) _opt_cfg="${2:-}"; shift 2 ;;
            --) shift; break ;;
            *) break ;;
        esac
    done
    # recover the spawn cwd+config-dir from the registry (authoritative).
    if _rec=$(_mts_lookup_by_session "$_sid"); then
        _track=$(printf '%s' "$_rec" | cut -f1)
        [ -n "$_opt_cwd" ] || _opt_cwd=$(printf '%s' "$_rec" | cut -f2)
        [ -n "$_opt_cfg" ] || _opt_cfg=$(printf '%s' "$_rec" | cut -f3)
    fi
    [ -n "$_opt_cwd" ] || { [ -n "${MT_WORKER_CWD:-}" ] && _opt_cwd="$MT_WORKER_CWD"; }
    [ -n "$_opt_cwd" ] || { echo "resume: no recorded/explicit cwd for $_sid" >&2; return 3; }

    _stream="$MTS_DIR_REG/resume_$$.jsonl"
    mkdir -p "$MTS_DIR_REG" 2>/dev/null || true
    # §RB-05 resume MUST pass --resume <id> at the recorded cwd.
    _mts_run_worker "$_opt_cwd" "$_opt_cfg" "$_opt_tok" "$_stream" \
        --resume "$_sid" -p --output-format stream-json --verbose "$@"
    _child_rc=$?
    printf 'RESUME: session_id=%s cwd=%s track=%s child_rc=%s\n' "$_sid" "$_opt_cwd" "${_track:-<unknown>}" "$_child_rc"
    if mts_result_ok "$_stream"; then echo "OK: resume SUCCESS (result.is_error=false)"; return 0; fi
    echo "FAIL: resume result not successful (child_rc=$_child_rc)" >&2
    return 1
}

# drive -- same as resume without a leading --resume (continue an interactive
# turn against an already-running session by id + recorded cwd/config).
cmd_drive() { cmd_resume "$@"; }

cmd_status() {
    _want="${1:-}"
    if [ ! -d "$MTS_TRACKS" ]; then echo "status: no sessions registered ($MTS_TRACKS)"; return 0; fi
    for _f in "$MTS_TRACKS"/*.json; do
        [ -e "$_f" ] || continue
        if [ -n "$_want" ]; then
            _t=$(_mts_json_str track < "$_f"); [ "$_t" = "$_want" ] || continue
        fi
        cat "$_f"
    done
}

cmd_stop() {
    _key="${1:-}"; [ -n "$_key" ] || { echo "stop: missing <track-alias|session_id>" >&2; return 2; }
    _f="$MTS_TRACKS/$_key.json"
    if [ ! -e "$_f" ]; then
        if _rec=$(_mts_lookup_by_session "$_key"); then
            _t=$(printf '%s' "$_rec" | cut -f1); _f="$MTS_TRACKS/$_t.json"
        fi
    fi
    [ -e "$_f" ] || { echo "stop: no session record for '$_key'" >&2; return 3; }
    _t=$(_mts_json_str track < "$_f"); _a=$(_mts_json_str alias < "$_f")
    _sid=$(_mts_json_str session_id < "$_f"); _cwd=$(_mts_json_str cwd < "$_f")
    _cfg=$(_mts_json_str config_dir < "$_f"); _pid=$(_mts_json_str pid < "$_f")
    # kill a live worker pid if one is recorded and still alive (bounded).
    if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null; then kill "$_pid" 2>/dev/null || true; fi
    _mts_event stop "$_t" "$_a" "$_sid" "$_cwd" "$_pid" "" "" stopped
    _mts_snapshot "$_t" "$_a" "$_sid" "$_cwd" "$_pid" stopped "$_cfg"
    echo "STOP: track=$_t session_id=$_sid marked stopped"
}

usage() {
    cat >&2 <<'USG'
usage: multitrack_sessions.sh <command> [args]
  spawn  <track-alias> [--cwd DIR] [--alias A] [--config-dir DIR] [-- <claude args>]
  drive  <session_id>  [--cwd DIR] [--config-dir DIR] [-- <claude args>]
  resume <session_id>  [--cwd DIR] [--config-dir DIR] [-- <claude args>]
  status [<track-alias>]
  stop   <track-alias|session_id>
  -h | --help
env selector (RB-06 sets these; NO alias is hardcoded here):
  MT_WORKER_ALIAS  MT_WORKER_CONFIG_DIR  MT_WORKER_OAUTH_TOKEN  MT_WORKER_CWD
USG
}

main() {
    _cmd="${1:-}"; shift 2>/dev/null || true
    case "$_cmd" in
        spawn)  cmd_spawn  "$@" ;;
        drive)  cmd_drive  "$@" ;;
        resume) cmd_resume "$@" ;;
        status) cmd_status "$@" ;;
        stop)   cmd_stop   "$@" ;;
        -h|--help|help|'') usage; [ -n "$_cmd" ] && return 0 || return 2 ;;
        *) usage; return 2 ;;
    esac
}

main "$@"
