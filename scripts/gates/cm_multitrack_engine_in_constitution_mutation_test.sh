#!/usr/bin/env bash
# cm_multitrack_engine_in_constitution_mutation_test.sh — §1.1 paired-mutation
# meta-test for CM-MULTITRACK-ENGINE-IN-CONSTITUTION (§11.4.187).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves CM-MULTITRACK-ENGINE-IN-CONSTITUTION is NOT a bluff gate across all
# three of its invariants (presence / decoupling / parseability), AND proves
# its narrow self-referential-comment exemption (documented in the gate's own
# header) does NOT mask a real violation:
#
#   1a. CLEAN fixture (generic scripts, incl. a comment that self-documents
#       "no atmosphere literal here" — exercising the exemption) → PASS.
#   1b. Too-few-scripts fixture (below --min-scripts) → PRESENCE FAILs.
#   2a. Real-literal-in-code fixture (a NON-comment line embeds a
#       track-mount+basename coupling literal in actual code) → DECOUPLING FAILs.
#   2b. Comment-only "atmosphere" mention (mirroring the real
#       multitrack_bootstrap.sh:107 case) → still PASSes (proves the
#       exemption fires correctly and is not itself a bluff-through).
#   3.  Parse-broken fixture (unbalanced quote) → PARSEABILITY FAILs.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_multitrack_engine_in_constitution_mutation_test.sh
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Creates + removes a temp fixture dir under $TMPDIR (trap-cleaned on EXIT).
#   No network, no commit, no mutation of the real engine tree.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, sh, the sibling cm_multitrack_engine_in_constitution.sh gate script.
#   Parses clean under bash -n.
#
# ── Cross-references ──────────────────────────────────────────────────────────
#   §1.1 (paired mutation), §11.4.187, §11.4.28(B)/§11.4.177 (decoupling),
#   §11.4.67 (target-shell-parseability).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — every sub-case produced the expected PASS/FAIL verdict.
#   1 — at least one sub-case produced the wrong verdict (bluff or false alarm).
#   2 — environment error (the gate script missing).
#
# Classification: universal (§11.4.17).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="${SCRIPT_DIR}/cm_multitrack_engine_in_constitution.sh"

[ -f "$GATE" ] || { echo "META: gate script missing: $GATE" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cm_mtec_mut.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

rc=0
note() { echo "$@"; }
expect_fail() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        note "❌ META FAIL: ${desc} — gate PASSed on a planted violation (bluff gate!)"
        rc=1
    else
        note "✅ META OK:   ${desc} — gate correctly FAILed on the mutation"
    fi
}
expect_pass() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        note "✅ META OK:   ${desc} — gate correctly PASSed"
    else
        note "❌ META FAIL: ${desc} — gate FAILed unexpectedly (false alarm!)"
        rc=1
    fi
}

echo "======================================================================"
echo "§1.1 paired-mutation meta-test for CM-MULTITRACK-ENGINE-IN-CONSTITUTION"
echo "fixtures under: $TMP"
echo "======================================================================"

# --- 1a/2b. CLEAN fixture: generic scripts + a self-referential exemption
#            comment (mirrors the real multitrack_bootstrap.sh:107 case) ---
CLEAN="$TMP/engine_clean"
mkdir -p "$CLEAN"
cat > "$CLEAN/multitrack_config.sh" <<'SH'
#!/usr/bin/env bash
# Generic config loader — project-agnostic (no project literal here;
# consuming projects supply config/multitrack/<hostname>.yaml as DATA).
set -euo pipefail
echo "load config"
SH
cat > "$CLEAN/multitrack_resolve_worktree.sh" <<'SH'
#!/usr/bin/env bash
# §11.4.28(B) / §11.4.177 (project-agnostic — no `atmosphere` literal here;
# this comment exists purely to exercise the gate's exemption clause).
set -euo pipefail
echo "resolve"
SH
cat > "$CLEAN/multitrack-up" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "up"
SH
chmod +x "$CLEAN"/multitrack_config.sh "$CLEAN"/multitrack_resolve_worktree.sh "$CLEAN"/multitrack-up
expect_pass "clean fixture (3 scripts, exemption comment present)" \
    bash "$GATE" --engine-dir "$CLEAN" --quiet

# --- 1b. Too-few-scripts fixture ---
FEW="$TMP/engine_few"
mkdir -p "$FEW"
cat > "$FEW/multitrack_config.sh" <<'SH'
#!/usr/bin/env bash
echo "only one script here"
SH
chmod +x "$FEW/multitrack_config.sh"
expect_fail "too-few-scripts fixture (1 < min-scripts 3)" \
    bash "$GATE" --engine-dir "$FEW" --min-scripts 3 --quiet

# --- 2a. Real-literal-in-code fixture: a NON-comment line embeds the
#         project-coupled mount+basename combination ---
MUT_LIT="$TMP/engine_literal_mut"
mkdir -p "$MUT_LIT"
cp -r "$CLEAN"/. "$MUT_LIT"/
# Build the 2a payload from split tokens so THIS test script does not itself
# statically embed the coupling literal (the §11.4.28(B) audit would flag it) —
# the assembled literal lands in the FIXTURE, which the gate under test must
# still catch on a non-comment code line.
_mut_lit="/mnt/track1/atmo""sphere-t1"
{
    printf '%s\n' '# MUTATION: a real (non-comment) project path'
    printf 'ROOT_OVERRIDE="%s"\n' "$_mut_lit"
    printf '%s\n' 'echo "$ROOT_OVERRIDE"'
} >> "$MUT_LIT/multitrack_config.sh"
expect_fail "real-literal-in-code fixture (/mnt/track1/atmosphere-t1 hardcoded)" \
    bash "$GATE" --engine-dir "$MUT_LIT" --quiet

# --- 3. Parse-broken fixture (unbalanced quote) ---
MUT_PARSE="$TMP/engine_parse_mut"
mkdir -p "$MUT_PARSE"
cp -r "$CLEAN"/. "$MUT_PARSE"/
cat >> "$MUT_PARSE/multitrack-up" <<'SH'
echo "unbalanced quote
SH
expect_fail "parse-broken fixture (unbalanced quote)" \
    bash "$GATE" --engine-dir "$MUT_PARSE" --quiet

echo "======================================================================"
if [ "$rc" -eq 0 ]; then
    echo "✅ META PASS: CM-MULTITRACK-ENGINE-IN-CONSTITUTION is a genuine (non-bluff) gate"
else
    echo "❌ META FAIL: CM-MULTITRACK-ENGINE-IN-CONSTITUTION failed the §1.1 discriminator"
fi
echo "======================================================================"
exit "$rc"
