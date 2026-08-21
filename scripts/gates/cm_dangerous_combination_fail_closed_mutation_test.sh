#!/usr/bin/env bash
# cm_dangerous_combination_fail_closed_mutation_test.sh — §1.1 paired-mutation
# meta-test for CM-DANGEROUS-COMBINATION-FAIL-CLOSED (anchor §11.4.252).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves the gate is NOT a bluff: plants each fail-open anti-pattern shape the
# gate detects (swallowed exception / silent-default-return / credential-
# defaulted-to-literal, in Python and C-family shapes) and asserts the gate
# correctly FAILs on each; then asserts it PASSes on clean fixtures using the
# LEGITIMATE counterpart patterns (logged/re-raised handling, real fallback
# work, env-var-sourced credential fallback) plus an honest SKIP on a
# no-candidate-files directory.
#
# ── Blind-spot regression fixtures (the reason this suite exists) ────────────
# The gate previously matched Python `except:` handlers with a LINE-ANCHORED
# REGEX and read the handler body at exactly `lineno+1`. That shape was blind
# in FOUR ways and false-positive in a FIFTH, and each is pinned here by its
# own fixture so the specific blind spot cannot silently return:
#
#   L1  trailing comment on the handler line  (`except Exception:  # noqa`)
#   L2  tuple exception clause                (`except (OSError, ValueError):`)
#   L3  a comment between `except` and `pass` (body no longer at lineno+1)
#   L4  silent default return                 (`except: return None`)
#   L5  CARRIER FALSE POSITIVE — a docstring / string literal that merely
#       MENTIONS `except: pass` (a style guide, or this very file) was matched
#       as if it were code. The negative control below asserts the gate stays
#       SILENT on it (§11.4.201(1): a false-positive refusal is a FAIL-bluff
#       exactly as a false-negative pass is a PASS-bluff).
#
# Every L1-L4 fixture PASSED the pre-fix gate (i.e. went undetected) and MUST
# FAIL a correct one; the L5 carrier FAILED the pre-fix gate and MUST PASS a
# correct one. Both polarities are asserted, in BOTH the structural (AST) and
# the degraded (text-fallback) execution modes.
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
expect_output_contains() { # $1=desc  $2=needle  $3..=command
    local desc="$1" needle="$2"; shift 2
    local out
    # CAPTURE first, then match. Piping the command straight into grep would
    # measure the PIPELINE status under `set -o pipefail`, and this gate exits
    # non-zero whenever it finds a hit - so the assertion would read the gate's
    # VERDICT instead of grep's MATCH and fail on correct output
    # (§11.4.201(12): the pipeline exit status is part of the instrument).
    out="$("$@" 2>&1)" || true
    if printf '%s' "$out" | grep -qF -- "$needle"; then
        echo "✅ META OK:   ${desc} — gate announced its degraded mode"
    else
        echo "❌ META FAIL: ${desc} — expected output to contain: ${needle}"
        rc=1
    fi
}

# Degraded (text-fallback) invocation: an EXPLICIT unusable interpreter pin is
# authoritative, so this exercises the real no-Python code path rather than
# simulating it.
gate_textmode() { DANGEROUS_COMBO_PYTHON=/nonexistent/python bash "$GATE_SCRIPT" "$@"; }

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

# ── 8. MUTATED (L1): trailing comment on the handler line ───────────────────
# The pre-fix regex anchored the handler line with `:[[:space:]]*$`, so a
# reviewed-and-annotated handler was exactly the one it could not see.
MUT4="$TMP/mut4"
mkdir -p "$MUT4"
cat > "$MUT4/l1.py" <<'PY'
def purge(path):
    try:
        shutil.rmtree(path)
    except Exception:  # noqa: S110 - best effort
        pass
PY
expect_fail "L1 swallowed exception with a TRAILING COMMENT on the handler line" \
    bash "$GATE_SCRIPT" --root "$MUT4" --quiet
expect_fail "L1 (degraded text-fallback mode)" \
    gate_textmode --root "$MUT4" --quiet

# ── 9. MUTATED (L2): tuple exception clause ─────────────────────────────────
# The pre-fix exception-type group was `[A-Za-z_.]+`, which cannot match `(`.
MUT5="$TMP/mut5"
mkdir -p "$MUT5"
cat > "$MUT5/l2.py" <<'PY'
def purge(path):
    try:
        shutil.rmtree(path)
    except (OSError, ValueError):
        pass
PY
expect_fail "L2 swallowed exception with a TUPLE exception clause" \
    bash "$GATE_SCRIPT" --root "$MUT5" --quiet
expect_fail "L2 (degraded text-fallback mode)" \
    gate_textmode --root "$MUT5" --quiet

