// fixed_test.go — coverage for parseFixed against the REAL Fixed.md format.
//
// Background: Fixed.md uses the SAME H2-heading + `**Status:**` metadata block
// shape as Issues.md (the ATMOSphere `## §<letters>[ CRITICAL] — [ATM-NNN]
// <title>` form, the canonical `## ABC-123 — <title>` form, and the
// bracket-less derived-id form) — NOT the pipe-table form the original
// fixedRowRe expected. parseFixed must therefore recognise H2-heading item
// blocks, emit them with current_location='Fixed', and keep the legacy
// pipe-table closure rows working for byte-identical round-trips.
//
// No mocks: parseFixed is the production parser; we assert on its real output.
package main

import (
	"strings"
	"testing"
)

// fxClosedGL — ATMOSphere closure block: bracketed id, em-dash title, a
// closure Status. This is the dominant real Fixed.md shape.
const fxClosedGL = `## §GL CRITICAL — [ATM-238] Netflix login failure on D3 (closed 2026-05-28)

**Status:** Fixed (→ Fixed.md)
**Type:** Bug
**Severity:** Critical — Netflix unusable; first-login blocked
**Round:** R12
**Commit(s):** abc1234, def5678
**Evidence:** docs/qa/ATM-238/transcript.md

Closure narrative: re-pinned the login token refresh path.
`

// fxClosedCanonical — the canonical HelixCode closure block.
const fxClosedCanonical = `## HXC-014b — Inheritance gate hardening across all four root docs

**Status:** Implemented (→ Fixed.md)
**Type:** Task
**Round:** R3
`

// fxClosedDerived — bracket-less ATMOSphere closure → derived id.
const fxClosedDerived = `## §GS CRITICAL — Local-playback A/V quality VLC fork 4K-glitch resolved

**Status:** Completed (→ Fixed.md)
**Type:** Bug
**Severity:** Critical — local Movies playback degraded
`

// fxFixedSectionHeader — a structural heading in Fixed.md with NO **Status:**
// block. MUST be skipped (kept as raw) exactly like the Issues path.
const fxFixedSectionHeader = `## Fixed-item conventions

This section explains the Fixed.md closure-row conventions. No metadata block.
`

// fxLegacyTable — the ORIGINAL pipe-table closure form. MUST still parse so the
// change is backward-compatible.
const fxLegacyTable = `| Date | Item | Type | Status | Round | Commit(s) | Evidence |
|---|---|---|---|---|---|---|
| 2026-05-20 | HRD-009: scaffold landed | Task | Fixed | R1 | 1111aaa | e2e log |
`

// TestParseFixed_H2Heading_BracketedID is the first failing TDD test: the real
// Fixed.md H2-heading format must yield a workable item at location 'Fixed'.
func TestParseFixed_H2Heading_BracketedID(t *testing.T) {
	items, segs := parseFixed(fxClosedGL)
	if len(items) != 1 {
		t.Fatalf("expected 1 item, got %d (%v)", len(items), itemIDs(items))
	}
	it := items[0]
	if it.AtmID != "ATM-238" {
		t.Errorf("atm_id: got %q want ATM-238", it.AtmID)
	}
	if it.CurrentLocation != "Fixed" {
		t.Errorf("current_location: got %q want Fixed", it.CurrentLocation)
	}
	if it.Status != "Fixed (→ Fixed.md)" {
		t.Errorf("status: got %q want Fixed (→ Fixed.md)", it.Status)
	}
	if it.Type != "Bug" {
		t.Errorf("type: got %q want Bug", it.Type)
	}
	if !strings.Contains(it.Title, "Netflix login failure on D3") {
		t.Errorf("title: got %q, expected the human title", it.Title)
	}
	if strings.Contains(it.Title, "[ATM-238]") || strings.Contains(it.Title, "§GL") {
		t.Errorf("title still carries the id/§-prefix: %q", it.Title)
	}
	if it.BodyMD != fxClosedGL {
		t.Errorf("body_md not verbatim:\n got: %q\nwant: %q", it.BodyMD, fxClosedGL)
	}
	itemSegs := 0
	for _, s := range segs {
		if s.Kind == "item" {
			itemSegs++
		}
	}
	if itemSegs != 1 {
		t.Errorf("item segments: got %d want 1", itemSegs)
	}
}

func TestParseFixed_H2Heading_Canonical(t *testing.T) {
	items, _ := parseFixed(fxClosedCanonical)
	if len(items) != 1 {
		t.Fatalf("expected 1 item, got %d (%v)", len(items), itemIDs(items))
	}
	it := items[0]
	if it.AtmID != "HXC-014b" {
		t.Errorf("atm_id: got %q want HXC-014b", it.AtmID)
	}
	if it.CurrentLocation != "Fixed" {
		t.Errorf("current_location: got %q want Fixed", it.CurrentLocation)
	}
	if it.Status != "Implemented (→ Fixed.md)" {
		t.Errorf("status: got %q want Implemented (→ Fixed.md)", it.Status)
	}
}

