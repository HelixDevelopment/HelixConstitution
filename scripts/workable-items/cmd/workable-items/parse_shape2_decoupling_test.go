// parse_shape2_decoupling_test.go — §11.4.28 project-decoupling regression
// guard for the shape-2 `## [PREFIX-NNN] <title>` heading form.
//
// Forensic anchor: atmShape2HeadingRe / atmShape2CodeRe were hardcoded to
// `ATM-\d+` specifically — a consuming project registering a DIFFERENT ticket
// prefix (e.g. `[XYZ-NNN]`) would silently fail isATMCandidateHeading's
// shape-2 test, so its heading would only be recognised if it happened to
// ALSO match shape 1 or shape 3 (it wouldn't for a bare `## [XYZ-42] title`
// heading), producing a phantom sync divergence for that project. This test
// proves the tool now recognises ANY ≥2-char uppercase prefix without a code
// change, while ATM/SPK/BOB continue to parse identically (see
// atmosphere_test.go + fixed_real_test.go for the ATM-specific fixtures this
// change must not regress).
package main

import "testing"

// TestShape2HeadingRecognisesArbitraryPrefix proves isATMCandidateHeading +
// parseATMHeading work for a project prefix this tool has never seen before
// (no ATM/SPK/BOB literal anywhere in the fixture), demonstrating the shape-2
// detector is genuinely project-agnostic per §11.4.28(B).
func TestShape2HeadingRecognisesArbitraryPrefix(t *testing.T) {
	const fxXYZBlock = `## [XYZ-42] Widget catalog sync drops trailing entry

**Status:** In progress
**Type:** Bug
**Severity:** Medium
`
	items, _ := parseIssues(fxXYZBlock)
	it := findItem(t, items, "XYZ-42")
	if it.Title == "" {
		t.Fatalf("expected non-empty title for XYZ-42, got item=%+v", it)
	}
	if want := "Widget catalog sync drops trailing entry"; it.Title != want {
		t.Errorf("Title = %q, want %q", it.Title, want)
	}
	if it.Status != "In progress" {
		t.Errorf("Status = %q, want %q", it.Status, "In progress")
	}
}

// TestShape2HeadingCandidateDetectorArbitraryPrefix directly exercises the
// heading-shape detector (isATMCandidateHeading) with a non-ATM prefix,
// isolating the regex-level fix from the full parseIssues pipeline.
func TestShape2HeadingCandidateDetectorArbitraryPrefix(t *testing.T) {
	cases := []struct {
		heading string
		want    bool
	}{
		{"## [XYZ-42] Widget catalog sync drops trailing entry", true},
		{"## [ATM-238] Netflix login failure", true},   // pre-existing prefix still matches
		{"## [SPK-478] JetKVM remote control", true},    // pre-existing prefix still matches
		{"## [A-1] too-short prefix rejected", false},   // prefix MUST be >= 2 chars
		{"## [xyz-42] lowercase prefix rejected", false}, // prefix MUST be uppercase
	}
	for _, tc := range cases {
		got := isATMCandidateHeading(tc.heading)
		if got != tc.want {
			t.Errorf("isATMCandidateHeading(%q) = %v, want %v", tc.heading, got, tc.want)
		}
	}
}

// TestShape2CodeExtractionArbitraryPrefix proves atmShape2CodeRe extracts the
// bracket id + title for a non-ATM prefix, mirroring parseATMHeading's
// dispatch logic directly.
func TestShape2CodeExtractionArbitraryPrefix(t *testing.T) {
	id, title := parseATMHeading("## [XYZ-42] Widget catalog sync drops trailing entry")
	if id != "XYZ-42" {
		t.Errorf("id = %q, want %q", id, "XYZ-42")
	}
	if title != "Widget catalog sync drops trailing entry" {
		t.Errorf("title = %q, want %q", title, "Widget catalog sync drops trailing entry")
	}
}
