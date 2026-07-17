#!/usr/bin/env bash
# cm_covenant_114_196_propagation_mutation_test.sh — §1.1 paired-mutation
# meta-test for CM-COVENANT-114-196-PROPAGATION (§11.4.196).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves CM-COVENANT-114-196-PROPAGATION is NOT a bluff gate: builds two
# disposable fleet fixtures under a temp dir — one with a carrier MISSING the
# `11.4.196` literal (MUST FAIL) and one where every carrier carries it (MUST
# PASS) — and asserts the gate reports the correct verdict on each. The pair
# only passes if the gate BOTH fails-on-mutation AND passes-on-clean, the
# §1.1 discriminator that the gate's assertion is real, not a tautology.
#
# Modeled verbatim on cm_covenant_114_187_propagation_mutation_test.sh (the
# sibling propagation-gate mutation pattern).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_covenant_114_196_propagation_mutation_test.sh
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Creates + removes a temp fixture dir under $TMPDIR (trap-cleaned on EXIT).
#   No network, no commit, no mutation of the real tree.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, the sibling cm_covenant_114_196_propagation.sh gate script. Parses
#   clean under bash -n.
#
# ── Cross-references ──────────────────────────────────────────────────────────
#   §1.1 (paired mutation), §11.4.196, §11.4.157 (five-carrier lockstep),
#   §11.4.28 (gate driven via --root, no hardcoded paths).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — gate FAILs-on-mutation AND PASSes-on-clean (the §1.1 proof holds).
#   1 — the gate did not FAIL on its planted mutation, or did not PASS clean.
#   2 — environment error (the gate script missing).
#
# Classification: universal (§11.4.17).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="${SCRIPT_DIR}/cm_covenant_114_196_propagation.sh"

[ -f "$GATE" ] || { echo "META: gate script missing: $GATE" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cm190_mut.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

rc=0
note() { echo "$@"; }
expect_fail() { # $1=desc  $2..=command
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        note "❌ META FAIL: ${desc} — gate PASSed on a planted violation (bluff gate!)"
        rc=1
    else
        note "✅ META OK:   ${desc} — gate correctly FAILed on the mutation"
    fi
}
expect_pass() { # $1=desc  $2..=command
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        note "✅ META OK:   ${desc} — gate correctly PASSed on clean fixture"
    else
        note "❌ META FAIL: ${desc} — gate FAILed on a clean fixture (false alarm!)"
        rc=1
    fi
}

echo "======================================================================"
echo "§1.1 paired-mutation meta-test for CM-COVENANT-114-196-PROPAGATION"
echo "fixtures under: $TMP"
echo "======================================================================"

# --- MUTATED fleet: a carrier MISSING the 11.4.196 literal ---
MUT_FLEET="$TMP/prop_mut"
mkdir -p "$MUT_FLEET/sub"
# good carrier (carries the anchor)
printf '## §11.4.196 work-to-track/branch binding enforcement\nanchor 11.4.196 present here\n' > "$MUT_FLEET/AGENTS.md"
# MUTATION: this carrier omits the literal entirely
printf '# Project carrier\nno anchor here at all\n' > "$MUT_FLEET/CLAUDE.md"
expect_fail "propagation gate / missing-anchor carrier" \
    bash "$GATE" --root "$MUT_FLEET" --quiet

# --- CLEAN fleet: every carrier carries the literal ---
CLEAN_FLEET="$TMP/prop_clean"
mkdir -p "$CLEAN_FLEET"
for c in CLAUDE.md AGENTS.md QWEN.md GEMINI.md; do
    printf '# carrier %s\n§11.4.196 — work-to-track/branch binding enforcement anchor literal 11.4.196\n' "$c" \
        > "$CLEAN_FLEET/$c"
done
expect_pass "propagation gate / clean fleet" \
    bash "$GATE" --root "$CLEAN_FLEET" --quiet

echo "======================================================================"
if [ "$rc" -eq 0 ]; then
    echo "✅ META PASS: CM-COVENANT-114-196-PROPAGATION is a genuine (non-bluff) gate"
else
    echo "❌ META FAIL: CM-COVENANT-114-196-PROPAGATION failed the §1.1 discriminator"
fi
echo "======================================================================"
exit "$rc"
