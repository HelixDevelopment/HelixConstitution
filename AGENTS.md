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

### Fixed-document column-alignment (§11.4.19, User mandate 2026-05-14)

The closed-archive tracker (`Fixed.md`) MUST mirror the open-work
tracker (`Issues.md` + `Issues_Summary.md`) along the same lifecycle
axes — at minimum **Status** and **Type**. Concretely: (1) every
`### ` / `#### ` heading in `Fixed.md` carries `**Status:**` (from
closed-set `{Fixed (→ Fixed.md) | Fixed — pending device verification
| Fixed — RECLASSIFIED}`) and `**Type:**` (`{Bug | Feature | Task}`)
within 8 non-blank lines of the heading; (2) `Fixed_Summary.md`
companion exists with column structure `# | Level | Status | Type |
One-line description` matching `Issues_Summary.md` exactly;
(3) all three formats (`.md`, `.html`, `.pdf`) for BOTH Fixed and
Fixed_Summary stay in sync via the same single-shot wrapper that
handles Issues + Issues_Summary; (4) closure is atomic — resolved
items migrate from Issues.md to Fixed.md in the same commit.
Pre-build gate `CM-FIXED-COLUMN-ALIGNMENT` (5+ invariants:
file-exists, header-has-Status+Type, mtime ≥ Fixed.md, generator
script present, sync wrapper invokes it, HTML+PDF exports present).
Paired mutation strips Status column from Fixed_Summary header →
gate FAILs. Classification: universal (per §11.4.17).

### Operator-blocked status + self-resolution exhaustion (§11.4.21, User mandate 2026-05-14)

`Operator-blocked` is the §11.4.15 Status closed-set's 7th value
alongside `{Queued | In progress | Ready for testing | In testing |
Reopened | Fixed (→ Fixed.md)}`. **Last-resort classification** —
agent MUST first exhaust applicable self-resolution paths:
(a) CLI / ADB / SSH / API access already available, (b) subagent
delegation per §11.4.20, (c) existing repo tooling, (d) captured
fallback (synthetic event / asset substitution / §11.4.3 SKIP),
(e) external research per §11.4.8. Every `Operator-blocked` item
MUST carry `**Operator-Block-Details:**` within 8 non-blank lines
of its heading stating WHAT (action) / WHY (each exhausted
alternative) / UNBLOCK CONDITION (observable signal) / WHO (contact
or doc pointer). `Issues_Summary.md` lists it as a sortable Status
value. Items re-evaluated every Nth tag cycle (≥3rd recommended).
Fake `Operator-blocked` without exhaustion audit = §11.4 covenant
violation at planning layer (PASS-bluff equivalent). Gates
`CM-ITEM-OPERATOR-BLOCKED-DETAILS` + `CM-OPERATOR-BLOCKED-SELF-
RESOLUTION-AUDIT` (every NEW Operator-blocked commit carries an
"Attempted: a — ...; b — ...; c — ..." trail). Classification:
universal (per §11.4.17). No escape hatch.

### Document-sync commit discipline (§11.4.22, User mandate 2026-05-14)

Every project tracking work items through an Issues / Fixed lifecycle
MUST provide a **lightweight commit path** distinct from the full-repo
commit wrapper. Stages, commits, pushes ONLY the status-tracking doc
set: Issues + Issues_Summary + Fixed + Fixed_Summary + CONTINUATION +
their HTML + PDF exports + auto-generated audit artifact. Wrapper
MUST: (a) auto-invoke the project's export-regeneration pipeline
first so Markdown + HTML + PDF stay in sync; (b) stage ONLY the
explicit doc-set list — NEVER `git add -A`; (c) use a separate flock
disjoint from the full-tree wrapper; (d) push to every parent-repo
remote; (e) exit `3` on nothing-to-commit (informational). MUST be
invocable standalone OR via a delegation flag on the full-tree
wrapper (e.g. `commit_all.sh --docs-only`). Inherits §9 preflight.
Gate `CM-COMMIT-DOCS-EXISTS` + paired mutation. Composes with
§11.4.12 / §11.4.15 / §11.4.18 / §12.10. Classification: universal
(per §11.4.17). No escape hatch — doc-status drift is a §11.4
PASS-bluff at the documentation layer.

### Build-resource stats tracking (§11.4.24, User mandate 2026-05-14)

