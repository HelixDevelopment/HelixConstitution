// Package store defines the scheduled-work data model and its persistence.
//
// The scheduled-work-engine is a DECOUPLED, project-agnostic service
// (constitution §11.4.28): it hardcodes NO consumer-specific data. Every
// item field is generic. Consumers register their own tags / sources at
// runtime via the public API.
package store

import "time"

// Status is the closed set of scheduled-work-item lifecycle states.
// "uncertain" and "blocked" and "overdue" are the states a REMINDER must
// re-verify before an agent reports the work as done (constitution
// §11.4.6 no-guessing, §11.4.108 verify-before-report).
type Status string

const (
	StatusScheduled  Status = "scheduled"   // queued, not started
	StatusInProgress Status = "in-progress" // actively being worked
	StatusBlocked    Status = "blocked"     // waiting on an external dependency
	StatusUncertain  Status = "uncertain"   // outcome unverified — needs confirmation
	StatusDone       Status = "done"        // completed, verified
	StatusOverdue    Status = "overdue"     // past DueAt, still open (derived on read)
	StatusCancelled  Status = "cancelled"   // abandoned
)

// ValidStatuses is the authoritative closed set (excluding the derived
// "overdue", which is computed on read from DueAt and never stored).
var ValidStatuses = map[Status]bool{
	StatusScheduled:  true,
	StatusInProgress: true,
	StatusBlocked:    true,
	StatusUncertain:  true,
	StatusDone:       true,
	StatusCancelled:  true,
}

// IsValidStatus reports whether s is a settable status.
func IsValidStatus(s Status) bool { return ValidStatuses[s] }

// Item is a single scheduled-work / reminder entry.
type Item struct {
	ID          string     `json:"id"`
	Title       string     `json:"title"`
	Description string     `json:"description,omitempty"`
	Status      Status     `json:"status"`
	DueAt       *time.Time `json:"due_at,omitempty"`
	Tags        []string   `json:"tags,omitempty"`
	Source      string     `json:"source,omitempty"` // consumer-supplied origin label
	Notes       string     `json:"notes,omitempty"`
	CreatedAt   time.Time  `json:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at"`
}

// EffectiveStatus returns the item's status with the derived "overdue"
// applied: an open item whose DueAt has passed reads as overdue without
// mutating the stored status (§11.4.6 — derived, not guessed).
func (it Item) EffectiveStatus(now time.Time) Status {
	if it.DueAt != nil && now.After(*it.DueAt) {
		switch it.Status {
		case StatusScheduled, StatusInProgress, StatusBlocked, StatusUncertain:
			return StatusOverdue
		}
	}
	return it.Status
}

// NeedsVerification reports whether a REMINDER arriving for this item
// requires the agent to confirm the real outcome before reporting done
// (blocked / uncertain / overdue open work).
func (it Item) NeedsVerification(now time.Time) bool {
	switch it.EffectiveStatus(now) {
	case StatusBlocked, StatusUncertain, StatusOverdue:
		return true
	}
	return false
}
