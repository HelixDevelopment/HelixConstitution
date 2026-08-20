#!/usr/bin/env bash
# cm_killpg_pgid_guard.sh — CM-KILLPG-PGID-GUARD gate (anchor §11.4.263).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# §11.4.263 (BOB-126 forensic anchor): a Python test bug — an unset
# AsyncMock().pid falling back to MagicMock's default __int__() == 1 — flowed
# into `os.getpgid(1)` → `os.killpg(1, SIGKILL)`, which is IDENTICAL on Linux
# to `kill(-1, SIGKILL)`: the disaster syscall that SIGKILLs every process the
# caller's UID owns. It SIGKILLed the operator's entire desktop session
# (systemd user manager, gnome-shell, tmux, ssh, browsers, Claude Code) SEVEN
# times over 48 hours.
#
# Clause (B) mandates: validate `isinstance(pid,int) and pid>1` AND
# `isinstance(pgid,int) and pgid>1` BEFORE every process-group signal call —
# `os.killpg` (Python), `syscall.Kill(-pgid,sig)` (Go), `nix::killpg` (Rust),
# `kill -<pgid>` / `pkill -g` (Bash), `killpg`/`kill(-pid,sig)` (C). This gate
# is the pre-build STATIC scanner half of clause (D)'s four-layer defense: it
# walks production source for a dangerous process-group-signal call site and
# FAILs when no guard comparing a pid/pgid/gid-named identifier to `1` via a
# `>`/`>=`/`-gt` comparator appears within a preceding window of source lines.
#
# ── Detection scope (honest, stated tradeoff — §11.4.6) ─────────────────────
# This is a bounded-window regex-proximity heuristic, NOT a data-flow or AST
# analysis (infeasible for a portable multi-language shell/awk scanner within
# this gate's scope). It WILL correctly clear the anchor's own prescribed
# guard idiom (`if isinstance(pid, int) and pid > 1: os.killpg(...)`) and WILL
# correctly flag the literal BOB-126 shape (a bare, unguarded
# `os.killpg(os.getpgid(proc.pid), signal.SIGKILL)`). A guard placed further
# than `KILLPG_GUARD_WINDOW` (default 6) lines above the call site, or one
# using an unusually-named guard variable outside the closed set
# `pid|pgid|gid|process_group|pgrp`, is a DOCUMENTED, BOUNDED limitation —
# never a silent one — rather than an attempt at full soundness this class of
# scanner cannot honestly claim.
#
# Shell-form detection is deliberately NARROW: an ordinary single-process
# `kill -9 $pid` MUST NOT be flagged (POSIX kill(2)'s process-group form
# requires a NEGATIVE pgid argument, and $pid here need not be negative), so
# only `pkill -g` and the unambiguous negated-pgid shell idiom
# `kill -"$pgid"` / `kill -${pgid}` (dash immediately followed by a
# variable-only pgid-token) are matched — precision over recall, honoring the
# brief's emphasis that false-positiving legitimately-safe code "matters
# enormously."
#
# Comment-prefixed lines (`#`/`//`) are stripped before matching so this
# gate's own doc-comments quoting `os.killpg(` (as above) are never
# self-flagged; `scripts/gates` is excluded from the default scan root's
# recursive walk for the same reason (this file + its mutation-test fixtures
# legitimately embed the dangerous literal as fixture text, never as a real
# call site).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_killpg_pgid_guard.sh [--root <dir>] [--window N] [--quiet]
#     --root <dir>   scan root (default: $KILLPG_GUARD_ROOT or "..")
#     --window N     guard-proximity window in preceding lines
#                     (default: $KILLPG_GUARD_WINDOW or 6)
#     --quiet        suppress per-file PASS lines (FAIL lines always shown)
#     -h|--help      print this header
#
# ── Environment overrides (§11.4.28/§11.4.35 — project-agnostic) ────────────
#   KILLPG_GUARD_ROOT       default scan root (else --root, else "..")
#   KILLPG_GUARD_WINDOW     guard-proximity window, lines (default 6)
#   KILLPG_GUARD_EXT        space-separated source extensions to scan
#                            (default: "py go rs c cc cpp h hpp sh bash")
#   KILLPG_GUARD_EXCLUDE    space-separated dir-name globs to prune
#                            (default: ".git node_modules vendor .venv
#                             __pycache__ scripts/gates out build dist")
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Per-hit evidence line (file:line + matched call-site text) + a final
#   PASS / FAIL verdict with the guarded/unguarded hit counts.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None (read-only; no network, no commit, no process signaled — the scanner
#   NEVER executes a real killpg/kill syscall, it only reads source text).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, find, grep (GNU or BSD ERE), awk. Parses clean under bash -n.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.263 (the anchor enforced — full clauses A-F), §11.4.201(1)/(7)(a)
#   (false-positive refusal is a FAIL-bluff; match structure not substring),
#   §11.4.6 (honest documented bounded limitation, never silent), §11.4.28/
#   §11.4.35 (project-agnostic, env-var-driven), §1.1 (paired mutation:
#   cm_killpg_pgid_guard_mutation_test.sh).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — PASS (no dangerous call site found, or every one found is guarded).
#   1 — FAIL (an unguarded process-group signal call site found).
#   2 — environment / argument error.
#
# Classification: universal (§11.4.17) — no project-specific literal.

