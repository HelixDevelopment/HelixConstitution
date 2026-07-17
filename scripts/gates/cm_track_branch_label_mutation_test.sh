#!/usr/bin/env bash
# cm_track_branch_label_mutation_test.sh — §1.1 paired-mutation meta-test for
# CM-TRACK-BRANCH-LABEL (§11.4.182).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves CM-TRACK-BRANCH-LABEL is NOT a bluff gate — i.e. its load-bearing
# ALIAS-VALIDATION invariant genuinely FAILs when the hook under test does NOT
# validate the alias field (the exact PRE-FIX behaviour: a format-only hook that
# lets a stale `claude4`-while-live-`claude3` label through):
#
#   1. CLEAN         — the REAL shipped hook + labeler + doc → gate PASSes.
#   2a. MUTATION (the load-bearing §1.1 pair) — a FORMAT-ONLY stub hook that
#       checks the label FORMAT but SKIPS the alias check → gate FAILs
#       (ALIAS-VALIDATION: the WRONG alias is not blocked).
#   2b. RESTORED     — re-run CLEAN → gate PASSes again (proves the FAIL was the
#       mutation, not a leaked side-effect).
#   3. DOC-MISSING   — point --doc at a non-existent path → gate FAILs (DOC).
#   4. PARSE-BROKEN  — a hook copy with an unbalanced quote → gate FAILs
#       (PARSEABILITY).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_track_branch_label_mutation_test.sh
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Creates + removes a temp fixture dir under $TMPDIR (trap-cleaned on EXIT).
#   No network, no commit, no mutation of the real hook/labeler/doc.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, the sibling cm_track_branch_label.sh gate script + the real hook,
#   labeler and doc it defaults to. Parses clean under bash -n.
#
# ── Cross-references ──────────────────────────────────────────────────────────
#   §1.1 (paired mutation), §11.4.182, §11.4.67, §11.4.18, §11.4.108.
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — every sub-case produced the expected PASS/FAIL verdict.
#   1 — at least one sub-case produced the wrong verdict (bluff or false alarm).
#   2 — environment error (gate / hook / labeler missing).
#
# Classification: universal (§11.4.17).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="${SCRIPT_DIR}/cm_track_branch_label.sh"
REAL_HOOK="${SCRIPT_DIR}/../hooks/guard-track-branch-label.sh"
REAL_LABELER="${SCRIPT_DIR}/../multitrack/track_branch_label.sh"
REAL_DOC="${SCRIPT_DIR}/../../docs/scripts/guard-track-branch-label.md"

[ -f "$GATE" ]        || { echo "META: gate script missing: $GATE" >&2; exit 2; }
[ -f "$REAL_HOOK" ]   || { echo "META: real hook missing: $REAL_HOOK" >&2; exit 2; }
[ -f "$REAL_LABELER" ]|| { echo "META: real labeler missing: $REAL_LABELER" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cm_tbl_mut.XXXXXX")"
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
echo "§1.1 paired-mutation meta-test for CM-TRACK-BRANCH-LABEL"
echo "fixtures under: $TMP"
echo "======================================================================"

# --- 1. CLEAN: real hook + labeler + doc → PASS ---
expect_pass "clean fixture (real hook validates the alias field)" \
    bash "$GATE" --hook "$REAL_HOOK" --labeler "$REAL_LABELER" --doc "$REAL_DOC" --quiet

# --- 2a. MUTATION: a FORMAT-ONLY stub hook (skips the alias check) → FAIL ---
# This is the PRE-FIX behaviour: it accepts any format-valid label, INCLUDING a
# stale/wrong alias — so the gate's ALIAS-VALIDATION probe (WRONG alias must be
# blocked) MUST FAIL. This is the load-bearing §1.1 discriminator: strip the
# alias check and the gate stops passing.
FMT_ONLY_HOOK="$TMP/hook_format_only.sh"
cat > "$FMT_ONLY_HOOK" <<'SH'
#!/usr/bin/env bash
# FORMAT-ONLY stub (pre-§11.4.182-alias-fix behaviour): checks the label FORMAT
# but does NOT validate the alias field. Represents the bug the real fix closes.
set -uo pipefail
PAYLOAD="$(cat || true)"
tn="$(printf '%s' "$PAYLOAD" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
case "$tn" in Agent|Task|TaskCreate) ;; *) exit 0 ;; esac
desc="$(printf '%s' "$PAYLOAD" | sed -n 's/.*"description"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
[ -n "$desc" ] || desc="$(printf '%s' "$PAYLOAD" | sed -n 's/.*"subagent"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
LABEL_RE='^\(T[0-9]+/[^)]+ - [^)]+\) '
if [[ -n "$desc" && "$desc" =~ $LABEL_RE ]]; then exit 0; fi   # FORMAT-ONLY: no alias check
exit 2
SH
chmod +x "$FMT_ONLY_HOOK"
expect_fail "MUTATION: format-only hook (alias check stripped)" \
    bash "$GATE" --hook "$FMT_ONLY_HOOK" --labeler "$REAL_LABELER" --doc "$REAL_DOC" --quiet

# --- 2b. RESTORED: re-run CLEAN → PASS (proves the FAIL was the mutation) ---
expect_pass "RESTORED fixture (real hook re-audited)" \
    bash "$GATE" --hook "$REAL_HOOK" --labeler "$REAL_LABELER" --doc "$REAL_DOC" --quiet

# --- 3. DOC-MISSING: --doc points at a non-existent path → FAIL ---
expect_fail "doc-missing fixture (§11.4.18 convention doc absent)" \
    bash "$GATE" --hook "$REAL_HOOK" --labeler "$REAL_LABELER" --doc "$TMP/no_such_doc.md" --quiet

# --- 4. PARSE-BROKEN: a hook copy with an unbalanced quote → FAIL ---
BROKEN_HOOK="$TMP/hook_parse_broken.sh"
cp "$REAL_HOOK" "$BROKEN_HOOK"
printf '\necho "unbalanced quote\n' >> "$BROKEN_HOOK"
chmod +x "$BROKEN_HOOK"
expect_fail "parse-broken fixture (unbalanced quote in hook)" \
    bash "$GATE" --hook "$BROKEN_HOOK" --labeler "$REAL_LABELER" --doc "$REAL_DOC" --quiet

echo "======================================================================"
if [ "$rc" -eq 0 ]; then
    echo "✅ META PASS: CM-TRACK-BRANCH-LABEL is a genuine (non-bluff) gate"
else
    echo "❌ META FAIL: CM-TRACK-BRANCH-LABEL failed the §1.1 discriminator"
fi
echo "======================================================================"
exit "$rc"
