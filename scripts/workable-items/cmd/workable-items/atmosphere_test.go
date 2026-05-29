// atmosphere_test.go — coverage for the ATMOSphere real tracker heading format.
//
// These fixtures are VERBATIM excerpts of ATMOSphere's actual docs/Issues.md
// (fetched from the live tracker), exercising the three real heading shapes:
//
//	## §<letters>[ CRITICAL] — [ATM-NNN] <title>   (bracketed id, em-dash title)
//	## §<letters> — [ATM-NNN] <title>              (bracketed id, bare dash)
//	## §<letters>[ CRITICAL] — <title>             (no bracket → derived id)
//	## §<letters> <title>                          (no dash, no bracket → derived)
//
// plus section headers (no `**Status:**` block) that MUST be skipped, plus the
// canonical `## ABC-123 — title` form which MUST keep parsing unchanged.
//
// No mocks: parseIssues is the production parser; we assert on its real output.
package main

import (
	"strings"
	"testing"
)

// findItem returns the parsed item with the given atm_id, or fails the test.
func findItem(t *testing.T, items []item, atmID string) item {
	t.Helper()
	for _, it := range items {
		if it.AtmID == atmID {
			return it
		}
	}
	t.Fatalf("no item with atm_id %q in %d parsed items: %v", atmID, len(items), itemIDs(items))
	return item{}
}

func itemIDs(items []item) []string {
	ids := make([]string, len(items))
	for i, it := range items {
		ids[i] = it.AtmID
	}
	return ids
}

func hasItem(items []item, atmID string) bool {
	for _, it := range items {
		if it.AtmID == atmID {
			return true
		}
	}
	return false
}

// fxGLBlock is the VERBATIM §GL / ATM-238 block (heading + metadata) from the
// real ATMOSphere Issues.md.
const fxGLBlock = `## §GL CRITICAL — [ATM-238] Netflix login failure on D3 (User report 2026-05-28)

**Status:** Operator-blocked
**Type:** Bug
**Severity:** Critical — Netflix unusable; first-login blocked

**Operator report:** Cannot login to Netflix.
`

// fxGMBlock — §GM / ATM-239, em-dash + bracketed id, Status "In progress".
const fxGMBlock = `## §GM CRITICAL — [ATM-239] Apple TV + Prime Video subtitles on PRIMARY not 2nd display (User report 2026-05-28)

**Status:** In progress
**Type:** Bug
**Severity:** Critical — subtitles mis-routed
`

// fxGZBlock — §GZ / ATM-240, bare dash + bracketed id, Status "Queued".
const fxGZBlock = `## §GZ — [ATM-240] 3-button navigation: Home and Recent-apps buttons sometimes do nothing (User report 2026-05-29)

**Status:** Queued
**Type:** Bug
**Severity:** High — core navigation unreliable
`

// fxGSNoBracket — §GS, em-dash title but NO [ATM-NNN] bracket → derived id.
const fxGSNoBracket = `## §GS CRITICAL — Local-playback A/V quality: VLC fork 4K-glitch (User report 2026-05-28)

**Status:** In progress
**Type:** Bug
**Severity:** Critical — local Movies playback degraded
`

// fxEUNoDash — §EU, no em-dash separator at all (dash is mid-title), no
// bracket → derived id. Tests the "drop leading §code token" title path.
const fxEUNoDash = `## §EU HDMI audio total loss persists across reboot (D3 critical)

**Status:** In progress
**Type:** Bug
**Severity:** C (Critical)
`

// fxSectionFN — §FN. section header. The trailing dot after the letters is the
// section-header idiom; crucially it has NO **Status:** block, so it MUST be
// skipped (treated as raw prose, not a workable item).
const fxSectionFN = `## §FN. DEFERRED FEATURE-BRANCH CLUSTER — Sonos + NanoKVM

Some descriptive prose for the section, no metadata block here.
`

// fxSectionPlain — a plain structural heading with no Status block → skipped.
const fxSectionPlain = `## Document conventions

This section explains the document conventions. No metadata.
`

// fxCanonical — the ORIGINAL HelixCode form. MUST still parse unchanged.
const fxCanonical = `## HXC-014b — Some canonical item title that is plenty long for the floor

**Status:** Queued
**Type:** Task
`

func TestParseATM_BracketedID_GL(t *testing.T) {
	items, segs := parseIssues(fxGLBlock)
	if len(items) != 1 {
		t.Fatalf("expected 1 item, got %d (%v)", len(items), itemIDs(items))
	}
	it := items[0]
	if it.AtmID != "ATM-238" {
		t.Errorf("atm_id: got %q want ATM-238", it.AtmID)
	}
	if it.Status != "Operator-blocked" {
		t.Errorf("status: got %q want Operator-blocked", it.Status)
	}
	if it.Type != "Bug" {
		t.Errorf("type: got %q want Bug", it.Type)
	}
	if !strings.Contains(it.Title, "Netflix login failure on D3") {
		t.Errorf("title: got %q, expected to contain the human title", it.Title)
	}
	if strings.Contains(it.Title, "[ATM-238]") || strings.Contains(it.Title, "§GL") {
		t.Errorf("title still carries the id/§-prefix: %q", it.Title)
	}
	// body_md must preserve the verbatim block (byte-identical round-trip).
	if it.BodyMD != fxGLBlock {
		t.Errorf("body_md not verbatim:\n got: %q\nwant: %q", it.BodyMD, fxGLBlock)
	}
	// Exactly one item segment, no spurious raw segment from the heading.
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

func TestParseATM_BracketedID_GM_GZ(t *testing.T) {
	for _, tc := range []struct {
		name, src, id, status, typ string
	}{
		{"GM/ATM-239 em-dash", fxGMBlock, "ATM-239", "In progress", "Bug"},
		{"GZ/ATM-240 bare-dash", fxGZBlock, "ATM-240", "Queued", "Bug"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			items, _ := parseIssues(tc.src)
			if len(items) != 1 {
				t.Fatalf("expected 1 item, got %d (%v)", len(items), itemIDs(items))
			}
			it := items[0]
			if it.AtmID != tc.id {
				t.Errorf("atm_id: got %q want %q", it.AtmID, tc.id)
			}
			if it.Status != tc.status {
				t.Errorf("status: got %q want %q", it.Status, tc.status)
			}
			if it.Type != tc.typ {
				t.Errorf("type: got %q want %q", it.Type, tc.typ)
			}
		})
	}
}

