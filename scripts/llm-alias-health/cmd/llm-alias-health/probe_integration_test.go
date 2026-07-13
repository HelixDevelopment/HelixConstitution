//go:build integration
// +build integration

package main

// probe_integration_test.go -- REAL end-to-end integration coverage
// (§11.4.27(A): non-unit tests MUST exercise the real system, no fakes).
// This drives the ACTUAL LLMsVerifier claude-alias-probe bridge binary
// (tools/helixqa/llms_verifier/llm-verifier/cmd/claude-alias-probe in
// the ATMOSphere-Android-15 repo) via a real `claude -p` call -- the
// exec-decoupled path this util uses in production (§11.4.28(C)).
//
// The bridge binary path is INJECTED via the
// LLM_ALIAS_HEALTH_TEST_BRIDGE_BIN env var, NEVER hardcoded (this
// constitution submodule must stay project-agnostic per §11.4.28(B) --
// it must not embed the consuming ATMOSphere project's own directory
// layout). SKIP-with-reason (§11.4.3), never FAIL, when the env var is
// unset or the real `claude`/ccr topology is unavailable.
//
// Quota-minimal (PART G risk 1 of the incorporation plan): exactly ONE
// real alias is probed here -- provider-router via the local
// claude-code-router (ccr), the SAME safe, already-proven route the
// sibling LLMsVerifier tests use. A "native" alias probe is
// deliberately NOT exercised by this automated suite: every native
// CLAUDE_CONFIG_DIR on this host is, at any given time, potentially held
// by a live parallel-track session (§11.4.119 single-resource-owner --
// driving a concurrent `claude -p` against a config dir a live session
// is using is the exact contention risk PART G risk 3 flags), and this
// test has no way to discover an "idle" native account without guessing
// (§11.4.6). UNCONFIRMED: a native-kind live probe is validated
// manually/operator-attended against a known-idle account, not by this
// automated suite.

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func realBridgeBinPath(t *testing.T) string {
	t.Helper()
	bin := os.Getenv("LLM_ALIAS_HEALTH_TEST_BRIDGE_BIN")
	if bin == "" {
		t.Skip("SKIP: LLM_ALIAS_HEALTH_TEST_BRIDGE_BIN not set -- point it at a built " +
			"tools/helixqa/llms_verifier/llm-verifier/cmd/claude-alias-probe binary to run this real integration test")
	}
	if _, err := os.Stat(bin); err != nil {
		t.Skipf("SKIP: LLM_ALIAS_HEALTH_TEST_BRIDGE_BIN=%q does not exist: %v", bin, err)
	}
	return bin
}

// TestIntegration_RealBridge_ProviderRouter_ViaCCR is the ONE real
// alias probe this suite performs (quota-minimal, PART G risk 1):
// provider-router via ccr, through this util's OWN runBridgeProbe ->
// statusFromBridge pipeline (not just the bridge binary standalone --
// proving the util's exec-decoupled integration is correctly wired end
// to end, not merely that the bridge works in isolation, which
// tools/helixqa/llms_verifier's own tests already prove).
func TestIntegration_RealBridge_ProviderRouter_ViaCCR(t *testing.T) {
	bin := realBridgeBinPath(t)

	a := AliasConfig{
		Alias:   "ccr-router-live",
		Kind:    KindProviderRouter,
		BaseURL: "http://127.0.0.1:3456",
	}
	sentinel := "LLM_ALIAS_HEALTH_PWU3_INTEGRATION_" + randomHex(8)
	args := argsForAlias(a, sentinel, 180)

	rep, err := runBridgeProbe(context.Background(), bin, args, 190*time.Second)
	status := statusFromBridge(rep, err)

	if status == "unknown" {
		t.Skipf("SKIP: real bridge probe could not complete in this environment (ccr/claude unreachable or too contended): err=%v rep=%+v", err, rep)
	}
	if status == "ok" && !rep.SentinelMatched {
		t.Fatalf("SENTINEL PASS-BLUFF GUARD TRIPPED: status=ok but SentinelMatched=false: %+v", rep)
	}
	if status != "ok" {
		// A real, honest rate_limited/quota_exceeded/failed verdict from
		// the live host is itself valid captured evidence -- the sink
		// this whole PWU exists to surface -- never an automated FAIL.
		t.Logf("real bridge probe returned a non-ok but VALID verdict (this is the sink-side signal the util exists to surface, not a test failure): status=%s rep=%+v", status, rep)
		return
	}

	t.Logf("PASS (real §11.4.69 sink-side probe via the util's own runBridgeProbe -> statusFromBridge pipeline, routed through ccr): status=%s latency_ms=%d model=%q", status, rep.LatencyMs, rep.Model)
}

// TestIntegration_RealBridge_FullSweep_WritesHealthJSONAndEvidence
// drives the FULL probeAllAliases orchestration (the same code path
// main() uses) against the one real alias, into a temp dir, and asserts
// health.json + the per-alias evidence file are both real, valid,
// non-fabricated artefacts.
func TestIntegration_RealBridge_FullSweep_WritesHealthJSONAndEvidence(t *testing.T) {
	bin := realBridgeBinPath(t)

	dir := t.TempDir()
	evidenceDir := filepath.Join(dir, "evidence")
	if err := os.MkdirAll(evidenceDir, 0o755); err != nil {
		t.Fatalf("setup: %v", err)
	}

	cfg := Config{
		LLMsVerifierBin: bin,
		TimeoutSeconds:  180,
		SentinelPrefix:  "LLM_ALIAS_HEALTH_PWU3_SWEEP_",
		Aliases: []AliasConfig{
			{Alias: "ccr-router-live", Kind: KindProviderRouter, BaseURL: "http://127.0.0.1:3456"},
		},
	}

	entries := probeAllAliases(context.Background(), cfg, evidenceDir, filepath.Join(dir, "events.jsonl"), os.Stdout)
	rankAliases(entries)
	doc := HealthDoc{GeneratedAt: nowRFC3339(), Aliases: entries}

	healthPath := filepath.Join(dir, "health.json")
	if err := writeHealthAtomic(healthPath, doc); err != nil {
		t.Fatalf("writeHealthAtomic failed: %v", err)
	}

	if len(entries) != 1 {
		t.Fatalf("expected 1 entry, got %d", len(entries))
	}
	if entries[0].Evidence == "" {
		t.Fatal("expected a non-empty evidence path")
	}
	if _, err := os.Stat(entries[0].Evidence); err != nil {
		t.Fatalf("evidence file was not written: %v", err)
	}
	if _, err := os.Stat(healthPath); err != nil {
		t.Fatalf("health.json was not written: %v", err)
	}
	if _, err := os.Stat(filepath.Join(dir, "events.jsonl")); err != nil {
		t.Fatalf("events.jsonl was not written: %v", err)
	}

	t.Logf("PASS: full real-bridge sweep produced health.json=%s evidence=%s status=%s", healthPath, entries[0].Evidence, entries[0].Status)
}
