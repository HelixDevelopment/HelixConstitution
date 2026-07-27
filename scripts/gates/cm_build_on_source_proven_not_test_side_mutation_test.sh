#!/usr/bin/env bash
# cm_build_on_source_proven_not_test_side_mutation_test.sh — §1.1 paired-mutation
# meta-test for CM-BUILD-ON-SOURCE-PROVEN-NOT-TEST-SIDE (§11.4.235(A)).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves the gate is a genuine §11.4.201(1) DUAL-ASSERTION guard, not a bluff,
# with the §11.4.107(10) golden-good / golden-bad / negative-control set.
# Builds disposable marker fixtures + config files under a temp dir:
#   BAD-A (FAIL-A) : source_review_go PRESENT, build_launched ABSENT,
#                    test_instrumentation_blocking PRESENT
#                    -> gate MUST FAIL (build held behind test-side w/ src-GO).
#   BAD-B (FAIL-B) : build_launched PRESENT, source_review_go ABSENT
#                    -> gate MUST FAIL (build launched with no source-review GO).
#   GOOD  (launched clean) : source_review_go PRESENT, build_launched PRESENT,
#                    blocking ABSENT -> gate MUST PASS.
#   NEG-CTRL (§11.4.201(1) false-positive guard) : source_review_go PRESENT,
#                    build_launched ABSENT, blocking ABSENT — a NORMAL in-flight
#                    state (source GO, build not yet launched, nothing blocking)
#                    -> gate MUST PASS (must NOT fire FAIL-A).
#   SKIP-CYCLE     : neither go nor build present -> honest SKIP (exit 0).
#   SKIP-NOCONF    : no --config supplied at all -> honest SKIP (exit 0).
# The pair only proves the gate genuine if it FAILs on BOTH planted violations
# AND PASSes on the clean fixture AND the negative-control AND the honest-SKIP
# paths (the §1.1 discriminator + the §11.4.201(1) false-positive guard).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_build_on_source_proven_not_test_side_mutation_test.sh
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Creates + removes a temp fixture dir (trap-cleaned). No network/commit.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, the sibling cm_build_on_source_proven_not_test_side.sh. bash -n clean.
#
# ── Cross-references ──────────────────────────────────────────────────────────
#   §1.1, §11.4.235(A), §11.4.201(1) (false-positive guard), §11.4.107(10)
#   (golden-good/bad/negative-control), §11.4.3 (SKIP-with-reason).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — gate FAILs on both violations AND PASSes on clean + neg-control + skips.
#   1 — a discriminator case did not behave as required.
#   2 — environment error (gate script missing).
#
# Classification: universal (§11.4.17).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="${SCRIPT_DIR}/cm_build_on_source_proven_not_test_side.sh"

[ -f "$GATE" ] || { echo "META: gate script missing: $GATE" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cmbps_mut.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

rc=0
note() { echo "$@"; }
expect_fail() { local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then note "❌ META FAIL: ${desc} — gate PASSed on a planted violation (bluff gate!)"; rc=1
    else note "✅ META OK:   ${desc} — gate correctly FAILed"; fi; }
expect_pass() { local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then note "✅ META OK:   ${desc} — gate correctly PASSed / SKIPped (exit 0)"
    else note "❌ META FAIL: ${desc} — gate FAILed on a clean/honest fixture (false alarm!)"; rc=1; fi; }

# build a fixture dir with a config + markers.
# $1=name  $2=go(1/0)  $3=build(1/0)  $4=block(1/0)
mkfix() {
    local d="$TMP/$1"; mkdir -p "$d/markers"
    cat > "$d/config" <<EOF
source_review_go              = markers/source_review_go
build_launched                = markers/build_launched
test_instrumentation_blocking = markers/test_instrumentation_blocking
EOF
    [ "$2" = 1 ] && echo GO   > "$d/markers/source_review_go"
    [ "$3" = 1 ] && echo LAUNCHED > "$d/markers/build_launched"
    [ "$4" = 1 ] && echo BLOCKING > "$d/markers/test_instrumentation_blocking"
    echo "$d/config"
}

echo "======================================================================"
echo "§1.1 paired-mutation meta-test for CM-BUILD-ON-SOURCE-PROVEN-NOT-TEST-SIDE"
echo "fixtures under: $TMP"
echo "======================================================================"

expect_fail "BAD-A (src-GO, build not launched, test-side BLOCKING -> held-past-GO)" \
    bash "$GATE" --config "$(mkfix bad_a 1 0 1)"

expect_fail "BAD-B (build launched, NO source-review GO)" \
    bash "$GATE" --config "$(mkfix bad_b 0 1 0)"

expect_pass "GOOD (src-GO + build launched, nothing blocking)" \
    bash "$GATE" --config "$(mkfix good 1 1 0)"

expect_pass "NEG-CTRL (src-GO, build not yet launched, NOTHING blocking — normal in-flight, §11.4.201(1) false-positive guard)" \
    bash "$GATE" --config "$(mkfix neg 1 0 0)"

expect_pass "SKIP-CYCLE (no go, no build -> honest topology SKIP)" \
    bash "$GATE" --config "$(mkfix skipcycle 0 0 0)"

expect_pass "SKIP-NOCONF (no --config at all -> honest feature_disabled_by_config SKIP)" \
    env -u CM_BUILD_PROVEN_CONFIG bash "$GATE"

echo "======================================================================"
if [ "$rc" -eq 0 ]; then
    echo "✅ META PASS: CM-BUILD-ON-SOURCE-PROVEN-NOT-TEST-SIDE is a genuine (non-bluff) dual-assertion gate"
else
    echo "❌ META FAIL: CM-BUILD-ON-SOURCE-PROVEN-NOT-TEST-SIDE failed the §1.1 discriminator"
fi
echo "======================================================================"
exit "$rc"
