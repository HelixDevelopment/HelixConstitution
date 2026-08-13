#!/usr/bin/env bash
# SOL-03 POC test — the needle-carrying measurement primitive.
# Written FIRST (§11.4.224). RED before needle_lib.sh exists.
#
# Contract under test (needle_lib.sh sourced functions):
#   nq_absent <file> <query-ere> <needle-ere>
#     exit 0 = CERTIFIED-ABSENT  (query 0 hits AND needle >0 hits through the SAME path)
#     exit 1 = PRESENT           (query has hits; prints sample lines — a count is a lead,
#                                 the lines are the finding, MU-6)
#     exit 2 = INSTRUMENT-BLIND  (needle returned 0 through the same path — the zero says NOTHING)
#     exit 3 = NEEDLE-CLASS-MISMATCH (query uses regex features the needle does not exercise —
#                                 a bare-literal needle cannot certify a dialect-dependent query,
#                                 §11.4.201(7)(b))
#   nq_stream_contains <producer-cmd...> -- <ere>
#     SIGPIPE-safe presence check on a stream: reads the producer to EOF, never
#     early-exits the consumer under pipefail. exit 0 present / 1 absent / 2 blind.
#
# Cases:
#   A golden-good      : absent token + present needle -> CERTIFIED-ABSENT (0)
#   B present          : query hits -> exit 1 AND sample lines printed
#   C golden-bad       : broken instrument (injected grep that sees nothing) -> exit 2, NEVER 0
#   D negative-control : carrier text mentions the token; structure-anchored query -> still
#                        CERTIFIED-ABSENT (no false-match on the carrier)
#   E class-mismatch   : alternation query + literal needle -> exit 3 (refused certification)
#   F SIGPIPE hazard   : 2MB payload, needle on line 1, under `set -o pipefail`:
#                        naive `| grep -q` misreports ABSENT (measured 400/400 on this host);
#                        nq_stream_contains reports PRESENT
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
[ -f "$HERE/needle_lib.sh" ] || { echo "FAIL: missing artifact needle_lib.sh"; echo "RESULT: RED"; exit 1; }
# shellcheck disable=SC1091
. "$HERE/needle_lib.sh"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# Fixture file: a known-present needle header + carrier prose + NO real forbidden token
cat > "$T/target.txt" <<'EOF'
HEADER: fixture-v1
This prose merely mentions FORBIDDEN_TOKEN inside a sentence (a carrier).
normal line
EOF

# ---- A golden-good --------------------------------------------------------
nq_absent "$T/target.txt" '^REAL_ABSENT_THING=' '^HEADER: fixture-v1$' >"$T/a.out" 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "A absent query + sighted needle -> CERTIFIED-ABSENT (0)" || bad "A expected 0 got $rc: $(cat "$T/a.out")"

# ---- B present with sample lines ------------------------------------------
nq_absent "$T/target.txt" '^normal line$' '^HEADER: fixture-v1$' >"$T/b.out" 2>&1
rc=$?
if [ "$rc" -eq 1 ] && grep -q 'normal line' "$T/b.out"; then
  ok "B present -> exit 1 with the matching LINES printed (count is a lead, lines are the finding)"
else
  bad "B expected 1 + sample lines, got $rc: $(cat "$T/b.out")"
fi

# ---- C golden-bad: blind instrument ---------------------------------------
FAKE="$T/fakebin"; mkdir -p "$FAKE"
cat > "$FAKE/grep" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$FAKE/grep"
NQ_GREP="$FAKE/grep" nq_absent "$T/target.txt" '^REAL_ABSENT_THING=' '^HEADER: fixture-v1$' >"$T/c.out" 2>&1
rc=$?
if [ "$rc" -eq 2 ] && grep -q 'INSTRUMENT-BLIND' "$T/c.out"; then
  ok "C blind instrument -> exit 2 INSTRUMENT-BLIND, the zero is never reported as absence"
else
  bad "C expected 2 INSTRUMENT-BLIND, got $rc: $(cat "$T/c.out")"
fi

# ---- D negative-control: carrier does not false-match ---------------------
nq_absent "$T/target.txt" '^FORBIDDEN_TOKEN=' '^HEADER: fixture-v1$' >"$T/d.out" 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "D structure-anchored query ignores the prose carrier -> CERTIFIED-ABSENT" \
  || bad "D carrier false-matched or blind: rc=$rc $(cat "$T/d.out")"

# ---- E needle-class mismatch refused --------------------------------------
nq_absent "$T/target.txt" '^(AAA|BBB):' '^HEADER' >"$T/e.out" 2>&1
rc=$?
if [ "$rc" -eq 3 ] && grep -q 'NEEDLE-CLASS-MISMATCH' "$T/e.out"; then
  ok "E alternation query + featureless needle -> refused (bare-literal needle certifies nothing)"
else
  bad "E expected 3 NEEDLE-CLASS-MISMATCH, got $rc: $(cat "$T/e.out")"
fi
# and the matched-class needle IS accepted:
nq_absent "$T/target.txt" '^(AAA|BBB):' '^(HEADER|NOSUCH):' >"$T/e2.out" 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "E2 alternation-carrying needle accepted -> CERTIFIED-ABSENT" || bad "E2 expected 0 got $rc: $(cat "$T/e2.out")"

# ---- F the SIGPIPE/pipefail hazard ----------------------------------------
PAY="$T/payload.txt"
{ echo "NEEDLE_PRESENT"; head -c 2000000 /dev/zero | tr '\0' 'x' | fold -w 80; } > "$PAY"
set -o pipefail
naive_miss=0
if cat "$PAY" | grep -q NEEDLE_PRESENT; then :; else naive_miss=1; fi
set +o pipefail
if [ "$naive_miss" -eq 1 ]; then
  ok "F1 hazard reproduced: naive 'cat | grep -q' under pipefail reads the PRESENT literal as ABSENT"
else
  echo "NOTE: F1 hazard did not fire on this run (timing-dependent below saturation payload)"
fi
set -o pipefail
if nq_stream_contains cat "$PAY" -- 'NEEDLE_PRESENT' >"$T/f.out" 2>&1; then
  ok "F2 nq_stream_contains reports PRESENT under pipefail (SIGPIPE-safe by construction)"
else
  bad "F2 nq_stream_contains missed a present literal: $(cat "$T/f.out")"
fi
set +o pipefail

echo "----------------------------------------"
echo "RESULT: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
