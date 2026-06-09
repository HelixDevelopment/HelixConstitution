# Token-Efficiency Design — the composed §11.4.141 solution

**Revision:** 1
**Last modified:** 2026-06-09T08:30:00Z
**Status:** design
**Authority:** constitution submodule, universal (§11.4.17). Composes with §11.4.78/§11.4.79/§11.4.80 (CodeGraph), §11.4.20/§11.4.70 (subagent-driven), §11.4.58/§11.4.103 (parallel streams), §11.4.35 (consumer-thin / canonical-in-submodule), §11.4.50 (deterministic consistency), §11.4.125 (code-review), §11.4.6 (no-guessing — measured, not asserted), §11.4.106 (docs-chain), §12.6 (memory ceiling).

---

## 0. Design principle: cheaper-to-charge before smaller-to-send before do-less

Three independent dials, applied in order of safety:
1. **Charge less for the same bytes** — prompt caching (transparent, zero behaviour change). Do this first; it is most of the win and cannot break anything.
2. **Send fewer bytes for the same rules** — thin index + on-demand detail + retrieval over full-file (rules preserved by reference; gates preserved by literal-anchor). Do this second.
3. **Do less work per token** — model-tiering, terse/low-effort output, batching, compaction (restricted to mechanical paths so no decision is degraded). Do this third.

Each dial composes with the others and with every existing mechanism. None removes a rule, weakens an assertion, or changes a verdict.

---

## 1. The ranked, composable measure set

### M1 — Cache the static governance prefix (Lever A) — PRIMARY, do first
**What:** Ensure the always-loaded governance (consumer `CLAUDE.md`/`AGENTS.md`/`QWEN.md` + `constitution/*`) forms a **byte-stable prefix** with a single `cache_control: {type:"ephemeral"}` breakpoint at its end, and that **nothing volatile is rendered ahead of it**.
**How, per agent:**
- **Claude Code:** native — the harness already caches the system+instruction prefix. The project's responsibility is the *don't-invalidate* discipline: governance files stay byte-identical within a session; no per-turn timestamp/UUID/unsorted-JSON is injected ahead of the breakpoint. Use the 1-hour TTL posture for gap-heavy sessions (set by the harness; project keeps the prefix stable).
- **Cursor / Aider / any Anthropic-SDK driver:** put the governance in `system` as a single (or final) text block with `cache_control: {"type":"ephemeral"}`; reuse the exact prefix on every call. Verify `usage.cache_read_input_tokens > 0`.
- **Gemini CLI / Qwen Code:** use API-key auth so the built-in context cache engages; keep the system instruction stable.
**Decoupling/reuse:** This is a *property of the prompt assembly* (stable prefix + breakpoint), not project-specific code. Any consuming project inherits it by keeping its governance prefix stable. Zero ATMOSphere coupling.
**Safety argument:** Caching is **prefix-transparent** — the model receives byte-identical input cached or not, so behaviour is provably unchanged (Anthropic docs; `shared/prompt-caching.md`). Every §11.4.X rule is still present verbatim in the prefix; every propagation gate's literal-anchor scan still passes against the same bytes. The only failure mode is paying full price (silent invalidator) — detectable, never corrupting. **It cannot break any existing mechanism because it changes only billing.**

### M2 — Subagent model-tiering + output-to-file (Lever D) — SECONDARY, biggest non-cache win
**What:** Route **mechanical, non-judgment** subagent work to a Haiku-class model; subagents persist large output to a file under `qa-results/` / `recordings/` (already git-ignored per §11.4.128) and return a short pointer instead of a 350–520K-token inline transcript.
**Mechanical-only allowlist (safe to tier down):** code/log search, grep/glob, status probes, doc export/regen, file-presence checks, read-only device probes (§11.4.96 SAFE catalogue), markdown sync.
**Strong-model-only (NEVER tier down):** any PASS/FAIL verdict, fix design / root-cause (§11.4.102), code review (§11.4.125), demotion-evidence judgment (§11.4.7), anything producing captured-evidence interpretation.
**How, per agent:** Claude Code subagent `model: haiku` (alias) for the allowlist; `inherit`/`opus` for the rest. Gemini/Qwen hybrid (Gemini for cheap discovery, Qwen/strong for synthesis). Cursor/Aider per-request model.
**Decoupling/reuse:** The allowlist is expressed as *task class*, not project package names — universal. Output-to-file uses the project's own artifact dirs (configured, not hardcoded).
**Safety argument:** The strong model still owns **every decision and every verdict** — only legwork is cheap, so §11.4.50 (determinism) and the anti-bluff covenant are untouched (the cheap model never emits a PASS). Output-to-file is *more* faithful, not less — the full evidence is on disk (§11.4.5/§11.4.69), only the conductor's context shrinks. §12.6 memory ceiling and the §11.4.58/§11.4.103 stream caps are unchanged.

