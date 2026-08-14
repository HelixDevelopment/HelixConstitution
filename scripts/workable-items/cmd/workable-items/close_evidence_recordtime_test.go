// close_evidence_recordtime_test.go — HXC-224 §11.4.115 RED-baseline +
// standing §11.4.135 regression guard for the RECORD-TIME half of the
// closure-evidence invariant.
//
// THE DEFECT (reproduced on the pre-fix source, 2026-08-08, against a COPY of
// the live records — never the live DB, §9.2):
//
//	go run -C constitution/scripts/workable-items ./cmd/workable-items close \
//	  HXC-159 --db /tmp/hxc224_repro/copy.db --status fixed \
//	  --evidence /tmp/DEFINITELY_NOT_A_REAL_PATH/x.log
//	close: moved HXC-159 Issues→Fixed (status=Fixed (→ Fixed.md), evidence=/tmp/DEFINITELY_NOT_A_REAL_PATH/x.log)
//	EXIT=0
//	sqlite> HXC-159|Fixed (→ Fixed.md)|Fixed
//	sqlite> HXC-159|Fixed|/tmp/DEFINITELY_NOT_A_REAL_PATH/x.log
//
// The closure landed in the single source of truth citing captured proof that
// never existed. The HXC-217 validator (unresolvableClosureEvidence, sync.go)
// catches it LATER, at `validate` time, if a sweep ever runs — but the
// "refused at the moment of recording" half was unimplemented. The evidence
// path is what makes a closure FALSIFIABLE; a closure recorded with a
// fabricated one is a §11.4 PASS-bluff written directly into the tracker
// (§11.4.5 / §11.4.69 / §11.4.123 / §11.4.226 evidence-class-at-closure).
//
// §11.4.115 POLARITY SWITCH — one source, two roles:
//
//	RED_MODE=1  reproduce-and-assert-the-defect-present. Run against the
//	            PRE-FIX artifact: close ACCEPTS the fabricated path and the
//	            mutation LANDS. Captured proof the guard is not a synthetic
//	            failure the fix was then written to agree with.
//	RED_MODE=0  (the default this file ships with, post-fix) the standing
//	            GREEN regression guard: the fabricated path is REFUSED with a
//	            non-zero exit AND nothing is mutated.
//
// The committed default is 0 because this guard runs inside the standing suite
// on every build (§11.4.135) — that IS the post-fix flip, not a deviation.
//
// §1.1 PAIRED MUTATION: replace the body of checkEvidencePath (evidence.go)
// with `return nil` — every refusal case below FAILs, proving the guard is not
// a tautology. Restore → GREEN.
//
// Every test drives the REAL subcommands + the REAL SQLite driver against a
// fresh temp DB; it NEVER touches the live docs/workable_items.db.
package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// hxc224RedMode reads the §11.4.115 polarity switch for THIS guard.
//
// It deliberately does NOT reuse the package's pre-existing redMode() helper
// (gap_dual_representation_test.go), whose default is RED — that helper's
// GREEN-only companions t.Skip() when RED is in force, so an unset RED_MODE
// leaves them un-run. This guard is a §11.4.135 STANDING regression guard: it
// must execute on every plain `go test ./...`, so its default is the GREEN arm.
// That default IS the post-fix flip §11.4.115 prescribes, not a deviation —
// `RED_MODE=1` still selects the reproduce-the-defect arm, exactly as the
// package convention does.
//
// An unrecognised value is a hard stop rather than a silent default: a mis-typed
// polarity that quietly ran the GREEN arm while the operator believed they were
// reproducing the defect would be a §11.4.201 false-null at the harness layer.
func hxc224RedMode(t *testing.T) bool {
	t.Helper()
	switch v := os.Getenv("RED_MODE"); v {
	case "1":
		return true
	case "", "0":
		return false
	default:
		t.Fatalf("RED_MODE=%q is not a recognised polarity (want 1 = reproduce-the-defect, 0/unset = standing guard)", v)
		return false
	}
}

// realEvidenceFile writes a non-empty artefact and returns its absolute path —
// the shape a genuine closure cites.
func realEvidenceFile(t *testing.T) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), "EVIDENCE.md")
	if err := os.WriteFile(p, []byte("captured runtime evidence\n"), 0o644); err != nil {
		t.Fatalf("write evidence artefact: %v", err)
	}
	return p
}

