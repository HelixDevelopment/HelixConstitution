// Package check implements the five machine-checkable check families
// (DESIGN §3): DEDUP, TIMELINE COHERENCE, CROSS-DOC CONSISTENCY, INTEGRITY,
// STRUCTURAL. Every family operates over the canonical []model.Record so it is
// source-kind-agnostic.
package check

import (
	"sort"

	"github.com/HelixDevelopment/HelixConstitution/scripts/doc_integrity/internal/config"
	"github.com/HelixDevelopment/HelixConstitution/scripts/doc_integrity/internal/model"
)

// Finding is one integrity violation. A finding MUST name the offending row/item
// (Locator + Offending) so it is actionable (§11.4.6). Severity is always FAIL —
// this validator has no WARN tier (a divergence is a divergence).
type Finding struct {
	Family    string   `json:"family"`
	RuleID    string   `json:"rule_id"`
	SourceID  string   `json:"source_id"`
	Locator   string   `json:"locator"`
	Message   string   `json:"message"`
	Offending []string `json:"offending,omitempty"`
}

// SourceData bundles one source's config with its loaded records + present cols.
type SourceData struct {
	Src     config.Source
	Records []model.Record
	Present map[string]bool
}

// Dataset is the whole doc-set the checks run over.
type Dataset struct {
	Cfg     *config.Config
	Sources []SourceData
	All     []model.Record // union of every source's records
}

// NewDataset builds the union.
func NewDataset(cfg *config.Config, sources []SourceData) *Dataset {
	ds := &Dataset{Cfg: cfg, Sources: sources}
	for _, s := range sources {
		ds.All = append(ds.All, s.Records...)
	}
	return ds
}

// RunAll runs every check family and returns a deterministically-sorted finding
// list (§11.4.50 — same inputs → identical findings across N runs).
func RunAll(ds *Dataset) []Finding {
	var findings []Finding
	findings = append(findings, Dedup(ds)...)
	findings = append(findings, Timeline(ds)...)
	findings = append(findings, CrossDoc(ds)...)
	findings = append(findings, Integrity(ds)...)
	findings = append(findings, Structural(ds)...)
	sortFindings(findings)
	return findings
}

func sortFindings(f []Finding) {
	sort.SliceStable(f, func(i, j int) bool {
		a, b := f[i], f[j]
		if a.Family != b.Family {
			return a.Family < b.Family
		}
		if a.RuleID != b.RuleID {
			return a.RuleID < b.RuleID
		}
		if a.SourceID != b.SourceID {
			return a.SourceID < b.SourceID
		}
		if a.Locator != b.Locator {
			return a.Locator < b.Locator
		}
		return a.Message < b.Message
	})
}
