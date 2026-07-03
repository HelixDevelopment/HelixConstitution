#!/usr/bin/env bash
# =============================================================================
# multitrack_claim.sh — exactly-once WORK-ITEM CLAIM registry for the multi-track
#                       pipeline (§11.4.176-A). §11.4.147 / §11.4.116 /
#                       §11.4.58 / §11.4.119 / §9.2 / §11.4.10 / §11.4.6.
# -----------------------------------------------------------------------------
# Purpose:
#   Guarantee EXACTLY-ONCE assignment of a workable item (e.g. ATM-NNN / JIRA-123 / any stable id) — or any
#   logical work group — to at most ONE track at a time, so N parallel
#   work-stream tracks (§11.4.58) never both grab the same item and duplicate /
#   clobber each other's work (§9.2 no-codebase-loss). This is the §11.4.176-A
#   "conflict-free-by-construction work-division claim registry", the work-item
#   analogue of the §11.4.119 single-resource-owner device lock.
#
#   Exactly-once, mechanically:
#     * `claim <item-id> <track>` is CHECK-AND-CLAIM inside ONE flock critical
#       section — it SUCCEEDS if the item is free, is IDEMPOTENT if the SAME
#       track re-claims it (refreshes the TTL, exit 0), and is REFUSED (non-zero,
#       exit 3) if a DIFFERENT track already holds it. Two tracks racing for the
#       same item => exactly one wins; the loser gets a clean EBUSY, never a
#       silent double-claim.
#     * TTL-reap (§11.4.147): a claim carries an expiry; a crashed track's claim
#       auto-expires so the item is never held hostage forever. `reap` (and every
#       locked op) drops expired claims first.
#
# Registry (§11.4.116 real-time sync substrate — mirrors the device-lock shape):
#   .ws_state/claims.jsonl      append-only JSONL event stream (CLAIM / RELEASE /
#                               REAP / DENY) — NEVER rewritten (§11.4.116 audit).
#   .ws_state/claims.snapshot   current claims, ATOMICALLY rewritten (temp+rename)
#                               so a lock-free reader never sees a torn write.
#   .ws_state/claims.lock       the flock target for the atomic critical section.
#   Snapshot line: <atm_id>|<track>|<pid>|<acquired_ts>|<expires_ts>
#
# Usage:
#   multitrack_claim.sh claim   <item-id> <track> [--ttl SEC] [--pid PID]
#   multitrack_claim.sh release <item-id> [--track <id>]
#   multitrack_claim.sh owner   <item-id>
#   multitrack_claim.sh status
#   multitrack_claim.sh reap
#   multitrack_claim.sh reconcile           # rebuild snapshot from the JSONL
#   multitrack_claim.sh help
#
# Exit codes: 0 ok · 2 usage · 3 EBUSY (claim: item held by ANOTHER track) /
#             NOT-CLAIMED (owner: no holder) · 5 malformed id/track · 1 internal.
#
# Inputs (env):
#   MT_REPO_ROOT      repo-root override (default: resolved from script dir).
#   MT_WS_STATE       state dir (default <repo>/.ws_state) — TEST points this at
#                     a TEMP copy so the real .ws_state is never touched.
#   MT_CLAIMS_JSONL / MT_CLAIMS_SNAP / MT_CLAIMS_LOCK  path overrides.
#   MT_CLAIM_TTL      default lease seconds (default 86400 = 24h; work items are
#                     long-lived — a short TTL is for testing the reap path).
#   MT_LOCK_WAIT      flock -w seconds (default 10).
#   MT_HOLDER_PID     pid recorded in events (default $PPID).
#
# Outputs:  human-readable lines on stdout; JSONL + snapshot under MT_WS_STATE.
# Side-effects:  writes ONLY under MT_WS_STATE (jsonl + snapshot + lock). NEVER a
#   device, NEVER a disk, NEVER credentials (§11.4.10).
# Dependencies:  bash, awk, flock, date, mkdir, mv.
# Cross-references:  scripts/multitrack/multitrack_device_lock.sh (shape model);
#   scripts/multitrack/multitrack_build.sh (§11.4.167-F build queue sibling);
#   scripts/multitrack/multitrack.sh (entrypoint);
#   scripts/multitrack/test_multitrack_queue_claim.sh (anti-bluff proof);
#   docs/scripts/multitrack_claim.md.
# =============================================================================

