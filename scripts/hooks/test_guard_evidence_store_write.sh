#!/usr/bin/env bash
# ============================================================================
# test_guard_evidence_store_write.sh — hermetic suite for the PreToolUse guard
# `guard-evidence-store-write.sh` (T113, spec 002; FR-031/FR-008 layer 1).
#
# §11.4.69 FEATURE: permission_grant   (host-side tool-call admission)
#
# WHAT THE GUARD UNDER TEST IS FOR — and, just as importantly, what it is NOT:
#   It is BEST-EFFORT PREVENTION layered UNDER the reader-side detection in
#   scripts/lib/critical_blocker_gate.sh (T118). Research D-3 measured that a
#   satisfy row forged by ONE plain `>>` redirection bypasses the append
#   function entirely, so PREVENTION alone can never be the guarantee. The
#   reader is the guarantee; this hook only raises the cost of the direct path.
#
# THE BYPASS IS A TEST CASE, NOT A FOOTNOTE (§11.4.6):
#   A Write/Edit matcher sees Write/Edit calls. One level of indirection — a
#   Bash call that appends, a helper script, a symlink — does not present as a
#   Write to the store path and is NOT blocked. That is asserted BELOW as a
#   measured fact. A bypass that is NAMED is a stated limit; a bypass that is
#   implied away is a bluff.
#
# ANTI-BLUFF SHAPE (§11.4.107(10) / §11.4.201(1)):
#   GOLDEN-TRUE   producer writing the store            -> BLOCK (exit 2)
#   GOLDEN-FALSE  non-producer writing the store        -> ALLOW
#   GOLDEN-FALSE  producer writing an unrelated path    -> ALLOW
#   FAIL-CLOSED   registry unreadable                   -> BLOCK
#   MEASURED      one-level-of-indirection write        -> ALLOW (the stated gap)
#   Both verdicts are reachable, so neither is hardcoded.
#
# Usage: bash constitution/scripts/hooks/test_guard_evidence_store_write.sh
# Exit 0 = every case behaved as specified; 1 = at least one did not.
# ============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/guard-evidence-store-write.sh"

PASS=0
FAIL=0
SCRATCH=""
VERDICTS=""

cleanup() { [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] && rm -rf "$SCRATCH"; }
trap cleanup EXIT

ok()  { PASS=$((PASS+1)); printf '  [PASS] %s\n' "$1"; VERDICTS="${VERDICTS}PASS	$1"$'\n'; }
bad() { FAIL=$((FAIL+1)); printf '  [FAIL] %s\n' "$1"; [ -n "${2:-}" ] && printf '         resolved: %s\n' "$2"; VERDICTS="${VERDICTS}FAIL	$1	${2:-}"$'\n'; return 0; }

printf '=== test_guard_evidence_store_write (hook=%s) ===\n' "$HOOK"

# --- the guard must EXIST before anything about its behaviour is claimed -----
# This is the RED gate for T113: until T122 lands, every behavioural assertion
# below is unreachable and the suite reports that, rather than passing quietly.
if [ ! -r "$HOOK" ]; then
    bad "guard_present — the PreToolUse guard exists at the declared path" \
        "$HOOK does not exist (RED — turned GREEN by T122)"
    printf -- '--- test_guard_evidence_store_write: %d PASS / %d FAIL ---\n' "$PASS" "$FAIL"
    exit 1
fi
ok "guard_present — the PreToolUse guard exists at $HOOK"

SCRATCH="$(mktemp -d)" || exit 2
REG="$SCRATCH/critical_blockers.jsonl"
OTHER="$SCRATCH/unrelated.txt"
: > "$OTHER"

# A registry in which SESS-PRODUCER is recorded as the producer for B-X.
cat > "$REG" <<EOF
{"blocker_id":"B-X","event":"open","scope":"every-release","evidence_class_floor":"runtime","declared_verbatim":"guard fixture","ts":"2026-08-21T00:00:00Z"}
{"blocker_id":"B-X","event":"satisfy","evidence_path":"$SCRATCH/ev.log","fingerprint":"*","evidence_class":"runtime","author_session_id":"SESS-VERIFIER","producer_session_id":"SESS-PRODUCER","independence_tier":"instance","ts":"2026-08-21T00:00:00Z"}
EOF

# --- payload builder ---------------------------------------------------------
payload() {  # <tool_name> <file_path> <session_id>
    printf '{"session_id":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"file_path":"%s","content":"x"}}' \
        "$3" "$1" "$2"
}
run_hook() {  # <payload> ; echoes rc
    printf '%s' "$1" | GESW_REGISTRY="$REG" bash "$HOOK" >/dev/null 2>&1
    printf '%s' "$?"
}

# --- CONTROL NEEDLE: the hook is reachable and CAN block ---------------------
# Reported FIRST. Every "not blocked" verdict below is meaningless if the hook
# cannot block at all — a hook that exits 0 unconditionally (or crashes into 0)
# would make all three negative controls pass while guarding nothing.
NEEDLE_RC="$(run_hook "$(payload Write "$REG" SESS-PRODUCER)")"
if [ "$NEEDLE_RC" = "2" ]; then
    ok "needle_hook_can_block — the hook is reachable and exits 2 on a known-blocking case"
else
    bad "needle_hook_can_block — the hook is reachable and exits 2 on a known-blocking case" \
        "rc=$NEEDLE_RC — INSTRUMENT BLIND: every ALLOW verdict below would prove nothing"
    printf -- '--- test_guard_evidence_store_write: %d PASS / %d FAIL ---\n' "$PASS" "$FAIL"
    exit 1
