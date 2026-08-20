#!/usr/bin/env bash
# covenant_propagation_wrappers_generate.sh — regeneration mechanism (§11.4.77)
# for the THIN CM-COVENANT-114-<N>-PROPAGATION gate + mutation-test wrappers.
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Per §11.4.251 the gate LOGIC lives once in
# `lib/covenant_propagation_engine.sh` and the §1.1 mutation HARNESS lives once
# in `lib/covenant_propagation_mutation_engine.sh`; the role values live in the
# DATA PACK `covenant_propagation_anchors.tsv`. What remains per gate is a thin
# wrapper that carries ONLY its own gate NAME and delegates. The wrappers must
# exist as real files because the §11.4.227(A) gate ledger's structural
# instrument (`grep -rlE --include='*.sh'`) requires a real, executable,
# non-mutation-test `.sh` gate site naming the gate — a data-pack row alone is
# a CARRIER, not an implementation (§11.4.201(7)(a)).
#
# This script REGENERATES those wrappers deterministically from the data pack,
# so the wrapper set can never silently drift from it. It is idempotent: a
# re-run over an unchanged data pack rewrites byte-identical files. It carries
# NO gate-name literal of its own (every name is read from the data pack at
# run time), so it can never be mistaken by the ledger for a gate site.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   covenant_propagation_wrappers_generate.sh [--check]
#     (no args)  (re)write every wrapper named in the data pack
#     --check    verify every wrapper exists and matches what would be
#                generated; exit 1 on any drift (nothing is written)
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Writes/chmods `cm_covenant_114_<N>_propagation.sh` and
#   `cm_covenant_114_<N>_propagation_mutation_test.sh` beside itself. `--check`
#   is read-only (uses a mktemp scratch dir).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, awk, sed, cmp. Parses clean under bash -n.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.251 (no byte-identical forks — role-as-data-pack), §11.4.227(A)
#   (why a real .sh gate site per gate is required), §11.4.77 (a generated
#   artifact needs a committed regeneration mechanism), §11.4.18 (script
#   documentation), §1.1.
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — wrappers written (default) / no drift (--check).
#   1 — drift detected (--check only).
#   2 — environment error (data pack missing/empty).
#
# Classification: universal (§11.4.17).

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PACK="${COVENANT_PROPAGATION_ANCHORS:-${HERE}/covenant_propagation_anchors.tsv}"
MODE="${1:-write}"

[ -r "$PACK" ] || { echo "generate: data pack not readable: $PACK" >&2; exit 2; }

rows="$(awk -F'\t' '/^#/{next} NF>=2 && $1!="" {print $1"\t"$2}' "$PACK")"
[ -n "$rows" ] || { echo "generate: data pack $PACK yielded zero rows" >&2; exit 2; }

emit_gate() { # $1=gate  $2=anchor  $3=outfile  $4=display-basename (real wrapper name)
    # $4 is REQUIRED so `--check` can render into a scratch path while still
    # emitting the byte-identical form of the REAL file: the header embeds the
    # wrapper's own filename, so rendering with the scratch basename would make
    # every file look "drifted" — a §11.4.201(1) false-positive refusal.
    local gate="$1" anchor="$2" out="$3" base="${4:-$(basename "$3")}"
    cat > "$out" <<WRAP
#!/usr/bin/env bash
# ${base} — ${gate} gate (anchor §${anchor}).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# §11.4.227(B) anchor-block integrity for §${anchor}: the anchor's BLOCK (its
# own governance paragraph, not merely the bare literal \`${anchor}\`) MUST be
# present EXACTLY ONCE in every owned governance context-carrier
# (CLAUDE.md / AGENTS.md / QWEN.md / GEMINI.md) across the consumer fleet
# (§11.4.157 lockstep, §11.4.35 inheritance), and every such block MUST be
# BYTE-IDENTICAL across the carriers that carry it. Block-STARTS are counted
# (line-anchored), never bare literals — a mid-body citation is a CARRIER
# (§11.4.201(7)(a)); a genuine §11.4.35 pointer-inheritance consumer carrying
# zero blocks is an honest SKIP, never a MISSING (§11.4.201(1)).
#
# ── Thin-wrapper rationale (§11.4.251) ───────────────────────────────────────
# Every gate in this family runs the IDENTICAL check and differs only in its
# gate NAME and anchor NUMBER. Keeping one full copy of the ~400-line check per
# gate would be exactly the near-identical fork §11.4.251 forbids, so the code
# lives ONCE in \`lib/covenant_propagation_engine.sh\` and the role values live
# in the data pack \`covenant_propagation_anchors.tsv\`. This file carries only
# its own gate name — required because the §11.4.227(A) ledger's structural
# instrument needs a real executable \`.sh\` gate site naming the gate. It is
# generated by \`covenant_propagation_wrappers_generate.sh\` (§11.4.77); edit
# the engine or the data pack, never this file by hand.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   ${base} [--root <consumer-root>] [--quiet]
#     --root <dir>   consumer fleet root to scan (default: \$CONSUMER_ROOT or "..")
#     --quiet        suppress per-file PASS lines (FAIL lines always shown)
#     -h|--help      print this header
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None (read-only; no network, no commit, no device mutation).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, lib/covenant_propagation_engine.sh, lib/pointer_carrier.sh,
#   covenant_propagation_anchors.tsv. Parses clean under bash -n.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §${anchor} (the anchor enforced), §11.4.227(A)/(B), §11.4.201(1)/(7)(a)/(7)(b),
#   §11.4.157, §11.4.35, §11.4.251, §11.4.28/§11.4.177, §1.1 (paired mutation:
#   ${base%.sh}_mutation_test.sh).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 PASS · 1 MISSING/DUPLICATED/DIVERGENT · 2 environment error / BLIND.
#
# Classification: universal (§11.4.17) — no project-specific data.

set -euo pipefail

GATE="${gate}"

_engine="\$(cd "\$(dirname "\${BASH_SOURCE[0]:-\$0}")" && pwd)/lib/covenant_propagation_engine.sh"
if [ ! -r "\$_engine" ]; then
    echo "\${GATE}: shared propagation engine not found at \$_engine" >&2
    exit 2
fi
# shellcheck source=lib/covenant_propagation_engine.sh
. "\$_engine"

covenant_propagation_main "\$GATE" "\$@"
WRAP
    chmod +x "$out"
}

