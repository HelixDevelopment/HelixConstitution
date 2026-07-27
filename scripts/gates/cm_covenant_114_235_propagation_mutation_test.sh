#!/usr/bin/env bash
# cm_covenant_114_235_propagation_mutation_test.sh — §1.1 paired-mutation
# meta-test for CM-COVENANT-114-235-PROPAGATION (§11.4.235).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves CM-COVENANT-114-235-PROPAGATION is NOT a bluff gate under the
# §11.4.227(B) anchor-block-integrity contract (block-starts, not bare
# literals; exactly-once; lockstep-identical BY FULL BLOCK CONTENT, not just
# the heading line) AND under the §11.4.35 pointer-inheritance carve-out
# (fence-aware). Builds eight disposable fleet fixtures under a temp dir:
#   1. MISSING        — a carrier with only a mid-body CITATION of the anchor
#                       (no line-anchored block-start) -> gate MUST FAIL.
#   2. DUPLICATED     — a carrier with the SAME block-start line TWICE (the
#                       F7 class) -> gate MUST FAIL.
#   3. DIVERGENT-HEAD — one block per carrier, one HEADING line differs
#                       -> gate MUST FAIL (§11.4.157 lockstep).
#   4. DIVERGENT-BODY — heading lines byte-identical, one BODY line differs
#                       -> gate MUST FAIL (the full-block-hash class).
#   6. FENCE-MISSING  — a real-mirror-shaped carrier that LOST its block but
#                       still carries the fenced "How inheritance works"
#                       inheritance EXAMPLE -> gate MUST FAIL (fence-aware
#                       predicate sees through the fenced carrier).
#   7. POINTER-OK     — a clean 4-carrier fleet PLUS a nested §11.4.35
#                       pointer-inheritance carrier (zero block-starts)
#                       -> gate MUST PASS (honest SKIP, not FAIL) + doubles
#                       as the negative-control for fixture 6.
#   8. CLEAN          — every carrier has exactly one byte-identical
#                       (full-block) block-start -> gate MUST PASS.
# The pair only proves the gate genuine if it BOTH FAILs on every planted
# violation AND PASSes on every clean/honestly-exempt fixture (§1.1
# discriminator).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_covenant_114_235_propagation_mutation_test.sh
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Creates + removes a temp fixture dir under $TMPDIR (trap-cleaned on EXIT).
#   No network, no commit, no mutation of the real tree.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, the sibling cm_covenant_114_235_propagation.sh gate script. Parses
#   clean under bash -n.
#
# ── Cross-references ──────────────────────────────────────────────────────────
#   §1.1, §11.4.235, §11.4.227(B), §11.4.201(1)/(7)(a), §11.4.157, §11.4.35,
#   §11.4.28.
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — the gate FAILs on all five planted violations AND PASSes on all
#       clean/honestly-exempt fixtures (the §1.1 proof holds).
#   1 — the gate did not FAIL on a planted violation, or did not PASS on a
#       clean/honestly-exempt fixture.
#   2 — environment error (the gate script missing).
#
# Classification: universal (§11.4.17).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="${SCRIPT_DIR}/cm_covenant_114_235_propagation.sh"
ANCHOR="11.4.235"

