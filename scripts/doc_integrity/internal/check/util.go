package check

import (
	"strconv"
	"strings"
	"time"

	"github.com/HelixDevelopment/HelixConstitution/scripts/doc_integrity/internal/model"
)

func dateStr(t *time.Time) string {
	if t == nil {
		return ""
	}
	return t.Format("2006-01-02")
}

// terminalStatus maps a §11.4.33 terminal Status literal → the Type it MUST
// carry ("" = any type, used by Obsolete). ok=false means the status is not a
// terminal closure status.
func terminalStatus(status string) (wantType string, ok bool) {
	switch strings.TrimSpace(status) {
	case "Fixed (→ Fixed.md)":
		return "Bug", true
	case "Implemented (→ Fixed.md)":
		return "Feature", true
	case "Completed (→ Fixed.md)":
		return "Task", true
	case "Obsolete (→ Fixed.md)":
		return "", true
	default:
		return "", false
	}
}

func isTerminalStatus(status string) bool {
	_, ok := terminalStatus(status)
	return ok
}

// compareVersionIDs compares two dotted-numeric IDs (e.g. "2.5.1" vs "2.5.10")
// segment-by-segment. Returns -1, 0, +1. Non-numeric segments compare
// lexically so it degrades gracefully on non-numeric IDs.
func compareVersionIDs(a, b string) int {
	as := strings.Split(a, ".")
	bs := strings.Split(b, ".")
	n := len(as)
	if len(bs) > n {
		n = len(bs)
	}
	for i := 0; i < n; i++ {
		var av, bv string
		if i < len(as) {
			av = as[i]
		}
		if i < len(bs) {
			bv = bs[i]
		}
		ai, aerr := strconv.Atoi(av)
		bi, berr := strconv.Atoi(bv)
		if aerr == nil && berr == nil {
			if ai != bi {
				if ai < bi {
					return -1
				}
				return 1
			}
			continue
		}
		if av != bv {
			if av < bv {
				return -1
			}
			return 1
		}
	}
	return 0
}

// indexBySource builds item-id and ticket lookup maps scoped to one source's
// records (dependency edges resolve within a plan first, DESIGN §3.3).
func indexBySource(records []model.Record) (byID, byTicket map[string]model.Record) {
	byID = map[string]model.Record{}
	byTicket = map[string]model.Record{}
	for _, r := range records {
		if r.ItemID != "" {
			if _, dup := byID[r.ItemID]; !dup {
				byID[r.ItemID] = r
			}
		}
		if r.Ticket != "" {
			if _, dup := byTicket[r.Ticket]; !dup {
				byTicket[r.Ticket] = r
			}
		}
	}
	return byID, byTicket
}
