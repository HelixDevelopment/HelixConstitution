// Command llm-alias-health is the ATMOSphere multi-track auto-select
// health engine's permanent fix for the provider/alias-selection crisis
// (PWU-3 of the LLMsVerifier incorporation --
// docs/research/llmsverifier_incorporation_20260707/ANALYSIS_AND_PLAN.md,
// PART D + PART F, ATMOSphere-Android-15 repo). It is project-agnostic
// (§11.4.28(B)): every alias, path, and credential-env-var-NAME is
// supplied via a consumer-owned YAML config, never hardcoded here.
//
// For each configured alias it EXECS the LLMsVerifier claude-alias-probe
// bridge (§11.4.28(C) exec-decoupling -- this util never imports
// LLMsVerifier as a Go dependency; the bridge binary path is injected via
// config), classifies the result into the closed-set status vocabulary
// {ok, rate_limited, quota_exceeded, failed, unknown}, writes a
// per-alias evidence file (§11.4.69 ab_pass_with_evidence-style
// artefact), appends an append-only JSONL event trail (§11.4.116), and
// atomically rewrites a native-preferred-ranked health.json snapshot a
// multitrack consumer can tail.
//
// Usage:
//
//	llm-alias-health -config health_config.yaml \
//	  -health-out health.json -events-out events.jsonl \
//	  -evidence-dir qa-results/llmsverifier_pwu3/evidence
//
// Exit codes: 0 always, UNLESS the config itself is invalid or the
// output paths cannot be written (config/usage error, exit 2). A
// per-alias probe failure/rate-limit/timeout is reflected in health.json
// -- it is NOT a reason for this command itself to fail, since the whole
// point is to surface unhealthy aliases without crashing the health
// sweep itself (§11.4.85 chaos-hardening: one bad alias must never take
// down the report for every other alias).
package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"
)

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}

func run(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("llm-alias-health", flag.ContinueOnError)
	fs.SetOutput(stderr)

	configPath := fs.String("config", "", "Path to the YAML health config (required)")
	healthOut := fs.String("health-out", "health.json", "Path to write the atomically-rewritten health.json snapshot")
	eventsOut := fs.String("events-out", "events.jsonl", "Path to append the JSONL event trail")
	evidenceDir := fs.String("evidence-dir", "", "Directory to write per-alias evidence JSON files (required)")

	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *configPath == "" {
		fmt.Fprintln(stderr, "config error: -config is required")
		return 2
	}
	if *evidenceDir == "" {
		fmt.Fprintln(stderr, "config error: -evidence-dir is required")
		return 2
	}

	cfg, err := loadConfig(*configPath)
	if err != nil {
		fmt.Fprintf(stderr, "config error: %v\n", err)
		return 2
	}

	if err := os.MkdirAll(*evidenceDir, 0o755); err != nil {
		fmt.Fprintf(stderr, "config error: cannot create -evidence-dir %q: %v\n", *evidenceDir, err)
		return 2
	}

	entries := probeAllAliases(context.Background(), cfg, *evidenceDir, *eventsOut, stdout)
	rankAliases(entries)

	doc := HealthDoc{GeneratedAt: nowRFC3339(), Aliases: entries}
	if err := writeHealthAtomic(*healthOut, doc); err != nil {
		fmt.Fprintf(stderr, "error: cannot write -health-out %q: %v\n", *healthOut, err)
		return 2
	}

	fmt.Fprintf(stdout, "llm-alias-health: wrote %d alias entries to %s\n", len(entries), *healthOut)
	return 0
}

// probeAllAliases runs every configured alias SEQUENTIALLY, by design
// (§11.4.119 single-resource-owner partitioning): several aliases may
// share a native account's CLAUDE_CONFIG_DIR / the SAME local ccr
// instance a live worker is also driving, so this util never fans out
// concurrent probes against the operator's own config by default --
// concurrent-safety of the underlying exec primitive itself (against
// DIFFERENT aliases/subprocesses) is proven separately by
// probe_stress_test.go.
func probeAllAliases(ctx context.Context, cfg Config, evidenceDir, eventsPath string, stdout io.Writer) []AliasHealthEntry {
	entries := make([]AliasHealthEntry, 0, len(cfg.Aliases))

	for _, a := range cfg.Aliases {
		sentinel := cfg.SentinelPrefix + randomHex(8)
		args := argsForAlias(a, sentinel, cfg.TimeoutSeconds)

		_ = appendEvent(eventsPath, Event{Alias: a.Alias, Event: "probe_start", Detail: fmt.Sprintf("kind=%s", a.Kind)})

		timeout := time.Duration(cfg.TimeoutSeconds+10) * time.Second
		rep, execErr := runBridgeProbe(ctx, cfg.LLMsVerifierBin, args, timeout)

		status := statusFromBridge(rep, execErr)
		evidencePath := filepath.Join(evidenceDir, a.Alias+".json")

		var detail string
		if execErr != nil {
			detail = execErr.Error()
		} else {
			detail = rep.Detail
		}
		if err := writeEvidenceFile(evidencePath, a, rep, execErr, status); err != nil {
			fmt.Fprintf(stdout, "llm-alias-health: WARNING: could not write evidence for alias %q: %v\n", a.Alias, err)
		}

		if execErr != nil {
			_ = appendEvent(eventsPath, Event{Alias: a.Alias, Event: "probe_error", Status: status, Detail: detail, Evidence: evidencePath})
		} else {
			_ = appendEvent(eventsPath, Event{Alias: a.Alias, Event: "probe_result", Status: status, Detail: detail, Evidence: evidencePath})
		}

		entries = append(entries, AliasHealthEntry{
			Alias:       a.Alias,
			Kind:        string(a.Kind),
			Status:      status,
			LatencyMs:   rep.LatencyMs,
			RetryAfterS: rep.RetryAfterSeconds,
			Model:       rep.Model,
			CheckedAt:   nowRFC3339(),
			Evidence:    evidencePath,
		})
	}

	return entries
}

// randomHex returns n random bytes hex-encoded, used to build a unique
// per-run sentinel round-trip token so a stale/cached reply can never be
// mistaken for a fresh one.
func randomHex(n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		// crypto/rand failing is exceptionally rare (kernel entropy
		// source unavailable); fall back to a fixed, clearly-labelled
		// suffix rather than crashing the whole health sweep over it.
		return "fallback"
	}
	return hex.EncodeToString(b)
}