[ -f "$GATE" ] || { echo "META: gate script missing: $GATE" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cm235_mut.XXXXXX")"
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
echo "§1.1 paired-mutation meta-test for CM-COVENANT-114-235-PROPAGATION"
echo "fixtures under: $TMP"
echo "======================================================================"

BLOCK_LINE="**§${ANCHOR} — canonical fixture block-start (identical across every carrier).**"
BODY_LINE="Fixture body line carrying the mandate's substantive text, identical across every carrier."

# --- MUTATION 1: MISSING — mid-body citation only, no block-start ---
MUT_MISSING="$TMP/mut_missing"
mkdir -p "$MUT_MISSING"
for c in CLAUDE.md AGENTS.md QWEN.md GEMINI.md; do
    printf '%s\n%s\n' "$BLOCK_LINE" "$BODY_LINE" > "$MUT_MISSING/$c"
done
printf 'This section composes with §%s(A) as a mid-body citation only.\n' "$ANCHOR" > "$MUT_MISSING/CLAUDE.md"
expect_fail "MISSING (mid-body citation is not a block-start)" \
    bash "$GATE" --root "$MUT_MISSING" --quiet

# --- MUTATION 2: DUPLICATED — one carrier has the block-start line twice ---
MUT_DUP="$TMP/mut_dup"
mkdir -p "$MUT_DUP"
for c in CLAUDE.md AGENTS.md QWEN.md GEMINI.md; do
    printf '%s\n%s\n' "$BLOCK_LINE" "$BODY_LINE" > "$MUT_DUP/$c"
done
printf '%s\n%s\n\n%s\n%s\n' "$BLOCK_LINE" "$BODY_LINE" "$BLOCK_LINE" "$BODY_LINE" > "$MUT_DUP/AGENTS.md"
expect_fail "DUPLICATED (one carrier carries the block twice, F7-class)" \
    bash "$GATE" --root "$MUT_DUP" --quiet

# --- MUTATION 3: DIVERGENT-HEAD — every carrier has one block, HEADING differs ---
MUT_DIVERGENT_HEAD="$TMP/mut_divergent_head"
mkdir -p "$MUT_DIVERGENT_HEAD"
for c in CLAUDE.md AGENTS.md QWEN.md GEMINI.md; do
    printf '%s\n%s\n' "$BLOCK_LINE" "$BODY_LINE" > "$MUT_DIVERGENT_HEAD/$c"
done
printf '**§%s — a DIFFERENT (divergent) heading than its siblings.**\n%s\n' "$ANCHOR" "$BODY_LINE" > "$MUT_DIVERGENT_HEAD/QWEN.md"
expect_fail "DIVERGENT-HEAD (one carrier's heading line differs, §11.4.157 lockstep)" \
    bash "$GATE" --root "$MUT_DIVERGENT_HEAD" --quiet

# --- MUTATION 4: DIVERGENT-BODY — heading lines byte-identical, BODY line differs ---
MUT_DIVERGENT_BODY="$TMP/mut_divergent_body"
mkdir -p "$MUT_DIVERGENT_BODY"
for c in CLAUDE.md AGENTS.md QWEN.md GEMINI.md; do
    printf '%s\n%s\n' "$BLOCK_LINE" "$BODY_LINE" > "$MUT_DIVERGENT_BODY/$c"
done
printf '%s\nA COMPLETELY DIFFERENT body line than every other carrier — same heading, divergent content.\n' \
    "$BLOCK_LINE" > "$MUT_DIVERGENT_BODY/GEMINI.md"
expect_fail "DIVERGENT-BODY (identical heading, divergent body — the full-block-hash class)" \
    bash "$GATE" --root "$MUT_DIVERGENT_BODY" --quiet

# --- FIXTURE 6: FENCE-MISSING — real-mirror-shaped carrier lost its block, ---
# --- still carries the FENCED "How inheritance works" EXAMPLE            ---
MUT_FENCE_MISSING="$TMP/mut_fence_missing"
mkdir -p "$MUT_FENCE_MISSING"
for c in CLAUDE.md AGENTS.md QWEN.md GEMINI.md; do
    printf '%s\n%s\n' "$BLOCK_LINE" "$BODY_LINE" > "$MUT_FENCE_MISSING/$c"
done
cat > "$MUT_FENCE_MISSING/CLAUDE.md" <<'FENCE_EOF'
## How inheritance works

A consuming project's root `CLAUDE.md` MUST start with a clearly-marked
inheritance pointer:

```markdown
## INHERITED FROM constitution/CLAUDE.md

All rules in `constitution/CLAUDE.md` (and the `constitution/Constitution.md`
it references) apply unconditionally. The project-specific rules below
extend them.
```

Claude Code supports the `@path/to/file` import syntax natively.
FENCE_EOF
expect_fail "FENCE-MISSING (block lost, only the fenced inheritance EXAMPLE remains)" \
    bash "$GATE" --root "$MUT_FENCE_MISSING" --quiet

# --- FIXTURE 7: POINTER-OK — clean fleet + a nested §11.4.35 pointer-inheritance carrier ---
POINTER_FLEET="$TMP/prop_pointer_ok"
mkdir -p "$POINTER_FLEET/nested_submodule"
for c in CLAUDE.md AGENTS.md QWEN.md GEMINI.md; do
    printf '%s\n%s\n' "$BLOCK_LINE" "$BODY_LINE" > "$POINTER_FLEET/$c"
done
printf '## INHERITED FROM constitution/CLAUDE.md\n\nAll rules apply unconditionally. Engine-rules-only mirror, zero restated anchor blocks.\n' \
    > "$POINTER_FLEET/nested_submodule/CLAUDE.md"
expect_pass "POINTER-OK (nested §11.4.35 pointer carrier with zero blocks -> honest SKIP, not FAIL)" \
    bash "$GATE" --root "$POINTER_FLEET" --quiet

# --- FIXTURE 8: CLEAN fleet: every carrier carries exactly one byte-identical (full-block) block ---
CLEAN_FLEET="$TMP/prop_clean"
mkdir -p "$CLEAN_FLEET"
for c in CLAUDE.md AGENTS.md QWEN.md GEMINI.md; do
    printf '%s\n%s\n' "$BLOCK_LINE" "$BODY_LINE" > "$CLEAN_FLEET/$c"
done
expect_pass "clean fleet (exactly-once + byte-identical full-block everywhere)" \
    bash "$GATE" --root "$CLEAN_FLEET" --quiet

echo "======================================================================"
if [ "$rc" -eq 0 ]; then
    echo "✅ META PASS: CM-COVENANT-114-235-PROPAGATION is a genuine (non-bluff) gate"
else
    echo "❌ META FAIL: CM-COVENANT-114-235-PROPAGATION failed the §1.1 discriminator"
fi
echo "======================================================================"
exit "$rc"
