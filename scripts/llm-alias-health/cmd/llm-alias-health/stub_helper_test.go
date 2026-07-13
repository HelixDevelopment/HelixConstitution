package main

// stub_helper_test.go -- builds testdata/stubbridge once per test binary
// invocation (memoized) so probe_integration_test.go, probe_stress_test.go,
// and probe_chaos_test.go can all exec a REAL subprocess (§11.4.27(A):
// non-unit tests must drive the real exec/parse path, not an in-process
// mock) whose behaviour is deterministically selectable via STUB_MODE.

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"testing"
)

var (
	stubBinOnce sync.Once
	stubBinPath string
	stubBinErr  error
	stubBinDir  string
)

// TestMain builds the stub bridge exactly once for the whole test
// binary and removes its temp build directory on exit.
func TestMain(m *testing.M) {
	code := m.Run()
	if stubBinDir != "" {
		_ = os.RemoveAll(stubBinDir)
	}
	os.Exit(code)
}

// buildStubBridge builds testdata/stubbridge into a process-lifetime
// temp dir shared across every test in this binary (built once,
// reused -- rebuilding per-test would materially slow the stress
// suite's N>=100 iteration budget for no benefit).
func buildStubBridge(t *testing.T) string {
	t.Helper()
	stubBinOnce.Do(func() {
		dir, err := os.MkdirTemp("", "llm-alias-health-stubbridge-*")
		if err != nil {
			stubBinErr = fmt.Errorf("mkdtemp: %w", err)
			return
		}
		stubBinDir = dir
		bin := filepath.Join(dir, "stubbridge")
		cmd := exec.Command("go", "build", "-p", "2", "-o", bin, "./testdata/stubbridge")
		out, err := cmd.CombinedOutput()
		if err != nil {
			stubBinErr = fmt.Errorf("go build testdata/stubbridge: %w (output: %s)", err, string(out))
			return
		}
		stubBinPath = bin
	})
	if stubBinErr != nil {
		t.Fatalf("failed to build testdata/stubbridge: %v", stubBinErr)
	}
	return stubBinPath
}
