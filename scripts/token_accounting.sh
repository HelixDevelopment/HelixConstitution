#!/usr/bin/env bash
# token_accounting.sh — Helix Universal §11.4.141 token-efficiency measurement harness.
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# The §11.4.141 anti-bluff measurement engine. Reads the AUTHORITATIVE Anthropic
# `usage` object (input_tokens / cache_read_input_tokens /
# cache_creation_input_tokens / output_tokens) from a session/transcript,
# recomputes cost from the RAW token fields with the published price table
# (NEVER tiktoken, NEVER the client-side `total_cost_usd` estimate), aggregates
# per development-cycle, and emits a BEFORE/AFTER JSON + a PASS/WARN/FAIL verdict.
#
# Pass criterion (§11.4.141 / MEASUREMENT §5):
#   reduction = 1 - (AFTER_cost / BEFORE_cost)
#   PASS  if  AFTER_cost <= 0.40 * BEFORE_cost        (>= 60% reduction — target)
#   WARN  if  0.40*BEFORE < AFTER <= 0.55*BEFORE  AND  --cold-cache-reason given
#   FAIL  otherwise
# The reported number is ALWAYS the MEASURED reduction, never the design estimate
# (§11.4.6 no-guessing).
#
# ── Where the usage data comes from, per agent (documented per §11.4.6) ───────
#   * Claude Code         : `claude -p ... --output-format json` emits a result
#                           object whose `usage` field carries input_tokens,
#                           cache_read_input_tokens, cache_creation_input_tokens
#                           (split 5m/1h via cache_creation.ephemeral_*),
#                           output_tokens. We recompute cost from those raw
#                           fields — we DO NOT trust the `total_cost_usd` estimate
#                           the same object also carries (it is a client-side
#                           estimate; cost-tracking docs flag it as such).
#                           Ref: https://code.claude.com/docs/en/agent-sdk/cost-tracking
#   * Anthropic-SDK driver: every Messages API response carries a `usage` object
#                           with the same four fields. The driver writes one
#                           usage-line per request to a JSONL transcript; this
#                           harness reads that transcript.
#   * Gemini CLI / Qwen   : their usage/cache-hit telemetry maps onto the same
#                           four-field shape (with the provider's own price
#                           table supplied via --price-* flags); if the agent is
#                           not configured the harness SKIPs that source per
#                           §11.4.3 (never a fake PASS).
#
# A transcript is a JSONL or JSON file. Two accepted shapes (auto-detected):
#   (a) JSONL  — one JSON object per line; each carries a `usage` object
#                (Anthropic API style) OR a top-level result with `.usage`
#                (Claude Code `--output-format stream-json` style).
#   (b) JSON   — a single Claude Code `--output-format json` result object
#                with a `.usage` field, OR an array of such objects.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   # Aggregate one transcript into a cycle report:
#   token_accounting.sh aggregate --transcript <file> --model <id> \
#       [--out <cycle_report.json>] [--label before|after]
#
#   # Compute the BEFORE/AFTER verdict from two cycle reports:
#   token_accounting.sh verdict --before <before.json> --after <after.json> \
#       [--out <verdict.json>] [--cold-cache-reason "<reason>"]
#
#   # Print the supported model price table:
#   token_accounting.sh prices
#
#   # Override / extend prices for a non-default model (USD per 1M tokens):
#   token_accounting.sh aggregate ... --price-in 5 --price-out 25
#
# ── Inputs ───────────────────────────────────────────────────────────────────
#   --transcript <file>  JSONL/JSON transcript with `usage` objects.
#   --model <id>         model id (resolves a row in the built-in price table,
#                        or supply --price-in/--price-out).
#   --before/--after     two cycle_report.json files for the `verdict` subcommand.
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   aggregate → cycle_report.json (the §11.4.69 captured-evidence artefact):
#     { model, label, requests, sum_input_tokens, sum_cache_read_input_tokens,
#       sum_cache_creation_input_tokens_5m, sum_cache_creation_input_tokens_1h,
#       sum_output_tokens, cost_usd, cache_read_ratio, warm_cache } + stderr summary.
#   verdict  → verdict.json + a one-line PASS/WARN/FAIL on stdout:
#     { before_cost_usd, after_cost_usd, reduction, target_met, verdict,
#       warm_cache_after, cold_cache_reason }.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Writes the requested --out file (default: stdout only). No device mutation,
#   no network, no commit. Reads the transcript read-only.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   jq (authoritative token-field extraction + cost recompute). Bash 4+.
#   Parses clean under bash -n AND sh -n (§11.4.67).
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.141 (token-efficiency mandate), §11.4.6 (measured-not-asserted),
#   §11.4.69 (captured-evidence taxonomy — feature class token_efficiency),
#   §11.4.50 (deterministic — same transcript ⇒ identical splits + verdict),
#   §11.4.5 (captured-evidence quality), §1.1 (paired mutation — the ratio check),
#   §11.4.18 (this doc block + docs/scripts companion), §11.4.67 (parse-clean).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   aggregate: 0 ok, 2 env/usage error (no usage objects found / jq missing).
#   verdict  : 0 PASS, 3 WARN (cold-cache floor met w/ reason), 1 FAIL, 2 env.
#   prices   : 0.
#
# Classification: universal (§11.4.17) — the consuming project supplies its own
# model ids / prices / transcripts. NO project-specific data here.