// seedOpenItem creates one Issues item through the REAL add subcommand.
func seedOpenItem(t *testing.T, dbPath, id string) {
	t.Helper()
	if code := addCmd([]string{
		"--db", dbPath, "--id", id,
		"--title", "record-time closure-evidence probe " + id,
		"--description", "a sufficiently long description that clears the §11.4.91 floor",
		"Bug", "High",
	}); code != exitOK {
		t.Fatalf("add %s exited %d, want %d", id, code, exitOK)
	}
}

// itemLocation returns (status, current_location) for an item, or ("","") when
// the row is absent.
func itemLocation(t *testing.T, dbPath, id string) (string, string) {
	t.Helper()
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	var status, loc string
	row := db.QueryRow(`SELECT status, current_location FROM items WHERE atm_id=?`, id)
	if err := row.Scan(&status, &loc); err != nil {
		return "", ""
	}
	return status, loc
}

// historyRows counts item_history rows for an item — the record-time guard must
// refuse BEFORE any transaction, so a refused closure leaves zero audit rows.
func historyRows(t *testing.T, dbPath, id string) int {
	t.Helper()
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	var n int
	if err := db.QueryRow(`SELECT COUNT(*) FROM item_history WHERE atm_id=?`, id).Scan(&n); err != nil {
		t.Fatalf("count history: %v", err)
	}
	return n
}

// TestCloseEvidenceRecordTime_Polarity is the §11.4.115 RED/GREEN pair.
//
// It drives the exact reproduction shape captured in the file header: a close
// whose --evidence names a path that has never existed.
func TestCloseEvidenceRecordTime_Polarity(t *testing.T) {
	const id = "WIT-810"
	fabricated := filepath.Join(t.TempDir(), "DEFINITELY_NOT_A_REAL_PATH", "x.log")
	if _, err := os.Stat(fabricated); err == nil {
		t.Fatalf("fixture invalid: %q exists", fabricated)
	}

	dbPath := newTestDB(t)
	seedOpenItem(t, dbPath, id)
	statusBefore, locBefore := itemLocation(t, dbPath, id)
	historyBefore := historyRows(t, dbPath, id)

	code := closeCmd([]string{"--db", dbPath, "--status", "fixed", "--evidence", fabricated, id})
	statusAfter, locAfter := itemLocation(t, dbPath, id)

	if hxc224RedMode(t) {
		// RED arm — assert the DEFECT is genuinely present on this artifact.
		if code != exitOK {
			t.Fatalf("RED_MODE=1: close REFUSED the fabricated evidence path (exit %d) — the defect is NOT present on this artifact, so this run reproduces nothing", code)
		}
		if locAfter != "Fixed" {
			t.Fatalf("RED_MODE=1: close exited OK but the item is at %q, not Fixed — the reproduction did not land the mutation it claims", locAfter)
		}
		t.Logf("RED reproduced: close accepted a fabricated evidence path (exit %d) and moved %s %s→%s (status %q→%q)",
			code, id, locBefore, locAfter, statusBefore, statusAfter)
		return
	}

	// GREEN arm (default) — the standing regression guard.
	if code == exitOK {
		t.Fatalf("close ACCEPTED a fabricated evidence path %q (exit %d) — HXC-224: a closure's captured proof must be refused at the moment of recording, not flagged by a later sweep", fabricated, code)
	}
	if locAfter != locBefore || statusAfter != statusBefore {
		t.Fatalf("close refused (exit %d) but MUTATED the record anyway: location %q→%q, status %q→%q — the guard must refuse BEFORE the transaction",
			code, locBefore, locAfter, statusBefore, statusAfter)
	}
	if got := historyRows(t, dbPath, id); got != historyBefore {
		t.Fatalf("close refused but wrote %d new item_history row(s) — a refused closure must leave no audit trace", got-historyBefore)
	}
}