### M3 — Thin always-loaded INDEX + on-demand detail (Lever B) — restructure governance
**What:** Restructure the consumer governance so the **always-loaded** file is a concise index (one line per fix / per anchor: `[§11.4.N]` literal + 1-sentence summary + pointer to the canonical full text in `constitution/Constitution.md`), with the **full bodies fetched on demand**. This realises §11.4.35's existing split (consumer = thin extensions, submodule = canonical) at the byte level.
**How:** The consumer `CLAUDE.md` keeps its project-specific *operative* sections (build/flash/audio constraints that the agent needs every turn) but the **112-row Applied-Fixes table** and the **verbatim §11.4.X anchor restatements** become an index that points at `constitution/Constitution.md` (which already holds the canonical full text). The agent reads a specific fix paragraph / anchor body only when a task touches it.
**Decoupling/reuse:** Pure file-layout + retrieval discipline — universal. No API feature, no project coupling.
**Safety argument (the load-bearing one):** **Three invariants keep every gate green and every rule reachable.** (1) Each index line carries the **literal `11.4.N` anchor token**, so the `CM-COVENANT-114-N-PROPAGATION` gates (which scan for literal anchor strings) still pass. (2) The **canonical full text stays in `constitution/Constitution.md`**, a tracked, gate-scanned file — no rule is deleted, only de-duplicated out of the consumer. (3) The full body is reachable in **one hop** (`Read constitution/Constitution.md` at the anchor) so no rule becomes practically inaccessible. This is a *de-duplication*, not a *deletion*: today the rule text exists in BOTH the consumer and the submodule; M3 keeps the canonical copy and replaces the consumer's duplicate with a pointer. Net effect: identical rule coverage, ~80% smaller always-loaded payload. **Because M1 already makes the duplicate cheap, M3 is optional for the cost target on a warm cache — but it is the safety net for cold caches and the latency/window win, so it is recommended, sequenced after M1.**

### M4 — CodeGraph / retrieval over full-file loading (Lever C)
**What:** Structural questions → CodeGraph (§11.4.78, already installed) or lumen `semantic_search`; region questions → grep-scoped read; never re-read a harness-tracked file.
**How, per agent:** Claude Code (CodeGraph MCP + lumen MCP — the PreToolUse hook already nudges this); other agents use their structural/semantic search + grep. Genericised rule: "prefer a structural/index query to a whole-file load when only structure or a region is needed."
**Decoupling/reuse:** Uses already-mandated infrastructure; the rule is generic.
**Safety argument:** CodeGraph is read-only and constitution-trusted (§11.4.78). No behaviour change; strictly fewer tokens for the same answer.

### M5 — Output-token reduction: terse status + low-effort mechanical subagents (Lever E)
**What:** Conductor status is one line per milestone, no restatement of unchanged governance; mechanical subagents run at `effort: "low"`; structured/JSON output where a sink consumes it.
**Safety argument:** Terseness is presentation-only — captured-evidence artefacts (§11.4.5/§11.4.69) unchanged. `effort: "low"` restricted to the M2 mechanical allowlist, so no reasoning/verdict path is degraded. Output is 5× input price (Opus), so this is cost-leveraged.

### M6 — Tool-call batching + no-re-reads (Lever F)
**What:** Independent tool calls in one block; reuse harness-tracked file state; reuse persisted tool outputs.
**Safety argument:** Pure efficiency; the harness already supports parallel calls and tracks file state. Zero behaviour change.

### M7 — Compaction / context-editing for long sessions (Lever G) — defensive
**What:** Enable server-side compaction / context-editing so a 100+ turn cycle doesn't re-pay for an ever-growing transcript.
**Safety argument:** Summarizes/prunes stale tool-results and old thinking, not the governance prefix; the cached prefix and all evidence on disk are untouched. Prevents erosion of the M1–M6 gains over long cycles.

---

## 2. Sequencing (which measures get to 60–70%)

