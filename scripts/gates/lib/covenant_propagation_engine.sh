#!/usr/bin/env bash
# covenant_propagation_engine.sh — SHARED §11.4.227(B) anchor-block-integrity
# ENGINE for the CM-COVENANT-114-<N>-PROPAGATION gate family.
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Every CM-COVENANT-114-<N>-PROPAGATION gate performs the IDENTICAL check and
# differs ONLY in two role values: the gate NAME and the anchor NUMBER.
# Maintaining one 400-line script per gate would be exactly the near-identical
# fork §11.4.251 forbids ("copies drift as one is patched and the other is
# not, until the drift is a defect surface no one owns"). Per §11.4.251 the
# code lives ONCE here; the role values live in the DATA PACK
# `scripts/gates/covenant_propagation_anchors.tsv`; each
# `cm_covenant_114_<N>_propagation.sh` is a THIN wrapper carrying only its own
# gate name (the §11.4.227(A) ledger's structural
# `grep --include='*.sh'` instrument requires a real executable gate site that
# names the gate) and delegating here.
#
# The logic below is a faithful port of the proven
# `cm_covenant_114_230_propagation.sh` template — same block-start regex, same
# control needle + citation negative-control, same exactly-once semantics,
# same full-block sha256 lockstep, same §11.4.35 pointer-inheritance skip, same
# exit codes. It is NOT a re-derivation.
#
# ── The check (§11.4.227(B)) ─────────────────────────────────────────────────
# §11.4.NNN requires the anchor BLOCK (the anchor's own governance paragraph,
# not merely the bare literal `11.4.NNN` — §11.4.227(B)) to be present EXACTLY
# ONCE in every owned governance context-carrier file (CLAUDE.md / AGENTS.md /
# QWEN.md / GEMINI.md) across the consumer fleet, per §11.4.157 five-carrier
# lockstep + §11.4.35 inheritance, AND to be BYTE-IDENTICAL across every
# carrier that has it (no F7-class divergent-duplicate drift).
#
# Per §11.4.227(B) this engine counts BLOCK-STARTS, never a bare-literal grep:
#   * a "block-start" is a LINE-ANCHORED heading pattern (the line itself
#     begins with the anchor marker) — a mid-sentence/mid-body CITATION of the
#     anchor (e.g. "... per §11.4.NNN(A) ...") is a CARRIER and MUST NOT count
#     (§11.4.201(7)(a): match structure, not substring);
#   * 0 block-starts in a discovered carrier = MISSING -> FAIL;
#   * >1 block-starts in one carrier = DUPLICATION (the F7 class) -> FAIL;
#   * exactly 1 block-start per carrier is required, AND every carrier's FULL
#     block (heading line through the line before the next block-start of ANY
#     anchor, or EOF — NOT merely the heading line) MUST be byte-identical
#     (sha256-equal) to every other carrier's — a divergent-but-present
#     duplicate is a FAIL the old bare-literal-presence gates could not see.
#   * §11.4.35 POINTER-INHERITANCE carriers (files carrying a REAL, non-fenced,
#     line-anchored `## INHERITED FROM ...` heading) are engine-rules-only
#     mirrors that legitimately carry ZERO per-anchor blocks — a zero-count on
#     such a carrier is an honest POINTER-INHERITANCE-SKIP, NEVER a
#     MISSING/FAIL (a false-positive refusal is itself a §11.4.201(1)
#     FAIL-bluff). The pointer predicate is FENCE-AWARE and is inherited BY
#     REFERENCE from `lib/pointer_carrier.sh` (§11.4.28/§11.4.177). A pointer
#     carrier that DOES restate the block is NOT skipped — it still
#     participates in exactly-once + lockstep.
#
# Recognised block-start conventions (line-anchored, ^ = start of line):
#   ^**§11.4.<N>              (bold-paragraph form — current convention)
#   ^### §11.4.<N>            (H3-heading form — Constitution.md's own style)
#   ^- §11.4.<N>               (bullet compact-summary form — older anchors)
# In all three forms the anchor number is boundary-checked ([^0-9] or EOL) so a
# numeric prefix-match (e.g. "270" vs "27") can never be mistaken.
#
# Control needle (§11.4.201(7)(b)): before trusting a zero-match "MISSING"
# verdict on any carrier, the extractor is self-tested against a synthetic line
# KNOWN to contain a genuine block-start for this exact anchor+regex class; if
# the needle itself fails to match, the instrument is BLIND and the run aborts
# (exit 2) rather than reporting a false absence. A paired negative control (a
# mid-body citation) MUST NOT match, proving structure-vs-substring
# discrimination.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   . "<gates-dir>/lib/covenant_propagation_engine.sh"
#   covenant_propagation_main <GATE-NAME> [--root <consumer-root>] [--quiet]
#
# The engine resolves <GATE-NAME> -> anchor number via the data pack
# `covenant_propagation_anchors.tsv` sitting beside `lib/`. An unknown gate
# name is a hard error (exit 2) — the engine NEVER guesses an anchor number
# from the gate's spelling (§11.4.6 no-guessing: a mis-derived anchor would
# silently check the wrong rule).
#
# ── Inputs ───────────────────────────────────────────────────────────────────
#   CONSUMER_ROOT  env override for the fleet root (arg --root takes precedence).
#   COVENANT_PROPAGATION_ANCHORS  optional override of the data-pack path.
#   Carriers are discovered by name (CLAUDE.md / AGENTS.md / QWEN.md /
#   GEMINI.md) under the root, EXCLUDING vendored / third-party trees
#   (node_modules, .git, out, build, dist, prebuilts, external, vendor,
#   target). Project-agnostic per §11.4.28 — no consuming project's paths are
#   hardcoded.
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Per-carrier PASS/FAIL/SKIP lines on stdout + a final summary; nonzero
#   return on any MISSING / DUPLICATED / DIVERGENT owned carrier.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None (read-only; no network, no commit, no device mutation).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, POSIX find + grep + awk + sed + sha256sum (or shasum -a 256 fallback),
#   lib/pointer_carrier.sh. Parses clean under bash -n.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.227(A) (named-gate ledger — why the thin wrappers exist), §11.4.227(B)
#   (anchor-block integrity), §11.4.201(1)/(7)(a)/(7)(b) (false-positive refusal
#   is a FAIL-bluff / structure-not-substring / control needle), §11.4.157
#   (lockstep), §11.4.35 (inheritance), §11.4.251 (no byte-identical forks —
#   this file IS that anchor's own remedy applied to the gate family),
#   §11.4.28/§11.4.177 (inherited by reference, never copied), §1.1 (paired
#   mutation, see covenant_propagation_mutation_engine.sh).
#
# ── Exit codes (returned to the wrapper) ─────────────────────────────────────
#   0 — every discovered owned carrier carries exactly ONE block for the
#       anchor, and every such block is byte-identical across all carriers.
#   1 — at least one discovered owned carrier is MISSING the block, carries it
#       MORE THAN ONCE, or carries a block that DIVERGES from its peers.
#   2 — environment error (unknown gate name, data pack / root not found, no
#       carriers discovered, or the control-needle self-test failed — the
#       instrument is blind).
#
# Classification: universal (§11.4.17) — no project-specific data.

