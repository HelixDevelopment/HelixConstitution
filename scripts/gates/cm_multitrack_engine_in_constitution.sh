#!/usr/bin/env bash
# cm_multitrack_engine_in_constitution.sh — CM-MULTITRACK-ENGINE-IN-CONSTITUTION gate.
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# §11.4.187 (Automatic multi-track ruler orchestration) mandates that the
# generic ruler engine (config loader, alias↔worktree resolver, cwd-hook,
# bind/fallback/cooldown orchestrator, session launcher, rate-limit monitor,
# supervisor) lives at `constitution/scripts/multitrack/`, inherited BY
# REFERENCE (§11.4.28(B)/§11.4.177), carrying NO project-specific literal.
# This gate asserts THREE invariants against that directory:
#
#   1. PRESENCE — the directory exists and contains at least
#      `--min-scripts` (default 3) shebang-carrying scripts — proof it is a
#      real engine, not an empty placeholder.
#   2. DECOUPLING — no discovered script embeds a project-coupling literal:
#      a bare project basename (a one-word consumer name), an org identifier
#      (a code-host org handle), a reverse-domain package prefix (of the form
#      `com.<consumer>`), or a track-mount path COMBINED with the project
#      basename (of the form `/mnt/track<N>/<consumer>`). A NARROW, EXPLICIT
#      exemption applies to comment-only lines that are self-referentially
#      DOCUMENTING this very decoupling rule (e.g. "no `atmosphere` literal
#      here") — see the "Known false-positive" note below; this is the ONLY
#      exemption, and it requires BOTH (a) the line being a pure `#`-comment
#      line AND (b) the same line also containing the word "literal" (case-
#      insensitive), so a genuine embedded path/identifier is never
#      accidentally waved through. NOTE: a BARE `/mnt/track[0-9]` mount-point
#      path is deliberately NOT flagged — it is the generic multi-track
#      mount convention used as an illustrative example inside the
#      UNIVERSAL constitution text itself (§11.4.182), so the engine's own
#      generic test fixtures legitimately reference it; only the mount path
#      COMBINED with the project basename is treated as real coupling.
#   3. PARSEABILITY (§11.4.67) — every discovered script parses clean under
#      BOTH `bash -n` and `sh -n` (target-shell-parseability).
#
# Known false-positive this gate's exemption clause specifically closes
# (verified 2026-07-09 against the real constitution/scripts/multitrack/
# tree): `multitrack_bootstrap.sh` contains the comment line
#   "§11.4.28(B) / §11.4.177 (project-agnostic — no `atmosphere` literal here;"
# — a self-documenting mention of the RULE itself, not an embedded project
# literal. Without the exemption this gate would bluff-FAIL on its own
# decoupling documentation. The exemption is narrow by design (comment-only
# AND mentions "literal") so it cannot mask a real violation elsewhere.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_multitrack_engine_in_constitution.sh [--engine-dir <dir>] [--min-scripts N] [--quiet]
#     --engine-dir <dir>  path to the ruler engine directory to audit
#                         (default: MULTITRACK_ENGINE_DIR env, else the
#                         sibling `../multitrack` directory relative to this
#                         gate script's own location — i.e.
#                         constitution/scripts/multitrack/ when this gate
#                         runs from constitution/scripts/gates/).
#     --min-scripts N     minimum shebang-script count required (default 3).
#     --quiet             suppress per-file PASS lines (FAIL lines always shown).
#
# ── Inputs ───────────────────────────────────────────────────────────────────
#   MULTITRACK_ENGINE_DIR  env override for the engine directory (--engine-dir
#                          takes precedence). Project-agnostic per §11.4.28 —
#                          no consuming project's paths are hardcoded; the
#                          default is purely relative to this gate's own
#                          location inside the constitution submodule.
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Per-check PASS/FAIL lines on stdout + a final summary; nonzero exit on any
#   failed invariant.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None (read-only; no network, no commit, no device mutation).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, sh, POSIX find + grep. Parses clean under bash -n.
#
# ── Cross-references ──────────────────────────────────────────────────────────
#   §11.4.187 (automatic multi-track ruler orchestration), §11.4.28(B) +
#   §11.4.177 (project-decoupled shared tooling), §11.4.67 (target-shell-
#   parseability), §1.1 (paired mutation — re-introduce a project literal
#   into the engine → this gate FAILs).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — presence + decoupling + parseability all hold.
#   1 — at least one invariant violated.
#   2 — environment error (engine directory not found).
#
# Classification: universal (§11.4.17) — no project-specific data (the
# literal patterns checked FOR are project-shaped examples, not hardcoded
# assumptions about any particular consumer; a consuming project may extend
# the pattern set via --extra-literal, see below).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="CM-MULTITRACK-ENGINE-IN-CONSTITUTION"

engine_dir="${MULTITRACK_ENGINE_DIR:-${SCRIPT_DIR}/../multitrack}"
min_scripts=3
quiet=""
extra_literals=()

while [ $# -gt 0 ]; do
    case "$1" in
        --engine-dir)     engine_dir="$2"; shift 2 ;;
        --min-scripts)    min_scripts="$2"; shift 2 ;;
        --extra-literal)  extra_literals+=("$2"); shift 2 ;;
        --quiet)          quiet="1"; shift ;;
        -h|--help) sed -n '1,60p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "${GATE}: unknown arg '$1'" >&2; exit 2 ;;
    esac
done

if [ ! -d "$engine_dir" ]; then
    echo "❌ ${GATE}: FAIL — engine directory not found: $engine_dir" >&2
    exit 2
fi
engine_dir="$(cd "$engine_dir" && pwd)"

