// Package config loads the consumer-owned checkset.yaml (DESIGN §1.4). ALL
// project-specific data — doc-set paths, column headers, id patterns, section
// names, thresholds — lives in this YAML, NEVER in Go source (§11.4.28 /
// §11.4.177 decoupling). The engine binary is project-agnostic; a consumer
// registers its docs as data.
package config

import (
	"fmt"
	"os"

	"gopkg.in/yaml.v3"
)

// Config is the root checkset schema.
type Config struct {
	SchemaVersion int          `yaml:"schema_version"`
	Sources       []Source     `yaml:"sources"`
	CrossdocJoin  CrossdocJoin `yaml:"crossdoc_join"`
	Dedup         DedupCfg     `yaml:"dedup"`
	Thresholds    Thresholds   `yaml:"thresholds"`
}

// Source describes one document/database in the doc-set.
type Source struct {
	ID   string `yaml:"id"`
	Kind string `yaml:"kind"` // xlsx | markdown-table | markdown-headings | sqlite
	Path string `yaml:"path"`

	// xlsx / markdown-table
	Sheet     int               `yaml:"sheet"`      // xlsx 1-based sheet index (0/1 → first)
	SheetName string            `yaml:"sheet_name"` // xlsx sheet name (wins over Sheet if set)
	HeaderRow int               `yaml:"header_row"` // 1-based header row (xlsx); default 1
	Columns   map[string]string `yaml:"columns"`    // logical name → source column header

	RequiredColumns     []string `yaml:"required_columns"`      // subset of Columns keys that MUST be present
	IDPattern           string   `yaml:"id_pattern"`            // STRUCTURAL id regex
	IDMonotonic         bool     `yaml:"id_monotonic"`          // STRUCT-02 monotonic check (opt-in; off by default)
	GatedMarker         string   `yaml:"gated_marker"`          // token marking a timeline-exempt row
	SectionHeaderMarker string   `yaml:"section_header_marker"` // token marking a section header row (literal substring)

	// SectionHeaderStructural (opt-in) recognises a section/grouping row that
	// carries NO literal marker: a row whose ItemID fails id_pattern AND has no
	// ticket AND no dates is a header, not an item (e.g. an xlsx whose section
	// rows put a "4.1 <title>" grouping label in the id column). Set when the
	// source's section rows are structurally distinct but share no literal token
	// with a marker. A row that fails the pattern but DOES carry a ticket or a
	// date is a real (malformed) item and is NEVER suppressed (§11.4.120 — the
	// gate asserts the RIGHT invariant: id discipline applies to items, not to
	// grouping headers; it does not fake-pass real malformed rows).
	SectionHeaderStructural bool `yaml:"section_header_structural"`

	// TicketIsEpic (opt-in, per-source) declares that this source's `ticket`
	// column is an EPIC identifier that legitimately spans many sub-task rows
	// (e.g. a delivery plan where one ATM-/SPK- ticket labels every sub-task of a
	// milestone). When set, DEDUP-01 (ticket-appears-on-many-rows) does NOT apply
	// to this source. DEDUP-02 (subject+scope duplicate) STILL runs and still
	// catches a genuinely-duplicated feature (§11.4.120 — the RIGHT invariant:
	// an epic ticket on N rows is not a duplicate; two rows describing the SAME
	// feature with divergent dates still is).
	TicketIsEpic bool `yaml:"ticket_is_epic"`

	// sqlite
	Table  string            `yaml:"table"`  // items table
	Tables map[string]string `yaml:"tables"` // logical→physical table names (items, history)
}

// CrossdocJoin controls how the same feature is recognised across sources.
type CrossdocJoin struct {
	Key           string   `yaml:"key"`           // primary join key (default "ticket")
	Fallback      string   `yaml:"fallback"`      // "subject_norm" fuzzy fallback
	Compare       []string `yaml:"compare"`       // timeline | status | type
	Authoritative string   `yaml:"authoritative"` // source id treated as authoritative (e.g. v9_plan)
}

// DedupCfg controls the DEDUP family.
type DedupCfg struct {
	KeyFields         []string `yaml:"key_fields"`          // e.g. [subject_norm, scope_norm]
	TicketField       string   `yaml:"ticket_field"`        // logical ticket column name
	DateToleranceDays int      `yaml:"date_tolerance_days"` // date-agreement tolerance for DEDUP-02
	Allowlist         []string `yaml:"allowlist"`           // "subject_norm|scope_norm" pairs known-distinct
}

// Thresholds holds calibrated numeric knobs.
type Thresholds struct {
	SubjectSimilarity float64 `yaml:"subject_similarity"` // fuzzy fallback join threshold
}

// Load reads and validates a checkset.yaml, applying safe defaults.
func Load(path string) (*Config, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read checkset %q: %w", path, err)
	}
	var c Config
	if err := yaml.Unmarshal(raw, &c); err != nil {
		return nil, fmt.Errorf("parse checkset %q: %w", path, err)
	}
	if len(c.Sources) == 0 {
		return nil, fmt.Errorf("checkset %q: no sources declared", path)
	}
	ids := map[string]bool{}
	for i := range c.Sources {
		s := &c.Sources[i]
		if s.ID == "" {
			return nil, fmt.Errorf("checkset %q: source #%d has no id", path, i+1)
		}
		if ids[s.ID] {
			return nil, fmt.Errorf("checkset %q: duplicate source id %q", path, s.ID)
		}
		ids[s.ID] = true
		if s.Path == "" {
			return nil, fmt.Errorf("checkset %q: source %q has no path", path, s.ID)
		}
		switch s.Kind {
		case "xlsx", "markdown-table", "markdown-headings", "sqlite":
		default:
			return nil, fmt.Errorf("checkset %q: source %q unknown kind %q", path, s.ID, s.Kind)
		}
		if s.HeaderRow == 0 {
			s.HeaderRow = 1
		}
	}
	// Defaults.
	if c.CrossdocJoin.Key == "" {
		c.CrossdocJoin.Key = "ticket"
	}
	if len(c.CrossdocJoin.Compare) == 0 {
		c.CrossdocJoin.Compare = []string{"timeline", "status", "type"}
	}
	if c.Thresholds.SubjectSimilarity == 0 {
		c.Thresholds.SubjectSimilarity = 0.90
	}
	if len(c.Dedup.KeyFields) == 0 {
		c.Dedup.KeyFields = []string{"subject_norm", "scope_norm"}
	}
	return &c, nil
}
