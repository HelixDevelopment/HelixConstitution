# Helix Constitution — Universal CLAUDE.md

> This is the **base CLAUDE.md** imported by every project that includes
> the Helix Constitution submodule. Project-level `CLAUDE.md` may
> extend or tighten any rule by adding an explicit
> `Override: <section>` block — but MUST NOT weaken them.
>
> Last revision: 2026-05-14

## How inheritance works

A consuming project's root `CLAUDE.md` MUST start with a clearly-marked
inheritance pointer:

```markdown
## INHERITED FROM constitution/CLAUDE.md

All rules in `constitution/CLAUDE.md` (and the `constitution/Constitution.md`
it references) apply unconditionally. The project-specific rules below
extend them.
```

Claude Code supports the `@path/to/file` import syntax natively, so a
consuming project can also write `@constitution/CLAUDE.md` at the top
of its own CLAUDE.md and Claude Code will resolve it recursively. For
agents that do not support `@imports`, the pointer-block pattern above
ensures the inheritance is at least readable.

## MANDATORY DEVELOPMENT PRINCIPLES

**NO BLUFF. Every change ships with positive-evidence validation on
the real target environment. A test that passes without exercising
the user-visible behaviour is a critical defect.**

(Constitution §7.1 + §11.4 — these references point to
`constitution/Constitution.md`.)

**CRITICAL: All code changes MUST follow these principles WITHOUT
EXCEPTION:**

1. **Solutions MUST NOT be error-prone.** Every fix must be robust,
   not introduce new failure modes. If a fix solves problem A but
   creates problem B, it is NOT acceptable. Test the fix against
   ALL existing functionality before committing.
2. **No blocking operations inside synchronized / shared-lock
   regions.** Long computations, network calls, or sleeps inside
   `synchronized` / `Lock`-held regions cause deadlocks or timeouts
   in other threads.
3. **Always consider concurrent callers.** Any method called from
   multiple threads must be safe for rapid consecutive calls.
4. **Test the fix, not just the symptom.** Verify the fix works AND
   doesn't break anything else.
5. **Anti-bluff is mandatory** (Constitution §7.1) — every runtime
   test MUST source the project anti-bluff helper, call at least
   one explicit user-visible action before any PASS, capture state
   delta, and assert positive evidence.
6. **Real captured evidence for audio/video** (Constitution §7.1 +
   §11.4.5) — features producing audio output validated via
   captured audio; features producing video output validated via
   captured frames + OCR or pixel-diff.

## MANDATORY ANTI-BLUFF COVENANT — END-USER QUALITY GUARANTEE

**Forensic anchor — verbatim user mandate (2026-04-28):**

> "We had been in position that all tests do execute with success and all Challenges as well, but in reality the most of the features does not work and can't be used! This MUST NOT be the case and execution of tests and Challenges MUST guarantee the quality, the completion and full usability by end users of the product!"

This is the historical origin of the project's anti-bluff covenant.
Every test, every Challenge, every gate, every mutation pair exists
to make the failure mode (PASS on broken-for-end-user feature)
mechanically impossible.

**Operative rule:** the bar for shipping is **not** "tests pass"
but **"users can use the feature."** Every PASS MUST carry
positive evidence captured during execution that the feature works
for the end user. Metadata-only PASS, configuration-only PASS,
"absence-of-error" PASS, and grep-based PASS without runtime
evidence are all critical defects regardless of how green the
summary line looks.

Tests AND Challenges (HelixQA, integration suites, smoke tests,
acceptance suites) are bound equally — a Challenge that scores
PASS on a non-functional feature is the same class of defect as a
unit test that does.

**Canonical authority:** `constitution/Constitution.md` §11.4 and
its sub-sections §11.4.1 through §11.4.16.

Non-compliance is a release blocker regardless of context.

### §11.4.1 — FAIL-bluffs are equally forbidden

A test that crashes for a script-internal reason (undefined variable
under `set -u`, regex error, malformed assertion, missing argument)
and produces a FAIL exit code is just as misleading as a PASS-bluff.
Both let real defects ship undetected. Every test MUST fail ONLY for
genuine product defects — script-bug failures must be fixed at the
source layer (helper library, shared lib, test source), not patched
in individual call sites.

