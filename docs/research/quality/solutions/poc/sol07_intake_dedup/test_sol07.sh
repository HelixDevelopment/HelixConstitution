#!/usr/bin/env bash
# SOL-07 POC test — recurrence intake: dedup + writer-repair classification.
# Written FIRST (§11.4.224). RED before intake_check.sh exists.
#
# Contract:
#   intake_check.sh dedup <existing.tsv> <new-subject> <new-scope>
#     existing.tsv: item_id <TAB> status <TAB> scope <TAB> subject
#     exit 0  = DISTINCT -> mint a new id
#     exit 10 = SAME-DEFECT-CANDIDATE -> mint-with-link + reopen-through-chain-head
#               (autonomous default per §11.4.214(3): a spurious id is recoverable,
#                a wrongly-merged defect is LOST)
#     keying: normalized (subject, scope) — NEVER bare subject substring (§11.4.186)
#   intake_check.sh fixkind <defect-shape: state|behaviour> <fix-kind: writer-repair|state-repair>
#     exit 0 = closure legal
#     exit 1 = REFUSED: a state-shaped defect closed by a state-only repair is a
#              MITIGATION with recurrence horizon = the writer's next run
#              (corpus-2 §7.3 writer-repair rule; the fossil's ~7 h horizon)
#
# Cases:
#   A distinct new item -> 0
#   B golden-bad: near-identical resubmission of a CLOSED item, same scope -> 10 naming the head
#   C negative-control: the corpus-3 HXC-052/053 archetype — same defect CLASS,
#     DIFFERENT scopes (two modules) -> DISTINCT (must NOT merge)
#   D fixkind golden-bad: state defect + state-repair -> refused with horizon message
#   E fixkind good: state defect + writer-repair -> 0
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
[ -f "$HERE/intake_check.sh" ] || { echo "FAIL: missing artifact intake_check.sh"; echo "RESULT: RED"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cat > "$T/items.tsv" <<'EOF'
ATM-100	Fixed	overlay	Watch-toggle overlay covers screen after media pause
ATM-101	Fixed	background_tasks	go.mod build break capitalised replace paths
ATM-102	In progress	audio	multichannel collapses to stereo on USB enumeration shift
EOF

bash "$HERE/intake_check.sh" dedup "$T/items.tsv" "brand-new subtitle cadence drift on secondary display" "subtitles" >"$T/a.out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "A genuinely new item -> DISTINCT (mint)" || bad "A expected 0 got $rc: $(cat "$T/a.out")"

bash "$HERE/intake_check.sh" dedup "$T/items.tsv" "overlay covers the screen again after media pause" "overlay" >"$T/b.out" 2>&1; rc=$?
if [ "$rc" -eq 10 ] && grep -q 'ATM-100' "$T/b.out"; then
  ok "B recurrence of a closed defect -> SAME-DEFECT-CANDIDATE naming ATM-100 (link + reopen head, not a new silent id)"
else
  bad "B expected 10 naming ATM-100 got $rc: $(cat "$T/b.out")"
fi

bash "$HERE/intake_check.sh" dedup "$T/items.tsv" "go.mod build break capitalised replace path" "conversation" >"$T/c.out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "C same defect CLASS in a DIFFERENT scope -> DISTINCT (the HXC-052/053 negative control — no false merge)" \
  || bad "C expected 0 got $rc: $(cat "$T/c.out")"

bash "$HERE/intake_check.sh" fixkind state state-repair >"$T/d.out" 2>&1; rc=$?
if [ "$rc" -eq 1 ] && grep -qi 'recurrence horizon' "$T/d.out"; then
  ok "D state defect + state-only repair -> refused as mitigation with a recurrence horizon"
else
  bad "D expected 1 with horizon message got $rc: $(cat "$T/d.out")"
fi

bash "$HERE/intake_check.sh" fixkind state writer-repair >"$T/e.out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "E state defect + writer-repair -> closure legal" || bad "E expected 0 got $rc"

echo "----------------------------------------"
echo "RESULT: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
