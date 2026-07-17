// Package model defines the canonical, source-kind-agnostic row model that
// every adapter maps its native rows into, so all five check families
// (DEDUP / TIMELINE / CROSS-DOC / INTEGRITY / STRUCTURAL) are written once and
// operate over any source kind (xlsx / markdown-table / markdown-headings /
// sqlite).
//
// Design authority: docs/research/doc_integrity_validator/DESIGN.md §2.
// Constitution: §11.4.186 (proposed), §11.4.28 (decoupled/project-agnostic).
package model

import "time"

// Record is the load-bearing canonical abstraction (DESIGN §2). Every adapter
// normalises its native rows into []Record so the check families never need to
// know which source kind produced a row. Locator carries the pinpoint back to
// the source (xlsx "sheet!A47", markdown "path:line", DB "items.atm_id=ATM-659")
// so every finding is actionable (§11.4.6 — a finding must name the offending
// row/item, never "something is inconsistent").
type Record struct {
	SourceID string // config source id that produced this record

	ItemID  string // e.g. "2.5.1" (STRUCTURAL id)
	Ticket  string // e.g. "ATM-659" / "SPK-012" (cross-doc + dedup join key)
	Subject string // raw subject / task name (EN or RU)

	SubjectNorm string // normalised subject (deterministic; §11.4.50)
	ScopeNorm   string // normalised task-scope discriminator (the anti-false-positive key)

	Type   string // Bug | Feature | Task (INTEGRITY §11.4.33)
	Status string // lifecycle status (INTEGRITY §11.4.33)

	Start    *time.Time // committed start date (nil = absent)
	Deadline *time.Time // committed deadline (nil = absent)
	StartRaw string     // raw as-read start cell (for messages)
	DeadRaw  string     // raw as-read deadline cell (for messages)

	Deps    []string // dependency references (item ids or tickets)
	Release string   // target release / version
	Section string   // section / milestone grouping label

	Gated         bool   // GATED (timeline-exempt but must be marked)
	SectionHeader bool   // this record is a section/milestone header row
	Location      string // for DB rows: "Issues" / "Fixed" (INTEG-03)
	Superseding   string // superseding-item reference (INTEG-01)

	Locator string // human-actionable pinpoint back to the source
}

// HasDates reports whether the record carries both a start and a deadline.
func (r Record) HasDates() bool { return r.Start != nil && r.Deadline != nil }

// HasAnyDate reports whether the record carries at least one date.
func (r Record) HasAnyDate() bool { return r.Start != nil || r.Deadline != nil }
