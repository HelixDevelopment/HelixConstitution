package main

// health_test.go -- UNIT tests (§11.4.27(A)) for status mapping, ranking,
// and the atomic health.json writer.

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func TestStatusFromBridge_ExecErrorAlwaysUnknown_NeverOK(t *testing.T) {
	// Anti-bluff (§11.4.69/§11.4.85): ANY exec-level error (missing
	// binary, crash, timeout, corrupted stdout) must degrade to
	// "unknown" regardless of what a stray/garbage BridgeReport might
	// otherwise say -- a caller must never be able to smuggle an "ok"
	// verdict through the error path.
	rep := BridgeReport{Verdict: "ok"} // deliberately-wrong stray value
	status := statusFromBridge(rep, errors.New("boom"))
	if status != "unknown" {
		t.Fatalf("PASS-BLUFF: exec error produced status=%q, want \"unknown\"", status)
	}
}

func TestStatusFromBridge_ValidVerdictsPassThrough(t *testing.T) {
	for _, v := range []string{"ok", "rate_limited", "quota_exceeded", "failed"} {
		got := statusFromBridge(BridgeReport{Verdict: v}, nil)
		if got != v {
			t.Fatalf("verdict %q: got status %q, want %q", v, got, v)
		}
	}
}

func TestStatusFromBridge_UnrecognisedVerdictIsUnknown(t *testing.T) {
	got := statusFromBridge(BridgeReport{Verdict: "something-new-and-unexpected"}, nil)
	if got != "unknown" {
		t.Fatalf("got %q, want \"unknown\" for an unrecognised verdict string", got)
	}
}

func TestRankAliases_NativePreferred_HealthiestFirst(t *testing.T) {
	entries := []AliasHealthEntry{
		{Alias: "z-router-ok", Kind: string(KindProviderRouter), Status: "ok"},
		{Alias: "b-native-failed", Kind: string(KindNative), Status: "failed"},
		{Alias: "a-native-ok", Kind: string(KindNative), Status: "ok"},
		{Alias: "c-router-unknown", Kind: string(KindProviderRouter), Status: "unknown"},
		{Alias: "d-provnative-ok", Kind: string(KindProviderNative), Status: "ok"},
	}
	rankAliases(entries)

	// Healthiest (ok) entries sort first; among equal "ok" status,
	// native beats provider-native beats provider-router; alphabetical
	// tie-break within equal (status, kind).
	want := []string{"a-native-ok", "d-provnative-ok", "z-router-ok", "b-native-failed", "c-router-unknown"}
	for i, w := range want {
		if entries[i].Alias != w {
			t.Fatalf("rank[%d] = %q, want %q (full order: %v)", i, entries[i].Alias, w, aliasNames(entries))
		}
	}
}

func aliasNames(entries []AliasHealthEntry) []string {
	out := make([]string, len(entries))
	for i, e := range entries {
		out[i] = e.Alias
	}
	return out
}

func TestWriteHealthAtomic_WritesValidJSON_NoTempFileLeftBehind(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "health.json")

	doc := HealthDoc{
		GeneratedAt: "2026-07-07T00:00:00Z",
		Aliases: []AliasHealthEntry{
			{Alias: "a1", Kind: string(KindNative), Status: "ok", CheckedAt: "2026-07-07T00:00:00Z", Evidence: "/tmp/a1.json"},
		},
	}
	if err := writeHealthAtomic(path, doc); err != nil {
		t.Fatalf("writeHealthAtomic failed: %v", err)
	}

	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("could not read written health.json: %v", err)
	}
	var got HealthDoc
	if err := json.Unmarshal(b, &got); err != nil {
		t.Fatalf("written health.json is not valid JSON: %v (content: %s)", err, string(b))
	}
	if len(got.Aliases) != 1 || got.Aliases[0].Alias != "a1" {
		t.Fatalf("unexpected round-tripped doc: %+v", got)
	}

	if _, err := os.Stat(path + ".tmp"); !os.IsNotExist(err) {
		t.Fatalf("expected the .tmp file to be renamed away, but it still exists (or stat errored: %v)", err)
	}
}

func TestWriteHealthAtomic_Overwrite_LeavesNoStaleContent(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "health.json")

	first := HealthDoc{GeneratedAt: "t1", Aliases: []AliasHealthEntry{{Alias: "old"}}}
	if err := writeHealthAtomic(path, first); err != nil {
		t.Fatalf("first write failed: %v", err)
	}
	second := HealthDoc{GeneratedAt: "t2", Aliases: []AliasHealthEntry{{Alias: "new"}}}
	if err := writeHealthAtomic(path, second); err != nil {
		t.Fatalf("second write failed: %v", err)
	}

	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read failed: %v", err)
	}
	var got HealthDoc
	if err := json.Unmarshal(b, &got); err != nil {
		t.Fatalf("unmarshal failed: %v", err)
	}
	if got.GeneratedAt != "t2" || len(got.Aliases) != 1 || got.Aliases[0].Alias != "new" {
		t.Fatalf("expected the second write to fully replace the first, got %+v", got)
	}
}
