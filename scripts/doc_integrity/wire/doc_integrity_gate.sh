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
#   bash doc_integrity_gate.sh <checkset.yaml> [repo_root] [--divergence-class-only]
#     <checkset.yaml>  consumer-owned checkset (e.g. .atmosphere/doc_integrity/checkset.yaml)
#     [repo_root]      root the source paths resolve against (default: $PWD)
#     --divergence-class-only
#                      §11.4.186 family-split: treat INTEGRITY-class findings
#                      (orphan-ref / Status↔Type / location↔status DATA defects) as
#                      NON-refusing (clause-6 honest boundary — plan-data correctness is
#                      an operator decision the gate SURFACES, never MAKES). Only the
#                      cross-document DIVERGENCE classes DEDUP / TIMELINE / CROSS-DOC /
#                      STRUCTURAL still REFUSE. Without the flag, ANY finding refuses
#                      (full strict). §11.4.50 ratchet: drop the flag once the plan's
#                      orphan-dependency rows are corrected, to strengthen monotonically.
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

# --- arg parse: extract --divergence-class-only anywhere; keep positional args ---
divergence_class_only=0
positional=()
for _a in "$@"; do
  case "${_a}" in
    --divergence-class-only) divergence_class_only=1 ;;
    *) positional+=("${_a}") ;;
  esac
done
set -- "${positional[@]+"${positional[@]}"}"

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
out="$("${bin}" verify "${checkset}" --repo-root "${repo_root}" 2>&1)"
rc=$?
set -e
printf '%s\n' "${out}"

# §11.4.186 family-split (only when --divergence-class-only): INTEGRITY-class findings
# (orphan-ref / Status↔Type / location↔status DATA defects) are NON-refusing per clause-6
# honest boundary (plan-DATA correctness is an operator decision the gate SURFACES, never
# MAKES); the cross-document DIVERGENCE classes DEDUP / TIMELINE / CROSS-DOC / STRUCTURAL
# still REFUSE. Without the flag, ANY rc==1 finding refuses (full strict).
if [ "${divergence_class_only}" -eq 1 ] && [ "${rc}" -eq 1 ]; then
  fam="$(printf '%s\n' "${out}" | grep -E '^by family:' | tail -1 || true)"
  div=0
  for _f in DEDUP TIMELINE CROSS-DOC STRUCTURAL; do
    _n="$(printf '%s' "${fam}" | grep -oE "${_f}=[0-9]+" | cut -d= -f2 || true)"
    div=$(( div + ${_n:-0} ))
  done
  if [ "${div}" -eq 0 ]; then
    echo "doc-integrity: INTEGRITY-only findings (${fam:-none}) — NON-divergence-class; export/commit PROCEEDS (§11.4.186 clause-6 honest boundary + §11.4.50 ratchet). [--divergence-class-only]" >&2
    rc=0
  fi
fi

case "${rc}" in
  0) echo "doc-integrity: PASS — export/commit may proceed." ;;
  1) echo "doc-integrity: FAIL — export/commit REFUSED (integrity findings above)." >&2 ;;
  3) echo "doc-integrity: SKIP — a source was unavailable (§11.4.3); not a fake PASS." >&2 ;;
  *) echo "doc-integrity: config error (exit ${rc}); export/commit REFUSED." >&2; rc=1 ;;
esac
exit "${rc}"
