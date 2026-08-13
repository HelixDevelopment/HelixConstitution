#!/usr/bin/env bash
# SOL-10 POC test — misunderstanding-layer mechanics.
# Written FIRST (§11.4.224). RED before mu_checks.sh exists.
#
# Contract (mu_checks.sh <mode> ...):
#  stateblock <doc.md>
#    Verifies every  <!-- machine:begin cmd="..." --> ... <!-- machine:end -->
#    block by RE-RUNNING cmd and BYTE-COMPARING (MU-1: text encoding a measurement
#    needs a re-measurement trigger; §11.4.205(4)).
#    Refuses a cmd that references the doc's own filename (the §11.4.205(5)
#    self-fingerprint fixpoint = permanent false-FAIL).
#    exit 0 fresh | 1 DRIFT/SELF-REF named | 2 blind
#  fence <registry.tsv> <docs-dir>
#    registry: verdict_id <TAB> comma-separated allowed files (the fence).
#    Any citation of the verdict id OUTSIDE its fence -> FENCE-VIOLATION (MU-2:
#    a TRUE verdict cited 6 weeks against an adjacent viable goal; §11.4.112(5)).
#  seam <gate-registry.tsv> <plan.md>
#    registry: gate_id <TAB> declared_seam. plan lines: REQUIRE <gate> AT <seam>.
#    Mismatch -> SEAM-MISMATCH (MU-3: a gate whose precondition the gated work
#    produces was imposed on authorship; its source seated it at activation).
#
# Cases (per mode): golden-good / golden-bad / negative-control.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
[ -f "$HERE/mu_checks.sh" ] || { echo "FAIL: missing artifact mu_checks.sh"; echo "RESULT: RED"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# ---- stateblock -----------------------------------------------------------
cat > "$T/fresh.md" <<'EOF'
# Live state
<!-- machine:begin cmd="printf 'edit-points=45\n'" -->
edit-points=45
<!-- machine:end -->
EOF
bash "$HERE/mu_checks.sh" stateblock "$T/fresh.md" >"$T/s1.out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "S1 fresh machine block verifies (re-render byte-matches)" || bad "S1 expected 0 got $rc: $(cat "$T/s1.out")"

cat > "$T/stale.md" <<'EOF'
# Live state
<!-- machine:begin cmd="printf 'edit-points=45\n'" -->
edit-points=22
<!-- machine:end -->
EOF
bash "$HERE/mu_checks.sh" stateblock "$T/stale.md" >"$T/s2.out" 2>&1; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'DRIFT' "$T/s2.out"; then
  ok "S2 stale block (the 22-vs-45 MU-1 case verbatim) -> DRIFT"
else
  bad "S2 expected 1 DRIFT got $rc: $(cat "$T/s2.out")"
fi

cat > "$T/selfref.md" <<'EOF'
<!-- machine:begin cmd="sha256sum selfref.md" -->
whatever
<!-- machine:end -->
EOF
bash "$HERE/mu_checks.sh" stateblock "$T/selfref.md" >"$T/s3.out" 2>&1; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'SELF-REF' "$T/s3.out"; then
  ok "S3 block hashing its own document refused (fixpoint false-FAIL, §11.4.205(5))"
else
  bad "S3 expected 1 SELF-REF got $rc: $(cat "$T/s3.out")"
fi

# ---- fence ----------------------------------------------------------------
mkdir -p "$T/docs"
printf 'VD-77\tdocs/verdict_vd77.md\n' > "$T/fence.tsv"
cat > "$T/docs/verdict_vd77.md" <<'EOF'
VD-77: relocating another app's protected surface WITHOUT its cooperation is impossible.
Scope: exactly that. Adjacent goals (whole-task placement) NOT covered.
EOF
bash "$HERE/mu_checks.sh" fence "$T/fence.tsv" "$T/docs" >"$T/f1.out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "F1 verdict cited only inside its fence -> clean" || bad "F1 expected 0 got $rc: $(cat "$T/f1.out")"

cat > "$T/docs/plan.md" <<'EOF'
We will not attempt whole-task placement because VD-77 says it is impossible.
EOF
bash "$HERE/mu_checks.sh" fence "$T/fence.tsv" "$T/docs" >"$T/f2.out" 2>&1; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'FENCE-VIOLATION.*plan.md' "$T/f2.out"; then
  ok "F2 verdict cited beyond its fence -> violation naming the citing file (MU-2 closed)"
else
  bad "F2 expected 1 FENCE-VIOLATION plan.md got $rc: $(cat "$T/f2.out")"
fi

# ---- seam -----------------------------------------------------------------
printf 'CM-E2-CHECK\tactivation\n' > "$T/gates.tsv"
cat > "$T/plan_good.md" <<'EOF'
REQUIRE CM-E2-CHECK AT activation
EOF
bash "$HERE/mu_checks.sh" seam "$T/gates.tsv" "$T/plan_good.md" >"$T/m1.out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "M1 plan requiring the gate at its declared seam -> clean" || bad "M1 expected 0 got $rc"

cat > "$T/plan_bad.md" <<'EOF'
REQUIRE CM-E2-CHECK AT authorship
EOF
bash "$HERE/mu_checks.sh" seam "$T/gates.tsv" "$T/plan_bad.md" >"$T/m2.out" 2>&1; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'SEAM-MISMATCH' "$T/m2.out"; then
  ok "M2 restatement moved the gate to a different seam -> SEAM-MISMATCH (MU-3 caught mechanically)"
else
  bad "M2 expected 1 SEAM-MISMATCH got $rc: $(cat "$T/m2.out")"
fi

echo "----------------------------------------"
echo "RESULT: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
