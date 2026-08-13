#!/usr/bin/env bash
# cm_version_increment_on_deploy.sh — CM-VERSION-INCREMENT-ON-DEPLOY gate
# (§11.4.235(B)).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# §11.4.235(B) mandates: the moment image(s)/artifact(s) deploy, the version
# id is INCREMENTED — every deployed artifact carries a DISTINCT, monotonic,
# greppable id (§11.4.151/§11.4.108/§11.4.200). "Two deployments sharing one
# version id defeats per-deploy artifact identity → §11.4.235(B) violation."
#
# This gate FAILs when a NEW-artifact deploy shares a version id with a prior
# deploy — i.e. when the deploy ledger records ONE version id against TWO OR
# MORE DISTINCT artifact fingerprints. A re-deploy of the IDENTICAL artifact
# (same fingerprint) under the same version id is NOT a new-artifact deploy
# and is the §11.4.201(1) NEGATIVE-CONTROL that MUST PASS (never a false
# positive).
#
# ── Consumer binding (§11.4.28 / §11.4.35 — DATA, not engine code) ────────────
# Project-agnostic engine. The consuming project supplies a key=value config
# (path via --config <file> or $CM_VERSION_DEPLOY_CONFIG) declaring ONE key:
#
#   deploy_ledger = <path>   # append-only TSV; one row per deploy:
#                            #   <version_id>\t<artifact_fingerprint>
#                            # `#`-comment + blank lines ignored.
#
# The ledger path resolves relative to the config file's directory when not
# absolute. NO config / config absent ⇒ honest SKIP (§11.4.3) —
# feature_disabled_by_config. deploy_ledger unset / file absent / zero data
# rows ⇒ honest SKIP — topology_unsupported (no deploys recorded). NEVER a
# fake pass (§11.4.6).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_version_increment_on_deploy.sh [--config <file>]
#   cm_version_increment_on_deploy.sh --print-example-config
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Resolved-ledger evidence (§11.4.201(5)) + PASS / FAIL / SKIP verdict.
#   On FAIL, names the offending version id + its distinct fingerprints.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None (read-only). No network/commit/device mutation.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash + awk. Parses clean under bash -n.
#
# ── Cross-references ──────────────────────────────────────────────────────────
#   §11.4.235(B), §11.4.151/§11.4.108/§11.4.200 (per-deploy artifact identity),
#   §11.4.201(1)/(5) (negative-control + resolved evidence), §11.4.3 (SKIP),
#   §11.4.28/§11.4.35 (decoupled engine + consumer DATA), §11.4.6 (no fake
#   pass), §1.1 (paired mutation: cm_version_increment_on_deploy_mutation_test.sh).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — PASS (every version id maps to one artifact) OR honest SKIP.
#   1 — FAIL (≥1 version id shared by ≥2 distinct artifact fingerprints).
#   2 — environment / argument error.
#
# Classification: universal (§11.4.17) — no project-specific data in the engine.

set -euo pipefail

GATE="CM-VERSION-INCREMENT-ON-DEPLOY"

config="${CM_VERSION_DEPLOY_CONFIG:-}"
while [ $# -gt 0 ]; do
    case "$1" in
        --config) config="$2"; shift 2 ;;
        --print-example-config)
            cat <<'EOF'
# CM-VERSION-INCREMENT-ON-DEPLOY marker-binding config (consumer DATA, §11.4.35).
# deploy_ledger : append-only TSV, one row per deploy: <version_id>\t<artifact_fingerprint>
deploy_ledger = deploys.tsv
EOF
            exit 0 ;;
        -h|--help) sed -n '1,55p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "${GATE}: unknown arg '$1'" >&2; exit 2 ;;
    esac
done

if [ -z "$config" ] || [ ! -f "$config" ]; then
    echo "⏭ ${GATE}: SKIP — feature_disabled_by_config: no consumer deploy-ledger binding"
    echo "   (supply --config <file> or \$CM_VERSION_DEPLOY_CONFIG; see --print-example-config)"
    exit 0
fi

config_dir="$(cd "$(dirname "$config")" && pwd)"

line="$(grep -E "^[[:space:]]*deploy_ledger[[:space:]]*=" "$config" | head -1 || true)"
ledger=""
if [ -n "$line" ]; then
    val="${line#*=}"
    val="$(printf '%s' "$val" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    case "$val" in
        /*) ledger="$val" ;;
        "") ledger="" ;;
        *)  ledger="${config_dir}/${val}" ;;
    esac
fi

if [ -z "$ledger" ] || [ ! -f "$ledger" ]; then
    echo "⏭ ${GATE}: SKIP — topology_unsupported: deploy_ledger unset or file absent (${ledger:-<unset>})"
    exit 0
fi

# Count data rows (non-comment, non-blank).
data_rows="$(awk -F'\t' '
    /^[[:space:]]*#/ {next}
    { t=$1; gsub(/^[[:space:]]+|[[:space:]]+$/,"",t); if(t=="") next; n++ }
    END{ print n+0 }' "$ledger")"

echo "${GATE}: deploy_ledger = ${ledger}  [data rows: ${data_rows}]  (§11.4.201(5) evidence)"

if [ "${data_rows:-0}" -eq 0 ]; then
    echo "⏭ ${GATE}: SKIP — topology_unsupported: no deploys recorded in the ledger"
    exit 0
fi

# Detect any version id bound to >1 DISTINCT artifact fingerprint.
report="$(awk -F'\t' '
    /^[[:space:]]*#/ {next}
    {
        v=$1; f=$2;
        gsub(/^[[:space:]]+|[[:space:]]+$/,"",v);
        gsub(/^[[:space:]]+|[[:space:]]+$/,"",f);
        if(v=="") next;
        key=v SUBSEP f;
        if(!(key in seen)){ seen[key]=1; cnt[v]++; lst[v]=lst[v] (lst[v]==""?"":", ") f; }
    }
    END{
        bad=0;
        for(v in cnt){ if(cnt[v]>1){ printf "OFFENDER version_id=%s distinct_fingerprints=[%s]\n", v, lst[v]; bad=1 } }
        exit bad
    }' "$ledger")" && awk_rc=0 || awk_rc=$?

if [ "$awk_rc" -eq 1 ]; then
    echo "$report"
    echo "❌ ${GATE}: FAIL — a version id is shared by ≥2 distinct deployed artifacts (§11.4.235(B))"
    exit 1
fi

echo "✅ ${GATE}: PASS — every deployed artifact carries a distinct version id (§11.4.235(B))"
exit 0
