package main

// probe_unit_test.go -- UNIT tests (§11.4.27(A)) for runBridgeProbe's
// exec/parse/anti-bluff contract. These tests exec a REAL subprocess --
// testdata/stubbridge -- but that stub IS the unit-test-only fake
// standing in for the real external dependency (the LLMsVerifier
// claude-alias-probe bridge), exactly the role §11.4.27(A) reserves
// mocks/stubs/fakes for. No real `claude` CLI call, no real LLM quota
// spent, and every scenario is deterministically selected via STUB_MODE
// so this suite is 100% reproducible (§11.4.50).
//
// This file carries the PWU-3 RED->GREEN proof named in the task brief:
// TestRunBridgeProbe_CappedAlias_RED_GREEN drives a capped-alias fixture
// (STUB_MODE=rate_limited / quota_exceeded) through the REAL
// exec+parse+statusFromBridge pipeline and asserts the util emits the
// distinct rate_limited/quota_exceeded status -- never "ok" (the exact
// PWU-2 gap the incorporation plan's providers/verdict.go closed at the
// LLMsVerifier layer; this test proves the util-layer wiring reflects it
// faithfully end to end).

import (
	"context"
	"strings"
	"testing"
	"time"
)

func withStubMode(t *testing.T, mode string) {
	t.Helper()
	t.Setenv("STUB_MODE", mode)
}

func TestRunBridgeProbe_OK_SentinelEchoedBack(t *testing.T) {
	bin := buildStubBridge(t)
	withStubMode(t, "ok")

	rep, err := runBridgeProbe(context.Background(), bin, []string{"--sentinel", "MY_SENTINEL_123"}, 10*time.Second)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if rep.Verdict != "ok" {
		t.Fatalf("verdict = %q, want \"ok\"", rep.Verdict)
	}
	if rep.Observed != "MY_SENTINEL_123" {
		t.Fatalf("observed = %q, want the echoed sentinel", rep.Observed)
	}
	if statusFromBridge(rep, nil) != "ok" {
		t.Fatalf("statusFromBridge did not propagate ok")
	}
}

// TestRunBridgeProbe_CappedAlias_RED_GREEN is the RED->GREEN proof named
// by the PWU-3 task brief. RED (pre-fix baseline, simulated here by the
// "generic_opaque_failure" sub-case): a capped alias whose bridge output
// cannot be distinguished from any other failure collapses into the
// generic "failed" bucket -- exactly the pre-PWU-2 gap
// providers/verdict.go's doc comment describes ("zero non-self
// callers" for ClassifyError). GREEN (post-fix, the "rate_limited" and
// "quota_exceeded" sub-cases): the SAME pipeline, given a bridge report
// that actually carries the distinct verdict, surfaces it distinctly --
// never "ok", never collapsed into "failed".
func TestRunBridgeProbe_CappedAlias_RED_GREEN(t *testing.T) {
	bin := buildStubBridge(t)

	cases := []struct {
		name       string
		mode       string
		wantStatus string
	}{
		{name: "rate_limited_alias_is_distinct_not_ok", mode: "rate_limited", wantStatus: "rate_limited"},
		{name: "quota_exceeded_alias_is_distinct_not_ok", mode: "quota_exceeded", wantStatus: "quota_exceeded"},
		{name: "generic_failure_is_failed_not_ok", mode: "failed", wantStatus: "failed"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			withStubMode(t, tc.mode)
			rep, execErr := runBridgeProbe(context.Background(), bin, []string{"--sentinel", "S"}, 10*time.Second)
			status := statusFromBridge(rep, execErr)

			if status == "ok" {
				t.Fatalf("PASS-BLUFF: a capped/failing alias (STUB_MODE=%s) reported status=ok", tc.mode)
			}
			if status != tc.wantStatus {
				t.Fatalf("STUB_MODE=%s: status = %q, want %q (rep=%+v execErr=%v)", tc.mode, status, tc.wantStatus, rep, execErr)
			}
		})
	}
}

