#!/bin/sh
# =============================================================================
# multitrack_conductor_monitor_autoarm.sh
#     — OUT-OF-THE-BOX conductor-session fallback-monitor auto-arm
#       (§11.4.187 automatic multi-track ruler orchestration; the CONDUCTOR-side
#        analogue of the cwd-hook's §4.2(C) track-worker monitor-auto-start).
# -----------------------------------------------------------------------------
# Purpose:
#   `multitrack-up` auto-arms a per-alias rate-limit fallback monitor for every
#   TRACK-WORKER session it launches (via multitrack_cwd_hook.sh's
#   _cwh_monitor_start). But the CONDUCTOR session is NEVER launched by
#   multitrack-up — the operator starts it directly in the main checkout — so it
#   gets NO monitor, and its `multitrack_fallback_monitor.sh` had to be started
#   by hand. If the conductor's own alias then hit a usage/rate limit, the
#   fallback did NOT fire out of the box (operator mandate 2026-07-10: "the
#   multi-track fallback MUST work OUT OF THE BOX, no operator reminder,
#   switching to the first WORKING native Claude alias FIRST").
#
#   This helper closes that gap. Run as a SessionStart hook (see
#   `.claude/settings.json` in the consuming project), it arms — idempotently,
#   read-only, fully non-fatal — exactly ONE fallback monitor for the conductor
#   session, tailing the conductor's OWN newest transcript for the DESIGN §4.2(C)
#   rate-limit signature. On a genuine quota-exhausted limit the monitor fires
#   `orchestrator fallback --track <conductor-track>`, which rebinds that track
#   to the next healthy alias — NATIVE-FIRST per multitrack_alias_orchestrator.sh
#   (operator mandate). Everything else it needs (alias, track, transcript) is
#   DERIVED deterministically (§11.4.6 — never guessed) from CLAUDE_CONFIG_DIR +
#   the project directory.
#
#   Project-agnostic (§11.4.177 / §11.4.28): hardcodes no project path, no track
#   layout, no alias set. Consumers invoke it BY REFERENCE from the constitution
#   submodule; it is never copied into a project.
#
# Usage:
#   multitrack_conductor_monitor_autoarm.sh            # arm (SessionStart hook)
#   multitrack_conductor_monitor_autoarm.sh -h|--help  # show this header
#
# Inputs (env, all optional — every one has a safe deterministic default):
#   CLAUDE_CONFIG_DIR   source of the live alias (basename `.claude-<alias>`) AND
#                       the transcript root ($CLAUDE_CONFIG_DIR/projects/<enc>/).
#                       Unset / non-`.claude-*` -> alias UNKNOWN -> honest NOTE +
#                       clean skip (never a guessed alias, never silent).
#   CLAUDE_PROJECT_DIR  the conductor's project dir (preferred); else $PWD. Used
#                       to derive BOTH the track and the transcript encoding.
#   MT_CONDUCTOR_TRACK  override the derived track (honest testability hook).
#   MT_CONDUCTOR_DIR    override the derived project dir (testability hook).
#   MT_CONDUCTOR_MONITOR override the fallback-monitor path (else sibling; else
#                       PATH) — mirrors the monitor's own MT_ORCHESTRATOR pattern.
#   MT_CONDUCTOR_POLL_TRIES  transcript-wait attempts (default 3).
#   MT_CONDUCTOR_POLL_SLEEP  seconds between attempts (default 1).
#   MT_CONDUCTOR_LOG    override the evidence log path (else
#                       <dir>/qa-results/multitrack/conductor_autoarm_<ts>.log,
#                       else a tmp fallback).
#   MULTITRACK_DISABLE=1  escape hatch: honest NOTE + clean skip.
#
# Track derivation (§11.4.111 resolve-by-stable-name): a project dir under
#   `/mnt/track<N>/...` -> `track-<N>`; anything else -> `track-1` (the conductor
#   default — the main checkout is Track 1). MT_CONDUCTOR_TRACK overrides.
#
# Outputs: `[autoarm] <iso-ts> <EVENT> ...` lines to stdout AND the evidence log.
#   EVENTs: STARTED (monitor launched) / ALREADY (idempotent skip — a monitor is
#   already live) / NOTE (no transcript yet after polling, unknown alias, disabled,
#   or monitor missing — a non-silent, non-fatal skip). NEVER a silent no-op
#   (§11.4.6): every skip path emits a NOTE naming the reason.
#
# Exit status: ALWAYS 0. This runs as a SessionStart hook and MUST NEVER fail a
#   session. The observable outcome is the STARTED/ALREADY/NOTE evidence line,
#   not the exit code (tests assert on the emitted line, per §11.4.6).
#
# Side-effects: NONE on any device / repo. Read-only on the transcript (the
#   monitor tails it, never writes). The ONLY writes are (a) this helper's own
#   evidence log and (b) the detached monitor's own log — both under
#   qa-results/multitrack/ (§11.4.89), tmp-fallback when unwritable. Idempotent:
#   a pgrep guard on the daemon's own argv means never a 2nd monitor per
#   (alias,track).
#
# Dependencies: POSIX sh, date; pgrep (optional idempotency guard), ls, tr,
#   mkdir, nohup; multitrack_fallback_monitor.sh (sibling, `--daemon`).
#
# Cross-references:
#   constitution/scripts/multitrack/multitrack_fallback_monitor.sh (the daemon)
#   constitution/scripts/multitrack/multitrack_cwd_hook.sh (_cwh_monitor_async —
#     the track-worker analogue this mirrors)
#   constitution/scripts/multitrack/multitrack_alias_orchestrator.sh (fallback →
#     native-first _next_available_alias)
#   constitution/scripts/multitrack/track_label_audit.sh (_tla_live_alias — same
#     CLAUDE_CONFIG_DIR basename `.claude-<alias>` derivation reused here)
#   docs/scripts/multitrack_conductor_monitor_autoarm.md (external guide, §11.4.18)
#   §11.4.187 auto multi-track ruler · §11.4.177 project-decoupled tooling ·
#   §11.4.128 observer-effect budget · §11.4.6 no-guessing / never-silent
# =============================================================================