fi

# --- (1) GOLDEN-TRUE: the recorded PRODUCER writing the store is BLOCKED -----
for T in Write Edit; do
    RC="$(run_hook "$(payload "$T" "$REG" SESS-PRODUCER)")"
    if [ "$RC" = "2" ]; then ok "block_producer_$T — a $T by the recorded producer to the evidence store is BLOCKED (exit 2)"
    else bad "block_producer_$T — a $T by the recorded producer to the evidence store is BLOCKED (exit 2)" "rc=$RC"; fi
done

# --- (2) GOLDEN-FALSE: a NON-producer write is NOT blocked ------------------
RC="$(run_hook "$(payload Write "$REG" SESS-VERIFIER)")"
if [ "$RC" = "0" ]; then ok "allow_non_producer — a write by a session that is NOT the recorded producer is ALLOWED"
else bad "allow_non_producer — a write by a session that is NOT the recorded producer is ALLOWED" "rc=$RC — false-positive block (§11.4.201(1))"; fi

# --- (3) GOLDEN-FALSE: an unrelated path is NOT blocked ---------------------
RC="$(run_hook "$(payload Write "$OTHER" SESS-PRODUCER)")"
if [ "$RC" = "0" ]; then ok "allow_unrelated_path — a write by the producer to a path outside the store class is ALLOWED"
else bad "allow_unrelated_path — a write by the producer to a path outside the store class is ALLOWED" "rc=$RC — false-positive block"; fi

# --- (4) FAIL-CLOSED: an unreadable registry BLOCKS -------------------------
UNREAD="$SCRATCH/unreadable.jsonl"
cp "$REG" "$UNREAD"
chmod 000 "$UNREAD"
if cat "$UNREAD" >/dev/null 2>&1; then
    printf '  [SKIP] failclosed_unreadable_registry — DAC bypassed on this host (uid=%s); unreadability could not be established (§11.4.3 skip-with-reason, never a pass)\n' "$(id -u)"
else
    RC="$(printf '%s' "$(payload Write "$UNREAD" SESS-PRODUCER)" | GESW_REGISTRY="$UNREAD" bash "$HOOK" >/dev/null 2>&1; printf '%s' "$?")"
    if [ "$RC" = "2" ]; then ok "failclosed_unreadable_registry — an unreadable registry BLOCKS (cannot establish who the producer is)"
    else bad "failclosed_unreadable_registry — an unreadable registry BLOCKS" "rc=$RC — fail-OPEN on an authorization surface (§11.4.252)"; fi
fi
chmod 644 "$UNREAD" 2>/dev/null || true

# --- (5) MEASURED LIMIT: one level of indirection is NOT blocked ------------
# Asserted as a FACT about coverage, not as a defect of this suite. A Bash tool
# call that appends to the same path does not present as a Write/Edit to it, so
# the matcher never sees it. This is why T118's reader-side check — which runs
# on every READ, regardless of how the row was written — is the guarantee and
# this hook is not.
INDIRECT='{"session_id":"SESS-PRODUCER","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"printf x >> '"$REG"'"}}'
RC="$(printf '%s' "$INDIRECT" | GESW_REGISTRY="$REG" bash "$HOOK" >/dev/null 2>&1; printf '%s' "$?")"
if [ "$RC" = "0" ]; then
    ok "measured_indirection_bypass_still_succeeds — a Bash append to the same path is NOT blocked (STATED LIMIT: prevention is best-effort; the reader-side check in critical_blocker_gate.sh is the guarantee)"
else
    bad "measured_indirection_bypass_still_succeeds — the documented bypass is expected to remain OPEN so the guard's real coverage is a measured fact" \
        "rc=$RC — the hook blocked it, so the documented limit no longer matches behaviour; update the documentation and this assertion together, never one alone"
fi

printf -- '--- test_guard_evidence_store_write: %d PASS / %d FAIL ---\n' "$PASS" "$FAIL"
# ab_summary-compatible count block (T124) — see the note in
# scripts/testing/us1_scenarios/lib_scratch_store.sh: the §11.4.135 standing
# suite classifies a guard from these counters, and without them a green run is
# recorded as "no parseable verdict line". Additive; changes no verdict.
printf 'PASS:    %d\n' "$PASS"
printf 'FAIL:    %d\n' "$FAIL"
printf 'SKIP:    0\n'
# §11.4.69 CAPTURED EVIDENCE — a durable artifact recording the hook's resolved
# identity and every case's verdict, written outside the scratch dir so the
# citation still resolves after cleanup. Produced, never merely cited.
EVDIR="${GESW_EVIDENCE_DIR:-$(cd "$HERE/../../.." && pwd)/qa-results/us1_scenarios}"
EVFILE="$EVDIR/guard_evidence_store_write_$(date -u +%Y%m%dT%H%M%SZ)_$$.log"
if mkdir -p "$EVDIR" 2>/dev/null && {
      printf 'suite=test_guard_evidence_store_write\nutc=%s\nhook=%s\nhook_sha256=%s\npass=%d fail=%d\n--- verdicts ---\n%s' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$HOOK" \
        "$(sha256sum "$HOOK" 2>/dev/null | cut -d' ' -f1)" "$PASS" "$FAIL" "$VERDICTS" > "$EVFILE" 2>/dev/null
   }; then
    printf 'PASS: guard-evidence-store-write verdict transcript captured [evidence: %s]\n' "$EVFILE"
else
    printf 'SKIP: verdict transcript NOT written (could not create %s)\n' "$EVDIR"
fi
[ "$FAIL" -eq 0 ]
