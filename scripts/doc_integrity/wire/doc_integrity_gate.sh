#!/usr/bin/env bash
# =============================================================================
# doc_integrity_gate.sh — pre-export / pre-commit HARD gate hook (§11.4.186)
# =============================================================================
# Purpose:
#   The mandatory-before-export seam for the doc-integrity validator. Callable
#   from `scripts/testing/sync_all_markdown_exports.sh`, Docs Chain `verify`,
#   and `scripts/commit_all.sh` so that export / commit is REFUSED on any
#   integrity FAIL (DESIGN §5.1). Rendering a divergent source to four formats
#   merely multiplies the defect across HTML/PDF/DOCX — so this runs FIRST,
#   before any render.
#
# Usage:
#   bash doc_integrity_gate.sh <checkset.yaml> [repo_root]
#     <checkset.yaml>  consumer-owned checkset (e.g. .atmosphere/doc_integrity/checkset.yaml)
#     [repo_root]      root the source paths resolve against (default: $PWD)
#
# Inputs:
#   $DOC_INTEGRITY_BIN  optional path to a prebuilt doc-integrity binary
#                       (else the module is built on demand via `go build`).
#
# Outputs / exit codes (the caller MUST honour these):
#   0  PASS   — no integrity findings; export/commit may proceed.
#   1  FAIL   — integrity findings; export/commit MUST be REFUSED.
#   3  SKIP   — a source (or the Go toolchain) is unavailable → honest
#              SKIP-with-reason (§11.4.3), NEVER a fake PASS. The caller MAY
#              proceed (a genuinely-absent doc is not a divergence) but MUST
#              surface the SKIP; the pre-build CM-DOC-INTEGRITY-VALIDATION gate
#              hard-fails on a missing toolchain, so routine exports are not
#              silently unguarded.
#
# Side-effects:  none (read-only validation; writes only its own build cache
#                under a temp dir + optional evidence dir).
# Dependencies:  go (1.21+) OR $DOC_INTEGRITY_BIN; the doc_integrity module.
# Cross-references: DESIGN.md §5, Constitution §11.4.186 / §11.4.106 / §11.4.65
#                   / §11.4.73 / §11.4.3 / §11.4.6.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"   # constitution/scripts/doc_integrity

checkset="${1:-}"
repo_root="${2:-$PWD}"

if [ -z "${checkset}" ]; then
  echo "doc_integrity_gate: usage: $0 <checkset.yaml> [repo_root]" >&2
  exit 3
fi
if [ ! -f "${checkset}" ]; then
  echo "SKIP: doc-integrity — checkset not found: ${checkset} (§11.4.3)" >&2
  exit 3
fi

# Resolve the binary: prefer a prebuilt one, else build on demand.
bin="${DOC_INTEGRITY_BIN:-}"
if [ -z "${bin}" ] || [ ! -x "${bin}" ]; then
  if ! command -v go >/dev/null 2>&1; then
    echo "SKIP: doc-integrity — Go toolchain absent; cannot build validator (§11.4.3)" >&2
    exit 3
  fi
  tmpbin="$(mktemp -d)/doc-integrity"
  if ! ( cd "${MODULE_DIR}" && GOFLAGS=-mod=mod go build -o "${tmpbin}" ./cmd/doc_integrity ) >/dev/null 2>&1; then
    echo "SKIP: doc-integrity — validator build failed (§11.4.3, not a fake PASS)" >&2
    exit 3
  fi
  bin="${tmpbin}"
fi

set +e
"${bin}" verify "${checkset}" --repo-root "${repo_root}"
rc=$?
set -e

case "${rc}" in
  0) echo "doc-integrity: PASS — export/commit may proceed." ;;
  1) echo "doc-integrity: FAIL — export/commit REFUSED (integrity findings above)." >&2 ;;
  3) echo "doc-integrity: SKIP — a source was unavailable (§11.4.3); not a fake PASS." >&2 ;;
  *) echo "doc-integrity: config error (exit ${rc}); export/commit REFUSED." >&2; rc=1 ;;
esac
exit "${rc}"
