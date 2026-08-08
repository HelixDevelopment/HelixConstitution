// evidence_fixture_test.go — shared fixture helpers for the HXC-224 record-time
// closure-evidence guard.
//
// WHY THIS FILE EXISTS (§11.4.120 reconciliation, not a weakening).
//
// Before HXC-224, `close` / `obsolete-details` / `subtask-status` /
// `move --evidence` accepted any non-empty string, so tests across this package
// seeded closures with plausible-looking but non-existent literals
// (`docs/qa/WIT-200/run.md`, `qa-results/x.log`, …). The record-time guard now
// REFUSES those — which is the guard working, not a regression: every one of
// those fixtures was recording a closure whose captured proof could not be
// produced.
//
// The correct response per §11.4.120 is to RECONCILE the fixtures (make the
// artefact real) — never to fake-pass the guard, weaken it to a tautology, or
// revert the fix. These helpers keep each test's ORIGINAL repo-relative literal
// intact — it is still what lands in the DB and in the rendered Markdown those
// tests assert on — while materialising the artefact it names under a temp root
// that $PWD points at, so the guard resolves it exactly as it resolves a real
// `docs/qa/<run-id>/…` path in the live tree (the HXC-201 anchoring the guard
// and the HXC-217 validator share).
package main

import (
	"os"
	"path/filepath"
	"testing"
)

// newEvidenceRoot creates a temp directory and points $PWD at it for the
// duration of the test, so repo-relative evidence literals materialised under it
// resolve through resolveInvocationRelative. Call ONCE per test, then pass the
// returned root to every materialiseEvidence call in that test — a second root
// would silently orphan the artefacts created under the first.
func newEvidenceRoot(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	t.Setenv("PWD", root)
	return root
}

// materialiseEvidence creates <root>/<rel> as a NON-EMPTY artefact and returns
// `rel` unchanged, so call sites read as
// `"--evidence", materialiseEvidence(t, root, "docs/qa/WIT-200/run.md")` and the
// literal recorded in the DB is exactly the one the test asserted on before.
func materialiseEvidence(t *testing.T, root, rel string) string {
	t.Helper()
	abs := filepath.Join(root, rel)
	if err := os.MkdirAll(filepath.Dir(abs), 0o755); err != nil {
		t.Fatalf("materialise evidence dir for %q: %v", rel, err)
	}
	if err := os.WriteFile(abs, []byte("captured runtime evidence for "+rel+"\n"), 0o644); err != nil {
		t.Fatalf("materialise evidence %q: %v", rel, err)
	}
	return rel
}