set -u

# --- self location (for the sibling fallback monitor) ------------------------
_aa_self="$0"
case "$_aa_self" in
    */*) _aa_dir=${_aa_self%/*} ;;
    *)   _aa_dir=. ;;
esac
_aa_dir=$(cd "$_aa_dir" 2>/dev/null && pwd)
[ -n "$_aa_dir" ] || _aa_dir=.

_aa_now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%SZ; }
_aa_now_epoch() { date +%s 2>/dev/null || echo 0; }

# --- evidence log (owned by this helper; never the device-under-test) --------
_aa_log_init() {  # $1 = project dir (for the default log location)
    if [ -n "${MT_CONDUCTOR_LOG:-}" ]; then AA_LOG="$MT_CONDUCTOR_LOG"; return 0; fi
    _ld="$1/qa-results/multitrack"
    if mkdir -p "$_ld" 2>/dev/null; then
        AA_LOG="$_ld/conductor_autoarm_$(_aa_now_epoch).log"
    else
        _ld="${TMPDIR:-/tmp}/multitrack_conductor_autoarm"
        mkdir -p "$_ld" 2>/dev/null || _ld="${TMPDIR:-/tmp}"
        AA_LOG="$_ld/conductor_autoarm_$(_aa_now_epoch).log"
    fi
}

# _aa_emit EVENT MESSAGE... -> one line to BOTH stdout and the evidence log.
_aa_emit() {
    _ev="$1"; shift
    _line="[autoarm] $(_aa_now_iso) $_ev $*"
    printf '%s\n' "$_line"
    [ -n "${AA_LOG:-}" ] && printf '%s\n' "$_line" >> "$AA_LOG" 2>/dev/null || true
}

# --- derive the live toolkit alias from CLAUDE_CONFIG_DIR basename ------------
#     `.claude-<alias>` (same rule as track_label_audit.sh:_tla_live_alias and
#     the reference labeler). Unset / non-`.claude-*` -> `?` (honest UNKNOWN).
_aa_live_alias() {
    _cd="${CLAUDE_CONFIG_DIR:-}"
    [ -n "$_cd" ] || { printf '%s' '?'; return; }
    _base="${_cd%/}"
    _base="${_base##*/}"
    case "$_base" in
        .claude-?*) printf '%s' "${_base#.claude-}" ;;
        *)          printf '%s' '?' ;;
    esac
}

