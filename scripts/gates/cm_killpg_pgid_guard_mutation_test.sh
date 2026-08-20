#!/usr/bin/env bash
# cm_killpg_pgid_guard_mutation_test.sh — §1.1 paired-mutation meta-test for
# CM-KILLPG-PGID-GUARD (anchor §11.4.263).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves CM-KILLPG-PGID-GUARD is NOT a bluff gate: it must FAIL on the exact
# BOB-126 forensic shape (an unguarded process-group signal call — the literal
# defect that SIGKILLed the operator's desktop session seven times over 48h),
# and it must PASS on the anchor's own prescribed guard idiom applied across
# every language class §11.4.263(B) names, PLUS the legitimate ordinary
# single-process `kill -9 $pid` shell idiom (which MUST NEVER be flagged —
# clause 3 of the gate's header design rationale).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_killpg_pgid_guard_mutation_test.sh
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Creates + removes a temp fixture dir under $TMPDIR (trap-cleaned on EXIT).
#   No network, no commit, no real killpg/kill syscall ever executed — every
#   fixture is inert source TEXT the gate's scanner reads, never runs.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, the sibling gate script. Parses clean under bash -n.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §1.1 (paired mutation), §11.4.263 (the anchor enforced), §11.4.201(1)
#   (false-positive refusal is a FAIL-bluff exactly as a false-negative pass —
#   both directions are tested here), §11.4.28 (gate driven via --root, no
#   hardcoded project path).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — gate FAILs-on-mutation AND PASSes-on-clean for every fixture pair
#       (the §1.1 proof holds).
#   1 — a fixture did not produce its expected verdict (bluff gate, or a
#       false-positive refusal).
#   2 — environment error (gate script missing).
#
# Classification: universal (§11.4.17).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="${SCRIPT_DIR}/cm_killpg_pgid_guard.sh"

[ -f "$GATE" ] || { echo "META: gate script missing: $GATE" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/killpg_mut.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

rc=0
expect_fail() { # $1=desc  $2=dir
    local desc="$1" dir="$2"
    if bash "$GATE" --root "$dir" >/dev/null 2>&1; then
        echo "❌ META FAIL: ${desc} — gate PASSed on a planted violation (bluff gate!)"
        rc=1
    else
        echo "✅ META OK:   ${desc} — gate correctly FAILed on the mutation"
    fi
}
expect_pass() { # $1=desc  $2=dir
    local desc="$1" dir="$2"
    if bash "$GATE" --root "$dir" >/dev/null 2>&1; then
        echo "✅ META OK:   ${desc} — gate correctly PASSed on clean fixture"
    else
        echo "❌ META FAIL: ${desc} — gate FAILed on a clean fixture (false-positive refusal, §11.4.201(1))"
        rc=1
    fi
}

echo "======================================================================"
echo "§1.1 paired-mutation meta-test for CM-KILLPG-PGID-GUARD (§11.4.263)"
echo "fixtures under: $TMP"
echo "======================================================================"

# ===================================================================
# 1. The literal BOB-126 shape — bare os.killpg(os.getpgid(proc.pid), ...)
# ===================================================================
MUT1="$TMP/bob126"
mkdir -p "$MUT1"
cat > "$MUT1/reaper.py" <<'PY'
import os, signal

def kill_process_tree(proc):
    # BOB-126: proc.pid was an unset AsyncMock().pid, defaulting via
    # MagicMock.__int__() to 1 -> os.getpgid(1) == 1 -> os.killpg(1, SIGKILL)
    # == kill(-1, SIGKILL) == SIGKILL every process the caller's UID owns.
    os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
PY
expect_fail "BOB-126 literal shape (unguarded os.killpg)" "$MUT1"

CLEAN1="$TMP/bob126_fixed"
mkdir -p "$CLEAN1"
cat > "$CLEAN1/reaper.py" <<'PY'
import os, signal

def kill_process_tree(proc):
    pid = getattr(proc, "pid", None)
    if not isinstance(pid, int) or pid <= 1:
        raise ValueError(f"refusing to signal unsafe pid: {pid!r}")
    pgid = os.getpgid(pid)
    if not isinstance(pgid, int) or pgid <= 1:
        raise ValueError(f"refusing to signal unsafe pgid: {pgid!r}")
    os.killpg(pgid, signal.SIGKILL)
PY
expect_pass "BOB-126 fixed shape (guarded pid+pgid>1 before killpg)" "$CLEAN1"

# ===================================================================
# 2. Go — syscall.Kill(-pgid, sig) unguarded vs guarded
# ===================================================================
MUT2="$TMP/go_bad"
mkdir -p "$MUT2"
cat > "$MUT2/reaper.go" <<'GO'
package main

import "syscall"

func killTree(pgid int) {
	syscall.Kill(-pgid, syscall.SIGKILL)
}
GO
expect_fail "Go unguarded syscall.Kill(-pgid,...)" "$MUT2"

CLEAN2="$TMP/go_good"
mkdir -p "$CLEAN2"
cat > "$CLEAN2/reaper.go" <<'GO'
package main

import (
	"fmt"
	"syscall"
)

func killTree(pgid int) error {
	if pgid <= 1 {
		return fmt.Errorf("refusing to signal unsafe pgid: %d", pgid)
	}
	return syscall.Kill(-pgid, syscall.SIGKILL)
}
GO
expect_pass "Go guarded (pgid>1 checked before syscall.Kill)" "$CLEAN2"

# ===================================================================
# 3. Shell — pkill -g <pgid> unguarded vs guarded
# ===================================================================
MUT3="$TMP/sh_bad"
mkdir -p "$MUT3"
cat > "$MUT3/reaper.sh" <<'SH'
#!/usr/bin/env bash
reap_tree() {
    local pgid="$1"
    pkill -g "$pgid"
}
SH
expect_fail "shell unguarded pkill -g \$pgid" "$MUT3"

CLEAN3="$TMP/sh_good"
mkdir -p "$CLEAN3"
cat > "$CLEAN3/reaper.sh" <<'SH'
#!/usr/bin/env bash
reap_tree() {
    local pgid="$1"
    case "$pgid" in
        ''|*[!0-9]*) echo "refusing to signal non-integer pgid: $pgid" >&2; return 1 ;;
    esac
    if [ "$pgid" -le 1 ]; then
        echo "refusing to signal unsafe pgid <=1: $pgid" >&2
        return 1
    fi
    pkill -g "$pgid"
}
SH
expect_pass "shell guarded pgid (pgid>1 checked before pkill -g)" "$CLEAN3"

# ===================================================================
# 4. Negative control — ordinary single-process `kill -9 $pid` MUST NEVER
#    be flagged: kill(2)'s process-GROUP form requires a NEGATIVE pgid, and
#    this is the single-process form. A gate that flags this is itself a
#    §11.4.201(1) false-positive refusal (FAIL-bluff).
# ===================================================================
NEG1="$TMP/ordinary_single_kill"
mkdir -p "$NEG1"
cat > "$NEG1/tidy.sh" <<'SH'
#!/usr/bin/env bash
stop_one() {
    local pid="$1"
    kill -9 "$pid"
}
SH
expect_pass "negative control: ordinary single-process 'kill -9 \$pid' never flagged" "$NEG1"

echo "======================================================================"
if [ "$rc" -eq 0 ]; then
    echo "✅ META PASS — CM-KILLPG-PGID-GUARD FAILs-on-mutation AND PASSes-on-clean for every fixture (§1.1 proof holds)"
else
    echo "❌ META FAIL — CM-KILLPG-PGID-GUARD is a bluff gate (see findings above)"
fi
exit "$rc"
