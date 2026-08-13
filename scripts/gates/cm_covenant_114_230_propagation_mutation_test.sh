#!/usr/bin/env bash
# cm_covenant_114_230_propagation_mutation_test.sh — §1.1 paired-mutation
# meta-test for CM-COVENANT-114-230-PROPAGATION (§11.4.230).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves CM-COVENANT-114-230-PROPAGATION is NOT a bluff gate under the
# §11.4.227(B) anchor-block-integrity contract (block-starts, not bare
# literals; exactly-once; lockstep-identical BY FULL BLOCK CONTENT, not just
# the heading line) AND under the §11.4.35 pointer-inheritance carve-out —
# INCLUDING that the pointer predicate is FENCE-AWARE (coordinator B2 fix):
# the real constitution mirrors quote the `## INHERITED FROM ...` heading
# INSIDE a fenced ```markdown code block (the "How inheritance works"
# EXAMPLE) as a mere CARRIER, and a bare (non-fence-tracking) grep would
# mis-classify a mirror that LOST its real anchor block as an honest
# POINTER-INHERITANCE-SKIP instead of the MISSING/FAIL it actually is.
# Builds eight disposable fleet fixtures under a temp dir:
#   1. MISSING        — a carrier with only a mid-body CITATION of the
#                       anchor (no line-anchored block-start at all)
#                       -> gate MUST FAIL (proves §11.4.201(7)(a)
#                       structure-not-substring: a carrier mentioning the
#                       anchor mid-sentence does NOT satisfy the block
#                       requirement).
#   2. DUPLICATED     — a carrier with the SAME block-start line appearing
#                       TWICE -> gate MUST FAIL (the F7-class duplication
#                       the legacy bare-literal-presence gates could not
#                       see).
#   3. DIVERGENT-HEAD — every carrier has exactly one block-start, but one
#                       carrier's HEADING line differs byte-for-byte from
#                       the others -> gate MUST FAIL (§11.4.157 lockstep
#                       violation).
#   4. DIVERGENT-BODY — every carrier's block-START LINE is byte-identical,
#                       but one carrier's BODY line (the line after the
#                       heading, still inside the same block) differs
#                       -> gate MUST FAIL. This is the coordinator's I1
#                       finding made concrete: a heading-only hash (the
#                       gate's PRE-FIX behaviour) would have missed this
#                       divergence entirely (DIVERGENT=0) since the
#                       heading lines matched; the fixed gate hashes the
#                       FULL block (heading through the line before the
#                       next block-start / EOF) and therefore catches it.
#   5. POINTER-OK     — a clean 4-carrier fleet PLUS a NESTED §11.4.35
#                       pointer-inheritance carrier (a subdir file whose
#                       first content line is a line-anchored
#                       `## INHERITED FROM constitution/CLAUDE.md` heading,
#                       carrying ZERO block-starts) -> gate MUST PASS. This
#                       is the coordinator's B1 finding made concrete: a
#                       pointer-inheritance mirror legitimately carries no
#                       per-anchor blocks and MUST be reported as an honest
#                       POINTER-INHERITANCE-SKIP, never MISSING/FAIL — the
#                       exact false-positive class §11.4.201(1) forbids.
#   6. FENCE-MISSING  — a carrier built from the REAL constitution mirror's
#                       "How inheritance works" section shape (CLAUDE.md
#                       lines ~86-96: a fenced ```markdown code block
#                       quoting `## INHERITED FROM constitution/CLAUDE.md`)
#                       that has LOST its real §11.4.230 block -> gate MUST
#                       FAIL with MISSING (NOT a false-positive
#                       POINTER-INHERITANCE-SKIP). This is the coordinator's
#                       B2 finding made permanent: the reviewer PROVED that
#                       deleting CLAUDE.md's real block while its fenced
#                       inheritance-example remained made the PRE-FIX gate
#                       report SKIP + PASS + exit 0 on a required mirror
#                       that lost its anchor -- the exact regression the
#                       gate exists to catch, masked. Without this fixture
#                       that regression is invisible to the §1.1 pair.
#   7. POINTER-OK     — a clean 4-carrier fleet PLUS a NESTED §11.4.35
#                       pointer-inheritance carrier (a subdir file whose
#                       first content line is a REAL, non-fenced,
#                       line-anchored `## INHERITED FROM constitution/
#                       CLAUDE.md` heading, carrying ZERO block-starts)
#                       -> gate MUST PASS. This is the coordinator's B1
#                       finding made concrete: a genuine pointer-inheritance
#                       mirror legitimately carries no per-anchor blocks and
#                       MUST be reported as an honest
#                       POINTER-INHERITANCE-SKIP, never MISSING/FAIL — the
#                       exact false-positive class §11.4.201(1) forbids.
#                       DOUBLES as the coordinator's negative-control (8):
#                       proves the fence-awareness fix (fixture 6) did NOT
#                       regress the genuine-pointer-carve-out (fixture 7) —
#                       a real unfenced pointer heading still SKIPs/PASSes.
#   8. CLEAN          — every REAL carrier has exactly one byte-identical
#                       (full-block) block-start -> gate MUST PASS.
# The mutation pair only proves the gate is genuine if it BOTH fails on every
# planted violation AND passes on every clean/honestly-exempt fixture — the
# §1.1 discriminator.
#
# Modeled on cm_covenant_114_213_propagation_mutation_test.sh's harness shape
# (temp fixture dir, expect_fail/expect_pass helpers, trap cleanup), extended
# to cover the §11.4.227(B) failure classes this gate detects PLUS the
# §11.4.35 pointer-inheritance honest-exemption class (fence-aware, per the
# coordinator's B2 remediation).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_covenant_114_230_propagation_mutation_test.sh
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Creates + removes a temp fixture dir under $TMPDIR (trap-cleaned on EXIT).
#   No network, no commit, no mutation of the real tree.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, the sibling cm_covenant_114_230_propagation.sh gate script. Parses
#   clean under bash -n.
#
# ── Cross-references ──────────────────────────────────────────────────────────
#   §1.1 (paired mutation), §11.4.230, §11.4.227(B) (anchor-block integrity),
#   §11.4.201(1)/(7)(a) (false-positive-refusal-is-a-FAIL-bluff /
#   structure-not-substring), §11.4.157 (five-carrier lockstep), §11.4.35
#   (pointer-inheritance carve-out), §11.4.28 (gate driven via --root, no
#   hardcoded paths).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — the gate FAILs on all five planted violations AND PASSes on all
#       three honest/clean fixtures (the §1.1 proof holds).
#   1 — the gate did not FAIL on at least one planted violation, or did not
#       PASS on a clean/honestly-exempt fixture.
#   2 — environment error (the gate script missing).
#
# Classification: universal (§11.4.17).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="${SCRIPT_DIR}/cm_covenant_114_230_propagation.sh"
ANCHOR="11.4.230"