emit_mut() { # $1=gate  $2=anchor  $3=outfile  $4=display-basename (real wrapper name)
    local gate="$1" anchor="$2" out="$3" base="${4:-$(basename "$3")}"
    cat > "$out" <<WRAP
#!/usr/bin/env bash
# ${base} — §1.1 paired-mutation meta-test for ${gate}
# (anchor §${anchor}).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves ${gate} is a GENUINE gate, not a bluff: it MUST
# FAIL on every planted defect class and MUST PASS on every clean / honestly
# exempt fixture (the §1.1 discriminator). Fixtures are built in a THROWAWAY
# mktemp corpus — the real repository is never mutated.
#   FAIL-expected : MISSING (mid-body citation only) · DUPLICATED (F7 class) ·
#                   DIVERGENT-HEAD · DIVERGENT-BODY · FENCE-MISSING
#   PASS-expected : POINTER-OK (genuine §11.4.35 pointer carrier) ·
#                   CLEAN (untouched corpus — the §11.4.201(1) false-positive
#                   guard) · ANCHOR-BOUNDARY (prefix-sharing decoy anchor)
#
# ── Thin-wrapper rationale (§11.4.251) ───────────────────────────────────────
# The harness is identical for every anchor, so it lives ONCE in
# \`lib/covenant_propagation_mutation_engine.sh\`; this file carries only its
# gate name. Generated by \`covenant_propagation_wrappers_generate.sh\`
# (§11.4.77) — edit the engine or the data pack, never this file by hand.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   ${base}
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Creates + removes a temp fixture dir under \$TMPDIR (trap-cleaned).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, lib/covenant_propagation_mutation_engine.sh, the sibling gate script.
#   Parses clean under bash -n.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §1.1, §${anchor}, §11.4.227(B), §11.4.201(1)/(7)(a), §11.4.157, §11.4.35,
#   §11.4.251, §11.4.107(10).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — §1.1 proof holds · 1 — a fixture was misclassified · 2 — env error.
#
# Classification: universal (§11.4.17).

set -uo pipefail

GATE="${gate}"

_mut_engine="\$(cd "\$(dirname "\${BASH_SOURCE[0]:-\$0}")" && pwd)/lib/covenant_propagation_mutation_engine.sh"
if [ ! -r "\$_mut_engine" ]; then
    echo "META: shared mutation engine not found at \$_mut_engine" >&2
    exit 2
fi
# shellcheck source=lib/covenant_propagation_mutation_engine.sh
. "\$_mut_engine"

covenant_propagation_mutation_main "\$GATE"
exit \$?
WRAP
    chmod +x "$out"
}

drift=0
written=0
scratch=""
if [ "$MODE" = "--check" ]; then
    scratch="$(mktemp -d)"
    trap 'rm -rf "$scratch"' EXIT
fi

while IFS=$'\t' read -r gate anchor; do
    [ -n "$gate" ] || continue
    slug="${anchor#11.4.}"
    gate_f="${HERE}/cm_covenant_114_${slug}_propagation.sh"
    mut_f="${HERE}/cm_covenant_114_${slug}_propagation_mutation_test.sh"
    if [ "$MODE" = "--check" ]; then
        emit_gate "$gate" "$anchor" "${scratch}/g.sh" "$(basename "$gate_f")"
        emit_mut  "$gate" "$anchor" "${scratch}/m.sh" "$(basename "$mut_f")"
        for pair in "${gate_f}:${scratch}/g.sh" "${mut_f}:${scratch}/m.sh"; do
            real="${pair%%:*}"; want="${pair##*:}"
            if [ ! -f "$real" ]; then
                echo "DRIFT: missing wrapper $real"; drift=$((drift+1))
            elif ! cmp -s "$real" "$want"; then
                echo "DRIFT: $real differs from generated form"; drift=$((drift+1))
            fi
        done
    else
        emit_gate "$gate" "$anchor" "$gate_f" "$(basename "$gate_f")"
        emit_mut  "$gate" "$anchor" "$mut_f" "$(basename "$mut_f")"
        written=$((written+2))
    fi
done <<< "$rows"

if [ "$MODE" = "--check" ]; then
    if [ "$drift" -gt 0 ]; then
        echo "covenant_propagation_wrappers_generate.sh --check: FAIL — ${drift} drifted/missing wrapper(s)"
        exit 1
    fi
    echo "covenant_propagation_wrappers_generate.sh --check: PASS — every wrapper matches the data pack"
    exit 0
fi
echo "covenant_propagation_wrappers_generate.sh: wrote ${written} wrapper file(s) from ${PACK}"
exit 0
