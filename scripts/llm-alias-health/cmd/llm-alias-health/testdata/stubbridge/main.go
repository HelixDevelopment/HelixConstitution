// Command stubbridge is a controllable stand-in for the LLMsVerifier
// claude-alias-probe bridge, used ONLY by llm-alias-health's own
// stress/chaos tests (never by production config -- §11.4.27(A): mocks
// are permitted only in this test-support role, exercised from
// integration-style tests that drive the REAL exec/parse path against a
// REAL subprocess, just not the real `claude` CLI). Behaviour is
// selected via the STUB_MODE env var so a single small binary covers
// every scenario the anti-bluff chaos suite needs: a healthy alias, a
// rate-limited/quota-exceeded alias, a genuine content-mismatch failure,
// a crashed/hung process, and corrupted/empty stdout.
package main

import (
	"fmt"
	"os"
	"time"
)

func main() {
	mode := os.Getenv("STUB_MODE")
	sentinel := flagValue(os.Args[1:], "--sentinel")

	switch mode {
	case "ok":
		fmt.Printf(`{"verdict":"ok","latency_ms":50,"model":"stub-model","sentinel_matched":true,"observed":%q}`+"\n", sentinel)
		os.Exit(0)
	case "rate_limited":
		fmt.Println(`{"verdict":"rate_limited","retry_after_seconds":30,"detail":"stub rate limit","latency_ms":10}`)
		os.Exit(3)
	case "quota_exceeded":
		fmt.Println(`{"verdict":"quota_exceeded","detail":"stub quota exceeded (weekly limit)","latency_ms":10}`)
		os.Exit(3)
	case "failed":
		fmt.Println(`{"verdict":"failed","detail":"stub sentinel mismatch","latency_ms":50}`)
		os.Exit(1)
	case "badjson":
		fmt.Println(`this is not json at all { broken`)
		os.Exit(1)
	case "empty":
		os.Exit(1) // no stdout at all
	case "nonzero_no_json":
		fmt.Fprintln(os.Stderr, "stub: simulated crash before producing any report")
		os.Exit(2)
	case "hang":
		time.Sleep(2 * time.Hour) // the caller's context timeout must kill this
	default:
		fmt.Fprintf(os.Stderr, "stubbridge: unknown or unset STUB_MODE=%q\n", mode)
		os.Exit(2)
	}
}

// flagValue does a minimal linear scan for --name VALUE in args (the
// stub does not need full flag parsing -- it only ever needs --sentinel
// to echo back for the "ok" case).
func flagValue(args []string, name string) string {
	for i, a := range args {
		if a == name && i+1 < len(args) {
			return args[i+1]
		}
	}
	return ""
}