[ -f "$GATE" ] || { echo "META: gate script missing: $GATE" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cm230_mut.XXXXXX")"
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
echo "§1.1 paired-mutation meta-test for CM-COVENANT-114-230-PROPAGATION"
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
# corrupt exactly one carrier: replace its block-start with a mid-sentence
# citation of the SAME anchor (a carrier, per §11.4.201(7)(a), not a block).
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

# --- MUTATION 3: DIVERGENT-HEAD — every carrier has exactly one block, HEADING differs ---
MUT_DIVERGENT_HEAD="$TMP/mut_divergent_head"
mkdir -p "$MUT_DIVERGENT_HEAD"
for c in CLAUDE.md AGENTS.md QWEN.md GEMINI.md; do
    printf '%s\n%s\n' "$BLOCK_LINE" "$BODY_LINE" > "$MUT_DIVERGENT_HEAD/$c"
done
printf '**§%s — a DIFFERENT (divergent) heading than its siblings.**\n%s\n' "$ANCHOR" "$BODY_LINE" > "$MUT_DIVERGENT_HEAD/QWEN.md"
expect_fail "DIVERGENT-HEAD (one carrier's heading line differs, §11.4.157 lockstep)" \
    bash "$GATE" --root "$MUT_DIVERGENT_HEAD" --quiet

# --- MUTATION 4: DIVERGENT-BODY — heading lines byte-identical, BODY line differs ---
# This is the coordinator's I1 finding made concrete: the pre-fix gate hashed
# ONLY the heading line, so this exact mutation (identical headings, divergent
# bodies) would have sailed through as DIVERGENT=0 -- a bluff gate for body
# drift. The fixed gate hashes the FULL block and MUST catch it.
MUT_DIVERGENT_BODY="$TMP/mut_divergent_body"
mkdir -p "$MUT_DIVERGENT_BODY"
for c in CLAUDE.md AGENTS.md QWEN.md GEMINI.md; do
    printf '%s\n%s\n' "$BLOCK_LINE" "$BODY_LINE" > "$MUT_DIVERGENT_BODY/$c"
done
printf '%s\nA COMPLETELY DIFFERENT body line than every other carrier — same heading, divergent content.\n' \
    "$BLOCK_LINE" > "$MUT_DIVERGENT_BODY/GEMINI.md"
expect_fail "DIVERGENT-BODY (identical heading, divergent body — the I1 body-drift class)" \
    bash "$GATE" --root "$MUT_DIVERGENT_BODY" --quiet

# --- FIXTURE 6: FENCE-MISSING — real-mirror-shaped carrier lost its block, ---
# --- still carries the FENCED "How inheritance works" EXAMPLE            ---
# This is the coordinator's B2 finding made permanent. Built from the REAL
# shape every constitution mirror carries (CLAUDE.md lines ~86-96 / GEMINI.md
# ~33): a fenced ```markdown code block quoting a `## INHERITED FROM
# constitution/CLAUDE.md` heading as a documentation EXAMPLE. The reviewer
# PROVED that deleting CLAUDE.md's real §11.4.230 block while this fenced
# example remained made the PRE-FIX gate's bare (non-fence-tracking) grep
# match the fenced heading, report an honest-LOOKING
# POINTER-INHERITANCE-SKIP, and exit 0 -- silently masking a required mirror
# that lost its anchor block, the EXACT regression this gate exists to
# catch. The FIXED (fence-aware) gate MUST see through the fence and report
# MISSING.
MUT_FENCE_MISSING="$TMP/mut_fence_missing"
mkdir -p "$MUT_FENCE_MISSING"
for c in CLAUDE.md AGENTS.md QWEN.md GEMINI.md; do
    printf '%s\n%s\n' "$BLOCK_LINE" "$BODY_LINE" > "$MUT_FENCE_MISSING/$c"
done
# CLAUDE.md loses its real block-start entirely; only the fenced EXAMPLE
# (quoting the real inheritance-pointer heading) remains -- reproducing the
# real "How inheritance works" section shape.
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
expect_fail "FENCE-MISSING (block lost, only the fenced inheritance EXAMPLE remains — the B2 regression)" \
    bash "$GATE" --root "$MUT_FENCE_MISSING" --quiet

# --- FIXTURE 7: POINTER-OK — clean fleet + a nested §11.4.35 pointer-inheritance carrier ---
# This is the coordinator's B1 finding made concrete: a pointer-inheritance
# mirror (## INHERITED FROM ...) carrying ZERO block-starts MUST be an honest
# POINTER-INHERITANCE-SKIP, never MISSING/FAIL. Without this fixture the B1
# defect (false-positive refusal on a legitimate §11.4.35 consumer) is
# invisible to the §1.1 pair -- exactly like the real helix_perf_cache
# submodule case the gates previously mis-flagged as MISSING on the real tree.
# Also serves as the coordinator's negative-control (8): proves the fixture-6
# fence-awareness fix did NOT regress this genuine (unfenced) pointer case.
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
    echo "✅ META PASS: CM-COVENANT-114-230-PROPAGATION is a genuine (non-bluff) gate"
else
    echo "❌ META FAIL: CM-COVENANT-114-230-PROPAGATION failed the §1.1 discriminator"
fi
echo "======================================================================"
exit "$rc"