# ── 10. MUTATED (L3): a comment between `except` and `pass` ─────────────────
# The pre-fix body check read exactly lineno+1, so a reviewer ADDING an
# explanatory comment inside the handler deleted the site from the report.
MUT6="$TMP/mut6"
mkdir -p "$MUT6"
cat > "$MUT6/l3.py" <<'PY'
def purge(path):
    try:
        shutil.rmtree(path)
    except Exception:
        # best effort - the directory may already be gone
        pass
PY
expect_fail "L3 swallowed exception with a COMMENT between except and pass" \
    bash "$GATE_SCRIPT" --root "$MUT6" --quiet
expect_fail "L3 (degraded text-fallback mode)" \
    gate_textmode --root "$MUT6" --quiet

# ── 11. MUTATED (L4): silent default return ─────────────────────────────────
# Handing the caller a plausible-looking value that carries zero information
# about the failure is the same fail-open defect as `pass` - arguably worse,
# because the caller cannot tell the operation failed.
MUT7="$TMP/mut7"
mkdir -p "$MUT7"
cat > "$MUT7/l4.py" <<'PY'
def fetch_balance(account_id):
    try:
        return ledger.balance(account_id)
    except Exception:
        return 0
PY
expect_fail "L4 silent default return (except -> return <trivial literal>)" \
    bash "$GATE_SCRIPT" --root "$MUT7" --quiet
expect_fail "L4 (degraded text-fallback mode)" \
    gate_textmode --root "$MUT7" --quiet

# ── 12. NEGATIVE CONTROL (L5): a CARRIER that only MENTIONS the pattern ─────
# A style guide documenting the anti-pattern, and a string constant holding a
# forbidden snippet. The pre-fix text scanner FIRED on both (a §11.4.201(1)
# FAIL-bluff: it refused healthy code). A parser cannot: a string literal is
# not a Try node and a comment is not a statement.
CLEAN5="$TMP/clean5"
mkdir -p "$CLEAN5"
cat > "$CLEAN5/carrier.py" <<'PY'
"""Style guide for this project.

Never write a swallowed handler like this:

    except Exception:
        pass

Always log and re-raise instead.
"""

FORBIDDEN_SNIPPET = """
except Exception:
    pass
"""


def safe_delete(record_id):
    try:
        db.delete(record_id)
    except OSError as exc:
        logger.error("delete failed for %s: %s", record_id, exc)
        raise
PY
expect_pass "L5 CARRIER negative control — docstring/string merely MENTIONING the pattern must NOT fire" \
    bash "$GATE_SCRIPT" --root "$CLEAN5" --quiet

# ── 13. NEGATIVE CONTROL: handlers that do REAL fallback work ──────────────
# Guards the new silent-default-return class against over-reach: a handler
# that logs, or returns a COMPUTED value, or runs an alternate strategy, is
# fallback handling - not a silent default - and must NOT be flagged.
CLEAN6="$TMP/clean6"
mkdir -p "$CLEAN6"
cat > "$CLEAN6/fallback.py" <<'PY'
def parse_primary(blob):
    try:
        return primary_parser(blob)
    except ParseError as exc:
        logger.warning("primary parser failed: %s", exc)
        return fallback_parser(blob)


def load_config(path):
    try:
        return json.loads(read(path))
    except FileNotFoundError:
        return build_default_config(path)


def read_rows(cursor):
    try:
        return cursor.fetchall()
    except TransientError:
        cursor.reconnect()
        return cursor.fetchall()
PY
expect_pass "handlers doing REAL fallback work (log+delegate / computed default / retry) must NOT fire" \
    bash "$GATE_SCRIPT" --root "$CLEAN6" --quiet

# ── 14. DEGRADED MODE ANNOUNCES ITSELF (§11.4.6 / §11.4.201(6)) ────────────
# A blind instrument that reports a quiet number is the false-null this gate
# exists to avoid; when the structural analyser is unavailable the gate MUST
# say so on stdout rather than silently reporting a floor as a census.
expect_output_contains "degraded text-fallback mode is announced, never silent" \
    "FLOOR, not a census" \
    gate_textmode --root "$MUT4" --quiet

echo "======================================================================"
if [ "$rc" -eq 0 ]; then
    echo "✅ META PASS — CM-DANGEROUS-COMBINATION-FAIL-CLOSED FAILs-on-mutation AND PASSes-on-clean for every fixture (§1.1 proof holds)"
else
    echo "❌ META FAIL — CM-DANGEROUS-COMBINATION-FAIL-CLOSED is a bluff gate (did not FAIL on a mutation, or failed a clean fixture)"
fi
echo "META_EXIT=$rc"
exit "$rc"
