// Package adapter maps every supported source kind into the canonical
// []model.Record. New source kinds are new adapters registered by kind string —
// never a project fork (§11.4.28 DESIGN §1.2).
package adapter

import (
	"errors"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/HelixDevelopment/HelixConstitution/scripts/doc_integrity/internal/config"
	"github.com/HelixDevelopment/HelixConstitution/scripts/doc_integrity/internal/model"
	"github.com/HelixDevelopment/HelixConstitution/scripts/doc_integrity/internal/normalize"
)

// ErrSourceUnavailable signals the source file/DB could not be opened (missing
// file, unreadable xlsx, DB open error). The caller maps this to an honest
// SKIP-with-reason exit 3 (§11.4.3), NEVER a fake PASS (DESIGN §2).
var ErrSourceUnavailable = errors.New("source unavailable")

// LoadResult is what every adapter returns.
type LoadResult struct {
	Records        []model.Record
	PresentColumns map[string]bool // logical column name → found in source header
	RawHeaders     []string        // as-read header labels (diagnostics)
}

// Load dispatches to the adapter for the source's kind.
func Load(src config.Source, repoRoot string) (LoadResult, error) {
	path := src.Path
	if !filepath.IsAbs(path) {
		path = filepath.Join(repoRoot, path)
	}
	switch src.Kind {
	case "xlsx":
		return loadXLSX(src, path)
	case "markdown-table":
		return loadMarkdownTable(src, path)
	case "markdown-headings":
		return loadMarkdownHeadings(src, path)
	case "sqlite":
		return loadSQLite(src, path)
	default:
		return LoadResult{}, errors.New("adapter: unknown kind " + src.Kind)
	}
}

// buildRecord assembles a canonical Record from a logical-name → raw-value map,
// applying the source's gated/section markers and deterministic normalisation.
// It is shared by every adapter so field semantics are identical across kinds.
func buildRecord(src config.Source, vals map[string]string, locator string) model.Record {
	get := func(k string) string { return strings.TrimSpace(vals[k]) }

	r := model.Record{
		SourceID:    src.ID,
		ItemID:      get("item_id"),
		Ticket:      get("ticket"),
		Subject:     firstNonEmpty(get("name_en"), get("name_ru"), get("subject"), get("title"), get("name")),
		Type:        get("type"),
		Status:      get("status"),
		Release:     get("release"),
		Section:     get("section"),
		Location:    get("location"),
		Superseding: get("superseding"),
		Locator:     locator,
	}
	r.SubjectNorm = normalize.Subject(r.Subject)
	r.ScopeNorm = normalize.Scope(get("scope"))

	r.StartRaw = get("start")
	r.DeadRaw = get("deadline")
	r.Start = normalize.Date(r.StartRaw)
	r.Deadline = normalize.Date(r.DeadRaw)

	if deps := get("deps"); deps != "" {
		r.Deps = splitDeps(deps)
	}

	// GATED / section-header markers may live in the status, a dedicated column,
	// or any cell — we test the joined row text plus the explicit status.
	joined := strings.ToUpper(strings.Join(mapValues(vals), " "))
	if src.GatedMarker != "" && strings.Contains(joined, strings.ToUpper(src.GatedMarker)) {
		r.Gated = true
	}
	if src.SectionHeaderMarker != "" && strings.Contains(joined, strings.ToUpper(src.SectionHeaderMarker)) {
		r.SectionHeader = true
	}

	// §11.4.120 structural section-header detection (opt-in): some plans (e.g. an
	// xlsx whose section rows put a "4.1 <title>" grouping label in the id column
	// with no ticket and no dates) carry NO literal section-header marker. When
	// section_header_structural is set, a row whose ItemID fails the id_pattern
	// AND has no ticket AND no dates is a section/grouping header, not an item —
	// so STRUCT-02 (id discipline) and TIME-01b (missing-dates) skip it. A row
	// that fails the pattern but DOES carry a ticket OR a date is a real
	// (malformed) item and is NOT suppressed (the anti-over-suppression guard).
	if src.SectionHeaderStructural && !r.SectionHeader && src.IDPattern != "" &&
		r.ItemID != "" && r.Ticket == "" && !r.HasAnyDate() {
		if pat, err := regexp.Compile(src.IDPattern); err == nil && !pat.MatchString(r.ItemID) {
			r.SectionHeader = true
		}
	}
	return r
}

func firstNonEmpty(vals ...string) string {
	for _, v := range vals {
		if strings.TrimSpace(v) != "" {
			return strings.TrimSpace(v)
		}
	}
	return ""
}

// splitDeps tokenises a dependencies cell into individual dependency-ref tokens.
//
// It splits in TWO stages so a date value in the deps column is never fragmented
// into bogus refs (ATM-687): stage 1 splits on the "hard" separators that never
// occur inside a date rendering (comma / semicolon / pipe / whitespace); each
// coarse field is then tested by normalize.IsDateLike — a date-shaped field
// (e.g. the spreadsheet-rendered "3/6/2001") is DROPPED (a date is not a
// dependency reference), whereas a NON-date coarse field is stage-2 split on '/'
// so genuine slash-separated refs ("ATM-1/ATM-2") still tokenise. A dotted
// item-ref like "5.0.1" is not date-like, has no '/', and survives intact — so a
// genuinely-unresolved dependency is still flagged by INTEG-01 (§11.4.146).
func splitDeps(s string) []string {
	isCoarseSep := func(r rune) bool {
		return r == ',' || r == ';' || r == '|' || r == ' ' || r == '\t' || r == '\n'
	}
	isSlashSep := func(r rune) bool { return r == '/' }

	keep := func(f string) bool {
		f = strings.TrimSpace(f)
		return f != "" && !strings.EqualFold(f, "none") && f != "-" && f != "—"
	}

	var out []string
	for _, coarse := range strings.FieldsFunc(s, isCoarseSep) {
		coarse = strings.TrimSpace(coarse)
		if !keep(coarse) {
			continue
		}
		// A date/datetime in the deps column is not a dependency reference —
		// drop it whole so its digit groups never become bogus ref candidates.
		if normalize.IsDateLike(coarse) {
			continue
		}
		for _, piece := range strings.FieldsFunc(coarse, isSlashSep) {
			piece = strings.TrimSpace(piece)
			if keep(piece) && !normalize.IsDateLike(piece) {
				out = append(out, piece)
			}
		}
	}
	return out
}

func mapValues(m map[string]string) []string {
	out := make([]string, 0, len(m))
	for _, v := range m {
		out = append(out, v)
	}
	return out
}

// presentFromHeaders builds the PresentColumns map by testing which logical
// columns resolved to a real source header.
func presentFromHeaders(cols map[string]string, headerIndex map[string]int) map[string]bool {
	present := map[string]bool{}
	for logical, header := range cols {
		_, ok := headerIndex[normalizeHeader(header)]
		present[logical] = ok
	}
	return present
}

// normalizeHeader canonicalises a header label for tolerant matching (trim +
// collapse internal whitespace + lowercase). Header text is data, not code, so
// tolerant matching avoids brittle exact-string coupling.
func normalizeHeader(h string) string {
	return strings.ToLower(strings.Join(strings.Fields(h), " "))
}
