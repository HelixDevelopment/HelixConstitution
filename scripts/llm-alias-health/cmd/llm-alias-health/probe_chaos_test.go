package main

// probe_chaos_test.go -- §11.4.85 CHAOS coverage: process-death/hang
// injection, input-corruption (non-JSON stdout), resource-exhaustion
// (unwritable evidence dir), and a whole-run "provider down" scenario
// exercised through the real orchestration path (probeAllAliases) --
// proving one alias's failure never crashes the sweep for the others,
// and a fabricated "ok" verdict is impossible under any of these
// conditions.

import (
	"bytes"
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
)

// TestChaos_ProbeAllAliases_ProviderDown_NoCrash_NoFalseOK drives the
// FULL orchestration path (probeAllAliases -> statusFromBridge ->
// writeEvidenceFile -> appendEvent) against 3 aliases all backed by a
// "crashed" bridge (STUB_MODE=nonzero_no_json: non-zero exit, no
// parseable JSON, stderr-only output -- the provider-down/bridge-crash
// class). The whole sweep MUST complete without panicking, MUST record
// "unknown" for every alias, and MUST NEVER report "ok".
func TestChaos_ProbeAllAliases_ProviderDown_NoCrash_NoFalseOK(t *testing.T) {
	bin := buildStubBridge(t)
	withStubMode(t, "nonzero_no_json")

	dir := t.TempDir()
	evidenceDir := filepath.Join(dir, "evidence")
	eventsPath := filepath.Join(dir, "events.jsonl")
	if err := os.MkdirAll(evidenceDir, 0o755); err != nil {
		t.Fatalf("setup: %v", err)
	}

	cfg := Config{
		LLMsVerifierBin: bin,
		TimeoutSeconds:  5,
		SentinelPrefix:  "CHAOS_",
		Aliases: []AliasConfig{
			{Alias: "down1", Kind: KindNative, ConfigDir: "/tmp/x"},
			{Alias: "down2", Kind: KindProviderRouter, BaseURL: "http://127.0.0.1:3456"},
			{Alias: "down3", Kind: KindProviderNative, BaseURL: "https://x", AuthTokenEnv: "UNUSED"},
		},
	}
	t.Setenv("UNUSED", "not-a-real-secret-just-satisfies-config-validation")

	var stdout bytes.Buffer
	entries := func() (result []AliasHealthEntry) {
		defer func() {
			if r := recover(); r != nil {
				t.Fatalf("PANIC during probeAllAliases under provider-down chaos: %v", r)
			}
		}()
		return probeAllAliases(context.Background(), cfg, evidenceDir, eventsPath, &stdout)
	}()

	if len(entries) != 3 {
		t.Fatalf("expected 3 entries, got %d: %+v", len(entries), entries)
	}
	for _, e := range entries {
		if e.Status == "ok" {
			t.Fatalf("PASS-BLUFF: alias %q reported status=ok while every alias's bridge was crashed/down", e.Alias)
		}
		if e.Status != "unknown" {
			t.Fatalf("alias %q: status = %q, want \"unknown\" for a crashed bridge", e.Alias, e.Status)
		}
		if e.Evidence == "" {
			t.Fatalf("alias %q: missing evidence path", e.Alias)
		}
		if _, err := os.Stat(e.Evidence); err != nil {
			t.Fatalf("alias %q: evidence file %q was not written: %v", e.Alias, e.Evidence, err)
		}
	}

	// events.jsonl must record a probe_error for each alias -- never a
	// silent drop.
	raw, err := os.ReadFile(eventsPath)
	if err != nil {
		t.Fatalf("could not read events.jsonl: %v", err)
	}
	lines := strings.Split(strings.TrimSpace(string(raw)), "\n")
	errorEvents := 0
	for _, line := range lines {
		var ev Event
		if err := json.Unmarshal([]byte(line), &ev); err != nil {
			t.Fatalf("events.jsonl line is not valid JSON: %v (line: %s)", err, line)
		}
		if ev.Event == "probe_error" {
			errorEvents++
		}
	}
	if errorEvents != 3 {
		t.Fatalf("expected 3 probe_error events, got %d (lines=%v)", errorEvents, lines)
	}
}

