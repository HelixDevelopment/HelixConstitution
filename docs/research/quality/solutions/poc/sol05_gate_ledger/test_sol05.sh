#!/usr/bin/env bash
# SOL-05 POC test — gate ledger + implementation ratchet.
# Written FIRST (§11.4.224). RED before gate_ledger.sh exists.
#
# Contract:
#   gate_ledger.sh generate <corpus.md> <impl-dir> > ledger.tsv
#     ledger rows: GATE_ID <TAB> IMPLEMENTED <TAB> <file>   |   GATE_ID <TAB> UNIMPLEMENTED <TAB> -
#   gate_ledger.sh check <ledger.tsv> <baseline-file> <deferral.tsv> <prev-gate-set> [removal-citations]
#     FAIL(1) if: any UNIMPLEMENTED gate has no deferral row (gate_id<TAB>item_id)
#                 unimplemented count > baseline (monotone ratchet)
#                 a gate id present in prev-gate-set vanished without a removal citation
#                 (closes the metric-gaming channel §11.4.201(8): deleting the NAME
#                  must not silently lower the count)
#     PASS(0) otherwise; blind inputs -> 2.
#
# Cases:
#   A generate       : corpus with 3 named gates, impl dir implements 1 -> ledger says 1/3
#   B golden-bad-1   : UNIMPLEMENTED gate without deferral row -> check FAILs naming it
#   C negative-ctl   : same gate WITH a registered deferral (tracked item) -> check PASSes
#   D golden-bad-2   : unimplemented count above baseline -> check FAILs (ratchet)
#   E golden-bad-3   : gate name deleted from corpus without citation -> check FAILs
#   F carrier control: a gate id mentioned in a .md file inside impl-dir does NOT
#                      count as implementation (structure: only executable .sh sites count)
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
[ -f "$HERE/gate_ledger.sh" ] || { echo "FAIL: missing artifact gate_ledger.sh"; echo "RESULT: RED"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/impl"

cat > "$T/corpus.md" <<'EOF'
Rules: gate `CM-ALPHA-CHECK` guards A. Gate `CM-BETA-CHECK` guards B.
Recommended gate `CM-GAMMA-CHECK` + paired mutation (gate-code = separate work item).
EOF
cat > "$T/impl/alpha.sh" <<'EOF'
#!/bin/sh
# implements CM-ALPHA-CHECK
echo CM-ALPHA-CHECK
EOF
cat > "$T/impl/carrier.md" <<'EOF'
This document merely mentions CM-BETA-CHECK in prose.
EOF

# ---- A + F: generate ------------------------------------------------------
bash "$HERE/gate_ledger.sh" generate "$T/corpus.md" "$T/impl" > "$T/ledger.tsv" 2>"$T/gen.err"
if grep -q $'CM-ALPHA-CHECK\tIMPLEMENTED' "$T/ledger.tsv" \
   && grep -q $'CM-BETA-CHECK\tUNIMPLEMENTED' "$T/ledger.tsv" \
   && grep -q $'CM-GAMMA-CHECK\tUNIMPLEMENTED' "$T/ledger.tsv"; then
  ok "A ledger generated: 1 implemented, 2 unimplemented"
else
  bad "A ledger wrong: $(cat "$T/ledger.tsv") err: $(cat "$T/gen.err")"
fi
grep -q $'CM-BETA-CHECK\tIMPLEMENTED' "$T/ledger.tsv" \
  && bad "F .md carrier counted as implementation" \
  || ok "F prose carrier in impl-dir does not count as implementation"

# ---- B golden-bad-1: unimplemented without deferral -----------------------
echo 3 > "$T/baseline"           # generous baseline so only the deferral rule fires
: > "$T/deferrals.tsv"
cut -f1 "$T/ledger.tsv" | sort > "$T/prev_set"
bash "$HERE/gate_ledger.sh" check "$T/ledger.tsv" "$T/baseline" "$T/deferrals.tsv" "$T/prev_set" > "$T/b.out" 2>&1
rc=$?
if [ "$rc" -eq 1 ] && grep -q 'CM-BETA-CHECK' "$T/b.out"; then
  ok "B unimplemented gate without registered deferral -> FAIL naming it"
else
  bad "B expected 1 naming CM-BETA-CHECK got $rc: $(cat "$T/b.out")"
fi

# ---- C negative-control: registered deferral is legal ---------------------
printf 'CM-BETA-CHECK\tATM-900\nCM-GAMMA-CHECK\tATM-901\n' > "$T/deferrals.tsv"
bash "$HERE/gate_ledger.sh" check "$T/ledger.tsv" "$T/baseline" "$T/deferrals.tsv" "$T/prev_set" > "$T/c.out" 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "C registered deferrals accepted (explicit debt is legal; silent debt is not)" \
  || bad "C expected 0 got $rc: $(cat "$T/c.out")"

# ---- D golden-bad-2: ratchet ----------------------------------------------
echo 1 > "$T/baseline"           # unimplemented=2 > baseline=1
bash "$HERE/gate_ledger.sh" check "$T/ledger.tsv" "$T/baseline" "$T/deferrals.tsv" "$T/prev_set" > "$T/d.out" 2>&1
rc=$?
if [ "$rc" -eq 1 ] && grep -qi 'ratchet' "$T/d.out"; then
  ok "D unimplemented count above baseline -> ratchet FAIL"
else
  bad "D expected ratchet FAIL got $rc: $(cat "$T/d.out")"
fi

# ---- E golden-bad-3: silent name deletion ---------------------------------
echo 3 > "$T/baseline"
printf 'CM-ALPHA-CHECK\nCM-BETA-CHECK\nCM-DELETED-CHECK\nCM-GAMMA-CHECK\n' > "$T/prev_set2"
bash "$HERE/gate_ledger.sh" check "$T/ledger.tsv" "$T/baseline" "$T/deferrals.tsv" "$T/prev_set2" > "$T/e.out" 2>&1
rc=$?
if [ "$rc" -eq 1 ] && grep -q 'CM-DELETED-CHECK' "$T/e.out"; then
  ok "E gate name vanished without citation -> FAIL (metric-gaming channel closed)"
else
  bad "E expected 1 naming CM-DELETED-CHECK got $rc: $(cat "$T/e.out")"
fi
# ...and WITH a citation it passes:
printf 'CM-DELETED-CHECK\trepealed per operator decision, commit ref\n' > "$T/removals.tsv"
bash "$HERE/gate_ledger.sh" check "$T/ledger.tsv" "$T/baseline" "$T/deferrals.tsv" "$T/prev_set2" "$T/removals.tsv" > "$T/e2.out" 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "E2 cited removal accepted" || bad "E2 expected 0 got $rc: $(cat "$T/e2.out")"

echo "----------------------------------------"
echo "RESULT: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
