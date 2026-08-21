#!/bin/sh
# =============================================================================
# independence_tier.sh — host-boundary detector + honest tier degradation
#                        (T117, spec 002; FR-033/FR-034)
# =============================================================================
#
# WHAT THIS ANSWERS: "what independence tier was ACHIEVED on THIS host?" — a
# MEASUREMENT. seam_tier_table.sh answers "what tier does this seam REQUIRE?" —
# a POLICY statement. Conflating the two is the exact theatre this feature
# exists to prevent: a seam that REQUIRES capability separation, on a host where
# none EXISTS, must record `instance` and say so. An unfulfilled `capability`
# claim is worse than an honest `instance` one, because a reader who trusts the
# record then believes a boundary is protecting them that is not there.
#
# THE MEASUREMENT (research D-4): a capability boundary exists for a store when
# the store is owned by a uid OTHER than the producer's AND the producer cannot
# write it. On a single-uid host neither half can be arranged by an agent —
# ownership defeats ACLs, the append-only attribute needs privilege the agent
# lacks, and any key the producer can use it can also read. So on such a host
# this detector reports ABSENT, every time, correctly.
#
# THE DETECTOR'S OWN CONTROL NEEDLE (§11.4.201(7)(b)) — load-bearing: a detector
# that is simply BROKEN also reports "no boundary". Those two states are
# indistinguishable from the outside, and reporting the second as the first is a
# false null. So before ANY absence is reported, the SAME code path is run
# against a KNOWN-PRESENT boundary (a root-owned, non-producer-writable path —
# /etc/passwd by default, overridable via ITIER_NEEDLE_PATH). Needle found =>
# an absence is a real absence. Needle NOT found => the detector reports itself
# BLIND (rc 3) and NEVER reports `instance`.
#
# TRIPWIRE (FR-036, observable filesystem state): when CBG_CAPABILITY_TRIPWIRE
# names a path, ENTERING the capability path touches it. Scenario S9 asserts the
# marker is ABSENT after an ordinary seam — an observable state check, not a
# "was the function called" assertion that a refactor can quietly satisfy.
#
# Usage (executed):
#   sh independence_tier.sh detect <store_path>        -> rc 0 present / 1 absent / 3 blind
#   sh independence_tier.sh achieved <seam> <store>    -> prints instance|capability
#   sh independence_tier.sh --selftest
# Usage (sourced):
#   . independence_tier.sh ; itier_detect_boundary <store> ; itier_achieved <seam> <store>
#
# POSIX sh; `sh -n` AND `bash -n` clean; every variable `_itier_`/`ITIER_`
# prefixed (§11.4.67 safe-sourced-lib discipline).
# =============================================================================

ITIER_NEEDLE_PATH=${ITIER_NEEDLE_PATH:-/etc/passwd}

_itier_tripwire() {   # record that the capability path was ENTERED
    [ -n "${CBG_CAPABILITY_TRIPWIRE:-}" ] || return 0
    : > "$CBG_CAPABILITY_TRIPWIRE" 2>/dev/null || true
    return 0
}

# --- the raw boundary predicate, applied to ONE path -------------------------
# rc 0 = boundary present, 1 = absent, 2 = path unusable (cannot be measured).
_itier_boundary_raw() {  # <path>
    _itier_p="${1:-}"
    [ -n "$_itier_p" ] || return 2
    [ -e "$_itier_p" ] || return 2
    _itier_owner=$(stat -c '%u' "$_itier_p" 2>/dev/null) || return 2
    [ -n "$_itier_owner" ] || return 2
    _itier_me=$(id -u 2>/dev/null) || return 2
    # BOTH halves are required. Owned-by-another-uid but world-writable is not a
    # boundary; owned-by-me but chmod 444 is not one either (I can chmod it back).
    if [ "$_itier_owner" != "$_itier_me" ] && [ ! -w "$_itier_p" ]; then
        return 0
    fi
    return 1
}

