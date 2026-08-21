#!/bin/sh
# =============================================================================
# seam_tier_table.sh — canonical seam -> independence-tier lookup (T116, spec 002)
# =============================================================================
#
# Contract: specs/002-anti-slop-enforcement/contracts/seam-tier-table.md
# Data model: specs/002-anti-slop-enforcement/data-model.md E5.
#
# WHAT THIS IS (FR-036): the tier a seam REQUIRES is resolved by EXACT-MATCH
# TABLE LOOKUP, never by a predicate. That is the whole point. A predicate
# ("does the seam id look release-ish?") can, by one careless edit, start
# demanding capability separation for a seam nobody listed — a false-positive
# refusal, which §11.4.201(1) rates exactly as seriously as a false pass. A
# table cannot: a seam that is not IN it resolves to `instance` BY ABSENCE.
#
# THE DELIBERATE ASYMMETRY — commented HERE, at the lookup, because a future
# reviewer who sees only one half will "correct" it into a defect:
#
#   axis                       unknown value resolves to   why
#   -------------------------  --------------------------  -----------------------
#   evidence-class FLOOR       HIGHEST rank (fail CLOSED)  an unknown floor must
#     (critical_blocker_gate.sh                             not VOID a floor
#      _cbg_floor_rank)
#   seam TIER (this file)      `instance`   (fail OPEN)     an unknown seam must
#                                                           not INVENT a requirement
#
# These look inconsistent and are not. Closing the floor protects evidence
# strength; opening the tier protects against inventing a requirement no one
# declared. Flipping EITHER produces a defect: a fail-open floor is a voided
# floor, a fail-closed tier is a false-refusal engine.
#
# HONEST BOUNDARY (§11.4.6): this file answers "what tier does this seam
# REQUIRE?" It does NOT answer "what tier was ACHIEVED?" — that is measured, on
# the host, by independence_tier.sh, and the two must never be conflated. A
# required tier is a policy statement; an achieved tier is a measurement.
#
# Usage (executed):
#   sh seam_tier_table.sh tier_for <seam_id>     -> prints tier, rc 0
#   sh seam_tier_table.sh list                   -> prints "<seam>\t<tier>" rows
#   sh seam_tier_table.sh --selftest             -> rc 0 when self-consistent
# Usage (sourced):
#   . seam_tier_table.sh ; seam_tier_required <seam_id>
#
# POSIX sh; `sh -n` AND `bash -n` clean. Every variable is `_stt_`/`STT_`
# prefixed so sourcing this file can never clobber a caller's variables
# (§11.4.67 safe-sourced-lib discipline).
# =============================================================================

# --- THE TABLE ---------------------------------------------------------------
# Tier-C seams ONLY. Every id here MUST be byte-identical to the contract.
# Format: "<seam_id> <tier_required>", one per line. Nothing else is a lookup
# key; nothing here is a pattern.
_STT_TIER_C_TABLE='release-tag capability
qa-deploy capability
manual-qa-handoff capability'

# The SIX canonical seam ids (data-model E5). The three NOT in the table above
# resolve to `instance` by absence — they are listed here only so the selftest
# can assert the vocabulary has not drifted, never as a lookup path.
_STT_CANONICAL_SEAMS='pre-action commit pre-build release-tag qa-deploy manual-qa-handoff'

# --- the lookup --------------------------------------------------------------
seam_tier_required() {  # <seam_id> -> prints instance|capability ; rc 0 always
    _stt_want="${1:-}"
    if [ -z "$_stt_want" ]; then
        printf 'seam_tier_required: usage: seam_tier_required <seam_id>\n' >&2
        return 2
    fi
    # EXACT match only. `=` is a string comparison, not a pattern match: a
    # near-miss id ("deploy" for "qa-deploy") does NOT match, and therefore
    # resolves to `instance` by absence — silently and without error, which is
    # the documented trap (data-model E5) and is why the near-miss case is a
    # named scenario assertion rather than a comment.
    printf '%s\n' "$_STT_TIER_C_TABLE" | while IFS=' ' read -r _stt_k _stt_v; do
        [ -n "$_stt_k" ] || continue
        if [ "$_stt_k" = "$_stt_want" ]; then
            printf '%s' "$_stt_v"
            exit 7          # sentinel out of the subshell: "found"
        fi
    done
    # rc 7 from the subshell above means a row matched and already printed.
    if [ $? -eq 7 ]; then
        printf '\n'
        return 0
    fi
    printf 'instance\n'
    return 0
}