### §11.4.2 — Recorded-evidence requirement

A test that emits PASS without captured visual or audio evidence of
the user-visible feature actually working on the screen the user
would see is a §11.4 PASS-bluff. Every PASS for a user-visible
feature MUST be cross-checked against captured recording + action
timeline.

### §11.4.3 — Per-environment-topology test dispatch

Tests that depend on environment topology MUST detect topology at
test entry and dispatch the topology-appropriate variant.
SKIP-with-reason is the correct fallback when the required topology
is absent; PASS-by-default is forbidden.

### §11.4.4 — Test-interrupt-on-discovery + retest-from-clean-baseline

The moment any defect is re-discovered, re-produced, or newly
identified during a test cycle, the cycle MUST stop. Then: systematic
debugging → fix at root cause → four-layer test coverage (pre-build /
post-build / runtime / meta-test paired mutation) → full rebuild →
re-deploy on every target → full retest from beginning.

### §11.4.5 — Captured-evidence quality analysis

Audio: presence (RMS amplitude), channel count, sample rate + bit
depth, glitch census, coexistence-artifact census. Video: presence
(non-zero frame count), routing target, frame health (drops /
jitter / freeze), obstruction census (OCR for hostile overlays),
resolution + codec. Every check is required for every PASS.

### §11.4.6 — No-guessing mandate

**Forensic anchor — verbatim user mandate (2026-05-08):**

> "'LIKELY' is guessing, we MUST NOT have guessing, since it can be
> or may not be! No bluffing and uncertainity is allowed at any cost!
> We MUST always know exactly precisly what is happening exactly, in
> any context, under any conditions, everywhere!"

Forbidden vocabulary in tests / gates / status reports / closure
narratives / commit messages when describing causes:
`likely`, `probably`, `maybe`, `might`, `possibly`, `presumably`,
`seems`, `appears to`, `guess`, `seemingly`, `apparently`,
`perhaps`, `supposedly`, `conjectured`, and synonyms.

Either prove the cause with captured forensic evidence and state it
as fact, OR explicitly mark `UNCONFIRMED:` / `UNKNOWN:` /
`PENDING_FORENSICS:` with a tracked-task ID for follow-up.

### §11.4.7 — Demotion-evidence rule

Demotion from a FAIL classification to a lower-severity
classification requires positive evidence captured under the SAME
CONDITIONS (same target, same build, same cycle position, same load
profile) that originally exposed the defect. "I cannot reproduce in
isolation" is a hypothesis, not a finding.

### §11.4.8 — Deep-web-research-before-implementation

Before designing a non-trivial fix, perform deep web research:
official docs, vendor technical guides, open-source codebases,
coding tutorials, issue trackers. Every non-trivial fix's commit
message (or accompanying entry) MUST cite at least one external
source OR the literal "NO external solution found — original work".

### §11.4.9 — Batch-source-fixes-before-rebuild

All source-side fixes that DO NOT require runtime validation to
design MUST be landed BEFORE the next artifact rebuild. The
anti-pattern of "fix A → rebuild → flash → cycle → fix B → rebuild
→ ..." serializes operator time onto rebuild latency.

### §11.4.10 — Credentials-handling mandate

**Forensic anchor — verbatim user mandate (2026-05-12):**

> "Credentials or any secret and sensitive data MUST NOT leak!"

Credentials MUST NEVER be tracked in git. `.env` / `.env.*` / `*.env`
patterns + `scripts/testing/secrets/*` (with `.example` + README.md
exception) git-ignored project-wide. Test scripts MUST NEVER print
or log credentials. Per-service file separation limits blast radius.
`chmod 600` on credential files, `chmod 700` on parent directory.
Rotation on suspected leak.

### §11.4.11 — File-layout discipline

Project files organised by purpose, not historical accident. Source
under canonical project roots. Tests under canonical test
directories. Logs and forensic artifacts under operator-controlled
directories — never scattered at repo root, never tracked unless
they are reference assets.

### §11.4.12 — Auto-generated docs sync

