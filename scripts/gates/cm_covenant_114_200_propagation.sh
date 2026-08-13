#!/usr/bin/env bash
# cm_covenant_114_200_propagation.sh — CM-COVENANT-114-200-PROPAGATION gate (non-targetable deploy/flash tooling MUST isolate exactly ONE eligible target and VERIFY-AFTER-WRITE on the INTENDED target).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# §11.4.200 (non-targetable deploy/flash tooling MUST isolate exactly ONE eligible target and VERIFY-AFTER-WRITE on the INTENDED target) requires
# the anchor literal `11.4.200` to be present in every owned governance
# context-carrier file (CLAUDE.md / AGENTS.md / QWEN.md / GEMINI.md) across the
# consumer fleet, per the §11.4.157 five-carrier-lockstep + §11.4.35
# inheritance rules. This gate scans the fleet, reports which carriers carry
# the literal (PRESENT) and which are MISSING it, and exits nonzero if any
# discovered carrier omits it.
#
# Mirrors the house propagation-gate concept (literal-anchor presence across
# the consumer fleet) used by every other CM-COVENANT-114-NNN-PROPAGATION
# gate — modeled verbatim on cm_covenant_114_187_propagation.sh (only the
# ANCHOR/GATE constants + this header differ).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_covenant_114_200_propagation.sh [--root <consumer-root>] [--quiet]
#     --root <dir>   consumer fleet root to scan (default: $CONSUMER_ROOT or "..")
#     --quiet        suppress the per-file PASS lines (FAIL lines always shown)
#
# ── Inputs ───────────────────────────────────────────────────────────────────
#   CONSUMER_ROOT  env override for the fleet root (arg --root takes precedence).
#   The gate discovers carriers by name (CLAUDE.md / AGENTS.md / QWEN.md /
#   GEMINI.md) under the root, EXCLUDING vendored / third-party trees that are
#   not authored by us (node_modules, .git, out, build, dist, prebuilts,
#   external, vendor, target). Project-agnostic per §11.4.28 — no consuming
#   project's paths are hardcoded.
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Per-carrier PASS/FAIL lines on stdout + a final summary; nonzero exit on any
#   MISSING owned carrier.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None (read-only; no network, no commit, no device mutation).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, POSIX find + grep. Parses clean under bash -n.
#
# ── Cross-references ──────────────────────────────────────────────────────────
#   §11.4.200 (deploy-target isolation + verify-after-write), §11.4.157
#   (five-carrier lockstep), §11.4.35 (inheritance), §11.4.28 (decoupling),
#   §11.4.108 / §11.4.111 / §11.4.130 (the artifact→runtime + resolve-by-stable-name anchors §11.4.200 applies to the deployment step), §1.1 (paired mutation — strip
#   the literal from a carrier → this gate FAILs). Note (§11.4.6 honest
#   boundary): this gate checks the four MIRROR carriers
#   (CLAUDE/AGENTS/QWEN/GEMINI.md) — Constitution.md itself is the anchor's own
#   source-of-truth location and is guaranteed to carry the literal by
#   construction, so it is intentionally not re-scanned here (same convention
#   as cm_covenant_114_187_propagation.sh).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — every discovered owned carrier carries the `11.4.200` literal.
#   1 — at least one discovered owned carrier is MISSING the literal.
#   2 — environment error (root not found, no carriers discovered).
#
# Classification: universal (§11.4.17) — no project-specific data.

set -euo pipefail

ANCHOR="11.4.200"
GATE="CM-COVENANT-114-200-PROPAGATION"

root="${CONSUMER_ROOT:-..}"
quiet=""
while [ $# -gt 0 ]; do
    case "$1" in
        --root)  root="$2"; shift 2 ;;
        --quiet) quiet="1"; shift ;;
        -h|--help) sed -n '1,45p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "${GATE}: unknown arg '$1'" >&2; exit 2 ;;
    esac
done

[ -d "$root" ] || { echo "${GATE}: consumer root not found: $root" >&2; exit 2; }
root="$(cd "$root" && pwd)"

# §11.4.28/§11.4.177 — inherit the shared §11.4.35 pointer-carrier predicate BY
# REFERENCE (never a copy). Resolve relative to THIS script's dir, not cwd.
_pc_lib="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib/pointer_carrier.sh"
if [ -r "$_pc_lib" ]; then
    # shellcheck source=lib/pointer_carrier.sh
    . "$_pc_lib"
else
    echo "${GATE}: shared pointer-carrier lib not found at $_pc_lib" >&2
    exit 2
fi

# Discover owned governance carriers, excluding non-authored trees.
carriers="$(find "$root" \
    \( -path '*/node_modules' -o -path '*/.git' -o -path '*/out' \
       -o -path '*/build' -o -path '*/dist' -o -path '*/prebuilts' \
       -o -path '*/external' -o -path '*/vendor' -o -path '*/target' \) -prune \
    -o \( -type f \( -name 'CLAUDE.md' -o -name 'AGENTS.md' \
       -o -name 'QWEN.md' -o -name 'GEMINI.md' \) -print \) 2>/dev/null | sort)"

if [ -z "${carriers//[$' \t\r\n']/}" ]; then
    echo "${GATE}: no governance carriers (CLAUDE/AGENTS/QWEN/GEMINI.md) found under $root" >&2
    exit 2
fi

pass=0 fail=0 skip=0
while IFS= read -r f; do
    [ -n "$f" ] || continue
    if grep -qF "$ANCHOR" "$f"; then
        pass=$((pass + 1))
        [ -n "$quiet" ] || echo "✅ PRESENT  ${f#"$root"/}"
    elif is_pointer_carrier "$f" 2>/dev/null; then
        # §11.4.35 pointer-inheritance consumer — inherits the anchor BY POINTER,
        # legitimately does NOT restate the literal. Skipping it is the
        # §11.4.201(1) false-positive fix, NOT an over-skip: a NON-pointer
        # carrier that omits the literal still falls through to MISSING below.
        skip=$((skip + 1))
        [ -n "$quiet" ] || echo "⏭ POINTER-INHERITANCE-SKIP  ${f#"$root"/}  — §11.4.35 pointer consumer (inherits ${ANCHOR} by pointer)"
    else
        fail=$((fail + 1))
        echo "❌ MISSING  ${f#"$root"/}  — lacks anchor literal ${ANCHOR}"
    fi
done <<< "$carriers"

echo "----------------------------------------------------------------------"
echo "${GATE}: ${pass} PRESENT, ${skip} POINTER-INHERITANCE-SKIP, ${fail} MISSING (anchor ${ANCHOR}) under ${root}"
if [ "$fail" -gt 0 ]; then
    echo "❌ ${GATE}: FAIL — ${fail} owned carrier(s) missing §11.4.200 anchor"
    exit 1
fi
echo "✅ ${GATE}: PASS — every owned carrier carries §11.4.200"
exit 0