# --- the public detector: needle FIRST, then the subject ---------------------
itier_detect_boundary() {  # <store_path> -> rc 0 present / 1 absent / 3 BLIND
    _itier_store="${1:-}"
    _itier_tripwire
    # (1) CONTROL NEEDLE — same function, same host, a boundary known to exist.
    _itier_boundary_raw "$ITIER_NEEDLE_PATH"
    _itier_needle_rc=$?
    if [ "$_itier_needle_rc" -ne 0 ]; then
        printf '[itier] BLIND detector could not see a KNOWN-PRESENT boundary at needle=%s (raw rc=%s, uid=%s) — refusing to report an absence, because a broken detector and a boundary-less host look identical from here (§11.4.201(7)(b))\n' \
            "$ITIER_NEEDLE_PATH" "$_itier_needle_rc" "$(id -u 2>/dev/null)" >&2
        return 3
    fi
    # (2) the SUBJECT — only now is an absence meaningful.
    _itier_boundary_raw "$_itier_store"
    _itier_sub_rc=$?
    case "$_itier_sub_rc" in
        0) return 0 ;;
        1) return 1 ;;
        *) printf '[itier] BLIND store path not measurable: %s (raw rc=%s)\n' "$_itier_store" "$_itier_sub_rc" >&2
           return 3 ;;
    esac
}

# --- the achieved tier -------------------------------------------------------
# ALWAYS the measured value. The seam's REQUIRED tier is deliberately NOT an
# input here: a requirement cannot conjure a boundary, and letting it do so is
# precisely the claim this file refuses to let anyone make.
itier_achieved() {  # <seam_id> <store_path> -> prints instance|capability ; rc 0/3
    _itier_seam="${1:-}"
    _itier_st="${2:-}"
    itier_detect_boundary "$_itier_st"
    _itier_rc=$?
    case "$_itier_rc" in
        0) printf 'capability\n'; return 0 ;;
        1) printf 'instance\n';   return 0 ;;
        *) printf 'blind\n';      return 3 ;;
    esac
}

# --- may a row CLAIM `capability`? ------------------------------------------
# rc 0 = the claim is supported by a measured boundary; 1 = it is NOT (refuse);
# 3 = the detector is blind, so the claim cannot be adjudicated (refuse, and say
# which of the two it is — one sends an operator to fix a host, the other to fix
# an instrument, and calling one the other is a false accusation).
itier_claim_supported() {  # <claimed_tier> <store_path>
    _itier_claim="${1:-}"
    _itier_cst="${2:-}"
    case "$_itier_claim" in
        capability) : ;;
        *) return 0 ;;   # only `capability` needs a host boundary behind it
    esac
    itier_detect_boundary "$_itier_cst"
    return $?
}

