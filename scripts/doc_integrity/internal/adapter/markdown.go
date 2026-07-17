package adapter

import (
	"bufio"
	"fmt"
	"os"
	"regexp"
	"strings"

	"github.com/HelixDevelopment/HelixConstitution/scripts/doc_integrity/internal/config"
	"github.com/HelixDevelopment/HelixConstitution/scripts/doc_integrity/internal/model"
)

// loadMarkdownTable parses a GFM pipe table. The FIRST table in the file whose
// header row contains all mapped source headers is used. Each data row → Record;
// the locator is path:line so a finding pinpoints the offending line (§11.4.6).
func loadMarkdownTable(src config.Source, path string) (LoadResult, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return LoadResult{}, fmt.Errorf("%w: read %q: %v", ErrSourceUnavailable, path, err)
	}
	lines := strings.Split(string(data), "\n")

	// Find the header line: a pipe row immediately followed by a separator row.
	headerLine, sepLine := -1, -1
	for i := 0; i+1 < len(lines); i++ {
		if isTableRow(lines[i]) && isSeparatorRow(lines[i+1]) {
			headerLine, sepLine = i, i+1
			break
		}
	}
	if headerLine < 0 {
		return LoadResult{}, fmt.Errorf("%w: no markdown table in %q", ErrSourceUnavailable, path)
	}

	header := splitTableRow(lines[headerLine])
	headerIndex := map[string]int{}
	for i, h := range header {
		headerIndex[normalizeHeader(h)] = i
	}
	logicalIdx := map[string]int{}
	for logical, h := range src.Columns {
		if idx, ok := headerIndex[normalizeHeader(h)]; ok {
			logicalIdx[logical] = idx
		}
	}

	var records []model.Record
	for i := sepLine + 1; i < len(lines); i++ {
		if !isTableRow(lines[i]) {
			break // table ends at first non-row line
		}
		cells := splitTableRow(lines[i])
		vals := map[string]string{}
		for logical, idx := range logicalIdx {
			if idx < len(cells) {
				vals[logical] = cells[idx]
			}
		}
		locator := fmt.Sprintf("%s:%d", src.Path, i+1)
		records = append(records, buildRecord(src, vals, locator))
	}
	return LoadResult{
		Records:        records,
		PresentColumns: presentFromHeaders(src.Columns, headerIndex),
		RawHeaders:     header,
	}, nil
}

func isTableRow(s string) bool {
	t := strings.TrimSpace(s)
	return strings.HasPrefix(t, "|")
}

var sepCellRe = regexp.MustCompile(`^:?-{1,}:?$`)

func isSeparatorRow(s string) bool {
	if !isTableRow(s) {
		return false
	}
	cells := splitTableRow(s)
	if len(cells) == 0 {
		return false
	}
	for _, c := range cells {
		if !sepCellRe.MatchString(strings.TrimSpace(c)) {
			return false
		}
	}
	return true
}

func splitTableRow(s string) []string {
	t := strings.TrimSpace(s)
	t = strings.TrimPrefix(t, "|")
	t = strings.TrimSuffix(t, "|")
	parts := strings.Split(t, "|")
	out := make([]string, len(parts))
	for i, p := range parts {
		out[i] = strings.TrimSpace(p)
	}
	return out
}

var (
	headingRe = regexp.MustCompile(`^#{2,4}\s+(.*)$`)
	ticketRe  = regexp.MustCompile(`\[([A-Z][A-Z0-9]*-\d+)\]`)
	sectionRe = regexp.MustCompile(`§?\s*([0-9]+(?:\.[0-9]+)*)`)
	metaRe    = regexp.MustCompile(`^\s*[-*]?\s*\*\*([A-Za-z][A-Za-z /-]*):\*\*\s*(.*)$`)
)

// loadMarkdownHeadings parses the Issues/Fixed heading format:
//
//	## §X.Y. [ATM-NNN] Title
//	**Type:** Bug
//	**Status:** Fixed (→ Fixed.md)
//	**Start:** 2026-10-05
//	**Deadline:** 2026-10-09
//	**Depends:** ATM-100, ATM-101
//
// Each H2–H4 heading with a ticket token starts a new record; the metadata
// lines until the next heading populate its fields.
func loadMarkdownHeadings(src config.Source, path string) (LoadResult, error) {
	f, err := os.Open(path)
	if err != nil {
		return LoadResult{}, fmt.Errorf("%w: read %q: %v", ErrSourceUnavailable, path, err)
	}
	defer f.Close()

	var records []model.Record
	var cur *model.Record
	var curVals map[string]string
	present := map[string]bool{}

	flush := func() {
		if cur == nil {
			return
		}
		rec := buildRecord(src, curVals, cur.Locator)
		// Preserve heading-derived identity that buildRecord may not see.
		if rec.Ticket == "" {
			rec.Ticket = cur.Ticket
		}
		if rec.ItemID == "" {
			rec.ItemID = cur.ItemID
		}
		if rec.Subject == "" {
			rec.Subject = cur.Subject
		}
		records = append(records, rec)
		cur = nil
	}

	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 0, 1024*1024), 8*1024*1024)
	lineNo := 0
	for sc.Scan() {
		lineNo++
		line := sc.Text()
		if m := headingRe.FindStringSubmatch(line); m != nil {
			title := strings.TrimSpace(m[1])
			if tk := ticketRe.FindStringSubmatch(title); tk != nil {
				flush()
				curVals = map[string]string{}
				rec := &model.Record{
					Ticket:  tk[1],
					Locator: fmt.Sprintf("%s:%d", src.Path, lineNo),
				}
				if sm := sectionRe.FindStringSubmatch(title); sm != nil {
					rec.ItemID = sm[1]
				}
				// subject = title minus the [TICKET] token and leading section number
				subj := ticketRe.ReplaceAllString(title, "")
				subj = strings.TrimSpace(regexp.MustCompile(`^§?\s*[0-9.]+\.?\s*`).ReplaceAllString(subj, ""))
				rec.Subject = subj
				cur = rec
				continue
			}
			// A non-ticket heading terminates the current record's metadata block.
			flush()
			continue
		}
		if cur == nil {
			continue
		}
		if mm := metaRe.FindStringSubmatch(line); mm != nil {
			key := strings.ToLower(strings.TrimSpace(mm[1]))
			val := strings.TrimSpace(mm[2])
			switch key {
			case "type":
				curVals["type"] = val
				present["type"] = true
			case "status":
				curVals["status"] = val
				present["status"] = true
			case "start", "start date":
				curVals["start"] = val
				present["start"] = true
			case "deadline", "due", "due date":
				curVals["deadline"] = val
				present["deadline"] = true
			case "depends", "depends on", "dependencies":
				curVals["deps"] = val
				present["deps"] = true
			case "scope":
				curVals["scope"] = val
				present["scope"] = true
			case "release", "version":
				curVals["release"] = val
			case "section":
				curVals["section"] = val
			case "location":
				curVals["location"] = val
			case "superseding", "superseding-item", "superseded-by":
				curVals["superseding"] = val
			}
		}
	}
	flush()
	if err := sc.Err(); err != nil {
		return LoadResult{}, fmt.Errorf("%w: scan %q: %v", ErrSourceUnavailable, path, err)
	}
	// ticket/item_id/subject always resolvable from headings.
	present["ticket"] = true
	present["item_id"] = true
	present["subject"] = true
	return LoadResult{Records: records, PresentColumns: present}, nil
}
