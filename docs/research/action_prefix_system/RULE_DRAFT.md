# §11.4.140 — Draft anchor text + consumer mirror

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-06-09 |
| Last modified | 2026-06-09T00:00:00Z |
| Status | draft (for operator review before landing in Constitution.md) |
| Scope | full §11.4.140 anchor + shorter CLAUDE.md/AGENTS.md/QWEN.md/GEMINI.md consumer mirror |
| Inputs | `RESEARCH.md`, `DESIGN.md` (this directory) |

> NOTE: this is DRAFT text written to research/ per the task scope. It is NOT
> applied to `Constitution.md` / `CLAUDE.md` / `AGENTS.md` / `QWEN.md` in this
> run (no commit/push/edit of the live governance files). The operator lands it
> via the §11.4.26 constitution-update pipeline.

---

## A. FULL anchor — to add as a new `### §11.4.140 …` section in `Constitution.md`

### §11.4.140 — Universal action-prefix system (`ACTION_NAME ::`) (User mandate, 2026-06-09)

**Forensic anchor — verbatim user mandate (2026-06-09):**

> "When a user prompt STARTS with `ACTION_NAME ::` (e.g. `BACKGROUND :: IMPORTANT: do X...`) the agent MUST replace the `ACTION_NAME ::` prefix with that action's registered expansion text, then execute the rest. For `BACKGROUND ::` the expansion is: 'The following prompt that we will provide MUST BE executed in background in parallel with all main work streams using the subagents-driven development approach! All work done MUST PRODUCE rock solid evidence covered with hard physical proof(s) that all done is working as expected and as specified without any false results and without any bluff!'. The mechanism MUST be UNIVERSAL/extensible — more actions will be added later, each with its own expansion + rules. It MUST work with EVERY CLI agent, be fully decoupled + reusable by every project that includes the constitution submodule, and load + execute out of the box."

Every project under this Constitution MUST support a universal, extensible
**action-prefix system**: when a user prompt's FIRST non-blank line starts with
an uppercase action token followed by `" :: "` (grammar
`^([A-Z][A-Z0-9_]*) :: ` — anchored at line start, UPPERCASE-only token,
exactly one space on each side of `::`), the agent MUST (1) look the token up in
the shared **action registry** (tracked data file
`constitution/actions/registry.yaml`, or `$HELIX_ACTION_REGISTRY`); (2) if the
token is a registered action, REPLACE the `ACTION_NAME :: ` prefix with that
action's registered `expansion` text and apply its `rules`; (3) execute the
REMAINDER of the prompt under the expanded instruction. The system is the
C-preprocessor expand-then-rescan model applied to prompts (a line-anchored
single-token macro): detect → substitute the registered expansion → execute the
residual.

**Two-layer architecture (both mandatory; LAYER 1 is the universal floor).**
(LAYER 1 — universal, always-on, out-of-the-box) the action-prefix recognition
instruction MUST be mirrored into EVERY agent context carrier the constitution
maintains (`CLAUDE.md`, `AGENTS.md`, `QWEN.md`, `GEMINI.md` per §11.4.35) so the
agent itself recognises and applies the prefix on every CLI agent — Claude Code,
Gemini CLI, Qwen Code, OpenAI Codex CLI, GitHub Copilot CLI, Cursor, Aider,
Cline, Continue, Roo Code, and any future agent that reads one of those carriers.
(LAYER 2 — mechanical, where the agent exposes a pre-submit seam) a
prompt-preprocessing hook reading the SAME registry applies the expansion
deterministically (Claude Code `UserPromptSubmit` / `UserPromptExpansion` hook
injecting the expansion via `additionalContext`; per-agent slash-command
equivalents generated from the registry for Gemini/Qwen/Codex). LAYER 2 is the
§11.4.109 anti-forgetting upgrade applied to prompt prefixes — the expansion
holds even if model recall lapses; LAYER 1 guarantees the system works
everywhere with zero extra setup. Honest §11.4.3 boundary (§11.4.6): transparent
mechanical free-form `^PREFIX ::` interception is genuinely available ONLY on
Claude Code today; on every other agent the free-form form is honoured by
LAYER 1 (the agent self-applies) and the slash-command equivalent is the
mechanical convenience — this split is documented, never papered over.

