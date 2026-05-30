// fixed_real_test.go — coverage for parseFixed against the REAL ATMOSphere
// Fixed.md heading shapes (verbatim fixture blocks under testdata/, pasted from
// the live host file docs/Fixed.md on 2026-05-30).
//
// The real Fixed.md uses THREE distinct H2 item-heading shapes, every one of
// which carries a `**Status:**` block immediately beneath the H2 (before any
// `### ` subheading):
//
//	shape 1: `## <CODE>. <title> — ` + backtick-status   (letter-code + DOT, no §; dominant)
//	shape 2: `## [ATM-NNN] <code> — <title> — ` + status  (heading starts with [ATM-NNN])
//	shape 3: `## §<code> <title> — ` + status             (§-prefixed)
//
// Section headers (`## A. Tooling …`, `## AI/AK. …`) carry their `**Status:**`
// only under a NESTED `### ` subheading, so they MUST be discriminated out and
// kept raw. No mocks: parseFixed is the production parser; we assert on its
// real output read from the committed fixtures.
package main

import (
	"os"
	"strings"
	"testing"
)

func readFixture(t *testing.T, name string) string {
	t.Helper()
	b, err := os.ReadFile("testdata/" + name)
	if err != nil {
		t.Fatalf("read fixture %s: %v", name, err)
	}
	return string(b)
}

// onlyItem returns the single parsed item, failing if the count is not exactly 1.
func onlyItem(t *testing.T, content string) item {
	t.Helper()
	items, _ := parseFixed(content)
	if len(items) != 1 {
		t.Fatalf("expected exactly 1 item, got %d (%v)", len(items), itemIDs(items))
	}
	return items[0]
}

// --- Shape 1: letter-code + DOT, no §, backtick status. The dominant shape. ---

