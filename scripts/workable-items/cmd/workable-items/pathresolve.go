// pathresolve.go — anchors relative --db / --out-dir / --out-issues /
// --out-fixed paths against the invoking shell's directory, not this
// process's actual working directory (HXC-201).
//
// # THE DEFECT THIS CLOSES
//
// Building and running this tool from a consuming project requires
// `go run -C <path-to-this-directory> ./cmd/workable-items ...` — the -C flag
// is not optional: a plain `go run ./constitution/scripts/workable-items/...`
// from a consumer's repo root fails outright ("main module ... does not
// contain package ...") because this tool is a separate Go module nested
// inside the consumer's tree. Measured directly (HXC-201 investigation): `go
// run -C <dir>` changes the CHILD PROCESS's actual working directory to
// <dir> — a minimal probe (`os.Getwd()` inside the built child) confirms this;
// it is not merely a build-time chdir that gets undone before the binary
// runs.
//
// Every documented invocation of this tool passes RELATIVE --db / --out-dir
// values (e.g. `--db docs/workable_items.db --out-dir docs`), written the way
// a human types a command: relative to the directory they are standing in.
// After `-C` silently relocates the process, those same relative paths
// resolve against THIS TOOL'S OWN source directory instead — an export that
// prints success-looking "wrote docs/Issues.md" lines while writing nothing
// useful to the caller's real docs/ tree, and (because --db also resolves
// there and does not exist yet) silently materialising a fresh, empty-schema,
// zero-row database inside this tool's own tree. That is the exact defect
// HXC-201 reports, reproduced byte-for-byte in this fix's commit evidence.
//
// # THE FIX, AND WHY IT STAYS DECOUPLED
//
// This tool is a project-agnostic constitution-submodule utility (§11.4.28 /
// §11.4.51): it must never hardcode any particular consumer's directory
// layout. The fix below does not — it leans on a plain POSIX shell
// convention instead. The PWD environment variable is set by the invoking
// shell to "the directory the user is standing in" and is inherited
// unchanged by every child process regardless of that child's own
// os.Chdir/os.Getwd calls — a process changing its OWN working directory
// never rewrites its parent-inherited environment. So PWD survives `go run
// -C`'s internal chdir intact and still names the directory the human or
// script actually invoked the command from, for the overwhelming majority of
// real invocations (any interactive shell, any script run via `bash
// script.sh`, any Makefile recipe — all POSIX shells maintain PWD on `cd`).
//
// When PWD is absent, relative, or stale (binary invoked with a stripped
// environment, or through some non-shell exec path), resolution falls back
// to today's behavior unchanged — this is a strict improvement, never a
// regression: it only repairs the specific case `go run -C` breaks, and an
// always-absolute path (the belt-and-suspenders fix landed in the same
// change, across every documented invocation of this tool) is unaffected by
// any of this either way.
package main

import (
	"os"
	"path/filepath"
)

// resolveInvocationRelative anchors a possibly-relative path against the
// invoking shell's directory ($PWD) instead of the process's actual current
// working directory.
//
//   - An already-absolute path is returned unchanged.
//   - An empty path (flag left at its zero value) is returned unchanged.
//   - Otherwise, when $PWD is set, absolute, and names a directory that
//     actually exists, the path is joined onto it.
//   - Otherwise (PWD unset / relative / stale / non-existent) the path is
//     returned unchanged — today's process-cwd-relative behavior.
func resolveInvocationRelative(path string) string {
	if path == "" || filepath.IsAbs(path) {
		return path
	}
	pwd := os.Getenv("PWD")
	if pwd == "" || !filepath.IsAbs(pwd) {
		return path
	}
	fi, err := os.Stat(pwd)
	if err != nil || !fi.IsDir() {
		return path
	}
	return filepath.Join(pwd, path)
}
