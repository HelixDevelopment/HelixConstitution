// Command doc-integrity is a project-agnostic pre-export doc + workable-item
// integrity validator (constitution §11.4.186 (proposed) / DESIGN
// docs/research/doc_integrity_validator/DESIGN.md). It runs FIVE machine-
// checkable check families over a consumer-registered doc-set and REFUSES the
// export (non-zero exit) on any integrity FAIL.
//
// Usage:
//
//	doc-integrity verify   <checkset.yaml> [--repo-root DIR] [--json PATH] [--evidence-dir DIR] [--quiet]
//	doc-integrity report   <checkset.yaml> [--repo-root DIR]
//	doc-integrity selfcheck
//	doc-integrity version
//
// Exit codes: 0 PASS, 1 FAIL, 2 config error, 3 SKIP (source unavailable —
// honest SKIP-with-reason §11.4.3, never a fake PASS).
package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/HelixDevelopment/HelixConstitution/scripts/doc_integrity/internal/report"
	"github.com/HelixDevelopment/HelixConstitution/scripts/doc_integrity/internal/runner"
	"github.com/HelixDevelopment/HelixConstitution/scripts/doc_integrity/internal/selfcheck"
)

const version = "doc-integrity 1.0.0 (constitution §11.4.186)"

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(report.ExitCfg)
	}
	switch os.Args[1] {
	case "verify":
		os.Exit(cmdVerify(os.Args[2:]))
	case "report":
		os.Exit(cmdReport(os.Args[2:]))
	case "selfcheck":
		os.Exit(cmdSelfcheck())
	case "version", "-v", "--version":
		fmt.Println(version)
		os.Exit(0)
	case "-h", "--help", "help":
		usage()
		os.Exit(0)
	default:
		fmt.Fprintf(os.Stderr, "doc-integrity: unknown subcommand %q\n", os.Args[1])
		usage()
		os.Exit(report.ExitCfg)
	}
}

func cmdVerify(args []string) int {
	// The checkset may appear before OR after the flags; Go's flag package stops
	// at the first positional, so we split it out first (operators naturally
	// write `verify <checkset> --repo-root X`).
	checkset, rest := splitPositional(args)
	fs := flag.NewFlagSet("verify", flag.ContinueOnError)
	repoRoot := fs.String("repo-root", ".", "repository root the source paths resolve against")
	jsonPath := fs.String("json", "", "write machine-readable result JSON to this path")
	evidenceDir := fs.String("evidence-dir", "", "write captured-evidence artefacts (JSON+report) under this dir")
	quiet := fs.Bool("quiet", false, "suppress the human report on stdout")
	if err := fs.Parse(rest); err != nil {
		return report.ExitCfg
	}
	if checkset == "" {
		checkset = fs.Arg(0)
	}
	if checkset == "" {
		fmt.Fprintln(os.Stderr, "doc-integrity verify: missing <checkset.yaml>")
		return report.ExitCfg
	}
	res, err := runner.Run(checkset, *repoRoot)
	if err != nil {
		fmt.Fprintf(os.Stderr, "doc-integrity: config error: %v\n", err)
		return report.ExitCfg
	}
	if *jsonPath != "" {
		f, e := os.Create(*jsonPath)
		if e != nil {
			fmt.Fprintf(os.Stderr, "doc-integrity: cannot write json: %v\n", e)
			return report.ExitCfg
		}
		_ = res.WriteJSON(f)
		f.Close()
	}
	if *evidenceDir != "" {
		if e := res.WriteEvidence(*evidenceDir); e != nil {
			fmt.Fprintf(os.Stderr, "doc-integrity: cannot write evidence: %v\n", e)
		}
	}
	if !*quiet {
		res.WriteHuman(os.Stdout)
	}
	return res.ExitCode
}

func cmdReport(args []string) int {
	checkset, rest := splitPositional(args)
	fs := flag.NewFlagSet("report", flag.ContinueOnError)
	repoRoot := fs.String("repo-root", ".", "repository root the source paths resolve against")
	if err := fs.Parse(rest); err != nil {
		return report.ExitCfg
	}
	if checkset == "" {
		checkset = fs.Arg(0)
	}
	if checkset == "" {
		fmt.Fprintln(os.Stderr, "doc-integrity report: missing <checkset.yaml>")
		return report.ExitCfg
	}
	res, err := runner.Run(checkset, *repoRoot)
	if err != nil {
		fmt.Fprintf(os.Stderr, "doc-integrity: config error: %v\n", err)
		return report.ExitCfg
	}
	res.WriteHuman(os.Stdout)
	return res.ExitCode
}

func cmdSelfcheck() int {
	ok, out := selfcheck.Run()
	fmt.Print(out)
	if ok {
		return report.ExitPass
	}
	return report.ExitFail
}

// splitPositional supports the checkset in either position without mis-reading
// a value-taking flag's value as the checkset:
//   - checkset FIRST (`verify <checkset> --flags…`): the remaining args are pure
//     flags, which flag.Parse handles correctly (values included).
//   - checkset NOT first (`verify --repo-root X <checkset>`): return all args so
//     flag.Parse consumes the leading flags and the checkset is fs.Arg(0).
func splitPositional(args []string) (positional string, rest []string) {
	if len(args) > 0 && args[0] != "" && args[0][0] != '-' {
		return args[0], args[1:]
	}
	return "", args
}

func usage() {
	fmt.Fprint(os.Stderr, `doc-integrity — pre-export doc + workable-item integrity validator (§11.4.186)

  doc-integrity verify   <checkset.yaml> [--repo-root DIR] [--json PATH] [--evidence-dir DIR] [--quiet]
  doc-integrity report   <checkset.yaml> [--repo-root DIR]
  doc-integrity selfcheck
  doc-integrity version

exit: 0 PASS  1 FAIL  2 config-error  3 SKIP(source-unavailable)
`)
}
