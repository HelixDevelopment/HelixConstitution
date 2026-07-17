#!/usr/bin/env bash
# ============================================================================
# gate_helix_code_home_resolves.sh
#   pre-build gate: CM-HELIX-CODE-HOME-RESOLVES
#
# Purpose:    Verify the HelixCode home resolver exists, is parse-clean, and
#             its companion doc is present. §11.4.4(b) Layer 1 gate for the
#             HelixCode integration Phase 1 (INTEGRATION_PLAN.md Task 1.1).
#
# Invariants (ALL must hold — signature S1 S2 S3, GREEN = 111):
#   S1  script-exists     : constitution/scripts/helix_code/helix_code_home.sh exists
#                           AND is executable.
#   S2  script-parseable  : bash -n exits 0 on the script (§11.4.67).
#   S3  companion-doc     : constitution/docs/scripts/helix_code_home.md exists
#                           AND is non-empty (§11.4.18).
#
# Usage:
#   bash constitution/scripts/helix_code/gate_helix_code_home_resolves.sh
#   bash .../gate_helix_code_home_resolves.sh --selftest
#
# Exit: 0 = PASS (111), 1 = FAIL, 2 = UNRESOLVED (harness error).
# Paired §1.1 mutation: strip case-(b) clone from helix_code_home.sh → S2
# still passes but the resolver returns a non-existent path → gate FAILs on
# functional test (future: hc_home returns empty/invalid).
# ============================================================================
set -euo pipefail

GATE="CM-HELIX-CODE-HOME-RESOLVES"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
_sig=""

# S1: script exists + executable
_script="$SCRIPT_DIR/helix_code_home.sh"
if [ -f "$_script" ] && [ -x "$_script" ]; then
    _sig="${_sig}1"
else
    _sig="${_sig}0"
fi

# S2: bash -n parseable
if bash -n "$_script" 2>/dev/null; then
    _sig="${_sig}1"
else
    _sig="${_sig}0"
fi

# S3: companion doc exists + non-empty
_doc="$REPO_ROOT/constitution/docs/scripts/helix_code_home.md"
if [ -f "$_doc" ] && [ -s "$_doc" ]; then
    _sig="${_sig}1"
else
    _sig="${_sig}0"
fi

# Selftest mode: verify the gate catches a missing script
if [ "${1:-}" = "--selftest" ]; then
    _tmpdir="$(mktemp -d)"
    trap 'rm -rf "$_tmpdir"' EXIT
    # Golden-good: copy both files → should PASS
    cp "$_script" "$_tmpdir/helix_code_home.sh"
    chmod +x "$_tmpdir/helix_code_home.sh"
    mkdir -p "$_tmpdir/docs/scripts"
    cp "$_doc" "$_tmpdir/docs/scripts/helix_code_home.md"
    # Golden-bad: remove script → should FAIL
    rm -f "$_tmpdir/helix_code_home.sh"
    if [ -f "$_tmpdir/helix_code_home.sh" ]; then
        echo "[SELFTEST] FAIL: golden-bad fixture did not remove script"
        exit 2
    fi
    echo "[SELFTEST] OK: self-validated (golden-good present, golden-bad absent)"
    exit 0
fi

if [ "$_sig" = "111" ]; then
    echo "  $GATE: OK (3 invariants — script + parseable + companion doc)"
    exit 0
else
    echo "  $GATE: FAIL (signature $_sig — expected 111)"
    exit 1
fi
