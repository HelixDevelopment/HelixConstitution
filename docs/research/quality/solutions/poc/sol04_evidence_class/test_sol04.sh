#!/usr/bin/env bash
# SOL-04 POC test — evidence-class-at-closure enforcement.
# Written FIRST (§11.4.224). RED before evidence_class_check.sh exists.
#
# Contract (evidence_class_check.sh <defect-layer> <evidence-file>):
#   defect layers (closed): user-visible | runtime | artifact | source
#   evidence classes (closed): runtime | artifact | source, verified by REQUIRED
#   MACHINE FIELDS in the evidence file, not by a bare label:
#     runtime  -> TARGET_FINGERPRINT: + RUNTIME_OBSERVABLE:
#     artifact -> ARTIFACT_PATH: + ARTIFACT_SHA256:
#     source   -> SOURCE_REF:
#   matching floor: user-visible/runtime defects need runtime evidence;
#                   artifact defects need >= artifact; source defects accept source.
#   anti-echo rule: RUNTIME_OBSERVABLE beginning with 'grep:' is a source transcript
#   wearing a runtime label -> REFUSED (the PC-8 five-greps-for-a-pixel-defect case).
#   exit 0 = class satisfied | 1 = refused (named reason) | 2 = blind/unreadable
#
# Cases:
#   A golden-good      : user-visible defect + true runtime evidence -> 0
#   B golden-bad-1     : user-visible defect + grep transcript labelled runtime -> 1 (WRONG-LAYER)
#   C golden-bad-2     : runtime label but required fields missing -> 1 (SHAPE-INCOMPLETE)
#   D negative-control : source-layer defect + source evidence -> 0 (no §11.4.201(1) false refusal)
#   E blind            : unreadable evidence path -> 2, never 0
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
[ -f "$HERE/evidence_class_check.sh" ] || { echo "FAIL: missing artifact evidence_class_check.sh"; echo "RESULT: RED"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

cat > "$T/runtime_good.ev" <<'EOF'
EVIDENCE-CLASS: runtime
TARGET_FINGERPRINT: build-2026-07-22-abcdef read from /system/build.prop on device
RUNTIME_OBSERVABLE: dumpsys display shows mirror_layers=0 across 30s window
CAPTURED-AT: 2026-07-22T18:00:00Z
EOF

cat > "$T/echo_bad.ev" <<'EOF'
EVIDENCE-CLASS: runtime
TARGET_FINGERPRINT: build-2026-07-22-abcdef
RUNTIME_OBSERVABLE: grep: OverlayService.kt:214 matched 'dismissOverlay' (5 hits)
EOF

cat > "$T/incomplete.ev" <<'EOF'
EVIDENCE-CLASS: runtime
RUNTIME_OBSERVABLE: dumpsys ok
EOF

cat > "$T/source_ok.ev" <<'EOF'
EVIDENCE-CLASS: source
SOURCE_REF: scripts/lint_rule.sh:42 pattern updated, sh -n clean, unit test transcript attached
EOF

run() { bash "$HERE/evidence_class_check.sh" "$1" "$2"; }

run user-visible "$T/runtime_good.ev" >"$T/a.out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "A user-visible defect + real runtime evidence accepted" || bad "A expected 0 got $rc: $(cat "$T/a.out")"

run user-visible "$T/echo_bad.ev" >"$T/b.out" 2>&1; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'WRONG-LAYER' "$T/b.out"; then
  ok "B grep transcript wearing a runtime label refused (PC-8 class closed)"
else
  bad "B expected 1 WRONG-LAYER got $rc: $(cat "$T/b.out")"
fi

run user-visible "$T/incomplete.ev" >"$T/c.out" 2>&1; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'SHAPE-INCOMPLETE' "$T/c.out"; then
  ok "C runtime label without required machine fields refused"
else
  bad "C expected 1 SHAPE-INCOMPLETE got $rc: $(cat "$T/c.out")"
fi

run source "$T/source_ok.ev" >"$T/d.out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "D source-layer defect + source evidence accepted (no false refusal)" || bad "D expected 0 got $rc: $(cat "$T/d.out")"

run user-visible "$T/does_not_exist.ev" >"$T/e.out" 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "E unreadable evidence -> blind (2), never accepted" || bad "E expected 2 got $rc"

echo "----------------------------------------"
echo "RESULT: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