# Resolve this lib's own directory once, so both the sibling
# pointer_carrier.sh and the parent data pack are found regardless of caller cwd.
_cpe_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# shellcheck source=pointer_carrier.sh
if [ -r "${_cpe_lib_dir}/pointer_carrier.sh" ]; then
    . "${_cpe_lib_dir}/pointer_carrier.sh"
else
    echo "covenant_propagation_engine.sh: shared pointer-carrier lib not found at ${_cpe_lib_dir}/pointer_carrier.sh" >&2
    return 2 2>/dev/null || exit 2
fi

# covenant_propagation_anchor_for <gate-name> — prints the anchor number bound
# to <gate-name> in the data pack, or nothing (nonzero) when unbound.
covenant_propagation_anchor_for() {
    local gate="$1" pack
    pack="${COVENANT_PROPAGATION_ANCHORS:-${_cpe_lib_dir}/../covenant_propagation_anchors.tsv}"
    [ -r "$pack" ] || return 2
    awk -F'\t' -v g="$gate" '
        /^#/ { next }
        NF >= 2 && $1 == g { print $2; found = 1; exit }
        END { exit !found }
    ' "$pack"
}

_cpe_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 | awk '{print $1}'
    else
        echo "covenant_propagation_engine.sh: neither sha256sum nor shasum available" >&2
        return 2
    fi
}