seam_tier_list() { printf '%s\n' "$_STT_TIER_C_TABLE" | sed -e 's/ /\t/'; }

# --- self-check (§11.4.107(10)) ----------------------------------------------
# Asserts the table has not drifted from the tracked contract + data model.
# EVERY absence assertion below is preceded by a control needle of the SAME
# query class (§11.4.201(7)(b)): a grep that cannot see a known-present string
# in that file proves nothing about a string it cannot find.
_stt_selftest() {
    _stt_rc=0
    _stt_here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
    # This file lives at <repo>/constitution/scripts/gates/lib/ — FOUR levels
    # below the consuming repo root, not three. (An earlier draft used three and
    # silently landed inside constitution/, where both tracked documents are
    # absent; the drift comparison then SKIPped and the selftest still said
    # PASS. That is the §11.4.201(6) false-null shape: a check that cannot see
    # reporting success. The verdict wording below now states which comparisons
    # actually RAN, so a skip can never be read as a comparison.)
    _stt_root=${STT_REPO_ROOT:-$(CDPATH='' cd -- "$_stt_here/../../../.." && pwd)}
    _stt_cmp_contract=SKIPPED
    _stt_cmp_dm=SKIPPED
    _stt_contract="$_stt_root/specs/002-anti-slop-enforcement/contracts/seam-tier-table.md"
    _stt_dm="$_stt_root/specs/002-anti-slop-enforcement/data-model.md"

    _stt_ok()  { printf '  PASS %s\n' "$1"; }
    _stt_bad() { printf '  FAIL %s\n' "$1" >&2; _stt_rc=1; }

    # (1) behavioural: the three Tier-C ids resolve to capability.
    for _stt_s in release-tag qa-deploy manual-qa-handoff; do
        _stt_got=$(seam_tier_required "$_stt_s")
        if [ "$_stt_got" = "capability" ]; then _stt_ok "tierC $_stt_s -> capability"
        else _stt_bad "tierC $_stt_s -> '$_stt_got' (expected capability)"; fi
    done
    # (2) behavioural NEGATIVE CONTROL: unlisted + near-miss resolve to instance
    #     WITHOUT error. This is the false-positive guard — if it ever returns
    #     `capability`, the lookup has become a predicate.
    # NOTE: near-miss ids are written as PLAIN LITERALS here on purpose. An
    # earlier draft built one with a command substitution to carry a trailing
    # space; command substitution STRIPS trailing whitespace, so the "near
    # miss" silently became the EXACT id and the negative control would have
    # asserted the opposite of what it read (§11.4.201(7) — the instrument, not
    # the subject, was wrong).
    for _stt_s in pre-action commit pre-build deploy tag commit-batch releasetag qa_deploy; do
        [ -n "$_stt_s" ] || continue
        _stt_got=$(seam_tier_required "$_stt_s")
        _stt_gr=$?
        if [ "$_stt_got" = "instance" ] && [ "$_stt_gr" -eq 0 ]; then
            _stt_ok "unlisted '$_stt_s' -> instance by absence (rc=0, no error)"
        else
            _stt_bad "unlisted '$_stt_s' -> '$_stt_got' rc=$_stt_gr (expected instance rc=0)"
        fi
    done
    # (3) the Tier-C ids are byte-identical to the CONTRACT.
    if [ -r "$_stt_contract" ]; then
        # control needle FIRST, same query class (grep -F on this file):
        if grep -qF 'tier_required' "$_stt_contract"; then
            _stt_ok "needle: the contract is readable and grep -F sees a known-present token"
            _stt_cmp_contract=RAN
            for _stt_s in release-tag qa-deploy manual-qa-handoff; do
                if grep -qF "$_stt_s" "$_stt_contract"; then _stt_ok "contract carries '$_stt_s' byte-identically"
                else _stt_bad "contract does NOT carry '$_stt_s' — the table has drifted from contracts/seam-tier-table.md"; fi
            done
        else
            _stt_bad "INSTRUMENT BLIND — grep -F could not see 'tier_required' in $_stt_contract; a zero for a seam id would be a FALSE NULL"
        fi
    else
        printf '  SKIP contract not readable (%s) — cannot compare (§11.4.3 skip-with-reason, never a pass)\n' "$_stt_contract"
    fi
    # (4) all SIX canonical ids are byte-identical to the DATA MODEL.
    if [ -r "$_stt_dm" ]; then
        if grep -qF 'seam_id' "$_stt_dm"; then
            _stt_ok "needle: the data model is readable and grep -F sees a known-present token"
            _stt_cmp_dm=RAN
            for _stt_s in $_STT_CANONICAL_SEAMS; do
                if grep -qF "\`$_stt_s\`" "$_stt_dm"; then _stt_ok "data-model carries canonical seam '$_stt_s'"
                else _stt_bad "data-model does NOT carry canonical seam '$_stt_s' — vocabulary drift"; fi
            done
        else
            _stt_bad "INSTRUMENT BLIND — grep -F could not see 'seam_id' in $_stt_dm"
        fi
    else
        printf '  SKIP data model not readable (%s)\n' "$_stt_dm"
    fi

    if [ "$_stt_rc" -eq 0 ]; then
        printf 'SEAM-TIER-TABLE SELFTEST PASS — exact-match lookup, Tier-C={release-tag,qa-deploy,manual-qa-handoff}, every other seam resolves to instance by absence (cannot invent a requirement); drift comparison contract=%s data-model=%s (SKIPPED means NOT compared, never compared-and-clean)\n' "$_stt_cmp_contract" "$_stt_cmp_dm"
    else
        printf 'SEAM-TIER-TABLE SELFTEST FAIL\n' >&2
    fi
    return "$_stt_rc"
}

