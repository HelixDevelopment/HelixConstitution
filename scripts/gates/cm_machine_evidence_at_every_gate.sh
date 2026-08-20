#!/usr/bin/env bash
# cm_machine_evidence_at_every_gate.sh — CM-MACHINE-EVIDENCE-AT-EVERY-GATE
# gate (§11.4.262(A)(B)(E) — every gate-verdict claim MUST cite a machine-
# created, machine-verifiable evidence artefact, bound to a specific
# §11.4.108 layer, content-addressed so it cannot silently go stale or be
# tampered with).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# §11.4.262 mandates: "every claim of works/passes/verified cites captured
# machine-derived machine-verifiable evidence ... cited by path + sha256 +
# timestamp (§11.4.207 content-addressed)" and binds every such claim to
# ONE of the closed §11.4.108 layers (SOURCE / ARTIFACT /
# RUNTIME-ON-CLEAN-TARGET / USER-VISIBLE) — "higher layer citing lower
# layer only = §11.4.226 wrong-layer violation". This gate reads a
# consumer-owned manifest of declared gate-verdict evidence rows
# (§11.4.28/§11.4.35 decoupling — the gate itself carries NO project
# literal) and, for EACH declared row, checks:
#   (1) the declared layer is a member of the CLOSED §11.4.108 set
#       {SOURCE, ARTIFACT, RUNTIME_ON_CLEAN_TARGET, USER_VISIBLE};
#   (2) the declared evidence file exists;
#   (3) the declared evidence file is non-empty (a zero-byte "evidence"
#       file is the canonical presence-without-content bluff §11.4.262
#       forbids);
#   (4) the evidence file's REAL sha256 matches the manifest's declared
#       sha256 — the content-addressed check per §11.4.207: a mismatch
#       means the evidence has gone STALE (regenerated since the verdict
#       was recorded) or TAMPERED (edited after the fact), either of
#       which invalidates the cited claim.
#
# Honest boundary (§11.4.6): this gate proves the CITED artefact exists,
# is non-empty, and is byte-identical to what was recorded at verdict time
# — it does NOT re-run the analyzer that produced the evidence, and does
# NOT itself judge whether the evidence CONTENT genuinely supports a PASS
# (that judgement is the analyzer's own job, self-validated per
# §11.4.107(10) and CM-EVIDENCE-ANALYZER-SELF-VALIDATED). This gate is the
# chain-of-custody check, not the content-correctness check.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_machine_evidence_at_every_gate.sh [--root <project-root>]
#                                        [--manifest <path>]
#     --root <dir>       project root (default: $CONSUMER_ROOT or ".").
#     --manifest <path>  TSV manifest of declared gate-verdict evidence
#                         rows, relative to --root unless absolute
#                         (default: docs/evidence/gate_evidence_manifest.tsv).
#                         Format, one row per non-blank/non-'#'-comment line:
#                             <gate_id><TAB><layer><TAB><evidence-path-relative-to-root><TAB><sha256>
#                         <layer> MUST be one of:
#                             SOURCE | ARTIFACT | RUNTIME_ON_CLEAN_TARGET | USER_VISIBLE
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Per-row OK/FAIL lines + final PASS/FAIL banner.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Read-only: computes sha256 of each declared evidence file. No writes.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, sha256sum. No shared lib required. Parses clean under `bash -n`.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.262 (this gate's mandate — machine-created evidence at every
#   gate), §11.4.108 (the closed four-layer taxonomy this gate validates
#   membership against), §11.4.207 (content-addressed evidence — the
#   sha256 chain-of-custody check), §11.4.226 (wrong-layer echo forbidden
#   — this gate proves LAYER MEMBERSHIP is declared + legal, it does not
#   itself catch a mislabelled layer whose evidence is real but attributed
#   to the wrong layer — that is a §11.4.194(6)(a) review-layer check),
#   §11.4.201 (a guard must assert the REAL condition — a false-positive
#   refusal of a genuinely-fresh, correctly-hashed artefact is a FAIL-bluff
#   exactly as accepting a stale/tampered one would be a PASS-bluff),
#   §11.4.28/§11.4.35 (decoupling — no project literal in this gate), §1.1
#   (paired mutation test cm_machine_evidence_at_every_gate_mutation_test.sh).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — every declared row has a legal layer, an existing non-empty
#       evidence file whose real sha256 matches the declared sha256. A
#       manifest declaring ZERO rows (or absent entirely) is a vacuous
#       PASS (§11.4.201(1) false-positive guard).
#   1 — any declared row fails any of the four checks.
#   2 — environment error (root not found).
#
# Classification: universal (§11.4.17).

set -u

GATE="CM-MACHINE-EVIDENCE-AT-EVERY-GATE"
ANCHOR="11.4.262"
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

root="${CONSUMER_ROOT:-.}"
manifest_rel="docs/evidence/gate_evidence_manifest.tsv"
while [ $# -gt 0 ]; do
    case "$1" in
        --root) root="$2"; shift 2 ;;
        --manifest) manifest_rel="$2"; shift 2 ;;
        -h|--help) sed -n '1,60p' "${BASH_SOURCE[0]:-$0}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "${GATE}: unknown arg '$1'" >&2; exit 2 ;;
    esac
