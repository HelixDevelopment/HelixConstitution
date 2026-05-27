// Package main is the entrypoint for the `workable-items` Go binary.
//
// §11.4.93 SQLite-backed single-source-of-truth for workable items.
// Forensic anchor: User mandate 2026-05-27.
//
// Phase 2 scaffold — subcommands stubbed; Phase 3 (md→db) + Phase 4
// (db→md) + Phase 5 (generator shims) follow per the 6-phase migration
// defined in Constitution.md §11.4.93.
package main

import (
	"flag"
	"fmt"
	"os"
)

const (
	exitOK      = 0
	exitUsage   = 1
	exitNotImpl = 2
)

func usage() {
	fmt.Fprintln(os.Stderr, `workable-items — §11.4.93 SQLite-SSoT for workable items

Usage:
  workable-items <subcommand> [args...]

Subcommands (Phase 2 scaffold — Phase 3+ implementation pending):
  sync md-to-db          Parse Issues.md + Fixed.md, upsert into DB.
  sync db-to-md          Regenerate Markdown trackers from DB.
  diff                   Show DB vs Markdown divergence (CI gate).
  validate               Schema sanity + §11.4.X invariants.
  add <type> <sev>       Interactive item creation with mandatory fields.
  close <atm-id> [opts]  Terminal transition with §11.4.5 evidence.
  report [--filter]      Query helpers (by type / status / severity / obsolete-audit).

Canonical authority: Constitution.md §11.4.93.
`)
}

func main() {
	flag.Parse()
	args := flag.Args()
	if len(args) < 1 {
		usage()
		os.Exit(exitUsage)
	}

	switch args[0] {
	case "sync":
		runSync(args[1:])
	case "diff":
		runDiff(args[1:])
	case "validate":
		runValidate(args[1:])
	case "add":
		runAdd(args[1:])
	case "close":
		runClose(args[1:])
	case "report":
		runReport(args[1:])
	case "-h", "--help", "help":
		usage()
		os.Exit(exitOK)
	default:
		fmt.Fprintf(os.Stderr, "unknown subcommand: %s\n", args[0])
		usage()
		os.Exit(exitUsage)
	}
}

func runSync(args []string) {
	if len(args) < 1 {
		fmt.Fprintln(os.Stderr, "sync: missing direction (md-to-db | db-to-md)")
		os.Exit(exitUsage)
	}
	switch args[0] {
	case "md-to-db":
		fmt.Fprintln(os.Stderr, "Phase 3 not yet implemented — sync md-to-db scaffolded but not wired")
		os.Exit(exitNotImpl)
	case "db-to-md":
		fmt.Fprintln(os.Stderr, "Phase 4 not yet implemented — sync db-to-md scaffolded but not wired")
		os.Exit(exitNotImpl)
	default:
		fmt.Fprintf(os.Stderr, "unknown sync direction: %s\n", args[0])
		os.Exit(exitUsage)
	}
}

func runDiff(_ []string) {
	fmt.Fprintln(os.Stderr, "Phase 3/4 dependent — diff requires md-to-db + db-to-md")
	os.Exit(exitNotImpl)
}

func runValidate(_ []string) {
	fmt.Fprintln(os.Stderr, "Phase 2 scaffold — validate not yet wired to schema.sql")
	os.Exit(exitNotImpl)
}

func runAdd(_ []string) {
	fmt.Fprintln(os.Stderr, "Phase 3 dependent — add requires Phase 3 schema + parser")
	os.Exit(exitNotImpl)
}

func runClose(_ []string) {
	fmt.Fprintln(os.Stderr, "Phase 3 dependent — close requires Phase 3 schema")
	os.Exit(exitNotImpl)
}

func runReport(_ []string) {
	fmt.Fprintln(os.Stderr, "Phase 3 dependent — report requires Phase 3 schema queries")
	os.Exit(exitNotImpl)
}
