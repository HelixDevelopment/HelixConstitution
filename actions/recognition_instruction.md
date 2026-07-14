# Action-Prefix Recognition Instruction (§11.4.140) — LAYER-1 carrier block

| Field | Value |
|---|---|
| Revision | 3 |
| Created | 2026-06-09 |
| Last modified | 2026-07-14T00:00:00Z |
| Status | active |
| Scope | the reusable verbatim instruction block embedded into every agent context carrier |
| Authority | DESIGN.md §5 + RULE_DRAFT.md Part B (this directory) |

> **Revision 3 (2026-07-14):** added the **sub-system shortcut** extension — a
> grammar-shaped token that names an incorporated sub-system / submodule (from
> the registry `subsystems:` catalogue OR recursive `.gitmodules` discovery)
> expands to a sub-system context injection. No new grammar; the same five forms.
>
> **Revision 2 (2026-07-02):** added the fifth grammar form — the arrow form
> `ACTION_NAME ---> <rest>` (and namespaced `PREFIX::ACTION_NAME ---> <rest>`) —
> as a first-class equivalent delimiter alongside `::` and `/`, plus the second
> registered action `REMINDER` (verify-don't-assume status re-surfacing).

This file holds the **single canonical LAYER-1 recognition-instruction block**.
The conductor (or the §11.4.35 propagation machinery) embeds the block between
the two markers below — VERBATIM, identical text — into every agent context
carrier the constitution maintains (`CLAUDE.md`, `AGENTS.md`, `QWEN.md`,
`GEMINI.md`). That textual identity across all four carriers IS the LAYER-1
universality: every CLI agent reads the same instruction via its own carrier and
applies the prefix expansion itself (per §11.4.35), so the system works on every
agent with zero extra setup.

The block is self-contained: even an agent with NO registry-file access still
has the most-used `BACKGROUND` expansion inline, while the registry
(`actions/registry.yaml`) remains the extensible source of truth for every other
action.

> NOTE: this is the canonical block text. It is NOT applied to the live
> governance files (`CLAUDE.md` / `AGENTS.md` / `QWEN.md` / `GEMINI.md`) by this
> machinery — those are conductor-owned (§11.4.58 contention paths). The operator
> lands it via the §11.4.26 constitution-update pipeline.

<!-- action-prefix-recognition:begin -->
> **§11.4.140 — Universal action-prefix system (`ACTION_NAME ::`) (User mandate,
> 2026-06-09; GRAMMAR_ADDENDUM 2026-06-09; arrow form 2026-07-02).** When a
> user prompt's FIRST
> non-blank line starts with a recognised action prefix, you MUST: (1) look the
> action token up in the action registry
> `constitution/actions/registry.yaml` (or `$HELIX_ACTION_REGISTRY`);
> (2) if it is a registered action, REPLACE the prefix with that action's
> `expansion` text and apply its `rules`; (3) execute the remainder of the prompt
> under the expanded instruction. **Five EQUIVALENT forms** — same action, same
> expansion, same execution: (1) `ACTION_NAME :: <rest>` (bare `::`),
> (2) `PREFIX::ACTION_NAME :: <rest>` (namespaced `::`), (3) `/ACTION_NAME <rest>`
> (bare slash), (4) `/PREFIX::ACTION_NAME <rest>` (namespaced slash),
> (5) `ACTION_NAME ---> <rest>` (bare arrow) ≡ `PREFIX::ACTION_NAME ---> <rest>`
> (namespaced arrow). Thus
> `BACKGROUND :: x` ≡ `DEFAULT::BACKGROUND :: x` ≡ `/BACKGROUND x` ≡
> `/DEFAULT::BACKGROUND x` ≡ `BACKGROUND ---> x` ≡ `DEFAULT::BACKGROUND ---> x`.
> `PREFIX` is an action NAMESPACE; the reserved default
> namespace is **`DEFAULT`**, and an action runs WITH or WITHOUT the prefix.
> Grammar (all hold): anchored at the FIRST non-blank line only (mid-prose tokens
> never match); the action token AND the namespace are UPPERCASE-only
> `[A-Z][A-Z0-9_]*` (lowercase never matches); the namespace separator `::`
> inside the token carries NO surrounding spaces (`PREFIX::ACTION_NAME`), DISTINCT
> from the action-body separator `" :: "` (one ASCII space on each side of `::` —
> avoids C++ `Foo::Bar`, YAML `key: value`, URLs) in forms 1/2, the arrow-body
> separator `" ---> "` (one ASCII space on each side) in form 5, and the
> slash-body separator (one space) in forms 3/4; stacked prefixes (`A :: B :: rest`) apply
> outer-to-inner, left-to-right (expand `A`, re-scan, expand `B`, then the
> residual is the task); a leading `\` escapes the prefix for the `::`, arrow,
> and slash forms (`\BACKGROUND :: x`, `\BACKGROUND ---> x`, `\/BACKGROUND x` —
> treat literally, strip the backslash, NO expansion) so action names can be
> discussed. **Conflict rule
> (slash form):** `/ACTION_NAME` (form 3) is honored as the action ONLY when
> `ACTION_NAME` (case-folded) does not collide with a built-in/host slash command
> (registry `slash_bare: auto` + `slash_conflicts: [..]`); form 4
> (`/PREFIX::ACTION_NAME`) is ALWAYS unambiguous and always honored. An unknown
> token that matches the grammar shape (any of the 5 forms) but is NOT registered
> is NEVER silently expanded or silently dropped — ask which registered action
> was meant (§11.4.66 / §11.4.105) or treat it as a literal prompt, NEVER invent
> an expansion (§11.4.6); any prompt not satisfying the grammar is an ordinary
> prompt and the system is a no-op. The registered action **`BACKGROUND`** expands
> to: *"The following prompt that we will provide MUST BE executed in background
> in parallel with all main work streams using the subagents-driven development
> approach! All work done MUST PRODUCE rock solid evidence covered with hard
> physical proof(s) that all done is working as expected and as specified without
> any false results and without any bluff!"* (composes §11.4.20 / §11.4.70
> subagent-driven, §11.4.58 / §11.4.103 parallel streams, §11.4.89 background
> execution, §11.4.5 / §11.4.69 / §11.4.107 captured physical evidence, §11.4
> anti-bluff). A second registered action **`REMINDER`** re-surfaces
> previously-scheduled, CRITICAL, status-UNCERTAIN work: FIRST verify the ACTUAL
> current status from captured evidence (never assume done or not-done —
> §11.4.6 no-guessing), THEN act on the delta — report the captured proof if
> genuinely complete, resume from the exact point if partial, action it NOW if
> not started, or surface the block per §11.4.66/§11.4.101 — always producing a
> status verdict (composes §11.4.6 / §11.4.87 / §11.4.94 / §11.4.97 / §11.4.103 /
> §11.4.108 / §11.4.130 / §11.4.147).
>
> **Sub-system shortcuts (§11.4.140 extension, 2026-07-14).** When the
> first-non-blank-line grammar-shaped token is NOT a registered action but
> NAMES an incorporated SUB-SYSTEM / submodule, it expands to a SUB-SYSTEM
> CONTEXT injection (repository + org + where-checked-out + §11.4.28 equal-
> codebase / decoupling / dependency-layout + §11.4.37 fetch-first + §11.4.113
> no-force-push + §11.4.183 full-constitution + §11.4/§11.4.69 anti-bluff) and
> the remainder of the prompt is the task to perform ON that sub-system —
> e.g. `HELIXQA :: run the atmosphere bank`, `PRESENTER ---> fix the pill`,
> `/CONTAINERS rebuild the pod`. Two data sources feed resolution: (a) the
> curated Helix-ecosystem catalogue in `subsystems:` of the registry (human
> abbreviations like `HXOTA` → HelixOTA), and (b) RECURSIVE `.gitmodules`
> discovery from the invoking project's own root, so EVERY submodule anywhere
> in the graph — and any newly-added one — auto-derives its UPPERCASE alias
> tokens (name / snake / camel-split / abbreviation) out-of-box with no
> hand-maintained list. A registered behavioral action ALWAYS wins a token
> collision; duplicate checkouts of the same submodule collapse to one
> sub-system; an ambiguous (multi-target) or lowercase token NEVER expands and
> falls to the clarify path (§11.4.6). Same five grammar forms, same
> first-non-blank-line anchor, same `\`-escape. The distinguishing result field
> is `kind` ∈ {`action`, `subsystem`}.
>
> The system is UNIVERSAL (every CLI agent reads this block via its
> context carrier per §11.4.35), extensible (new action = new registry row),
> decoupled + reusable (§11.4.28), and loads out-of-the-box. Classification:
> universal (§11.4.17). **Canonical authority:** constitution submodule
> [`Constitution.md`](Constitution.md) §11.4.140. Non-compliance is a release
> blocker. No escape hatch — no `--skip-action-prefix`, `--ignore-prefix`,
> `--no-registry`, `--invent-expansion-OK`, `--single-layer-only` flag.
<!-- action-prefix-recognition:end -->
