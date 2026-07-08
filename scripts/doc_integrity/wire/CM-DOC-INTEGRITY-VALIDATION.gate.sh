#!/usr/bin/env bash
# =============================================================================
# CM-DOC-INTEGRITY-VALIDATION — recommended pre-build gate STUB (§11.4.186 §5.2)
# =============================================================================
# Purpose:
#   Self-contained reference implementation of the pre-build gate the conductor
#   pastes into `device/rockchip/rk3588/tests/pre_build_verification.sh`. It
#   asserts the five DESIGN §5.2 invariants:
#     (i)   the doc_integrity module exists AND the binary builds;
#     (ii)  `doc-integrity selfcheck` exits 0 (golden fixtures wired — the
#           §11.4.107(10) anti-bluff self-validation);
#     (iii) the export seam (`sync_all_markdown_exports.sh`) contains the
#           `doc_integrity_gate.sh` / `doc-integrity verify` invocation literal;
#     (iv)  the consumer checkset exists and parses;
#     (v)   `doc-integrity verify <checkset>` over the LIVE doc-set exits 0
#           (the actual project docs are clean) — OR the failure is surfaced.
#
#   Invariants (iii)+(iv)+(v) depend on consumer wiring (a seam edit + a
#   consumer checkset authored by the data stream). Until that lands, this stub
#   reports those as PENDING (honest, §11.4.6), NEVER a fake PASS.
#
# Usage:      bash CM-DOC-INTEGRITY-VALIDATION.gate.sh [checkset.yaml] [repo_root]
# Exit:       0 = all applicable invariants PASS; 1 = a hard invariant FAILED.
# Dependencies: go (1.21+), the doc_integrity module.
# Cross-references: DESIGN.md §5.2 / §6, Constitution §11.4.186 / §11.4.107(10).
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
GATE="CM-DOC-INTEGRITY-VALIDATION"

checkset="${1:-}"
repo_root="${2:-$PWD}"
fail=0

say_pass() { echo "PASS ${GATE}: $1"; }
say_fail() { echo "FAIL ${GATE}: $1" >&2; fail=1; }
say_pend() { echo "PENDING ${GATE}: $1 (consumer wiring not yet landed — §11.4.6, not a fake PASS)"; }

# (i) module exists + binary builds.
if [ ! -d "${MODULE_DIR}/cmd/doc_integrity" ]; then
  say_fail "doc_integrity module missing at ${MODULE_DIR}"
else
  if ( cd "${MODULE_DIR}" && GOFLAGS=-mod=mod go build ./... ) >/dev/null 2>&1; then
    say_pass "(i) module builds"
  else
    say_fail "(i) module does NOT build"
  fi
fi

# (ii) selfcheck exits 0.
if ( cd "${MODULE_DIR}" && GOFLAGS=-mod=mod go run ./cmd/doc_integrity selfcheck ) >/dev/null 2>&1; then
  say_pass "(ii) selfcheck GREEN (golden good/bad/negative-control)"
else
  say_fail "(ii) selfcheck FAILED — validator itself is bluffing"
fi

# (iii) export-seam invocation literal present.
seam="${repo_root}/scripts/testing/sync_all_markdown_exports.sh"
if [ -f "${seam}" ]; then
  if grep -Eq "doc_integrity_gate\.sh|doc-integrity[[:space:]]+verify" "${seam}"; then
    say_pass "(iii) export seam invokes doc-integrity"
  else
    say_pend "(iii) export seam does not yet invoke doc-integrity_gate.sh"
  fi
else
  say_pend "(iii) export seam ${seam} not found"
fi

# (iv)+(v) consumer checkset present + live doc-set verifies.
if [ -n "${checkset}" ] && [ -f "${checkset}" ]; then
  say_pass "(iv) consumer checkset exists: ${checkset}"
  if ( cd "${MODULE_DIR}" && GOFLAGS=-mod=mod go run ./cmd/doc_integrity verify "${checkset}" --repo-root "${repo_root}" --quiet ); then
    say_pass "(v) live doc-set verifies clean"
  else
    rc=$?
    if [ "${rc}" -eq 3 ]; then
      say_pend "(v) live doc-set has an unavailable source (SKIP, §11.4.3)"
    else
      say_fail "(v) live doc-set FAILED integrity validation (surface the findings)"
    fi
  fi
else
  say_pend "(iv)+(v) consumer checkset not provided/found"
fi

exit "${fail}"
