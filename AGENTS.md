# Helix Constitution — Universal AGENTS.md

> This is the **base AGENTS.md** for any CLI agent (Codex, Cursor,
> Aider, Continue, Gemini CLI, future LLMs) working on a project that
> includes the Helix Constitution submodule. Project-level `AGENTS.md`
> may extend or tighten rules but MUST NOT weaken them.
>
> Last revision: 2026-05-14

## How inheritance works

Because not every CLI agent honours the Markdown `@import` syntax,
each consuming project's root `AGENTS.md` MUST do one of:

1. **Reference + restate critical rules** (safest — works for every
   agent):

   ```markdown
   # <Project> — AGENTS.md

   > Base agent rules: `constitution/AGENTS.md` — READ IT FIRST.
   > The base file is authoritative for any topic not covered here.

   ## Critical base rules restated (for agents that don't follow links)
   - Never commit secrets.
   - All commits go through the project's commit wrapper.
   - Anti-bluff covenant binds every test (Constitution §11.4).

   ## Project-specific
   - ...
   ```

2. **Generate at build time** — keep one source-of-truth in this
   submodule, concatenate with a project-specific delta file. A
   `compose-agents.sh` script in this submodule's `Upstreams/` (or
   `scripts/` if added) would output `constitution/AGENTS.md`
   followed by `---` followed by `AGENTS.project.md`.

## Identity & posture

You are working inside a project that has opted into the Helix
Constitution. The Constitution is the source of truth for engineering
discipline (test coverage, anti-bluff covenant, data safety, host
safety, credentials handling, documentation discipline). Whenever
this AGENTS.md mentions a `§X.Y` reference, it points to
`constitution/Constitution.md`.

The Constitution applies recursively to every submodule of every
project that includes it — you MUST treat the Constitution's rules
as in-force regardless of how deep into the submodule tree you are
working.

## Top-level invariants for every agent

1. **Never assume; verify by reading files.** Especially before any
   destructive action.
2. **Never bluff.** Do not invent file paths, command outputs, test
   results, or library APIs you have not verified. If you are
   unsure, say so explicitly and verify.
3. **No guessing language** (§11.4.6). `likely`, `probably`, `maybe`,
   `might`, `appears`, `seems` are forbidden when reporting causes.
   Use captured evidence or mark explicitly `UNCONFIRMED:`.
4. **Test coverage for every change** (§1) — pre-build gate,
   post-build gate, runtime test, AND a meta-test mutation that
   proves the gate catches regressions.
5. **Commit through the project's official wrapper.** Direct
   `git add` / `git commit` / `git push` on the main repo is
   forbidden in normal workflow.
6. **Never skip hooks** (`--no-verify`, `--no-gpg-sign`).
7. **Never force-push.** Force-push requires explicit per-session
   human authorization AND a green §9.1.5 post-op gate.
8. **Hardlinked backup before any destructive op** (§9). Zero excuse.
9. **Host safety** (§12) — abort if pre-flight check fails; wrap
   heavy work in bounded execution scopes; never exceed 60% of host
   RAM.
10. **Credentials NEVER tracked** (§11.4.10) — `.env` patterns
    git-ignored; runtime-load only; per-service file separation.
11. **CONTINUATION.md kept in sync** (§12.10) — every non-trivial
    state change updates the continuation document in the same
    commit.

## Critical base rules restated (for agents that don't honour @imports)

### Anti-bluff covenant — END-USER QUALITY GUARANTEE (§11.4)

**Forensic anchor — verbatim user mandate (2026-04-28):**

> "We had been in position that all tests do execute with success and all Challenges as well, but in reality the most of the features does not work and can't be used! This MUST NOT be the case and execution of tests and Challenges MUST guarantee the quality, the completion and full usability by end users of the product!"

The bar for shipping is **not** "tests pass" but **"users can use
the feature."** Every PASS MUST carry positive evidence captured
during execution that the feature works for the end user.
Metadata-only PASS, configuration-only PASS, absence-of-error PASS,
and grep-based PASS without runtime evidence are critical defects.

### Mutation-paired gates (§1.1)

Every new gate MUST be paired with a mutation entry in the project's
meta-test harness that mutates the asserted condition and asserts
the gate now FAILs. A gate without a paired mutation is a bluff
gate and is forbidden.

### Recorded-evidence requirement (§11.4.2)

Every PASS for a user-visible feature MUST be cross-checked against
a captured recording + action timeline. A PASS that lacks at least
one matched timeline event in the analyzer findings is a §11.4
PASS-bluff.

### Test-interrupt-on-discovery (§11.4.4)

The moment any defect is re-discovered, re-produced, or newly
identified during a test cycle, the cycle MUST stop. Then:
systematic debugging → fix at root cause → four-layer test coverage
(pre-build / post-build / runtime / meta-test paired mutation) →
full rebuild → re-deploy on every target → full retest from
beginning.

### No-guessing mandate (§11.4.6)

**Forensic anchor — verbatim user mandate (2026-05-08):**

> "'LIKELY' is guessing, we MUST NOT have guessing, since it can be
> or may not be! No bluffing and uncertainity is allowed at any cost!
> We MUST always know exactly precisly what is happening exactly, in
> any context, under any conditions, everywhere!"

Forbidden vocabulary when reporting causes:
`likely`, `probably`, `maybe`, `might`, `possibly`, `presumably`,
`seems`, `appears to`, `guess`, `seemingly`, `apparently`,
`perhaps`, `supposedly`, `conjectured`, and synonyms.

### Item-type tracking (§11.4.16)

