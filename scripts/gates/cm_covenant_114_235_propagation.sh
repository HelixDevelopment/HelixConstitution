#!/usr/bin/env bash
# cm_covenant_114_235_propagation.sh — CM-COVENANT-114-235-PROPAGATION gate
# (build-and-deploy the moment source fixes are proven-correct + test-side
# hardening is a parallel stage never a build gate + post-deploy version
# increment).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# §11.4.235 requires the anchor BLOCK (the anchor's own governance paragraph,
# not merely the bare literal `11.4.235` — §11.4.227(B)) to be present
# EXACTLY ONCE in every owned governance context-carrier file (CLAUDE.md /
# AGENTS.md / QWEN.md / GEMINI.md) across the consumer fleet, per §11.4.157
# five-carrier-lockstep + §11.4.35 inheritance, AND to be BYTE-IDENTICAL
# across every carrier that has it (no F7-class divergent-duplicate drift).
#
# Per §11.4.227(B) this gate counts BLOCK-STARTS, never a bare-literal grep:
#   * a "block-start" is a LINE-ANCHORED heading pattern (the line itself
#     begins with the anchor marker) — a mid-sentence/mid-body CITATION of
#     the anchor (e.g. "... per §11.4.235(A) ...") is a CARRIER and MUST NOT
#     count (§11.4.201(7)(a): match structure, not substring);
#   * 0 block-starts in a discovered carrier = MISSING -> FAIL;
#   * >1 block-starts in one carrier = DUPLICATION (the F7 class) -> FAIL;
#   * exactly 1 block-start per carrier is required, AND every carrier's
#     FULL block (heading line through the line before the next block-start
#     of ANY anchor, or EOF — NOT merely the heading line: these anchors are
#     genuinely multi-paragraph, forensic-motivation + lettered-clause +
#     Classification + Canonical-authority + no-escape-hatch) MUST be
#     byte-identical (sha256-equal) to every other carrier's — a
#     divergent-but-present duplicate is a FAIL the old bare-literal-presence
#     gates (e.g. cm_covenant_114_213) could not see.
#   * §11.4.35 POINTER-INHERITANCE carriers (files carrying a REAL,
#     non-fenced, line-anchored `## INHERITED FROM ...` heading) are
#     engine-rules-only mirrors that legitimately carry ZERO per-anchor
#     blocks — a zero-count on such a carrier is an honest
#     POINTER-INHERITANCE-SKIP, NEVER a MISSING/FAIL (a false-positive
#     refusal is itself a §11.4.201(1) FAIL-bluff). The pointer predicate
#     is FENCE-AWARE: the canonical constitution mirrors themselves quote
#     the `## INHERITED FROM ...` heading inside a fenced ```markdown code
#     block (the "How inheritance works" EXAMPLE, e.g. CLAUDE.md:91,
#     GEMINI.md:33) — that fenced text is a CARRIER, not a real pointer
#     heading (§11.4.201(7)(a)); a bare (non-fence-tracking) grep would
#     mis-classify those FULL mirrors as pointer consumers the moment they
#     lose their real anchor block, silently converting a real MISSING/FAIL
#     into an honest-looking SKIP — the false-negative the fence-tracking
#     predicate exists to prevent. A pointer carrier that DOES restate the
#     block is NOT skipped — it still participates in exactly-once +
#     lockstep so a restating consumer's own duplication/divergence is
#     still caught.
#
# Recognised block-start conventions (line-anchored, ^ = start of line):
#   ^**§11.4.<N>              (bold-paragraph form — the current convention
#                              for §11.4.185 and later anchors, incl. 235)
#   ^### §11.4.<N>            (H3-heading form — Constitution.md's own style)
#   ^- §11.4.<N>               (bullet compact-summary form — older anchors)
# In all three forms the anchor number is boundary-checked ([^0-9] or EOL)
# so a numeric prefix-match (e.g. "2351") can never be mistaken for "235".
#
# Control needle (§11.4.201(7)(b)): before trusting a zero-match "MISSING"
# verdict on any carrier, the extractor is self-tested against a synthetic
# line KNOWN to contain a genuine block-start for this exact anchor+regex
# class; if the needle itself fails to match, the instrument is BLIND and
# the run aborts (exit 2) rather than reporting a false absence.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_covenant_114_235_propagation.sh [--root <consumer-root>] [--quiet]
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
#   Per-carrier PASS/FAIL/SKIP lines on stdout + a final summary; nonzero
#   exit on any MISSING / DUPLICATED / DIVERGENT owned carrier. A
#   §11.4.35 pointer-inheritance carrier reports POINTER-INHERITANCE-SKIP
#   (informational, never a fail cause).
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None (read-only; no network, no commit, no device mutation).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, POSIX find + grep + sha256sum (or shasum -a 256 fallback). Parses
#   clean under bash -n.
#
# ── Cross-references ──────────────────────────────────────────────────────────
#   §11.4.235 (build-and-deploy-on-source-proven + post-deploy version
#   increment), §11.4.227(B) (anchor-block integrity: block-starts not bare
#   literals, exactly-once, lockstep hash), §11.4.201(7)(a)/(b)
#   (structure-not-substring + control needle), §11.4.157 (five-carrier
#   lockstep), §11.4.35 (inheritance), §11.4.28 (decoupling), §1.1 (paired
#   mutation — strip a block / duplicate a block / diverge a block across
#   carriers -> this gate FAILs). Note (§11.4.6 honest boundary): this gate
#   checks the four MIRROR carriers (CLAUDE/AGENTS/QWEN/GEMINI.md) —
#   Constitution.md itself is the anchor's own source-of-truth location and
#   is guaranteed to carry the block by construction, so it is intentionally
#   not re-scanned here (same convention as the legacy bare-literal gates,
#   e.g. cm_covenant_114_213_propagation.sh).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — every discovered owned carrier carries exactly ONE `11.4.235` block,
#       and every such block is byte-identical across all carriers that have it.
#   1 — at least one discovered owned carrier is MISSING the block, carries
#       it MORE THAN ONCE, or carries a block that DIVERGES from its peers.
#   2 — environment error (root not found, no carriers discovered, or the
#       control-needle self-test failed — the instrument is blind).
#
# Classification: universal (§11.4.17) — no project-specific data.

