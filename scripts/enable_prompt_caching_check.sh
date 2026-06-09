#!/usr/bin/env bash
# enable_prompt_caching_check.sh — §11.4.141 Measure M1 warm-cache confirmation helper.
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Confirms the governance-prefix prompt cache (Measure M1 of §11.4.141) is WARM —
# i.e. `cache_read_input_tokens > 0` on the governance-bearing turns of a
# transcript — and reports the cache-read ratio. A warm cache is the captured
# evidence that M1 engaged; a collapsed (~0) cache-read is the signature of a
# silent invalidator (a per-turn timestamp/UUID/unsorted-JSON ahead of the cache
# breakpoint) and FAILs this check. This is the human-runnable confirmation step
# referenced by enable_prompt_caching.md; it is also the building block for the
# §1.1 paired mutation (inject a pre-breakpoint volatile → this check FAILs).
#
# This helper is a thin, transparent wrapper over `token_accounting.sh aggregate`
# (the authoritative Anthropic `usage`-object reader) — it adds the warm/ratio
# verdict on top of the cost aggregation. It NEVER trusts tiktoken or the
# client-side `total_cost_usd` (§11.4.141).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   enable_prompt_caching_check.sh --transcript <file> [--model <id>] \
#       [--min-ratio <0..1>] [--quiet]
#
# ── Inputs ───────────────────────────────────────────────────────────────────
#   --transcript <file>  JSONL/JSON with `usage` objects (Anthropic or Claude
#                        Code `--output-format json` shape — see token_accounting.sh).
#   --model <id>         model id (default: claude-opus-4-8; only used so the
#                        aggregator can resolve a price row — cost is incidental
#                        here, the warm/ratio fields are what matter).
#   --min-ratio <r>      minimum acceptable cache_read_ratio (default: 0 — any
#                        positive cache-read counts as warm; raise for stricter
#                        steady-state checks, e.g. 0.5).
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   A JSON line { warm_cache, cache_read_ratio, sum_cache_read_input_tokens,
#                 sum_input_tokens, min_ratio, verdict } on stdout + a human
#                 summary on stderr.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None (read-only; no device mutation, no network, no commit).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   token_accounting.sh (same dir), jq. Parses clean under bash -n AND sh -n.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.141 (M1 — prompt-cache the governance prefix), §11.4.6 (measured proof),
#   §11.4.69 (captured-evidence — token_efficiency), §1.1 (silent-invalidator
#   paired mutation flips this to FAIL), §11.4.67 (parse-clean).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — WARM (cache_read_ratio >= min-ratio AND cache_read > 0).
#   1 — COLD (cache collapsed / below min-ratio) — silent-invalidator suspected.
#   2 — env error (token_accounting.sh / jq missing, transcript not found, no usage).
#
# Classification: universal (§11.4.17) — no project-specific data.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
TOKACC="${SCRIPT_DIR}/token_accounting.sh"

_die() { echo "enable_prompt_caching_check: $*" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || _die "jq is required."
[ -x "$TOKACC" ] || [ -f "$TOKACC" ] || _die "token_accounting.sh not found at $TOKACC"

transcript="" model="claude-opus-4-8" min_ratio="0" quiet=""
while [ $# -gt 0 ]; do
    case "$1" in
        --transcript) transcript="$2"; shift 2 ;;
        --model)      model="$2";      shift 2 ;;
        --min-ratio)  min_ratio="$2";  shift 2 ;;
        --quiet)      quiet="1";        shift ;;
        -h|--help)    sed -n '1,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) _die "unknown arg '$1'" ;;
    esac
done
[ -n "$transcript" ] || _die "--transcript required"
[ -f "$transcript" ] || _die "transcript not found: $transcript"

# Delegate to the authoritative aggregator; capture its JSON report.
report="$(bash "$TOKACC" aggregate --transcript "$transcript" --model "$model" 2>/dev/null)" \
    || _die "token_accounting.sh aggregate failed (no usage objects in transcript? — that is itself a §11.4.1 FAIL-bluff, not a cold cache)."

[ -n "${report//[$' \t\r\n']/}" ] || _die "empty report from aggregator."

result="$(printf '%s' "$report" | jq -c \
    --argjson minr "$min_ratio" '
    {
        warm_cache: .warm_cache,
        cache_read_ratio: .cache_read_ratio,
        sum_cache_read_input_tokens: .sum_cache_read_input_tokens,
        sum_input_tokens: .sum_input_tokens,
        min_ratio: $minr,
        verdict: ( if (.warm_cache and (.cache_read_ratio >= $minr)) then "WARM" else "COLD" end )
    }')"

printf '%s\n' "$result"
verdict="$(printf '%s' "$result" | jq -r '.verdict')"
ratio="$(printf '%s' "$result" | jq -r '.cache_read_ratio')"
if [ -z "$quiet" ]; then
    echo "enable_prompt_caching_check: ${verdict} (cache_read_ratio=${ratio}, min=${min_ratio}) — ${transcript}" >&2
fi
[ "$verdict" = "WARM" ] && exit 0 || exit 1
