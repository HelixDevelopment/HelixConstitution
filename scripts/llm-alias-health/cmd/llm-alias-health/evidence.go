package main

// evidence.go -- per-alias captured-evidence artefact (§11.4.69: every
// PASS/status cites an evidence path; this is that artefact). One JSON
// file per alias per run, holding the full bridge report (or the exec
// error, when the bridge itself could not be run/parsed) plus the
// derived status -- so a reviewer can trace "why does health.json say
// alias X is rate_limited" back to the exact real captured output.

import (
	"encoding/json"
	"os"
)

// evidenceDoc is the persisted per-alias evidence artefact.
type evidenceDoc struct {
	Alias     string      `json:"alias"`
	Kind      string      `json:"kind"`
	Status    string      `json:"status"`
	CheckedAt string      `json:"checked_at"`
	Report    *BridgeReport `json:"report,omitempty"`
	ExecError string      `json:"exec_error,omitempty"`
}

// writeEvidenceFile persists one alias's probe outcome. It writes
// EITHER the bridge's own report (when the exec+parse succeeded) OR the
// exec error text (when it did not) -- never both, and never a
// fabricated report when execErr != nil.
func writeEvidenceFile(path string, a AliasConfig, rep BridgeReport, execErr error, status string) error {
	doc := evidenceDoc{
		Alias:     a.Alias,
		Kind:      string(a.Kind),
		Status:    status,
		CheckedAt: nowRFC3339(),
	}
	if execErr != nil {
		doc.ExecError = execErr.Error()
	} else {
		r := rep
		doc.Report = &r
	}

	b, err := json.MarshalIndent(doc, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, b, 0o644)
}
