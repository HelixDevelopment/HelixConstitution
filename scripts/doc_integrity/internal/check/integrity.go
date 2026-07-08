package check

import (
	"fmt"

	"github.com/HelixDevelopment/HelixConstitution/scripts/doc_integrity/internal/model"
)

// Integrity implements DESIGN §3.5.
//
//   - INTEG-01 orphan ref: every dep / superseding reference must resolve to a
//     real record in the union of sources.
//   - INTEG-02 status/type (§11.4.33): a terminal Status must match the item Type
//     (Bug→Fixed, Feature→Implemented, Task→Completed).
//   - INTEG-03 location/status: a Fixed-location row must have a terminal status
//     and vice-versa (only for sources that carry a location field).
func Integrity(ds *Dataset) []Finding {
	ids, tickets := unionIndex(ds.All)
	var findings []Finding

	for _, r := range ds.All {
		// INTEG-01 orphan references.
		for _, dep := range r.Deps {
			if !ids[dep] && !tickets[dep] {
				findings = append(findings, Finding{
					Family:    "INTEGRITY",
					RuleID:    "INTEG-01",
					SourceID:  r.SourceID,
					Locator:   r.Locator,
					Message:   fmt.Sprintf("item %s references unknown dependency %q", idOrTicket(r), dep),
					Offending: []string{r.Locator},
				})
			}
		}
		if r.Superseding != "" && !ids[r.Superseding] && !tickets[r.Superseding] {
			findings = append(findings, Finding{
				Family:    "INTEGRITY",
				RuleID:    "INTEG-01",
				SourceID:  r.SourceID,
				Locator:   r.Locator,
				Message:   fmt.Sprintf("item %s references unknown superseding item %q", idOrTicket(r), r.Superseding),
				Offending: []string{r.Locator},
			})
		}

		// INTEG-02 status↔type (§11.4.33).
		if wantType, ok := terminalStatus(r.Status); ok && wantType != "" && r.Type != "" {
			if r.Type != wantType {
				findings = append(findings, Finding{
					Family:   "INTEGRITY",
					RuleID:   "INTEG-02",
					SourceID: r.SourceID,
					Locator:  r.Locator,
					Message: fmt.Sprintf("§11.4.33 violation: item %s Type=%q closed with Status=%q (expected Type=%q)",
						idOrTicket(r), r.Type, r.Status, wantType),
					Offending: []string{r.Locator},
				})
			}
		}

		// INTEG-03 location↔status.
		switch r.Location {
		case "Fixed":
			if r.Status != "" && !isTerminalStatus(r.Status) {
				findings = append(findings, Finding{
					Family:   "INTEGRITY",
					RuleID:   "INTEG-03",
					SourceID: r.SourceID,
					Locator:  r.Locator,
					Message: fmt.Sprintf("item %s is in Fixed but carries non-terminal Status=%q",
						idOrTicket(r), r.Status),
					Offending: []string{r.Locator},
				})
			}
		case "Issues":
			if isTerminalStatus(r.Status) {
				findings = append(findings, Finding{
					Family:   "INTEGRITY",
					RuleID:   "INTEG-03",
					SourceID: r.SourceID,
					Locator:  r.Locator,
					Message: fmt.Sprintf("item %s is in Issues but carries terminal Status=%q",
						idOrTicket(r), r.Status),
					Offending: []string{r.Locator},
				})
			}
		}
	}
	return findings
}

func unionIndex(records []model.Record) (ids, tickets map[string]bool) {
	ids = map[string]bool{}
	tickets = map[string]bool{}
	for _, r := range records {
		if r.ItemID != "" {
			ids[r.ItemID] = true
		}
		if r.Ticket != "" {
			tickets[r.Ticket] = true
		}
	}
	return ids, tickets
}
