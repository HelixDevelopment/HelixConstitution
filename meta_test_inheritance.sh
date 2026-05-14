#!/usr/bin/env bash
# meta_test_inheritance.sh — Constitution-side meta-test that proves
# the consuming project's inheritance gate is not itself a bluff gate.
#
# Pattern (mutation testing — Constitution §1.1):
#   1. Take a snapshot of Constitution.md.
#   2. Mutate: delete the §11.4 anchor block.
#   3. Run the consuming project's inheritance gate.
#   4. Assert the gate now reports FAIL.
#   5. Restore.
#
# This file is invoked by the consuming project's meta-test harness
# (e.g. ATMOSphere's `scripts/testing/meta_test_false_positive_proof.sh`
# `CM-CONSTITUTION-INHERITANCE mutation`).
#
# Usage:
#   bash meta_test_inheritance.sh <project-gate-cmd>
#     <project-gate-cmd>: shell command that runs the inheritance gate
#                         and returns non-zero on FAIL.
#
# Constitution: §1.1 False-positive immunity is an invariant.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_FILE="${SCRIPT_DIR}/Constitution.md"
GATE_CMD="${1:-}"

if [[ -z "${GATE_CMD}" ]]; then
    echo "Usage: $0 <project-gate-cmd>" >&2
    exit 2
fi

if [[ ! -f "${TARGET_FILE}" ]]; then
    echo "ERROR: ${TARGET_FILE} not found" >&2
    exit 2
fi

BACKUP="$(mktemp)"
cp "${TARGET_FILE}" "${BACKUP}"

cleanup() {
    cp "${BACKUP}" "${TARGET_FILE}"
    rm -f "${BACKUP}"
}
trap cleanup EXIT INT TERM

# --- Mutation ----------------------------------------------------------
# Delete the §11.4 anchor heading line. This is a single-line surgical
# mutation that simulates the regression "someone weakened the
# Constitution by stripping the End-User Quality Guarantee anchor".
SENTINEL_LINE='### §11.4 End-user quality guarantee — forensic anchor (User mandate, 2026-04-28)'
if ! grep -qF "${SENTINEL_LINE}" "${TARGET_FILE}"; then
    echo "ERROR: sentinel line not found in ${TARGET_FILE}" >&2
    echo "       expected: ${SENTINEL_LINE}" >&2
    exit 2
fi

# Use grep -v to filter out the sentinel line (safer than sed when the
# line contains special chars).
grep -vF "${SENTINEL_LINE}" "${BACKUP}" > "${TARGET_FILE}"

# --- Run the consuming project's inheritance gate ---------------------
echo "Mutation applied: §11.4 anchor removed from Constitution.md"
echo "Running consuming-project gate: ${GATE_CMD}"
set +e
eval "${GATE_CMD}"
GATE_RC=$?
set -e

# Restore happens via trap; explicit verification below.
cleanup
trap - EXIT INT TERM

# --- Assertion ---------------------------------------------------------
if [[ "${GATE_RC}" -ne 0 ]]; then
    echo "✓ META-TEST PASS: gate correctly FAILed (rc=${GATE_RC}) on mutated Constitution"
    exit 0
else
    echo "✗ META-TEST FAIL: gate returned 0 even though the §11.4 anchor"
    echo "  was removed from Constitution.md. The gate is a BLUFF GATE."
    echo "  Fix the consuming project's inheritance gate so it actually"
    echo "  asserts the §11.4 anchor's presence."
    exit 1
fi
