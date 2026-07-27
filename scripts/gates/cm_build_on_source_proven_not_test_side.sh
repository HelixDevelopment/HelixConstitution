#!/usr/bin/env bash
# cm_build_on_source_proven_not_test_side.sh — CM-BUILD-ON-SOURCE-PROVEN-NOT-TEST-SIDE
# gate (§11.4.235(A)).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# §11.4.235(A) mandates: the build's GO-SIGNAL is SOURCE-correctness alone
# (the mandatory independent review returned a clean GO on the source diff);
# test-side hardening (gate/mutation authoring, regression instrumentation +
# its re-review) is a DEPLOY-INDEPENDENT PARALLEL STAGE, NEVER a build gate.
# This gate is the §11.4.201(1) DUAL-ASSERTION guard the anchor declares:
#
#   FAIL-A  "build held past source-GO w/ unfinished test-instrumentation" —
#           the source is proven-correct (a source-review GO marker is
#           present) YET the build was NOT launched, and the reason is an
#           unfinished test-instrumentation stage that is being TREATED AS A
#           BUILD GATE (a "test-side is blocking the build" marker present).
#           Holding the build behind test-side work when source is GO is the
#           exact sequential anti-pattern §11.4.235(A) forbids.
#
#   FAIL-B  "build started with NO source-review GO" — a build WAS launched
#           but no source-correctness-review GO marker is present. The build
#           proceeded without its mandatory §11.4.125/§11.4.142/§11.4.194 →
#           §11.4.134 GO precondition.
#
# The two FAILs are the §11.4.201(1) dual assertion: a FALSE-POSITIVE refusal
# (blocking a legitimate not-yet-launched build whose source review is still
# genuinely running, with NO test-side-blocking marker) is a FAIL-bluff
# exactly as a false pass is; a build not-yet-launched with source GO but NO
# test-side-blocking marker is a NORMAL in-flight state and MUST PASS.
#
# ── Consumer binding (§11.4.28 / §11.4.35 — DATA, not engine code) ────────────
# The engine is project-agnostic. The consuming project supplies a small
# key=value config file (path via --config <file> or $CM_BUILD_PROVEN_CONFIG)
# declaring the paths to its own build/review MARKER files. Keys (all
# optional; a missing key ⇒ that marker is treated ABSENT):
#
#   source_review_go               = <path>   # exists+non-empty ⟺ the mandatory
#                                              #   source-correctness review
#                                              #   returned a clean GO for the
#                                              #   current batch (§11.4.134).
#   build_launched                 = <path>   # exists+non-empty ⟺ the build has
#                                              #   been triggered for the batch.
#   test_instrumentation_blocking  = <path>   # exists+non-empty ⟺ a test-
#                                              #   instrumentation stage is
#                                              #   unfinished AND is being
#                                              #   treated as a gate that blocks
#                                              #   the build (the violation flag).
#
# Marker paths are resolved relative to the config file's directory when not
# absolute. If NO config is supplied / the config file is absent, the gate
# has no binding on this host and SKIPs-with-reason (§11.4.3) —
# feature_disabled_by_config — NEVER a fake pass. If a config IS supplied but
# there is no active build/review cycle (neither source_review_go nor
# build_launched present), the gate SKIPs-with-reason (topology_unsupported:
# no build/review cycle in flight).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_build_on_source_proven_not_test_side.sh [--config <file>]
#   cm_build_on_source_proven_not_test_side.sh --print-example-config
#     --config <file>          consumer marker-binding config (else
#                              $CM_BUILD_PROVEN_CONFIG).
#     --print-example-config   print a documented example config template + exit.
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Resolved-evidence lines (each marker path + its present/absent state,
#   §11.4.201(5)) + a PASS / FAIL / SKIP verdict line.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None (read-only; no network, no commit, no device mutation).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash + POSIX test. Parses clean under bash -n.
#
# ── Cross-references ──────────────────────────────────────────────────────────
#   §11.4.235(A) (the mandate), §11.4.201(1)/(5) (false-positive refusal is a
#   FAIL-bluff + print resolved evidence), §11.4.3 (SKIP-with-reason when
#   unbound), §11.4.28/§11.4.35 (project-agnostic engine, consumer-owned
#   marker DATA), §11.4.6 (no-guessing — never fake a pass on an unresolvable
#   signal), §11.4.134/§11.4.125/§11.4.142/§11.4.194 (the source-review GO
#   the marker represents), §11.4.230(A) (parallel test-side stage),
#   §1.1 (paired mutation: cm_build_on_source_proven_not_test_side_mutation_test.sh).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — PASS (source-GO build launched cleanly, or a normal in-flight state)
#       OR honest SKIP (no consumer binding / no active cycle).
#   1 — FAIL-A (build held behind test-side with source-GO) or FAIL-B (build
#       launched with no source-review GO).
#   2 — environment / argument error.
#
# Classification: universal (§11.4.17) — no project-specific data in the engine.

set -euo pipefail

GATE="CM-BUILD-ON-SOURCE-PROVEN-NOT-TEST-SIDE"

config="${CM_BUILD_PROVEN_CONFIG:-}"
while [ $# -gt 0 ]; do
    case "$1" in
        --config) config="$2"; shift 2 ;;
        --print-example-config)
            cat <<'EOF'