set -uo pipefail

# ── Built-in price table (USD per 1,000,000 tokens) ──────────────────────────
# Source: claude-api skill shared/models.md. Input price = Pin, output = Pout.
# Cache-read multiplier 0.1x; cache-write 1.25x (5m TTL) / 2.0x (1h TTL) — these
# multiply Pin and are applied in the cost formula below, not in this table.
_price_in_for_model() {
    case "$1" in
        *opus*)   echo "5"  ;;   # Opus 4.x : $5 / 1M in
        *sonnet*) echo "3"  ;;   # Sonnet 4.x: $3 / 1M in
        *haiku*)  echo "1"  ;;   # Haiku 4.x : $1 / 1M in
        *)        echo ""   ;;   # unknown — caller must pass --price-in
    esac
}
_price_out_for_model() {
    case "$1" in
        *opus*)   echo "25" ;;   # Opus 4.x : $25 / 1M out
        *sonnet*) echo "15" ;;   # Sonnet 4.x: $15 / 1M out
        *haiku*)  echo "5"  ;;   # Haiku 4.x : $5 / 1M out
        *)        echo ""   ;;
    esac
}

_die() { echo "token_accounting: $*" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || _die "jq is required (authoritative token extraction; tiktoken is forbidden per §11.4.141)."

# jq program: from ANY accepted transcript shape, emit one normalised usage
# object per request as a JSON stream. Handles:
#   - a bare Anthropic `usage` object,                       (.usage present at top)
#   - a Claude Code result object carrying `.usage`,
#   - the same nested under `.result.usage`,
#   - an array of any of the above.
# Cache-creation split: Anthropic exposes either a flat
# `cache_creation_input_tokens` (assumed 5m unless `cache_creation.ephemeral_1h_input_tokens`
# is present) OR the detailed `cache_creation` object. We read both honestly.
_JQ_NORMALISE='
def usageobj:
  if has("usage") then .usage
  elif (has("result") and (.result|type=="object") and (.result|has("usage"))) then .result.usage
  elif (has("input_tokens") or has("output_tokens") or has("cache_read_input_tokens")) then .
  else null end;
def split5m1h(u):
  ( (u.cache_creation // {}) ) as $cc
  | { five:  ( $cc.ephemeral_5m_input_tokens
               // ( if ($cc|type=="object") and ($cc.ephemeral_1h_input_tokens != null)
                    then 0
                    else (u.cache_creation_input_tokens // 0) end ) ),
      one_h: ( $cc.ephemeral_1h_input_tokens // 0 ) };
( if type=="array" then .[] else . end )
| usageobj as $u
| select($u != null)
| split5m1h($u) as $s
| {
    input:        ($u.input_tokens // 0),
    cache_read:   ($u.cache_read_input_tokens // 0),
    cache_5m:     ($s.five),
    cache_1h:     ($s.one_h),
    output:       ($u.output_tokens // 0)
  }
'

_normalise_transcript() {
    # Stream-tolerant: feed the file through jq with -c on a slurp-or-stream basis.
    # JSONL (one object per line) and a single JSON value both work with `jq -c`.
    jq -c "$_JQ_NORMALISE" "$1" 2>/dev/null
}

_subcmd_aggregate() {
    local transcript="" model="" out="" label="" pin="" pout=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --transcript) transcript="$2"; shift 2 ;;
            --model)      model="$2";      shift 2 ;;
            --out)        out="$2";        shift 2 ;;
            --label)      label="$2";      shift 2 ;;
            --price-in)   pin="$2";        shift 2 ;;
            --price-out)  pout="$2";       shift 2 ;;
            *) _die "aggregate: unknown arg '$1'" ;;
        esac
    done
    [ -n "$transcript" ] || _die "aggregate: --transcript required"
    [ -f "$transcript" ] || _die "aggregate: transcript not found: $transcript"
    [ -n "$model" ] || _die "aggregate: --model required"
    [ -z "$pin" ]  && pin="$(_price_in_for_model "$model")"
    [ -z "$pout" ] && pout="$(_price_out_for_model "$model")"
    [ -n "$pin" ]  || _die "aggregate: unknown model '$model' — supply --price-in"
    [ -n "$pout" ] || _die "aggregate: unknown model '$model' — supply --price-out"

    local normalised
    normalised="$(_normalise_transcript "$transcript")"
    if [ -z "${normalised//[$' \t\r\n']/}" ]; then
        _die "aggregate: no usage objects found in transcript '$transcript' (refusing to emit a zero-cost report — that would be a §11.4.1 FAIL-bluff)."
    fi

    # Sum the five fields, then recompute cost per §11.4.141 formula:
    #   cost = Pin*(input + 0.1*cache_read + 1.25*cache_5m + 2.0*cache_1h) + Pout*output
    # (token counts in tokens; prices in USD/1e6 tokens.)
    local report
    report="$(printf '%s\n' "$normalised" | jq -s \
        --arg model "$model" --arg label "${label:-}" \
        --argjson pin "$pin" --argjson pout "$pout" '
        ( reduce .[] as $r ({i:0,cr:0,c5:0,c1:0,o:0,n:0};
            { i:  (.i  + $r.input),
              cr: (.cr + $r.cache_read),
              c5: (.c5 + $r.cache_5m),
              c1: (.c1 + $r.cache_1h),
              o:  (.o  + $r.output),
              n:  (.n  + 1) }) ) as $s
        | ( ($pin/1000000) * ($s.i + 0.1*$s.cr + 1.25*$s.c5 + 2.0*$s.c1)
            + ($pout/1000000) * $s.o ) as $cost
        | ( if ($s.i + $s.cr) > 0 then ($s.cr / ($s.i + $s.cr)) else 0 end ) as $ratio
        | {
            model: $model,
            label: $label,
            requests: $s.n,
            price_in_per_1m: $pin,
            price_out_per_1m: $pout,
            sum_input_tokens: $s.i,
            sum_cache_read_input_tokens: $s.cr,
            sum_cache_creation_input_tokens_5m: $s.c5,
            sum_cache_creation_input_tokens_1h: $s.c1,
            sum_output_tokens: $s.o,
            cost_usd: $cost,
            cache_read_ratio: $ratio,
            warm_cache: ($s.cr > 0)
          }
    ')"

    if [ -n "$out" ]; then printf '%s\n' "$report" > "$out"; fi
    printf '%s\n' "$report"

    # Short human summary to stderr (does not pollute the JSON stdout).
    echo "token_accounting[aggregate] model=$model label=${label:-none} requests=$(printf '%s' "$report" | jq -r '.requests') cost_usd=$(printf '%s' "$report" | jq -r '.cost_usd') cache_read_ratio=$(printf '%s' "$report" | jq -r '.cache_read_ratio') warm_cache=$(printf '%s' "$report" | jq -r '.warm_cache')" >&2
}

_subcmd_verdict() {
    local before="" after="" out="" cold_reason=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --before) before="$2"; shift 2 ;;
            --after)  after="$2";  shift 2 ;;
            --out)    out="$2";    shift 2 ;;
            --cold-cache-reason) cold_reason="$2"; shift 2 ;;
            *) _die "verdict: unknown arg '$1'" ;;
        esac
    done
    [ -f "$before" ] || _die "verdict: --before report not found: $before"
    [ -f "$after" ]  || _die "verdict: --after report not found: $after"

    local before_cost after_cost warm_after
    before_cost="$(jq -r '.cost_usd' "$before")"
    after_cost="$(jq -r '.cost_usd' "$after")"
    warm_after="$(jq -r '.warm_cache' "$after")"

    if ! jq -e '.cost_usd > 0' "$before" >/dev/null 2>&1; then
        _die "verdict: BEFORE cost is not positive — a zero/empty BEFORE makes the reduction undefined (§11.4.1 FAIL-bluff guard)."
    fi

    local verdict_json
    verdict_json="$(jq -n \
        --argjson bc "$before_cost" --argjson ac "$after_cost" \
        --arg warm "$warm_after" --arg cold "$cold_reason" '
        ( 1 - ($ac / $bc) ) as $red
        | {
            before_cost_usd: $bc,
            after_cost_usd: $ac,
            reduction: $red,
            target_met: ($ac <= 0.40 * $bc),
            warm_cache_after: ($warm == "true"),
            cold_cache_reason: $cold,
            verdict:
              ( if   $ac <= 0.40 * $bc then "PASS"
                elif ($ac <= 0.55 * $bc) and ($cold != "") then "WARN"
                else "FAIL" end )
          }
    ')"

    if [ -n "$out" ]; then printf '%s\n' "$verdict_json" > "$out"; fi
    printf '%s\n' "$verdict_json"

    local v; v="$(printf '%s' "$verdict_json" | jq -r '.verdict')"
    local red; red="$(printf '%s' "$verdict_json" | jq -r '.reduction')"
    echo "token_accounting[verdict] ${v}: measured reduction=${red} (before=${before_cost} after=${after_cost} warm_cache_after=${warm_after})" >&2
    case "$v" in
        PASS) return 0 ;;
        WARN) return 3 ;;
        *)    return 1 ;;
    esac
}

_subcmd_prices() {
    cat <<'EOF'
Helix §11.4.141 price table (USD per 1,000,000 tokens; source: claude-api shared/models.md)
  model-substring   Pin   Pout
  *opus*            5     25
  *sonnet*          3     15
  *haiku*           1     5
Cache multipliers (applied to Pin in the cost formula, not this table):
  cache_read_input_tokens          0.1x
  cache_creation_input_tokens 5m   1.25x
  cache_creation_input_tokens 1h   2.0x
Cost formula:
  cost = Pin/1e6 * (input + 0.1*cache_read + 1.25*cache_5m + 2.0*cache_1h)
       + Pout/1e6 * output
EOF
}

main() {
    local sub="${1:-}"; [ $# -gt 0 ] && shift || true
    case "$sub" in
        aggregate) _subcmd_aggregate "$@" ;;
        verdict)   _subcmd_verdict "$@" ;;
        prices)    _subcmd_prices ;;
        ""|-h|--help)
            sed -n '1,80p' "$0" | sed 's/^# \{0,1\}//'
            ;;
        *) _die "unknown subcommand '$sub' (use: aggregate | verdict | prices)" ;;
    esac
}

main "$@"
