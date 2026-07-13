package check

import (
	"fmt"
	"regexp"
	"sort"

	"github.com/HelixDevelopment/HelixConstitution/scripts/doc_integrity/internal/model"
)

// Structural implements DESIGN §3.6.
//
//   - STRUCT-01 required columns: every configured required column must map to a
//     present source header (catches silent column drift that breaks every
//     downstream check).
//   - STRUCT-02 id discipline: item IDs unique + matching id_pattern; monotonic
//     within a section is an opt-in check (id_monotonic: true).
func Structural(ds *Dataset) []Finding {
	var findings []Finding
	for _, sd := range ds.Sources {
		findings = append(findings, struct01(sd)...)
		findings = append(findings, struct02(sd)...)
	}
	return findings
}

func struct01(sd SourceData) []Finding {
	required := sd.Src.RequiredColumns
	if len(required) == 0 {
		// default: every configured logical column is required to be present.
		for logical := range sd.Src.Columns {
			required = append(required, logical)
		}
	}
	sort.Strings(required)
	var findings []Finding
	for _, logical := range required {
		if !sd.Present[logical] {
			source := sd.Src.Columns[logical]
			findings = append(findings, Finding{
				Family:   "STRUCTURAL",
				RuleID:   "STRUCT-01",
				SourceID: sd.Src.ID,
				Locator:  sd.Src.Path,
				Message: fmt.Sprintf("required column %q (source header %q) is missing from %q",
					logical, source, sd.Src.ID),
				Offending: []string{logical},
			})
		}
	}
	return findings
}

func struct02(sd SourceData) []Finding {
	var findings []Finding
	var pat *regexp.Regexp
	if sd.Src.IDPattern != "" {
		if p, err := regexp.Compile(sd.Src.IDPattern); err == nil {
			pat = p
		}
	}

	seen := map[string][]string{} // item id → locators
	var order []model.Record
	for _, r := range sd.Records {
		if r.SectionHeader {
			continue // §11.4.120 — a section/grouping header is not an item; id discipline does not apply
		}
		if r.ItemID == "" {
			continue
		}
		if _, ok := seen[r.ItemID]; !ok {
			order = append(order, r)
		}
		seen[r.ItemID] = append(seen[r.ItemID], r.Locator)
		if pat != nil && !pat.MatchString(r.ItemID) {
			findings = append(findings, Finding{
				Family:   "STRUCTURAL",
				RuleID:   "STRUCT-02",
				SourceID: sd.Src.ID,
				Locator:  r.Locator,
				Message: fmt.Sprintf("item id %q does not match id_pattern %q in %q",
					r.ItemID, sd.Src.IDPattern, sd.Src.ID),
				Offending: []string{r.Locator},
			})
		}
	}
	// uniqueness
	ids := make([]string, 0, len(seen))
	for id := range seen {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	for _, id := range ids {
		locs := seen[id]
		if len(locs) > 1 {
			sort.Strings(locs)
			findings = append(findings, Finding{
				Family:    "STRUCTURAL",
				RuleID:    "STRUCT-02",
				SourceID:  sd.Src.ID,
				Locator:   locs[0],
				Message:   fmt.Sprintf("duplicate item id %q in %q (%v)", id, sd.Src.ID, locs),
				Offending: locs,
			})
		}
	}
	// monotonic (opt-in)
	if sd.Src.IDMonotonic {
		bySection := map[string][]model.Record{}
		var secOrder []string
		for _, r := range order {
			if _, ok := bySection[r.Section]; !ok {
				secOrder = append(secOrder, r.Section)
			}
			bySection[r.Section] = append(bySection[r.Section], r)
		}
		for _, sec := range secOrder {
			recs := bySection[sec]
			for i := 1; i < len(recs); i++ {
				if compareVersionIDs(recs[i-1].ItemID, recs[i].ItemID) > 0 {
					findings = append(findings, Finding{
						Family:   "STRUCTURAL",
						RuleID:   "STRUCT-02",
						SourceID: sd.Src.ID,
						Locator:  recs[i].Locator,
						Message: fmt.Sprintf("item id %q is out of monotonic order after %q in section %q of %q",
							recs[i].ItemID, recs[i-1].ItemID, sec, sd.Src.ID),
						Offending: []string{recs[i-1].Locator, recs[i].Locator},
					})
				}
			}
		}
	}
	return findings
}
