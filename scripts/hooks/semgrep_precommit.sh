#!/bin/sh
# ============================================================
# Semgrep Pre-Commit Hook
#
# Purpose:
#   Runs semgrep on staged file changes before commit.
#   Blocks the commit if semgrep finds issues.
#   Gracefully degrades if semgrep is not available.
#
# Usage:
#   As a pre-commit git hook, invoked automatically by git.
#   Can also be run manually:
#     ./scripts/hooks/semgrep_precommit.sh
#
# Exit codes:
#   0 - All checks pass (or semgrep not available)
#   1 - Semgrep found issues (commit blocked)
#
# Dependencies:
#   - semgrep on PATH (optional — graceful degradation)
#   - git
#   - POSIX sh
#
# Cross-references:
#   - scripts/semgrep/semgrep_ci_test.sh
#   - docs/semgrep/VERIFICATION.md
#   - .docs_chain/contexts/semgrep_status.yaml
# ============================================================

set -u

# --- Check if semgrep is available ---
if ! command -v semgrep >/dev/null 2>&1; then
    echo "[semgrep-precommit] semgrep not found on PATH — skipping pre-commit scan"
    exit 0
fi

# --- Get staged files ---
STAGED_FILES=""
STAGED_FILES="$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null || true)"

if [ -z "${STAGED_FILES}" ]; then
    echo "[semgrep-precommit] no staged files to scan"
    exit 0
fi

# --- Filter to source files semgrep can analyze ---
# Include: Python, JavaScript, TypeScript, Go, Java, Kotlin, Ruby, C, C++, YAML, JSON, shell scripts
SCAN_FILES=""
for _f in ${STAGED_FILES}; do
    case "${_f}" in
        *.py|*.js|*.ts|*.go|*.java|*.kt|*.rb|*.c|*.cpp|*.h|*.hpp|*.yaml|*.yml|*.json|*.sh|*.bash)
            if [ -f "${_f}" ]; then
                SCAN_FILES="${SCAN_FILES} ${_f}"
            fi
            ;;
    esac
done

if [ -z "${SCAN_FILES}" ]; then
    echo "[semgrep-precommit] no scannable file types in staged changes"
    exit 0
fi

# --- Run semgrep ---
echo "[semgrep-precommit] scanning staged changes with semgrep..."

SEMGREP_OUTPUT="$(mktemp /tmp/semgrep_precommit.XXXXXX 2>/dev/null)"
SEMGREP_EXIT=0

# shellcheck disable=SC2086
semgrep scan --config auto --error ${SCAN_FILES} > "${SEMGREP_OUTPUT}" 2>&1
SEMGREP_EXIT=$?

if [ "${SEMGREP_EXIT}" -eq 0 ]; then
    echo "[semgrep-precommit] no issues found — commit allowed"
    rm -f "${SEMGREP_OUTPUT}"
    exit 0
elif [ "${SEMGREP_EXIT}" -eq 2 ]; then
    echo ""
    echo "[semgrep-precommit] SEMGREP FOUND ISSUES — COMMIT BLOCKED"
    echo "=============================================="
    cat "${SEMGREP_OUTPUT}"
    echo "=============================================="
    echo ""
    echo "To bypass (not recommended): git commit --no-verify"
    rm -f "${SEMGREP_OUTPUT}"
    exit 1
else
    echo "[semgrep-precommit] semgrep scan error (exit ${SEMGREP_EXIT})"
    echo "--- output ---"
    cat "${SEMGREP_OUTPUT}"
    echo "--- end ---"
    echo "[semgrep-precommit] allowing commit despite semgrep error (non-blocking)"
    rm -f "${SEMGREP_OUTPUT}"
    exit 0
fi
