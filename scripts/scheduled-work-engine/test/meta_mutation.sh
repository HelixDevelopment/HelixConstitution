#!/usr/bin/env bash
# ============================================================================
# meta_mutation.sh — §1.1 paired meta-test mutation for scheduled-work-engine
# ============================================================================
# Purpose:
#   Prove the test suite is NOT a bluff (constitution §1.1): temporarily break
#   the mark-done handler at the source layer and assert the tests FAIL, then
#   restore and assert they PASS. A test suite that stays GREEN under a broken
#   handler is a §11.4 PASS-bluff.
#
# Usage:   bash test/meta_mutation.sh
# Outputs: PASS / FAIL to stdout; exit 0 on PASS, 1 on FAIL.
# Side-effects: mutates internal/store/store.go in place, ALWAYS restored on
#   every exit path (trap EXIT) — §11.4.14 cleanup.
# Dependencies: go
# Cross-references: constitution §1.1 (paired mutation), §11.4.120, §11.4.84.
# Last verified: 2026-07-02
# ============================================================================
set -eu

ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${ENGINE_DIR}/internal/store/store.go"
BACKUP="${TARGET}.meta_backup"

cleanup() {
	if [ -f "$BACKUP" ]; then
		mv -f "$BACKUP" "$TARGET"
		echo "[meta] restored ${TARGET}"
	fi
}
trap cleanup EXIT INT TERM

cd "$ENGINE_DIR"

echo "[meta] 1/3 baseline: tests must PASS on the honest source"
if ! go test ./internal/store/ ./test/ >/dev/null 2>&1; then
	echo "FAIL: baseline tests did not pass on honest source"
	exit 1
fi
echo "[meta]   baseline GREEN"

echo "[meta] 2/3 mutate: break MarkDone (StatusDone -> StatusScheduled)"
cp "$TARGET" "$BACKUP"
# The mutation: mark-done no longer sets the item done.
sed -i 's/return s.UpdateStatus(id, StatusDone, notes)/return s.UpdateStatus(id, StatusScheduled, notes) \/\/ MUTATION/' "$TARGET"
if ! grep -q '// MUTATION' "$TARGET"; then
	echo "FAIL: mutation did not apply (source pattern changed?)"
	exit 1
fi

echo "[meta]   asserting the suite now FAILs"
if go test ./internal/store/ ./test/ >/dev/null 2>&1; then
	echo "FAIL: tests still PASSED with a broken mark-done handler — BLUFF GATE"
	exit 1
fi
echo "[meta]   suite correctly FAILed on the broken handler"

echo "[meta] 3/3 restore + re-verify GREEN"
cleanup
trap - EXIT INT TERM
if ! go test ./internal/store/ ./test/ >/dev/null 2>&1; then
	echo "FAIL: tests did not pass after restore"
	exit 1
fi

echo "PASS: §1.1 paired mutation — the test suite catches a broken mark-done handler [evidence: RED-on-mutation + GREEN-on-restore]"
exit 0