Every active item in the project Issues file MUST carry a
`**Type:**` line within eight non-blank lines of its heading.
Three-value CLOSED vocabulary: `Bug` (product defect / regression /
user-visible broken behaviour), `Feature` (new capability not
previously offered to end users), `Task` (internal workstream —
refactor, doc, infra, gate, audit; the lowest-stakes default when
ambiguous). The Issues_Summary file carries the Type column for
every active item. All three Issues / Issues_Summary / Fixed file
types kept in sync (Markdown + HTML + PDF). Pre-build gates
`CM-ITEM-TYPE-TRACKING` + `CM-COVENANT-114-16-PROPAGATION` enforce
the mandate. No escape hatch.

### Universal-vs-project classification (§11.4.17, User mandate 2026-05-14)

Before adding ANY new rule / mandatory constraint / covenant clause
/ gate / "MUST"-bearing statement, classify it: **universal** (any
project → constitution submodule) or **project-specific** (specific
hardware / vendor / package / region → project / submodule layer).
Commit message MUST carry `Classification:` line + one-sentence
rationale. When uncertain, default to project-specific. Gate
`CM-UNIVERSAL-VS-PROJECT-CLASSIFICATION` audits new rule commits.
Paired mutation enforces the gate is not a bluff.

### Subagent-driven-by-default (§11.4.20, User mandate 2026-05-14)

When the runtime supports subagent delegation (Agent tool / task
runner / sub-session), the primary agent MUST default to subagent
delegation for multi-step scope (≥3 phases), parallelisable
independent subtasks, long-running diagnostic loops, OR specialised
domain workflows. Foreground-only is reserved for single-file edits,
mid-execution operator clarification, critical-state sequencing
(commits / pushes / tags), or tasks under ~30s. Discipline: tight
scope (4-6 tasks), checkpoint commits per task, anti-stall protection
in prompts, anti-bluff verification of subagent claims via repo
state. Parallel subagents MUST partition non-overlapping files;
parent `commit_all.sh --auto-cascade` bundles via `git add -A`.
Gate `CM-SUBAGENT-DELEGATION-AUDIT` (per consuming project) flags
foreground multi-step work as a violation. Paired mutation enforces
the gate is not a bluff.

### Script documentation mandate (§11.4.18, User mandate 2026-05-14)

Every Bash / shell / POSIX-sh script under `scripts/` / `bin/` /
`tests/` / library dirs / CI hooks (depth-N recursive) MUST carry
(1) an in-source documentation block at the top (Purpose / Usage /
Inputs / Outputs / Side-effects / Dependencies / Cross-references)
AND (2) an external user guide under `docs/scripts/<script-name>.md`
(Overview / Prerequisites / Usage examples / Edge cases / Internal
behaviour / Related scripts / Last verified date). When a script is
modified, BOTH the in-source block AND the external user guide MUST
be updated in the SAME commit. **No documentation ever out of sync
with its codebase.** Gate `CM-SCRIPT-DOCS-SYNC` enforces. Paired
mutation strips the invariant.

### Credentials-handling (§11.4.10)

**Forensic anchor — verbatim user mandate (2026-05-12):**

> "Credentials or any secret and sensitive data MUST NOT leak!"

`.env` patterns git-ignored project-wide. Runtime-load-only — tests
load credentials at execution time from operator-populated files
under `scripts/testing/secrets/` (or per-project equivalent). Test
scripts MUST NEVER print or log credentials.

### Host-session safety (§12)

Project procedures MUST NOT use more than **60%** of total system
RAM. Heavy work wrapped in bounded execution scopes so the kernel
OOM-kills only the scope — `user@<uid>.service` stays alive.
Hibernating / suspending / logging out the user is FORBIDDEN
(directly OR indirectly).

### Continuation document (§12.10)

`docs/CONTINUATION.md` MUST exist at the project root and reflect
the live state of the work. Every non-trivial state change updates
it in the same commit. Any agent must be able to resume work
exactly where the previous session left off by reading this single
file.

### Data safety (§9)

Hardlinked backup before any destructive operation. Post-op gate
MUST pass. Force-push requires explicit per-session human
authorization. Every history rewrite gets a `docs/changelogs/`
audit entry.

## CLI workflow expectations

1. **Read before write.** Use file-reading tools to inspect the
   current state before editing. Edits in the dark are how bugs
   sneak in.
2. **Use the project's commit wrapper.** Direct `git add` / `git
   commit` is forbidden unless explicitly carved out.
3. **Commit messages cite forensic evidence** for any non-trivial
   fix (logs, captures, /sys readings, dropbox entries, strace).
   Speculative narratives are §11.4.6 violations.
4. **Update CONTINUATION.md** in the same commit as the work
   (§12.10).
5. **Run pre-build / post-build / runtime gates** before declaring a
   change complete. NEVER report "done" without running the
   relevant gate.
6. **Cite external research sources** for non-trivial fixes
   (§11.4.8). Either a citation OR the literal "NO external
   solution found — original work".
7. **Refuse to bluff.** If a step requires information you don't
   have, say so and STOP. Don't guess.

## Hierarchy of project authority

When a project files declares conflicting rules with this base
AGENTS.md, resolve in this order:

1. **Project's `docs/guides/<PROJECT>_CONSTITUTION.md`** — most
   specific, project-tailored.
2. **`constitution/Constitution.md`** (this submodule) — universal.
3. **Project's root `CLAUDE.md` / `AGENTS.md`** — agent-facing
   summaries; lossy compared to the Constitution.
4. **This `constitution/CLAUDE.md` / `AGENTS.md`** — universal
   agent-facing summary; lossy compared to the Constitution.

If a project's own files contradict the Constitution, that is
itself a Constitution violation and MUST be reported. Do NOT
silently follow the contradicting project file.

## When stuck

- Read `constitution/Constitution.md`.
- Cross-reference the project's CLAUDE.md / AGENTS.md.
- If still unclear, ask the operator. Do NOT guess. Do NOT bluff.

---
