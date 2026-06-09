# Action-Prefix Recognition Instruction (§11.4.140) — LAYER-1 carrier block

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-06-09 |
| Last modified | 2026-06-09T00:00:00Z |
| Status | active |
| Scope | the reusable verbatim instruction block embedded into every agent context carrier |
| Authority | DESIGN.md §5 + RULE_DRAFT.md Part B (this directory) |

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
> 2026-06-09; GRAMMAR_ADDENDUM 2026-06-09).** When a user prompt's FIRST
> non-blank line starts with a recognised action prefix, you MUST: (1) look the
> action token up in the action registry
> `constitution/actions/registry.yaml` (or `$HELIX_ACTION_REGISTRY`);
> (2) if it is a registered action, REPLACE the prefix with that action's
> `expansion` text and apply its `rules`; (3) execute the remainder of the prompt
> under the expanded instruction. **Four EQUIVALENT forms** — same action, same
> expansion, same execution: (1) `ACTION_NAME :: <rest>` (bare `::`),
> (2) `PREFIX::ACTION_NAME :: <rest>` (namespaced `::`), (3) `/ACTION_NAME <rest>`
> (bare slash), (4) `/PREFIX::ACTION_NAME <rest>` (namespaced slash). Thus
> `BACKGROUND :: x` ≡ `DEFAULT::BACKGROUND :: x` ≡ `/BACKGROUND x` ≡
> `/DEFAULT::BACKGROUND x`. `PREFIX` is an action NAMESPACE; the reserved default
> namespace is **`DEFAULT`**, and an action runs WITH or WITHOUT the prefix.
> Grammar (all hold): anchored at the FIRST non-blank line only (mid-prose tokens
> never match); the action token AND the namespace are UPPERCASE-only
> `[A-Z][A-Z0-9_]*` (lowercase never matches); the namespace separator `::`
> inside the token carries NO surrounding spaces (`PREFIX::ACTION_NAME`), DISTINCT
> from the action-body separator `" :: "` (one ASCII space on each side of `::` —
> avoids C++ `Foo::Bar`, YAML `key: value`, URLs) in forms 1/2 and the slash-body
> separator (one space) in forms 3/4; stacked prefixes (`A :: B :: rest`) apply
> outer-to-inner, left-to-right (expand `A`, re-scan, expand `B`, then the
> residual is the task); a leading `\` escapes the prefix for BOTH the `::` and
> the slash form (`\BACKGROUND :: x`, `\/BACKGROUND x` — treat literally, strip
> the backslash, NO expansion) so action names can be discussed. **Conflict rule
> (slash form):** `/ACTION_NAME` (form 3) is honored as the action ONLY when
> `ACTION_NAME` (case-folded) does not collide with a built-in/host slash command
> (registry `slash_bare: auto` + `slash_conflicts: [..]`); form 4
> (`/PREFIX::ACTION_NAME`) is ALWAYS unambiguous and always honored. An unknown
> token that matches the grammar shape (any of the 4 forms) but is NOT registered
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
> anti-bluff). The system is UNIVERSAL (every CLI agent reads this block via its
> context carrier per §11.4.35), extensible (new action = new registry row),
> decoupled + reusable (§11.4.28), and loads out-of-the-box. Classification:
> universal (§11.4.17). **Canonical authority:** constitution submodule
> [`Constitution.md`](Constitution.md) §11.4.140. Non-compliance is a release
> blocker. No escape hatch — no `--skip-action-prefix`, `--ignore-prefix`,
> `--no-registry`, `--invent-expansion-OK`, `--single-layer-only` flag.
<!-- action-prefix-recognition:end -->
