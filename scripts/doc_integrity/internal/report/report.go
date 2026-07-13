// Package report renders a verify Result as JSON + a human-readable report and
// defines the closed verdict/exit-code contract (DESIGN §2):
//
//	0 PASS  — zero findings, every source loaded
//	1 FAIL  — one or more findings
//	2 config error
//	3 SKIP  — a source was unavailable (honest SKIP-with-reason §11.4.3, never a fake PASS)
package report

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"time"

	"github.com/HelixDevelopment/HelixConstitution/scripts/doc_integrity/internal/check"
)

const (
	ExitPass = 0
	ExitFail = 1
	ExitCfg  = 2
	ExitSkip = 3
)

// Skip records a source that could not be loaded.
type Skip struct {
	SourceID string `json:"source_id"`
	Reason   string `json:"reason"`
}

// Result is the whole verify outcome.
type Result struct {
	Verdict      string          `json:"verdict"` // PASS | FAIL | SKIP
	ExitCode     int             `json:"exit_code"`
	Checkset     string          `json:"checkset"`
	GeneratedAt  string          `json:"generated_at"`
	SourceRows   map[string]int  `json:"source_rows"`
	Findings     []check.Finding `json:"findings"`
	Skips        []Skip          `json:"skips"`
	FamilyCounts map[string]int  `json:"family_counts"`
}

// Finalize sets verdict + exit code from findings/skips.
func (r *Result) Finalize() {
	r.GeneratedAt = time.Now().UTC().Format(time.RFC3339)
	r.FamilyCounts = map[string]int{}
	for _, f := range r.Findings {
		r.FamilyCounts[f.Family]++
	}
	switch {
	case len(r.Findings) > 0:
		r.Verdict, r.ExitCode = "FAIL", ExitFail
	case len(r.Skips) > 0:
		r.Verdict, r.ExitCode = "SKIP", ExitSkip
	default:
		r.Verdict, r.ExitCode = "PASS", ExitPass
	}
}

// WriteJSON writes the machine-readable result.
func (r *Result) WriteJSON(w io.Writer) error {
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	return enc.Encode(r)
}

// WriteHuman writes the operator-facing report.
func (r *Result) WriteHuman(w io.Writer) {
	fmt.Fprintf(w, "doc-integrity %s — checkset: %s\n", r.Verdict, r.Checkset)
	if len(r.SourceRows) > 0 {
		keys := sortedKeys(r.SourceRows)
		fmt.Fprintf(w, "sources loaded: ")
		for i, k := range keys {
			if i > 0 {
				fmt.Fprintf(w, ", ")
			}
			fmt.Fprintf(w, "%s(%d)", k, r.SourceRows[k])
		}
		fmt.Fprintln(w)
	}
	for _, s := range r.Skips {
		fmt.Fprintf(w, "SKIP  source %q: %s\n", s.SourceID, s.Reason)
	}
	if len(r.Findings) == 0 {
		fmt.Fprintln(w, "no integrity findings.")
		return
	}
	fmt.Fprintf(w, "\n%d finding(s):\n", len(r.Findings))
	for _, f := range r.Findings {
		fmt.Fprintf(w, "  [%s/%s] %s @ %s\n      %s\n", f.Family, f.RuleID, f.SourceID, f.Locator, f.Message)
	}
	fam := sortedKeys(r.FamilyCounts)
	fmt.Fprintf(w, "\nby family: ")
	for i, k := range fam {
		if i > 0 {
			fmt.Fprintf(w, ", ")
		}
		fmt.Fprintf(w, "%s=%d", k, r.FamilyCounts[k])
	}
	fmt.Fprintln(w)
}

// WriteEvidence writes both JSON + human report under an evidence directory
// (§11.4.69 captured-evidence artefact).
func (r *Result) WriteEvidence(dir string) error {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	jf, err := os.Create(filepath.Join(dir, "doc_integrity_result.json"))
	if err != nil {
		return err
	}
	defer jf.Close()
	if err := r.WriteJSON(jf); err != nil {
		return err
	}
	hf, err := os.Create(filepath.Join(dir, "doc_integrity_report.txt"))
	if err != nil {
		return err
	}
	defer hf.Close()
	r.WriteHuman(hf)
	return nil
}

func sortedKeys(m map[string]int) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}
