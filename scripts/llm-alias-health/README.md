# llm-alias-health

**Revision:** 1
**Last modified:** 2026-07-07T00:00:00Z

PWU-3 of the LLMsVerifier incorporation (see
`docs/research/llmsverifier_incorporation_20260707/ANALYSIS_AND_PLAN.md`,
PART D + PART F, in the ATMOSphere-Android-15 consuming repo) — the
permanent, project-agnostic auto-select **health engine** for
Claude-Code-CLI aliases (native accounts, provider-router routes via
`ccr`, and provider-native routes), replacing the previous *reactive*
cooldown-only rotation with a *proactive* out-of-band health probe.

## What it does

For every alias in a YAML config, `llm-alias-health`:

1. **Execs** the LLMsVerifier `claude-alias-probe` bridge binary
   (§11.4.28(C) exec-decoupling — this util never imports LLMsVerifier
   as a Go dependency; the bridge path is injected via
   `llmsverifier_bin` in the config, never hardcoded).
2. Classifies the result into the closed-set status vocabulary
   `{ok, rate_limited, quota_exceeded, failed, unknown}` — `unknown`
   is reserved for cases where the bridge itself could not be run or
   its output could not be parsed (missing binary, crash, timeout,
   corrupted stdout); it is **never** conflated with a genuine `ok`.
3. Writes one evidence JSON file per alias (`ab_pass_with_evidence`
   style artefact, §11.4.69) plus an append-only `events.jsonl`
   real-time event trail (§11.4.116).
4. Atomically rewrites a native-preferred-ranked `health.json`
   snapshot a multitrack consumer can tail.

## Config schema

```yaml
llmsverifier_bin: /path/to/claude-alias-probe   # required
timeout_seconds: 60                              # optional, default 60
sentinel_prefix: "LLM_ALIAS_HEALTH_"             # optional
aliases:
  - alias: claude1
    kind: native                # native | provider-native | provider-router
    config_dir: /home/user/.claude-claude1
    model: claude-opus-4-8      # optional
  - alias: zai-glm-router
    kind: provider-router
    base_url: http://127.0.0.1:3456
  - alias: some-provider
    kind: provider-native
    base_url: https://api.example.com
    auth_token_env: SOME_PROVIDER_TOKEN   # NAME of the env var holding the secret
```

## Usage

```bash
go build -o bin/llm-alias-health ./cmd/llm-alias-health
./bin/llm-alias-health \
  -config health_config.yaml \
  -health-out health.json \
  -events-out events.jsonl \
  -evidence-dir qa-results/llmsverifier_pwu3/evidence
```

Exit code `2` on config/usage error; otherwise `0` (a per-alias probe
failure is reflected *in* `health.json`, it is never a reason for the
whole sweep to fail).

## Testing

`go test -p 2 ./...` — unit (config parse, status mapping, ranking,
atomic write) + a full-sweep end-to-end run against a controllable stub
bridge (`testdata/stubbridge`) + stress (100-iteration latency
percentiles, 10-way concurrency) + chaos (corrupted/empty/missing-binary
/hung-subprocess/unwritable-evidence-dir/pre-corrupted-events-file — all
degrade honestly, never a fabricated `ok`).

`go test -p 2 -tags integration ./...` drives the **real** LLMsVerifier
bridge via `LLM_ALIAS_HEALTH_TEST_BRIDGE_BIN=<built-binary-path>` (one
real `claude -p` call via `ccr`, quota-minimal).

## Status

Go code + full test suite (unit/stress/chaos/integration) complete.
Four-format doc export (HTML/PDF/DOCX per §11.4.65/§11.4.73) and
wiring into the shared `meta_test_false_positive_proof.sh` paired-
mutation harness are tracked as PWU-6 follow-up per the incorporation
plan's own phasing, not part of this PWU's Go-code deliverable.
