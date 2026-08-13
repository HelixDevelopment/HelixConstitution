// pathresolve_test.go — HXC-201 regression guard.
//
// §11.4.115 polarity: TestExportCmd_RelativeFlags_AnchorAtInvocationPWD below
// reproduces the exact documented (previously broken) invocation shape — a
// relative --db/--out-dir run from a process whose cwd has been relocated the
// way `go run -C <this-tool's-dir>` relocates it — entirely in-process, with
// real SQLite + real command dispatch (no mocks). Before the pathresolve.go
// fix this test FAILS: output lands under the simulated tool directory, empty
// placeholder docs and a fresh zero-row DB appear there, and the caller's real
// project docs stay untouched. After the fix it PASSES: both --db and
// --out-dir resolve against $PWD (the invoking shell's directory), matching
// what the human who typed the documented command actually meant.
package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestResolveInvocationRelative(t *testing.T) {
	realDir := t.TempDir()

	cases := []struct {
		name string
		path string
		pwd  string // "" = unset
		want string
	}{
		{
			name: "absolute path is never touched",
			path: "/already/absolute/docs",
			pwd:  realDir,
			want: "/already/absolute/docs",
		},
		{
			name: "empty path is returned unchanged",
			path: "",
			pwd:  realDir,
			want: "",
		},
		{
			name: "PWD unset falls back to unchanged relative path",
			path: "docs",
			pwd:  "",
			want: "docs",
		},
		{
			name: "PWD set but relative is ignored (never trust a relative anchor)",
			path: "docs",
			pwd:  "not/absolute",
			want: "docs",
		},
		{
			name: "PWD set but names a directory that does not exist is ignored",
			path: "docs",
			pwd:  filepath.Join(realDir, "does-not-exist-at-all"),
			want: "docs",
		},
		{
			name: "PWD set, absolute, and real: relative path is anchored there",
			path: "docs/workable_items.db",
			pwd:  realDir,
			want: filepath.Join(realDir, "docs/workable_items.db"),
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Setenv("PWD", tc.pwd)
			if tc.pwd == "" {
				os.Unsetenv("PWD")
			}
			got := resolveInvocationRelative(tc.path)
			if got != tc.want {
				t.Errorf("resolveInvocationRelative(%q) with PWD=%q = %q, want %q",
					tc.path, tc.pwd, got, tc.want)
			}
		})
	}
}

// TestExportCmd_RelativeFlags_AnchorAtInvocationPWD_NotProcessCwd reproduces
// HXC-201 end-to-end: a relative --db/--out-dir pair, run from a process cwd
// that has been relocated the way `go run -C constitution/scripts/workable-items`
// relocates it, MUST resolve against the invoking directory ($PWD) — the real
// project root — not the relocated process cwd (this tool's own directory).
func TestExportCmd_RelativeFlags_AnchorAtInvocationPWD_NotProcessCwd(t *testing.T) {
	// projectRoot simulates the consuming project's repo root: the directory
	// the human was standing in when they typed the documented command.
	projectRoot := t.TempDir()
	// toolDir simulates constitution/scripts/workable-items — where `-C`
	// silently relocates the process.
	toolDir := t.TempDir()

	// Seed a real DB with one open item, at the path the documented command
	// names relative to projectRoot: docs/workable_items.db.
	t.Setenv("HELIX_RELEASE_PREFIX", "wit")
	dbPath := filepath.Join(projectRoot, "docs", "workable_items.db")
	if err := os.MkdirAll(filepath.Dir(dbPath), 0o755); err != nil {
		t.Fatalf("mkdir docs: %v", err)
	}
	if code := addCmd([]string{"Bug", "High", "--db", dbPath,
		"--title", "HXC-201 regression probe item",
		"--description", "Present only if export read the real project DB, not a fresh empty one"}); code != exitOK {
		t.Fatalf("seed add: exit %d", code)
	}

	// Relocate the process cwd exactly as `go run -C toolDir` would, and set
	// PWD to the directory the human actually invoked the command from —
	// exactly what a real shell leaves in the child's environment.
	origWD, err := os.Getwd()
	if err != nil {
		t.Fatalf("Getwd: %v", err)
	}
	if err := os.Chdir(toolDir); err != nil {
		t.Fatalf("Chdir(toolDir): %v", err)
	}
	t.Cleanup(func() {
		if err := os.Chdir(origWD); err != nil {
			t.Fatalf("restore cwd: %v", err)
		}
	})
	t.Setenv("PWD", projectRoot)

	// The exact documented (previously broken) invocation shape: relative
	// --db and --out-dir, typed as if standing in projectRoot.
	code := exportCmd([]string{
		"--db", "docs/workable_items.db",
		"--out-dir", "docs",
		"--no-formats",
	})
	if code != exitOK {
		t.Fatalf("exportCmd exit = %d, want %d", code, exitOK)
	}

	// The real destination: projectRoot/docs/Issues.md must exist, be
	// non-empty, and contain the seeded item.
	wantIssues := filepath.Join(projectRoot, "docs", "Issues.md")
	b, err := os.ReadFile(wantIssues)
	if err != nil {
		t.Fatalf("export did not write %s (landed elsewhere?): %v", wantIssues, err)
	}
	if len(b) == 0 {
		t.Errorf("%s is empty — export ran against the wrong (empty) DB", wantIssues)
	}
	if !strings.Contains(string(b), "HXC-201 regression probe item") {
		t.Errorf("%s missing the seeded item — export read the wrong DB:\n%s", wantIssues, string(b))
	}

	// The bug's signature artefact: NOTHING should have been written inside
	// toolDir (the relocated process cwd) — no stray docs/, no stray DB.
	if _, err := os.Stat(filepath.Join(toolDir, "docs")); err == nil {
		t.Errorf("export wrote into the relocated process cwd (%s/docs) — HXC-201 regressed", toolDir)
	}
}