# CM-BUILD-ON-SOURCE-PROVEN-NOT-TEST-SIDE marker-binding config (consumer DATA, §11.4.35).
# key = path ; relative paths resolve against THIS config file's directory.
# A marker "exists" for the gate iff its file is present AND non-empty.
source_review_go              = markers/source_review_go
build_launched                = markers/build_launched
test_instrumentation_blocking = markers/test_instrumentation_blocking
EOF
            exit 0 ;;
        -h|--help) sed -n '1,60p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "${GATE}: unknown arg '$1'" >&2; exit 2 ;;
    esac
done

# ── No consumer binding ⇒ honest SKIP (§11.4.3), never a fake pass ──────────
if [ -z "$config" ] || [ ! -f "$config" ]; then
    echo "⏭ ${GATE}: SKIP — feature_disabled_by_config: no consumer marker-binding config"
    echo "   (supply --config <file> or \$CM_BUILD_PROVEN_CONFIG; see --print-example-config)"
    exit 0
fi

config_dir="$(cd "$(dirname "$config")" && pwd)"

# Parse `key = value` (whitespace-tolerant, `#` comments) into resolved paths.
get_marker() { # $1=key -> echoes resolved path (empty if key absent)
    local key="$1" line val
    line="$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$config" | head -1 || true)"
    [ -n "$line" ] || { echo ""; return 0; }
    val="${line#*=}"
    # trim leading/trailing whitespace
    val="$(printf '%s' "$val" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -n "$val" ] || { echo ""; return 0; }
    case "$val" in
        /*) echo "$val" ;;
        *)  echo "${config_dir}/${val}" ;;
    esac
}

# present() : path exists AND non-empty
present() { [ -n "$1" ] && [ -s "$1" ]; }

p_go="$(get_marker source_review_go)"
p_build="$(get_marker build_launched)"
p_block="$(get_marker test_instrumentation_blocking)"

state() { present "$1" && echo PRESENT || echo ABSENT; }
echo "${GATE}: resolved markers (§11.4.201(5) evidence) —"
echo "   source_review_go              = ${p_go:-<unset>}  [$(state "$p_go")]"
echo "   build_launched                = ${p_build:-<unset>}  [$(state "$p_build")]"
echo "   test_instrumentation_blocking = ${p_block:-<unset>}  [$(state "$p_block")]"

has_go=0;    present "$p_go"    && has_go=1
has_build=0; present "$p_build" && has_build=1
has_block=0; present "$p_block" && has_block=1

# ── No active build/review cycle ⇒ honest SKIP (topology absent) ────────────
if [ "$has_go" -eq 0 ] && [ "$has_build" -eq 0 ]; then
    echo "⏭ ${GATE}: SKIP — topology_unsupported: no build/review cycle in flight"
    exit 0
fi

# ── FAIL-B: build launched with NO source-review GO ─────────────────────────
if [ "$has_build" -eq 1 ] && [ "$has_go" -eq 0 ]; then
    echo "❌ ${GATE}: FAIL — build launched with NO source-correctness-review GO marker (§11.4.235(A) / §11.4.134)"
    exit 1
fi

# ── FAIL-A: source GO, build NOT launched, held by a blocking test stage ────
if [ "$has_go" -eq 1 ] && [ "$has_build" -eq 0 ] && [ "$has_block" -eq 1 ]; then
    echo "❌ ${GATE}: FAIL — build HELD past source-GO by an unfinished test-instrumentation stage treated as a build gate (§11.4.235(A))"
    exit 1
fi

# ── Otherwise PASS (source-GO build launched; or a normal in-flight state) ──
echo "✅ ${GATE}: PASS — build gated on source-correctness alone; test-side work is not blocking the build (§11.4.235(A))"
exit 0