1. **M1 (cache governance)** — alone gets total cost to **~35–50% of baseline** (input dominated by the now-0.1× governance). This is most of the target and the safest single change.
2. **+ M2 (tier + output-to-file)** — subagent fleet is a large share under the parallel-stream methodology; tiering mechanical work + killing inline transcripts brings total to **~30–40% of baseline (60–70% reduction) — the target**, on a warm cache.
3. **+ M4/M5/M6** — push toward the low end of 30–40% and harden it on read-heavy and output-heavy turns.
4. **M3 (index)** — the structural safety net: turns the cold-start / cache-miss case from "full-price 170K" into "full-price ~30K," so the gains survive bursty sessions; also frees window + cuts first-turn latency.
5. **M7** — keeps it from eroding on very long cycles.

**Realistic combined number (honest, per §11.4.6):**
- **Warm-cache steady state: ~30–40% of baseline (60–70% reduction) — target met**, contingent on the three measured conditions in RESEARCH §5 (cache warm, no silent invalidator, mechanical subagents tiered).
- **Cold-cache / caching-unavailable floor: ~45–55% of baseline (45–55% reduction)** from M3+M2+M4+M5+M6 alone. **This is the number to quote when caching cannot be relied on — the target is not safely achievable without warm caching, and the rule requires the *measured* best, never an asserted headline.**

---

## 3. Universal / decoupled / reusable story

Every measure is expressed as a **discipline or an API-feature usage**, never as ATMOSphere code:
- M1/M5/M7 = Claude/LLM API features (cache_control, effort, compaction) — the consuming project supplies its own model IDs and prefix.
- M2/M4/M6 = task-class disciplines (tier mechanical work; prefer structural query; batch) — the project supplies its own mechanical-allowlist and structural-index tool.
- M3 = file-layout discipline (thin index + canonical-by-reference) — the project supplies its own governance files; the §11.4.35 split already exists to host it.

A different project inherits §11.4.141 by: keeping its governance prefix stable + breakpointed (M1), tiering its own mechanical subagents (M2), indexing its own large always-loaded docs (M3), preferring its own structural search (M4), and running its measurement harness (MEASUREMENT.md). No ATMOSphere-specific value is required.

---

## 4. The must-not-break / must-not-degrade safety summary (per measure)

| Measure | Could it remove a rule? | Could it weaken a gate? | Could it lower quality? | Could it change a verdict? |
|---|---|---|---|---|
| M1 cache | No (bytes identical) | No (literal anchors present, identical bytes) | No (transparent) | No |
| M2 tier+file | No | No | No (strong model owns all decisions; mechanical-only tier-down) | No (cheap model never emits PASS/FAIL) |
| M3 index | No (canonical text kept in submodule, reachable 1 hop, literal anchors in index) | No (literal-anchor scan passes; full text still gate-scanned) | No (rules still reachable) | No |
| M4 retrieval | No | No | No (CodeGraph trusted §11.4.78) | No |
| M5 terse/low-effort | No | No | No (evidence unchanged; effort:low mechanical-only) | No |
| M6 batch | No | No | No | No |
| M7 compaction | No (prunes stale tool-results, not governance/evidence) | No | No | No |

**No measure can break or degrade any existing mechanism, because:** caching is transparent; tiering and low-effort are confined to mechanical non-judgment work; indexing preserves the full rules by reference with literal anchors so the propagation gates pass; retrieval uses already-trusted read-only infrastructure; the anti-bluff covenant, deterministic-consistency, code-review, and memory-ceiling rules are all untouched.

---

## 5. Project-layer instantiation note (for the ATMOSphere consumer, per §11.4.35)

When this anchor lands, the ATMOSphere consumer instantiation would: (a) confirm the Claude Code governance-prefix cache is warm (`cache_read_input_tokens > 0`) and free of pre-breakpoint volatiles; (b) tier the §11.4.96-SAFE mechanical subagents (search/grep/status/doc-export) to Haiku and require subagent output-to-file under `qa-results/`; (c) replace the 112-row Applied-Fixes inline table + verbatim anchor restatements in the consumer `CLAUDE.md` with a literal-anchor index pointing at `constitution/Constitution.md`; (d) keep CodeGraph/lumen-first navigation; (e) run the §MEASUREMENT harness before/after to prove the measured reduction. That instantiation is a separate follow-up PWU — this document defines the universal contract only.