set -euo pipefail

MTC_SELF=$0
case "$MTC_SELF" in
    */*) MTC_DIR=${MTC_SELF%/*} ;;
    *)   MTC_DIR=. ;;
esac

MTC_REPO_ROOT=${MT_REPO_ROOT:-$(cd "$MTC_DIR/../.." 2>/dev/null && pwd || printf '.')}
MT_WS_STATE=${MT_WS_STATE:-$MTC_REPO_ROOT/.ws_state}
MTC_EVENTS=${MT_CLAIMS_JSONL:-$MT_WS_STATE/claims.jsonl}
MTC_SNAP=${MT_CLAIMS_SNAP:-$MT_WS_STATE/claims.snapshot}
MTC_LOCK=${MT_CLAIMS_LOCK:-$MT_WS_STATE/claims.lock}
MT_CLAIM_TTL=${MT_CLAIM_TTL:-86400}
MT_LOCK_WAIT=${MT_LOCK_WAIT:-10}
MTC_HOLDER_PID=${MT_HOLDER_PID:-$PPID}

_now() { date +%s; }
_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# JSON-safe: strip embedded double-quotes so the JSONL line stays well-formed.
_jsan() { printf '%s' "${1:-}" | tr '"' "'"; }

# _event EVENT ATM TRACK EXPIRES NOTE -> append one JSONL line (never rewritten).
_event() {
    printf '{"ts":%s,"iso":"%s","event":"%s","atm":"%s","track":"%s","expires":"%s","pid":%s,"note":"%s"}\n' \
        "$(_now)" "$(_iso)" "$(_jsan "$1")" "$(_jsan "$2")" "$(_jsan "$3")" \
        "$(_jsan "$4")" "$MTC_HOLDER_PID" "$(_jsan "$5")" >> "$MTC_EVENTS"
}

_ensure_dirs() {
    mkdir -p "$MT_WS_STATE" 2>/dev/null || { echo "FATAL: cannot create $MT_WS_STATE" >&2; exit 1; }
    [ -e "$MTC_EVENTS" ] || : > "$MTC_EVENTS"
    [ -e "$MTC_SNAP" ]   || : > "$MTC_SNAP"
    [ -e "$MTC_LOCK" ]   || : > "$MTC_LOCK"
}

# Reject empty / '|' / whitespace-bearing tokens (would corrupt the snapshot).
_validate_tok() {
    _vt_what=$1; _vt_val=$2
    [ -n "$_vt_val" ] || { echo "usage: $_vt_what must be non-empty" >&2; exit 2; }
    case "$_vt_val" in
        *"|"*)  echo "invalid $_vt_what '$_vt_val': contains '|' (snapshot delimiter)" >&2; exit 5 ;;
        *[!A-Za-z0-9._/-]*) echo "invalid $_vt_what '$_vt_val': only [A-Za-z0-9._/-] allowed" >&2; exit 5 ;;
    esac
}

# --- snapshot helpers (ALL callers hold the flock; writes are atomic) ---------
_reap() {  # drop expired claims; emit REAP events. (inside lock)
    _rp_now=$(_now)
    [ -s "$MTC_SNAP" ] || return 0
    _rp_tmp="$MTC_SNAP.tmp.$$"
    : > "$_rp_tmp"
    while IFS='|' read -r _rp_atm _rp_track _rp_pid _rp_acq _rp_exp; do
        [ -n "$_rp_atm" ] || continue
        if [ "${_rp_exp:-0}" -le "$_rp_now" ]; then
            _event REAP "$_rp_atm" "$_rp_track" "$_rp_exp" "claim-expired-ttl-elapsed"
        else
            printf '%s|%s|%s|%s|%s\n' "$_rp_atm" "$_rp_track" "$_rp_pid" "$_rp_acq" "$_rp_exp" >> "$_rp_tmp"
        fi
    done < "$MTC_SNAP"
    mv -f "$_rp_tmp" "$MTC_SNAP"
}

# prints the owning track for an atm id (empty if unclaimed). (post-reap)
_owner_of() { awk -F'|' -v a="$1" '$1==a{print $2; exit}' "$MTC_SNAP" 2>/dev/null || true; }

# --- commands -----------------------------------------------------------------
cmd_claim() {
    _cl_atm=$1; _cl_track=$2; _cl_ttl=${3:-$MT_CLAIM_TTL}
    _validate_tok "item-id" "$_cl_atm"
    _validate_tok "track"  "$_cl_track"
    _ensure_dirs
    _cl_rc=0
    (
        flock -w "$MT_LOCK_WAIT" 9 || { echo "FATAL: claim registry busy (flock timeout)" >&2; exit 1; }
        _reap
        _cl_owner=$(_owner_of "$_cl_atm")
        _cl_now=$(_now); _cl_exp=$(( _cl_now + _cl_ttl ))
        # ---- exactly-once GUARD: an item held by ANOTHER track is REFUSED. This
        # is the load-bearing §11.4.176-A invariant; the paired §1.1 mutation
        # (test_multitrack_queue_claim.sh) strips exactly this block and proves a
        # guard-less registry double-claims (owner flips to the 2nd track).
        # >>MT_CLAIM_MUT_EXACTLYONCE (paired §1.1 mutation target — do NOT remove marker)
        if [ -n "$_cl_owner" ] && [ "$_cl_owner" != "$_cl_track" ]; then
            _event DENY "$_cl_atm" "$_cl_track" "" "held-by:$_cl_owner requester:$_cl_track"
            echo "EBUSY: $_cl_atm is already claimed by track '$_cl_owner' — NOT re-claiming for '$_cl_track' (exactly-once §11.4.176-A)" >&2
            exit 3
        fi
        # <<MT_CLAIM_MUT_EXACTLYONCE
        if [ -z "$_cl_owner" ]; then
            # ---- free -> claim the WHOLE item atomically (single snapshot rewrite)
            {
                if [ -s "$MTC_SNAP" ]; then cat "$MTC_SNAP"; fi
                printf '%s|%s|%s|%s|%s\n' "$_cl_atm" "$_cl_track" "$MTC_HOLDER_PID" "$_cl_now" "$_cl_exp"
            } > "$MTC_SNAP.tmp.$$" && mv -f "$MTC_SNAP.tmp.$$" "$MTC_SNAP"
            _event CLAIM "$_cl_atm" "$_cl_track" "$_cl_exp" "ttl=$_cl_ttl claimed"
            printf 'CLAIMED: %s -> track %s (ttl=%ss expires=%s)\n' "$_cl_atm" "$_cl_track" "$_cl_ttl" "$_cl_exp"
            exit 0
        else
            # ---- reached ONLY when owner == track (guard let it through), so this
            # is an IDEMPOTENT refresh: overwrite the row with the requesting track
            # (identical owner) + fresh TTL. If the guard above is MUTATED away, a
            # different track reaches here and this overwrite flips the owner —
            # exactly the double-claim the paired §1.1 mutation must catch.
            awk -F'|' -v a="$_cl_atm" -v t="$_cl_track" -v p="$MTC_HOLDER_PID" -v n="$_cl_now" -v e="$_cl_exp" \
                'BEGIN{OFS="|"}{ if($1==a){$2=t;$3=p;$4=n;$5=e} print }' \
                "$MTC_SNAP" > "$MTC_SNAP.tmp.$$" && mv -f "$MTC_SNAP.tmp.$$" "$MTC_SNAP"
            _event CLAIM "$_cl_atm" "$_cl_track" "$_cl_exp" "ttl=$_cl_ttl idempotent-refresh"
            printf 'ALREADY-OWNED (idempotent): %s already held by track %s — TTL refreshed (expires=%s)\n' \
                "$_cl_atm" "$_cl_track" "$_cl_exp"
            exit 0
        fi
    ) 9<"$MTC_LOCK" || _cl_rc=$?
    return "$_cl_rc"
}

cmd_release() {
    _rl_atm=$1; _rl_track=${2:-}
    _validate_tok "item-id" "$_rl_atm"
    _ensure_dirs
    _rl_rc=0
    (
        flock -w "$MT_LOCK_WAIT" 9 || { echo "FATAL: claim registry busy (flock timeout)" >&2; exit 1; }
        _reap
        _rl_owner=$(_owner_of "$_rl_atm")
        if [ -z "$_rl_owner" ]; then
            printf 'NOT-CLAIMED: %s has no active claim (nothing to release)\n' "$_rl_atm"
            exit 0
        fi
        if [ -n "$_rl_track" ] && [ "$_rl_track" != "$_rl_owner" ]; then
            echo "REFUSED: $_rl_atm is held by '$_rl_owner', not '$_rl_track' — refusing cross-track release" >&2
            exit 3
        fi
        awk -F'|' -v a="$_rl_atm" '$1!=a{print}' "$MTC_SNAP" > "$MTC_SNAP.tmp.$$" \
            && mv -f "$MTC_SNAP.tmp.$$" "$MTC_SNAP"
        _event RELEASE "$_rl_atm" "$_rl_owner" "" "released"
        printf 'RELEASED: %s (was held by track %s)\n' "$_rl_atm" "$_rl_owner"
    ) 9<"$MTC_LOCK" || _rl_rc=$?
    return "$_rl_rc"
}

cmd_owner() {
    _ow_atm=$1
    _validate_tok "item-id" "$_ow_atm"
    _ensure_dirs
    _ow_rc=0
    (
        flock -w "$MT_LOCK_WAIT" 9 || { echo "FATAL: claim registry busy (flock timeout)" >&2; exit 1; }
        _reap
        _ow_owner=$(_owner_of "$_ow_atm")
        if [ -n "$_ow_owner" ]; then
            printf '%s\n' "$_ow_owner"
            exit 0
        fi
        echo "NOT-CLAIMED: no active claim for $_ow_atm" >&2
        exit 3
    ) 9<"$MTC_LOCK" || _ow_rc=$?
    return "$_ow_rc"
}

cmd_status() {
    _ensure_dirs
    _st_rc=0
    (
        flock -w "$MT_LOCK_WAIT" 9 || { echo "FATAL: claim registry busy (flock timeout)" >&2; exit 1; }
        _reap
        printf '== work-item claims (%s) ==\n' "$MTC_SNAP"
        if [ -s "$MTC_SNAP" ]; then
            _st_now=$(_now)
            printf 'ITEM-ID              TRACK        PID     REMAINING\n'
            awk -F'|' -v now="$_st_now" '{ rem=$5-now; if(rem<0)rem=0;
                printf "%-20s %-12s %-7s %ss\n", $1, $2, $3, rem }' "$MTC_SNAP"
        else
            printf '(no active claims)\n'
        fi
    ) 9<"$MTC_LOCK" || _st_rc=$?
    return "$_st_rc"
}

cmd_reap() {
    _ensure_dirs
    _rp_rc=0
    ( flock -w "$MT_LOCK_WAIT" 9 || exit 1; _reap; echo "REAP: expired claims dropped (see claims.jsonl)"; ) 9<"$MTC_LOCK" || _rp_rc=$?
    return "$_rp_rc"
}

cmd_reconcile() {
    # Rebuild the snapshot from the append-only JSONL (§11.4.116 recovery path):
    # replay in order, keep the last CLAIM per atm, drop RELEASE/REAP'd; then reap.
    _ensure_dirs
    _rc_rc=0
    ( flock -w "$MT_LOCK_WAIT" 9 || exit 1
      awk '
        function val(line,key,   re,s,q){ re="\""key"\":\""; if(match(line,re)){ s=substr(line,RSTART+length(re)); q=index(s,"\""); return substr(s,1,q-1)} return "" }
        {
          ev=val($0,"event"); atm=val($0,"atm"); tr=val($0,"track"); exp=val($0,"expires"); pid=val($0,"pid"); ts=val($0,"ts")
          if(ev=="CLAIM"){ hold[atm]=tr; e[atm]=exp; p[atm]=pid; a[atm]=ts }
          else if(ev=="RELEASE"||ev=="REAP"){ if(atm!="") delete hold[atm] }
        }
        END{ for(x in hold) if(x!="") printf "%s|%s|%s|%s|%s\n", x, hold[x], p[x], a[x], e[x] }
      ' "$MTC_EVENTS" > "$MTC_SNAP.tmp.$$" && mv -f "$MTC_SNAP.tmp.$$" "$MTC_SNAP"
      _reap
      echo "RECONCILE: snapshot rebuilt from $MTC_EVENTS"
    ) 9<"$MTC_LOCK" || _rc_rc=$?
    return "$_rc_rc"
}

usage() {
cat <<'EOF'
multitrack_claim.sh — exactly-once work-item claim registry (§11.4.176-A)

  claim   <item-id> <track> [--ttl SEC] [--pid PID]
                       claim an item for a track. Free -> CLAIMED. Same track ->
                       idempotent (refresh TTL). Other track -> EBUSY (exit 3).
  release <item-id> [--track <id>]   release a claim (optionally guard by owner)
  owner   <item-id>     print the owning track (exit 3 if unclaimed)
  status               list all active claims + remaining TTL
  reap                 drop expired claims (§11.4.147 crashed-track recovery)
  reconcile            rebuild the snapshot from the append-only JSONL
  help                 this help

Env : MT_WS_STATE  MT_CLAIM_TTL  MT_LOCK_WAIT  MT_CLAIMS_SNAP  MT_CLAIMS_JSONL
Exit: 0 ok · 2 usage · 3 EBUSY/not-claimed · 5 bad id/track · 1 error
See docs/scripts/multitrack_claim.md
EOF
}

[ $# -ge 1 ] || { usage >&2; exit 2; }
MTC_CMD=$1; shift

# parse flags out of the positional stream (--ttl / --pid / --track)
MTC_TTL=""; MTC_TRACKOPT=""; MTC_POS=""
while [ $# -gt 0 ]; do
    case "$1" in
        --ttl)   MTC_TTL=$2; shift ;;
        --ttl=*) MTC_TTL=${1#--ttl=} ;;
        --pid)   MTC_HOLDER_PID=$2; shift ;;
        --pid=*) MTC_HOLDER_PID=${1#--pid=} ;;
        --track)   MTC_TRACKOPT=$2; shift ;;
        --track=*) MTC_TRACKOPT=${1#--track=} ;;
        --*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
        *) MTC_POS="$MTC_POS $1" ;;
    esac
    shift
done
# shellcheck disable=SC2086  # deliberate re-split of the collected positionals
set -- $MTC_POS

MTC_RC=0
case "$MTC_CMD" in
    claim)
        [ $# -eq 2 ] || { echo "usage: claim <item-id> <track> [--ttl SEC] [--pid PID]" >&2; exit 2; }
        cmd_claim "$1" "$2" "${MTC_TTL:-$MT_CLAIM_TTL}" || MTC_RC=$? ;;
    release)
        [ $# -eq 1 ] || { echo "usage: release <item-id> [--track <id>]" >&2; exit 2; }
        cmd_release "$1" "$MTC_TRACKOPT" || MTC_RC=$? ;;
    owner)
        [ $# -eq 1 ] || { echo "usage: owner <item-id>" >&2; exit 2; }
        cmd_owner "$1" || MTC_RC=$? ;;
    status)    [ $# -eq 0 ] || { echo "usage: status" >&2; exit 2; };    cmd_status    || MTC_RC=$? ;;
    reap)      [ $# -eq 0 ] || { echo "usage: reap" >&2; exit 2; };      cmd_reap      || MTC_RC=$? ;;
    reconcile) [ $# -eq 0 ] || { echo "usage: reconcile" >&2; exit 2; }; cmd_reconcile || MTC_RC=$? ;;
    help|--help|-h) usage ;;
    *) echo "multitrack_claim: unknown command '$MTC_CMD'" >&2; usage >&2; exit 2 ;;
esac
exit "$MTC_RC"
