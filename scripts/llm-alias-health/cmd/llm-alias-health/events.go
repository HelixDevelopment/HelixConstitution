package main

// events.go -- the append-only JSONL event stream (§11.4.116: a
// real-time conductor<->autonomous-test-framework sync channel). Every
// probe attempt emits a probe_start event, then EITHER a probe_result
// event (with the evidence path a PASS/verdict cites, §11.4.69) or a
// probe_error event (execution itself failed) -- an entry with no
// terminal event for its probe_start is the mechanical signal that the
// probe never completed.

import (
	"encoding/json"
	"os"
	"time"
)

// Event is one append-only JSONL line.
type Event struct {
	TS       string `json:"ts"`
	Alias    string `json:"alias"`
	Event    string `json:"event"` // probe_start | probe_result | probe_error
	Status   string `json:"status,omitempty"`
	Detail   string `json:"detail,omitempty"`
	Evidence string `json:"evidence,omitempty"`
}

// appendEvent appends ev as one JSON line to path (creating it if
// absent). Failure to append is a soft error the caller logs but does
// not treat as probe failure (the health.json snapshot remains the
// authoritative current-state view even if the historical log write
// stumbles).
func appendEvent(path string, ev Event) error {
	if ev.TS == "" {
		ev.TS = time.Now().UTC().Format(time.RFC3339Nano)
	}
	f, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return err
	}
	defer f.Close()

	b, err := json.Marshal(ev)
	if err != nil {
		return err
	}
	b = append(b, '\n')
	_, err = f.Write(b)
	return err
}
