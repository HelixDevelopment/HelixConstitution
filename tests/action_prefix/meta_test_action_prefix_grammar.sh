#!/usr/bin/env bash
# tests/action_prefix/meta_test_action_prefix_grammar.sh
#
# §1.1 paired-mutation meta-test for the §11.4.140 GRAMMAR_ADDENDUM grammar suite.
# Proves the grammar test (test_action_prefix_grammar.sh) is NOT a bluff gate:
# break the slash-form parse, assert the suite FAILs; restore, assert it PASSes.
#
# Mutations (each: mutate → assert suite FAIL → restore → assert suite PASS):
#   M1  break the slash-form regex in the python parse path (the `/...` branch)
#       → the form-3 / form-4 slash cases FAIL → suite exit != 0.
#   M2  break the slash-form match in the awk parse path
#       → python/awk parity cases FAIL (paths diverge) → suite exit != 0.
#   M3  corrupt the python parse path's DEFAULT-namespace default (returns
#       "WRONG" instead of "DEFAULT") so the python path diverges from both the
#       awk path AND the expected tuple → parity + form-1/3 namespace cases FAIL.
#
# §11.4.84 quiescence: each mutation is serialised — mutate, run, RESTORE from a
# pristine backup BEFORE the next mutation; the working tree is restored on EXIT
# (trap) even on SIGINT so no mutation residue can persist.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   bash tests/action_prefix/meta_test_action_prefix_grammar.sh
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Per-mutation verdict lines + a final RESULT. Exit 0 iff EVERY mutation flips
#   the suite to FAIL and the restored suite PASSes; non-zero otherwise.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Temporarily edits action_prefix_lib.sh + registry.yaml IN PLACE, then
#   RESTORES them from a pristine backup (trap EXIT). Never commits. Writes
#   evidence under qa-results/action_prefix/<run-id>/meta/.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   test_action_prefix_grammar.sh (the suite under test), sed, cp.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §1.1 (paired mutation), §11.4.84 (working-tree quiescence — restore-on-exit),
#   §11.4.140 (the grammar), §11.4.67 (parse-clean), §11.4.50 (determinism).
#
# Classification: universal (§11.4.17)

set -u

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd)"
ROOT="$(cd "$TEST_DIR/../.." >/dev/null 2>&1 && pwd)"
SUITE="$TEST_DIR/test_action_prefix_grammar.sh"
LIB="$ROOT/scripts/action_prefix_lib.sh"
REG="$ROOT/actions/registry.yaml"

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)_$$"
META_DIR="$ROOT/qa-results/action_prefix/$RUN_ID/meta"
mkdir -p "$META_DIR"

# Pristine backups for restore (§11.4.84).
BK_LIB="$META_DIR/action_prefix_lib.sh.orig"
BK_REG="$META_DIR/registry.yaml.orig"
cp "$LIB" "$BK_LIB"
cp "$REG" "$BK_REG"

restore_all() {
  cp "$BK_LIB" "$LIB"
  cp "$BK_REG" "$REG"
}
trap restore_all EXIT INT TERM

PASS=0
FAIL=0

# run_suite → echoes 'PASS' or 'FAIL' (suite exit code), evidence captured.
run_suite() {
  local tag="$1"
  if AB_N_ITER=1 bash "$SUITE" > "$META_DIR/suite_$tag.log" 2>&1; then
    printf 'PASS'
  else
    printf 'FAIL'
  fi
}

# assert one mutation: mutate ($2 is a function) → suite must FAIL → restore →
# suite must PASS.
check_mutation() {
  local id="$1" mutate_fn="$2"
  restore_all
  # baseline already-restored — verify it PASSes first (sanity)
  local before; before="$(run_suite "${id}_before")"
  # apply the mutation
  "$mutate_fn"
  local mutated; mutated="$(run_suite "${id}_mutated")"
  # restore
  restore_all
  local after; after="$(run_suite "${id}_after")"
  {
    printf 'MUTATION: %s\nBEFORE(restored): %s\nMUTATED: %s\nAFTER(restored): %s\n' \
      "$id" "$before" "$mutated" "$after"
  } > "$META_DIR/$id.txt"
  if [ "$before" = "PASS" ] && [ "$mutated" = "FAIL" ] && [ "$after" = "PASS" ]; then
    PASS=$((PASS+1))
    printf 'PASS: %s (before=PASS mutated=FAIL after=PASS) [evidence: %s]\n' "$id" "$META_DIR/$id.txt"
  else
    FAIL=$((FAIL+1))
    printf 'FAIL: %s (before=%s mutated=%s after=%s) — expected before=PASS mutated=FAIL after=PASS\n' \
      "$id" "$before" "$mutated" "$after"
  fi
}

# ── Mutation functions (edit in place; restore_all undoes them) ───────────────

# M1 — break the slash-form regex in the python parse path so /ACTION never
# matches: rewrite the whole `re.match(... slash regex ...)` line so its action
# group can never match an uppercase token (`[QZ]{99}` matches nothing real).
mut_python_slash() {
  sed -i "s#^m = re.match(r'\^/.*\$#m = re.match(r'^/__NEVER_MATCHES_SLASH__\$', line)#" "$LIB"
}

# M2 — break the slash-form match in the awk parse path so the awk slash branch
# never fires: rewrite its anchor `if (line ~ /^\/.../ ...)` to require a literal
# leading `#` instead of `/`, so no real `/ACTION` input enters the slash branch.
mut_awk_slash() {
  sed -i 's#^      if (line ~ /\^\\/.*{$#      if (line ~ /^__NEVER_AWK_SLASH__/) {#' "$LIB"
}

# M3 — corrupt the python parse path's DEFAULT-namespace default so the bare
# forms (1 + 3) report namespace "WRONG". This diverges the python path from both
# the awk path (parity cases) AND the expected tuple (form-1/form-3 namespace
# cases) → the suite FAILs, proving the namespace-default + parity coverage is
# real and not a bluff.
mut_python_ns_default() {
  sed -i 's/ns = m.group(1) or "DEFAULT"/ns = m.group(1) or "WRONG"/g' "$LIB"
}

echo "=== META-TEST: paired §1.1 mutations for the §11.4.140 grammar suite ==="
check_mutation "M1-python-slash-regex" mut_python_slash
check_mutation "M2-awk-slash-match"    mut_awk_slash
check_mutation "M3-python-ns-default"  mut_python_ns_default

# Final restore handled by trap; explicit for clarity.
restore_all

echo "===================================================================="
echo "META RESULT: PASS=$PASS FAIL=$FAIL  (evidence: $META_DIR)"
if [ "$FAIL" -ne 0 ]; then
  echo "META-TEST FAILED — a mutation did not flip the suite (bluff-gate risk)."
  exit 1
fi
echo "ALL MUTATIONS CAUGHT"
exit 0