# --- self-check (§11.4.107(10)) ---------------------------------------------
_itier_selftest() {
    _itier_trc=0
    _it_ok()  { printf '  PASS %s\n' "$1"; }
    _it_bad() { printf '  FAIL %s\n' "$1" >&2; _itier_trc=1; }
    _itier_tmp=$(mktemp -d) || return 2

    # (N) NEEDLE: the detector CAN see a real, known-present boundary.
    _itier_boundary_raw "$ITIER_NEEDLE_PATH"
    if [ $? -eq 0 ]; then _it_ok "NEEDLE detector sees the known-present boundary at $ITIER_NEEDLE_PATH"
    else _it_bad "NEEDLE detector CANNOT see the known-present boundary at $ITIER_NEEDLE_PATH — every absence below would be a false null"; fi

    # (1) a self-owned, self-writable store => boundary ABSENT (the real case here)
    : > "$_itier_tmp/store.jsonl"
    itier_detect_boundary "$_itier_tmp/store.jsonl"
    _itier_r=$?
    if [ "$_itier_r" -eq 1 ]; then _it_ok "self-owned writable store => boundary ABSENT (rc=1)"
    else _it_bad "self-owned writable store => rc=$_itier_r (expected 1 ABSENT)"; fi

    # (2) achieved tier for that store is `instance`, NOT capability
    _itier_t=$(itier_achieved qa-deploy "$_itier_tmp/store.jsonl")
    if [ "$_itier_t" = "instance" ]; then _it_ok "achieved tier on a single-uid host is 'instance' (honest degradation)"
    else _it_bad "achieved tier reported '$_itier_t' (expected instance)"; fi

    # (3) a CLAIM of capability against that store is NOT supported
    itier_claim_supported capability "$_itier_tmp/store.jsonl"
    if [ $? -ne 0 ]; then _it_ok "a 'capability' claim with no measured boundary is NOT supported (refusable)"
    else _it_bad "a 'capability' claim was reported SUPPORTED with no boundary — the exact theatre FR-033 forbids"; fi

    # (4) NEGATIVE CONTROL — the false-positive guard. A claim of `instance` is
    #     NOT refused, and the detector reports PRESENT for a genuine boundary.
    itier_claim_supported instance "$_itier_tmp/store.jsonl"
    if [ $? -eq 0 ]; then _it_ok "NEGATIVE CONTROL an 'instance' claim needs no boundary and is NOT refused"
    else _it_bad "an 'instance' claim was refused — false-positive refusal (§11.4.201(1))"; fi

    itier_detect_boundary "$ITIER_NEEDLE_PATH"
    if [ $? -eq 0 ]; then _it_ok "NEGATIVE CONTROL a genuine boundary store reports PRESENT (rc=0), so PRESENT is reachable"
    else _it_bad "a genuine boundary reported NOT-present — the detector can only ever say 'absent', which proves nothing"; fi

    # (5) BLIND path: an unreachable needle makes the detector report BLIND (3),
    #     never `instance`. This is the check that keeps a broken detector from
    #     masquerading as a boundary-less host.
    ( ITIER_NEEDLE_PATH="$_itier_tmp/no-such-needle"; itier_detect_boundary "$_itier_tmp/store.jsonl" ) 2>/dev/null
    if [ $? -eq 3 ]; then _it_ok "BLIND an unreachable needle yields rc=3 BLIND, never a reported absence"
    else _it_bad "an unreachable needle did NOT yield BLIND — a broken detector would report 'instance'"; fi

    # (6) TRIPWIRE observable: entering the capability path touches the marker.
    ( CBG_CAPABILITY_TRIPWIRE="$_itier_tmp/tw"; export CBG_CAPABILITY_TRIPWIRE
      itier_detect_boundary "$_itier_tmp/store.jsonl" >/dev/null 2>&1 )
    if [ -e "$_itier_tmp/tw" ]; then _it_ok "TRIPWIRE entering the capability path leaves an observable marker"
    else _it_bad "TRIPWIRE marker absent after entering the capability path — S9's absence assertion would prove nothing"; fi

    rm -rf "$_itier_tmp"
    if [ "$_itier_trc" -eq 0 ]; then
        printf 'INDEPENDENCE-TIER SELFTEST PASS — needle-guarded detector (cannot report a blind instrument as an absence), honest degradation to instance on a single-uid host, an unsupported capability CLAIM is refusable, and both PRESENT and ABSENT are reachable (so neither verdict is hardcoded)\n'
    else
        printf 'INDEPENDENCE-TIER SELFTEST FAIL\n' >&2
    fi
    return "$_itier_trc"
}

# --- dispatch (content-identified, never by filename) ------------------------
_ITIER_SELF_SENTINEL='itier-self-id-9c3d72fb-independence-tier'
_itier_is_self() { [ -n "${1:-}" ] && [ -r "$1" ] && grep -qF "$_ITIER_SELF_SENTINEL" "$1" 2>/dev/null; }

if [ -n "${BASH_SOURCE:-}" ]; then
    if [ "${BASH_SOURCE}" = "$0" ]; then _ITIER_EXECUTED=1; else _ITIER_EXECUTED=0; fi
elif [ -n "${ZSH_EVAL_CONTEXT:-}" ]; then
    case "$ZSH_EVAL_CONTEXT" in *:file*) _ITIER_EXECUTED=0 ;; *) _ITIER_EXECUTED=1 ;; esac
elif _itier_is_self "$0"; then _ITIER_EXECUTED=1
elif [ -r "$0" ]; then _ITIER_EXECUTED=0
else _ITIER_EXECUTED=u
fi

if [ "$_ITIER_EXECUTED" = "1" ]; then
    case "${1:-}" in
        detect)     itier_detect_boundary "${2:-}"; exit $? ;;
        achieved)   itier_achieved "${2:-}" "${3:-}"; exit $? ;;
        --selftest) _itier_selftest; exit $? ;;
        *) printf 'usage: %s detect <store> | achieved <seam> <store> | --selftest\n' "$0" >&2; exit 2 ;;
    esac
fi
