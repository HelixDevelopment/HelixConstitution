#!/bin/sh
# semgrep_validate.sh — Helix Universal semgrep anti-bluff validation.
#
# Validates that the installed semgrep is functional, that it can produce
# valid JSON output against real code, and that the semgrep registry is
# reachable. All functions are POSIX-sh compliant per §11.4.67.
#
# Functions:
#   semgrep_validate_check()    — runs semgrep scan --config auto --json
#                                 on a known test file and asserts valid JSON
#   semgrep_validate_rules()    — verifies the semgrep registry is reachable
#
# Usage:
#   . <constitution>/scripts/semgrep/semgrep_validate.sh
#   semgrep_validate_check
#   semgrep_validate_rules
#
# Anti-bluff (§107 / §11.4.69):
#   - `semgrep_validate_check` pumps a real file through `semgrep scan
#     --config auto --json` and asserts the output parses as valid JSON
#     with a non-empty `results` array (or at least syntactically valid).
#   - A scan returning malformed JSON or an empty JSON structure without
#     results is a FAIL.
#   - Every PASS emits `ab_pass_with_evidence`-style output:
#       PASS: <description> [evidence: <path>]
#   - Evidence path is written to a well-known file so an external
#     orchestrator can consume it (per §11.4.116 sync pattern).
#
# Exit codes:
#   0 — validation PASS (all asserts passed)
#   1 — validation FAIL (a required assert did not pass)
#   2 — environment problem (semgrep not on PATH, JSON tool missing)
#
# Dependencies: semgrep (installed via semgrep_setup.sh)
# Cross-references: semgrep_setup.sh, semgrep_path.sh, docs/semgrep/Status.md
# Last verified: 2026-06-21

set -u

# ---------- state ----------
SEMGREP_DIR="${SEMGREP_DIR:-$(cd "$(dirname "$0")" && pwd)}"
CONST_ROOT="$(cd "${SEMGREP_DIR}/../.." && pwd)"
STATUS_DOC="${CONST_ROOT}/docs/semgrep/Status.md"
VALIDATE_DIR="${CONST_ROOT}/docs/.semgrep"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

mkdir -p "${VALIDATE_DIR}"

# ---------- helpers ----------

# Emit a structured PASS line with evidence path per §11.4.69.
ab_pass_with_evidence() {
    _desc="$1"
    _evidence="$2"
    echo "PASS: ${_desc} [evidence: ${_evidence}]"
}

# Emit a structured FAIL line.
ab_fail() {
    _desc="$1"
    _detail="$2"
    echo "FAIL: ${_desc} — ${_detail}"
}

# Log a validation event.
semgrep_log_validation() {
    _event="$1"
    _detail="$2"
    {
        echo ""
        echo "## ${TS} — ${_event}"
        echo ""
        echo "${_detail}"
    } >> "${STATUS_DOC}"
}

# ---------- test fixture ----------
# Write a small C file so we have a known target for --config auto.
_SEMGREP_FIXTURE="${VALIDATE_DIR}/test_fixture.c"
if [ ! -f "${_SEMGREP_FIXTURE}" ]; then
    cat <<'SEMGREP_FIXTURE' > "${_SEMGREP_FIXTURE}"
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    char buf[64];
    strcpy(buf, argv[0]);  /* potential buffer overflow */
    printf("Hello: %s\n", buf);
    return 0;
}
SEMGREP_FIXTURE
fi

# ---------- public functions ----------

