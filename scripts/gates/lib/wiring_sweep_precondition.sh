#!/bin/sh
# lib/wiring_sweep_precondition.sh — the FR-021 ordering precondition.
#
# ── What this is ─────────────────────────────────────────────────────────────
# ONE predicate. It answers exactly one question:
#
#     Has the wiring sweep produced a result FOR THE CURRENT TREE STATE?
#
# FR-021: "the adoption step MUST NOT be accepted before the wiring step
# reports its sweep result." Ordering constraints that live only in a
# checklist are not ordering constraints — they are hopes. This predicate is
# the mechanical form, so the adoption seam can REFUSE rather than proceed on
# an assumption.
#
# ── SCOPE BOUNDARY — read this before looking for the adoption gate here ────
# This file delivers the PRECONDITION and nothing else. The dependency-
# adoption gate that CONSUMES it (FR-013 / FR-014 / FR-020) is a DIFFERENT
# stream's deliverable and is deliberately NOT implemented here, NOT stubbed
# here, and NOT referenced by a guessed path. Naming that boundary is the
# honest position (§11.4.6): inventing the adoption gate's path would create a
# reference that resolves by absence the moment the real one lands somewhere
# else.
#
# The consuming gate does two things:
#     fp=$(cm_unreferenced_gate_bound_or_retired.sh --fingerprint)
#     wiring_sweep_precondition "<result-path>" "$fp" || exit 2
# The fingerprint is computed by the SWEEP, not recomputed here, so there is
# exactly ONE definition of "the current tree state" and the two cannot drift.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   . lib/wiring_sweep_precondition.sh
#   wiring_sweep_precondition <result-tsv> <current-fingerprint>
#
#   Returns 0 when the precondition HOLDS.
#   Returns non-zero and prints `REFUSE: <reason> — <resolved evidence>` to
#   stderr otherwise. The reasons are the closed set from
#   contracts/gate-verdict.md.
#
#   The file may also be executed directly with the same two arguments, which
#   is how its test drives it.
#
# ── The three refusal paths (all REFUSE, none "no findings") ────────────────
#   1. ABSENT       the result file does not exist. The sweep has not run.
#   2. UNREADABLE   the file exists but cannot be read, or carries no
#                   parseable `tree-fingerprint` row. §11.4.201(6): an
#                   instrument that cannot read is BLIND, and a blind
#                   instrument's silence is not an absence of findings.
#                   Treating an unreadable result as "nothing to report"
#                   would make `chmod 000` a way to pass the gate.
#   3. STALE        the recorded fingerprint differs from the current one.
#                   The sweep ran, but against a different tree. A result for
#                   another state is not a result for this one.
#
# A malformed/absent fingerprint is deliberately classed with UNREADABLE
# rather than STALE: we do not know that the tree moved, we know we cannot
# tell, and those are different claims (§11.4.6).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   POSIX sh, awk. Parses clean under `sh -n` AND `bash -n` (§11.4.67).
#
# ── Cross-references ────────────────────────────────────────────────────────
#   FR-021 (spec.md), quickstart S19, contracts/gate-verdict.md,
#   cm_unreferenced_gate_bound_or_retired.sh (produces the result and owns
#   the fingerprint definition), §11.4.201(1)(6), §11.4.6.
#   Test: scripts/gates/test_wiring_sweep_precondition.sh.
#
# Classification: universal (§11.4.17).

# wiring_sweep_precondition <result-tsv> <current-fingerprint> -> 0 | non-zero
wiring_sweep_precondition() {
    _wsp_result=${1:-}
    _wsp_want=${2:-}

    if [ -z "$_wsp_result" ] || [ -z "$_wsp_want" ]; then
        printf 'REFUSE: command_field_ABSENT — wiring_sweep_precondition needs <result-tsv> and <current-fingerprint>; got result="%s" fingerprint="%s"\n' \
            "$_wsp_result" "$_wsp_want" >&2
        return 2
    fi

    # 1. ABSENT
    if [ ! -e "$_wsp_result" ]; then
        printf 'REFUSE: evidence_file_MISSING — the wiring sweep has produced no result at %s. FR-021: adoption is not accepted before the wiring step reports. Run cm_unreferenced_gate_bound_or_retired.sh first.\n' \
            "$_wsp_result" >&2
        return 2
    fi

    # 2. UNREADABLE — including present-but-empty and present-but-malformed.
    if [ ! -r "$_wsp_result" ]; then
        printf 'REFUSE: store_UNREADABLE — the sweep result exists at %s but cannot be READ. An unreadable store is a refusal, never "no findings" (§11.4.201(6)); otherwise making it unreadable would be a way to pass.\n' \
            "$_wsp_result" >&2
        return 2
    fi
    if [ ! -s "$_wsp_result" ]; then
        printf 'REFUSE: evidence_file_EMPTY — the sweep result at %s is zero bytes. A zero-byte result is not a clean result.\n' \
            "$_wsp_result" >&2
        return 2
    fi

    _wsp_got=$(awk -F'\t' '$1=="tree-fingerprint"{print $2; exit}' "$_wsp_result" 2>/dev/null)
    if [ -z "$_wsp_got" ]; then
        printf 'REFUSE: store_UNREADABLE — the sweep result at %s carries no parseable `tree-fingerprint` row. This is classed as UNREADABLE, not STALE, on purpose: we cannot tell whether the tree moved, and "cannot tell" is a different claim from "it moved" (§11.4.6).\n' \
            "$_wsp_result" >&2
        return 2
    fi

    # 3. STALE
    if [ "$_wsp_got" != "$_wsp_want" ]; then
        printf 'REFUSE: evidence_class_TOO_LOW — the sweep result at %s was computed against a DIFFERENT tree state. Resolved evidence: recorded=%s current=%s. A result for another state is not a result for this one (FR-021).\n' \
            "$_wsp_result" "$_wsp_got" "$_wsp_want" >&2
        return 2
    fi

    return 0
}

# Direct execution drives the same predicate, so the test exercises the
# shipped code path rather than a copy of it.
case "${0##*/}" in
    wiring_sweep_precondition.sh)
        wiring_sweep_precondition "${1:-}" "${2:-}"
        exit $?
        ;;
esac