**Grammar (mandatory, all hold).** (1) Anchored at the start of the first
non-blank line ONLY; mid-prose tokens never match. (2) UPPERCASE-only token
`[A-Z][A-Z0-9_]*`; lowercase never matches. (3) Separator is exactly `" :: "`
(space-colon-colon-space) — avoids C++ `Foo::Bar`, YAML `key: value`, URLs.
(4) Stacked prefixes (`A :: B :: rest`) apply outer-to-inner, left-to-right
(expand A, rescan, expand B, then the residual is the task). (5) A leading `\`
escapes the prefix (literal, no expansion) so action names can be discussed.
(6) An unknown token that matches the grammar shape but is NOT registered is
NEVER silently expanded or silently dropped — the agent asks which registered
action was meant (§11.4.66 + §11.4.105) or treats it literally; it NEVER invents
an expansion (§11.4.6). (7) Any prompt not satisfying the grammar is an ordinary
prompt; the system is a no-op.

**Registry is the single source of truth + the extension contract.** Adding a
new action = adding ONE `actions[]` row (`name`, `version`, `summary` ≥6 words
per §11.4.91, `expansion`, optional `rules` + `composes_with`) — no code change
in either layer (the registry is data, not code). Both layers read the same
file (§11.4.93-style single-source-of-truth). The first registry entry is
`BACKGROUND` with the operator's verbatim expansion above; it composes
§11.4.20/§11.4.70 (subagent-driven), §11.4.58/§11.4.103 (parallel streams),
§11.4.89 (background execution), and §11.4.5/§11.4.69/§11.4.107 (captured
physical evidence) + §11.4 (anti-bluff). Decoupled + reusable (§11.4.28): the
registry + hook + expander carry zero project-specific data and are consumed by
reference (the §11.4.80 `codegraph_*` pattern); a consuming project ships its own
registry or inherits the constitution default. Loads out-of-the-box via the
§11.4.75 install seam.

Classification: universal (§11.4.17). Composes §11.4 / §11.4.5 / §11.4.6 /
§11.4.17 / §11.4.20 / §11.4.28 / §11.4.35 / §11.4.58 / §11.4.66 / §11.4.69 /
§11.4.70 / §11.4.75 / §11.4.80 / §11.4.89 / §11.4.91 / §11.4.93 / §11.4.103 /
§11.4.105 / §11.4.107 / §11.4.109. Propagation gate
`CM-COVENANT-114-140-PROPAGATION` (literal `11.4.140` across the consumer fleet)
+ recommended gate `CM-ACTION-PREFIX-SYSTEM` (registry exists + parses + the
grammar regex matches/no-matches the canonical fixtures + the LAYER-1 mirror
block is present in CLAUDE.md/AGENTS.md/QWEN.md/GEMINI.md + the BACKGROUND
expansion text matches the registry verbatim + the Claude `UserPromptSubmit`
hook + expander script exist and are executable) + paired §1.1 meta-test
mutation (corrupt the BACKGROUND expansion in the registry OR strip the
`prefix_regex` OR remove the LAYER-1 mirror block from one carrier → the gate
FAILs; strip the literal `11.4.140` → the propagation gate FAILs; gate-code =
separate work item).

**Canonical authority:** constitution submodule
[`Constitution.md`](Constitution.md) §11.4.140. Non-compliance is a release
blocker. No escape hatch — no `--skip-action-prefix`, `--ignore-prefix`,
`--no-registry`, `--invent-expansion-OK`, `--single-layer-only` flag.

---

## B. SHORTER consumer mirror — to add to `CLAUDE.md` / `AGENTS.md` / `QWEN.md` / `GEMINI.md`

(One block, identical text in all four carriers — that identity IS the LAYER-1
universality. Verbatim BACKGROUND expansion is inlined so the most-used action
works out-of-the-box even without registry-file access.)

> **§11.4.140 — Universal action-prefix system (`ACTION_NAME ::`) (User mandate,
> 2026-06-09).** When a user prompt's FIRST non-blank line starts with an
> uppercase action token followed by `" :: "` (grammar
> `^([A-Z][A-Z0-9_]*) :: `), you MUST: (1) look the token up in the action
> registry `constitution/actions/registry.yaml` (or `$HELIX_ACTION_REGISTRY`);
> (2) if it is a registered action, REPLACE the `ACTION_NAME :: ` prefix with
> that action's `expansion` text and apply its `rules`; (3) execute the
> remainder of the prompt under the expanded instruction. Grammar: anchored at
> the first non-blank line only; UPPERCASE-only token; separator exactly
> `" :: "`; stacked prefixes (`A :: B :: rest`) apply outer-to-inner; a leading
> `\` escapes the prefix (literal, no expansion); an unknown grammar-shaped
> token is NEVER silently expanded or dropped — ask which registered action was
> meant (§11.4.66 / §11.4.105) or treat it literally, NEVER invent an expansion
> (§11.4.6). The registered action **`BACKGROUND`** expands to: *"The following
> prompt that we will provide MUST BE executed in background in parallel with
> all main work streams using the subagents-driven development approach! All
> work done MUST PRODUCE rock solid evidence covered with hard physical proof(s)
> that all done is working as expected and as specified without any false
> results and without any bluff!"* (composes §11.4.20 / §11.4.70 subagent-driven,
> §11.4.58 / §11.4.103 parallel streams, §11.4.89 background execution,
> §11.4.5 / §11.4.69 / §11.4.107 captured physical evidence, §11.4 anti-bluff).
> The system is UNIVERSAL (every CLI agent reads this block via its context
> carrier per §11.4.35), extensible (new action = new registry row), decoupled
> + reusable (§11.4.28), and loads out-of-the-box. Classification: universal
> (§11.4.17). **Canonical authority:** constitution submodule
> [`Constitution.md`](constitution/Constitution.md) §11.4.140. Non-compliance is
> a release blocker. No escape hatch — no `--skip-action-prefix`,
> `--ignore-prefix`, `--no-registry`, `--invent-expansion-OK`,
> `--single-layer-only` flag.

---

## C. Landing checklist (for the operator, via §11.4.26 pipeline)

1. `git fetch` + `git pull --ff-only` in the constitution submodule (§11.4.26 step 1 / §11.4.37).
2. Add §11.4.140 (Part A) to `Constitution.md`; add the mirror (Part B) to
   `CLAUDE.md`, `AGENTS.md`, `QWEN.md`, and a new `GEMINI.md` (the GEMINI.md
   carrier is added by this anchor so Gemini CLI gets the LAYER-1 floor).
3. Land `actions/registry.yaml` + `actions/SCHEMA.md` +
   `scripts/hooks/action-prefix-expand.sh` + `scripts/actions/expand_prefix.sh`
   + `scripts/actions/gen_agent_commands.sh` per DESIGN.md §2.
4. Wire `CM-COVENANT-114-140-PROPAGATION` + `CM-ACTION-PREFIX-SYSTEM` gates +
   the §1.1 paired mutations (TEST_PLAN.md).
5. Re-export `.html`/`.pdf`/`.docx` siblings per §11.4.65; bump revision header
   per §11.4.44; sync the consumer fleet per §11.4.35.
6. Commit + push to ALL upstreams per §11.4.26 step 4 / §2.1 (no force-push
   per §11.4.113).
