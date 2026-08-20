#!/usr/bin/env bash
# cm_test_mock_pid_explicit_int_mutation_test.sh — §1.1 paired-mutation
# meta-test for CM-TEST-MOCK-PID-EXPLICIT-INT (anchor §11.4.263).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves CM-TEST-MOCK-PID-EXPLICIT-INT is NOT a bluff gate: it must FAIL on
# the exact BOB-126 test-bug shape (an AsyncMock/MagicMock/Mock whose `.pid`
# is read without ever being explicitly set to an int — the precise defect
# that let MagicMock's default `__int__() == 1` fallback flow into
# `os.getpgid(1) == 1` -> `os.killpg(1, SIGKILL)` == `kill(-1, SIGKILL)`), and
# it must PASS on the anchor's own prescribed fix idiom (`mock.pid = <int>`
# set explicitly, either via constructor kwarg or a later attribute
# assignment), for both AsyncMock and MagicMock. It must ALSO NOT
# false-positive-refuse a mock whose `.pid` is never read at all (a §11.4.201
# false-positive-refusal negative control).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_test_mock_pid_explicit_int_mutation_test.sh
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Creates + removes a temp fixture dir under $TMPDIR (trap-cleaned on EXIT).
#   No network, no commit — every fixture is inert source TEXT the gate's
#   scanner reads, no mock or process is ever really instantiated/executed.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, the sibling gate script. Parses clean under bash -n.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §1.1 (paired mutation), §11.4.263(C) (the anchor clause enforced),
#   §11.4.201(1) (false-positive refusal is a FAIL-bluff exactly as a
#   false-negative pass — both directions tested here), §11.4.28 (gate
#   driven via --root, no hardcoded project path).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — gate FAILs-on-mutation AND PASSes-on-clean for every fixture pair.
#   1 — a fixture did not produce its expected verdict (bluff gate, or a
#       false-positive refusal).
#   2 — environment error (gate script missing).
#
# Classification: universal (§11.4.17).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="${SCRIPT_DIR}/cm_test_mock_pid_explicit_int.sh"

[ -f "$GATE" ] || { echo "META: gate script missing: $GATE" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/mockpid_mut.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

rc=0
expect_fail() {
    local desc="$1" dir="$2"
    if bash "$GATE" --root "$dir" >/dev/null 2>&1; then
        echo "❌ META FAIL: ${desc} — gate PASSed on a planted violation (bluff gate!)"
        rc=1
    else
        echo "✅ META OK:   ${desc} — gate correctly FAILed on the mutation"
    fi
}
expect_pass() {
    local desc="$1" dir="$2"
    if bash "$GATE" --root "$dir" >/dev/null 2>&1; then
        echo "✅ META OK:   ${desc} — gate correctly PASSed on clean fixture"
    else
        echo "❌ META FAIL: ${desc} — gate FAILed on a clean fixture (false-positive refusal, §11.4.201(1))"
        rc=1
    fi
}

echo "======================================================================"
echo "§1.1 paired-mutation meta-test for CM-TEST-MOCK-PID-EXPLICIT-INT (§11.4.263)"
echo "fixtures under: $TMP"
echo "======================================================================"

# ===================================================================
# 1. The literal BOB-126 test-bug shape — AsyncMock() with an unset .pid
#    that is READ (feeding a getpgid/killpg-style call).
# ===================================================================
MUT1="$TMP/bob126"
mkdir -p "$MUT1"
cat > "$MUT1/test_reaper.py" <<'PY'
from unittest.mock import AsyncMock
import os, signal

async def test_kill_process_tree_regression():
    proc = AsyncMock()
    # BOB-126 forensic shape: proc.pid was never explicitly set. It falls
    # back through MagicMock's auto-child-mock + __int__() default == 1.
    pgid = os.getpgid(proc.pid)
    os.killpg(pgid, signal.SIGKILL)
PY
expect_fail "BOB-126 literal test-bug shape (AsyncMock unset .pid read)" "$MUT1"

CLEAN1="$TMP/bob126_fixed"
mkdir -p "$CLEAN1"
cat > "$CLEAN1/test_reaper.py" <<'PY'
from unittest.mock import AsyncMock
import os, signal

async def test_kill_process_tree_regression():
    proc = AsyncMock()
    proc.pid = 4242
    pgid = os.getpgid(proc.pid)
    os.killpg(pgid, signal.SIGKILL)
PY
expect_pass "BOB-126 fixed (AsyncMock, explicit later mock.pid = <int>)" "$CLEAN1"

# ===================================================================
# 2. MagicMock variant with an unset .pid read vs. constructor-kwarg fix.
# ===================================================================
MUT2="$TMP/magicmock_bad"
mkdir -p "$MUT2"
cat > "$MUT2/test_process.py" <<'PY'
from unittest.mock import MagicMock
import os

def test_process_group_lookup():
    process = MagicMock()
    group = os.getpgid(process.pid)
    assert group is not None
PY
expect_fail "MagicMock unset .pid read" "$MUT2"

CLEAN2="$TMP/magicmock_good"
mkdir -p "$CLEAN2"
cat > "$CLEAN2/test_process.py" <<'PY'
from unittest.mock import MagicMock
import os

def test_process_group_lookup():
    process = MagicMock(pid=9999)
    group = os.getpgid(process.pid)
    assert group is not None
PY
expect_pass "MagicMock fixed (explicit constructor kwarg pid=<int>)" "$CLEAN2"

# ===================================================================
# 3. Negative control — a Mock() whose .pid is NEVER read anywhere in the
#    file MUST NOT be flagged, even though it never gets an explicit int
#    .pid. Flagging it would be a §11.4.201(1) false-positive refusal: the
#    defect only manifests when .pid is actually accessed/coerced.
# ===================================================================
NEG1="$TMP/pid_never_read"
mkdir -p "$NEG1"
cat > "$NEG1/test_unrelated.py" <<'PY'
from unittest.mock import Mock

def test_unrelated_mock_never_touches_pid():
    db_conn = Mock()
    db_conn.execute.return_value = []
    result = db_conn.execute("SELECT 1")
    assert result == []
PY
expect_pass "negative control: Mock() whose .pid is never read is never flagged" "$NEG1"

# ===================================================================
# 4. Plain Mock() (not Async/Magic) with the same unguarded-read shape,
#    to prove the gate covers all three unittest.mock classes the anchor
#    names.
# ===================================================================
MUT3="$TMP/plain_mock_bad"
mkdir -p "$MUT3"
cat > "$MUT3/test_plain.py" <<'PY'
from unittest.mock import Mock
import signal, os

def test_plain_mock_pid_unset():
    child = Mock()
    os.killpg(child.pid, signal.SIGTERM)
PY
expect_fail "plain Mock() unset .pid read" "$MUT3"

echo "======================================================================"
if [ "$rc" -eq 0 ]; then
    echo "✅ META PASS — CM-TEST-MOCK-PID-EXPLICIT-INT FAILs-on-mutation AND PASSes-on-clean for every fixture (§1.1 proof holds)"
else
    echo "❌ META FAIL — CM-TEST-MOCK-PID-EXPLICIT-INT is a bluff gate (see findings above)"
fi
exit "$rc"
