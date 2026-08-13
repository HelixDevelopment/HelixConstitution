#!/usr/bin/env bash
# SOL-09 POC test — detection-pressure scheduler.
# Written FIRST (§11.4.224). RED before pressure_queue.sh exists.
#
# Contract (pressure_queue.sh <registry.tsv> <verdicts.tsv> <topology.txt> <current-fp> <max-age-days> <now-epoch>):
#   registry: guard_id <TAB> item_id <TAB> topology_class <TAB> reopens_count
#   verdicts: guard_id <TAB> exit <TAB> fingerprint <TAB> epoch
#   Output: a RERUN QUEUE — every topology-present guard whose latest verdict is
#     (a) absent, (b) on a stale fingerprint, or (c) older than max-age-days,
#     ordered MOST-REOPENED-FIRST (§11.4.189), then stalest-first.
#   exit 0 = queue empty (all fresh on current fp) | 3 = queue non-empty | 2 = blind
#   Topology-absent guards: enumerated, never queued (no false pressure §11.4.201(1)).
#
# Cases:
#   A fresh guard on current fp -> not queued
#   B guard with NO verdict -> queued
#   C guard with stale-fingerprint verdict -> queued
#   D guard with old (beyond budget) verdict on current fp -> queued
#   E ordering: reopens=4 guard queued BEFORE reopens=0 guard
#   F topology-absent guard -> enumerated, not queued
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
[ -f "$HERE/pressure_queue.sh" ] || { echo "FAIL: missing artifact pressure_queue.sh"; echo "RESULT: RED"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
NOW=1000000000; DAY=86400; FP="fp-now"

cat > "$T/reg.tsv" <<'EOF'
G_FRESH	ATM-1	device	0
G_NOVERDICT	ATM-2	device	4
G_STALEFP	ATM-3	device	1
G_OLD	ATM-4	device	0
G_ABSENT	ATM-5	speaker_array	9
EOF
printf 'device\n' > "$T/topo.txt"
{
  printf 'G_FRESH\t0\t%s\t%s\n'   "$FP" "$((NOW - DAY))"
  printf 'G_STALEFP\t0\tfp-old\t%s\n'    "$((NOW - DAY))"
  printf 'G_OLD\t0\t%s\t%s\n'     "$FP" "$((NOW - 40*DAY))"
} > "$T/ver.tsv"

bash "$HERE/pressure_queue.sh" "$T/reg.tsv" "$T/ver.tsv" "$T/topo.txt" "$FP" 7 "$NOW" > "$T/q.out" 2>&1
rc=$?
[ "$rc" -eq 3 ] && ok "queue non-empty -> exit 3" || bad "expected 3 got $rc: $(cat "$T/q.out")"
grep -q '^QUEUE.*G_FRESH' "$T/q.out" && bad "A fresh guard was queued" || ok "A fresh guard on current fp not queued"
grep -q '^QUEUE.*G_NOVERDICT' "$T/q.out" && ok "B never-executed guard queued" || bad "B G_NOVERDICT missing from queue"
grep -q '^QUEUE.*G_STALEFP' "$T/q.out" && ok "C stale-fingerprint guard queued" || bad "C G_STALEFP missing"
grep -q '^QUEUE.*G_OLD' "$T/q.out" && ok "D over-budget-age guard queued" || bad "D G_OLD missing"
first_queued=$(grep '^QUEUE' "$T/q.out" | head -1)
case "$first_queued" in
  *G_NOVERDICT*) ok "E most-reopened (4) guard ordered FIRST (§11.4.189)";;
  *) bad "E expected G_NOVERDICT first, got: $first_queued";;
esac
if grep -q 'TOPOLOGY-EXEMPT.*G_ABSENT' "$T/q.out" && ! grep -q '^QUEUE.*G_ABSENT' "$T/q.out"; then
  ok "F topology-absent guard enumerated, not queued (no false pressure)"
else
  bad "F G_ABSENT handling wrong: $(cat "$T/q.out")"
fi

# Empty registry is blind
: > "$T/empty.tsv"
bash "$HERE/pressure_queue.sh" "$T/empty.tsv" "$T/ver.tsv" "$T/topo.txt" "$FP" 7 "$NOW" > "$T/e.out" 2>&1
rc=$?
[ "$rc" -eq 2 ] && ok "G empty registry -> blind (2)" || bad "G expected 2 got $rc"

echo "----------------------------------------"
echo "RESULT: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
