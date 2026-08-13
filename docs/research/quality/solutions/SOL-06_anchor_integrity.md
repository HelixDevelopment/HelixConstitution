# SOL-06 — Anchor-Block Integrity Gate (the Propagation-Gate Shape Fix)

| Field | Value |
|---|---|
| Revision | 1 |
| Last modified | 2026-07-22T21:35:00Z |
| Rank | 7 |
| Closes | M13 (duplicated-divergent anchors green under presence≥1), MU-4 (contradicting canonical rules — the decidable subset) |
| Seam | build (governance-file gate) + governance-commit |
| POC | [`poc/sol06_anchor_integrity/`](poc/sol06_anchor_integrity/) — GREEN 5/5, RED-first, **plus a second RED→GREEN loop for a false positive the live run exposed** |
| Anchors mechanized (no new anchor) | the `CM-COVENANT-*-PROPAGATION` family's shape, §11.4.201(1)(7)(a), §11.4.157 lockstep |

## 1. The measured problem

- **Two anchor blocks duplicated verbatim-divergently** in the canonical agent-facing mirror —
  §11.4.208 and §11.4.209 each appeared TWICE (an earlier compact variant AND a fuller verbatim
  variant, the two divergent from each other) **in all four mirrors**, undetected because every
  propagation gate asserts literal-presence ≥ 1 [M13; constitution CLAUDE.md F7 remediation
  note]. A duplicated-divergent anchor *satisfies* a presence check — the §11.4.201 false-
  negative shape inside the governance layer itself.
- The corpus measures its own health in words-present, so it grows words (ROOT_CAUSE §5.3);
  presence-shaped gates mechanically reward restatement.
- MU-4: two canonical entry-point mandates contradict; nothing mechanical checks inter-anchor
  consistency at all [M19].

## 2. The mechanism

Fix the **gate shape**, not the instance: a propagation gate must count **block-starts** (a
structural pattern — `**§11.4.N —` / `### §11.4.N` at line start), never bare literals, and:

1. **count == 1 per anchor per file** — 0 is the old absence check, **>1 is the new duplication
   check** (FAIL naming the anchor);
2. **content-hash equality across the declared lockstep set** (the four mirrors per §11.4.157)
   — divergent copies FAIL naming both files;
3. mid-body citations of an anchor literal are **carriers** and never count (§11.4.201(7)(a));
4. zero blocks extracted from a governance file is `BLIND-OR-EMPTY` (exit 2), never clean.

## 3. POC results — including two live findings on the real corpus

RED → GREEN 5/5 (duplicate-divergent caught; cross-mirror divergence caught; carrier citation
not false-matched; dotted sub-anchor distinct).

**Live run 1** (`evidence/live_mirror_scan.txt`) produced a **false positive of this tool's
own**: `§11.4.10.A` prefix-matched as `§11.4.10` → false DUPLICATE-BLOCK in two files. Per
§11.4.201(1) that false refusal is a FAIL-bluff; per §11.4.224 a new failing test case (E,
dotted sub-anchor — `evidence/RED_case_E.txt`) was added FIRST, then the extractor fixed to
capture full dotted ids, then GREEN.

**Live run 2** (`evidence/live_mirror_scan_v2.txt`), post-fix, read-only over the real
governance files:

| File | Blocks | Findings |
|---|---|---|
| CLAUDE.md | 139 | 0 |
| AGENTS.md | 152 | 0 |
| QWEN.md | 146 | 0 |
| GEMINI.md | 77 | 0 |
| Constitution.md | 220 | **4 — §11.4.140 and §11.4.141 each head TWO different mandates** |

The four mirrors are clean (confirming the 2026-07-22 F7 reconciliation held), and the
instrument **independently re-detects the known, operator-owned anchor-number collision** in
Constitution.md (§11.4.140 action-prefix vs HelixTranslate; §11.4.141 token-efficiency vs
translation review — the incidental finding of the remediation round, now mechanically visible
instead of narratively known). No fix is attempted here — resolution requires re-minting one
mandate of each pair at a free number, a fleet-wide citation change the operator owns
(§11.4.66/§11.4.122).

## 4. The failure this makes IMPOSSIBLE

On a wired consumer, a governance edit that duplicates an anchor block, lets two mirror copies
drift, or re-mints an existing number cannot pass the build — the M13 state (duplicated-
divergent in four mirrors, all gates green) becomes unrepresentable.

## 5. What it still does NOT catch (honest boundary)

1. **Semantic contradiction between two *different* anchors** (the MU-4 entry-point conflict)
   is undecidable by block hashing; SOL-10's fence/seam checks catch the decidable sub-classes
   (scope-fenced verdicts, seam declarations), the rest remains review territory — stated, not
   claimed.
2. **The lockstep set is declared data**; omitting a mirror from the invocation exempts it
   silently. Integration wires the file list from one manifest (§11.4.35), and SOL-05's ledger
   pattern (required-set declared independently) applies to the mirror list itself.
3. Compact-vs-full variant relationships (mirror carries a summary, Constitution the full text)
   are legitimately divergent ACROSS layers — the equality check applies only within the
   declared lockstep set, so canonical-vs-mirror drift is NOT caught by this tool (that is the
   §11.4.186 cross-doc family's job).