func TestRunBridgeProbe_RateLimited_CarriesRetryAfter(t *testing.T) {
	bin := buildStubBridge(t)
	withStubMode(t, "rate_limited")

	rep, err := runBridgeProbe(context.Background(), bin, []string{"--sentinel", "S"}, 10*time.Second)
	if err != nil {
		t.Fatalf("unexpected error (rate_limited is a valid parsed report, not an exec error): %v", err)
	}
	if rep.RetryAfterSeconds != 30 {
		t.Fatalf("expected retry_after_seconds=30 from the stub fixture, got %d", rep.RetryAfterSeconds)
	}
}

// TestRunBridgeProbe_ChaosBadJSON_NeverFabricatesOK is the corrupted-
// stdout chaos case (§11.4.85 input-corruption injection): the stub
// emits non-JSON garbage. runBridgeProbe MUST return an error (never a
// fabricated report), and statusFromBridge MUST degrade to "unknown".
func TestRunBridgeProbe_ChaosBadJSON_NeverFabricatesOK(t *testing.T) {
	bin := buildStubBridge(t)
	withStubMode(t, "badjson")

	rep, err := runBridgeProbe(context.Background(), bin, []string{"--sentinel", "S"}, 10*time.Second)
	if err == nil {
		t.Fatalf("expected an error for unparseable/non-JSON bridge output, got report=%+v", rep)
	}
	if statusFromBridge(rep, err) != "unknown" {
		t.Fatalf("expected status=unknown for corrupted stdout")
	}
}

// TestRunBridgeProbe_ChaosEmptyStdout_NeverFabricatesOK covers the
// no-output case (crashed before writing anything).
func TestRunBridgeProbe_ChaosEmptyStdout_NeverFabricatesOK(t *testing.T) {
	bin := buildStubBridge(t)
	withStubMode(t, "empty")

	rep, err := runBridgeProbe(context.Background(), bin, []string{"--sentinel", "S"}, 10*time.Second)
	if err == nil {
		t.Fatalf("expected an error for empty bridge stdout, got report=%+v", rep)
	}
	if statusFromBridge(rep, err) != "unknown" {
		t.Fatalf("expected status=unknown for empty stdout")
	}
}

// TestRunBridgeProbe_ChaosMissingBinary_NeverFabricatesOK covers the
// binary-not-found case (a mistyped/misconfigured llmsverifier_bin
// path).
func TestRunBridgeProbe_ChaosMissingBinary_NeverFabricatesOK(t *testing.T) {
	rep, err := runBridgeProbe(context.Background(), "/nonexistent/path/to/claude-alias-probe", []string{"--sentinel", "S"}, 5*time.Second)
	if err == nil {
		t.Fatalf("expected an error for a missing bridge binary, got report=%+v", rep)
	}
	if !strings.Contains(err.Error(), "exec failed") && !strings.Contains(err.Error(), "no such file") {
		t.Fatalf("expected an exec-failure error message, got: %v", err)
	}
	if statusFromBridge(rep, err) != "unknown" {
		t.Fatalf("expected status=unknown for a missing binary")
	}
}

// TestRunBridgeProbe_ChaosTimeout_NeverFabricatesOK covers a hung
// subprocess: the probe's own timeout budget MUST kill it and report an
// honest timeout error, never hang the caller indefinitely nor fabricate
// a report.
func TestRunBridgeProbe_ChaosTimeout_NeverFabricatesOK(t *testing.T) {
	bin := buildStubBridge(t)
	withStubMode(t, "hang")

	start := time.Now()
	rep, err := runBridgeProbe(context.Background(), bin, []string{"--sentinel", "S"}, 1*time.Second)
	elapsed := time.Since(start)

	if err == nil {
		t.Fatalf("expected a timeout error for a hung subprocess, got report=%+v", rep)
	}
	if !strings.Contains(err.Error(), "timed out") {
		t.Fatalf("expected a timeout error message, got: %v", err)
	}
	if elapsed > 5*time.Second {
		t.Fatalf("runBridgeProbe took %v to return after a 1s timeout budget -- the hung subprocess was not killed promptly", elapsed)
	}
	if statusFromBridge(rep, err) != "unknown" {
		t.Fatalf("expected status=unknown for a timed-out probe")
	}
}
