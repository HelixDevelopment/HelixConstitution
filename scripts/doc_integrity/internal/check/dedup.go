package check

import (
	"fmt"
	"sort"
	"strings"

	"github.com/HelixDevelopment/HelixConstitution/scripts/doc_integrity/internal/model"
)

// Dedup implements DESIGN §3.2.
//
//   - DEDUP-01 (ticket): within one source, a ticket value on >1 record (same
//     ticket + same location) is a duplicate.
//   - DEDUP-02 (subject+scope): records grouped by the configured key_fields
//     (default (subject_norm, scope_norm)); a group of size >1 is a duplicate.
//     scope_norm is the discriminator that keeps genuinely-distinct same-subject
//     tasks (the ~10 NanoKVM rows, DESIGN §3.2) in SEPARATE groups → not flagged;
//     bare subject-substring dedup is FORBIDDEN (§11.4.6) precisely because it
//     false-positives on them.
func Dedup(ds *Dataset) []Finding {
	var findings []Finding
	allow := allowSet(ds.Cfg.Dedup.Allowlist)

	for _, sd := range ds.Sources {
		findings = append(findings, dedup01Ticket(sd)...)
		findings = append(findings, dedup02SubjectScope(ds, sd, allow)...)
	}
	return findings
}

func dedup01Ticket(sd SourceData) []Finding {
	if sd.Src.TicketIsEpic {
		// §11.4.120 — this source's ticket column is an EPIC id that legitimately
		// spans many sub-task rows; ticket-on-many-rows is NOT a duplicate here.
		// DEDUP-02 (subject+scope) still runs and still catches a real dup feature.
		return nil
	}
	groups := map[string][]model.Record{}
	order := []string{}
	for _, r := range sd.Records {
		if r.Ticket == "" {
			continue
		}
		key := r.Ticket + "\x00" + r.Location
		if _, ok := groups[key]; !ok {
			order = append(order, key)
		}
		groups[key] = append(groups[key], r)
	}
	var findings []Finding
	for _, key := range order {
		g := groups[key]
		if len(g) < 2 {
			continue
		}
		locs := locatorsOf(g)
		findings = append(findings, Finding{
			Family:   "DEDUP",
			RuleID:   "DEDUP-01",
			SourceID: sd.Src.ID,
			Locator:  g[0].Locator,
			Message: fmt.Sprintf("ticket %q appears on %d records within source %q (%s)",
				g[0].Ticket, len(g), sd.Src.ID, strings.Join(locs, ", ")),
			Offending: locs,
		})
	}
	return findings
}

func dedup02SubjectScope(ds *Dataset, sd SourceData, allow map[string]bool) []Finding {
	fields := ds.Cfg.Dedup.KeyFields
	exempt := exemptStatusSet(ds.Cfg.Dedup.ExemptStatuses)
	groups := map[string][]model.Record{}
	order := []string{}
	for _, r := range sd.Records {
		if strings.TrimSpace(r.SubjectNorm) == "" {
			continue // no subject to key on
		}
		// §11.4.90 / §11.4.214 / §11.4.201(1): a RETIRED record (a duplicate
		// closed via the sanctioned `Obsolete`/duplicate-of path, or any other
		// consumer-declared terminal-retired status) keeps the canonical
		// item's subject BY CONSTRUCTION. Grouping it with its live canonical
		// sibling reports DEDUP-02 on the CORRECT resolution of a duplicate —
		// a false-positive refusal. Skip the RECORD, never the group: two
		// non-exempt (live) records sharing the key still group and still
		// FAIL, so the check is narrowed, not weakened (golden-bad
		// bad_dedup_exempt_status_still_dedup02 is the standing proof).
		if len(exempt) > 0 && exempt[normalizeStatusKey(r.Status)] {
			continue
		}
		key := dedupKey(r, fields)
		if allow[key] {
			continue // consumer-declared legitimately-distinct
		}
		if _, ok := groups[key]; !ok {
			order = append(order, key)
		}
		groups[key] = append(groups[key], r)
	}
	var findings []Finding
	for _, key := range order {
		g := groups[key]
		if len(g) < 2 {
			continue
		}
		locs := locatorsOf(g)
		msg := fmt.Sprintf("%d records share key (%s)=%q in source %q",
			len(g), strings.Join(fields, "+"), key, sd.Src.ID)
		if divergentTimelines(g) {
			// the operator's exact named defect: one feature, divergent timelines.
			msg += " with DIVERGENT timelines — a duplicate feature carrying inconsistent dates"
		}
		findings = append(findings, Finding{
			Family:    "DEDUP",
			RuleID:    "DEDUP-02",
			SourceID:  sd.Src.ID,
			Locator:   g[0].Locator,
			Message:   msg + " (" + strings.Join(locs, ", ") + ")",
			Offending: locs,
		})
	}
	return findings
}

func dedupKey(r model.Record, fields []string) string {
	parts := make([]string, len(fields))
	for i, f := range fields {
		parts[i] = fieldValue(r, f)
	}
	return strings.Join(parts, "|")
}

func fieldValue(r model.Record, field string) string {
	switch field {
	case "subject_norm":
		return r.SubjectNorm
	case "scope_norm":
		return r.ScopeNorm
	case "ticket":
		return r.Ticket
	case "item_id":
		return r.ItemID
	case "type":
		return r.Type
	case "status":
		return r.Status
	case "release":
		return r.Release
	case "section":
		return r.Section
	default:
		return ""
	}
}

// normalizeStatusKey folds a status value for the exempt-status compare:
// trimmed + lowercased + internal whitespace collapsed. Deterministic
// (§11.4.50) and forgiving of incidental spacing between the checkset's
// declared vocabulary and the source's stored value, WITHOUT loosening into a
// substring match (§11.4.201(7)(a) — match the value, never a carrier of it).
func normalizeStatusKey(s string) string {
	return strings.ToLower(strings.Join(strings.Fields(s), " "))
}

// exemptStatusSet builds the normalized lookup for DedupCfg.ExemptStatuses.
// An empty/blank entry is dropped so a stray list item can never exempt the
// records whose status is empty (which is most rows in most sources) — that
// would silently disarm DEDUP-02 for the whole source.
func exemptStatusSet(list []string) map[string]bool {
	m := map[string]bool{}
	for _, e := range list {
		k := normalizeStatusKey(e)
		if k == "" {
			continue
		}
		m[k] = true
	}
	return m
}

func allowSet(list []string) map[string]bool {
	m := map[string]bool{}
	for _, e := range list {
		m[strings.TrimSpace(e)] = true
	}
	return m
}

func locatorsOf(g []model.Record) []string {
	out := make([]string, 0, len(g))
	for _, r := range g {
		out = append(out, r.Locator)
	}
	sort.Strings(out)
	return out
}

func divergentTimelines(g []model.Record) bool {
	var seenStart, seenDead string
	first := true
	for _, r := range g {
		s, d := dateStr(r.Start), dateStr(r.Deadline)
		if first {
			seenStart, seenDead = s, d
			first = false
			continue
		}
		if s != seenStart || d != seenDead {
			return true
		}
	}
	return false
}
