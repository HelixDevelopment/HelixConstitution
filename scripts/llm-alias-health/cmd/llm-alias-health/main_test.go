package main

// main_test.go -- UNIT tests for run()'s flag validation (config-error
// exit paths) plus one full end-to-end exercise of run() itself against
// the stub bridge (config file -> CLI flags -> health.json + events.jsonl
// + evidence files on disk), proving main.go's own wiring (not just the
// internal functions it calls) produces real artefacts.

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestRun_ConfigErrors_Exit2(t *testing.T) {
	dir := t.TempDir()
	validCfgPath := filepath.Join(dir, "health_config.yaml")
	if err := os.WriteFile(validCfgPath, []byte("llmsverifier_bin: /bin/true\naliases:\n  - alias: a1\n    kind: native\n    config_dir: /tmp/x\n"), 0o644); err != nil {
		t.Fatalf("setup: %v", err)
	}

	cases := [][]string{
		{}, // missing -config
		{"-config", validCfgPath}, // missing -evidence-dir
		{"-config", filepath.Join(dir, "nonexistent.yaml"), "-evidence-dir", dir}, // unreadable config
	}
	for i, args := range cases {
		var stdout, stderr bytes.Buffer
		got := run(args, &stdout, &stderr)
		if got != 2 {
			t.Fatalf("case %d (%v): exit code = %d, want 2; stderr=%s", i, args, got, stderr.String())
		}
	}
}

func TestRun_EndToEnd_WithStubBridge_WritesRealArtefacts(t *testing.T) {
	bin := buildStubBridge(t)
	withStubMode(t, "ok")

	dir := t.TempDir()
	cfgPath := filepath.Join(dir, "health_config.yaml")
	cfgYAML := "llmsverifier_bin: " + bin + "\n" +
		"timeout_seconds: 10\n" +
		"sentinel_prefix: \"E2E_\"\n" +
		"aliases:\n" +
		"  - alias: e2e-native\n" +
		"    kind: native\n" +
		"    config_dir: /tmp/does-not-need-to-exist-for-the-stub\n" +
		"  - alias: e2e-router\n" +
		"    kind: provider-router\n" +
		"    base_url: http://127.0.0.1:3456\n"
	if err := os.WriteFile(cfgPath, []byte(cfgYAML), 0o644); err != nil {
		t.Fatalf("setup: %v", err)
	}

	healthOut := filepath.Join(dir, "health.json")
	eventsOut := filepath.Join(dir, "events.jsonl")
	evidenceDir := filepath.Join(dir, "evidence")

	var stdout, stderr bytes.Buffer
	code := run([]string{
		"-config", cfgPath,
		"-health-out", healthOut,
		"-events-out", eventsOut,
		"-evidence-dir", evidenceDir,
	}, &stdout, &stderr)

	if code != 0 {
		t.Fatalf("run() exit code = %d, want 0; stdout=%s stderr=%s", code, stdout.String(), stderr.String())
	}

	b, err := os.ReadFile(healthOut)
	if err != nil {
		t.Fatalf("health.json was not written: %v", err)
	}
	var doc HealthDoc
	if err := json.Unmarshal(b, &doc); err != nil {
		t.Fatalf("health.json is not valid JSON: %v (content: %s)", err, string(b))
	}
	if len(doc.Aliases) != 2 {
		t.Fatalf("expected 2 alias entries, got %d: %+v", len(doc.Aliases), doc.Aliases)
	}
	for _, e := range doc.Aliases {
		if e.Status != "ok" {
			t.Fatalf("alias %q: status = %q, want ok (STUB_MODE=ok)", e.Alias, e.Status)
		}
		if _, err := os.Stat(e.Evidence); err != nil {
			t.Fatalf("alias %q: evidence file missing: %v", e.Alias, err)
		}
	}
	if _, err := os.Stat(eventsOut); err != nil {
		t.Fatalf("events.jsonl was not written: %v", err)
	}
}
