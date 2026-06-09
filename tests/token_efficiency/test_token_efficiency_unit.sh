#!/usr/bin/env bash
# tests/token_efficiency/test_token_efficiency_unit.sh
#
# §11.4.141 UNIT tests (§11.4.27 — unit tier; synthetic `usage` fixtures permitted).
# Proves the measurement harness (token_accounting.sh) + the warm-cache helper +
# the model-tier resolver compute the CORRECT values against hand-calculated
# expectations — the cost formula, the cache multipliers, the warm/ratio verdict,
# and the tiering bright line. The harness reads the AUTHORITATIVE Anthropic
# `usage` object and recomputes cost from raw fields (tiktoken / total_cost_usd
# forbidden — §11.4.141) — that rejection is asserted here.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   bash tests/token_efficiency/test_token_efficiency_unit.sh
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Per-assertion PASS/FAIL lines + a final RESULT. Exit 0 iff all pass.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Writes temp fixtures + a cycle report under qa-results/token_efficiency/<run>/.
#   No device mutation, no network, no commit.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   scripts/token_accounting.sh, scripts/enable_prompt_caching_check.sh,
#   scripts/subagent_tier.sh, jq. Parses clean under bash -n AND sh -n (§11.4.67).
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.141, §11.4.6 (measured), §11.4.50 (determinism), §11.4.27 (unit tier),
#   §11.4.69 (captured-evidence), §1.1 (the meta-test mutates these assertions).
#
# Classification: universal (§11.4.17).

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
CONST_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TOKACC="${CONST_ROOT}/scripts/token_accounting.sh"
CACHECHK="${CONST_ROOT}/scripts/enable_prompt_caching_check.sh"
TIER="${CONST_ROOT}/scripts/subagent_tier.sh"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)_$$"
EVID="${CONST_ROOT}/qa-results/token_efficiency/${RUN_ID}/unit"
mkdir -p "$EVID"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
no()  { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
# floating-point equality within tolerance
feq() { awk -v a="$1" -v b="$2" -v t="${3:-1e-9}" 'BEGIN{d=a-b; if(d<0)d=-d; exit !(d<=t)}'; }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq missing"; exit 2; }

# ── U1: cost formula on a single known usage object ──────────────────────────
# input=1000, cache_read=50000, cache_5m=0, cache_1h=0, output=200, Opus(5/25).
# cost = 5/1e6*(1000+0.1*50000) + 25/1e6*200 = 5/1e6*6000 + 0.005 = 0.030+0.005 = 0.035
echo '{"usage":{"input_tokens":1000,"cache_read_input_tokens":50000,"cache_creation_input_tokens":0,"output_tokens":200}}' > "$EVID/u1.jsonl"
c1="$(bash "$TOKACC" aggregate --transcript "$EVID/u1.jsonl" --model claude-opus-4-8 2>/dev/null | jq -r '.cost_usd')"
if feq "$c1" "0.035"; then ok "U1 cost formula (cache_read 0.1x) = 0.035 (got $c1)"; else no "U1 cost formula expected 0.035 got $c1"; fi

# ── U2: cache-creation 5m (1.25x) + 1h (2.0x) split ──────────────────────────
# 5m=40000, 1h=60000 → 5/1e6*(1.25*40000 + 2.0*60000) = 5/1e6*170000 = 0.85
echo '{"usage":{"input_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":100000,"cache_creation":{"ephemeral_5m_input_tokens":40000,"ephemeral_1h_input_tokens":60000},"output_tokens":0}}' > "$EVID/u2.jsonl"
c2="$(bash "$TOKACC" aggregate --transcript "$EVID/u2.jsonl" --model claude-opus-4-8 2>/dev/null | jq -r '.cost_usd')"
if feq "$c2" "0.85"; then ok "U2 cache-write 1.25x/2.0x split = 0.85 (got $c2)"; else no "U2 expected 0.85 got $c2"; fi

# ── U3: per-model summation (Sonnet vs Haiku prices) ─────────────────────────
# output 1000 tokens only. Sonnet out=15 → 0.015 ; Haiku out=5 → 0.005
echo '{"usage":{"input_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"output_tokens":1000}}' > "$EVID/u3.jsonl"
cs="$(bash "$TOKACC" aggregate --transcript "$EVID/u3.jsonl" --model claude-sonnet-4-6 2>/dev/null | jq -r '.cost_usd')"
ch="$(bash "$TOKACC" aggregate --transcript "$EVID/u3.jsonl" --model claude-haiku-4-5 2>/dev/null | jq -r '.cost_usd')"
if feq "$cs" "0.015" && feq "$ch" "0.005"; then ok "U3 per-model prices Sonnet=$cs Haiku=$ch"; else no "U3 expected Sonnet 0.015/Haiku 0.005 got $cs/$ch"; fi

# ── U4: client-side total_cost_usd is IGNORED (forbidden per §11.4.141) ──────
echo '{"type":"result","total_cost_usd":999.99,"usage":{"input_tokens":1000,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"output_tokens":0}}' > "$EVID/u4.json"
c4="$(bash "$TOKACC" aggregate --transcript "$EVID/u4.json" --model claude-opus-4-8 2>/dev/null | jq -r '.cost_usd')"
# recomputed cost = 5/1e6*1000 = 0.005  (NOT 999.99)
if feq "$c4" "0.005" && ! feq "$c4" "999.99" "1"; then ok "U4 ignores total_cost_usd=999.99, recomputes 0.005 (got $c4)"; else no "U4 should recompute 0.005 not trust 999.99, got $c4"; fi

# ── U5: empty / no-usage transcript is rejected (§11.4.1 FAIL-bluff guard) ────
echo '{"no":"usage"}' > "$EVID/u5.jsonl"
if bash "$TOKACC" aggregate --transcript "$EVID/u5.jsonl" --model claude-opus-4-8 >/dev/null 2>&1; then
    no "U5 empty transcript should be rejected (exit 2)"
else
    ok "U5 empty/no-usage transcript rejected (exit 2)"
fi

# ── U6: warm-cache ratio verdict ─────────────────────────────────────────────
echo '{"usage":{"input_tokens":100,"cache_read_input_tokens":900,"cache_creation_input_tokens":0,"output_tokens":0}}' > "$EVID/u6.jsonl"
# ratio = 900/(100+900) = 0.9 → WARM at min 0.5
if bash "$CACHECHK" --transcript "$EVID/u6.jsonl" --min-ratio 0.5 >/dev/null 2>&1; then ok "U6 warm-cache ratio 0.9 >= 0.5 → WARM (exit 0)"; else no "U6 expected WARM"; fi
# cold case
echo '{"usage":{"input_tokens":1000,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"output_tokens":0}}' > "$EVID/u6b.jsonl"
if bash "$CACHECHK" --transcript "$EVID/u6b.jsonl" >/dev/null 2>&1; then no "U6b cache_read=0 should be COLD (exit 1)"; else ok "U6b cache_read=0 → COLD (exit 1)"; fi

# ── U7: verdict PASS / WARN / FAIL bands ─────────────────────────────────────
bash "$TOKACC" aggregate --transcript "${CONST_ROOT}/tests/token_efficiency/fixtures/before.jsonl" --model claude-opus-4-8 --out "$EVID/before.json" >/dev/null 2>&1
bash "$TOKACC" aggregate --transcript "${CONST_ROOT}/tests/token_efficiency/fixtures/after.jsonl"  --model claude-opus-4-8 --out "$EVID/after.json"  >/dev/null 2>&1
bash "$TOKACC" verdict --before "$EVID/before.json" --after "$EVID/after.json" >/dev/null 2>&1; rc=$?
if [ $rc -eq 0 ]; then ok "U7 PASS band: AFTER<=0.40*BEFORE → verdict PASS (exit 0)"; else no "U7 expected PASS exit 0 got $rc"; fi

# WARN-band fixture (5x 80000 input → cost 2.0625 vs before 4.3125 → 0.522 reduction)
for i in 1 2 3 4 5; do echo '{"usage":{"input_tokens":80000,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"output_tokens":500}}'; done > "$EVID/warn.jsonl"
bash "$TOKACC" aggregate --transcript "$EVID/warn.jsonl" --model claude-opus-4-8 --out "$EVID/warn.json" >/dev/null 2>&1
bash "$TOKACC" verdict --before "$EVID/before.json" --after "$EVID/warn.json" --cold-cache-reason "cache cold per RESEARCH §5" >/dev/null 2>&1; rc=$?
if [ $rc -eq 3 ]; then ok "U7 WARN band: floor + cold-reason → verdict WARN (exit 3)"; else no "U7 expected WARN exit 3 got $rc"; fi
bash "$TOKACC" verdict --before "$EVID/before.json" --after "$EVID/warn.json" >/dev/null 2>&1; rc=$?
if [ $rc -eq 1 ]; then ok "U7 FAIL band: floor WITHOUT cold-reason → verdict FAIL (exit 1)"; else no "U7 expected FAIL exit 1 got $rc"; fi

# ── U8: tiering bright line — judgment class REFUSED for mechanical model ─────
if bash "$TIER" assert-mechanical code_search >/dev/null 2>&1; then ok "U8 code_search is mechanical (safe to tier down)"; else no "U8 code_search should be mechanical"; fi
if bash "$TIER" assert-mechanical pass_fail_verdict >/dev/null 2>&1; then no "U8 pass_fail_verdict must be REFUSED (judgment)"; else ok "U8 pass_fail_verdict REFUSED for mechanical model (bright line)"; fi
if bash "$TIER" assert-mechanical fix_design >/dev/null 2>&1; then no "U8 fix_design must be REFUSED (judgment)"; else ok "U8 fix_design REFUSED (judgment §11.4.102)"; fi
if bash "$TIER" assert-mechanical code_review >/dev/null 2>&1; then no "U8 code_review must be REFUSED (judgment)"; else ok "U8 code_review REFUSED (judgment §11.4.125)"; fi

# ── Result ───────────────────────────────────────────────────────────────────
echo "----"
echo "RESULT: ${PASS} PASS / ${FAIL} FAIL   [evidence: ${EVID}]"
[ "$FAIL" -eq 0 ]