// TestCloseEvidenceRecordTime_AcceptsRealArtefact is the §11.4.201(1)
// false-positive guard-rail: refusing a VALID closure is a FAIL-bluff exactly
// as accepting a fabricated one is a PASS-bluff. Without this case the guard
// could be a blanket "every close is refused" tautology.
func TestCloseEvidenceRecordTime_AcceptsRealArtefact(t *testing.T) {
	const id = "WIT-811"
	dbPath := newTestDB(t)
	seedOpenItem(t, dbPath, id)

	if code := closeCmd([]string{"--db", dbPath, "--status", "fixed", "--evidence", realEvidenceFile(t), id}); code != exitOK {
		t.Fatalf("close REFUSED a closure citing a real non-empty artefact (exit %d) — §11.4.201(1) false-positive refusal", code)
	}
	if _, loc := itemLocation(t, dbPath, id); loc != "Fixed" {
		t.Fatalf("close reported OK but the item is at %q, not Fixed", loc)
	}
}

// TestCloseEvidenceRecordTime_RelativePathAnchoredAtPWD proves the guard uses
// the SAME anchoring as the HXC-217 validator (resolveInvocationRelative /
// $PWD, the HXC-201 mechanism) — the real-world evidence shape is a
// REPO-RELATIVE `docs/qa/<run-id>/…` path, and `go run -C` relocates the child
// process's cwd into this tool's own source tree. Anchoring on the process cwd
// would refuse every legitimate relative evidence path: the exact
// §11.4.201(1) FAIL-bluff this case exists to prevent.
//
// Measured, not assumed: an earlier validator run from the tool's own source
// directory reported 124 spurious violations; the same run with $PWD at the
// repo root reported 1 real one.
func TestCloseEvidenceRecordTime_RelativePathAnchoredAtPWD(t *testing.T) {
	root := t.TempDir()
	rel := filepath.Join("docs", "qa", "run-1", "EVIDENCE.md")
	abs := filepath.Join(root, rel)
	if err := os.MkdirAll(filepath.Dir(abs), 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	if err := os.WriteFile(abs, []byte("captured runtime evidence\n"), 0o644); err != nil {
		t.Fatalf("write evidence: %v", err)
	}

	// The process cwd is the package dir (go test's default) — deliberately NOT
	// `root`. Only $PWD anchoring can resolve `rel`, so a pass here proves the
	// anchoring, and a failure proves it was lost.
	t.Setenv("PWD", root)

	const id = "WIT-812"
	dbPath := newTestDB(t)
	seedOpenItem(t, dbPath, id)
	if code := closeCmd([]string{"--db", dbPath, "--status", "fixed", "--evidence", rel, id}); code != exitOK {
		t.Fatalf("close REFUSED a repo-relative evidence path that resolves under $PWD (exit %d) — the guard is not anchoring through resolveInvocationRelative (§11.4.201(1))", code)
	}
}

// TestEvidencePathCaseSpace is the §11.4.146 STEP-3 fan-out: the enumerated
// case space of the record-time guard, each case with its decided outcome and
// the reason it is decided that way. Driven through checkEvidencePath directly
// so every case is exercised without a DB round-trip; the subcommand wiring is
// covered by the sink tests below.
func TestEvidencePathCaseSpace(t *testing.T) {
	dir := t.TempDir()

	mkfile := func(name, content string) string {
		p := filepath.Join(dir, name)
		if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
			t.Fatalf("write %s: %v", name, err)
		}
		return p
	}
	mkdir := func(name string) string {
		p := filepath.Join(dir, name)
		if err := os.MkdirAll(p, 0o755); err != nil {
			t.Fatalf("mkdir %s: %v", name, err)
		}
		return p
	}

	nonEmptyFile := mkfile("EVIDENCE.md", "captured runtime evidence\n")
	emptyFile := mkfile("EMPTY.log", "")
	emptyDir := mkdir("empty-run-id")
	fullDir := mkdir("full-run-id")
	if err := os.WriteFile(filepath.Join(fullDir, "EVIDENCE.md"), []byte("captured\n"), 0o644); err != nil {
		t.Fatalf("populate dir: %v", err)
	}

	goodLink := filepath.Join(dir, "link-to-real")
	if err := os.Symlink(nonEmptyFile, goodLink); err != nil {
		t.Fatalf("symlink: %v", err)
	}
	danglingLink := filepath.Join(dir, "link-to-nowhere")
	if err := os.Symlink(filepath.Join(dir, "gone", "never.log"), danglingLink); err != nil {
		t.Fatalf("dangling symlink: %v", err)
	}

	cases := []struct {
		name       string
		path       string
		wantRefuse bool
		wantSub    string // substring the refusal must carry (actionability)
		why        string
	}{
		{
			name: "absolute path to an existing non-empty file", path: nonEmptyFile,
			why: "the canonical shape of captured proof — accepted",
		},
		{
			name: "absolute path that does not exist", path: filepath.Join(dir, "never", "captured.log"),
			wantRefuse: true, wantSub: "nothing exists there",
			why: "the HXC-224 defect itself — a closure citing proof that was never captured",
		},
		{
			name: "existing but EMPTY file", path: emptyFile,
			wantRefuse: true, wantSub: "EMPTY file",
			why: "§11.4.69 ab_pass_with_evidence verifies exists AND non-empty; a 0-byte capture is the bluff shape (the capture produced nothing), so it is refused even though os.Stat succeeds — deliberately STRICTER than the HXC-217 validator, which only stats. Stricter-at-record-time is safe; the reverse would be the bug.",
		},
		{
			name: "directory containing artefacts", path: fullDir,
			why: "§11.4.83 mandates per-run evidence DIRECTORIES (docs/qa/<run-id>/) — measured on the live records, 22 of 77 distinct evidence paths are directories, so refusing them would be a mass §11.4.201(1) false refusal",
		},
		{
			name: "EMPTY directory", path: emptyDir,
			wantRefuse: true, wantSub: "EMPTY directory",
			why: "an evidence directory with nothing in it carries no captured proof — same reasoning as the empty file",
		},
		{
			name: "symlink to a real non-empty file", path: goodLink,
			why: "os.Stat follows symlinks; the artefact is reachable at the recorded path, which is what 'producible on demand' means — and it matches the validator's behaviour",
		},
		{
			name: "dangling symlink", path: danglingLink,
			wantRefuse: true, wantSub: "nothing exists there",
			why: "the artefact is NOT producible at the recorded path",
		},
		{
			name: "narrative prose in the single-path field", path: "closure confirmed by manual QA during the session",
			wantRefuse: true, wantSub: "narrative or multi-value text",
			why: "the second observed HXC-217 sub-class; named separately because its remediation differs (capture an artefact vs. locate one)",
		},
		{
			name: "empty string", path: "",
			why: "'not supplied' is not this guard's decision — each caller owns whether --evidence is required (close/obsolete-details require it, move does not), so the guard is a no-op and the caller's own required-flag check reports it",
		},
		{
			name: "whitespace-only string", path: "   ",
			why: "trims to empty — same as the empty string, the caller's required-flag check owns it",
		},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			err := checkEvidencePath(c.path)
			if c.wantRefuse {
				if err == nil {
					t.Fatalf("ACCEPTED %q — expected refusal (%s)", c.path, c.why)
				}
				if !strings.Contains(err.Error(), c.wantSub) {
					t.Errorf("refusal does not carry the %q sub-class wording (unactionable, §11.4.201(5)): %v", c.wantSub, err)
				}
				if !strings.Contains(err.Error(), "resolved") {
					t.Errorf("refusal does not print the RESOLVED path — a false refusal must be diagnosable in one read (§11.4.201(5)): %v", err)
				}
				return
			}
			if err != nil {
				t.Fatalf("REFUSED %q — expected acceptance (%s): %v", c.path, c.why, err)
			}
		})
	}
}