done

[ -d "$root" ] || { echo "${GATE}: BLIND — project root not found: $root" >&2; exit 2; }
root="$(cd "$root" && pwd)"

case "$manifest_rel" in
    /*) manifest="$manifest_rel" ;;
    *) manifest="${root}/${manifest_rel}" ;;
esac

fail=0
declared=0

if [ ! -f "$manifest" ]; then
    echo "${GATE}: PASS — no gate-evidence manifest declared at '${manifest}' (nothing to validate, honest §11.4.201(1) vacuous case, §${ANCHOR})"
    exit 0
fi

is_legal_layer() {
    case "$1" in
        SOURCE|ARTIFACT|RUNTIME_ON_CLEAN_TARGET|USER_VISIBLE) return 0 ;;
        *) return 1 ;;
    esac
}

while IFS=$'\t' read -r gate_id layer evidence_rel declared_sha || [ -n "${gate_id:-}" ]; do
    case "$gate_id" in
        ''|'#'*) continue ;;
    esac
    if [ -z "${layer:-}" ] || [ -z "${evidence_rel:-}" ] || [ -z "${declared_sha:-}" ]; then
        echo "${GATE}: FAIL row for '${gate_id}' reason=MALFORMED_ROW (expected 4 tab-separated fields: gate_id, layer, evidence-path, sha256)"
        fail=$((fail + 1))
        continue
    fi
    declared=$((declared + 1))

    if ! is_legal_layer "$layer"; then
        echo "${GATE}: FAIL gate_id='${gate_id}' layer='${layer}' reason=INVALID_LAYER (must be one of SOURCE|ARTIFACT|RUNTIME_ON_CLEAN_TARGET|USER_VISIBLE)"
        fail=$((fail + 1))
        continue
    fi
    echo "${GATE}: OK gate_id='${gate_id}' layer='${layer}' is a legal §11.4.108 layer"

    case "$evidence_rel" in
        /*) evidence="$evidence_rel" ;;
        *) evidence="${root}/${evidence_rel}" ;;
    esac

    if [ ! -f "$evidence" ]; then
        echo "${GATE}: FAIL gate_id='${gate_id}' evidence='${evidence}' reason=EVIDENCE_MISSING"
        fail=$((fail + 1))
        continue
    fi

    if [ ! -s "$evidence" ]; then
        echo "${GATE}: FAIL gate_id='${gate_id}' evidence='${evidence}' reason=EVIDENCE_EMPTY"
        fail=$((fail + 1))
        continue
    fi
    echo "${GATE}: OK gate_id='${gate_id}' evidence file exists and is non-empty"

    real_sha="$(sha256sum "$evidence" 2>/dev/null | awk '{print $1}')"
    if [ "$real_sha" != "$declared_sha" ]; then
        echo "${GATE}: FAIL gate_id='${gate_id}' evidence='${evidence}' reason=EVIDENCE_HASH_MISMATCH declared=${declared_sha} real=${real_sha} (evidence is stale or tampered)"
        fail=$((fail + 1))
        continue
    fi
    echo "${GATE}: OK gate_id='${gate_id}' evidence sha256 matches declared value (content-addressed, §11.4.207)"
done < "$manifest"

echo "${GATE}: SUMMARY manifest=${manifest} declared=${declared} fail=${fail}"

if [ "$declared" -eq 0 ]; then
    echo "${GATE}: PASS — manifest declares zero rows (nothing to validate, honest §11.4.201(1) vacuous case, §${ANCHOR})"
    exit 0
fi

if [ "$fail" -gt 0 ]; then
    echo "${GATE}: FAIL — ${fail} sub-check(s) failed across ${declared} declared row(s) (§${ANCHOR})" >&2
    exit 1
fi

echo "${GATE}: PASS — all ${declared} declared row(s) have a legal layer, existing non-empty evidence, and a matching sha256 (§${ANCHOR})"
exit 0
