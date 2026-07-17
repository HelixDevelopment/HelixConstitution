#!/usr/bin/env bash
# ============================================================================
# live_smoke.sh — live captured-evidence smoke run for scheduled-work-engine
# ============================================================================
# Purpose:
#   Boot the REAL built binary and exercise the full work-item lifecycle end
#   to end, capturing the transcript as evidence (constitution §11.4.5 /
#   §11.4.69 / §11.4.83). Two surfaces:
#     (A) REST over TLS (HTTP/1.1+2, curl) — create -> list -> mark-done -> verify
#     (B) MCP over stdio (JSON-RPC 2.0) — initialize -> tools/call create -> list
#   The HTTP/3 + brotli surface is proven by test/integration_test.go (real h3
#   client); curl here does not speak h3, so this smoke uses the h1/h2 fallback
#   of the SAME engine (honest boundary per §11.4.6).
#
# Usage:   bash test/live_smoke.sh
# Outputs: transcript to stdout AND to qa-results/<ts>/live_smoke.log
# Exit:    0 all steps confirmed, 1 on any failure.
# Dependencies: go, curl, python3 (jq-free JSON asserts)
# Cross-references: constitution §11.4.5 / §11.4.69 / §11.4.83 / §11.4.27.
# Last verified: 2026-07-02
# ============================================================================
set -eu

ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ENGINE_DIR"

TS="$(date -u +%Y%m%dT%H%M%SZ)"
EVID_DIR="${ENGINE_DIR}/qa-results/${TS}"
mkdir -p "$EVID_DIR"
LOG="${EVID_DIR}/live_smoke.log"
DB="${EVID_DIR}/store.json"

log() { echo "$@" | tee -a "$LOG"; }

BIN="${ENGINE_DIR}/bin/scheduled-work"
log "[smoke] building binary"
CGO_ENABLED=0 go build -o "$BIN" ./cmd/scheduled-work

ADDR="127.0.0.1:8791"
BASE="https://${ADDR}"

log "[smoke] ============ (A) REST over TLS (h1/h2) ============"
SWQ_DB="$DB" SWQ_ADDR="$ADDR" SWQ_H3=0 SWQ_BROTLI=5 "$BIN" serve >"${EVID_DIR}/server.stderr" 2>&1 &
SRV_PID=$!
cleanup() { kill "$SRV_PID" >/dev/null 2>&1 || true; }
trap cleanup EXIT INT TERM

# wait for readiness (each attempt capped at 2s connect + 3s max)
ready=0
i=0
while [ "$i" -lt 50 ]; do
	if curl -sk --connect-timeout 2 --max-time 3 "${BASE}/healthz" >/dev/null 2>&1; then ready=1; break; fi
	sleep 0.1
	i=$((i + 1))
done
if [ "$ready" -ne 1 ]; then
	log "FAIL: REST server did not become ready"
	cat "${EVID_DIR}/server.stderr" | tee -a "$LOG"
	exit 1
fi
log "[smoke] server ready at ${BASE}"

CREATE_JSON="$(curl -sk --connect-timeout 2 --max-time 5 -X POST "${BASE}/api/v1/items" \
	-H 'Content-Type: application/json' \
	-d '{"title":"live smoke: flash D1","status":"blocked","source":"smoke"}')"
log "[smoke] CREATE -> ${CREATE_JSON}"
ID="$(printf '%s' "$CREATE_JSON" | python3 -c 'import sys,json;print(json.load(sys.stdin)["id"])')"
[ -n "$ID" ] || { log "FAIL: no id returned"; exit 1; }

NV_JSON="$(curl -sk --connect-timeout 2 --max-time 5 "${BASE}/api/v1/items/needs-verification")"
log "[smoke] needs-verification -> ${NV_JSON}"
printf '%s' "$NV_JSON" | python3 -c 'import sys,json;d=json.load(sys.stdin);assert d["count"]==1,d;print("  assert count==1 OK")' | tee -a "$LOG"

DONE_JSON="$(curl -sk --connect-timeout 2 --max-time 5 -X POST "${BASE}/api/v1/items/${ID}/done" \
	-H 'Content-Type: application/json' -d '{"notes":"verified via smoke"}')"
log "[smoke] MARK-DONE -> ${DONE_JSON}"
printf '%s' "$DONE_JSON" | python3 -c 'import sys,json;d=json.load(sys.stdin);assert d["status"]=="done",d;print("  assert status==done OK")' | tee -a "$LOG"

NV2_JSON="$(curl -sk --connect-timeout 2 --max-time 5 "${BASE}/api/v1/items/needs-verification")"
log "[smoke] needs-verification (after) -> ${NV2_JSON}"
printf '%s' "$NV2_JSON" | python3 -c 'import sys,json;d=json.load(sys.stdin);assert d["count"]==0,d;print("  assert count==0 OK (state delta captured)")' | tee -a "$LOG"

cleanup
trap - EXIT INT TERM

log "[smoke] ============ (B) MCP over stdio (JSON-RPC 2.0) ============"
MCP_IN="${EVID_DIR}/mcp_in.jsonl"
{
	printf '%s\n' '{"jsonrpc":"2.0","id":"1","method":"initialize","params":{}}'
	printf '%s\n' '{"jsonrpc":"2.0","id":"2","method":"tools/call","params":{"name":"create_work_item","arguments":{"title":"mcp stdio smoke","status":"uncertain"}}}'
	printf '%s\n' '{"jsonrpc":"2.0","id":"3","method":"tools/call","params":{"name":"list_needs_verification","arguments":{}}}'
} >"$MCP_IN"

MCP_OUT="$(SWQ_DB="${EVID_DIR}/mcp_store.json" "$BIN" mcp-stdio <"$MCP_IN" 2>>"$LOG")"
printf '%s\n' "$MCP_OUT" | tee -a "$LOG"
printf '%s\n' "$MCP_OUT" | python3 -c '
import sys,json
lines=[l for l in sys.stdin if l.strip()]
resps=[json.loads(l) for l in lines]
assert resps[0]["result"]["protocolVersion"], "no initialize result"
assert "mcp stdio smoke" in resps[1]["result"]["content"][0]["text"], "create text missing"
assert "mcp stdio smoke" in resps[2]["result"]["content"][0]["text"], "uncertain item not surfaced by needs-verification"
print("  assert MCP initialize + create + needs-verification OK")
' | tee -a "$LOG"

log ""
log "PASS: live smoke — REST(TLS) + MCP(stdio) full lifecycle confirmed [evidence: ${LOG}]"
exit 0