covenant_propagation_main() {
    local GATE="${1:?covenant_propagation_main: <gate-name> required}"; shift
    local ANCHOR root quiet
    local pack="${COVENANT_PROPAGATION_ANCHORS:-${_cpe_lib_dir}/../covenant_propagation_anchors.tsv}"

    if [ ! -r "$pack" ]; then
        echo "${GATE}: anchor data pack not found/readable: $pack" >&2
        return 2
    fi
    ANCHOR="$(covenant_propagation_anchor_for "$GATE" || true)"
    if [ -z "${ANCHOR:-}" ]; then
        echo "${GATE}: gate name is not bound to an anchor in the data pack ($pack) — refusing to guess an anchor number from the gate's spelling (§11.4.6)" >&2
        return 2
    fi

    root="${CONSUMER_ROOT:-..}"
    quiet=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --root)  root="$2"; shift 2 ;;
            --quiet) quiet="1"; shift ;;
            -h|--help) sed -n '1,60p' "$0" | sed 's/^# \{0,1\}//'; return 0 ;;
            *) echo "${GATE}: unknown arg '$1'" >&2; return 2 ;;
        esac
    done

    [ -d "$root" ] || { echo "${GATE}: consumer root not found: $root" >&2; return 2; }
    root="$(cd "$root" && pwd)"

    # Anchor number, ERE-escaped (dots literalised); trailing boundary of
    # [^0-9] or end-of-line prevents a numeric prefix-match.
    local ANCHOR_RE BLOCK_RE
    ANCHOR_RE="$(printf '%s' "$ANCHOR" | sed 's/\./\\./g')"
    BLOCK_RE="^(\\*\\*|### |- )§${ANCHOR_RE}([^0-9]|\$)"

    # ── Control needle (§11.4.201(7)(b)) ─────────────────────────────────────
    local needle_line needle_hit citation_line citation_hit
    needle_line="**§${ANCHOR} — control-needle synthetic block-start.**"
    needle_hit="$(printf '%s\n' "$needle_line" | grep -cE "$BLOCK_RE" || true)"
    if [ "${needle_hit:-0}" -lt 1 ]; then
        echo "${GATE}: BLIND — control needle failed to match the block-start regex for ${ANCHOR}; refusing to trust any zero-match result" >&2
        return 2
    fi
    # Negative-control companion: a MID-BODY citation MUST NOT match.
    citation_line="This composes with §${ANCHOR}(A) as a mid-sentence citation, never a block-start."
    citation_hit="$(printf '%s\n' "$citation_line" | grep -cE "$BLOCK_RE" || true)"
    if [ "${citation_hit:-0}" -ge 1 ]; then
        echo "${GATE}: BLIND — the block-start regex for ${ANCHOR} false-matched a mid-body citation (carrier-vs-block-start discrimination broken)" >&2
        return 2
    fi

    # Discover owned governance carriers, excluding non-authored trees.
    local carriers
    carriers="$(find "$root" \
        \( -path '*/node_modules' -o -path '*/.git' -o -path '*/out' \
           -o -path '*/build' -o -path '*/dist' -o -path '*/prebuilts' \
           -o -path '*/external' -o -path '*/vendor' -o -path '*/target' \) -prune \
        -o \( -type f \( -name 'CLAUDE.md' -o -name 'AGENTS.md' \
           -o -name 'QWEN.md' -o -name 'GEMINI.md' \) -print \) 2>/dev/null | sort)"

    if [ -z "${carriers//[$' \t\r\n']/}" ]; then
        echo "${GATE}: no governance carriers (CLAUDE/AGENTS/QWEN/GEMINI.md) found under $root" >&2
        return 2
    fi

    # Generic (any-anchor-number) block-start regex — used ONLY to find the END
    # boundary of THIS anchor's block.
    local GENERIC_BLOCK_RE='^(\*\*|### |- )§11\.4\.[0-9]'

    local pass=0 fail=0 skip=0 f rel count start_line next_line end_line block_text h
    local -a hashes=()
    local -a hash_owners=()

    while IFS= read -r f; do
        [ -n "$f" ] || continue
        rel="${f#"$root"/}"
        count="$(grep -cE "$BLOCK_RE" "$f" || true)"
        count="${count:-0}"
        if [ "$count" -eq 0 ]; then
            if is_pointer_carrier "$f" 2>/dev/null; then
                skip=$((skip + 1))
                echo "⏭ POINTER-INHERITANCE-SKIP ${rel}  — §11.4.35 pointer consumer (engine-rules-only mirror; zero ${ANCHOR} blocks expected, not a violation)"
            else
                fail=$((fail + 1))
                echo "❌ MISSING     ${rel}  — zero ${ANCHOR} block-starts (bare-literal citations elsewhere do not count, §11.4.201(7)(a))"
            fi
        elif [ "$count" -gt 1 ]; then
            fail=$((fail + 1))
            echo "❌ DUPLICATED  ${rel}  — ${count} ${ANCHOR} block-starts (F7-class duplication, §11.4.227(B))"
        else
            start_line="$(grep -nE "$BLOCK_RE" "$f" | head -1 | cut -d: -f1)"
            next_line="$(awk -v s="$start_line" 'NR>s && /'"${GENERIC_BLOCK_RE}"'/{print NR; exit}' "$f")"
            if [ -n "$next_line" ]; then
                end_line=$((next_line - 1))
            else
                end_line="$(wc -l < "$f")"
            fi
            block_text="$(sed -n "${start_line},${end_line}p" "$f")"
            h="$(printf '%s' "$block_text" | _cpe_sha256)"
            hashes+=("$h")
            hash_owners+=("$rel")
            pass=$((pass + 1))
            [ -n "$quiet" ] || echo "✅ PRESENT     ${rel}  — exactly one ${ANCHOR} block (lines ${start_line}-${end_line})"
        fi
    done <<< "$carriers"

    local lockstep_fail=0 first_hash first_owner idx
    if [ "${#hashes[@]}" -gt 1 ]; then
        first_hash="${hashes[0]}"
        first_owner="${hash_owners[0]}"
        idx=0
        for h in "${hashes[@]}"; do
            if [ "$h" != "$first_hash" ]; then
                lockstep_fail=$((lockstep_fail + 1))
                echo "❌ DIVERGENT   ${hash_owners[$idx]}  — ${ANCHOR} block differs from ${first_owner} (§11.4.157 lockstep violation)"
            fi
            idx=$((idx + 1))
        done
    fi

    echo "----------------------------------------------------------------------"
    echo "${GATE}: ${pass} single-block-PRESENT, ${skip} POINTER-INHERITANCE-SKIP, ${fail} MISSING/DUPLICATED, ${lockstep_fail} DIVERGENT (anchor ${ANCHOR}) under ${root}"
    if [ "$fail" -gt 0 ] || [ "$lockstep_fail" -gt 0 ]; then
        echo "❌ ${GATE}: FAIL — anchor-block integrity violated for §${ANCHOR}"
        return 1
    fi
    echo "✅ ${GATE}: PASS — every owned carrier carries exactly one byte-identical §${ANCHOR} block"
    return 0
}
