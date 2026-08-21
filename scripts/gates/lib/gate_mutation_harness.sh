#!/bin/sh
# =============================================================================
# gate_mutation_harness.sh — shared driver for paired §1.1 mutation tests
# (support library for T228/T229/T231/T232/T233).
#
# ── Why a shared harness ────────────────────────────────────────────────────
# Five mutation tests that each re-implement copy-out / mutate / run / read the
# named verdict / restore / checksum would be five copies of one algorithm,
# which is the near-identical fork §11.4.251 refuses — and the copies would
# drift, so a later fix to the checksum check would land in one of them.
#
# ── What a valid pair must demonstrate (§11.4.115(F), §11.4.194(6)(d)) ──────
#   0. BASELINE  : the NAMED assertion is PASSing before the mutation, or there
#                  is nothing for the mutation to flip.
#   1. MUTATED   : that SAME named assertion flips to FAIL — read by id, never
#                  by "some assertion changed".
#   1b. SURGICAL : the named STABLE assertions do NOT move, so the flip is
#                  attributable to the mutation rather than to general breakage.
#   2. RESTORED  : the named assertion returns to PASS. A one-way flip does not
#                  demonstrate a pair.
#   3. UNTOUCHED : the TRACKED file is byte-identical before and after
#                  (§11.4.84 single-resource-owner). Mutations run on an
#                  out-of-repo copy; the working tree is never edited.
#
# ── Behavioural, not textual (§11.4.115(F)) ─────────────────────────────────
# The caller supplies a mutator that changes BEHAVIOUR. A mutation whose diff
# only deletes the literal strings the gate greps for is a refused tautology:
# it proves the gate can read its own source, not that it can catch the defect.
# The harness enforces the parse check so a "flip" can never be a syntax error.
#
# Usage:
#   . lib/gate_mutation_harness.sh
#   gm_init <gate-abs-path>
#   gm_mutate_target <target-abs-path>        # file to copy + mutate
#   gm_pair <mutator-fn> <flip-id> [stable-id...]
#   gm_report                                 # rc 0 = pair valid
#
# The mutator function receives the COPY path as $1 and must edit it in place.
# =============================================================================

set -u

GM_FAILS=0
GM_GATE=""
GM_TARGET=""
GM_TMP=""
GM_SUM_BEFORE=""
GM_ARGS=""

gm_say() { printf '%s\n' "$*"; }
gm_ok()  { gm_say "  [ok]   $*"; }
gm_bad() { GM_FAILS=$((GM_FAILS + 1)); gm_say "  [FAIL] $*"; }

gm_init() {  # <gate-abs-path> [extra gate args...]
    GM_GATE=${1:?gm_init needs the gate path}
    shift
    GM_ARGS=$*
    [ -f "$GM_GATE" ] || { gm_say "PAIR-NOT-DEMONSTRATED: gate absent: $GM_GATE"; exit 1; }
    GM_TMP=$(mktemp -d "${TMPDIR:-/tmp}/gm_pair.XXXXXX") || exit 2
    # shellcheck disable=SC2064
    trap "rm -rf '$GM_TMP'" EXIT INT TERM
}

gm_mutate_target() {  # <target-abs-path>
    GM_TARGET=${1:?gm_mutate_target needs a path}
    [ -f "$GM_TARGET" ] || { gm_say "PAIR-NOT-DEMONSTRATED: target absent: $GM_TARGET"; exit 1; }
    GM_SUM_BEFORE=$(sha256sum "$GM_TARGET" | cut -d' ' -f1)
}