set -euo pipefail

ANCHOR="11.4.235"
GATE="CM-COVENANT-114-235-PROPAGATION"

root="${CONSUMER_ROOT:-..}"
quiet=""
while [ $# -gt 0 ]; do
    case "$1" in
        --root)  root="$2"; shift 2 ;;
        --quiet) quiet="1"; shift ;;
        -h|--help) sed -n '1,70p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "${GATE}: unknown arg '$1'" >&2; exit 2 ;;
    esac
done

[ -d "$root" ] || { echo "${GATE}: consumer root not found: $root" >&2; exit 2; }
root="$(cd "$root" && pwd)"

# Anchor number, ERE-escaped (dots literalised) for use inside the
# block-start regex; a trailing boundary of [^0-9] or end-of-line prevents a
# numeric prefix-match (e.g. never confuse "2351" with "235").
ANCHOR_RE="$(printf '%s' "$ANCHOR" | sed 's/\./\\./g')"
BLOCK_RE="^(\\*\\*|### |- )§${ANCHOR_RE}([^0-9]|\$)"

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 | awk '{print $1}'
    else
        echo "${GATE}: neither sha256sum nor shasum available" >&2
        exit 2
    fi
}

# §11.4.35 pointer-inheritance predicate — FENCE-AWARE. A bare
# `grep -qE '^## INHERITED FROM '` false-matches the "How inheritance works"
# EXAMPLE that the real constitution mirrors carry INSIDE a fenced ```markdown
# code block (constitution/CLAUDE.md:91, GEMINI.md:33) — that fenced text is a
# CARRIER quoting the heading (§11.4.201(7)(a)), never a real pointer heading.
# This predicate tracks fence state (```/~~~ toggles) and only recognises
# `## INHERITED FROM ` OUTSIDE any fence as a genuine pointer. Returns 0 (true)
# iff a real, non-fenced pointer heading exists.
is_pointer_carrier() {
    awk '
        BEGIN { fenced = 0; found = 0 }
        /^(```|~~~)/ { fenced = !fenced; next }
        !fenced && /^## INHERITED FROM / { found = 1; exit }
        END { exit !found }
    ' "$1"
}

# ── Control needle (§11.4.201(7)(b)) ─────────────────────────────────────────
needle_line="**§${ANCHOR} — control-needle synthetic block-start.**"
needle_hit="$(printf '%s\n' "$needle_line" | grep -cE "$BLOCK_RE" || true)"
if [ "${needle_hit:-0}" -lt 1 ]; then
    echo "${GATE}: BLIND — control needle failed to match the block-start regex for ${ANCHOR}; refusing to trust any zero-match result" >&2
    exit 2
fi
# Negative-control companion: a MID-BODY citation (not line-anchored) MUST
# NOT match — proves the regex discriminates structure from substring.
citation_line="This composes with §${ANCHOR}(A) as a mid-sentence citation, never a block-start."
citation_hit="$(printf '%s\n' "$citation_line" | grep -cE "$BLOCK_RE" || true)"
if [ "${citation_hit:-0}" -ge 1 ]; then
    echo "${GATE}: BLIND — the block-start regex for ${ANCHOR} false-matched a mid-body citation (carrier-vs-block-start discrimination broken)" >&2
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

# Generic (any-anchor-number) block-start regex — used ONLY to find the END
# boundary of THIS anchor's block (the next block-start line of ANY anchor
# marks where this anchor's own multi-paragraph block stops).
GENERIC_BLOCK_RE='^(\*\*|### |- )§11\.4\.[0-9]'

pass=0 fail=0 skip=0
declare -a hashes=()
declare -a hash_owners=()

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
        h="$(printf '%s' "$block_text" | sha256_of)"
        hashes+=("$h")
        hash_owners+=("$rel")
        pass=$((pass + 1))
        [ -n "$quiet" ] || echo "✅ PRESENT     ${rel}  — exactly one ${ANCHOR} block (lines ${start_line}-${end_line})"
    fi
done <<< "$carriers"

lockstep_fail=0
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
    exit 1
fi
echo "✅ ${GATE}: PASS — every owned carrier carries exactly one byte-identical §${ANCHOR} block"
exit 0
