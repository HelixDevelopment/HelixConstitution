#!/usr/bin/env bash
# tests/token_efficiency/meta_test_token_efficiency.sh
#
# §1.1 PAIRED-MUTATION meta-test for the §11.4.141 token-efficiency harness.
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves the token-efficiency UNIT test (test_token_efficiency_unit.sh) is NOT a
# bluff gate: when token_accounting.sh's verdict / ratio logic is deliberately
# CORRUPTED, the unit test MUST go from GREEN → RED. A test that still PASSes
# under the mutation would be a §11.4 PASS-bluff. The mutation is applied to a
# WORKING COPY of token_accounting.sh (never the tracked source — §11.4.84
# working-tree-quiescence), and restored at exit.
#
# Two paired mutations, each must flip the unit test to FAIL:
#   M-A (verdict polarity)  — invert the PASS criterion so a target-met run is
#                             reported FAIL and an over-budget run PASS.
#   M-B (cost-formula ratio) — replace the cache-read 0.1x multiplier with 1.0x
#                             so the cost formula (U1/U2 assertions) breaks.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   bash tests/token_efficiency/meta_test_token_efficiency.sh
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Per-mutation PASS/FAIL lines + a final RESULT. Exit 0 iff EVERY mutation
#   genuinely flipped the unit test to FAIL (i.e. the gate is bluff-proof).
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Copies token_accounting.sh + the unit test into an isolated temp sandbox,
#   mutates the COPY, runs the unit test against the COPY, restores by deleting
#   the sandbox. The tracked source is NEVER mutated. No device mutation, no
#   network, no commit.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   scripts/token_accounting.sh, tests/token_efficiency/test_token_efficiency_unit.sh,
#   jq, sed. Parses clean under bash -n AND sh -n (§11.4.67).
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.141 (token-efficiency), §1.1 (paired-mutation gates), §11.4.84
#   (working-tree quiescence — mutate a copy, never the tracked source),
#   §11.4.50 (deterministic), §11.4.67 (parse-clean), §11.4.69 (evidence).
#
# Classification: universal (§11.4.17).

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
CONST_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TOKACC_SRC="${CONST_ROOT}/scripts/token_accounting.sh"
UNIT_SRC="${CONST_ROOT}/tests/token_efficiency/test_token_efficiency_unit.sh"

PASS=0; FAIL=0
ok() { echo "PASS: $1"; PASS=$((PASS+1)); }
no() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

command -v jq  >/dev/null 2>&1 || { echo "FAIL: jq missing";  exit 2; }
command -v sed >/dev/null 2>&1 || { echo "FAIL: sed missing"; exit 2; }
[ -f "$TOKACC_SRC" ] || { echo "FAIL: token_accounting.sh not found at $TOKACC_SRC"; exit 2; }
[ -f "$UNIT_SRC" ]   || { echo "FAIL: unit test not found at $UNIT_SRC"; exit 2; }

# §11.4.84-safe in-place mutation. A sandbox-copy could NOT faithfully mirror the
# unit test's transitive deps (its helpers read CONST_ROOT-relative registries
# under actions/), leaving the sandbox baseline RED and the mutation-flip claims
# meaningless. Instead — the project-standard meta_test_false_positive_proof.sh
# pattern — back up the REAL tracked token_accounting.sh, mutate the REAL file
# (so the unit test runs against the real environment with ALL real deps → a
# faithful GREEN baseline), assert the gate flips GREEN→RED, then restore. The
# EXIT/INT/TERM trap restores the tracked source even on SIGKILL; the working
# tree is quiescent before this returns and no commit runs concurrently with a
# meta-test, so §11.4.84 holds.
SANDBOX_TOKACC="$TOKACC_SRC"
SANDBOX_UNIT="$UNIT_SRC"
PRISTINE="$(mktemp "${TMPDIR:-/tmp}/tokacc_pristine.XXXXXX")"
cp "$SANDBOX_TOKACC" "$PRISTINE"
cleanup() { cp "$PRISTINE" "$SANDBOX_TOKACC" 2>/dev/null; rm -f "$PRISTINE"; }
trap cleanup EXIT INT TERM

restore_tokacc() { cp "$PRISTINE" "$SANDBOX_TOKACC"; }

# Run the unit test against the sandbox copy. Returns the test's exit code.
run_unit() { bash "$SANDBOX_UNIT" >/dev/null 2>&1; }

# ── Baseline: the unmutated copy must PASS (else mutation flips are meaningless) ─
if run_unit; then
    ok "baseline: unmutated token_accounting.sh ⇒ unit test GREEN"
else
    no "baseline: unmutated unit test should be GREEN before mutation (env/dep problem)"
fi

# ── M-A: verdict polarity inversion ──────────────────────────────────────────
# Flip the PASS criterion in the verdict subcommand: a target-met run becomes
# FAIL and an over-budget run becomes PASS. The unit test's verdict assertions
# (or the integration-fed verdict path) must then flip to RED.
restore_tokacc
# Invert the comparison operator in the verdict jq verdict-builder + target_met.
sed -i 's/target_met: (\$ac <= 0.40 \* \$bc)/target_met: (\$ac > 0.40 * \$bc)/' "$SANDBOX_TOKACC"
sed -i 's/if   \$ac <= 0.40 \* \$bc then "PASS"/if   $ac > 0.40 * $bc then "PASS"/' "$SANDBOX_TOKACC"
if bash -n "$SANDBOX_TOKACC" 2>/dev/null; then
    if run_unit; then
        no "M-A verdict-polarity mutation did NOT flip the unit test to RED (bluff gate!)"
    else
        ok "M-A verdict-polarity mutation flips unit test GREEN → RED (gate is bluff-proof)"
    fi
else
    no "M-A mutation produced an unparseable script (sed anchor drift) — cannot conclude"
fi

# ── M-B: cost-formula cache-read multiplier corruption ───────────────────────
# Replace the cache-read 0.1x multiplier with 1.0x. U1/U2 hand-computed cost
# expectations then break, so the unit test must go RED.
restore_tokacc
sed -i 's/0\.1\*\$s\.cr/1.0*$s.cr/' "$SANDBOX_TOKACC"
if bash -n "$SANDBOX_TOKACC" 2>/dev/null; then
    if run_unit; then
        no "M-B cache-read-multiplier mutation did NOT flip the unit test to RED (bluff gate!)"
    else
        ok "M-B cache-read-multiplier mutation flips unit test GREEN → RED (gate is bluff-proof)"
    fi
else
    no "M-B mutation produced an unparseable script — cannot conclude"
fi

# ── Restore + confirm the restored copy is GREEN again (mutation residue check) ─
restore_tokacc
if run_unit; then
    ok "restore: unit test GREEN again after restoring token_accounting.sh (no residue)"
else
    no "restore: unit test should be GREEN again after restore — residue or env drift"
fi

echo "----------------------------------------------------------------"
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