# Build the out-of-repo working copy: the whole gates dir layout the gate needs
# to resolve its libraries, so the copy runs exactly as the tracked one does.
_gm_stage() {
    _gm_src=$(dirname -- "$GM_GATE")
    rm -rf "$GM_TMP/gates"
    mkdir -p "$GM_TMP/gates/lib"
    cp "$GM_GATE" "$GM_TMP/gates/" || return 2
    for _gm_l in "$_gm_src"/lib/*.sh; do
        [ -f "$_gm_l" ] && cp "$_gm_l" "$GM_TMP/gates/lib/"
    done
    # Mirror the target into the copy, wherever it lives relative to the gate.
    case $GM_TARGET in
        "$_gm_src"/lib/*) GM_COPY="$GM_TMP/gates/lib/$(basename "$GM_TARGET")" ;;
        "$_gm_src"/*)     GM_COPY="$GM_TMP/gates/$(basename "$GM_TARGET")" ;;
        *)                GM_COPY="$GM_TMP/gates/$(basename "$GM_TARGET")" ;;
    esac
    cp "$GM_TARGET" "$GM_COPY" || return 2
    GM_COPY_GATE="$GM_TMP/gates/$(basename "$GM_GATE")"
    return 0
}

_gm_run() {  # <outfile>
    # shellcheck disable=SC2086
    sh "$GM_COPY_GATE" $GM_ARGS > "$1" 2>&1
    return 0
}

gm_pair() {  # <mutator-fn> <flip-id> [stable-id...]
    _gm_mut=${1:?gm_pair needs a mutator function}; shift
    _gm_flip=${1:?gm_pair needs the id expected to flip}; shift
    _gm_stable=$*

    _gm_stage || { gm_bad "could not stage an out-of-repo working copy"; return 1; }

    gm_say "=== paired §1.1 mutation for $(basename "$GM_GATE") ==="
    gm_say "tracked target (READ-ONLY to this harness): $GM_TARGET"
    gm_say "mutating an out-of-repo copy at:            $GM_COPY"

    gm_say '--- direction 0: baseline on the unmutated copy ---'
    _gm_run "$GM_TMP/base.out"
    _gm_b=$(cn_verdict_of "$GM_TMP/base.out" "$_gm_flip")
    if [ "$_gm_b" = PASS ]; then gm_ok "baseline $_gm_flip = PASS (there is something for the mutation to flip)"
    else gm_bad "baseline $_gm_flip = $_gm_b — a mutation cannot be shown to flip an assertion that is not passing to begin with"; fi
    for _gm_s in $_gm_stable; do
        _gm_v=$(cn_verdict_of "$GM_TMP/base.out" "$_gm_s")
        if [ "$_gm_v" = PASS ]; then gm_ok "baseline $_gm_s = PASS (surgical control)"
        else gm_bad "baseline $_gm_s = $_gm_v — it cannot serve as a surgical control"; fi
    done

    gm_say '--- applying the BEHAVIOURAL mutation ---'
    "$_gm_mut" "$GM_COPY" || { gm_bad "the mutator reported failure"; return 1; }
    if sh -n "$GM_COPY" 2>/dev/null; then gm_ok "the mutated copy still parses — the flip is behavioural, not a syntax error"
    else gm_bad "the mutated copy no longer parses; a crash is not the behaviour change this pair claims"; fi
    if cmp -s "$GM_TARGET" "$GM_COPY"; then gm_bad "the mutator changed nothing — no pair can be demonstrated"
    else gm_ok "the copy differs from the tracked file (the mutation applied)"; fi

    gm_say "--- direction 1: mutated -> $_gm_flip must FAIL ---"
    _gm_run "$GM_TMP/mut.out"
    _gm_m=$(cn_verdict_of "$GM_TMP/mut.out" "$_gm_flip")
    if [ "$_gm_m" = FAIL ]; then gm_ok "$_gm_flip flipped PASS -> FAIL under the mutation"
    else gm_bad "$_gm_flip = $_gm_m under mutation (expected FAIL) — the gate does not depend on the mutated behaviour, so its PASS was not load-bearing"; fi
    for _gm_s in $_gm_stable; do
        _gm_v=$(cn_verdict_of "$GM_TMP/mut.out" "$_gm_s")
        if [ "$_gm_v" = PASS ]; then gm_ok "$_gm_s stayed PASS — the mutation is SURGICAL (§11.4.194(6)(d))"
        else gm_bad "$_gm_s = $_gm_v under mutation; the flip is not attributable to the targeted assertion"; fi
    done

    gm_say "--- direction 2: restored -> $_gm_flip must return to PASS ---"
    cp "$GM_TARGET" "$GM_COPY" || { gm_bad "restore failed"; return 1; }
    _gm_run "$GM_TMP/res.out"
    _gm_r=$(cn_verdict_of "$GM_TMP/res.out" "$_gm_flip")
    if [ "$_gm_r" = PASS ]; then gm_ok "$_gm_flip restored to PASS — the flip tracks the mutation in BOTH directions"
    else gm_bad "$_gm_flip = $_gm_r after restore; a one-way flip does not demonstrate a pair"; fi
    return 0
}

gm_report() {
    _gm_after=$(sha256sum "$GM_TARGET" | cut -d' ' -f1)
    if [ "$GM_SUM_BEFORE" = "$_gm_after" ]; then
        gm_ok "tracked file unchanged (sha256 $_gm_after) — single-resource-owner respected (§11.4.84)"
    else
        gm_bad "the TRACKED file changed during this run ($GM_SUM_BEFORE -> $_gm_after); that is a working-tree violation, not a test result"
    fi
    gm_say ''
    if [ "$GM_FAILS" -eq 0 ]; then
        gm_say '=== MUTATION PAIR VALID ==='
        return 0
    fi
    gm_say "=== PAIR NOT DEMONSTRATED ($GM_FAILS failed) ==="
    return 1
}
