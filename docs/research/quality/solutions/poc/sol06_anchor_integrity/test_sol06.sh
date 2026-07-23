#!/usr/bin/env bash
# SOL-06 POC test — anchor-block integrity (the propagation-gate SHAPE fix).
# Written FIRST (§11.4.224). RED before anchor_integrity.sh exists.
#
# Contract (anchor_integrity.sh <file...>):
#   * BLOCK-START structure: a line beginning `**§11.4.N —` or `### §11.4.N` —
#     bare mid-text citations of an anchor literal are CARRIERS and never count
#     (§11.4.201(7)(a): match structure, not substring).
#   * Per file: any anchor with block-start count > 1 -> FAIL DUPLICATE-BLOCK.
#   * Across the lockstep set (all files passed): an anchor present in >=2 files
#     whose normalized block content differs -> FAIL DIVERGENT-MIRRORS.
#   * exit 0 clean | 1 findings (named) | 2 blind inputs.
#
# Cases:
#   A golden-good      : one block per anchor, two identical mirrors -> 0
#   B golden-bad-1     : anchor block appears TWICE, variants divergent, in one file
#                        -> FAIL naming the anchor (the F7/M13 shape a presence>=1
#                        gate stayed GREEN on)
#   C golden-bad-2     : same anchor, two mirrors, divergent content -> FAIL
#   D negative-control : an anchor CITED inside another anchor's body (carrier)
#                        does not count as a second block -> 0
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
[ -f "$HERE/anchor_integrity.sh" ] || { echo "FAIL: missing artifact anchor_integrity.sh"; echo "RESULT: RED"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

good_block_208='**§11.4.208 — Request-history ledger.** Full verbatim mandate text here.'
good_block_209='**§11.4.209 — Review model pin.** Fable at xhigh, Opus fallback.'

# ---- A golden-good --------------------------------------------------------
printf '%s\n\n%s\n' "$good_block_208" "$good_block_209" > "$T/m1.md"
printf '%s\n\n%s\n' "$good_block_208" "$good_block_209" > "$T/m2.md"
bash "$HERE/anchor_integrity.sh" "$T/m1.md" "$T/m2.md" > "$T/a.out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "A single blocks + identical mirrors -> clean" || bad "A expected 0 got $rc: $(cat "$T/a.out")"

# ---- B duplicated-divergent inside one file (the measured M13/F7 defect) ---
printf '%s\n\n%s\n\n**§11.4.208 — Request-history ledger.** A DIFFERENT compact variant.\n' \
  "$good_block_208" "$good_block_209" > "$T/dup.md"
bash "$HERE/anchor_integrity.sh" "$T/dup.md" > "$T/b.out" 2>&1; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'DUPLICATE-BLOCK.*11\.4\.208' "$T/b.out"; then
  ok "B duplicated anchor block -> FAIL naming §11.4.208 (presence>=1 gates stayed green on this)"
else
  bad "B expected 1 DUPLICATE-BLOCK 11.4.208 got $rc: $(cat "$T/b.out")"
fi

# ---- C cross-mirror divergence --------------------------------------------
printf '%s\n' "$good_block_208" > "$T/x1.md"
printf '**§11.4.208 — Request-history ledger.** Silently edited in one mirror only.\n' > "$T/x2.md"
bash "$HERE/anchor_integrity.sh" "$T/x1.md" "$T/x2.md" > "$T/c.out" 2>&1; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'DIVERGENT-MIRRORS.*11\.4\.208' "$T/c.out"; then
  ok "C divergent mirror copies -> FAIL naming the anchor"
else
  bad "C expected 1 DIVERGENT-MIRRORS got $rc: $(cat "$T/c.out")"
fi

# ---- D carrier negative-control -------------------------------------------
cat > "$T/carrier.md" <<'EOF'
**§11.4.209 — Review model pin.** Body text: this anchor composes with §11.4.208
and quotes the literal **§11.4.208** mid-sentence as a citation, which is a
carrier, not a block start.
EOF
bash "$HERE/anchor_integrity.sh" "$T/carrier.md" > "$T/d.out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "D mid-body citation of another anchor is a carrier, not a duplicate" \
  || bad "D carrier false-matched: rc=$rc $(cat "$T/d.out")"

# ---- E negative-control-2: dotted sub-anchor is a DISTINCT anchor ---------
# (found by the live run: §11.4.10.A prefix-matched as §11.4.10 -> false
#  duplicate — the §11.4.201(1) false-positive class, in this very tool)
cat > "$T/dotted.md" <<'EOF'
### §11.4.10 — Credentials-handling mandate
Body of ten.

### §11.4.10.A — Pre-store credential leak audit
Body of ten-A: a different anchor, not a duplicate of §11.4.10.
EOF
bash "$HERE/anchor_integrity.sh" "$T/dotted.md" > "$T/e.out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "E dotted sub-anchor (§11.4.10.A) is distinct from §11.4.10 — no false duplicate" \
  || bad "E dotted sub-anchor false-flagged: rc=$rc $(cat "$T/e.out")"

echo "----------------------------------------"
echo "RESULT: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