Every project under this Constitution with a build exceeding 1 minute
wall-clock MUST run a host-side resource sampler for every build —
samples /proc/meminfo + /proc/loadavg + /proc/stat + /proc/diskstats
at a fixed interval (recommended 5 s); writes TSV. On stop, computes
**min / max / mean / p95** per metric; appends one TSV row per build
to a registry; regenerates a Markdown report (Stats.md) whose top
surfaces **ever-values** (min / max / mean across all tracked builds)
and whose body lists per-build entries most-recent-first with SUCCESS /
FAIL / UNKNOWN + reason. Stats.md exported to Stats.html + Stats.pdf
through the project's normal export pipeline per §11.4.12. Triple
committed via the §11.4.22 lightweight doc-sync wrapper. Sampler MUST
stay under 50 MB RSS / 5% CPU. Stop hook called from both success AND
failure paths of the build wrapper. Gate `CM-BUILD-RESOURCE-STATS-TRACKER`
+ paired mutation. Classification: mixed (per §11.4.17). Composes with
§11.4.12 / §11.4.18 / §11.4.22 / §12.6 / §12.7 / §12.9. No escape hatch —
build-resource debugging without time-series data is the bluff this
anchor forbids.

### Full-Automation-Coverage (§11.4.25, User mandate 2026-05-15)

**Forensic anchor — verbatim user mandate (2026-05-15):**

> "Make sure that every feature, every functionality, every flow,
> every use case, every edge case, every service or application, on
> every platform we support is covered with full automation tests
> which will confirm anti-bluff policy and provide the proof of
> fully working capabilities, working implementation as expected,
> no issues, no bugs, fully documented, tests covered!"

No feature / functionality / flow / use case / edge case / service /
application on any supported platform may be considered deliverable
until automation tests prove six invariants: (1) anti-bluff posture
with captured runtime evidence (§7.1 + §11.4); (2) proof of working
capability end-to-end on target topology (§11.4.3, no mocks);
(3) implementation matches documented promise; (4) no open
issues/bugs surfaced (cross-checked vs §11.4.15 / §11.4.16);
(5) full documentation (user manual + §11.4.18 for scripts) kept in
sync via §11.4.12; (6) four-layer test floor per §1 (pre-build +
post-build + runtime + paired mutation). Consuming projects publish
a coverage ledger (feature × platform × invariant × status)
regenerated at release-gate sweep. Classification: universal
(§11.4.17). Severity-equivalent to a §11.4 PASS-bluff at the
release-gate layer. No escape hatch. See Constitution §11.4.25 for
the full mandate.

### Constitution-Submodule Update Workflow (§11.4.26, User mandate 2026-05-15)

**Forensic anchor — verbatim user mandate (2026-05-15):**

> "Every time we add something into our root (constitution Submodule)
> Constitution, CLAUDE.MD and AGENTS.MD we MUST FIRST fetch and pull
> all new changes / work from constitution Submodule first! All
> changes we apply MUST BE commited and pushed to all constitution
> Submodule upstreams! In case of conflict, IT MUST BE carefully
> resolved! Nothing can be broken, made faulty, corrupted or unusable!
> After merging full validation and verification MUST BE done!"

Before any modification to `constitution/{Constitution,CLAUDE,AGENTS}.md`,
execute in order: (1) fetch + pull (--ff-only or --rebase; never
strategy=ours / unrelated-histories without authorization) so the
submodule is at upstream tip before editing; (2) apply the change
with §11.4.17 classification + verbatim mandate quote; (3) validate
(meta_test_inheritance.sh + no merge-conflict markers + cross-file
consistency); (4) commit (governance files only, no `git add -A`)
+ push to EVERY configured upstream remote (§2.1 violation if not);
(5) careful conflict resolution preserving union of governance
content — force-push forbidden (§9.2); (6) post-merge validation:
`git submodule update --remote --init` + re-run cascade verifier
(CONST-047) confirming the new clause reaches every owned submodule;
(7) bump consuming project's `.gitmodules` pointer to new HEAD in
the SAME commit as cascade work — out-of-sync pointer = §11.4.26
violation. Classification: universal (§11.4.17). Severity-equivalent
to force-push without §9.2 authorization. No escape hatch. See
Constitution §11.4.26 for the full pipeline (operational scope,
cross-cutting reach).

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
