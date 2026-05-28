// parse.go — Markdown → (items + segments) parsers for Issues.md and Fixed.md.
//
// §11.4.93: parsing is byte-preserving. Each source file is decomposed into an
// ordered segment list; item segments additionally carry parsed fields. db→md
// reassembles from segments + items.body_md for a byte-identical round-trip.
package main

import (
	"regexp"
	"strings"
)

// issueHeadingRe matches an Issues.md item heading: `## <ID> — <title>` where
// <ID> is a ticket id (3 uppercase letters, dash, alnum suffix e.g. HXC-014b).
// The em-dash separator (` — `, U+2014) distinguishes item headings from
// structural headings like `## Prefix convention`.
var issueHeadingRe = regexp.MustCompile(`^## ([A-Z]{3}-[0-9A-Za-z]+)(?: \([^)]*\))? — (.+)$`)

// metaLineRe extracts `**Key:** value` metadata lines from an item body.
var metaLineRe = regexp.MustCompile(`(?m)^\*\*([A-Za-z-]+):\*\*[ \t]*(.*)$`)

// splitKeepNewlines splits text into lines, each retaining its trailing "\n"
// (the final element has no "\n" iff the source did not end with one). This
// lets us reassemble byte-identically.
func splitKeepNewlines(s string) []string {
	var lines []string
	start := 0
	for i := 0; i < len(s); i++ {
		if s[i] == '\n' {
			lines = append(lines, s[start:i+1])
			start = i + 1
		}
	}
	if start < len(s) {
		lines = append(lines, s[start:])
	}
	return lines
}

// parseIssues decomposes Issues.md into items + segments.
func parseIssues(content string) ([]item, []segment) {
	lines := splitKeepNewlines(content)
	var items []item
	var segs []segment
	seq := 0

	var rawBuf strings.Builder
	flushRaw := func() {
		if rawBuf.Len() == 0 {
			return
		}
		segs = append(segs, segment{Document: "Issues", Seq: seq, Kind: "raw", Raw: rawBuf.String()})
		seq++
		rawBuf.Reset()
	}

	i := 0
	for i < len(lines) {
		trimmed := strings.TrimRight(lines[i], "\n")
		m := issueHeadingRe.FindStringSubmatch(trimmed)
		if m == nil {
			rawBuf.WriteString(lines[i])
			i++
			continue
		}
		// Item heading found. Capture the block from this line up to the next
		// `## ` heading (any H2) or EOF.
		flushRaw()
		var block strings.Builder
		block.WriteString(lines[i])
		i++
		for i < len(lines) {
			lt := strings.TrimRight(lines[i], "\n")
			if strings.HasPrefix(lt, "## ") {
				break
			}
			block.WriteString(lines[i])
			i++
		}
		body := block.String()
		it := buildItem(m[1], m[2], body, "Issues")
		items = append(items, it)
		segs = append(segs, segment{Document: "Issues", Seq: seq, Kind: "item", AtmID: it.AtmID})
		seq++
	}
	flushRaw()
	return items, segs
}

// buildItem parses the metadata + description out of an item's raw body block.
func buildItem(id, titleRest, body, location string) item {
	it := item{
		AtmID:           id,
		Title:           titleRest,
		CurrentLocation: location,
		BodyMD:          body,
		Type:            "Task", // §11.4.16 lowest-stakes default when absent
		Status:          "Queued",
	}
	for _, mm := range metaLineRe.FindAllStringSubmatch(body, -1) {
		key := strings.ToLower(mm[1])
		val := strings.TrimSpace(mm[2])
		switch key {
		case "type":
			it.Type = normalizeType(val)
		case "status":
			it.Status = normalizeStatus(val)
		case "severity":
			it.Severity = val
		}
	}
	it.Description = deriveDescription(it.Title, body)
	return it
}

// deriveDescription returns a §11.4.91-compliant description (≥6 words OR ≥40
// chars). Deterministic rule: prefer the heading title; if that is too short,
// append the first non-metadata, non-separator prose sentence from the body.
func deriveDescription(title, body string) string {
	base := strings.TrimSpace(title)
	if wordCount(base) >= 6 || len(base) >= 40 {
		return base
	}
	// Find the first prose line in the body that is not a heading, not a
	// `**Key:**` metadata line, not a separator, not blank.
	for _, ln := range splitKeepNewlines(body) {
		t := strings.TrimSpace(ln)
		if t == "" || t == "---" || strings.HasPrefix(t, "## ") {
			continue
		}
		if metaLineRe.MatchString(ln) {
			continue
		}
		// Strip a leading inline `**Key:**` fragment if any remained.
		combined := base
		if combined != "" {
			combined += " — "
		}
		combined += firstSentence(t)
		return combined
	}
	return base
}

func firstSentence(s string) string {
	if idx := strings.IndexAny(s, ".!?"); idx >= 0 {
		return strings.TrimSpace(s[:idx+1])
	}
	return s
}

func wordCount(s string) int {
	return len(strings.Fields(s))
}

// normalizeType maps a raw `**Type:**` value onto the closed set
// {Bug, Feature, Task}. Unknown values default to Task (§11.4.16).
func normalizeType(v string) string {
	v = strings.TrimSpace(v)
	switch {
	case strings.EqualFold(v, "Bug"):
		return "Bug"
	case strings.EqualFold(v, "Feature"):
		return "Feature"
	case strings.EqualFold(v, "Task"):
		return "Task"
	default:
		return "Task"
	}
}

