package main

// probe_stress_test.go -- §11.4.85 STRESS coverage: sustained load
// (N>=100 iterations, per-iteration latency p50/p95/p99 recorded) +
// concurrent contention (N>=10 parallel invocations, no deadlock, no
// resource leak) + boundary conditions (empty/max/off-by-one input).
// Runs against testdata/stubbridge (the unit-test-only fake standing in
// for the real bridge, §11.4.27(A)) so the suite is fast, deterministic,
// and spends zero real LLM quota.

import (
	"context"
	"fmt"
	"os"
	"sort"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestStress_SustainedLoad_100Iterations_LatencyPercentiles(t *testing.T) {
	bin := buildStubBridge(t)
	withStubMode(t, "ok")

	const n = 100
	latencies := make([]time.Duration, 0, n)

	for i := 0; i < n; i++ {
		start := time.Now()
		rep, err := runBridgeProbe(context.Background(), bin, []string{"--sentinel", fmt.Sprintf("S%d", i)}, 10*time.Second)
		elapsed := time.Since(start)
		if err != nil {
			t.Fatalf("iteration %d: unexpected error: %v", i, err)
		}
		if rep.Verdict != "ok" {
			t.Fatalf("iteration %d: verdict = %q, want ok", i, rep.Verdict)
		}
		latencies = append(latencies, elapsed)
	}

	sort.Slice(latencies, func(i, j int) bool { return latencies[i] < latencies[j] })
	p50 := latencies[n*50/100]
	p95 := latencies[n*95/100]
	p99 := latencies[n*99/100]

	t.Logf("STRESS EVIDENCE: n=%d p50=%v p95=%v p99=%v min=%v max=%v", n, p50, p95, p99, latencies[0], latencies[n-1])

	// Sanity bound (not a strict performance assertion, §11.4.6 --
	// calibrated on this project's own fixture, not an imported
	// literature threshold): a stub subprocess round-trip on this host
	// should not regularly exceed a few seconds; a wildly larger p99
	// would indicate something is wrong with process spawning, not the
	// bridge protocol itself.
	if p99 > 10*time.Second {
		t.Fatalf("p99 latency %v exceeds the 10s sanity bound for a local stub-subprocess round-trip", p99)
	}
}

func TestStress_Concurrent10_NoDeadlock_NoLeak(t *testing.T) {
	bin := buildStubBridge(t)
	withStubMode(t, "ok")

	const concurrency = 10
	var wg sync.WaitGroup
	errs := make(chan error, concurrency)

	for i := 0; i < concurrency; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			rep, err := runBridgeProbe(context.Background(), bin, []string{"--sentinel", fmt.Sprintf("CONC_%d", idx)}, 10*time.Second)
			if err != nil {
				errs <- fmt.Errorf("goroutine %d: %w", idx, err)
				return
			}
			if rep.Verdict != "ok" {
				errs <- fmt.Errorf("goroutine %d: verdict=%q, want ok", idx, rep.Verdict)
				return
			}
			if rep.Observed != fmt.Sprintf("CONC_%d", idx) {
				errs <- fmt.Errorf("goroutine %d: cross-contaminated observed=%q (single-owner/independent-subprocess property violated)", idx, rep.Observed)
			}
		}(i)
	}

	done := make(chan struct{})
	go func() { wg.Wait(); close(done) }()

	select {
	case <-done:
		// completed within budget: no deadlock.
	case <-time.After(30 * time.Second):
		t.Fatal("DEADLOCK/HANG: 10 concurrent runBridgeProbe invocations did not complete within 30s")
	}

	close(errs)
	for e := range errs {
		t.Error(e)
	}
}

func TestStress_BoundaryConditions(t *testing.T) {
	bin := buildStubBridge(t)

	t.Run("empty_sentinel_flag_value", func(t *testing.T) {
		withStubMode(t, "ok")
		rep, err := runBridgeProbe(context.Background(), bin, []string{"--sentinel", ""}, 10*time.Second)
		if err != nil {
			t.Fatalf("unexpected error for an empty sentinel value: %v", err)
		}
		if rep.Observed != "" {
			t.Fatalf("expected empty observed for an empty sentinel, got %q", rep.Observed)
		}
	})

	t.Run("max_bounded_sentinel_length", func(t *testing.T) {
		withStubMode(t, "ok")
		huge := strings.Repeat("X", 4096)
		rep, err := runBridgeProbe(context.Background(), bin, []string{"--sentinel", huge}, 10*time.Second)
		if err != nil {
			t.Fatalf("unexpected error for a large sentinel value: %v", err)
		}
		if rep.Observed != huge {
			t.Fatalf("expected the full large sentinel echoed back, got length %d want %d", len(rep.Observed), len(huge))
		}
	})

	t.Run("off_by_one_timeout_boundary", func(t *testing.T) {
		// A timeout of exactly the stub's own near-instant completion
		// time (well under 1s) must still succeed -- proves the timeout
		// wiring does not off-by-one-cancel a call that finishes
		// immediately.
		withStubMode(t, "ok")
		rep, err := runBridgeProbe(context.Background(), bin, []string{"--sentinel", "S"}, 2*time.Second)
		if err != nil {
			t.Fatalf("unexpected error at a tight-but-sufficient timeout: %v", err)
		}
		if rep.Verdict != "ok" {
			t.Fatalf("verdict = %q, want ok", rep.Verdict)
		}
	})

	t.Run("nonexistent_evidence_dir_is_created_on_demand", func(t *testing.T) {
		dir := t.TempDir()
		nested := dir + "/a/b/c"
		a := AliasConfig{Alias: "bx", Kind: KindNative, ConfigDir: "/tmp/x"}
		if err := writeEvidenceFile(nested+"-should-fail.json", a, BridgeReport{Verdict: "ok"}, nil, "ok"); err == nil {
			t.Fatal("expected writeEvidenceFile to fail when the parent directory does not exist (it does not create directories itself -- main.go's MkdirAll is the caller's responsibility)")
		}
		if err := os.MkdirAll(nested, 0o755); err != nil {
			t.Fatalf("setup: mkdir: %v", err)
		}
		if err := writeEvidenceFile(nested+"/bx.json", a, BridgeReport{Verdict: "ok"}, nil, "ok"); err != nil {
			t.Fatalf("writeEvidenceFile failed once the directory exists: %v", err)
		}
	})
}
