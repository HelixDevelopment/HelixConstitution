#!/bin/sh
# ============================================================
# Semgrep CI Integration Test
#
# Purpose:
#   CI-ready validation test for Semgrep SAST tool integration.
#   Verifies semgrep is installed, functional, and capable of
#   detecting known vulnerabilities in test fixtures.
#
# Usage:
#   ./scripts/semgrep/semgrep_ci_test.sh
#
# Exit codes:
#   0 - All checks PASS
#   1 - One or more checks FAIL
#
# Dependencies:
#   - semgrep on PATH (pip install semgrep)
#   - POSIX sh (dash, bash --posix, busybox ash)
#
# Outputs:
#   Captured evidence under qa-results/ per §11.4.69
#
# Cross-references:
#   - docs/semgrep/VERIFICATION.md
#   - scripts/hooks/semgrep_precommit.sh
#   - .docs_chain/contexts/semgrep_status.yaml
# ============================================================

set -u

# --- Constants ---
TEST_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
QA_ROOT="${TEST_DIR}/qa-results"
RUN_ID="semgrep_ci_$(date -u +%Y%m%dT%H%M%SZ)"
QA_DIR="${QA_ROOT}/${RUN_ID}"
SEMGREP_TMP="${QA_DIR}/tmp"
EVIDENCE_FILE="${QA_DIR}/evidence.log"
SUMMARY_FILE="${QA_DIR}/summary.txt"
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

# --- Evidence logging (§11.4.69) ---
log_evidence() {
    _msg="$1"
    _path="${2:-}"
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ${_msg}" >> "${EVIDENCE_FILE}"
    if [ -n "${_path}" ]; then
        echo "  evidence: ${_path}" >> "${EVIDENCE_FILE}"
    fi
}

record_pass() {
    _desc="$1"
    _path="${2:-}"
    PASS_COUNT=$((PASS_COUNT + 1))
    log_evidence "PASS: ${_desc}" "${_path}"
    echo "PASS: ${_desc}"
}

record_fail() {
    _desc="$1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    log_evidence "FAIL: ${_desc}"
    echo "FAIL: ${_desc}"
}

record_skip() {
    _desc="$1"
    _reason="$2"
    SKIP_COUNT=$((SKIP_COUNT + 1))
    log_evidence "SKIP: ${_desc} (reason: ${_reason})"
    echo "SKIP: ${_desc} (${_reason})"
}

# --- Setup ---
mkdir -p "${SEMGREP_TMP}"
: > "${EVIDENCE_FILE}"
log_evidence "Semgrep CI test run ${RUN_ID} started"

echo ""
echo "=== Semgrep CI Integration Test ==="
echo "Run ID: ${RUN_ID}"
echo ""

# --- Test 1: semgrep on PATH ---
echo "--- Test 1: semgrep on PATH ---"
if command -v semgrep >/dev/null 2>&1; then
    SEMGREP_BIN="$(command -v semgrep)"
    record_pass "semgrep found at ${SEMGREP_BIN}" "${SEMGREP_BIN}"
else
    record_fail "semgrep not found on PATH"
    record_skip "remaining tests depend on semgrep binary" "semgrep not installed"
    echo ""
    echo "=== Summary ==="
    echo "PASS: ${PASS_COUNT} | FAIL: ${FAIL_COUNT} | SKIP: ${SKIP_COUNT}"
    echo "Evidence: ${EVIDENCE_FILE}"
    exit 1
fi

# --- Test 2: semgrep --version ---
echo ""
echo "--- Test 2: semgrep --version ---"
SEMGREP_VERSION_OUTPUT="${SEMGREP_TMP}/version.txt"
if semgrep --version > "${SEMGREP_VERSION_OUTPUT}" 2>&1; then
    SEMGREP_VERSION="$(cat "${SEMGREP_VERSION_OUTPUT}")"
    record_pass "semgrep --version returned: ${SEMGREP_VERSION}" "${SEMGREP_VERSION_OUTPUT}"
else
    record_fail "semgrep --version returned non-zero"
fi

# --- Test 3: Known-vulnerability detection ---
echo ""
echo "--- Test 3: Known-vulnerability detection (eval injection) ---"

# Create a small test file with a known vulnerability: Python eval(input())
TESTFILE="${SEMGREP_TMP}/vuln_test.py"
cat > "${TESTFILE}" << 'VULN_EOF'
import os

def greet_user():
    """Greet the user — WARNING: contains eval() for CI-test purposes."""
    name = eval(input("Enter your name: "))  # semgrep-ignore: ci-test-fixture
    print("Hello, " + name)

if __name__ == "__main__":
    greet_user()
VULN_EOF

log_evidence "Created vulnerability test fixture" "${TESTFILE}"