// TestEvidencePathCaseSpace_RelativeToProcessCwdOnly documents the one
// deliberately-strict case: a path that resolves against the PROCESS cwd but
// NOT against $PWD is REFUSED.
//
// Decided this way for consistency: the HXC-217 validator resolves through
// resolveInvocationRelative alone, so accepting a process-cwd-only path here
// would record a row `validate` is guaranteed to flag later — trading a
// record-time refusal for a deferred, harder-to-diagnose one. The guard and the
// detective gate must never disagree.
func TestEvidencePathCaseSpace_RelativeToProcessCwdOnly(t *testing.T) {
	// $PWD points at an empty directory; the artefact exists relative to the
	// process cwd (the package directory) instead.
	t.Setenv("PWD", t.TempDir())

	rel := "close_evidence_recordtime_test.go" // exists relative to the process cwd
	if _, err := os.Stat(rel); err != nil {
		t.Skipf("fixture unavailable: %v", err)
	}
	if err := checkEvidencePath(rel); err == nil {
		t.Fatal("ACCEPTED a path that resolves only against the process cwd — the guard must resolve exactly as the HXC-217 validator does, or the two disagree")
	}
}

// TestEvidenceRecordTime_OtherSinks proves the guard is wired into EVERY
// subcommand that records a CLOSURE-class evidence path, not only `close` —
// each refuses a fabricated path AND accepts a real artefact (the paired
// false-positive guard-rail).
//
// SCOPE, stated honestly (§11.4.6): `reopen --incident` also writes
// item_history.evidence_path but is deliberately NOT wired. A Reopened event is
// by construction NOT a closure, and the HXC-217 validator explicitly exempts
// open items (validate_evidence_test.go case (d)); enforcing at record time what
// the detective gate deliberately declines to enforce would create a new policy
// and a new false-refusal class rather than close the HXC-224 gap.
func TestEvidenceRecordTime_OtherSinks(t *testing.T) {
	fabricated := filepath.Join(t.TempDir(), "never", "captured.log")

	t.Run("obsolete-details", func(t *testing.T) {
		const id = "WIT-820"
		dbPath := newTestDB(t)
		seedOpenItem(t, dbPath, id)
		if code := closeCmd([]string{"--db", dbPath, "--status", "obsolete", "--evidence", realEvidenceFile(t), id}); code != exitOK {
			t.Fatalf("setup close exited %d", code)
		}
		args := func(ev string) []string {
			return []string{"--db", dbPath, "--since", "2026-08-08", "--reason", "feature-removed",
				"--superseding", "none", "--evidence", ev, id}
		}
		if code := obsoleteDetailsCmd(args(fabricated)); code == exitOK {
			t.Fatalf("obsolete-details ACCEPTED a fabricated §11.4.90 triple-check evidence path")
		}
		if code := obsoleteDetailsCmd(args(realEvidenceFile(t))); code != exitOK {
			t.Fatalf("obsolete-details REFUSED a real artefact (exit %d) — §11.4.201(1) false positive", code)
		}
	})

	t.Run("subtask-status to Completed", func(t *testing.T) {
		const parent = "WIT-830"
		dbPath := newTestDBWithParent(t, parent)
		child := parent + "-001"
		if code := subtaskAddCmd([]string{parent, "--db", dbPath,
			"--session", "record-time-evidence-probe"}); code != exitOK {
			t.Fatalf("subtask add exited %d", code)
		}
		if code := subtaskStatusCmd([]string{"--db", dbPath, "--to", "Completed", "--evidence", fabricated, child}); code == exitOK {
			t.Fatalf("subtask-status ACCEPTED a fabricated evidence path for a Completed transition")
		}
		if code := subtaskStatusCmd([]string{"--db", dbPath, "--to", "Completed", "--evidence", realEvidenceFile(t), child}); code != exitOK {
			t.Fatalf("subtask-status REFUSED a real artefact (exit %d) — §11.4.201(1) false positive", code)
		}
	})

	t.Run("move with evidence", func(t *testing.T) {
		const id = "WIT-840"
		dbPath := newTestDB(t)
		seedOpenItem(t, dbPath, id)
		base := []string{"--db", dbPath, "--id", id, "--to", "Fixed",
			"--status", "Fixed (→ Fixed.md)", "--why", "record-time evidence probe"}
		if code := moveCmd(append(append([]string{}, base...), "--evidence", fabricated)); code == exitOK {
			t.Fatalf("move ACCEPTED a fabricated evidence path")
		}
		if code := moveCmd(append(append([]string{}, base...), "--evidence", realEvidenceFile(t))); code != exitOK {
			t.Fatalf("move REFUSED a real artefact (exit %d) — §11.4.201(1) false positive", code)
		}
	})

	t.Run("move without evidence stays optional", func(t *testing.T) {
		const id = "WIT-841"
		dbPath := newTestDB(t)
		seedOpenItem(t, dbPath, id)
		if code := moveCmd([]string{"--db", dbPath, "--id", id, "--to", "Fixed",
			"--status", "Fixed (→ Fixed.md)", "--why", "no evidence supplied"}); code != exitOK {
			t.Fatalf("move REFUSED a relocation with no --evidence (exit %d) — the flag is optional on this command and the guard must not silently make it mandatory", code)
		}
	})
}