# --- derive the conductor track from the project dir (§11.4.111) --------------
#     /mnt/track<N>/... -> track-<N> ; anything else -> track-1 (conductor).
_aa_derive_track() {  # $1 = project dir
    if [ -n "${MT_CONDUCTOR_TRACK:-}" ]; then printf '%s' "$MT_CONDUCTOR_TRACK"; return; fi
    case "$1" in
        /mnt/track[0-9]*/*|/mnt/track[0-9]*)
            _rest=${1#/mnt/track}      # "<N>/..." or "<N>"
            _n=${_rest%%/*}            # "<N>"
            case "$_n" in
                *[!0-9]*|'') printf '%s' 'track-1' ;;   # not a bare number -> default
                *)           printf '%s' "track-$_n" ;;
            esac ;;
        *) printf '%s' 'track-1' ;;
    esac
}

# --- resolve the fallback-monitor path (env override FIRST, then sibling) -----
_aa_resolve_monitor() {
    if [ -n "${MT_CONDUCTOR_MONITOR:-}" ]; then
        if [ -r "$MT_CONDUCTOR_MONITOR" ]; then printf '%s' "$MT_CONDUCTOR_MONITOR"; return 0; fi
        if command -v "$MT_CONDUCTOR_MONITOR" >/dev/null 2>&1; then command -v "$MT_CONDUCTOR_MONITOR"; return 0; fi
        return 1
    fi
    _sib="$_aa_dir/multitrack_fallback_monitor.sh"
    if [ -r "$_sib" ]; then printf '%s' "$_sib"; return 0; fi
    if command -v multitrack_fallback_monitor.sh >/dev/null 2>&1; then
        command -v multitrack_fallback_monitor.sh; return 0
    fi
    return 1
}

# --- main --------------------------------------------------------------------
_aa_main() {
    _dir="${MT_CONDUCTOR_DIR:-${CLAUDE_PROJECT_DIR:-$PWD}}"
    _aa_log_init "$_dir"

    if [ "${MULTITRACK_DISABLE:-0}" = "1" ]; then
        _aa_emit NOTE "MULTITRACK_DISABLE=1 — conductor monitor not armed (escape hatch)"
        return 0
    fi

    _alias="$(_aa_live_alias)"
    if [ "$_alias" = "?" ]; then
        _aa_emit NOTE "alias UNKNOWN (CLAUDE_CONFIG_DIR unset or not .claude-*) — cannot arm monitor without a real alias (never guessed, §11.4.6)"
        return 0
    fi

    _track="$(_aa_derive_track "$_dir")"

    _mon="$(_aa_resolve_monitor)" || {
        _aa_emit NOTE "fallback monitor not found (set MT_CONDUCTOR_MONITOR) — conductor monitor not armed for alias=$_alias track=$_track"
        return 0
    }
    _mon_base="$(basename "$_mon")"

    # Idempotency: one monitor per (alias,track). If one is already live, done.
    if command -v pgrep >/dev/null 2>&1; then
        if pgrep -f "$_mon_base --daemon --alias $_alias --track $_track" >/dev/null 2>&1; then
            _aa_emit ALREADY "monitor already live for alias=$_alias track=$_track (idempotent — no 2nd start)"
            return 0
        fi
    fi

    # Transcript: newest *.jsonl under $CLAUDE_CONFIG_DIR/projects/<enc>/ where
    # <enc> = the project dir with every '/'→'-' (Claude Code transcript-dir
    # convention). Poll BRIEFLY for it (a fresh session may not have flushed the
    # first line yet) — never a silent no-op if still absent (§11.4.6).
    _ccdir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
    _enc="$(printf '%s' "$_dir" | tr '/' '-')"
    _projdir="$_ccdir/projects/$_enc"
    _tries="${MT_CONDUCTOR_POLL_TRIES:-3}"
    _sleep="${MT_CONDUCTOR_POLL_SLEEP:-1}"
    _tp=""
    _i=0
    while [ "$_i" -lt "$_tries" ]; do
        _tp="$(ls -1t "$_projdir"/*.jsonl 2>/dev/null | head -n1 || true)"
        [ -n "$_tp" ] && break
        _i=$((_i + 1))
        [ "$_i" -lt "$_tries" ] && [ "$_sleep" -gt 0 ] 2>/dev/null && sleep "$_sleep" 2>/dev/null || true
    done
    if [ -z "$_tp" ]; then
        _aa_emit NOTE "no transcript yet under $_projdir after ${_tries} poll(s) — conductor monitor NOT armed this session (will arm on next SessionStart once a transcript exists); alias=$_alias track=$_track"
        return 0
    fi

    _logdir="$_dir/qa-results/multitrack"
    mkdir -p "$_logdir" 2>/dev/null || _logdir="${TMPDIR:-/tmp}/multitrack_monitor_logs"
    mkdir -p "$_logdir" 2>/dev/null || true
    _monlog="$_logdir/monitor_${_alias}_$(_aa_now_epoch).log"

    # Launch ONE detached daemon (READ-ONLY tail; §11.4.128 observer-effect).
    nohup sh "$_mon" --daemon --alias "$_alias" --track "$_track" --transcript "$_tp" \
        >"$_monlog" 2>&1 &
    _aa_emit STARTED "conductor fallback monitor armed: alias=$_alias track=$_track transcript=$_tp monlog=$_monlog"
    return 0
}

case "${1:-}" in
    -h|--help) grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//' | head -80 ;;
    *)         _aa_main ;;
esac
exit 0