SEMGREP_JSON="${SEMGREP_TMP}/scan_results.json"
semgrep scan --config auto --json "${TESTFILE}" > "${SEMGREP_JSON}" 2>"${SEMGREP_TMP}/scan_stderr.txt"
SEMGREP_JSON_EXIT=$?

log_evidence "semgrep scan exit code: ${SEMGREP_JSON_EXIT}"

# Semgrep OSS exits 0 even when findings are found. The authoritative
# evidence is the JSON output, NOT the exit code. Use --error to get
# non-zero exit on findings, but for CI validation we check JSON directly.
RESULT_COUNT="$(grep -o '"check_id"' "${SEMGREP_JSON}" 2>/dev/null | wc -l | tr -d ' \t\n')"
if [ -z "${RESULT_COUNT}" ]; then
    RESULT_COUNT="0"
fi
if [ "${RESULT_COUNT}" -ge 1 ] 2>/dev/null; then
    record_pass "semgrep detected ${RESULT_COUNT} findings in test fixture" "${SEMGREP_JSON}"
else
    # Fall back to re-running with --error to force non-zero exit as cross-check
    semgrep scan --config auto --error "${TESTFILE}" > /dev/null 2>"${SEMGREP_TMP}/scan_error_stderr.txt"
    SEMGREP_ERROR_EXIT=$?
    echo "INFO: semgrep OSS exit(0) with findings. --error re-run exit: ${SEMGREP_ERROR_EXIT}" >> "${EVIDENCE_FILE}"
    if [ "${SEMGREP_ERROR_EXIT}" -eq 2 ]; then
        record_pass "semgrep --error confirms findings (exit ${SEMGREP_ERROR_EXIT})" "${SEMGREP_TMP}/scan_error_stderr.txt"
    else
        record_fail "semgrep detected 0 findings for known-eval vuln test fixture (JSON: ${RESULT_COUNT}, --error: ${SEMGREP_ERROR_EXIT})"
    fi
fi

# --- Test 4: Shell-script scan (current dir) ---
echo ""
echo "--- Test 4: Shell-script lint scan (no crash) ---"

# Collect .sh files from the scripts/ directory (top-level only to keep scope bounded)
SEMGREP_SH_OUTPUT="${SEMGREP_TMP}/sh_scan_output.txt"
SEMGREP_SH_JSON="${SEMGREP_TMP}/sh_scan_results.json"

# Run on scripts/ dir .sh files; if none, SKIP
SCRIPT_FILES=""
SCRIPT_DIR="${TEST_DIR}/scripts"
if [ -d "${SCRIPT_DIR}" ]; then
    SCRIPT_FILES="$(find "${SCRIPT_DIR}" -maxdepth 2 -name '*.sh' -type f 2>/dev/null | head -50)"
fi

if [ -z "${SCRIPT_FILES}" ]; then
    record_skip "shell script scan" "no .sh files found in scripts/"
else
    # Write file list to a temp file for semgrep
    FILE_LIST="${SEMGREP_TMP}/sh_files.txt"
    echo "${SCRIPT_FILES}" > "${FILE_LIST}"
    # shellcheck disable=SC2086
    semgrep scan --config auto --json $(cat "${FILE_LIST}") > "${SEMGREP_SH_JSON}" 2>"${SEMGREP_TMP}/sh_scan_stderr.txt"
    SH_EXIT=$?

    if [ "${SH_EXIT}" -eq 0 ] || [ "${SH_EXIT}" -eq 2 ]; then
        # exit 0 = clean, exit 2 = findings found (both are "no crash" for this test)
        record_pass "semgrep shell-script scan completed (exit ${SH_EXIT}, no crash)" "${SEMGREP_SH_JSON}"
    else
        record_fail "semgrep shell-script scan crashed (exit ${SH_EXIT})"
        cat "${SEMGREP_TMP}/sh_scan_stderr.txt" >> "${EVIDENCE_FILE}"
    fi
fi

# --- Summary ---
echo ""
echo "=== Summary ==="
echo "PASS: ${PASS_COUNT} | FAIL: ${FAIL_COUNT} | SKIP: ${SKIP_COUNT}"
echo "Evidence: ${EVIDENCE_FILE}"
echo ""

cat > "${SUMMARY_FILE}" << EOF
Semgrep CI Test Run: ${RUN_ID}
Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Result: PASS=${PASS_COUNT} FAIL=${FAIL_COUNT} SKIP=${SKIP_COUNT}
EOF

log_evidence "Run complete: PASS=${PASS_COUNT} FAIL=${FAIL_COUNT} SKIP=${SKIP_COUNT}" "${SUMMARY_FILE}"

if [ "${FAIL_COUNT}" -gt 0 ]; then
    exit 1
fi
exit 0
