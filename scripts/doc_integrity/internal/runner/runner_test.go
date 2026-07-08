package runner

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/HelixDevelopment/HelixConstitution/scripts/doc_integrity/internal/report"
)

func write(t *testing.T, dir, name, content string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(dir, name), []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

// A clean single-source checkset must PASS (exit 0).
func TestRunPass(t *testing.T) {
	dir := t.TempDir()
	write(t, dir, "plan.md", "| № | Ticket | Task | Deadline |\n|---|---|---|---|\n| 1.1 | ATM-1 | Alpha | 2026-08-10 |\n")
	write(t, dir, "checkset.yaml", `
schema_version: 1
sources:
  - id: plan
    kind: markdown-table
    path: plan.md
    columns:
      item_id: "№"
      ticket: "Ticket"
      name_en: "Task"
      deadline: "Deadline"
`)
	res, err := Run(filepath.Join(dir, "checkset.yaml"), dir)
	if err != nil {
		t.Fatal(err)
	}
	if res.Verdict != "PASS" || res.ExitCode != report.ExitPass {
		t.Fatalf("want PASS/0, got %s/%d findings=%+v", res.Verdict, res.ExitCode, res.Findings)
	}
}

// A missing source is a SKIP (exit 3), NEVER a fake PASS (§11.4.3).
func TestRunSkipOnMissingSource(t *testing.T) {
	dir := t.TempDir()
	write(t, dir, "checkset.yaml", `
schema_version: 1
sources:
  - id: plan
    kind: markdown-table
    path: does_not_exist.md
    columns:
      item_id: "№"
`)
	res, err := Run(filepath.Join(dir, "checkset.yaml"), dir)
	if err != nil {
		t.Fatal(err)
	}
	if res.Verdict != "SKIP" || res.ExitCode != report.ExitSkip {
		t.Fatalf("missing source must SKIP/3 (honest, not fake PASS), got %s/%d", res.Verdict, res.ExitCode)
	}
	if len(res.Skips) != 1 {
		t.Fatalf("want 1 skip, got %d", len(res.Skips))
	}
}

// A malformed checkset is a config error (non-nil err → exit 2).
func TestRunConfigError(t *testing.T) {
	dir := t.TempDir()
	write(t, dir, "checkset.yaml", "sources: []\n")
	if _, err := Run(filepath.Join(dir, "checkset.yaml"), dir); err == nil {
		t.Fatal("empty-sources checkset must be a config error")
	}
}