func TestParseATM_NoBracket_DerivedID(t *testing.T) {
	for _, tc := range []struct {
		name, src, titleContains string
	}{
		{"GS em-dash, no bracket", fxGSNoBracket, "Local-playback A/V quality"},
		{"EU no dash, no bracket", fxEUNoDash, "HDMI audio total loss"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			items, _ := parseIssues(tc.src)
			if len(items) != 1 {
				t.Fatalf("expected 1 item, got %d (%v)", len(items), itemIDs(items))
			}
			it := items[0]
			if !strings.HasPrefix(it.AtmID, "ATM-DERIVED-") {
				t.Errorf("expected derived id, got %q", it.AtmID)
			}
			if !strings.Contains(it.Title, tc.titleContains) {
				t.Errorf("title %q does not contain %q", it.Title, tc.titleContains)
			}
			if strings.HasPrefix(strings.TrimSpace(it.Title), "§") {
				t.Errorf("title still leads with the §-code: %q", it.Title)
			}
		})
	}
}

// Derived id is STABLE across runs for the same heading text.
func TestParseATM_DerivedID_Stable(t *testing.T) {
	a, _ := parseIssues(fxGSNoBracket)
	b, _ := parseIssues(fxGSNoBracket)
	if len(a) != 1 || len(b) != 1 {
		t.Fatalf("expected 1 item each, got %d / %d", len(a), len(b))
	}
	if a[0].AtmID != b[0].AtmID {
		t.Errorf("derived id not stable: %q vs %q", a[0].AtmID, b[0].AtmID)
	}
}

// Section headers (no **Status:** block) MUST be skipped, even when they carry
// the ATMOSphere §-prefix shape (`## §FN. …`).
func TestParseATM_SectionHeaders_Skipped(t *testing.T) {
	for _, tc := range []struct {
		name, src string
	}{
		{"§FN. section header", fxSectionFN},
		{"plain structural heading", fxSectionPlain},
	} {
		t.Run(tc.name, func(t *testing.T) {
			items, segs := parseIssues(tc.src)
			if len(items) != 0 {
				t.Errorf("expected 0 items (section header), got %d (%v)", len(items), itemIDs(items))
			}
			// It must survive as raw prose so the round-trip is byte-identical.
			var rebuilt strings.Builder
			for _, s := range segs {
				if s.Kind == "raw" {
					rebuilt.WriteString(s.Raw)
				}
			}
			if rebuilt.String() != tc.src {
				t.Errorf("section header not preserved verbatim as raw:\n got: %q\nwant: %q", rebuilt.String(), tc.src)
			}
		})
	}
}

// The canonical `## ABC-123 — title` form MUST still parse, unchanged, with NO
// Status-block requirement (it never had one).
func TestParseATM_CanonicalForm_Unchanged(t *testing.T) {
	items, _ := parseIssues(fxCanonical)
	if len(items) != 1 {
		t.Fatalf("expected 1 item, got %d (%v)", len(items), itemIDs(items))
	}
	it := items[0]
	if it.AtmID != "HXC-014b" {
		t.Errorf("atm_id: got %q want HXC-014b", it.AtmID)
	}
	if it.Status != "Queued" || it.Type != "Task" {
		t.Errorf("status/type: got %q/%q want Queued/Task", it.Status, it.Type)
	}
}

// A mixed document with ALL shapes interleaved: backward-compat + ATMOSphere
// items + a skipped section header — and the full text must round-trip
// byte-identically through the (item body + raw segment) decomposition.
func TestParseATM_MixedDocument_RoundTrip(t *testing.T) {
	preamble := "# ATMOSphere Issues\n\nSome preamble prose.\n\n"
	doc := preamble + fxSectionPlain + "\n" + fxCanonical + "\n" + fxGLBlock + "\n" + fxGZBlock + "\n" + fxSectionFN + "\n" + fxGSNoBracket

	items, segs := parseIssues(doc)

	// Items: HXC-014b, ATM-238, ATM-240, and one derived (§GS). NOT the two
	// section headers.
	if !hasItem(items, "HXC-014b") {
		t.Errorf("canonical HXC-014b missing")
	}
	if !hasItem(items, "ATM-238") {
		t.Errorf("ATM-238 missing")
	}
	if !hasItem(items, "ATM-240") {
		t.Errorf("ATM-240 missing")
	}
	derivedCount := 0
	for _, it := range items {
		if strings.HasPrefix(it.AtmID, "ATM-DERIVED-") {
			derivedCount++
		}
	}
	if derivedCount != 1 {
		t.Errorf("expected exactly 1 derived-id item (§GS), got %d", derivedCount)
	}
	if len(items) != 4 {
		t.Errorf("expected 4 items, got %d (%v)", len(items), itemIDs(items))
	}

	// Byte-identical reassembly: walk segments in seq order, emitting raw
	// verbatim and item bodies from the matching item.BodyMD.
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
