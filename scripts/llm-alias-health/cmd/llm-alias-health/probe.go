package main

// probe.go -- the exec-decoupled bridge invocation (§11.4.28(C)). This
// util NEVER imports the LLMsVerifier module; it execs the injected
// llmsverifier_bin (the claude-alias-probe bridge, PWU-3's own
// tools/helixqa/llms_verifier/llm-verifier/cmd/claude-alias-probe) and
// parses its JSON stdout contract. Anti-bluff / chaos-hardened
// (§11.4.69/§11.4.85): a missing binary, a killed subprocess, a timeout,
// or corrupted/non-JSON stdout ALL degrade to an explicit error --
// NEVER a fabricated "ok" verdict.

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"strconv"
	"time"
)

// BridgeReport mirrors the claude-alias-probe bridge's JSON output shape
// (tools/helixqa/llms_verifier/llm-verifier/cmd/claude-alias-probe/main.go's
// probeReport). Kept as a plain local struct (not imported) per the
// exec-decoupling constraint -- the two definitions are independently
// maintained but MUST stay wire-compatible; the paired mutation
// (probe_mutation_test.go) proves a schema drift is caught, not silently
// swallowed.
type BridgeReport struct {
	Verdict           string `json:"verdict"`
	RetryAfterSeconds int    `json:"retry_after_seconds,omitempty"`
	Detail            string `json:"detail,omitempty"`
	LatencyMs         int64  `json:"latency_ms"`
	Model             string `json:"model"`
	SentinelMatched   bool   `json:"sentinel_matched"`
	Observed          string `json:"observed,omitempty"`
}

// validVerdicts is the closed set of verdict strings the bridge may
// legitimately report. Anything else is treated as an unparseable
// payload (degrades to "unknown", never trusted as-is).
var validVerdicts = map[string]bool{
	"ok":             true,
	"rate_limited":   true,
	"quota_exceeded": true,
	"failed":         true,
}

// argsForAlias builds the claude-alias-probe CLI argument vector for one
// alias. The sentinel is caller-supplied (per-run, unique) so a stale
// cached reply from a previous probe can never be mistaken for a fresh
// one.
func argsForAlias(a AliasConfig, sentinel string, timeoutSeconds int) []string {
	args := []string{
		"--kind", string(a.Kind),
		"--sentinel", sentinel,
		"--timeout", strconv.Itoa(timeoutSeconds),
	}
	if a.Model != "" {
		args = append(args, "--model", a.Model)
	}
	switch a.Kind {
	case KindNative:
		args = append(args, "--config-dir", a.ConfigDir)
	case KindProviderNative:
		args = append(args, "--base-url", a.BaseURL, "--auth-token-env", a.AuthTokenEnv)
	case KindProviderRouter:
		args = append(args, "--base-url", a.BaseURL)
		if a.APIKeyEnv != "" {
			args = append(args, "--api-key-env", a.APIKeyEnv)
		}
	}
	return args
}

// runBridgeProbe execs bin with args and returns the parsed
// BridgeReport. It is single-owner-safe for concurrent callers targeting
// DIFFERENT aliases (§11.4.119 -- each invocation is an independent
// subprocess with no shared mutable state); callers targeting the SAME
// native account's CLAUDE_CONFIG_DIR concurrently are the caller's
// responsibility to serialize (this function does not itself serialize
// -- see health.go's sequential-by-default alias loop).
//
// Anti-bluff / chaos contract (§11.4.69/§11.4.85): the JSON payload on
// stdout is authoritative REGARDLESS of the process exit code (the
// bridge's own exit-code convention encodes verdict==failed/rate_limited
// /quota_exceeded as non-zero exits that STILL carry a valid, parseable
// report) -- so a non-zero exit with valid JSON is expected, not an
// error. Only a genuinely unparseable/absent payload (crash, hang past
// timeout, corrupted stdout, missing binary) is surfaced as a Go error,
// and this function NEVER fabricates an "ok" BridgeReport in that case.
func runBridgeProbe(ctx context.Context, bin string, args []string, timeout time.Duration) (BridgeReport, error) {
	cctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	cmd := exec.CommandContext(cctx, bin, args...)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	runErr := cmd.Run()

	trimmed := bytes.TrimSpace(stdout.Bytes())
	if len(trimmed) > 0 {
		var rep BridgeReport
		if parseErr := json.Unmarshal(trimmed, &rep); parseErr == nil && validVerdicts[rep.Verdict] {
			return rep, nil // authoritative regardless of process exit code
		}
	}

	detail := stderr.String()
	if detail == "" {
		detail = stdout.String()
	}
	if cctx.Err() == context.DeadlineExceeded {
		return BridgeReport{}, fmt.Errorf("bridge probe timed out after %v", timeout)
	}
	if runErr != nil {
		return BridgeReport{}, fmt.Errorf("bridge exec failed: %w (output: %s)", runErr, firstNChars(detail, 300))
	}
	return BridgeReport{}, fmt.Errorf("bridge produced no parseable verdict (output: %s)", firstNChars(detail, 300))
}

// firstNChars returns the first n runes of s (UTF-8 aware).
func firstNChars(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return string(r[:n])
}
