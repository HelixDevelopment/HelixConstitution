// parse.go — Markdown → (items + segments) parsers for Issues.md and Fixed.md.
//
// §11.4.93: parsing is byte-preserving. Each source file is decomposed into an
// ordered segment list; item segments additionally carry parsed fields. db→md
// reassembles from segments + items.body_md for a byte-identical round-trip.
package main

import (
	"crypto/sha1"
	"encoding/hex"
	"regexp"
	"strings"
)

// issueHeadingRe matches the canonical HelixCode Issues.md item heading:
// `## <ID> — <title>` where <ID> is a ticket id (3 uppercase letters, dash,
// alnum suffix e.g. HXC-014b). The em-dash separator (` — `, U+2014)
// distinguishes item headings from structural headings like
// `## Prefix convention`. This is the ORIGINAL, backward-compatible form and
// is recognised unconditionally (no Status-block requirement).
var issueHeadingRe = regexp.MustCompile(`^## ([A-Z]{3}-[0-9A-Za-z]+)(?: \([^)]*\))? — (.+)$`)

// atmBracketIDRe matches an ATMOSphere `[ATM-NNN]` bracket id appearing
// anywhere in a heading line, e.g. `## §GL CRITICAL — [ATM-238] Netflix …`.
var atmBracketIDRe = regexp.MustCompile(`\[(ATM-\d+)\]`)

// atmCandidateHeadingRe recognises ATMOSphere's real tracker heading SHAPES
// that MAY be workable items (subject to the Status-block test below). Two
// shapes are accepted, mirroring Herald's commons_workable/parser.go:
//
//	## §<letters>[ CRITICAL/…] — [ATM-NNN] <title>   (§-prefixed, em-dash title)
//	## §<letters> <title>                            (§-prefixed, space title)
//
// A heading matching this shape is treated as an item ONLY when its body
// carries a `**Status:**` metadata line; without one it is a section header
// (e.g. `## §FN. DEFERRED …`) and is skipped. Backward-compat note: the
// canonical `## ABC-123 — …` form is handled by issueHeadingRe FIRST and never
// reaches this path.
var atmCandidateHeadingRe = regexp.MustCompile(`^## §\S`)

// statusLineRe detects a `**Status:**` metadata line anywhere in an item body
// (it may follow blockquote prose, per the real ATMOSphere blocks). This is
// the section-header-vs-item discriminator for ATMOSphere-shaped headings.
var statusLineRe = regexp.MustCompile(`(?m)^\*\*Status:\*\*`)

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

	seenID := map[string]int{} // atm_id -> dedup counter (PK-collision guard)

	i := 0
	for i < len(lines) {
		trimmed := strings.TrimRight(lines[i], "\n")

		canonical := issueHeadingRe.FindStringSubmatch(trimmed)
		atmShaped := canonical == nil && atmCandidateHeadingRe.MatchString(trimmed)

		if canonical == nil && !atmShaped {
			rawBuf.WriteString(lines[i])
			i++
			continue
		}

		// Candidate item heading. Capture the block from this line up to the
		// next `## ` heading (any H2) or EOF — verbatim, for byte-identical
		// round-trip. body_md preserves the exact source bytes regardless of
		// which heading form recognised it.
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

		var it item
		if canonical != nil {
			// Canonical `## ABC-123 — title` — unchanged behaviour; recognised
			// unconditionally (no Status-block requirement), exactly as before.
			it = buildItem(canonical[1], canonical[2], body, "Issues")
		} else {
			// ATMOSphere-shaped `## §… [— [ATM-NNN]] title`. It is a workable
			// item ONLY if its body carries a `**Status:**` line; otherwise it
			// is a section header (`## §FN. DEFERRED …`) → keep it as raw so the
			// round-trip is unaffected.
			if !statusLineRe.MatchString(body) {
				rawBuf.WriteString(body)
				continue
			}
			id, title := parseATMHeading(trimmed)
			// PK-collision guard: ATMOSphere reuses §-letters across reopened
			// items, and derived ids could theoretically collide. The DB
			// identity is (atm_id, current_location), so disambiguate within
			// Issues here, matching parseFixed's seen-counter discipline.
			if n, ok := seenID[id]; ok {
				seenID[id] = n + 1
				id = id + "#" + itoa(n+1)
			} else {
				seenID[id] = 0
			}
			it = buildItem(id, title, body, "Issues")
		}

		// Close any preceding raw prose into its own segment BEFORE the item
		// segment, preserving source order for byte-identical regeneration.
		flushRaw()
		items = append(items, it)
		segs = append(segs, segment{Document: "Issues", Seq: seq, Kind: "item", AtmID: it.AtmID})
		seq++
	}
	flushRaw()
	return items, segs
}

// parseATMHeading extracts the (id, title) pair from an ATMOSphere-shaped H2
// heading line (the leading `## ` already present in `headingLine`). The id is
// a `[ATM-NNN]` bracket if present, else a stable sha1-derived id. The title is
// the human-readable text after the em-/hyphen-dash separator (or the §-code
// segment when there is no separator), with any `[ATM-NNN]` bracket stripped.
//
//	"## §GL CRITICAL — [ATM-238] Netflix login failure on D3" -> ("ATM-238", "Netflix login failure on D3")
//	"## §GZ — [ATM-240] 3-button navigation …"                -> ("ATM-240", "3-button navigation …")
//	"## §GS CRITICAL — Local-playback A/V quality …"          -> ("ATM-DERIVED-xxxxxxxx", "Local-playback A/V quality …")
//	"## §EU HDMI audio \"command error 1\" — total loss …"    -> ("ATM-DERIVED-xxxxxxxx", "HDMI audio …")
func parseATMHeading(headingLine string) (id, title string) {
	heading := strings.TrimSpace(strings.TrimPrefix(headingLine, "## "))

	if m := atmBracketIDRe.FindStringSubmatch(heading); m != nil {
		id = m[1]
	} else {
		id = deriveATMID(heading)
	}
	title = atmHeadingTitle(heading)
	return id, title
}

// atmHeadingTitle strips the §-code prefix segment and any [ATM-NNN] bracket
// from an ATMOSphere heading, returning the human-readable title.
func atmHeadingTitle(heading string) string {
	title := heading
	if idx := strings.Index(title, " — "); idx >= 0 {
		title = title[idx+len(" — "):]
	} else if idx := strings.Index(title, " - "); idx >= 0 {
		title = title[idx+len(" - "):]
	} else {
		// No dash separator (e.g. `§EU HDMI audio …`): drop the leading
		// `§<letters>` code token, keep the rest as the title.
		if fields := strings.SplitN(title, " ", 2); len(fields) == 2 && strings.HasPrefix(fields[0], "§") {
			title = fields[1]
		}
	}
	// Drop a leading/inline [ATM-NNN] bracket if it survived the split.
	title = atmBracketIDRe.ReplaceAllString(title, "")
	return strings.TrimSpace(title)
}

// deriveATMID produces a stable, deterministic id for a bracket-less
// ATMOSphere heading: "ATM-DERIVED-<8hexchars>" of the sha1 of the heading
// text (mirrors Herald commons_workable/parser.go deriveID).
func deriveATMID(heading string) string {
	sum := sha1.Sum([]byte(heading))
	return "ATM-DERIVED-" + hex.EncodeToString(sum[:])[:8]
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