func TestParseFixed_Real_Shape1_GO(t *testing.T) {
	src := readFixture(t, "fx_shape1_go.md")
	it := onlyItem(t, src)
	if it.AtmID != "GO" {
		t.Errorf("atm_id: got %q want GO", it.AtmID)
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
	wantTitle := "2nd display (Arvus monitor) immediate-sleep on D3 — secondary-display keep-awake WakeLock (= completes unimplemented §JU-4)"
	if it.Title != wantTitle {
		t.Errorf("title:\n got %q\nwant %q", it.Title, wantTitle)
	}
	if strings.Contains(it.Title, "`") || strings.Contains(it.Title, "Fixed.md") {
		t.Errorf("title leaked the trailing status/backtick: %q", it.Title)
	}
	if it.BodyMD != src {
		t.Errorf("body_md not verbatim")
	}
}

// shape-1 with a hyphenated letter-code (`GS-2`) — the title must NOT be split
// on the code's hyphen, and the code must round-trip whole.
func TestParseFixed_Real_Shape1_DashCode(t *testing.T) {
	it := onlyItem(t, readFixture(t, "fx_shape1_dashcode.md"))
	if it.AtmID != "GS-2" {
		t.Errorf("atm_id: got %q want GS-2", it.AtmID)
	}
	wantTitle := "ATMOSphere VLC/MPV local 5.1 audio reaches HDMI as multichannel (not downmixed to stereo)"
	if it.Title != wantTitle {
		t.Errorf("title:\n got %q\nwant %q", it.Title, wantTitle)
	}
}

// shape-1 with a multi-char letter-code (`BJ-SOURCE`) whose title itself
// contains an inner ` — ` (which must be PRESERVED, not used as the split).
func TestParseFixed_Real_Shape1_InnerEmDash(t *testing.T) {
	it := onlyItem(t, readFixture(t, "fx_shape1_bjsource.md"))
	if it.AtmID != "BJ-SOURCE" {
		t.Errorf("atm_id: got %q want BJ-SOURCE", it.AtmID)
	}
	wantTitle := "Fix #135 — c2.rk.avc.encoder source-side disable (REQUIRES_REBUILD follow-up)"
	if it.Title != wantTitle {
		t.Errorf("title (inner em-dash must survive):\n got %q\nwant %q", it.Title, wantTitle)
	}
}

// --- Shape 2: heading STARTS with [ATM-NNN]; id from the bracket. ---

func TestParseFixed_Real_Shape2_BracketID(t *testing.T) {
	it := onlyItem(t, readFixture(t, "fx_shape2_atm248.md"))
	if it.AtmID != "ATM-248" {
		t.Errorf("atm_id: got %q want ATM-248", it.AtmID)
	}
	if it.CurrentLocation != "Fixed" {
		t.Errorf("current_location: got %q want Fixed", it.CurrentLocation)
	}
	if it.Status != "Completed (→ Fixed.md)" {
		t.Errorf("status: got %q want Completed (→ Fixed.md)", it.Status)
	}
	// Title is the human text after `] `, with the inner code (`D11`) kept,
	// trimmed at the trailing ` — ` + backtick-status boundary.
	wantTitle := "D11 — VideoOutputManager service binding regression"
	if it.Title != wantTitle {
		t.Errorf("title:\n got %q\nwant %q", it.Title, wantTitle)
	}
	if strings.Contains(it.Title, "[ATM-248]") {
		t.Errorf("title still carries the bracket id: %q", it.Title)
	}
}

// --- Shape 3: §-prefixed; id derived from the §-code (no bracket present). ---

func TestParseFixed_Real_Shape3_SectionSign(t *testing.T) {
	it := onlyItem(t, readFixture(t, "fx_shape3_fl.md"))
	// No [ATM-NNN] bracket → stable derived id from the §-code.
	if !strings.HasPrefix(it.AtmID, "ATM-DERIVED-") {
		t.Errorf("atm_id: got %q want an ATM-DERIVED-* id", it.AtmID)
	}
	if it.CurrentLocation != "Fixed" {
		t.Errorf("current_location: got %q want Fixed", it.CurrentLocation)
	}
	if it.Status != "Completed (→ Fixed.md)" {
		t.Errorf("status: got %q want Completed (→ Fixed.md)", it.Status)
	}
	wantTitle := "Phase 39.FL D3 post-flash cycle FAIL forensic + root-cause fixes"
	if it.Title != wantTitle {
		t.Errorf("title:\n got %q\nwant %q", it.Title, wantTitle)
	}
	if strings.HasPrefix(it.Title, "§") {
		t.Errorf("title still carries the §-prefix: %q", it.Title)
	}
}

// --- Section headers: Status lives under a NESTED ### — MUST be skipped. ---

func TestParseFixed_Real_SectionHeader_AIAK_Skipped(t *testing.T) {
	src := readFixture(t, "fx_section_AIAK.md")
	items, segs := parseFixed(src)
	if len(items) != 0 {
		t.Errorf("expected 0 items (## AI/AK. is a section header; Status is under ###), got %d (%v)",
			len(items), itemIDs(items))
	}
	var rebuilt strings.Builder
	for _, s := range segs {
		if s.Kind == "raw" {
			rebuilt.WriteString(s.Raw)
		}
	}
	if rebuilt.String() != src {
		t.Errorf("section header not preserved verbatim")
	}
}

func TestParseFixed_Real_SectionHeader_A_Skipped(t *testing.T) {
	items, _ := parseFixed(readFixture(t, "fx_section_A.md"))
	if len(items) != 0 {
		t.Errorf("expected 0 items (## A. Tooling … is a section header), got %d (%v)",
			len(items), itemIDs(items))
	}
}

// --- Full real file: count + byte-identical round-trip. ---

// TestParseFixed_Real_FullFile_Count asserts the dominant shapes are now all
// recognised (was 7/54 with the §-only regex; expect 42 real H2 items — every
// H2 whose Status sits before any nested ### — with 12 section headers skipped).
func TestParseFixed_Real_FullFile_Count(t *testing.T) {
	src, err := os.ReadFile("/tmp/atm_fixed_real.md")
	if err != nil {
		t.Skipf("real Fixed.md not available at /tmp/atm_fixed_real.md: %v", err)
	}
	items, segs := parseFixed(string(src))
	const wantItems = 42
	if len(items) != wantItems {
		t.Errorf("real Fixed.md item count: got %d want %d\nIDs: %v", len(items), wantItems, itemIDs(items))
	}
	for _, it := range items {
		if it.CurrentLocation != "Fixed" {
			t.Errorf("%s: current_location %q != Fixed", it.AtmID, it.CurrentLocation)
		}
		// A clean title is non-empty and is not merely the trailing closure
		// status string (the prior 7/54 bug). NOTE: titles legitimately CAN
		// contain inner ` — `, inline `code` spans, and §-anchor cross-refs
		// (e.g. `## JD. §EW … investigation outcome`), so those are NOT leaks.
		if strings.TrimSpace(it.Title) == "" {
			t.Errorf("%s: empty title", it.AtmID)
		}
		if strings.HasPrefix(it.Title, "`Fixed (") || strings.HasPrefix(it.Title, "`Completed (") ||
			strings.HasPrefix(it.Title, "`Implemented (") || strings.HasPrefix(it.Title, "`Obsolete (") {
			t.Errorf("%s: title is just a status string (the 7/54 mangling bug): %q", it.AtmID, it.Title)
		}
		// The heading's OWN [ATM-NNN] bracket must not survive in the title.
		if strings.Contains(it.Title, "[ATM-2") {
			t.Errorf("%s: title leaked its own [ATM-NNN] bracket: %q", it.AtmID, it.Title)
		}
	}
	// Byte-identical round-trip on the REAL file.
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
	if rebuilt.String() != string(src) {
		t.Errorf("real Fixed.md round-trip NOT byte-identical (got %d bytes, want %d):\n%s",
			len(rebuilt.String()), len(src), firstDiff(string(src), rebuilt.String()))
	}
}