fail=0

# ── Invariant 1: PRESENCE ────────────────────────────────────────────────────
# A "script" here is any regular file whose first line is a shebang — this
# correctly counts extensionless launchers (multitrack-up / multitrack-down)
# alongside *.sh files, and correctly excludes non-script assets (README.md /
# .html / .pdf / .docx).
mapfile -t scripts < <(
    find "$engine_dir" -maxdepth 1 -type f 2>/dev/null | sort | while IFS= read -r f; do
        head -c 2 "$f" 2>/dev/null | grep -qF '#!' && printf '%s\n' "$f"
    done
)

script_count="${#scripts[@]}"
if [ "$script_count" -ge "$min_scripts" ]; then
    echo "✅ PRESENCE: ${script_count} shebang script(s) found under ${engine_dir} (>= ${min_scripts} required)"
else
    echo "❌ PRESENCE: only ${script_count} shebang script(s) found under ${engine_dir} (< ${min_scripts} required)"
    fail=1
fi

# ── Invariant 2: DECOUPLING (no project-coupling literal) ───────────────────
# Closed set of project-coupling literal patterns (extend via --extra-literal).
# The bare-word pattern `atmosphere` is intentionally checked case-
# insensitively with the narrow self-referential-comment exemption documented
# above; the other patterns (hardcoded consumer path, org id, reverse-domain
# package) are checked without that exemption since a genuine occurrence of
# any of THOSE is never a benign self-referential mention.
literal_patterns=("atmosphere")
for extra in "${extra_literals[@]:-}"; do
    [ -n "$extra" ] && literal_patterns+=("$extra")
done
# NOTE (§11.4.6 FACT, verified 2026-07-09): a bare `/mnt/track[0-9]` mount-
# point path is NOT project-coupling — it is the GENERIC multi-track mount
# convention used as an illustrative example inside the UNIVERSAL constitution
# text itself (constitution/Constitution.md §11.4.182: "parallel checkouts
# each on a distinct branch — e.g. `/mnt/track1..4`"). Flagging it would be a
# false-positive against the engine's own test fixtures (which legitimately
# use `/mnt/track1/proj`-style placeholders to exercise the generic
# resolver). Only the SPECIFIC combination of a track-mount path WITH the
# ATMOSphere project basename is a real coupling signal.
strict_patterns=("/mnt/track[0-9]+/atmosphere" "ATMOSphere1234321" "com\.atmosphere")

decoupling_violations=0
for f in "${scripts[@]}"; do
    rel="${f#"$engine_dir"/}"
    # bare-word "atmosphere" (case-insensitive) with the narrow exemption
    while IFS=: read -r lineno line; do
        [ -n "$lineno" ] || continue
        trimmed="$(printf '%s' "$line" | sed 's/^[[:space:]]*//')"
        case "$trimmed" in
            '#'*)
                if printf '%s' "$line" | grep -qi 'literal'; then
                    # exempt: comment-only line self-documenting the rule
                    continue
                fi
                ;;
        esac
        echo "❌ DECOUPLING: ${rel}:${lineno} embeds project-coupling literal 'atmosphere' — ${line}"
        decoupling_violations=$((decoupling_violations + 1))
    done < <(grep -in "atmosphere" "$f" 2>/dev/null)

    for pat in "${strict_patterns[@]}"; do
        while IFS=: read -r lineno line; do
            [ -n "$lineno" ] || continue
            echo "❌ DECOUPLING: ${rel}:${lineno} embeds project-coupling literal (pattern '${pat}') — ${line}"
            decoupling_violations=$((decoupling_violations + 1))
        done < <(grep -inE "$pat" "$f" 2>/dev/null)
    done
done

if [ "$decoupling_violations" -eq 0 ]; then
    echo "✅ DECOUPLING: no project-coupling literal found across ${script_count} script(s)"
else
    echo "❌ DECOUPLING: ${decoupling_violations} project-coupling literal(s) found"
    fail=1
fi

# ── Invariant 3: PARSEABILITY (bash -n + sh -n, §11.4.67) ───────────────────
parse_fail=0
for f in "${scripts[@]}"; do
    rel="${f#"$engine_dir"/}"
    if ! bash -n "$f" 2>/tmp/cm_mtec_bashn.$$; then
        echo "❌ PARSEABILITY: ${rel} fails bash -n: $(tr '\n' ' ' < /tmp/cm_mtec_bashn.$$)"
        parse_fail=$((parse_fail + 1))
    fi
    rm -f /tmp/cm_mtec_bashn.$$
    if ! sh -n "$f" 2>/tmp/cm_mtec_shn.$$; then
        echo "❌ PARSEABILITY: ${rel} fails sh -n: $(tr '\n' ' ' < /tmp/cm_mtec_shn.$$)"
        parse_fail=$((parse_fail + 1))
    fi
    rm -f /tmp/cm_mtec_shn.$$
    [ -n "$quiet" ] || echo "✅ PARSEABILITY: ${rel} clean (bash -n + sh -n)"
done

if [ "$parse_fail" -eq 0 ]; then
    echo "✅ PARSEABILITY: all ${script_count} script(s) parse clean under bash -n + sh -n"
else
    echo "❌ PARSEABILITY: ${parse_fail} parse failure(s) across the engine"
    fail=1
fi

echo "----------------------------------------------------------------------"
if [ "$fail" -eq 0 ]; then
    echo "✅ ${GATE}: PASS — presence + decoupling + parseability all hold (${engine_dir})"
    exit 0
fi
echo "❌ ${GATE}: FAIL — see violations above (${engine_dir})"
exit 1