# --- dispatch (only when EXECUTED, never when sourced) ------------------------
# Identified by content, never by filename (the §11.4.201(6) rename false-null
# that bit critical_blocker_gate.sh: a copy under another name silently no-oped
# and reported success).
_STT_SELF_SENTINEL='stt-self-id-6b1c40ae-seam-tier-table'
_stt_is_self() { [ -n "${1:-}" ] && [ -r "$1" ] && grep -qF "$_STT_SELF_SENTINEL" "$1" 2>/dev/null; }

if [ -n "${BASH_SOURCE:-}" ]; then
    if [ "${BASH_SOURCE}" = "$0" ]; then _STT_EXECUTED=1; else _STT_EXECUTED=0; fi
elif [ -n "${ZSH_EVAL_CONTEXT:-}" ]; then
    case "$ZSH_EVAL_CONTEXT" in *:file*) _STT_EXECUTED=0 ;; *) _STT_EXECUTED=1 ;; esac
elif _stt_is_self "$0"; then _STT_EXECUTED=1
elif [ -r "$0" ]; then _STT_EXECUTED=0
else _STT_EXECUTED=u
fi

if [ "$_STT_EXECUTED" = "1" ]; then
    case "${1:-}" in
        tier_for)   seam_tier_required "${2:-}"; exit $? ;;
        list)       seam_tier_list; exit 0 ;;
        --selftest) _stt_selftest; exit $? ;;
        *)
            printf 'usage: %s tier_for <seam_id> | list | --selftest\n' "$0" >&2
            exit 2 ;;
    esac
fi
