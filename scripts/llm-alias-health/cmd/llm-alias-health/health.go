package main

// health.go -- status mapping, native-preferred ranking, and the
// health.json document shape (PART D of
// docs/research/llmsverifier_incorporation_20260707/ANALYSIS_AND_PLAN.md,
// ATMOSphere-Android-15 repo).

import (
	"encoding/json"
	"os"
	"sort"
	"time"
)

// AliasHealthEntry is one alias's health.json row.
type AliasHealthEntry struct {
	Alias       string `json:"alias"`
	Kind        string `json:"kind"`
	Status      string `json:"status"`
	LatencyMs   int64  `json:"latency_ms"`
	RetryAfterS int    `json:"retry_after_s,omitempty"`
	Model       string `json:"model,omitempty"`
	CheckedAt   string `json:"checked_at"`
	Evidence    string `json:"evidence"`
}

// HealthDoc is the top-level health.json document (§11.4.116 -- an
// atomically-rewritten status snapshot a conductor/orchestrator tails
// live).
type HealthDoc struct {
	GeneratedAt string             `json:"generated_at"`
	Aliases     []AliasHealthEntry `json:"aliases"`
}

// statusFromBridge maps a (BridgeReport, exec-error) pair onto the
// closed-set status vocabulary {ok, rate_limited, quota_exceeded,
// failed, unknown}. execErr != nil (the bridge could not be run/parsed
// at all -- missing binary, crash, timeout, corrupted stdout) ALWAYS
// degrades to "unknown", NEVER "ok" and NEVER silently dropped
// (§11.4.69/§11.4.85 chaos-hardening: a killed subprocess or a
// provider-down condition must be visibly distinguishable from a
// genuine content determination).
func statusFromBridge(rep BridgeReport, execErr error) string {
	if execErr != nil {
		return "unknown"
	}
	switch rep.Verdict {
	case "ok", "rate_limited", "quota_exceeded", "failed":
		return rep.Verdict
	default:
		return "unknown"
	}
}

// statusRank + kindRank implement the native-preferred ranking PART D
// specifies: healthiest first (ok before rate_limited before
// quota_exceeded before failed before unknown), and within equal status,
// native aliases before provider-native before provider-router (a
// native Max/Pro account is the operator's own paid seat -- prefer it
// over a third-party provider route when both are equally healthy).
var statusRank = map[string]int{
	"ok":             0,
	"rate_limited":   1,
	"quota_exceeded": 2,
	"failed":         3,
	"unknown":        4,
}

var kindRank = map[string]int{
	string(KindNative):         0,
	string(KindProviderNative): 1,
	string(KindProviderRouter): 2,
}

// rankAliases sorts entries in place: healthiest-status-first, then
// native-kind-first, then alphabetically by alias name (deterministic
// tie-break, §11.4.50).
func rankAliases(entries []AliasHealthEntry) {
	sort.SliceStable(entries, func(i, j int) bool {
		si, sj := statusRank[entries[i].Status], statusRank[entries[j].Status]
		if si != sj {
			return si < sj
		}
		ki, kj := kindRank[entries[i].Kind], kindRank[entries[j].Kind]
		if ki != kj {
			return ki < kj
		}
		return entries[i].Alias < entries[j].Alias
	})
}

// writeHealthAtomic writes doc to path via a temp-file-then-rename
// sequence (§11.4.116 atomically-rewritten status snapshot -- a reader
// never observes a torn/partial write).
func writeHealthAtomic(path string, doc HealthDoc) error {
	b, err := json.MarshalIndent(doc, "", "  ")
	if err != nil {
		return err
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, b, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

// nowRFC3339 is the single time source for CheckedAt/GeneratedAt
// timestamps, isolated so tests can assert format without depending on
// wall-clock timing.
func nowRFC3339() string {
	return time.Now().UTC().Format(time.RFC3339)
}
