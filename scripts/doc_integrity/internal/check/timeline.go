package check

import (
	"fmt"
	"sort"

	"github.com/HelixDevelopment/HelixConstitution/scripts/doc_integrity/internal/model"
)

// Timeline implements DESIGN §3.3.
//
//   - TIME-01  intra-row: start ≤ deadline for non-GATED rows.
//   - TIME-01b no-dates: a schedulable planned row (source maps a deadline col,
//     row has an item id) with NO dates AND no GATED marker is a finding.
//   - TIME-02  dependency ordering: for edge A→B (B depends on A),
//     A.deadline ≤ B.start (no deadline-before-dependency — the operator's
//     named defect).
//   - TIME-03  cycle: a cycle in the dependency DAG is a finding.
//   - TIME-04  section span: a section-header row's [start,deadline] window must
//     contain every member row (opt-in — only fires when a source declares a
//     section_header_marker).
func Timeline(ds *Dataset) []Finding {
	var findings []Finding
	for _, sd := range ds.Sources {
		findings = append(findings, time01(sd)...)
		findings = append(findings, time02and03(sd)...)
		findings = append(findings, time04Section(sd)...)
	}
	return findings
}

func time01(sd SourceData) []Finding {
	var findings []Finding
	scheduleSource := sd.Src.Columns["deadline"] != "" || sd.Present["deadline"]
	for _, r := range sd.Records {
		if r.Gated || r.SectionHeader {
			continue
		}
		if r.Start != nil && r.Deadline != nil {
			if r.Start.After(*r.Deadline) {
				findings = append(findings, Finding{
					Family:   "TIMELINE",
					RuleID:   "TIME-01",
					SourceID: sd.Src.ID,
					Locator:  r.Locator,
					Message: fmt.Sprintf("start %s is after deadline %s for item %s",
						dateStr(r.Start), dateStr(r.Deadline), idOrTicket(r)),
					Offending: []string{r.Locator},
				})
			}
			continue
		}
		// TIME-01b: a planned schedulable row must carry dates OR be GATED.
		if scheduleSource && r.ItemID != "" && !r.HasAnyDate() {
			findings = append(findings, Finding{
				Family:   "TIMELINE",
				RuleID:   "TIME-01b",
				SourceID: sd.Src.ID,
				Locator:  r.Locator,
				Message: fmt.Sprintf("planned item %s has no start/deadline and is not marked GATED",
					idOrTicket(r)),
				Offending: []string{r.Locator},
			})
		}
	}
	return findings
}

func time02and03(sd SourceData) []Finding {
	byID, byTicket := indexBySource(sd.Records)
	resolve := func(ref string) (model.Record, bool) {
		if r, ok := byID[ref]; ok {
			return r, true
		}
		if r, ok := byTicket[ref]; ok {
			return r, true
		}
		return model.Record{}, false
	}

	var findings []Finding
	// TIME-02 dependency ordering.
	for _, b := range sd.Records {
		for _, dep := range b.Deps {
			a, ok := resolve(dep)
			if !ok {
				continue // orphan handled by INTEG-01
			}
			if a.Deadline != nil && b.Start != nil && a.Deadline.After(*b.Start) {
				findings = append(findings, Finding{
					Family:   "TIMELINE",
					RuleID:   "TIME-02",
					SourceID: sd.Src.ID,
					Locator:  b.Locator,
					Message: fmt.Sprintf("item %s starts %s before its dependency %s finishes %s (deadline-before-dependency)",
						idOrTicket(b), dateStr(b.Start), dep, dateStr(a.Deadline)),
					Offending: []string{b.Locator, a.Locator},
				})
			}
		}
	}

	// TIME-03 cycle detection (DFS over dep edges).
	color := map[string]int{} // 0=white 1=gray 2=black, keyed by node key
	nodeKey := func(r model.Record) string {
		if r.ItemID != "" {
			return "id:" + r.ItemID
		}
		return "tk:" + r.Ticket
	}
	var cyclePath []string
	var dfs func(r model.Record) bool
	dfs = func(r model.Record) bool {
		k := nodeKey(r)
		color[k] = 1
		for _, dep := range r.Deps {
			a, ok := resolve(dep)
			if !ok {
				continue
			}
			ak := nodeKey(a)
			switch color[ak] {
			case 1:
				cyclePath = []string{idOrTicket(r), dep}
				return true
			case 0:
				if dfs(a) {
					return true
				}
			}
		}
		color[k] = 2
		return false
	}
	// deterministic node order
	nodes := append([]model.Record(nil), sd.Records...)
	sort.SliceStable(nodes, func(i, j int) bool { return nodes[i].Locator < nodes[j].Locator })
	for _, r := range nodes {
		if r.ItemID == "" && r.Ticket == "" {
			continue
		}
		if color[nodeKey(r)] == 0 {
			if dfs(r) {
				findings = append(findings, Finding{
					Family:    "TIMELINE",
					RuleID:    "TIME-03",
					SourceID:  sd.Src.ID,
					Locator:   r.Locator,
					Message:   fmt.Sprintf("dependency cycle detected involving %v", cyclePath),
					Offending: cyclePath,
				})
				break // one cycle report per source is enough to block
			}
		}
	}
	return findings
}

func time04Section(sd SourceData) []Finding {
	if sd.Src.SectionHeaderMarker == "" {
		return nil // opt-in
	}
	var findings []Finding
	// map section label → header record (if any)
	headers := map[string]model.Record{}
	for _, r := range sd.Records {
		if r.SectionHeader && r.Section != "" && r.HasDates() {
			headers[r.Section] = r
		}
	}
	for _, r := range sd.Records {
		if r.SectionHeader || r.Section == "" || !r.HasDates() {
			continue
		}
		h, ok := headers[r.Section]
		if !ok {
			continue
		}
		if r.Start.Before(*h.Start) || r.Deadline.After(*h.Deadline) {
			findings = append(findings, Finding{
				Family:   "TIMELINE",
				RuleID:   "TIME-04",
				SourceID: sd.Src.ID,
				Locator:  r.Locator,
				Message: fmt.Sprintf("item %s [%s..%s] falls outside its section %q window [%s..%s]",
					idOrTicket(r), dateStr(r.Start), dateStr(r.Deadline), r.Section,
					dateStr(h.Start), dateStr(h.Deadline)),
				Offending: []string{r.Locator, h.Locator},
			})
		}
	}
	return findings
}

func idOrTicket(r model.Record) string {
	if r.ItemID != "" && r.Ticket != "" {
		return r.ItemID + " (" + r.Ticket + ")"
	}
	if r.ItemID != "" {
		return r.ItemID
	}
	if r.Ticket != "" {
		return r.Ticket
	}
	return r.SubjectNorm
}