func TestParseFixed_H2Heading_DerivedID(t *testing.T) {
	items, _ := parseFixed(fxClosedDerived)
	if len(items) != 1 {
		t.Fatalf("expected 1 item, got %d (%v)", len(items), itemIDs(items))
	}
	it := items[0]
	if !strings.HasPrefix(it.AtmID, "ATM-DERIVED-") {
		t.Errorf("expected derived id, got %q", it.AtmID)
	}
	if it.CurrentLocation != "Fixed" {
		t.Errorf("current_location: got %q want Fixed", it.CurrentLocation)
	}
	if !strings.Contains(it.Title, "Local-playback A/V quality") {
		t.Errorf("title %q missing expected text", it.Title)
	}
}

// Section headers (no **Status:** block) MUST be skipped, kept verbatim as raw.
func TestParseFixed_H2_SectionHeader_Skipped(t *testing.T) {
	items, segs := parseFixed(fxFixedSectionHeader)
	if len(items) != 0 {
		t.Errorf("expected 0 items (section header), got %d (%v)", len(items), itemIDs(items))
	}
	var rebuilt strings.Builder
	for _, s := range segs {
		if s.Kind == "raw" {
			rebuilt.WriteString(s.Raw)
		}
	}
	if rebuilt.String() != fxFixedSectionHeader {
		t.Errorf("section header not preserved verbatim:\n got: %q\nwant: %q", rebuilt.String(), fxFixedSectionHeader)
	}
}

// The legacy pipe-table closure form MUST still parse (backward-compat).
func TestParseFixed_LegacyTable_StillParses(t *testing.T) {
	items, _ := parseFixed(fxLegacyTable)
	if len(items) != 1 {
		t.Fatalf("expected 1 legacy-table item, got %d (%v)", len(items), itemIDs(items))
	}
	it := items[0]
	if it.AtmID != "HRD-009" {
		t.Errorf("atm_id: got %q want HRD-009", it.AtmID)
	}
	if it.CurrentLocation != "Fixed" {
		t.Errorf("current_location: got %q want Fixed", it.CurrentLocation)
	}
}

// A mixed Fixed.md document: H2-heading closures + a skipped section header +
// a legacy table — and the full text MUST round-trip byte-identically through
// the (item body + raw segment) decomposition.
func TestParseFixed_MixedDocument_RoundTrip(t *testing.T) {
	// Realistic layout: an optional legacy pipe-table block lives in the
	// preamble (a table-form Fixed.md or migration remnant), BEFORE the
	// H2-heading closure items. Each H2 item block runs up to the next `## `
	// heading or EOF, so a bare table after an H2 item would belong to that
	// item's body — hence the table sits in the preamble where it round-trips
	// AND is independently recognised.
	preamble := "# ATMOSphere Fixed log\n\nClosed-item registry.\n\n" + fxLegacyTable + "\n"
	doc := preamble + fxFixedSectionHeader + "\n" + fxClosedCanonical + "\n" +
		fxClosedGL + "\n" + fxClosedDerived

	items, segs := parseFixed(doc)

	if !hasItem(items, "HXC-014b") {
		t.Errorf("canonical HXC-014b missing")
	}
	if !hasItem(items, "ATM-238") {
		t.Errorf("ATM-238 missing")
	}
	if !hasItem(items, "HRD-009") {
		t.Errorf("legacy-table HRD-009 missing")
	}
	derivedCount := 0
	for _, it := range items {
		if strings.HasPrefix(it.AtmID, "ATM-DERIVED-") {
			derivedCount++
		}
		if it.CurrentLocation != "Fixed" {
			t.Errorf("%s: current_location %q != Fixed", it.AtmID, it.CurrentLocation)
		}
	}
	if derivedCount != 1 {
		t.Errorf("expected exactly 1 derived-id item (§GS), got %d", derivedCount)
	}
	// HXC-014b, ATM-238, §GS-derived, HRD-009 (legacy table) = 4 items.
	if len(items) != 4 {
		t.Errorf("expected 4 items, got %d (%v)", len(items), itemIDs(items))
	}

	bodyByID := map[string]string{}
	for _, it := range items {
		bodyByID[it.AtmID] = it.BodyMD
	}
	var rebuilt strings.Builder
	for _, s := range segs {
		switch s.Kind {
		case "raw":
			rebuilt.WriteString(s.Raw)
		case "item":
			rebuilt.WriteString(bodyByID[s.AtmID])
		}
	}
	if rebuilt.String() != doc {
		t.Errorf("mixed-document round-trip NOT byte-identical (got %d bytes, want %d):\n%s",
			len(rebuilt.String()), len(doc), firstDiff(doc, rebuilt.String()))
	}
}