set -uo pipefail

GATE="CM-KILLPG-PGID-GUARD"
ANCHOR="11.4.263"

root="${KILLPG_GUARD_ROOT:-..}"
window="${KILLPG_GUARD_WINDOW:-6}"
quiet=0

while [ $# -gt 0 ]; do
    case "$1" in
        --root) root="$2"; shift 2 ;;
        --window) window="$2"; shift 2 ;;
        --quiet) quiet=1; shift ;;
        -h|--help) sed -n '1,90p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "${GATE}: unknown arg '$1'" >&2; exit 2 ;;
    esac
done

case "$window" in
    ''|*[!0-9]*) echo "${GATE}: --window must be a non-negative integer, got '$window'" >&2; exit 2 ;;
esac

[ -d "$root" ] || { echo "${GATE}: scan root not found: $root" >&2; exit 2; }
root="$(cd "$root" && pwd)"

exts="${KILLPG_GUARD_EXT:-py go rs c cc cpp h hpp sh bash}"
excludes="${KILLPG_GUARD_EXCLUDE:-.git node_modules vendor .venv __pycache__ scripts/gates out build dist}"

# ── Build the `find` file-selector predicate (extensions) ──────────────────
find_name_expr=()
first=1
for e in $exts; do
    if [ "$first" -eq 1 ]; then first=0; else find_name_expr+=(-o); fi
    find_name_expr+=(-name "*.${e}")
done