// closedStatuses is the §11.4.15/§11.4.21/§11.4.90 closed-set the schema CHECK
// enforces. normalizeStatus maps a raw `**Status:**` value onto it, tolerating
// trailing prose after the canonical token (e.g. "Fixed (→ Fixed.md) — see…").
var closedStatuses = []string{
	"Fixed (→ Fixed.md)",
	"Implemented (→ Fixed.md)",
	"Completed (→ Fixed.md)",
	"Obsolete (→ Fixed.md)",
	"Queued",
	"In progress",
	"Ready for testing",
	"In testing",
	"Reopened",
	"Operator-blocked",
}

func normalizeStatus(v string) string {
	v = strings.TrimSpace(v)
	// Exact closed-set match first.
	for _, s := range closedStatuses {
		if v == s {
			return s
		}
	}
	// Prefix match (closure values often carry trailing prose).
	for _, s := range closedStatuses {
		if strings.HasPrefix(v, s) {
			return s
		}
	}
	// Graceful fallback for non-closed-set inputs: keep the work moving by
	// mapping common synonyms, else Queued (a valid closed-set value).
	lv := strings.ToLower(v)
	switch {
	case strings.Contains(lv, "obsolete"):
		return "Obsolete (→ Fixed.md)"
	case strings.Contains(lv, "implemented"):
		return "Implemented (→ Fixed.md)"
	case strings.Contains(lv, "completed"):
		return "Completed (→ Fixed.md)"
	case strings.Contains(lv, "fixed"):
		return "Fixed (→ Fixed.md)"
	case strings.Contains(lv, "operator"):
		return "Operator-blocked"
	case strings.Contains(lv, "reopen"):
		return "Reopened"
	case strings.Contains(lv, "in testing"):
		return "In testing"
	case strings.Contains(lv, "ready"):
		return "Ready for testing"
	case strings.Contains(lv, "progress"):
		return "In progress"
	default:
		return "Queued"
	}
}

// fixedRowRe matches a Fixed.md closure table data row:
// `| <date> | <title> | <Type> | <Status> | <Round> | <Commit(s)> | <Evidence> |`
// The title cell holds `<ID>[ (...)]: <title>` (colon separator in Fixed.md).
var fixedRowRe = regexp.MustCompile(`^\| *([0-9]{4}-[0-9]{2}-[0-9]{2}) *\| *(.*?) *\| *([^|]*?) *\| *([^|]*?) *\| *([^|]*?) *\| *(.*?) *\| *(.*?) *\|\s*$`)

// fixedTitleIDRe pulls the leading ticket id out of a Fixed.md title cell.
var fixedTitleIDRe = regexp.MustCompile(`^([A-Z]{3}-[0-9A-Za-z]+)(?: \([^)]*\))?`)

// parseFixed decomposes Fixed.md (table form) into items + segments. Each
// closure data row becomes an item segment; all other lines (preamble, table
// header, blank separators, footer) are raw.
func parseFixed(content string) ([]item, []segment) {
	lines := splitKeepNewlines(content)
	var items []item
	var segs []segment
	seq := 0
	seen := map[string]int{} // atm_id -> dedup counter for synthetic ids

	var rawBuf strings.Builder
	flushRaw := func() {
		if rawBuf.Len() == 0 {
			return
		}
		segs = append(segs, segment{Document: "Fixed", Seq: seq, Kind: "raw", Raw: rawBuf.String()})
		seq++
		rawBuf.Reset()
	}

	for _, ln := range lines {
		trimmed := strings.TrimRight(ln, "\n")
		m := fixedRowRe.FindStringSubmatch(trimmed)
		if m == nil {
			rawBuf.WriteString(ln)
			continue
		}
		// A data row. Resolve its id from the title cell.
		titleCell := m[2]
		idm := fixedTitleIDRe.FindStringSubmatch(titleCell)
		var id string
		if idm != nil {
			id = idm[1]
		} else {
			// No ticket id (legacy narrative rows). Synthesize a stable,
			// document-unique key so the row still round-trips + validates.
			id = "FIX-" + m[1] // date-based
		}
		// Disambiguate duplicate ids within Fixed.md (same ticket closed in
		// multiple rows / no-id rows sharing a date).
		if n, ok := seen[id]; ok {
			seen[id] = n + 1
			id = id + "#" + itoa(n+1)
		} else {
			seen[id] = 0
		}

		flushRaw()
		it := item{
			AtmID:           id,
			Title:           strings.TrimSpace(titleCell),
			Type:            normalizeType(m[3]),
			Status:          normalizeStatus(m[4]),
			CurrentLocation: "Fixed",
			BodyMD:          ln, // verbatim row (with trailing newline)
		}
		it.Description = deriveDescription(it.Title, m[7])
		items = append(items, it)
		segs = append(segs, segment{Document: "Fixed", Seq: seq, Kind: "item", AtmID: it.AtmID})
		seq++
	}
	flushRaw()
	return items, segs
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	var b [20]byte
	i := len(b)
	for n > 0 {
		i--
		b[i] = byte('0' + n%10)
		n /= 10
	}
	if neg {
		i--
		b[i] = '-'
	}
	return string(b[i:])
}
