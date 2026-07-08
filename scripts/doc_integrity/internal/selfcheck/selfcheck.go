// Package selfcheck runs the embedded golden fixtures and asserts each expected
// verdict, proving the validator itself cannot bluff (§11.4.107(10)). A
// validator that PASSes a golden-bad fixture, or FAILs golden-good / the
// negative-control, is itself a bluff → selfcheck fails and the pre-build gate
// FAILs (DESIGN §4).
package selfcheck

import (
	"embed"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"

	"github.com/HelixDevelopment/HelixConstitution/scripts/doc_integrity/internal/runner"
)

//go:embed all:golden
var goldenFS embed.FS

type fixtureExpect struct {
	dir     string   // path under golden/
	verdict string   // PASS | FAIL
	rules   []string // rule ids that MUST appear (FAIL fixtures)
	note    string
}

// fixtures is the anti-bluff self-validation spec (§11.4.107(10)): golden-good +
// negative-control MUST PASS; one golden-bad per family MUST FAIL with its
// injected rule pinpointed. Neutering any expected-FAIL here is the paired-
// mutation (m2) that MUST break the CM-DOC-INTEGRITY-VALIDATION gate.
var fixtures = []fixtureExpect{
	{dir: "golden-good", verdict: "PASS", note: "clean checkset over all adapters"},
	{dir: "golden-bad/bad_dedup", verdict: "FAIL", rules: []string{"DEDUP-02"}, note: "same subject+scope duplicate w/ divergent timeline (NanoKVM-triplicate class)"},
	{dir: "golden-bad/bad_timeline", verdict: "FAIL", rules: []string{"TIME-02"}, note: "deadline-before-dependency"},
	{dir: "golden-bad/bad_crossdoc", verdict: "FAIL", rules: []string{"XDOC-01"}, note: "same ticket, divergent deadline across sources (MVP↔plan)"},
	{dir: "golden-bad/bad_integrity", verdict: "FAIL", rules: []string{"INTEG-02"}, note: "Feature closed as Fixed (§11.4.33) + orphan dep"},
	{dir: "golden-bad/bad_structural", verdict: "FAIL", rules: []string{"STRUCT-01", "STRUCT-02"}, note: "renamed required column + duplicate id"},
	{dir: "golden-bad-negative-control", verdict: "PASS", note: "~distinct same-subject NanoKVM tasks — MUST NOT false-positive"},
	// RC1/RC2 opt-in engine flags (V9-plan calibration) — load-bearing pairs.
	{dir: "golden-good-section-header", verdict: "PASS", note: "section_header_structural: true — a header row (no ticket/dates) is not an item; strip the engine flag → STRUCT-02+TIME-01b fire on it → this FAILs (m-RC1)"},
	{dir: "golden-good-ticket-epic", verdict: "PASS", note: "ticket_is_epic: true — an epic id legitimately spans sub-task rows; strip the engine flag → DEDUP-01 fires on the epic ticket → this FAILs (m-RC2)"},
	{dir: "golden-bad/bad_section_header_overreach", verdict: "FAIL", rules: []string{"STRUCT-02"}, note: "section_header_structural ON but a malformed id WITH ticket+dates is a real item → MUST still FAIL STRUCT-02 (no over-suppression)"},
	{dir: "golden-bad/bad_ticket_is_epic_still_dedup02", verdict: "FAIL", rules: []string{"DEDUP-02"}, note: "ticket_is_epic ON but same subject+scope w/ divergent deadline → MUST still FAIL DEDUP-02 (flag scopes only DEDUP-01)"},
}

// Run executes every fixture and returns (allPassed, humanReport).
func Run() (bool, string) {
	var sb strings.Builder
	ok := true
	sb.WriteString("doc-integrity selfcheck (golden fixtures — §11.4.107(10))\n")
	for _, fx := range fixtures {
		pass, detail := runOne(fx)
		status := "OK  "
		if !pass {
			status = "FAIL"
			ok = false
		}
		sb.WriteString(fmt.Sprintf("  [%s] %-34s %s\n", status, fx.dir, detail))
	}
	if ok {
		sb.WriteString("selfcheck PASS — validator provably distinguishes good from bad (and does not false-positive).\n")
	} else {
		sb.WriteString("selfcheck FAIL — the validator itself is bluffing; release-blocker.\n")
	}
	return ok, sb.String()
}

func runOne(fx fixtureExpect) (bool, string) {
	root, err := extract(fx.dir)
	if err != nil {
		return false, "extract error: " + err.Error()
	}
	defer os.RemoveAll(root)

	res, err := runner.Run(filepath.Join(root, "checkset.yaml"), root)
	if err != nil {
		return false, "runner error: " + err.Error()
	}
	if res.Verdict != fx.verdict {
		return false, fmt.Sprintf("expected %s got %s (%d findings): %s", fx.verdict, res.Verdict, len(res.Findings), fx.note)
	}
	// For FAIL fixtures, every expected rule must appear AND be pinpointed.
	for _, want := range fx.rules {
		found := false
		for _, f := range res.Findings {
			if f.RuleID == want {
				if len(f.Offending) == 0 && f.Locator == "" {
					return false, fmt.Sprintf("rule %s fired without a pinpoint (§11.4.6)", want)
				}
				found = true
				break
			}
		}
		if !found {
			return false, fmt.Sprintf("expected rule %s not among findings", want)
		}
	}
	return true, fx.note
}

// extract copies the embedded golden/<dir> subtree to a fresh temp dir so the
// runner reads real files with real relative paths.
func extract(dir string) (string, error) {
	root, err := os.MkdirTemp("", "docint-self-")
	if err != nil {
		return "", err
	}
	base := "golden/" + dir
	err = fs.WalkDir(goldenFS, base, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(base, p)
		if err != nil {
			return err
		}
		dst := filepath.Join(root, rel)
		if d.IsDir() {
			return os.MkdirAll(dst, 0o755)
		}
		data, err := goldenFS.ReadFile(p)
		if err != nil {
			return err
		}
		if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
			return err
		}
		return os.WriteFile(dst, data, 0o644)
	})
	if err != nil {
		os.RemoveAll(root)
		return "", err
	}
	return root, nil
}