# ── Build the `find` prune predicate (excluded dir-name globs, incl. paths
#    like "scripts/gates" matched against the tail of the path) ────────────
prune_expr=()
for ex in $excludes; do
    case "$ex" in
        */*) prune_expr+=(-path "*/${ex}" -o -path "*/${ex}/*" -o) ;;
        *)   prune_expr+=(-name "$ex" -o) ;;
    esac
done
# drop trailing -o
if [ "${#prune_expr[@]}" -gt 0 ]; then
    unset 'prune_expr[${#prune_expr[@]}-1]'
fi

mapfile -d '' -t files < <(
    if [ "${#prune_expr[@]}" -gt 0 ]; then
        find "$root" -type d \( "${prune_expr[@]}" \) -prune -o -type f \( "${find_name_expr[@]}" \) -print0
    else
        find "$root" -type f \( "${find_name_expr[@]}" \) -print0
    fi
)

if [ "${#files[@]}" -eq 0 ]; then
    echo "⏭ ${GATE}: SKIP — topology_unsupported: no source files under scan (root=$root, ext=[$exts])"
    exit 0
fi

# ── Dangerous call-site ERE (comment-stripped lines only) ──────────────────
#   * Python/Go/Rust/C:  killpg(          — os.killpg / killpg / nix::killpg
#   * Go:                syscall.Kill(-   — process-GROUP form (negative pgid)
#   * C/generic:          kill(-           — kill(-pid,sig) process-group form
#   * shell:              pkill -g        — pkill's explicit process-group flag
#   * shell:              kill -"$pgid" / kill -${pgid}  — negated-pgid idiom
CALL_ERE='killpg[[:space:]]*\(|syscall\.Kill[[:space:]]*\([[:space:]]*-|(^|[^[:alnum:]_])kill[[:space:]]*\([[:space:]]*-|pkill[[:space:]]+-g[[:space:]]|kill[[:space:]]+-"?\$\{?[A-Za-z_][A-Za-z0-9_]*\}?"?'

# Guard-proximity ERE: a pid/pgid/gid-family identifier compared to 1 via
# ANY ordering comparator (>, >=, <, <=, -gt, -ge, -lt, -le; either operand
# order; either language's syntax). Broadened deliberately (§11.4.201 — a
# false-positive refusal is exactly as forbidden as a false-negative pass):
# both the affirmative "if pid > 1: dangerous()" idiom AND the equally
# legitimate negated raise-early idiom "if pid <= 1: raise(...)" are real,
# common guard shapes and BOTH must clear this gate without a false refusal.
GUARD_ERE='(pid|pgid|gid|process_group|pgrp)[A-Za-z0-9_]*[[:space:]]*(>=?|<=?|-gt|-ge|-lt|-le)[[:space:]]*1([^0-9]|$)|1[[:space:]]*(<=?|>=?)[[:space:]]*(pid|pgid|gid|process_group|pgrp)'

unguarded=0
guarded=0

for f in "${files[@]}"; do
    # Strip comment-prefixed lines (# ... or // ...) before matching so this
    # gate's own doc-comments, and any project's comment-only mentions, are
    # never treated as real call sites (§11.4.201(7)(a) — match structure,
    # not substring; a doc mention is a CARRIER, not the thing itself).
    code_only="$(sed -E 's/^[[:space:]]*(#|\/\/).*$//' "$f" 2>/dev/null || true)"
    [ -n "$code_only" ] || continue

    hit_lines="$(printf '%s\n' "$code_only" | grep -nE "$CALL_ERE" 2>/dev/null || true)"
    [ -n "$hit_lines" ] || continue

    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        lineno="${hit%%:*}"
        text="${hit#*:}"

        start=$(( lineno - window ))
        [ "$start" -lt 1 ] && start=1

        window_text="$(printf '%s\n' "$code_only" | sed -n "${start},${lineno}p")"

        if printf '%s\n' "$window_text" | grep -qE "$GUARD_ERE"; then
            guarded=$(( guarded + 1 ))
            [ "$quiet" -eq 1 ] || echo "✅ ${GATE}: PASS — guarded process-group signal call at ${f}:${lineno}: ${text# }"
        else
            unguarded=$(( unguarded + 1 ))
            echo "❌ ${GATE}: FAIL — UNGUARDED process-group signal call at ${f}:${lineno}: ${text# }"
            echo "   (no pid/pgid>1 comparator found in the preceding ${window} lines — §11.4.263(B))"
        fi
    done <<< "$hit_lines"
done

echo "======================================================================"
if [ "$unguarded" -gt 0 ]; then
    echo "❌ ${GATE}: FAIL — ${unguarded} unguarded process-group signal call site(s), ${guarded} guarded (§${ANCHOR})"
    exit 1
fi

if [ "$guarded" -gt 0 ]; then
    echo "✅ ${GATE}: PASS — ${guarded} process-group signal call site(s), all guarded (§${ANCHOR})"
else
    echo "✅ ${GATE}: PASS — no process-group signal call sites found under scan root (§${ANCHOR})"
fi
exit 0
