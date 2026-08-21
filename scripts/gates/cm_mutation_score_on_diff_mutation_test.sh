#!/bin/sh
# cm_mutation_score_on_diff_mutation_test.sh — the paired §1.1 mutation test for
# CM-MUTATION-SCORE-ON-DIFF (feature 002-anti-slop-enforcement, task T408b).
#
# ── What a paired mutation is FOR ───────────────────────────────────────────
# A gate that has never been OBSERVED failing is unvalidated instrumentation
# (§11.4.115(F)). This test breaks a SPECIFIC assertion the gate names and
# asserts the gate's own selftest then FAILS. If the mutated gate still passes,
# the assertion was decoration.
#
# ── The two mutations, and why each is specific ─────────────────────────────
#   M1  the score comparison  `[ "$_pct" -lt "$_tv" ]`  ->  `-gt`
#       Kills the threshold check itself. The golden-TRUE fixture (a partial
#       suite measured at 60% against a 70% fixture threshold) must stop being
#       refused.
#   M2  the engine's CONTROL NEEDLE — the sentinel-mutant guard's `-eq 0`
#       becomes `-eq 999`, so a blind kill command is no longer detected.
#       The blind-control case must stop reporting KILLER_BLIND. This is the
#       mutation that matters most: without it, "the tests killed nothing" and
#       "the kill command can detect nothing" collapse into the same 0%, and
#       the second one is not a measurement at all (§11.4.201(7)(b)).
#
# A mutation that merely deleted the literal strings the selftest greps for
# would be a tautology and is deliberately NOT used (§11.4.115(F)).
#
# ── Usage / exit codes ──────────────────────────────────────────────────────
#   cm_mutation_score_on_diff_mutation_test.sh
#     0  every mutation was CAUGHT (the mutated gate's selftest failed)
#     1  a mutation SURVIVED — the gate is not validated by that assertion
#     2  setup error
#
# ── Side-effects ────────────────────────────────────────────────────────────
#   Writes ONLY inside a mktemp -d it removes on exit. It never edits the
#   tracked gate or engine (§11.4.84 — a mutation harness that mutates the
#   working tree is how mutation residue gets committed).

set -u

PROG=$(basename "$0")
SELF_DIR=$(cd "$(dirname "$0")" && pwd)
GATE="$SELF_DIR/cm_mutation_score_on_diff.sh"
ENGINE="$SELF_DIR/lib/shell_mutation_engine.sh"

die() { printf '%s: %s\n' "$PROG" "$1" >&2; exit 2; }

[ -f "$GATE" ]   || die "gate not found: $GATE"
[ -f "$ENGINE" ] || die "engine not found: $ENGINE"

WD=$(mktemp -d) || die "mktemp failed"
# shellcheck disable=SC2064
trap "rm -rf '$WD'" EXIT INT TERM

PASS=0
FAIL=0

fresh_copy() {
    rm -rf "$WD/g"
    mkdir -p "$WD/g/lib" || return 1
    cp "$GATE"   "$WD/g/cm_mutation_score_on_diff.sh" || return 1
    cp "$ENGINE" "$WD/g/lib/shell_mutation_engine.sh" || return 1
    chmod 0755 "$WD/g/cm_mutation_score_on_diff.sh"
    return 0
}

# assert_control — the UNMUTATED copy must PASS its own selftest. Without this,
# a mutation "caught" by a copy that was already broken proves nothing.
fresh_copy || die "could not stage a copy"
timeout 300 sh "$WD/g/cm_mutation_score_on_diff.sh" --selftest > "$WD/control.log" 2>&1
CTRL_RC=$?
if [ "$CTRL_RC" -ne 0 ]; then
    printf 'MUT-TEST\tFAIL\tCONTROL: the unmutated copy does not pass its own selftest (rc=%s) — no mutation result below would mean anything\n' "$CTRL_RC"
    sed 's/^/    | /' "$WD/control.log"
    exit 1
fi
printf 'MUT-TEST\tPASS\tCONTROL: unmutated copy passes its own selftest (rc=0)\n'
PASS=$((PASS + 1))

run_mutation() {
    _label=$1
    timeout 300 sh "$WD/g/cm_mutation_score_on_diff.sh" --selftest > "$WD/mut.log" 2>&1
    _rc=$?
    if [ "$_rc" -ne 0 ]; then
        printf 'MUT-TEST\tPASS\t%s — CAUGHT (mutated gate selftest rc=%s)\n' "$_label" "$_rc"
        grep '^SELFTEST	FAIL' "$WD/mut.log" | sed 's/^/    caught: /'
        PASS=$((PASS + 1))
    else
        printf 'MUT-TEST\tFAIL\t%s — SURVIVED (mutated gate selftest still rc=0; the assertion is decoration)\n' "$_label"
        FAIL=$((FAIL + 1))
    fi
}

# ── M1 — the score comparison ───────────────────────────────────────────────
fresh_copy || die "could not stage a copy"
awk '
    { if ($0 ~ /if \[ "\$_pct" -lt "\$_tv" \]; then/) { sub(/-lt/, "-gt"); m++ } print }
    END { if (m != 1) exit 3 }
' "$WD/g/cm_mutation_score_on_diff.sh" > "$WD/g/m1.sh"
M1_RC=$?
[ "$M1_RC" -eq 0 ] || die "M1 did not apply exactly once (awk rc=$M1_RC) — the anchor moved; fix the mutation, never the gate"
mv "$WD/g/m1.sh" "$WD/g/cm_mutation_score_on_diff.sh"
chmod 0755 "$WD/g/cm_mutation_score_on_diff.sh"
run_mutation 'M1 score comparison -lt -> -gt'

# ── M2 — the engine's sentinel control needle ───────────────────────────────
fresh_copy || die "could not stage a copy"
awk '
    /_sme_run_kill "\$_s_kill" "\$_s_sent"/ { armed = 1; print; next }
    armed == 1 && /-eq 0/ { sub(/-eq 0/, "-eq 999"); armed = 2; m++; print; next }
    { print }
    END { if (m != 1) exit 3 }
' "$WD/g/lib/shell_mutation_engine.sh" > "$WD/g/lib/m2.sh"
M2_RC=$?
[ "$M2_RC" -eq 0 ] || die "M2 did not apply exactly once (awk rc=$M2_RC) — the anchor moved; fix the mutation, never the engine"
mv "$WD/g/lib/m2.sh" "$WD/g/lib/shell_mutation_engine.sh"
run_mutation 'M2 engine sentinel control needle disarmed'

printf 'MUT-TEST\tSUMMARY\tpass=%d fail=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
