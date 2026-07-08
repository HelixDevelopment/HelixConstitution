package check

import (
	"fmt"
	"sort"
	"strings"

	"github.com/HelixDevelopment/HelixConstitution/scripts/doc_integrity/internal/model"
	"github.com/HelixDevelopment/HelixConstitution/scripts/doc_integrity/internal/normalize"
)

// CrossDoc implements DESIGN §3.4 (XDOC-01). It joins the SAME feature across
// sources — by ticket, falling back to a subject_norm fuzzy match at the
// consumer-calibrated threshold — and, for any feature present in ≥2 sources,
// asserts the compared fields (timeline / status / type) are identical. This is
// the operator's "MVP timelines MUST be consistent with V9" rule, with the
// configured authoritative source named in the finding.
func CrossDoc(ds *Dataset) []Finding {
	compare := map[string]bool{}
	for _, c := range ds.Cfg.CrossdocJoin.Compare {
		compare[c] = true
	}
	authoritative := ds.Cfg.CrossdocJoin.Authoritative

	groups := joinCrossDoc(ds)
	var findings []Finding
	for _, grp := range groups {
		if distinctSources(grp) < 2 {
			continue
		}
		if compare["timeline"] {
			findings = append(findings, compareField(grp, "timeline", authoritative, timelineOf)...)
		}
		if compare["status"] {
			findings = append(findings, compareField(grp, "status", authoritative, func(r model.Record) string { return strings.TrimSpace(r.Status) })...)
		}
		if compare["type"] {
			findings = append(findings, compareField(grp, "type", authoritative, func(r model.Record) string { return strings.TrimSpace(r.Type) })...)
		}
	}
	sort.SliceStable(findings, func(i, j int) bool { return findings[i].Message < findings[j].Message })
	return findings
}

type xdocGroup struct {
	key     string
	members []model.Record
}

func joinCrossDoc(ds *Dataset) []xdocGroup {
	byTicket := map[string][]model.Record{}
	var ticketless []model.Record
	for _, r := range ds.All {
		if r.Ticket != "" {
			byTicket[r.Ticket] = append(byTicket[r.Ticket], r)
		} else if r.SubjectNorm != "" {
			ticketless = append(ticketless, r)
		}
	}

	var groups []xdocGroup
	// deterministic ticket order
	tickets := make([]string, 0, len(byTicket))
	for t := range byTicket {
		tickets = append(tickets, t)
	}
	sort.Strings(tickets)
	for _, t := range tickets {
		groups = append(groups, xdocGroup{key: "ticket:" + t, members: byTicket[t]})
	}

	// Fuzzy subject fallback for ticketless records (only when configured).
	if ds.Cfg.CrossdocJoin.Fallback == "subject_norm" {
		threshold := ds.Cfg.Thresholds.SubjectSimilarity
		used := make([]bool, len(ticketless))
		for i := 0; i < len(ticketless); i++ {
			if used[i] {
				continue
			}
			cluster := []model.Record{ticketless[i]}
			used[i] = true
			for j := i + 1; j < len(ticketless); j++ {
				if used[j] {
					continue
				}
				if normalize.Similarity(ticketless[i].SubjectNorm, ticketless[j].SubjectNorm) >= threshold {
					cluster = append(cluster, ticketless[j])
					used[j] = true
				}
			}
			if len(cluster) > 1 {
				groups = append(groups, xdocGroup{key: "subject:" + ticketless[i].SubjectNorm, members: cluster})
			}
		}
	}
	return groups
}

func distinctSources(g xdocGroup) int {
	set := map[string]bool{}
	for _, r := range g.members {
		set[r.SourceID] = true
	}
	return len(set)
}

func timelineOf(r model.Record) string {
	s, d := dateStr(r.Start), dateStr(r.Deadline)
	if s == "" && d == "" {
		return ""
	}
	return s + ".." + d
}

// compareField reports a finding when a comparable field's non-empty values
// disagree across the group's members. Empty values are ignored (a source that
// does not carry a field must not manufacture a divergence).
func compareField(g xdocGroup, field, authoritative string, valOf func(model.Record) string) []Finding {
	type sv struct {
		val string
		rec model.Record
	}
	var present []sv
	for _, r := range g.members {
		v := valOf(r)
		if v != "" {
			present = append(present, sv{v, r})
		}
	}
	if len(present) < 2 {
		return nil
	}
	// all-equal?
	base := present[0].val
	allEqual := true
	for _, p := range present[1:] {
		if p.val != base {
			allEqual = false
			break
		}
	}
	if allEqual {
		return nil
	}
	// Build one finding naming every divergent (source:locator=value) + authority.
	var parts []string
	sort.SliceStable(present, func(i, j int) bool { return present[i].rec.SourceID < present[j].rec.SourceID })
	var offending []string
	authNote := ""
	for _, p := range present {
		parts = append(parts, fmt.Sprintf("%s@%s=%q", p.rec.SourceID, p.rec.Locator, p.val))
		offending = append(offending, p.rec.Locator)
		if authoritative != "" && p.rec.SourceID == authoritative {
			authNote = fmt.Sprintf(" [authoritative %s=%q]", authoritative, p.val)
		}
	}
	return []Finding{{
		Family:    "CROSS-DOC",
		RuleID:    "XDOC-01",
		SourceID:  present[0].rec.SourceID,
		Locator:   present[0].rec.Locator,
		Message:   fmt.Sprintf("%s divergence for %s: %s%s", field, g.key, strings.Join(parts, " vs "), authNote),
		Offending: offending,
	}}
}
