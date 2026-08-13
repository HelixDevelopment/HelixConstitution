#!/usr/bin/env bash
# SOL-02 POC test — coverage-aware verdict semantics at the release seam.
# Written FIRST (§11.4.224). RED before verdict_gate.sh exists.
#
# Contract under test (verdict_gate.sh <registry.tsv> <verdicts.tsv> <topology.txt> <candidate-fp>):
#   exit 0  = every registered, topology-present guard has an exit-0 verdict ON THE CANDIDATE fingerprint
#   exit 1  = >=1 FAIL verdict on the candidate fingerprint (FAIL dominates)
#   exit 3  = zero FAILs but uncovered != empty set  (ABSENCE BLOCKS LIKE FAIL — the M9 fix)
#   topology-absent guards: enumerated as honest gaps in output, NEVER blocking, NEVER silent
#   stale verdicts (different fingerprint): count as ABSENT for the candidate (self-clearing)
#
# Cases:
#   A golden-good        : full coverage, all green -> exit 0
#   B golden-bad-1 (M9)  : 61 guards, 0 PASS / 5 FAIL / 56 no-verdict -> exit 1, uncovered=56 reported
#                          (the EXACT live incident where the old suite exited 0 "not blocked")
#   C golden-bad-2       : 0 FAIL, 1 uncovered -> exit 3
#   D golden-bad-3       : verdict exists only for an OLD fingerprint -> uncovered -> exit 3
#   E negative-control   : topology-absent guard -> enumerated, NOT blocking -> exit 0
#                          (a flat "PENDING always blocks" here would be the §11.4.201(1) FAIL-bluff)
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
[ -f "$HERE/verdict_gate.sh" ] || { echo "FAIL: missing artifact verdict_gate.sh"; echo "RESULT: RED"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
FP="fp-candidate-2026"

# ---- A golden-good --------------------------------------------------------
cat > "$T/reg.tsv" <<EOF
G1	ATM-1	device	tests/g1.sh
G2	ATM-2	host	tests/g2.sh
EOF
printf 'G1\tGREEN\t0\t%s\tev/g1.log\nG2\tGREEN\t0\t%s\tev/g2.log\n' "$FP" "$FP" > "$T/ver.tsv"
printf 'device\nhost\n' > "$T/topo.txt"
bash "$HERE/verdict_gate.sh" "$T/reg.tsv" "$T/ver.tsv" "$T/topo.txt" "$FP" > "$T/a.out" 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "A full coverage all-green -> exit 0" || bad "A expected 0 got $rc: $(cat "$T/a.out")"

# ---- B golden-bad-1: the exact M9 incident shape --------------------------
: > "$T/reg.tsv"; : > "$T/ver.tsv"
for i in $(seq 1 61); do printf 'G%d\tATM-%d\tdevice\ttests/g%d.sh\n' "$i" "$i" "$i" >> "$T/reg.tsv"; done
for i in $(seq 1 5);  do printf 'G%d\tGREEN\t1\t%s\tev/g%d.log\n' "$i" "$FP" "$i" >> "$T/ver.tsv"; done
bash "$HERE/verdict_gate.sh" "$T/reg.tsv" "$T/ver.tsv" "$T/topo.txt" "$FP" > "$T/b.out" 2>&1
rc=$?
if [ "$rc" -eq 1 ]; then
  grep -q 'uncovered=56' "$T/b.out" && ok "B M9 shape (5 FAIL + 56 no-verdict) -> exit 1 AND uncovered=56 reported" \
    || bad "B exit 1 but uncovered count wrong: $(grep -o 'uncovered=[0-9]*' "$T/b.out")"
else
  bad "B M9 shape returned exit $rc (the historical bug returned 0)"
fi

# ---- C golden-bad-2: absence alone blocks ---------------------------------
cat > "$T/reg.tsv" <<EOF
G1	ATM-1	device	tests/g1.sh
G2	ATM-2	device	tests/g2.sh
EOF
printf 'G1\tGREEN\t0\t%s\tev/g1.log\n' "$FP" > "$T/ver.tsv"
bash "$HERE/verdict_gate.sh" "$T/reg.tsv" "$T/ver.tsv" "$T/topo.txt" "$FP" > "$T/c.out" 2>&1
rc=$?
[ "$rc" -eq 3 ] && ok "C zero FAILs + 1 uncovered -> exit 3 (absence blocks)" || bad "C expected 3 got $rc"

# ---- D golden-bad-3: stale-fingerprint verdict counts as absent -----------
printf 'G1\tGREEN\t0\t%s\tev/g1.log\nG2\tGREEN\t0\tfp-OLD-BUILD\tev/g2.log\n' "$FP" > "$T/ver.tsv"
bash "$HERE/verdict_gate.sh" "$T/reg.tsv" "$T/ver.tsv" "$T/topo.txt" "$FP" > "$T/d.out" 2>&1
rc=$?
if [ "$rc" -eq 3 ] && grep -q 'G2' "$T/d.out"; then
  ok "D stale-fingerprint verdict treated as absent for the candidate (self-clearing)"
else
  bad "D expected exit 3 naming G2, got $rc: $(cat "$T/d.out")"
fi

# ---- E negative-control: topology-absent exempt but enumerated ------------
cat > "$T/reg.tsv" <<EOF
G1	ATM-1	device	tests/g1.sh
G9	ATM-9	speaker_array	tests/g9.sh
EOF
printf 'G1\tGREEN\t0\t%s\tev/g1.log\n' "$FP" > "$T/ver.tsv"
bash "$HERE/verdict_gate.sh" "$T/reg.tsv" "$T/ver.tsv" "$T/topo.txt" "$FP" > "$T/e.out" 2>&1
rc=$?
if [ "$rc" -eq 0 ] && grep -q 'TOPOLOGY-EXEMPT.*G9' "$T/e.out"; then
  ok "E topology-absent guard exempt (no false block) AND enumerated (never silent)"
else
  bad "E expected exit 0 with enumerated G9 exemption, got $rc: $(cat "$T/e.out")"
fi

echo "----------------------------------------"
echo "RESULT: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
