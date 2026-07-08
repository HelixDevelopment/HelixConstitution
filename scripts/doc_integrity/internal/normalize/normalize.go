// Package normalize provides deterministic (§11.4.50) normalisation helpers used
// by adapters and the DEDUP / CROSS-DOC check families.
//
// The functions are the discriminators that keep the ~10 legitimately-distinct
// NanoKVM tasks from being false-positive duplicates (DESIGN §3.2): a naive
// subject-substring dedup would raise ~10 false positives, so DEDUP keys on
// (subject_norm, scope_norm) — never bare subject substring (§11.4.6).
package normalize

import (
	"strings"
	"time"
	"unicode"
)

// Subject lowercases, collapses every run of non-letter/non-digit runes to a
// single space, and trims. It is Unicode-aware so RU and EN subjects normalise
// consistently. Deterministic: same input → same output across N runs.
func Subject(s string) string {
	var b strings.Builder
	prevSpace := false
	for _, r := range strings.ToLower(strings.TrimSpace(s)) {
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			b.WriteRune(r)
			prevSpace = false
			continue
		}
		if !prevSpace {
			b.WriteByte(' ')
			prevSpace = true
		}
	}
	return strings.TrimSpace(b.String())
}

// Scope normalises the task-scope discriminator identically to Subject. When a
// source has no explicit scope column the caller passes "" and scope_norm stays
// empty — an honest empty discriminator, never a guessed one (§11.4.6).
func Scope(s string) string { return Subject(s) }

// dateLayouts is the closed set of accepted date renderings. Order matters only
// for disambiguation; every layout is unambiguous on its own.
var dateLayouts = []string{
	"2006-01-02",
	"2006/01/02",
	"02.01.2006",
	"01/02/2006",
	"2006-1-2",
}

// Date parses a date cell into a *time.Time, returning nil for empty/unparseable
// input. It never guesses a partial date (§11.4.6): a value it cannot parse in
// full yields nil, which the timeline checks treat as "no committed date".
func Date(s string) *time.Time {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil
	}
	for _, layout := range dateLayouts {
		if t, err := time.Parse(layout, s); err == nil {
			return &t
		}
	}
	return nil
}

// dateTimeLayouts extends dateLayouts with the ISO/spreadsheet datetime
// renderings (a date carrying a time-of-day component). Kept separate from
// dateLayouts so the timeline Date() semantics (date-only) are unchanged; only
// IsDateLike consults the superset.
var dateTimeLayouts = []string{
	"2006-01-02T15:04:05",
	"2006-01-02 15:04:05",
	"2006-01-02T15:04:05Z07:00",
	"2006/01/02 15:04:05",
	"01/02/2006 15:04:05",
	// UNPADDED M/D/YYYY — the exact rendering excelize produces for a
	// spreadsheet date cell (V9 "Реалистичный" E156 → "3/6/2001", from the
	// serial date 2001-03-06). Go's "01/02/2006" requires ZERO-PADDED month +
	// day (getnum fixed=true) so it REJECTS "3/6/2001"; the unpadded "1/2/2006"
	// layout (getnum fixed=false) accepts BOTH "3/6/2001" AND "03/06/2001". Kept
	// in the IsDateLike-only superset so Date()/timeline semantics are unchanged
	// (ATM-687). This is the layout that actually makes the ATM-687 fix fire.
	"1/2/2006",
}

// IsDateLike reports whether the ENTIRE trimmed value is a date (or datetime)
// under the closed layout set — never a partial/heuristic match (§11.4.6). It is
// the discriminator that keeps a date value in the dependencies column (e.g. the
// spreadsheet-rendered "3/6/2001") from being fragmented into bogus dependency-
// ref candidates (ATM-687). A dotted item-ref like "5.0.1" or a ticket like
// "ATM-599" is NOT date-like: time.Parse rejects the out-of-range / non-year
// components, so those genuine dependency refs still tokenize + still get flagged.
func IsDateLike(s string) bool {
	s = strings.TrimSpace(s)
	if s == "" {
		return false
	}
	if Date(s) != nil {
		return true
	}
	for _, layout := range dateTimeLayouts {
		if _, err := time.Parse(layout, s); err == nil {
			return true
		}
	}
	return false
}

// Similarity returns a normalised [0,1] similarity ratio between two already-
// normalised subjects, using Levenshtein edit distance. Used only for the
// CROSS-DOC fuzzy fallback join when a ticket is absent; the threshold is
// consumer-calibrated on the project's own fixtures, never a literature
// constant (§11.4.6 / DESIGN §1.4).
func Similarity(a, b string) float64 {
	if a == b {
		return 1.0
	}
	if a == "" || b == "" {
		return 0.0
	}
	d := levenshtein(a, b)
	maxLen := len([]rune(a))
	if bl := len([]rune(b)); bl > maxLen {
		maxLen = bl
	}
	if maxLen == 0 {
		return 1.0
	}
	return 1.0 - float64(d)/float64(maxLen)
}

func levenshtein(a, b string) int {
	ra, rb := []rune(a), []rune(b)
	prev := make([]int, len(rb)+1)
	cur := make([]int, len(rb)+1)
	for j := range prev {
		prev[j] = j
	}
	for i := 1; i <= len(ra); i++ {
		cur[0] = i
		for j := 1; j <= len(rb); j++ {
			cost := 1
			if ra[i-1] == rb[j-1] {
				cost = 0
			}
			cur[j] = min3(cur[j-1]+1, prev[j]+1, prev[j-1]+cost)
		}
		prev, cur = cur, prev
	}
	return prev[len(rb)]
}

func min3(a, b, c int) int {
	m := a
	if b < m {
		m = b
	}
	if c < m {
		m = c
	}
	return m
}