Every auto-generated document MUST be regenerated in the same
commit as any edit to its source. All output formats (.md + .html +
.pdf) MUST stay in sync at all times.

### §11.4.13 — Out-of-band sink-side captured-evidence

Whenever a downstream consumer (HDMI sink, cloud monitor, downstream
service) provides a network-accessible introspection API that
reports what was actually received, the test suite MUST consume that
report as captured-evidence. The on-source-side view alone is
insufficient.

### §11.4.14 — Test playback cleanup

Every test MUST leave the target in a quiescent state. Cleanup
mandatory on every exit path (`trap '<cleanup>' EXIT`). The
orchestrator MUST run a post-test sanity check and FAIL the
just-completed test if it left orphan state.

### §11.4.15 — Item-status tracking

Every active item in the project Issues file carries a
`**Status:**` line within five lines of its heading. Six-state
vocabulary: `Queued`, `In progress`, `Ready for testing`,
`In testing`, `Reopened`, `Fixed (→ Fixed.md)`. Status updated as
the item progresses. All three Issues / Issues_Summary / Fixed
file types kept in sync (Markdown + HTML + PDF).

### §11.4.16 — Item-type tracking

Every active item in the project Issues file carries a `**Type:**`
line within eight non-blank lines of its heading. Three-value
CLOSED vocabulary: `Bug` (product defect / regression / user-visible
broken behaviour), `Feature` (new capability not previously offered
to end users), `Task` (internal workstream — refactor, doc, infra,
gate, audit; the lowest-stakes default when ambiguous). The
Issues_Summary file carries the Type column for every active item.
All three Issues / Issues_Summary / Fixed file types kept in sync
(Markdown + HTML + PDF). Pre-build gates `CM-ITEM-TYPE-TRACKING` +
`CM-COVENANT-114-16-PROPAGATION` enforce the mandate.

### §11.4.17 — Universal-vs-project classification of new rules (User mandate, 2026-05-14)