// TestChaos_WriteEvidenceFile_UnwritableDir_NoCrash_ErrorReturned
// simulates a resource-exhaustion/permission-failure class (§11.4.85):
// the evidence directory is not writable (mode 0o500, no write bit).
// writeEvidenceFile MUST return an error, never panic; and
// probeAllAliases MUST log a warning and continue rather than aborting
// the whole sweep over one alias's evidence-write failure.
func TestChaos_WriteEvidenceFile_UnwritableDir_NoCrash_ErrorReturned(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("SKIP: POSIX permission-bit semantics not applicable on windows")
	}
	if os.Geteuid() == 0 {
		t.Skip("SKIP: running as root ignores directory permission bits, so this chaos scenario cannot be reproduced")
	}

	dir := t.TempDir()
	roDir := filepath.Join(dir, "readonly-evidence")
	if err := os.MkdirAll(roDir, 0o755); err != nil {
		t.Fatalf("setup: %v", err)
	}
	if err := os.Chmod(roDir, 0o500); err != nil {
		t.Fatalf("setup: chmod: %v", err)
	}
	t.Cleanup(func() { _ = os.Chmod(roDir, 0o755) }) // let TempDir cleanup remove it

	a := AliasConfig{Alias: "ro1", Kind: KindNative, ConfigDir: "/tmp/x"}
	err := writeEvidenceFile(filepath.Join(roDir, "ro1.json"), a, BridgeReport{Verdict: "ok"}, nil, "ok")
	if err == nil {
		t.Fatal("expected an error writing evidence into a read-only directory")
	}

	bin := buildStubBridge(t)
	withStubMode(t, "ok")
	cfg := Config{
		LLMsVerifierBin: bin,
		TimeoutSeconds:  5,
		SentinelPrefix:  "CHAOS_",
		Aliases:         []AliasConfig{a},
	}
	var stdout bytes.Buffer
	entries := func() (result []AliasHealthEntry) {
		defer func() {
			if r := recover(); r != nil {
				t.Fatalf("PANIC when the evidence dir is unwritable: %v", r)
			}
		}()
		return probeAllAliases(context.Background(), cfg, roDir, filepath.Join(dir, "events.jsonl"), &stdout)
	}()
	if len(entries) != 1 {
		t.Fatalf("expected the sweep to still produce 1 entry despite the evidence-write failure, got %d", len(entries))
	}
	if entries[0].Status != "ok" {
		t.Fatalf("the probe itself succeeded (STUB_MODE=ok); an unrelated evidence-write failure must not corrupt the probe's own status, got %q", entries[0].Status)
	}
	if !strings.Contains(stdout.String(), "WARNING") {
		t.Fatalf("expected a WARNING logged for the evidence-write failure, stdout=%q", stdout.String())
	}
}

// TestChaos_AppendEvent_PreExistingCorruptedFile_AppendsCleanly proves a
// pre-existing corrupted/garbage events.jsonl (a prior chaos event, disk
// hiccup, or partial write from an earlier crashed run) does not prevent
// a new, well-formed event from being appended -- JSONL append-only
// semantics mean prior garbage is inert, never rewritten or parsed on
// write.
func TestChaos_AppendEvent_PreExistingCorruptedFile_AppendsCleanly(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "events.jsonl")
	if err := os.WriteFile(path, []byte("{not valid json at all\n"), 0o644); err != nil {
		t.Fatalf("setup: %v", err)
	}

	if err := appendEvent(path, Event{Alias: "a1", Event: "probe_result", Status: "ok"}); err != nil {
		t.Fatalf("appendEvent failed on a file with pre-existing corrupted content: %v", err)
	}

	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read failed: %v", err)
	}
	lines := strings.Split(strings.TrimSpace(string(raw)), "\n")
	last := lines[len(lines)-1]
	var ev Event
	if err := json.Unmarshal([]byte(last), &ev); err != nil {
		t.Fatalf("the newly-appended last line is not valid JSON: %v (line: %q)", err, last)
	}
	if ev.Alias != "a1" || ev.Status != "ok" {
		t.Fatalf("unexpected appended event: %+v", ev)
	}
}

// TestChaos_ContextCancelledMidProbe_KillsSubprocess_NoHang proves an
// external context cancellation (the caller giving up, e.g. because the
// whole health sweep itself is being shut down) promptly kills a hung
// subprocess rather than leaking it.
func TestChaos_ContextCancelledMidProbe_KillsSubprocess_NoHang(t *testing.T) {
	bin := buildStubBridge(t)
	withStubMode(t, "hang")

	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	var probeErr error
	go func() {
		_, probeErr = runBridgeProbe(ctx, bin, []string{"--sentinel", "S"}, 60*time.Second)
		close(done)
	}()

	time.Sleep(200 * time.Millisecond)
	cancel()

	select {
	case <-done:
		if probeErr == nil {
			t.Fatal("expected an error when the parent context is cancelled mid-probe")
		}
	case <-time.After(10 * time.Second):
		t.Fatal("DEADLOCK/HANG: cancelling the parent context did not stop runBridgeProbe within 10s")
	}
}
