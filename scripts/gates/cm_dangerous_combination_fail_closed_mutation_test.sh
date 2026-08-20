#!/usr/bin/env bash
# cm_dangerous_combination_fail_closed_mutation_test.sh — §1.1 paired-mutation
# meta-test for CM-DANGEROUS-COMBINATION-FAIL-CLOSED (anchor §11.4.252).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves the gate is NOT a bluff: plants each of the two literal fail-open
# anti-pattern shapes the gate detects (swallowed exception / credential-
# defaulted-to-literal, in both a Python and a C-family shape) and asserts the
# gate correctly FAILs on each; then asserts it PASSes on clean fixtures using
# the LEGITIMATE counterpart patterns (logged/re-raised exception handling,
# env-var-sourced credential fallback) plus an honest SKIP on a no-candidate-
# files directory.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_dangerous_combination_fail_closed_mutation_test.sh
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Creates + removes a temp fixture dir under $TMPDIR (trap-cleaned on EXIT).
#   No network, no commit, no mutation of the real tree.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, the sibling gate script. Parses clean under bash -n.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §1.1 (paired mutation), §11.4.252, §11.4.3 (clean fixture exercises the
#   SKIP-vs-PASS boundary), §11.4.28 (gate driven via env, no hardcoded paths).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — gate FAILs-on-mutation AND PASSes-on-clean for every fixture (the §1.1
#       proof holds).
#   1 — a fixture did not FAIL on its planted mutation, or did not PASS clean.
#   2 — environment error (the gate script missing).
#
# Classification: universal (§11.4.17).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE_SCRIPT="${SCRIPT_DIR}/cm_dangerous_combination_fail_closed.sh"

[ -f "$GATE_SCRIPT" ] || { echo "META: gate script missing: $GATE_SCRIPT" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dcfc_mut.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

rc=0
expect_fail() { # $1=desc  $2..=command
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        echo "❌ META FAIL: ${desc} — gate PASSed on a planted violation (bluff gate!)"
        rc=1
    else
        echo "✅ META OK:   ${desc} — gate correctly FAILed on the mutation"
    fi
}
expect_pass() { # $1=desc  $2..=command
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        echo "✅ META OK:   ${desc} — gate correctly PASSed on clean fixture"
    else
        echo "❌ META FAIL: ${desc} — gate FAILed on a clean fixture (false alarm!)"
        rc=1
    fi
}

echo "======================================================================"
echo "§1.1 paired-mutation meta-test for CM-DANGEROUS-COMBINATION-FAIL-CLOSED"
echo "fixtures under: $TMP"
echo "======================================================================"

# ── 1. MUTATED: Python bare 'except: pass' (swallowed exception) ───────────
MUT1="$TMP/mut1"
mkdir -p "$MUT1"
cat > "$MUT1/handler.py" <<'PY'
def delete_record(record_id):
    try:
        db.delete(record_id)
    except:
        pass
    return True
PY
expect_fail "Python bare 'except: pass' swallowed exception" \
    bash "$GATE_SCRIPT" --root "$MUT1" --quiet

# ── 2. CLEAN: Python except with logging + re-raise ─────────────────────────
CLEAN1="$TMP/clean1"
mkdir -p "$CLEAN1"
cat > "$CLEAN1/handler.py" <<'PY'
def delete_record(record_id):
    try:
        db.delete(record_id)
    except DatabaseError as e:
        logger.error("delete failed for %s: %s", record_id, e)
        raise
    return True
PY
expect_pass "Python except with logging + re-raise (legitimate)" \
    bash "$GATE_SCRIPT" --root "$CLEAN1" --quiet

# ── 3. MUTATED: JS empty catch block (swallowed exception) ──────────────────
MUT2="$TMP/mut2"
mkdir -p "$MUT2"
cat > "$MUT2/handler.js" <<'JS'
function deleteRecord(recordId) {
    try {
        db.delete(recordId);
    } catch (err) {
    }
    return true;
}
JS
expect_fail "JS empty catch block (swallowed exception)" \
    bash "$GATE_SCRIPT" --root "$MUT2" --quiet

# ── 4. CLEAN: JS catch with real handling ────────────────────────────────────
CLEAN2="$TMP/clean2"
mkdir -p "$CLEAN2"
cat > "$CLEAN2/handler.js" <<'JS'
function deleteRecord(recordId) {
    try {
        db.delete(recordId);
    } catch (err) {
        logger.error("delete failed", err);
        throw err;
    }
    return true;
}
JS
expect_pass "JS catch with real handling (legitimate)" \
    bash "$GATE_SCRIPT" --root "$CLEAN2" --quiet

# ── 5. MUTATED: credential silently defaulted to a literal string ───────────
MUT3="$TMP/mut3"
mkdir -p "$MUT3"
cat > "$MUT3/config.py" <<'PY'
def get_api_key():
    api_key = loaded_value or "sk-hardcoded-fallback-secret"
    return api_key
PY
expect_fail "credential (api_key) silently defaulted to a literal string" \
    bash "$GATE_SCRIPT" --root "$MUT3" --quiet

# ── 6. CLEAN: credential fallback to env var (legitimate secondary source) ──
CLEAN3="$TMP/clean3"
mkdir -p "$CLEAN3"
cat > "$CLEAN3/config.py" <<'PY'
def get_api_key():
    api_key = loaded_value or os.environ.get("API_KEY")
    return api_key
PY
expect_pass "credential fallback to env var (legitimate secondary source)" \
    bash "$GATE_SCRIPT" --root "$CLEAN3" --quiet

# ── 7. NEGATIVE CONTROL: no candidate source files at all -> honest SKIP ────
CLEAN4="$TMP/clean4"
mkdir -p "$CLEAN4"
echo "just documentation text, no source files" > "$CLEAN4/README.md"
expect_pass "no candidate source files present — honest SKIP (exit 0), never a fake FAIL" \
    bash "$GATE_SCRIPT" --root "$CLEAN4" --quiet

echo "======================================================================"
if [ "$rc" -eq 0 ]; then
    echo "✅ META PASS — CM-DANGEROUS-COMBINATION-FAIL-CLOSED FAILs-on-mutation AND PASSes-on-clean for every fixture (§1.1 proof holds)"
else
    echo "❌ META FAIL — CM-DANGEROUS-COMBINATION-FAIL-CLOSED is a bluff gate (did not FAIL on a mutation, or failed a clean fixture)"
fi
echo "META_EXIT=$rc"
exit "$rc"
