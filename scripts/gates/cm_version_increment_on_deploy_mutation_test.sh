#!/usr/bin/env bash
# cm_version_increment_on_deploy_mutation_test.sh — §1.1 paired-mutation
# meta-test for CM-VERSION-INCREMENT-ON-DEPLOY (§11.4.235(B)).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves the gate is genuine with the §11.4.107(10) golden-good / golden-bad /
# negative-control set. Builds disposable deploy-ledger fixtures + configs:
#   BAD      : two DISTINCT artifact fingerprints share ONE version id
#              -> gate MUST FAIL (§11.4.235(B) — two deploys, one version id).
#   GOOD     : distinct version id per distinct artifact -> gate MUST PASS.
#   NEG-CTRL : the SAME artifact (identical fingerprint) re-deployed under the
#              SAME version id -> NOT a new-artifact deploy -> gate MUST PASS
#              (§11.4.201(1) false-positive guard).
#   SKIP-EMPTY : ledger with only comments/blank rows -> honest SKIP (exit 0).
#   SKIP-NOCONF: no --config at all -> honest SKIP (exit 0).
# The pair only proves the gate genuine if it FAILs on the collision AND
# PASSes on distinct-ids AND the identical-redeploy negative-control AND the
# honest-SKIP paths (the §1.1 discriminator + §11.4.201(1) false-positive
# guard).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_version_increment_on_deploy_mutation_test.sh
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Creates + removes a temp fixture dir (trap-cleaned). No network/commit.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, the sibling cm_version_increment_on_deploy.sh. bash -n clean.
#
# ── Cross-references ──────────────────────────────────────────────────────────
#   §1.1, §11.4.235(B), §11.4.201(1) (false-positive guard), §11.4.107(10)
#   (golden-good/bad/negative-control), §11.4.3 (SKIP-with-reason).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — gate FAILs on the collision AND PASSes on good + neg-control + skips.
#   1 — a discriminator case did not behave as required.
#   2 — environment error (gate script missing).
#
# Classification: universal (§11.4.17).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="${SCRIPT_DIR}/cm_version_increment_on_deploy.sh"

[ -f "$GATE" ] || { echo "META: gate script missing: $GATE" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cmvid_mut.XXXXXX")"
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

# $1=name  $2..=ledger rows (each "version_id<TAB>fingerprint"); writes config+ledger, echoes config path.
mkfix() {
    local name="$1"; shift
    local d="$TMP/$name"; mkdir -p "$d"
    echo "deploy_ledger = deploys.tsv" > "$d/config"
    : > "$d/deploys.tsv"
    local row
    for row in "$@"; do printf '%s\n' "$row" >> "$d/deploys.tsv"; done
    echo "$d/config"
}
TAB=$'\t'

echo "======================================================================"
echo "§1.1 paired-mutation meta-test for CM-VERSION-INCREMENT-ON-DEPLOY"
echo "fixtures under: $TMP"
echo "======================================================================"

expect_fail "BAD (two distinct artifacts share version_id v1)" \
    bash "$GATE" --config "$(mkfix bad "v1${TAB}fpA" "v1${TAB}fpB")"

expect_pass "GOOD (distinct version id per distinct artifact)" \
    bash "$GATE" --config "$(mkfix good "v1${TAB}fpA" "v2${TAB}fpB")"

expect_pass "NEG-CTRL (same artifact re-deployed under same version id — §11.4.201(1) false-positive guard)" \
    bash "$GATE" --config "$(mkfix neg "v1${TAB}fpA" "v1${TAB}fpA")"

expect_pass "SKIP-EMPTY (ledger has only a comment/blank row -> honest topology SKIP)" \
    bash "$GATE" --config "$(mkfix skipempty "# header only" "")"

expect_pass "SKIP-NOCONF (no --config at all -> honest feature_disabled_by_config SKIP)" \
    env -u CM_VERSION_DEPLOY_CONFIG bash "$GATE"

echo "======================================================================"
if [ "$rc" -eq 0 ]; then
    echo "✅ META PASS: CM-VERSION-INCREMENT-ON-DEPLOY is a genuine (non-bluff) gate"
else
    echo "❌ META FAIL: CM-VERSION-INCREMENT-ON-DEPLOY failed the §1.1 discriminator"
fi
echo "======================================================================"
exit "$rc"