Before adding ANY new rule, mandatory constraint, covenant clause,
gate, or "MUST"-bearing statement to a project's Constitution /
CLAUDE.md / AGENTS.md (or to a submodule's equivalents), the author
MUST classify it as **universal** (reusable across any project →
goes into this constitution submodule) or **project-specific**
(references particular hardware / vendor / package / region →
stays in the project / submodule layer). The commit message MUST
carry a `Classification:` line stating the choice + one-sentence
rationale. Universal rules that leak project-specific assumptions
(hardware part numbers, vendor names, geographic regions, internal
asset names) MUST be genericised first or downgraded to
project-specific. When uncertain, default to project-specific (the
narrower scope — lifting to universal later is cheap; the reverse
is expensive). Pre-build gate `CM-UNIVERSAL-VS-PROJECT-CLASSIFICATION`
audits new rule commits for the classification statement; paired
mutation strips it and asserts gate FAILs.

### §11.4.20 — Subagent-driven-by-default mandate (User mandate, 2026-05-14)

When the runtime supports subagent delegation (Claude Code Agent
tool, Cursor task-runners, Aider sub-sessions, etc.), the primary
agent MUST default to subagent delegation for any task that has
multi-step scope (≥3 phases), parallelisable independent subtasks,
long-running diagnostic loops, OR specialised domain workflows
(code review, security audit, doc propagation). Foreground-only is
reserved for single-file edits, mid-execution operator clarification,
critical-state sequencing (commits / pushes / tags), or tasks so
quick that subagent overhead exceeds the work. Sub-discipline:
**tight scope** (4-6 tasks, not "do everything"), **checkpoint
commits** after each major task, **anti-stall protection** explicit
in prompts, **anti-bluff verification** of subagent claims via repo
state. Parallel subagents MUST partition non-overlapping files;
`commit_all.sh --auto-cascade` bundles both via `git add -A`. Gate
`CM-SUBAGENT-DELEGATION-AUDIT` (when implemented in consuming
project) flags foreground multi-step work as a §11.4.20 violation.

### §11.4.18 — Script documentation mandate (User mandate, 2026-05-14)

Every Bash / shell / POSIX-sh script anywhere in a project
(`scripts/`, `bin/`, `tests/`, library directories, deployment
hooks, CI helpers — depth-N recursive) MUST carry: (1) an
in-source documentation block (Purpose / Usage / Inputs / Outputs
/ Side-effects / Dependencies / Cross-references) at the top of
the file; (2) an external user guide under
`docs/scripts/<script-name>.md` covering Overview / Prerequisites
/ Usage examples / Edge cases / Internal behaviour / Related
scripts / Last verified date. When a script is modified, BOTH
the in-source block AND the external user guide MUST be updated
in the SAME commit. **No documentation ever can be out of sync
with its codebase.** Pre-build gate `CM-SCRIPT-DOCS-SYNC` walks
every `*.sh` / `*.bash` under script directories, verifies a
companion `docs/scripts/<name>.md` exists, AND verifies doc was
modified in the same commit (or doc-mtime ≥ script-mtime as a
softer floor). Paired mutation strips the doc-sync invariant
and asserts gate FAILs.

### §11.4.19 — Fixed-document column-alignment mandate (User mandate, 2026-05-14)

Every project that maintains an open-work tracker AND a closed-archive
tracker MUST keep the two structurally aligned along the same lifecycle
axes (Status + Type). For the Fixed archive that means: (1) every
`### ` / `#### ` heading in `Fixed.md` (or equivalent) carries a
`**Status:**` line and a `**Type:**` line within 8 non-blank lines of
its heading; (2) a `Fixed_Summary.md` companion exists with the same
column structure as `Issues_Summary.md` (`# | Level | Status | Type |
One-line description`); (3) all three file formats (`.md` + `.html` +
`.pdf`) for BOTH `Fixed.md` and `Fixed_Summary.md` stay in sync via
the same single-shot wrapper that handles Issues + Issues_Summary;
(4) closure migration is atomic — when an Issues entry resolves it
moves to Fixed.md in the same commit, disappears from Issues_Summary
(open-only), and appears in Fixed_Summary (closed-only). Status
values for closed items are drawn from `{Fixed (→ Fixed.md) | Fixed —
pending device verification | Fixed — RECLASSIFIED}`. Type values
follow §11.4.16: `{Bug | Feature | Task}`. Pre-build gate
`CM-FIXED-COLUMN-ALIGNMENT` (5+ invariants) — Fixed_Summary.md
exists, table header carries Status+Type columns, mtime
(Fixed_Summary ≥ Fixed), generator script present, sync wrapper
invokes it, HTML+PDF exports for both Fixed and Fixed_Summary
present. Paired mutation strips Status column from Fixed_Summary
table header → gate FAILs. Classification: universal (per §11.4.17).
No escape hatch.

### §11.4.21 — Operator-blocked status + self-resolution exhaustion (User mandate, 2026-05-14)

`Operator-blocked` is the §11.4.15 Status closed-set's 7th value:
`{Queued | In progress | Ready for testing | In testing | Reopened |
Operator-blocked | Fixed (→ Fixed.md)}`. It is a **last-resort
classification**, earned only after the agent documents exhaustion
of every applicable self-resolution path: (a) CLI / ADB / SSH / API
access already available, (b) subagent delegation per §11.4.20,
(c) existing repo tooling (scripts / helpers / libraries),
(d) captured fallback (synthetic event, asset substitution, mock,
§11.4.3 topology SKIP), (e) external research per §11.4.8.
Every `Operator-blocked` item MUST carry an
`**Operator-Block-Details:**` line within 8 non-blank lines of its
heading stating: **WHAT** (concrete action), **WHY** (each
exhausted alternative enumerated), **UNBLOCK CONDITION**
(observable signal), **WHO** (handle / contact / doc pointer).
`Issues_Summary.md` lists `Operator-blocked` as a sortable Status
value. Items MUST be re-evaluated every Nth tag cycle (project-
defined, recommended ≥3rd cycle) — operator dependencies change.
Fake `Operator-blocked` (no exhaustion audit) is a §11.4 covenant
violation at the planning layer, severity-equivalent to a PASS-bluff.
Gates: `CM-ITEM-OPERATOR-BLOCKED-DETAILS` (every Operator-blocked
heading has the details line), `CM-OPERATOR-BLOCKED-SELF-RESOLUTION-
AUDIT` (NEW Operator-blocked commits contain "Attempted: a — ...;
b — ...; c — ..." trail). Classification: universal (per §11.4.17).
No escape hatch.

### §11.4.22 — Document-sync commit discipline (User mandate, 2026-05-14)

Every project tracking work items through an Issues / Fixed lifecycle
MUST provide a **lightweight commit path** distinct from the full-repo
commit wrapper. The lightweight path stages, commits, and pushes ONLY
the status-tracking doc set — Issues + Issues_Summary + Fixed +
Fixed_Summary + CONTINUATION + their HTML + PDF exports + any
auto-generated audit artifact — so doc-status never drifts behind
working-tree reality when the full-repo wrapper is unavailable
(in-flight rebase, large submodule churn, partial network). The
wrapper MUST: (a) auto-invoke the project's export-regeneration
pipeline first so Markdown + HTML + PDF stay in sync; (b) stage ONLY
the explicit doc-set list — NEVER `git add -A`; (c) use a separate
flock disjoint from the full-tree wrapper's lock; (d) push to every
parent-repo remote; (e) exit `3` on nothing-to-commit (informational,
not error). The wrapper MUST be invocable standalone OR as a
delegation flag on the full-tree wrapper (e.g. `commit_all.sh
--docs-only`) so operators have a single mental model. Inherits the
project's §9 preflight discipline (refuses to run mid-meta-test).
Gate `CM-COMMIT-DOCS-EXISTS` verifies wrapper + guide + flag +
doc-set enumeration. Paired mutation strips the doc-set array → gate
FAILs. Classification: universal (per §11.4.17). Composes with
§11.4.12 (export-sync), §11.4.15 (status tracking), §11.4.18 (script
documentation), §12.10 (CONTINUATION maintenance). No escape hatch —
doc-status drift is a §11.4 PASS-bluff at the documentation layer.

### §11.4.24 — Build-resource stats tracking mandate (User mandate, 2026-05-14)

Every project under this Constitution with a build exceeding 1 minute
wall-clock MUST run a host-side resource sampler for every build that
captures memory used, CPU%, load average, disk read/write at a fixed
interval (recommended 5 s) and computes per-metric **min / max / mean
/ p95** at stop. Per-build summaries appended to a TSV registry; the
registry is the single source of truth — the human-readable Markdown
report (and its HTML + PDF exports per §11.4.12) is derived. Top of
the report MUST surface **ever-values** (min / max / mean across all
tracked builds). Per-build entries sorted most-recent-first; each row
carries SUCCESS / FAIL / UNKNOWN + reason for FAIL. Sampler MUST itself
stay under 50 MB RSS and 5% CPU (Heisenberg-class observer constraint).
Stop hook MUST be called from both success AND failure paths of the
build wrapper. The Stats.{md,html,pdf} triple is committed via the
project's §11.4.22 lightweight doc-sync wrapper. Gate
`CM-BUILD-RESOURCE-STATS-TRACKER` + paired mutation hiding the monitor
aside → gate FAILs. Classification: mixed (per §11.4.17) — the discipline
universal, the implementation paths project-specific. Composes with
§11.4.12 / §11.4.18 / §11.4.22 / §12.6 / §12.7 / §12.9 (the host-safety
forensic anchors are the empirical motivation for this telemetry). No
escape hatch — build-resource debugging without time-series data is the
bluff this anchor forbids.

## MANDATORY HOST-SESSION SAFETY (Constitution §12)

Every script, test, helper, and AI agent MUST respect host-session
safety. Non-compliance is a release blocker.

### Forbidden — directly OR indirectly

1. Suspending the host (`systemctl suspend`, etc.).
2. Hibernating / hybrid-sleeping the host.
3. Logging out the user (`loginctl terminate-session`,
   `pkill -u <user>`, anything targeting `user@<uid>.service`).
4. Unbounded-memory operations inside `user@<uid>.service` cgroup —
   any command expected to exceed ~4 GiB RSS MUST be wrapped in a
   bounded execution scope.
5. Programmatic rfkill toggles, lid-switch handlers, power-button
   handlers — these cascade into idle-actions.
6. Disabling session managers "to make things faster".

### Required safeguards for heavy scripts

1. Source the project's host-safety helper library.
2. Call its pre-flight check and abort if it fails.
3. Wrap any subprocess expected to exceed ~4 GiB RSS in a bounded
   execution scope.
4. Cap parallelism to fit available RAM.

### §12.6 Memory-Budget Ceiling — 60% MAXIMUM

**Forensic anchor — verbatim user mandate:**

> "First make sure that whatever we do through our procedures
> related to this project MUST NOT use more than 60% of total system
> memory! All processes MUST be able to function normally!"

Project procedures MUST NOT use more than **60%** of total system
RAM. The remaining 40% is reserved for the operator's other
workloads. No escape hatch — bypassing this is the bluff §11.4
forbids.

### §12.10 Continuation document maintenance

`docs/CONTINUATION.md` MUST exist at the project root and reflect
the live state of the work. Every non-trivial state change updates
it in the same commit. Any agent must be able to resume work
exactly where the previous session left off by reading this single
file.

## MANDATORY ABSOLUTE DATA SAFETY — ZERO RISK (Constitution §9)

Every destructive repository operation (history rewrite, force-push,
branch deletion, bulk file removal, submodule de-init, object
pruning) MUST follow the full §9 safety protocol WITHOUT EXCEPTION:

1. **Backup first, always** — hardlinked mirror of `.git` to a
   sibling backup directory (`cp -al .git <backup>/repo.git.mirror`)
   is near-instant and uses zero additional disk.
2. **Record metadata** — refs, tags, submodule pointers, HEAD
   commit, HEAD tree hash, tree content sha256.
3. **Define expected post-op state**.
4. **Run the destructive operation** — never with `--no-verify`,
   never with `--force` that bypasses hooks, never auto-force on
   failure.
5. **Post-op gate** — HEAD tree identical, all tags preserved, all
   submodule pointers intact, per-entry archive integrity 100%,
   pre-build gates green. If any check fails → restore immediately.
6. **Force-push authorization** — force-push is NEVER automatic.
   Each force-push event requires explicit human authorization AND
   requires the post-op gate to have passed.
7. **Audit trail** — every history rewrite gets a `docs/changelogs/`
   "Force-push audit" section.

Hardlinked backup is so cheap (zero disk, <2 s) that there is NEVER
an excuse to skip it.

## MANDATORY COMMIT & PUSH CONSTRAINTS

1. **Use the project's official commit wrapper** for the main repo
   (e.g. `scripts/commit_all.sh`).
2. **NEVER use `git add`, `git commit`, or `git push` directly** on
   the main repo unless the project Constitution explicitly carves
   out a use case.
3. **Multi-upstream push is the norm** — every commit pushed to ALL
   configured upstream remotes. The constitution submodule ships an
   `install_upstreams.sh` (and an `Upstreams/` directory) that
   configures all remotes locally.
4. **NEVER skip hooks** (`--no-verify`, `--no-gpg-sign`) unless the
   user explicitly authorizes it for the session.

## MANDATORY TESTING CONSTRAINTS

Tests MUST be run at every stage WITHOUT EXCEPTION:

1. **Pre-build / pre-merge verification** — BEFORE every build.
2. **Post-build / packaging verification** — AFTER every build.
3. **Post-deploy verification** — AFTER every deploy / flash.

NEVER skip tests. NEVER mark a test as "broken — disable for now"
without fixing the underlying issue. NEVER ship a release with
unresolved WARNs.

## Code conventions

Universal conventions applicable to most projects:

- Use the project's preferred language for new code. Don't mix
  languages in one module without explicit Constitution permission.
- Static analyzers / linters / type-checkers MUST run clean (zero
  warnings) before commit.
- Style is set by the project's formatter; do not hand-edit style
  in PRs.
- Public APIs are documented at the source.

## When in doubt

- Read `constitution/Constitution.md` for the canonical text.
- Cross-reference the project's CLAUDE.md / AGENTS.md for project-
  specific extensions.
- If still unclear, ask the operator. Do NOT guess. Do NOT bluff.

---