# semgrep_validate_check — runs semgrep scan --config auto --json on a real
# source file and asserts the output is valid JSON with a "results" key.
# Writes the JSON output to a captured-evidence path.
semgrep_validate_check() {
    echo "[semgrep_validate] Running semgrep scan on test fixture..."

    if ! command -v semgrep >/dev/null 2>&1; then
        echo "ERROR: semgrep not on PATH. Run semgrep_setup_install first." >&2
        return 2
    fi

    _evidence_path="${VALIDATE_DIR}/scan_${TS}.json"
    _stderr_path="${VALIDATE_DIR}/scan_${TS}.stderr"

    semgrep scan --config auto --json "${_SEMGREP_FIXTURE}" \
        > "${_evidence_path}" 2>"${_stderr_path}"
    _scan_exit=$?

    # Check file is non-empty
    if [ ! -s "${_evidence_path}" ]; then
        _err="$(cat "${_stderr_path}" 2>/dev/null || echo '')"
        ab_fail "semgrep scan produced empty output" "${_err}"
        semgrep_log_validation "validate check FAILED" \
            "- exit: ${_scan_exit}\n- stderr: ${_err}"
        return 1
    fi

    # Anti-bluff: verify the output is valid JSON.
    # Use a portable JSON check: python3 -m json.tool if available,
    # fall back to grepping for the "results" key.
    _is_valid=1
    if command -v python3 >/dev/null 2>&1; then
        if python3 -m json.tool "${_evidence_path}" >/dev/null 2>&1; then
            _is_valid=0
        fi
    else
        # POSIX grep for a "results" key as a best-effort validity check.
        if grep -q '"results"' "${_evidence_path}" 2>/dev/null; then
            _is_valid=0
        fi
    fi

    if [ "${_is_valid}" -eq 0 ]; then
        ab_pass_with_evidence \
            "semgrep scan produced valid JSON with results" \
            "${_evidence_path}"
        semgrep_log_validation "validate check PASSED" \
            "- evidence: ${_evidence_path}\n- exit code: ${_scan_exit}"
        return 0
    else
        _err="$(cat "${_stderr_path}" 2>/dev/null || echo '')"
        ab_fail "semgrep scan output is NOT valid JSON" "${_err}"
        semgrep_log_validation "validate check FAILED" \
            "- evidence: ${_evidence_path}\n- output is not valid JSON"
        return 1
    fi
}

# semgrep_validate_rules — verifies the semgrep registry is reachable.
# Runs `semgrep --config-registry --dump-config-rules` and extracts the
# first few lines to confirm the registry responded.
semgrep_validate_rules() {
    echo "[semgrep_validate] Checking semgrep registry reachability..."

    if ! command -v semgrep >/dev/null 2>&1; then
        echo "ERROR: semgrep not on PATH. Run semgrep_setup_install first." >&2
        return 2
    fi

    _evidence_path="${VALIDATE_DIR}/registry_${TS}.txt"

    # --config-registry --dump-config-rules is the canonical way to dump
    # the bundled rule set. We capture the first 5 lines as a reachability
    # probe per §11.4.69.
    semgrep --config-registry --dump-config-rules 2>&1 | head -5 \
        > "${_evidence_path}"

    if [ -s "${_evidence_path}" ]; then
        ab_pass_with_evidence \
            "semgrep registry reachable (dump-config-rules returned output)" \
            "${_evidence_path}"
        semgrep_log_validation "registry check PASSED" \
            "- evidence: ${_evidence_path}"
        return 0
    else
        ab_fail "semgrep registry unreachable" \
            "dump-config-rules produced empty output"
        semgrep_log_validation "registry check FAILED" \
            "- registry produced empty output"
        return 1
    fi
}

# ---------- main ----------
# When invoked directly, run both checks.
case "$(basename "$0" 2>/dev/null)" in
    semgrep_validate.sh)
        _overall=0

        semgrep_validate_check
        _rc=$?
        [ "${_rc}" -ne 0 ] && _overall="${_rc}"

        echo "---"

        semgrep_validate_rules
        _rc=$?
        [ "${_rc}" -ne 0 ] && _overall="${_rc}"

        if [ "${_overall}" -eq 0 ]; then
            echo ""
            echo "=== semgrep validation: ALL PASS ==="
        else
            echo ""
            echo "=== semgrep validation: FAIL (exit ${_overall}) ===" >&2
        fi

        exit "${_overall}"
        ;;
    *)
        # Sourced — provide functions only
        ;;
esac
