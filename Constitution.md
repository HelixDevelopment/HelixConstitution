# Helix Universal Constitution

> **This document defines mandatory, non-negotiable rules for every project
> that includes this constitution submodule. Every AI agent and every
> human contributor MUST comply. Violations are blockers.**
>
> Project-specific constitutions extend this document. When a project
> Constitution (e.g. `docs/guides/PROJECT_CONSTITUTION.md`) and this
> universal Constitution differ, the project Constitution may extend or
> tighten — but NEVER weaken — the universal rules below.
>
> **Last revision**: 2026-05-14 (v1.0 — initial extraction from ATMOSphere Android 15 1.1.5-dev)

This Constitution is the universal source-of-truth for the engineering
practices shared across all Helix projects (and any project that opts in
by adding this submodule). It is intentionally agnostic about specific
hardware, operating systems, languages, vendors, and product domains.
Anything in this document that mentions a specific product, hardware
SKU, library version, or vendor MUST be moved to the consuming project's
own Constitution.

---

## 1. Test coverage is mandatory for every change

Every code, configuration, documentation, or infrastructure change MUST
ship with tests that prove:

| Invariant | Mechanism |
|---|---|
| The change is present in source | pre-build / pre-merge gate that scans the source tree for the expected pattern |
| The change survives compilation / packaging | post-build gate that inspects the produced artifact (binary, archive, image) and verifies the change actually shipped |
| The change behaves correctly at runtime | runtime / integration / on-device test that exercises the user-visible behaviour |
| The gate itself is not bluffing | meta-test (mutation) entry that mutates the asserted condition and proves the gate catches the break |

A change without all four layers of coverage is not ready to merge.

### 1.1 False-positive immunity is an invariant

A test that always returns PASS because its regex never matches, its
input path is wrong, its assertion target does not exist, or its
comparison is tautological is **worse than no test**. Every new gate
MUST be paired with a mutation entry in the project's meta-test harness
that:

1. Temporarily breaks the assertion (sed out a line, rename a symbol, etc.).
2. Re-runs the gate.
3. Asserts the gate now reports FAIL.
4. Restores the original.

If the mutation round does not turn PASS → FAIL, the gate is a sham and
must be rewritten.

This is the **single most important rule in this Constitution.** Every
subsequent §11.4.x clause is downstream of it.

---

## 2. Commit and push mechanics — single entrypoint, locked

All commit and push work uses the project's official multi-remote
commit wrapper (e.g. `scripts/commit_all.sh`) as the single
entrypoint. Direct `git commit` / `git push` / `git add` on the main
repo is prohibited in normal workflow. Exception: tag creation +
tag-ref push is done via explicit `git tag -a` and
`git push <remote> <tag>`.

The commit and push wrappers MUST hold an advisory `flock` so two
invocations cannot race against each other. Lock files self-clean on
process exit via `trap`.

When a contributor sees the "another commit/push wrapper is already
running" error, they MUST NOT `rm -f` the lock unless they have just
killed the owning process.

### 2.1 Multi-upstream push is the norm

Every project hosted on multiple Git providers (GitHub primary,
GitLab / GitFlic / GitVerse / Bitbucket / Gitea mirrors) MUST push every
commit to ALL configured upstream remotes. A commit that lives on only
one remote is a future operational risk: when that one provider has an
outage, the project is unreachable.

The constitution submodule itself ships an `install_upstreams.sh`
helper (and an `Upstreams/` directory with one declaration script per
remote). Running it from the submodule root configures all the remotes
locally. Consuming projects SHOULD do the same for their own multi-
remote topology.

---

## 3. Submodule changes propagate through submodule commits first

When a change lands in any submodule of the project:

1. **Commit inside the submodule first** (the submodule's own
   `git add` + `git commit`), since the parent project's commit
   wrapper does not commit submodule source — it only captures the
   updated submodule pointer.
2. **Push the submodule commit** to **all** remotes of that submodule.
3. **Then** run the parent project's commit wrapper to capture the
   updated submodule pointer in main and push main.

Skipping step 1 produces parent commits / tags that point at old
submodule HEADs without the actual source.

---

## 4. Every tag on the main repo MUST be mirrored on every owned submodule

When a version tag is created on the main repo at a specific commit,
the same tag MUST be created on **every owned submodule** at that
submodule's currently-pointed-to HEAD, and pushed to **every remote**
of every owned repo. Third-party submodules (libraries not under the
project's control) are excluded. The consuming project's Constitution
declares its owned-submodule set explicitly.

---

## 5. Changelog discipline and multi-format export

Every tagged release MUST ship:

1. A new `docs/changelogs/<tag>.md` entry describing user-visible
   changes, developer-visible changes, and known caveats.
2. Exports of that entry to `docs/changelogs/<tag>.{html,json,txt}`
   so external tooling (release portals, ticketing systems, package
   indices) can consume without needing a Markdown parser.
3. An update to a cumulative `docs/changelogs/CHANGELOG.md` (reverse
   chronological).

The project SHOULD provide a script (`scripts/testing/export_changelog.sh
<tag>` or equivalent) that wraps `pandoc` + `jq` + plain-text Markdown
strip.

---

## 6. Documentation up to the nano-details

Every new feature, fix, or infrastructure change MUST update:

1. The project's CLAUDE.md / AGENTS.md Applied Fixes table (one row,
   one commit, one release tag).
2. `docs/guides/` for any user-visible or developer-reachable
   behaviour change.
3. Architecture diagrams, flowcharts, and any reference docs that
   touch the changed subsystem.
4. The per-version changelog (§5).

Documentation drift after a fix is itself a Constitution violation:
undocumented behaviour change is the same defect class as un-tested
behaviour change.

---

## 7. Making false-success results literally impossible

All validation output MUST satisfy the following invariants:

1. Every gate reports concrete PASS / FAIL / SKIP with explicit
   reason text. A gate that just says "ok" is non-compliant.
2. Every SKIP reason MUST be mechanically distinguishable from a PASS.
   Summary counters track them separately.
3. FAILs are counted towards exit status. A script that hides FAILs
   in logs and returns 0 is a bug.
4. Meta-tests (§1.1) catch any gate that always PASSes regardless of
   condition.
5. Runtime results MUST be cross-referenced against host-side
   evidence (capture rig, screen recording, log analyzer, or
   equivalent) when the system's own introspection cannot directly
   verify the behaviour.

### §7.1 NO BLUFF — positive-evidence-only validation

Every runtime test MUST satisfy ALL FIVE of the following
non-negotiable constraints. A test that violates any one of them is a
**bluff** and is forbidden from being committed to the test suite:

1. **Real ACTION**: the test MUST invoke at least one user-visible
   action via a project anti-bluff helper (e.g. `ab_send_action()`
   in shell-based suites). A test that records a PASS without ever
   calling such a helper is automatically failed by the summary
   function.
2. **State DELTA**: every PASS that claims to verify a feature MUST
   capture state BEFORE the action and AFTER, and assert the delta
   matches expectation. `before == after` on success is a bluff.
3. **POSITIVE EVIDENCE**: the PASS condition MUST be POSITIVE
   evidence (a value match, a state delta, a captured frame analysis,
   a captured audio frame analysis), NEVER absence-of-error. If a
   probe returns nothing, that's a FAIL not a SKIP.
4. **UNIQUE EVIDENCE TOKEN**: tests that interact with mutable
   framework state MUST embed a per-run UUID into the action AND
   look for that token in the resulting state. Cached results
   predating the token cannot match — this defeats the stale-cache
   false-pass.
5. **Audio / video features REQUIRE captured evidence**: features
   that produce audio output MUST be validated by capturing the
   actual output via a capture pipeline (loopback, hardware capture
   rig, or equivalent) — NOT by metadata-only checks. Features that
   produce video output MUST be validated via frame capture + OCR
   or pixel-difference analysis.

Each consuming project SHOULD ship a shared anti-bluff helper library
(typically `tests/lib/anti_bluff.sh` or equivalent) that codifies
these rules; every new runtime test MUST source it and use its
assertion helpers.

---

## §8. Bleeding-edge ultra-perfection quality bar

The acceptance bar for shipping a project change is **not** "tests
pass and source compiles" — that is the floor. The acceptance bar is:

> **The user, on a freshly-deployed system, sees the expected effect
> when they perform the documented action — confirmed end-to-end, with
> captured evidence, on the actual target environment.**

The following are **forbidden**:

1. **"Source rebrand without shipped artifact rebuild"**: every
   source-side rename or rebranding MUST flow through to a shipped
   artifact that the runtime actually loads. Pre-build source-string
   gates are insufficient by themselves; shipped-artifact gates must
   accompany them.
2. **"Tests pass but feature broken"**: this is the failure mode §7.1
   exists to eradicate. Any test that PASSes despite the feature being
   non-functional is a critical defect; its mutation pair must FAIL on
   the breakage.
3. **"Configuration-only tests"**: a test that only verifies a config
   file exists / has expected contents is downgraded to a pre-build
   gate. Runtime tests MUST exercise the actual user-visible behaviour
   and capture the result.
4. **"It works on my workstation"**: every fix is validated on every
   supported target before any release. No exceptions.
5. **"Will fix in next cycle"**: deferrals are documented in the
   changelog with concrete blockers + implementation plans, not just
   handwaved.

---

## §9. Absolute codebase and data safety — zero risk, zero loss

Every destructive operation on the repository (history rewrite,
force-push, branch deletion, bulk file removal, submodule de-init,
pack repack that drops objects) is a **safety-critical** operation.
Data loss from a wrong force-push is irreversible once the remote
garbage-collects dangling objects. This section is non-negotiable.

### §9.1 Mandatory safety protocol for destructive operations

Every destructive operation MUST execute, in strict order:

1. **Full backup before touching anything.** Hardlinked mirror of
   `.git` to a sibling backup directory:
   ```
   cp -al .git <backup>/<repo>.git.mirror
   ```
   This is near-instant on the same filesystem and uses zero
   additional disk. If `.git` is small, also create
   `git bundle create <backup>/main.bundle --all`.
2. **Record critical metadata into the backup dir**:
   - `git show-ref > refs.txt`
   - `git tag > tags.txt`
   - `git submodule status > submodules.txt`
   - `git rev-parse HEAD > head.txt`
   - `git rev-parse HEAD^{tree} > head_tree.txt`
   - `git ls-tree -r HEAD --full-tree | sha256sum > head_tree_content.sha256`
   - `git ls-tree -r HEAD --full-tree > head_tree_listing.txt`
3. **Identify the target state**: the expected HEAD commit, tree
   hash, and tree content hash after the operation completes. The
   operation MUST preserve these unless it is explicitly changing
   HEAD content.
4. **Run the operation** (filter-repo, rebase, etc.). NEVER use
   `--no-verify` / bypass-hooks flags. NEVER auto-force on failure.
5. **Post-operation verification gate** (all MUST pass):
   - HEAD tree hash matches pre-op target (content identical for
     non-content-changing rewrites)
   - HEAD tree content sha256 matches pre-op sha256
   - All tags from `tags.txt` are preserved and resolve to valid
     commits
   - All submodule pointers from `submodules.txt` match current state
   - Project's pre-build / pre-merge gates pass with zero FAIL and
     zero unclassified WARN
6. **Only if every check in §9.1.5 passes** may the operation be
   considered successful. Otherwise: restore from backup
   immediately (`rm -rf .git && mv <backup>/<repo>.git.mirror .git`).
7. **Then and only then** may a force-push proceed — and still not
   without explicit user authorization per §9.2.

### §9.2 Force-push requires explicit user authorization every time

Force-pushing (including `push --force`, `push --force-with-lease`,
or any divergence-recovery code path inside an automated wrapper)
overwrites the remote's view of history. On any shared branch this
is irreversible.

Rules:
- Automated push wrappers MUST NOT auto-force-push as a fallback to
  any kind of failure (size rejection, divergence, server error,
  anything). The historical divergence-recovery code that silently
  force-resets the remote is forbidden and must be removed or gated
  behind an explicit flag.
- A human must affirmatively say "force-push" (or equivalent) in the
  session to authorize each force-push.
- Force-push to `main` (and any equivalent primary branch on owned
  submodules) is only authorized after the §9.1.5 gate has passed.
- Every force-push event is recorded in `docs/changelogs/<tag>.md`
  under a "Force-push audit" section (target refs, backup location,
  validation gate output).

### §9.3 Hardlinked backup is the standard — there is no excuse

Because hardlinked `.git` copies are near-instant and use zero
additional disk (same-filesystem inodes), the cost of making a backup
is trivial. Any destructive operation without a fresh hardlinked
backup is a Constitution violation regardless of how small the repo
is or how confident the operator.

### §9.4 Commit-message audit trail for history rewrites

After any `git filter-repo` run (or equivalent), commit a record
under `docs/changelogs/` (or `docs/history-rewrites/`) containing:
- What was stripped and why
- Pre-op `.git` size vs post-op `.git` size
- Pre-op HEAD commit vs post-op HEAD commit
- Pre-op HEAD tree hash vs post-op HEAD tree hash (MUST match for
  non-content-changing rewrites)
- Backup location

---

## §10. Enforcement

Any commit, tag, or release that violates §1–§9 is non-compliant.
The fix is to amend/revert and re-land with compliance. No
exceptions for speed pressure. Data-safety violations (§9) and
host-session-safety violations (§12) are treated as catastrophic
and block the entire release cycle until fully remediated.

---

## §11. End-user quality covenant

### §11.4 End-user quality guarantee — forensic anchor (User mandate, 2026-04-28)

The reason §7.1 + §8 exist — captured verbatim from the project
owner so that future engineers and AI agents understand the
historical failure mode the covenant exists to eradicate:

> "We had been in position that all tests do execute with success and all Challenges as well, but in reality the most of the features does not work and can't be used! This MUST NOT be the case and execution of tests and Challenges MUST guarantee the quality, the completion and full usability by end users of the product!"

This is the canonical motivation for every gate, every mutation
pair, every meta-test, every anti-bluff helper, every captured-
evidence requirement, every multi-environment validation rule.
The covenant exists because the project has historically shipped
broken features behind PASS-ing tests, and that outcome is no
longer tolerated.

**Operative rule:** the bar for shipping is not "tests pass" but
**"users can use the feature."** Every PASS in this codebase MUST
carry positive evidence captured during execution that the feature
works for the end user. Metadata-only PASS, configuration-only PASS,
"absence-of-error" PASS, and grep-based PASS without runtime
evidence are all critical defects regardless of how green the
summary line looks.

**Propagation requirement:** every `CLAUDE.md` and every `AGENTS.md`
in the project tree (parent + every submodule recursively) MUST
contain a clearly-titled "MANDATORY ANTI-BLUFF COVENANT — END-USER
QUALITY GUARANTEE" section that quotes this user mandate verbatim
and points back to this §11.4 as the canonical authority. The
consuming project enforces this via a pre-build gate (typically
`CM-COVENANT-PROPAGATION`).

### §11.4.1 — FAIL-bluffs are equally forbidden

The covenant must be enforced symmetrically. The historical failure
mode the covenant eradicates is the **PASS-bluff**: a green test
result on a feature that doesn't work for users. But the inverse
failure mode is just as toxic — the **FAIL-bluff**: a red test
result caused by a script bug (shell crash, missing argument, regex
error, malformed assertion) rather than by an actual product defect.

Examples of FAIL-bluffs:
- A test using `set -eu` calls `log_pass` without arguments → the
  helper references `$1` → script crashes with "1: parameter not
  set" → orchestrator records FAIL → engineer assumes product bug.
- A test pre-condition check uses an unbounded sed range → a
  comment line in the source matches the range terminator → the
  intended mutation never fires → audit reports PASS — bluff.

A FAIL produced by a test bug is no more useful than a PASS
produced by a test bug — both mislead investigation, waste cycles,
and ultimately let real defects ship undetected.

**Operative rule (extended):** every test MUST fail ONLY for
genuine product defects. A test that crashes for a script-internal
reason — undefined variable under `set -u`, unhandled error,
malformed pipe, regex syntax error, division by zero, etc. — is a
critical defect in the test suite itself and MUST be fixed at the
source layer (helper library, shared lib, test source) so the
failure mode disappears project-wide, not patched in individual
call sites.

### §11.4.2 — Recorded-evidence requirement

A test that emits PASS without **captured visual or audio evidence
of the user-visible feature actually working on the screen the user
would see** is a §11.4 PASS-bluff. Closing this gap requires a
project-wide recording + analyzer infrastructure consisting of (at
minimum):

* **Recording wrapper** that captures the user-visible output to
  time-synchronized media files. Multi-display systems record every
  output stream in parallel; sync metadata (host wall-clock at
  spawn) is written alongside the recording.
* **Action-timeline emitter**: every test emits structured timeline
  events (JSONL or equivalent) at every user-visible transition.
* **Frame / audio analyzer**: scans the recordings, extracts
  samples at a configurable interval, feeds them to recognizers
  (OCR for text overlays, speech-to-text for audio, pixel-diff for
  frame health), correlates against the timeline, and emits
  findings.

**Closure criterion:** every PASS for a user-visible feature MUST
be cross-checked by the analyzer against the recording + action
timeline. A PASS that lacks at least one matched timeline event in
the analyzer findings is treated as a §11.4 PASS-bluff.

### §11.4.3 — Per-environment-topology test dispatch

Tests that depend on environment topology (presence/absence of
secondary displays, microphones, network interfaces, peripheral
devices, cloud services, etc.) MUST detect topology at test entry
and dispatch the topology-appropriate variant. A test that runs the
WRONG variant for the actual topology and PASSes is a §11.4
PASS-bluff: it claims a feature works while never having exercised
it on the configuration the user actually has.

A topology-touching test that does NOT have a dispatcher AND a per-
topology variant is a §11.4 violation regardless of how it "passes"
on any specific configuration. Single-test-multi-topology scripts
MUST gate every topology-dependent assertion behind an explicit
topology check that emits SKIP-with-reason if the required topology
is absent — never PASS-by-default.

### §11.4.4 — Test-interrupt-on-discovery + retest-from-clean-baseline

A test cycle that *continues running past a freshly discovered
defect* is itself a §11.4 PASS-bluff: it produces "all green"
summaries that the operator might tag as a release while the
codebase under test is known-broken at the moment those greens
were recorded.

**The mandatory protocol — non-negotiable:**

1. **Interrupt immediately.** The moment a defect is re-discovered,
   re-produced, or newly identified during a test cycle, the cycle
   MUST stop. No "let it finish for the data" — the data is
   contaminated.
2. **Systematic debugging before any fix.** Identify root cause at
   source layer (not symptom), blast radius across related
   tests/features/subsystems, and regression-protection seam.
   Symptom patching is forbidden.
3. **Fix at root cause** per §11.4.1: source-layer fix, not symptom
   patch in the calling site. The fix MUST be safe (no new failure
   modes), minimal (no surrounding cleanup smuggled in), and
   non-regressive.
4. **Four-layer test coverage per fix.** Every fix lands with
   positive-evidence coverage in every applicable layer:
     - **Pre-build / pre-merge gate** (source-level catch)
     - **Post-build / packaging gate** (artifact-level catch)
     - **Runtime / on-device test** (end-user-behaviour catch)
     - **Meta-test paired mutation** (proves the gate is not itself
       a bluff)
5. **Documentation MUST be updated for every fix** — Issues → Fixed
   migration on closure, Applied Fixes table row, user-facing
   guides, architecture diagrams, per-version changelog.
6. **Rebuild the system.** Full build via the canonical build
   script. Skipping rebuild — even when the fix is host-only —
   invites stale-artifact contamination of the retest baseline.
7. **Re-deploy on every supported target.** A target left on the
   pre-fix build is a confounder.
8. **Repeat the full test suite** from the beginning on every
   target, sequentially per host memory cap. Partial reruns are a
   §11.4 violation.
9. **No-bluff certification per cycle.** Before tagging: meta-test
   harness returns all gates green AND every gate's paired mutation
   FAILs.

### §11.4.5 — Captured-evidence quality analysis

§11.4.2 mandates *captured* evidence; §11.4.5 mandates the **content**
of that evidence be analyzed for quality, not merely for presence.

**Audio quality analysis — every audio test that PASSes MUST verify:**
1. **Presence** — non-trivial RMS amplitude in captured output.
2. **Channel count** — analyzer reports the exact channel count the
   test claims (2.0 stereo, 5.1 surround, etc.). Stereo downmix in
   a "5.1 PASS" claim is a PASS-bluff.
3. **Sample rate + bit depth** — match the codec / pipeline under
   test.
4. **Glitch census** — underruns, XRUNs, dropouts above tolerance
   MUST be explicitly classified (PASS within budget, WARN above,
   FAIL on hard limits). Silently ignoring counts is a PASS-bluff.
5. **Coexistence-artifact census** — radio / IPC / shared-resource
   contention above tolerance.

**Video quality analysis — every video test that PASSes MUST verify:**
1. **Presence** — captured recording has non-zero size AND decoded-
   frame total > 0. A 0-byte file is the canonical PASS-bluff.
2. **Routing target** — analyzer confirms video appeared on the
   intended display / surface.
3. **Frame health** — drop count, jitter, freeze detection, tearing.
4. **Obstruction census** — OCR scan for hostile overlays (error
   dialogs, sign-in dialogs, geo-restriction overlays, paywall, etc).
5. **Resolution + codec** — captured dimensions match what the test
   claims.

### §11.4.6 — No-guessing mandate

Tests, gates, status reports, closure narratives, commit messages,
and any operator-facing text MUST NOT use words like `likely`,
`probably`, `maybe`, `might`, `possibly`, `presumably`, `seems`,
`appears to`, `guess`, `seemingly`, `apparently`, `perhaps`,
`supposedly`, `conjectured`, or their synonyms when describing
CAUSES of test failures, system behaviour, or fix effectiveness.

Either:

1. **Prove the cause** with captured forensic evidence (logs,
   kernel ring buffer, kernel ramoops, structured snapshots, OS
   journals, strace, etc.) and state it as fact, OR
2. **Explicitly mark UNCONFIRMED + PENDING_FORENSICS** with a
   tracked-task ID for follow-up.

Every "X likely caused Y" sentence in the codebase or documentation
is a §11.4.6 violation. Every "appears to be benign" without a
concrete forensic trace is a §11.4.6 violation.

### §11.4.7 — Demotion-evidence rule

A demotion from any FAIL classification (`OPEN`, `POSSIBLE PRODUCT
DEFECT`, `FAIL`) to a lower-severity classification (`INVESTIGATED`,
`MITIGATED`, `RESOLVED`, `WORKING-AS-INTENDED`) requires positive
evidence captured under the SAME CONDITIONS that originally exposed
the defect:

1. **Same target** — defect on Target-A needs Target-A evidence;
   cross-target claims need every target.
2. **Same build** — evidence captured BEFORE a relevant fix landed
   does not validate post-fix behaviour.
3. **Same cycle position** — a stress-soak FAIL is not refuted by
   an isolated-test PASS.
4. **Same load profile** — a contention-mode FAIL is not refuted by
   a quiescent-mode PASS.

"I cannot reproduce in isolation" is a HYPOTHESIS, not a finding.
Per §11.4.6 it MUST be tagged `UNCONFIRMED:` until same-conditions
retest produces positive evidence.

### §11.4.8 — Deep-web-research-before-implementation

Before designing a non-trivial fix, before implementing a new
feature, before declaring an architectural choice — perform deep
web research to verify the chosen approach is informed by current
state-of-the-art. The research surface includes:

1. **Official documentation** of the platform, framework, language,
   or service.
2. **Vendor technical guides** for the hardware / cloud / library.
3. **Open-source codebases** that already solved analogous problems.
4. **Coding tutorials + technical articles**.
5. **Issue trackers** for the relevant projects.

**Operative rule.** A fix that re-invents a wheel (or reproduces a
known-broken pattern) when the open-source community has already
solved the problem is a §11.4 violation by omission.

**Documentation requirement.** Every non-trivial fix's commit
message (or accompanying entry in the project's Issues /
Fixed file) MUST cite the research sources that informed it: at
least one external link OR the literal "NO external solution found —
original work".

### §11.4.9 — Batch-source-fixes-before-rebuild

When working through a multi-defect closure cycle, all source-side
fixes that DO NOT require runtime validation to design MUST be
landed BEFORE the next artifact rebuild. The anti-pattern this
mandate eliminates is `Fix A → rebuild → flash → cycle → fix B →
rebuild → ...` which serializes operator time onto rebuild latency.

Exceptions where a fix DOES require interim rebuild MUST be
documented in the fix's commit message as `REQUIRES_REBUILD:
<reason>`. The default is the batch path; rebuild-now is the
operator-authorized exception.

### §11.4.10 — Credentials-handling mandate

**Forensic anchor — direct user mandate:**

> "Credentials or any secret and sensitive data MUST NOT leak! This
> MUST BE added as the mandatory constraint into all Submodules and
> main project's Constitution, CLAUDE.MD and AGENTS.MD."

All credentials, secrets, API tokens, passwords, phone numbers,
OAuth refresh tokens, signing keys, encryption keys, and any other
authentication-or-authorization-bearing data used by test scripts,
build automation, or any project tooling MUST be handled per the
following rules without exception:

1. **No tracked-file storage.** Credentials NEVER live in any file
   that git tracks. Placeholder templates with `<replace ...>` or
   `EXAMPLE_VALUE_DO_NOT_USE` placeholders ARE allowed in `.example`
   files committed to show operators what keys to populate.
2. **Repository-wide ignore.** `.gitignore` MUST exclude all
   credential-bearing paths:
   - `.env`, `.env.*`, `*.env`, `.<service>.env`, `*.<service>.env`
   - `scripts/testing/secrets/*` with `.example` + `README.md`
     exception
3. **Runtime-load-only.** Tests load credentials AT EXECUTION TIME
   from operator-populated files under `scripts/testing/secrets/`
   (or per-project equivalent). If the file is missing, the test
   SKIPs with "credentials not configured for <service>" — it does
   NOT proceed without credentials and does NOT use defaults.
4. **No echo / no log.** Test scripts MUST NEVER print, log, or
   include credentials in error paths, stack traces, screen
   recordings, or output artifacts.
5. **Per-service file separation.** One file per service keeps
   blast radius small.
6. **Filesystem permissions.** `.env` files are `chmod 600`,
   parent directory is `chmod 700`.
7. **Rotation on suspected leak.** Rotate at provider, update local
   files, audit captured artifacts.

The consuming project's `.gitignore` MUST be verified before every
commit: `git ls-files --cached | grep -E "\\.env$"` MUST show no
real `.env` files (only `.env.example`).

### §11.4.10.A — Pre-store credential leak audit (User mandate, 2026-05-17)

**Forensic anchor — verbatim user mandate (2026-05-17):**

> "Us these for all future testing (full automation testing) and make
> sure they are not leaking anywhere or get git versioned!"
>
> [Discovered during execution: the operator-provided test credentials
> ALREADY existed in 5 tracked files dating to prior project cycles.
> §11.4.10 + §11.4.30 catch new commits but did not detect the
> pre-existing leak when the operator re-provided the same values
> for a new use.]

When an operator provides credentials, API tokens, signing keys, or
any other secret material to be stored in the project's gitignored
configuration (.env, scripts/testing/secrets/*, secrets/*, etc.),
the agent or human storing them MUST FIRST execute a repo-wide
audit for prior leaks of THOSE specific values BEFORE storing.

The audit MUST:

1. **Grep every tracked file** for the literal credential value(s).
   `git ls-files | xargs grep -l <value>` is the canonical form.
   Search MUST cover all file types — `.md`, `.json`, `.yaml`,
   `.kt`, `.go`, `.py`, `.sh`, `.sql`, build configs, docs.
2. **Grep the entire git history** for the literal credential
   value(s). `git log -S<value> --all --source --remotes` reveals
   historical commits even if the current tree is clean. A
   history-only leak is a §11.4.10 violation of equal severity to
   a tree-leak — anyone who pulled an older commit still has the
   value in their working copy of any branch they cloned.
3. **Report findings to the operator BEFORE storing the new value
   in any operator-controlled location.** The operator may then
   decide whether to (a) rotate the credential at the upstream
   provider before reusing, (b) accept the historical leak as a
   known-compromise and proceed, or (c) abort the storage. Storing
   the value without surfacing the audit is itself a §11.4 PASS-
   bluff at the security layer.
4. **If a leak is found:** open a forensic incident record per the
   project's §6/§7 sixth-law-incidents discipline (or equivalent),
   redact the literal values from all tracked files in-place (replace
   with `<redacted-per-§11.4.10>` placeholders), and record an
   OPERATOR ACTION REQUIRED for rotation per §11.4.10 sub-clause 7.
   The redaction commit lives on master IMMEDIATELY; the history-
   purge follow-up (git-filter-repo / BFG / equivalent + force-push
   to every upstream) requires explicit per-operation operator
   authorization per §9.2.
5. **Strengthen pre-push hook detection** when a previously-undetected
   class of literal credential is discovered. The pre-push hook's
   credential-pattern grep MUST be extended to catch the specific
   pattern class that escaped (literal usernames matched with literal
   passwords in the same file, well-known credential SHA-256 hashes,
   org-specific naming conventions for service accounts, etc.). The
   extension MUST land in the same commit as the redaction.

Pre-build gate (recommended) `CM-PRE-STORE-CREDENTIAL-AUDIT` (when
implemented in consuming project) checks the commit message body of
any commit that touches `.env`, `.env.example`, `scripts/testing/
secrets/`, or equivalent for an `Audit-Pre-Stored:` stamp citing the
audit's outcome. Paired mutation (§1.1) strips the stamp and asserts
gate FAILs.

Composes with §11.4.10 (the core credentials mandate this extends),
§11.4.30 (.gitignore + no-versioned-artifacts — overlapping enforce-
ment surface), §11.4.6 (no-guessing — audit findings stated as fact
or as PENDING_FORENSICS), §11.4.7 (demotion-evidence — "I think it's
not leaked" without grep evidence is a guess). Classification:
universal (per §11.4.17). No escape hatch.

### §11.4.11 — File-layout discipline

Project files MUST be organised by purpose, not by historical
accident. Source code goes under canonical project roots. Tests go
under canonical test directories. Logs and forensic artifacts go
under operator-controlled directories (`~/Documents/`,
`qa-results/`, `/tmp/`, OS-equivalent) — NEVER scattered at the
repo root, NEVER inside working source trees, NEVER tracked unless
they are reference assets explicitly required for evidence-replay.

Discovered drift is fixed by **moving** files to their canonical
location and updating every caller — never by adding redirect shims
or by leaving the misplaced copy "for backwards compatibility".

### §11.4.12 — Auto-generated docs sync mandate

Every auto-generated document (Issues_Summary, API reference,
build manifest, etc.) MUST be regenerated in the **same commit** as
any edit to its source. Stale auto-generated docs are §11.4
PASS-bluffs in document form: an operator reading them gets a
divergent view of project state.

All three file types MUST stay in sync at all times — Markdown
source + HTML export + PDF export (or equivalent multi-format
output the project ships). Enforced by a pre-build gate that checks
mtime ordering and content hash agreement.

### §11.4.13 — Out-of-band sink-side captured-evidence

Whenever a downstream consumer (HDMI sink, cloud service, monitoring
target, downstream system) provides a network-accessible
introspection API that reports what was actually received, the test
suite MUST consume that report as captured-evidence for every test
asserting end-to-end delivery.

The on-source-side view ALONE is insufficient — that is the exact
"tests pass but the feature doesn't work" pattern §11.4 forbids.
Sink-side reports MUST be:
- Identity-verified (MAC, serial, UUID match) before consumed as
  evidence.
- Topology-dispatched (§11.4.3) — sink-probe-unreachable → SKIP,
  never FAIL.
- Cross-referenced with the on-source state at a matching
  wall-clock instant.

### §11.4.14 — Test playback cleanup mandate

A test that completes (PASS, FAIL, or SKIP) MUST leave the target
in a quiescent state — no orphan playback, no orphan recording, no
orphan capture, no orphan background process continuing after the
test's last assertion. Tests are transient probes; their side-
effects on shared target state MUST NOT outlive the test.

**Mandatory protections:**

1. Every test that issues a playback or capture command MUST issue
   the matching cleanup at test end (force-stop the app, stop the
   recorder, close the file descriptor, terminate the helper).
2. Cleanup is mandatory on EVERY exit path — PASS, FAIL, SKIP,
   error, trap, signal, parent-killed. Use shell `trap '<cleanup>'
   EXIT` or `try/finally`.
3. Tests MUST verify the cleanup succeeded via positive evidence
   (§11.4.5).
4. The orchestrator MUST run a post-test sanity check between tests
   and FAIL the just-completed test if it left orphan state. This
   blames the leaker, not the next-test victim.
5. No grace period for "the next test will clean it up" — that is
   precisely the §11.4 PASS-bluff pattern. Cleanup is the test's
   responsibility, not the next test's, not the orchestrator's.

### §11.4.15 — Item-status tracking mandate

Every active item tracked in the project's Issues file MUST carry a
`**Status:**` line within five lines of its heading. The status
value is drawn from a closed set:

| State | Meaning |
|---|---|
| `Queued` | In backlog, no work has started. Sub-state qualifier `Queued — BLOCKED on <reason>` permitted. |
| `In progress` | Active investigation or coding underway. |
| `Ready for testing` | Source-side fix landed (pre-build / meta-test gates green), waiting for the next deploy cycle. |
| `In testing` | A deploy + cycle is in flight that exercises the fix; live captured-evidence is being collected per §11.4.2 + §11.4.5. |
| `Reopened` | Item failed its runtime test cycle and is back to active work. Carries a reference to the failure-cycle artefact. |
| `Fixed (→ Fixed file)` | Item closed: captured-evidence per §11.4.5 collected, runtime test PASSes, paired meta-test mutation FAILs, item migrated to the Fixed file. |

Status MUST be updated as the item progresses. Every commit that
changes an item's lifecycle state MUST update its Status line in
the same commit.

All three Issues / Issues_Summary / Fixed file types MUST be in
sync at all times (Markdown + HTML + PDF).

### §11.4.16 — Item-type tracking mandate

Every active item tracked in the project's Issues file MUST carry a
`**Type:**` line within eight non-blank lines of its heading (the
same window the §11.4.15 Status audit uses). The type value is
drawn from a CLOSED set of three values:

| Type | Meaning |
|---|---|
| `Bug` | Product defect / regression / user-visible broken behaviour. The product worked before (or was expected to) and now does NOT for the end user. |
| `Feature` | New capability not previously offered to end users — a new integration, new output, new probe, new bank, new architectural surface. |
| `Task` | Internal workstream — not user-visible. Refactor, infrastructure, documentation, audit, covenant clause, gate, mutation, propagation enforcement, host-session-safety hardening. The largest class by count; the lowest-stakes default when the classification is ambiguous. |

The vocabulary is CLOSED — only `Bug`, `Feature`, `Task`. Any other
value is a violation. When ambiguous, fall back to `Task`.

Type tells the operator WHAT KIND of work an item is — distinct from
severity (HOW URGENT) and status (WHERE IN LIFECYCLE). The three axes
together drive ownership routing, testing strategy, release-note
framing, and changelog classification.

The Issues_Summary file MUST carry the Type column for every active
item. All three file types (Markdown + HTML + PDF) MUST stay in sync
under the same `CM-DOCS-EXPORT-SYNC` discipline as §11.4.12 + §11.4.15.

Pre-build gates `CM-ITEM-TYPE-TRACKING` (scans Issues file for
`**Type:**` presence within the audit window) and
`CM-COVENANT-114-16-PROPAGATION` (anchor presence in every project
CLAUDE.md / AGENTS.md) enforce the mandate. Paired mutations in the
project's meta-test prove neither gate is a bluff gate.

No escape hatch — items that genuinely don't fit MUST be re-classified
as `INFORMATIONAL` and excluded from the active-item set rather than
carry a fabricated Type.

### §11.4.17 — Universal-vs-project classification of new rules (User mandate, 2026-05-14)

**Forensic anchor — direct user mandate (verbatim, 2026-05-14):**

> "Adding any new rules or mandatory constraints or anything relevant
> which should be added into Constitution, CLAUDE.MD, AGENTS.MD and
> relevant files MUST BE determined as reusable / universal VS project
> specific. If it is universal and reusable it MUST BE added into our
> root / main constitution Submodule, otherwise into our project level
> Constitution, AGENTS.MD and CLAUDE.MD (or Submodule if it is
> Submodule related)."

Before any new rule, mandatory constraint, covenant clause, gate
declaration, or "MUST"-bearing statement is added to a project's
Constitution / CLAUDE.md / AGENTS.md or to a child submodule's
equivalents, the author MUST first classify it along this axis:

| Classification | Definition | Destination |
|---|---|---|
| **Universal** (reusable) | The rule applies to ANY project — independent of language, framework, target platform, or domain. Examples: anti-bluff covenant, no-guessing mandate, credentials-handling, host-session safety, item-status tracking, multi-upstream push, file-layout discipline, deep-web-research-before-implementation. | This constitution submodule's `Constitution.md` + `CLAUDE.md` + `AGENTS.md`. Propagates to every consuming project via inheritance. |
| **Project-specific** | The rule references a specific hardware target, vendor, model, SoC, vendor-fork, project-internal package name, deployment topology, or company-internal asset. Examples (illustrative — these are intentionally NOT in this universal file): the SoC's specific power-management quirks; a particular Android/iOS/Linux SDK behaviour; a specific app or service bundled with the project. | The project's own `Constitution.md` / `CLAUDE.md` / `AGENTS.md` (top-level), OR the affected submodule's equivalents (when the rule scopes to that submodule). |

A rule that mentions hardware part numbers, vendor names, specific
package identifiers, geographic regions, or company-internal asset
names is **project-specific by definition** — it cannot be lifted
into the universal layer without genericising those references first.
A universal rule MAY reference patterns (e.g., "USB-HID multitouch
panels") but MUST NOT name specific vendors.

**Anti-bluff:** the universal-vs-project classification is itself an
auditable artefact. Every new rule's commit message MUST include a
one-line classification statement (e.g.,
`Classification: universal — applies to any project tracking items
through an Issues/Fixed lifecycle`). A commit that adds a rule without
classification justification is a §11.4.17 violation.

Authors who are uncertain SHOULD default to project-specific
(narrower scope). Lifting a project-specific rule to universal later
is cheap (one merge); generalising a universal rule that turned out
to leak project-specific assumptions is expensive (every consumer
must update).

Pre-build gate `CM-UNIVERSAL-VS-PROJECT-CLASSIFICATION` audits the
last N commits for rule additions and asserts each one carries a
classification statement. Paired mutation strips the classification
literal and asserts the gate FAILs.

### §11.4.20 — Subagent-driven-by-default mandate (User mandate, 2026-05-14)

**Forensic anchor — direct user mandate (verbatim, 2026-05-14):**

> "Make sure we ALWAYS WORK EVERYTHING subagents-driven if it is
> possible or applicable!"

When operating in a multi-agent runtime (Claude Code with subagents,
Cursor with task-runners, Aider with sub-sessions, or any CLI tool
that supports delegated execution), the primary agent MUST default
to subagent delegation for any task that satisfies AT LEAST ONE of:

1. **Multi-step scope** — three or more discrete editing / file-creation
   / verification phases. Hand-off boundaries are where stalls happen;
   pre-planned subagent decomposition avoids them.
2. **Parallelisable work** — two or more independent tasks with no
   shared mutable state. Parallel subagents finish wall-clock-faster
   than sequential foreground work AND insulate the primary agent's
   context window from the volume of file reads.
3. **Long-running diagnostic loops** — repeated probe / re-test cycles,
   build-flash-cycle loops, soak tests. Subagents survive context
   compression boundaries that would otherwise truncate progress.
4. **Domain-specific or specialised workflows** — code review,
   security audit, infrastructure change review, performance triage,
   documentation propagation across N files. Specialised subagents
   (`code-reviewer`, `iac-reviewer`, `general-purpose`) bring
   pre-curated tool sets and disciplines the primary agent would
   re-derive from scratch.

The primary agent SHOULD only do foreground work when AT LEAST ONE of:

- The task is a single edit or single file read with no follow-up.
- The task requires conversational clarification with the operator
  mid-execution (subagents cannot ask the operator questions).
- The task is gating critical state (a commit, a push, a tag
  cascade) that must be sequenced before the next operator action.
- The task is so quick (under ~30 seconds of execution) that
  subagent spin-up overhead exceeds the work itself.

**Anti-stall discipline.** Subagents have watchdog timeouts in most
runtimes (Claude Code: ~600 s of no-progress). When delegating, the
parent agent MUST: (a) scope tightly (no "complete everything"
prompts — break into 4-6 tightly-scoped tasks); (b) require
**checkpoint commits** after each major task so partial progress is
preserved even on stall; (c) explicitly prohibit destructive
operations the subagent might attempt to "be helpful" (`git reset
--hard`, `git push --force`, `--no-verify`); (d) provide explicit
discipline pointers (§11.4.6 no-guessing, §11.4.10 credentials,
§11.4.17 classification).

**Anti-bluff applied.** A subagent that returns "completed" without
captured evidence in commits / outputs / artifacts is a §11.4
PASS-bluff at the multi-agent layer. The parent agent MUST verify
subagent claims against repo state (`git log`, `git status`,
post-completion gate runs) before treating the work as landed.

**Coordination.** When parallel subagents touch overlapping files,
the parent agent MUST partition the work so subagents work on
**non-overlapping files**. The parent's `commit_all.sh --auto-cascade`
naturally bundles both subagents' dirty files into atomic commits
via `git add -A` — exploit this for "forward-reference + provider"
patterns where one subagent creates files another subagent references.

**No escape hatch.** Operating exclusively in the foreground when
subagent delegation is feasible burns operator wall-clock time, risks
context-window overflow on large tasks, and forfeits the parallelism
that multi-agent runtimes were designed to provide. Pre-build gate
`CM-SUBAGENT-DELEGATION-AUDIT` (when implemented per consuming
project) scans recent session transcripts for multi-step foreground
work that should have been delegated; paired mutation enforces the
gate is not a bluff.

### §11.4.18 — Script documentation mandate (User mandate, 2026-05-14)

**Forensic anchor — direct user mandate (verbatim, 2026-05-14):**

> "Make sure that every single script inside the scripts dir (in all
> subdirs in depth) is fully documented and covered with full user
> manuals and user guides! ... Whenever is some bash script modified
> we MUST document it fully and create for it complete user guide(s)
> and manual(s) - if already exists make sure all of it is in sync
> and fully updated! No documentation ever can be out of sync with
> its codebase!"

Every Bash / shell / POSIX-sh script ANYWHERE in a project (anywhere
under `scripts/`, `bin/`, `tests/`, library directories, `Upstreams/`,
deployment hooks, CI helpers, etc. — depth-N recursive) MUST carry:

1. **In-source documentation block** at the top of the file:
   - Purpose: one-sentence description of what the script does.
   - Usage: complete invocation syntax with all flags, env vars,
     positional arguments, examples.
   - Inputs: env vars, files read, command-line args, stdin.
   - Outputs: files written, stdout/stderr behaviour, exit codes.
   - Side-effects: anything that changes system state outside the
     script's own scratch directory.
   - Dependencies: required commands (and how to install them) +
     required system state (e.g., "must be run as root", "must run
     from project root").
   - Cross-references: companion guides under `docs/`.

2. **External user guide** under `docs/scripts/<script-name>.md`
   (Markdown). Required sections:
   - **Overview** — what the script does in plain English.
   - **Prerequisites** — environment + dependencies.
   - **Usage examples** — copy-paste recipes for the common cases.
   - **Edge cases** — unusual invocations, error conditions, how to
     diagnose them.
   - **Internal behaviour** — for advanced users / future maintainers:
     what the script does step-by-step.
   - **Related scripts** — companion scripts and how they compose.
   - **Last verified version / date** — when the doc was last
     reconciled against the script source.

Whenever the script source is modified, the in-source documentation
block AND the external user guide MUST be updated in the SAME
commit. A commit that touches a script but leaves its documentation
unchanged (or worse, lets it drift) is a §11.4.18 violation.

Pre-build gate `CM-SCRIPT-DOCS-SYNC` walks every `*.sh` and `*.bash`
under `scripts/` (or equivalent script directories), verifies a
companion `docs/scripts/<name>.md` exists, AND verifies the doc was
modified in the same commit as the script (by SHA cross-reference,
or by mtime ≥ script mtime as a softer floor). Paired mutation
strips the doc-sync invariant and asserts the gate FAILs.

**No documentation ever can be out of sync with its codebase.**

This mandate composes with §11.4.11 (file-layout discipline — docs
live under `docs/`, scripts live under `scripts/`) and §11.4.12
(auto-generated docs sync — the on-disk Markdown + its rendered
HTML/PDF must all stay synchronised).

### §11.4.19 — Fixed-document column-alignment mandate (User mandate, 2026-05-14)

**Forensic anchor — direct user mandate (verbatim, 2026-05-14):**

> "Make sure that Fixed document (all 3 file formats) is consistent
> and has the same structure and columns as Issues and Issues_Summary
> documents! This has to be added as detail to Constitution, CLAUDE.MD
> and AGENTS.MD (constitution Submodule where these information shall
> exist)."

Every project that maintains an Issues / open-work tracker AND a
Fixed / closed-archive tracker MUST keep the two structurally
aligned along the same lifecycle axes — at minimum **Status** and
**Type** — so an operator reading either gets a consistent view
across the entire lifecycle (open → in progress → ready for testing
→ in testing → reopened → fixed).

Specifically:

1. **Per-entry annotation.** Every heading in the Fixed archive
   document MUST carry, within 8 non-blank lines of the heading,
   a `**Status:**` line and a `**Type:**` line — exactly as
   §11.4.15 + §11.4.16 require for the Issues tracker. For Fixed
   entries the Status value is drawn from the **closure-set**:
   - `Fixed (→ Fixed.md)` — fully verified on device with captured
     evidence per §11.4.5.
   - `Fixed — pending device verification` — source-side fix
     landed, regression-protection gate wired, awaiting the next
     firmware build + flash + cycle for captured evidence.
   - `Fixed — RECLASSIFIED` — item was reclassified during
     investigation (test-side defect, environment-only, etc.).

   Type values follow §11.4.16: `Bug` | `Feature` | `Task`. Default
   on missing-annotation: `Task`.

2. **Auto-generated companion summary.** A `Fixed_Summary.md` MUST
   exist alongside `Fixed.md`, regenerated by an automation script
   (e.g. `generate_fixed_summary.sh`), and MUST mirror the column
   structure of `Issues_Summary.md` exactly:

   `| # | Level | Status | Type | One-line description |`

   The `Level` (severity) column uses the **original severity** the
   item had when it was open — so an operator can correlate a
   closed item with its original priority bucket. The same
   deterministic classification rules apply (REAL PRODUCT DEFECT /
   PARTIAL-or-WORKSTREAM-or-DEEP-DIVE / everything-else mapping to
   C / M / L).

3. **Three-format sync.** All three file types (`.md`, `.html`,
   `.pdf`) for BOTH the Fixed archive AND the Fixed_Summary MUST
   stay in sync at all times — same `.html` + `.pdf` export pipeline
   that §11.4.12 requires for Issues + Issues_Summary. The
   single-shot sync wrapper (e.g. `sync_issues_docs.sh`) MUST
   invoke the Fixed_Summary generator AND export all five doc
   variants (Issues, Issues_Summary, Fixed, Fixed_Summary,
   CONTINUATION) in one operation so they all carry the same mtime.

4. **Cross-lifecycle consistency.** A status line in Issues.md that
   reads `Fixed (→ Fixed.md)` is a **migration marker**, not a
   self-describing closure: when an Issues.md entry resolves, it
   MUST be moved to Fixed.md in the same commit, then disappear
   from Issues_Summary (because Issues_Summary only enumerates OPEN
   items) and appear in Fixed_Summary (because Fixed_Summary
   enumerates CLOSED items). Per §11.4.4 fix-closure protocol +
   §11.4.5 captured-evidence requirement, the migrated entry in
   Fixed.md MUST carry: closure cycle, closure commit SHA, captured
   evidence pointer, regression-protection gate name + paired
   mutation reference.

**Pre-build gate `CM-FIXED-COLUMN-ALIGNMENT`** (5+ invariants):
   - `docs/Fixed_Summary.md` exists.
   - `docs/Fixed_Summary.md` table header line contains both
     `Status` and `Type` columns (column-alignment with Issues_Summary).
   - `mtime(Fixed_Summary.md) >= mtime(Fixed.md)` (regenerated after
     Fixed.md edits).
   - Generator script exists (`generate_fixed_summary.sh` or
     equivalent integrated branch in `generate_issues_summary.sh`).
   - Sync wrapper invokes the Fixed_Summary generator (grep for
     the script name in `sync_issues_docs.sh` or equivalent).
   - HTML + PDF exports for both Fixed and Fixed_Summary exist
     (`docs/Fixed.html`, `docs/Fixed.pdf`, `docs/Fixed_Summary.html`,
     `docs/Fixed_Summary.pdf`).

**Paired mutation**: strip the Status column from
`Fixed_Summary.md` table header (or rename the generator) → gate
FAILs. Enforced by `meta_test_false_positive_proof.sh`.

**Propagation.** This anchor is a §11.4.17-classified **universal**
rule — it composes naturally with §11.4.12 (auto-generated docs
sync), §11.4.15 (Status tracking), §11.4.16 (Type tracking) and is
mandatory across every consuming project's CLAUDE.md / AGENTS.md.
The propagation gate `CM-COVENANT-114-19-PROPAGATION` (when
implemented per consuming project) enforces the anchor's presence
in every covenant file.

**No escape hatch.** A Fixed archive that lacks Status/Type columns
or whose Summary companion drifts out of sync is the exact
"different lifecycles report different facts" hazard §11.4 forbids
— an operator reading Issues_Summary can no longer answer "where is
item X now?" by cross-referencing Fixed_Summary because the schemas
diverge. Non-compliance is a release blocker regardless of context.

### §11.4.21 — Operator-blocked status + self-resolution exhaustion mandate (User mandate, 2026-05-14)

**Forensic anchor — direct user mandate (verbatim, 2026-05-14):**

> "Add into Issues and Issues_Summary new status: Operator blocked!
> We need another column with details in Issues document with exact
> details on how exactly is operator blocked issue! Before issue
> becomes operator blocked we MUST investigate in-depth all ways on
> how it can be resolved without operator's involvement - by you, or
> by activating any relevant mechanism for the resolution!"

Every project that maintains an Issues / open-work tracker MUST
treat operator dependency as a **last-resort classification**, earned
only after documented exhaustion of self-resolution paths. Routing an
item to the operator without proving the agent + tooling cannot
unblock it themselves is the §11.4 PASS-bluff pattern transplanted
into the planning layer — the work stalls indefinitely while the
agent claims "nothing more I can do."

**1. Status vocabulary extension.** §11.4.15's closed-set of Status
values is extended with a seventh value, `Operator-blocked`. The full
closed-set becomes:

| # | Status value | Meaning |
|---|---|---|
| 1 | `Queued` | Awaiting work to start. |
| 2 | `In progress` | Active agent / developer work. |
| 3 | `Ready for testing` | Source-side fix landed, awaiting verification. |
| 4 | `In testing` | Captured-evidence cycle running. |
| 5 | `Reopened` | Previously closed item resurfaced (regression). |
| 6 | `Operator-blocked` | **NEW.** Cannot proceed without an operator action that the agent + available tooling cannot perform. |
| 7 | `Fixed (→ Fixed.md)` | Closure migration marker per §11.4.15 + §11.4.19. |

**2. Self-resolution exhaustion mandate.** BEFORE classifying any
item as `Operator-blocked`, the agent MUST verifiably exhaust every
self-resolution path applicable to the project:

  - **(a) CLI / ADB / SSH / API access** — can the work be done via
    any access the agent already has? (e.g. `adb shell pm clear`,
    `gh api`, `aws ssm`, `kubectl exec`, `psql`).
  - **(b) Subagent delegation** — can a specialised subagent
    (per §11.4.20) reach further than the primary agent? (e.g.
    `general-purpose` for multi-step probing, `code-reviewer` for
    architectural blockers, `iac-reviewer` for infra access).
  - **(c) Existing tooling** — is there a script / helper / library
    already in the repo that handles this case? (e.g.
    `scripts/testing/<helper>.sh`, project-specific automation).
  - **(d) Captured fallback** — can the blocker be sidestepped with
    a synthetic event, test asset substitution, mock, or
    topology-aware SKIP per §11.4.3? (e.g. simulate the input,
    substitute a stand-in fixture, downgrade to a pre-build gate).
  - **(e) Documentation + research** — per §11.4.8, has the agent
    consulted external sources (official docs, vendor guides,
    open-source codebases, issue trackers) for a self-resolution
    pattern the community has already solved?

Only AFTER each applicable path is **verifiably attempted and
documented as exhausted** is `Operator-blocked` the correct
classification. "I didn't try X because I assumed it wouldn't work"
is a §11.4.6 no-guessing violation AND a §11.4.21 self-resolution
violation.

**3. Operator-Block-Details mandate.** Every `Status:
Operator-blocked` item MUST carry an `**Operator-Block-Details:**`
line within 8 non-blank lines of its heading (mirroring the
§11.4.15 Status placement pattern). The content MUST state ALL of:

  - **WHAT** — the specific concrete action the operator must
    perform (verb + object + target system). Generic "the operator
    must investigate" is forbidden — name the action.
  - **WHY** — the alternatives that were exhausted, enumerated.
    Each exhausted path from §11.4.21.2 above gets a one-line
    statement of what was attempted and why it could not unblock
    the item. "Subagent delegation: tried general-purpose with X
    scope — blocked because Y" is the bar.
  - **UNBLOCK CONDITION** — the observable signal that the operator
    has completed the action (e.g. "operator confirms hardware
    rev-B installed", "operator pastes new API key into
    `scripts/testing/secrets/.foo.env`", "operator force-pushes
    PR #123 merge to upstream"). Without this, the agent cannot
    automatically detect when to re-evaluate.
  - **WHO** — the handle / contact / pointer to the document
    where operator-side details live if questions arise (e.g.
    "operator: @username", "see `docs/operator/<topic>.md`",
    "vendor: support-id 12345"). Operator-blocked without WHO is
    operationally untrackable.

**4. Issues_Summary inclusion as sortable axis.** The auto-generated
`Issues_Summary.md` (per §11.4.12 + §11.4.15) MUST include
`Operator-blocked` as a first-class Status value in the table — the
column header is unchanged but operators can sort / filter on it
deterministically. The summary generator MUST also emit a count
of `Operator-blocked` items in any rollup line / header.

**5. Periodic re-evaluation requirement.** Items in
`Operator-blocked` status MUST be re-evaluated every Nth tag-cycle
(project-defined, recommended every 3rd tag cycle). Operator
dependencies change over time: CI may have been added, hardware may
have been swapped, automation may have matured, vendor APIs may have
unlocked. An item that was correctly Operator-blocked at tag T may
be self-resolvable at tag T+3. Re-evaluation MUST follow the same
§11.4.21.2 exhaustion checklist and document each re-attempt.

**6. Anti-bluff layer.** A fake `Operator-blocked` (classification
applied without exhausting §11.4.21.2 alternatives) is a §11.4
covenant violation at the planning layer — equivalent severity to
a PASS-bluff at the testing layer. The agent's commit message
introducing or maintaining an `Operator-blocked` classification MUST
contain evidence of self-resolution attempts (the explicit
"Attempted: a — exhausted because X; b — exhausted because Y;
c — exhausted because Z" form).

**7. Pre-build gates (recommended, per consuming project):**

  - **`CM-ITEM-OPERATOR-BLOCKED-DETAILS`** — every heading whose
    Status line equals `Operator-blocked` has an
    `**Operator-Block-Details:**` line within 8 non-blank lines.
    Paired mutation strips the details line → gate FAILs.
  - **`CM-OPERATOR-BLOCKED-SELF-RESOLUTION-AUDIT`** — every NEW
    `Operator-blocked` item introduced in a commit carries an
    "Attempted: ..." audit trail (either in the Issues.md entry
    body OR in the commit message). Paired mutation introduces an
    `Operator-blocked` item without the audit trail → gate FAILs.

**Propagation.** This anchor is a §11.4.17-classified **universal**
rule — it composes with §11.4.15 (Status tracking), §11.4.16 (Type
tracking), §11.4.19 (Fixed-document column alignment), §11.4.12
(auto-generated docs sync), §11.4.20 (subagent delegation as a
self-resolution path), §11.4.8 (research-before-implementation as a
self-resolution path), §11.4.6 (no guessing about what the operator
"would have to do"). Propagation gate `CM-COVENANT-114-21-PROPAGATION`
(when implemented per consuming project) enforces the anchor's
presence in every CLAUDE.md / AGENTS.md across the parent + every
owned submodule + every dependency.

**No escape hatch.** Items that legitimately need operator
intervention are real and unavoidable — hardware swaps, vendor
contracts, physical-world inputs, account credentials, irreversible
business decisions. But the classification must be **earned** via
documented exhaustion. An `Operator-blocked` heading without an
audit trail of self-resolution attempts is a §11.4 release blocker
regardless of context.

---

### §11.4.22 — Document-sync commit discipline (User mandate, 2026-05-14)

**Forensic anchor — direct user mandate (verbatim, 2026-05-14):**

> "For Issues, Issues_Summary and Fixed docs (and all its exports) we
> MUST commit and push (only them) as soon as they are updated (synced).
> Continuation doc and other similar / relevant documentation MUST be
> committed and pushed too! Like this we will always have up to date
> status of working items without need to do full commit and push of
> everything if that is not possible to do!"

**Classification:** §11.4.17-classified **universal** — every project
that tracks work items through an Issues / Fixed lifecycle has the
same problem, so the discipline lives in the Constitution and every
consuming project implements its own wrapper.

**The defect this anchor closes.** Until this anchor existed, the only
way to push a status update was the full-tree commit wrapper. When
the working tree had unrelated heavy churn (large submodule diffs,
in-flight rebase, partial-network conditions, ongoing build),
operators had two bad options: (a) wait until the heavy work
finishes — which can be hours — leaving the doc-status stale to every
other agent; (b) skip the doc-status update entirely — which is a
§11.4.4 documentation-drift violation. Neither option is acceptable.

**The mandate.** Every project under this Constitution that ships a
status-tracking doc set MUST provide a **lightweight commit path**
distinct from the full-repo commit wrapper. The lightweight path
stages, commits, and pushes **only** the status-tracking doc set:

1. The active issue tracker (`docs/Issues.md` in ATMOSphere's layout;
   the project's equivalent file elsewhere) and its HTML + PDF exports.
2. The auto-generated issues summary (`docs/Issues_Summary.md`) and
   its HTML + PDF exports.
3. The fixed-bug archive (`docs/Fixed.md`) and its HTML + PDF exports.
4. The auto-generated fixed summary (`docs/Fixed_Summary.md`) and its
   HTML + PDF exports.
5. The cross-session continuation document (`docs/CONTINUATION.md`,
   per §12.10) and its HTML + PDF exports.
6. Any auto-generated audit artifact (`docs/anti_bluff_audit.md` or
   equivalent) that pairs with the above.

The lightweight wrapper MUST:

1. **Auto-invoke the project's export-regeneration pipeline first** —
   so Markdown + HTML + PDF are all synchronised before push.
   (Skipped only when an explicit `--no-sync` flag is passed AND the
   operator just ran the pipeline manually.)
2. **Stage ONLY the doc-set files** — `git add` of an explicit file
   list, NEVER `git add -A` (which would catch unrelated WIP churn).
3. **Use a separate flock** disjoint from the full-tree commit
   wrapper's lock — so the two can run in parallel without
   contention on disjoint file sets.
4. **Push to every parent-repo remote** (reusing the project's
   push-all driver where available).
5. **Exit code semantics** — `0` success, `1` validation failure,
   `2` lock contention, `3` nothing-to-commit (informational, not an
   error — so the wrapper can be wired into automation that
   tolerates no-op outcomes).

The lightweight wrapper MUST be invocable either standalone OR via a
flag on the full-tree wrapper (e.g. `commit_all.sh --docs-only`) so
operators have a single mental model.

**§9 preflight inheritance.** The lightweight wrapper inherits the
parent project's §9 preflight discipline — if `meta_test_*` is mid-
mutation or `*.mut.bak` files exist, the wrapper refuses to run, same
as the full-tree wrapper.

**Pre-build gates (recommended, per consuming project):**

- **`CM-COMMIT-DOCS-EXISTS`** — verifies the lightweight wrapper
  exists + is executable, its external user guide (per §11.4.18)
  exists, the full-tree wrapper advertises the delegation flag, and
  the wrapper's doc-set enumeration lists ≥ N entries (N depends on
  project — ATMOSphere's set is 15). Paired mutation strips the
  doc-set array → gate FAILs.

**Propagation.** Composes with §11.4.12 (export-sync invariant —
HTML + PDF in sync with Markdown after every edit), §11.4.15 (item
status tracking — Status lines must be visible quickly), §11.4.18
(every script ships with an in-source doc block + an external user
guide), §12.10 (CONTINUATION document maintenance — the lightweight
wrapper is one of the mechanisms that keeps CONTINUATION current).

**No escape hatch.** The discipline exists because doc-status drift
is itself a §11.4 PASS-bluff pattern at the documentation layer: a
green-looking `Issues_Summary.html` that doesn't reflect Markdown
reality is the same class of defect as a passing test that doesn't
reflect runtime reality. Operators who can't run the lightweight
wrapper for some reason MUST run the full-tree wrapper and accept
the heavier cost — the doc-status drift is non-negotiable.

---

### §11.4.23 — Visual-cue & grouping mandate for Issues docs (User mandate, 2026-05-14)

**Forensic anchor — direct user mandate (verbatim, 2026-05-14):**

> "We MUST make sure that Issues, Issues_Summary and Fixed docs and its
> exported files (PDFs and HTMLs) have one small improvement: we MUST
> introduce some background coloring for cells of item type and status!
> Also, we MUST group items by the status! ... Base colors for types
> would be: bug - background pale red, task - background pale blue,
> feature - background pale yellow. However, changing the status affects
> the color of the cell of the type and the status cell background color:
> queued - no color, no effect, fixed - both cells pale green, in
> progress - only status cell is pale green, reopened - status cell is
> pale red, blocker - status cell is red (not pale, however MUST BE still
> readable), anything else please follow the same logic!"

**Classification:** §11.4.17-classified **mixed** — the discipline (visual
cues + status grouping for tracked-item docs) is universal across every
project that maintains an Issues / Fixed lifecycle. The implementation
(CSS classes, HTML post-processor, weasyprint integration) is
project-specific because each project's export toolchain differs (pandoc,
asciidoctor, sphinx, etc.).

**The defect this anchor closes.** A long, multi-column tracked-item
table where every row looks identical at first glance is a §11.4
operational-readability defect — operators have to *read* every Status
column to identify what is queued vs in-progress vs fixed. With dozens
to hundreds of items, this is slow enough that operators inevitably
skim, and the doc effectively becomes write-only. Color cues + status
grouping make at-a-glance triage possible.

**The mandate.** Every project under this Constitution that ships
tracked-item docs (per §11.4.15) MUST apply visual-cue coloring AND
status grouping to those docs' HTML + PDF exports. The Markdown source
stays free of color noise (Markdown is the canonical text), but the
HTML + PDF exports MUST be enriched in a post-processing stage:

**Type cell base colors:**

| Type | Background |
|------|-----------|
| Bug | pale red (`#FFE5E5` or equivalent — ~5% red saturation) |
| Task | pale blue (`#E5F0FF`) |
| Feature | pale yellow (`#FFF8DC`) |

**Status cell colors (override the Status column; Fixed also overrides Type cell):**

| Status | Status cell | Effect on Type cell |
|--------|-------------|---------------------|
| Queued | no color (transparent) | keeps base type color |
| In progress | pale green (`#D4F1D4`) | keeps base type color |
| Ready for testing | pale green-blue (`#C6EAEF`) | keeps base type color |
| In testing | pale green-yellow (`#E7F4D6`) | keeps base type color |
| Reopened | pale red (`#FFCCCC`) | keeps base type color |
| Fixed | pale green (`#A8E6A8`) | **also** pale green |
| Operator-blocked / Blocker | vibrant red (`#FF4444`) with white text for readability | keeps base type color |

**Status grouping:** items in the rendered table MUST be grouped by
Status, emitting an H3-class heading for each Status group with the
item count. Group order (most-actionable first; closed last):

1. Operator-blocked / Blocker
2. In testing
3. Ready for testing
4. In progress
5. Reopened
6. Queued
7. Fixed

This ordering surfaces the items requiring operator attention at the
top of the doc; closed/archived items sink to the bottom.

**Print-fidelity requirement.** The CSS MUST declare
`print-color-adjust: exact` (or the project's renderer's equivalent) so
PDF exports preserve the cell backgrounds. A weasyprint default-rendered
PDF that strips colors is a §11.4 export-drift defect — HTML and PDF MUST
be visually equivalent.

**Pre-build gates (recommended, per consuming project):**

- **`CM-DOC-COLOR-GROUPING-DISCIPLINE`** — verifies the project's CSS
  carries the type+status class set, the post-processor exists and is
  executable, the sync wrapper invokes it, AND after sync the rendered
  HTML carries the grouping-heading + per-cell color classes (the
  captured-evidence proof — without this last invariant a stub
  post-processor could silently pass the static gate). Paired mutation
  strips a Status class literal from CSS → gate FAILs.

**Propagation.** Composes with §11.4.12 (export-sync invariant —
HTML + PDF in sync with Markdown after every edit), §11.4.15 (item
status tracking — every active item carries a Status line from the
closed-set vocabulary), §11.4.19 (Fixed_Summary column-aligned
companion), §11.4.22 (lightweight commit path for doc-set updates).

**No escape hatch.** Color cues are not optional polish — they are the
operational-readability seam that converts a long tracked-item table
from a write-only Markdown blob into a self-triaging document.

---

### §11.4.24 — Build-resource stats tracking mandate (User mandate, 2026-05-14)

**Forensic anchor — direct user mandate (verbatim, 2026-05-14):**

> "We need to incorporate through the Containers Submodule we use to run
> our System build Container the following mechanism safely: during its
> working lifetime we MUST track in proper Markdown document exported
> into PDF and HTML stats on System resources use! What was the peak and
> the minimum EVER the Container / System building process used! ... In
> top of the document we MUST have this ever values. ... After this we
> MUST present properly sorted divided by version tags names all build
> processes we were running with notes if the process completed with
> success or not, and resources usage during the process! Besides min
> and max values ever and per build iteration we MUST have for each
> resource we have average values — average memory usage, average CPU
> usage, and all other parameters IO and other resources!"

**Classification:** §11.4.17-classified **mixed** — the discipline of
tracking host-side build-resource usage with min / max / mean / p95
per-build PLUS ever-values across all builds in a versioned Markdown +
HTML + PDF triple is universal across every long-build project
(AOSP, kernel, large monorepo, ML model training, multi-hour data
pipelines). The implementation (registry path, monitor script name,
exporter wiring) is project-specific.

**The defect this anchor closes.** Long builds (multi-hour AOSP builds,
ML training runs, large monorepo CI) consume highly variable resource
profiles over their lifetime — soong_build's 33 GB peak coexists with
quiescent linker-only stretches at <2 GB. Without per-build sampling +
ever-values, operators have NO empirical basis to (a) size containers
correctly, (b) detect resource regressions across versions, (c) prove
which build iteration was the OOM-killer's trigger, (d) reason about
parallelism caps (cf. §12.7 -j2 hard cap whose forensic basis would
have been one full Stats.md generation earlier had this discipline
been in place). Memory pressure debugging without time-series data
is the bluff this anchor forbids.

**The mandate.** Every project under this Constitution with a build
exceeding **1 minute wall-clock** MUST:

**1. Run a host-side resource sampler for every build.** The sampler
runs as a sibling background process (not inside the build's own
process tree), reads `/proc/meminfo` + `/proc/loadavg` + `/proc/stat`
+ `/proc/diskstats` (or platform equivalents on non-Linux) at a fixed
interval (recommended 5 s default — fine-grained enough to catch
seconds-long peaks; coarse enough to keep itself <5% CPU and <50 MB
RSS). Samples written as TSV.

**2. Compute per-build summaries on stop.** Per metric (memory used,
CPU%, load average, disk read/write): **min, max, mean, p95**. p95 is
the 95th-percentile sample value — required because mean alone hides
extended-peak behaviour (a 2 h build with one 33 GB soong_build peak
has mean ≈ 18 GB but p95 ≈ 32 GB; the latter is what operators must
size for).

**3. Append per-build summaries to a registry.** One TSV row per
build (build_id, status SUCCESS/FAIL/UNKNOWN, start/end timestamps,
per-metric min/max/mean/p95, total disk read/write). The registry
is the single source of truth — the Markdown report is derived.

**4. Maintain ever-values across ALL builds.** Min / max / mean
across every tracked build, computed on every Markdown regeneration
from the registry. Surface at the **top** of the report per User
mandate verbatim.

**5. Markdown + HTML + PDF triple.** Stats.md (auto-generated),
exported to Stats.html + Stats.pdf through the project's normal
export pipeline. Triple stays in sync per §11.4.12. Committed via the
project's lightweight doc-sync wrapper per §11.4.22.

**6. Sort per-build entries by recency (most recent first) AND,**
where applicable, **group by version tag.** Operators reading the
report want the latest build's profile at the top and the historical
sweep underneath.

**7. Track status per build.** SUCCESS / FAIL / UNKNOWN — and if FAIL,
capture the reason (exit code, OOM, ANR, etc.). A FAIL build's
resource profile is the most operationally interesting one in the
report — never silently drop FAIL entries.

**8. Performance budget for the sampler itself.** <50 MB RSS,
<5% CPU. The monitor MUST NOT itself contribute to the resource
pressure it is measuring (Heisenberg-class observer effect at scale).
Pure /proc reads + awk arithmetic is the reference implementation;
vmstat / pidstat acceptable; psrecord / heavy-Python-import samplers
are forbidden.

**9. Survive build failures.** The stop hook MUST be called from both
the success AND failure paths of the build wrapper so FAIL builds
still produce a row. Hooking only the success path is a PASS-bluff at
the telemetry layer.

**Pre-build gate (recommended, per consuming project):**

- **`CM-BUILD-RESOURCE-STATS-TRACKER`** — verifies (a) the monitor
  script exists + executable, (b) the Stats.md target file exists,
  (c) the build wrapper invokes start AND stop, (d) the doc-sync
  wrapper enumerates the Stats.{md,html,pdf} triple, (e) the
  exporter advertises the build-stats slug. Paired mutation hides
  the monitor script aside → gate FAILs.

**Propagation.** Composes with §11.4.12 (export-sync invariant —
HTML + PDF in sync with Markdown), §11.4.18 (script-documentation
discipline — the monitor ships with an external user guide),
§11.4.22 (lightweight doc-sync commit wrapper enumerates the
Stats.{md,html,pdf} triple), §12.6 / §12.7 / §12.9 (host-safety +
containerized-build envelope whose forensic anchors are the
empirical motivation for this telemetry).

**No escape hatch.** Build-resource tracking is not optional polish —
it is the operational-evidence seam that converts post-mortem "the
build OOM'd, no idea why" into "build X at git-SHA Y peaked at Z GB
at minute N, which is W% above the rolling p95". The discipline pays
for itself the first time it diagnoses a build-resource regression.

### §11.4.25 — Full-Automation-Coverage Mandate (User mandate, 2026-05-15)

**Forensic anchor — verbatim user mandate (2026-05-15):**

> "Make sure that every feature, every functionality, every flow,
> every use case, every edge case, every service or application, on
> every platform we support is covered with full automation tests
> which will confirm anti-bluff policy and provide the proof of
> fully working capabilities, working implementation as expected, no
> issues, no bugs, fully documented, tests covered! Nothing less
> than this does not give us a chance to deliver stable product!
> This is mandatory constraint which MUST BE respected without
> ignoring, skipping, slacking or forgetting it!"

**Operative rule.** For every consuming project under this
Constitution, no feature, functionality, flow, use case, edge case,
service, or application on any supported platform may be considered
**deliverable** until it is covered by automation tests that
collectively prove six invariants:

1. **Anti-bluff posture (per §7.1 + §11.4):** every assertion carries
   captured runtime evidence; metadata-only / configuration-only /
   grep-based / absence-of-error PASSes are forbidden.
2. **Proof of working capability:** the user-visible behaviour is
   exercised end-to-end on the target platform topology
   (per §11.4.3), not in a mock or in-memory facsimile.
3. **Working implementation as expected:** assertions match the
   product's documented promise (in user manual, README, specs),
   not an implementation-detail back-door.
4. **No issues, no bugs:** the test suite is the canonical seam for
   surfacing defects — passing without producing defect signals
   means defects do not exist or have been previously surfaced,
   tracked (per §11.4.15 / §11.4.16), and closed.
5. **Fully documented:** the feature has a user-facing doc entry
   (per §11.4.18 for scripts, and project-level user-manual
   coverage for everything else); the doc is kept in sync with the
   tests (per §11.4.12).
6. **Tests-covered (the four-layer floor per §1):** pre-build
   presence-of-change gate, post-build artifact-shipped gate,
   runtime / integration / on-device gate, AND meta-test paired
   mutation that proves the runtime gate catches the break.

**Cross-cutting reach.** This mandate is **universal** — it applies
to every project consuming this Constitution, every feature surface
they expose (HTTP endpoints, CLI commands, slash commands, IPC
channels, plugins, hooks, MCP servers, agents, providers, integrations,
GUI flows, mobile flows, scheduled jobs), and every supported
platform (Linux, macOS, Windows, iOS, Android, AuroraOS, HarmonyOS,
embedded, containers, headless servers, kiosk, etc.). A project that
ships a feature without satisfying all six invariants is **not
delivering a stable product**, irrespective of how green its summary
line looks.

**Coverage audit.** Consuming projects MUST publish a coverage
ledger (matrix of: feature × platform × invariant-1..6 × status)
that is regenerated as part of the release-gate sweep. The ledger
itself is documented (per §11.4.18 / §11.4.12) and committed via
the §11.4.22 lightweight doc-sync wrapper. Gaps in the ledger
(`UNCONFIRMED:` / `PENDING:` / `BLOCKED:` cells) MUST cite a tracked
work item per §11.4.15 + §11.4.16; rows that quietly omit a
platform are §11.4.25 violations.

**Composition.** §11.4.25 explicitly stacks on top of §1
(four-layer test-coverage floor), §1.1 (false-positive immunity),
§7.1 (positive-evidence-only validation), §11.4.1 (FAIL-bluffs
forbidden), §11.4.2 (recorded-evidence requirement), §11.4.3
(per-environment-topology dispatch), §11.4.6 (no-guessing),
§11.4.15 / §11.4.16 (status + type tracking), §11.4.17
(universal-vs-project classification — this rule is universal),
§11.4.18 (script documentation), §11.4.20 (subagent delegation
when the work is multi-step), §11.4.22 (lightweight doc-sync).
It does NOT supersede them; it forecloses the loophole "the
feature works locally for me, ship it".

**Classification:** universal (per §11.4.17). No escape hatch.
Severity-equivalent to a §11.4 PASS-bluff at the release-gate
layer — a project claiming "Done" without honoring §11.4.25 is
making a false claim regardless of how the work-item tracker
labels the row.

### §11.4.26 — Constitution-Submodule Update Workflow Mandate (User mandate, 2026-05-15)

**Forensic anchor — verbatim user mandate (2026-05-15):**

> "Every time we add something into our root (constitution
> Submodule) Constitution, CLAUDE.MD and AGENTS.MD we MUST FIRST
> fetch and pull all new changes / work from constitution Submodule
> first! All changes we apply MUST BE commited and pushed to all
> constitution Submodule upstreams! In case of conflict, IT MUST BE
> carefully resolved! Nothing can be broken, made faulty, corrupted
> or unusable! After merging full validation and verification MUST
> BE done!"

**Operative rule.** Before ANY agent or operator modifies the
`constitution/Constitution.md`, `constitution/CLAUDE.md`, or
`constitution/AGENTS.md` files of a project that consumes this
Constitution as a submodule, the agent or operator MUST execute
the following pipeline in order, with NO step skipped:

1. **Fetch + pull first.** From inside the `constitution/`
   submodule worktree, run `git fetch <every-configured-remote>`
   followed by `git pull --ff-only origin <branch>` (or
   `--rebase` if non-FF-mergeable; **never** `--strategy=ours` /
   `--allow-unrelated-histories` without explicit operator
   authorization). The submodule MUST be at upstream tip BEFORE
   any local edit is applied.
2. **Apply the change.** Edit the relevant file(s). The edit MUST
   classify itself per §11.4.17 (universal vs project-specific) —
   only universal additions belong in the constitution submodule;
   project-specific clauses belong in the consuming project's
   own governance files. The edit MUST include the verbatim user
   mandate (if it originated from one) as a forensic anchor.
3. **Validate before commit.** Run the constitution submodule's
   `meta_test_inheritance.sh` (or equivalent) to confirm the
   inheritance chain still resolves. Verify no governance file
   was left with merge-conflict markers (`<<<<<<<`, `=======`,
   `>>>>>>>`). Verify all three governance files (Constitution +
   CLAUDE + AGENTS) cross-reference the new clause consistently.
4. **Commit + push to ALL upstreams.** Stage only the governance
   files (NEVER `git add -A` inside the constitution submodule —
   stray local artefacts MUST NOT enter governance). Commit with
   a message that cites the user mandate (verbatim quote) + the
   classification line per §11.4.17. Push to **every** configured
   remote of the constitution submodule. A commit that lives on
   one upstream but not others is a §11.4.26 violation equivalent
   to a §2.1 multi-upstream-push violation.
5. **Conflict resolution.** If `pull --ff-only` reports
   non-fast-forward, the merge MUST be performed carefully:
   inspect both sides, preserve the union of governance content
   (no clause silently dropped), re-classify per §11.4.17, validate
   per step 3. Force-push to "make conflicts go away" is FORBIDDEN
   (§9.2). Nothing about the constitution may be broken, made
   faulty, corrupted, or rendered unusable by the merge.
6. **Post-merge validation + verification.** After the push lands,
   re-clone (or `git submodule update --remote --init`) in a
   throwaway worktree and re-run the consumer project's
   inheritance-cascade verifier (e.g. `scripts/verify-governance-
   cascade.sh`) to confirm the new clause reaches every owned
   submodule per CONST-047. Any cascade gap MUST be closed in the
   same change-window.
7. **Update the consuming project's pointer.** The consuming
   project's `.gitmodules`-tracked submodule pointer MUST be
   bumped to the new constitution HEAD in the SAME commit as any
   downstream cascade work; out-of-sync submodule pointers are a
   §11.4.26 violation.

**Operational scope.** This workflow applies regardless of who
initiates the change (operator, primary agent, subagent per
§11.4.20, automated lint suggestion). The workflow CANNOT be
shortcut by "I'll fetch later" or "I'll push to the other
upstreams in the next commit". The constitution is the **single
source of truth** for every project that imports it; allowing it
to fragment across upstreams is the structural equivalent of a
§11.4 PASS-bluff at the governance layer.

**Cross-cutting reach.** §11.4.26 composes with: §2 (single-
entrypoint commit wrapper), §2.1 (multi-upstream push), §3
(submodule changes propagate through submodule commits first),
§9.1 / §9.2 (data-safety + force-push authorization),
§11.4.17 (universal-vs-project classification), §11.4.22
(lightweight doc-sync), §11.4.25 (full-automation coverage —
the post-merge validation step is itself a form of automation
coverage). It does NOT supersede them.

**Classification:** universal (per §11.4.17). No escape hatch.
A constitution-submodule change that violates §11.4.26 is a
release blocker for every consuming project, equivalent in
severity to a force-push without §9.2 authorization.

---

### §11.4.31 — Submodule-Dependency-Manifest Mandate (User mandate, 2026-05-15)

**Forensic anchor — verbatim user mandate (2026-05-15):**

> "We MUST HAVE mechanism for each Submodule to determine / know
> what are its Submodule dependencies so new projects or palces we
> are incorporate them can add these Submodules to the project root
> and make them available! Suggested idea is configuration file
> with expected Submodules Git ssh urls perhaps? New project can
> read it, and recursively add each Submodule to the root of the
> project and install / expose it to veryone. This MUST be
> analyzed and applied. We MUST apply the best strategy for this
> which can be easily executed just by following our root
> Constitution, AGENTS.MD and CLAUDE.MD! Process this, extend out
> Constitution, AGENTS.MD and CLAUDE.MD with mandatory
> instructions and then process project root and all Submodules
> deep recursively so proper configuration Submodules dependency
> files are created! Document EVERYTHING and cover with all
> supported test types! Any kind of bluff is strictyl forbidden!
> All wotk MUST come with mechanism for validation and
> verification by creating proper proofs for all critical points!"

**Operative rule.** Every owned-by-us submodule MUST ship a
machine-readable, version-controlled **dependency manifest** at
the canonical path `helix-deps.yaml` (or `helix-deps.json` /
`helix-deps.toml` if the submodule's ecosystem strongly prefers a
different serialisation — but only one canonical file per
submodule, and its name MUST appear in the submodule's
`README.md` + governance trio).

**Manifest schema (CONST-051(C)-aligned):**

```yaml
# helix-deps.yaml
# Declares this submodule's own-org dependencies. Consuming projects
# read this manifest recursively and add each declared dependency to
# their root at <root>/<name>/ or <root>/submodules/<name>/ per
# CONST-051(C). Nested own-org submodule chains are FORBIDDEN — this
# manifest is the bridge.

schema_version: 1
deps:
  - name: Challenges                                  # canonical name (will become snake_case per §11.4.29)
    ssh_url: git@github.com:vasic-digital/Challenges.git
    ref: main                                         # branch or pinned tag
    why: "Cross-cutting Challenges + Panoptic browser harness"
    layout: flat                                      # 'flat' = <root>/<name>/; 'grouped' = <root>/submodules/<name>/
  - name: HelixQA
    ssh_url: git@github.com:HelixDevelopment/HelixQA.git
    ref: main
    why: "Anti-bluff QA orchestration + autonomous-session driver"
    layout: flat

transitive_handling:
  # Each declared dep itself ships a helix-deps.yaml. The incorporator
  # tooling MUST recurse — top-level project gets the union of all
  # transitively-declared deps, flattened to root.
  recursive: true

  # When two submodules declare the same dependency at different
  # refs, CONFLICT — operator MUST resolve before incorporation
  # proceeds. The incorporator aborts on conflict (never silently
  # picks one).
  conflict_resolution: operator-required

language_specific_subtree: false      # set true for Android/Kotlin/Apple
                                       # roots (per §11.4.29 exception);
                                       # excludes inner subtree from
                                       # snake_case enforcement.
```

**Tooling contract.** A consuming project MUST be able to bootstrap
its entire own-org dependency graph by:

1. Running `incorporate-submodule <ssh-url>` (canonical name; lives
   in the constitution submodule's `scripts/` or in a parent
   project's bin path).
2. The script:
   - Adds the supplied submodule at its declared canonical path
     (per CONST-051(C) `flat` vs `grouped` layout).
   - Reads the newly-added submodule's `helix-deps.yaml`.
   - For each declared dep, checks if it already exists at the
     consuming project's root; if missing, recurses (incorporate-
     submodule on the dep's ssh_url).
   - On conflict (same name declared at different ref by two
     submodules), aborts with a directed error pointing the
     operator at the conflicting declarations.
   - Emits a final manifest-of-manifests file at
     `<root>/.helix-manifest.yaml` listing every submodule + its
     declared deps, for audit + reproducibility.

**Anti-bluff guarantee.** Every manifest MUST be paired with a
**verification proof**: a Challenge script (per §11.4.27 +
CONST-050(B)) that:

- Bootstraps a throwaway consuming project from scratch in a temp
  directory.
- Runs `incorporate-submodule` against the manifest under test.
- Verifies the produced submodule layout matches the manifest's
  declarations (every dep present at its declared layout path; no
  extras; no missing).
- Runs the submodule's own test suite against the bootstrapped
  layout; asserts pass.
- Captures wire evidence (per §11.4.2) of every step.

A manifest without this verification proof is a §11.4.31 violation
of equal severity to a §11.4 PASS-bluff at the dependency-graph
layer.

**Cascade requirement.** Every owned-by-us submodule MUST ship
`helix-deps.yaml` at its root, recursively (sub-submodules of
submodules ship their own). The constitution submodule itself
ships a manifest declaring its own deps (currently empty for the
universal Constitution; project consumers may have project-specific
extensions). The verifier (`scripts/verify-governance-cascade.sh`
or its successor) MUST check every owned submodule for manifest
presence.

**Composition.** §11.4.31 directly enables §11.4.28 / CONST-051(C)
flat-layout enforcement: nested own-org submodule chains can be
mechanically flattened because each submodule declares what it
needs, and the incorporator places those deps at the root.
Composes with §1 (manifest schema is itself tested for parse +
validation), §3 (submodule-first commit discipline applies to
manifest changes too), §11.4.12 (manifest changes regenerate any
derived docs/diagrams), §11.4.17 (universal — no project-specific
assumptions in the manifest format), §11.4.18 (manifest documented
in script-doc + external user guide), §11.4.20 (subagent delegation
for cross-submodule manifest authoring), §11.4.25 (manifest
presence in coverage ledger), §11.4.26 (constitution-update
workflow when extending manifest schema), §11.4.27 (manifest test
matrix), §11.4.28 (this rule is its operational complement),
§11.4.29 (manifests use snake_case names + canonical paths),
§11.4.30 (manifest is tracked source — not a build artefact),
CONST-047 (manifests cascade recursively).

**Classification:** universal (per §11.4.17). No escape hatch.
Severity-equivalent to a §11.4 PASS-bluff at the dependency-graph
layer.

### §11.4.32 — Post-Constitution-Pull Validation Mandate (User mandate, 2026-05-15)

**Forensic anchor — verbatim user mandate (2026-05-15):**

> "Every time we fetch and pull new changes on constitution
> Submodule we MUST process the whole project and all Submodule
> (deep recursively) for validation and verification taht every
> single rule or mandatory constraint is followed and respected!
> If it is not, IT MUST BE!"

**Operative rule.** Whenever a consuming project's constitution
submodule is fetched + pulled with **any** content change (rule
addition, rule revision, gate addition, anchor reference, version
bump), the consuming project MUST execute a full-project +
recursive-submodule validation sweep BEFORE the new constitution
HEAD is treated as canonical for any other work.

**Validation sweep contract.** The sweep is implemented as
`scripts/verify-all-constitution-rules.sh` (canonical name) which:

1. Re-runs the existing governance-cascade verifier (`scripts/
   verify-governance-cascade.sh`) covering every §11.9 + CONST-*
   anchor across every owned submodule (recursive per CONST-047).
2. For each rule whose enforcement gate is implementable
   programmatically (e.g., CONST-053 `.gitignore`-pattern audit;
   CONST-051(C) nested-own-org-chain audit; CONST-052
   case-conformance audit; CONST-050(A) mock-path-from-production-
   code audit; CONST-035 anti-bluff smoke-scan), the sweep runs
   the corresponding gate against the post-pull tree.
3. Any failure produces a directed FAIL entry naming the rule
   (e.g., `FAIL: CONST-053 — *.log tracked at HelixCode/foo.log`)
   + the canonical fix.
4. Failures populate the project's Issues tracker per §11.4.15
   with Status: `Reopened` (since a previously-passing audit now
   fails) and Type: `Bug` (since real codebase state violates the
   constitution).
5. The agent or operator MUST resolve every FAIL before treating
   the new constitution HEAD as canonical — closure of each
   reopened item per the existing §11.4 anti-bluff covenant
   (positive-evidence-only, captured wire evidence).

**Pull-time invocation.** `git submodule update --remote constitution`
MUST trigger the sweep automatically (post-update hook OR the
operator's commit wrapper invokes it as part of any commit that
advances the constitution submodule pointer). Operator-explicit
manual invocation MUST also be available
(`./scripts/verify-all-constitution-rules.sh`).

**Anti-bluff guarantee.** A sweep that exits PASS without actually
running every implementable gate is a §11.4.32 violation. The
sweep's own meta-test (paired mutation, §1.1) MUST plant a known
violation of each enforced gate and assert the sweep reports
FAIL for the planted gate.

**Composition.** §11.4.32 is the **enforcement engine** for every
other §11.4.x and CONST-NNN rule. Without it, new rules cascade
as anchors but never get enforced in the codebase. Composes with
every rule that has a programmatic gate: §1, §1.1, §11.4.10,
§11.4.12, §11.4.15, §11.4.16, §11.4.18, §11.4.20, §11.4.22,
§11.4.24, §11.4.25, §11.4.26, §11.4.27, §11.4.28, §11.4.29,
§11.4.30, §11.4.31, CONST-035, CONST-038, CONST-042, CONST-043,
CONST-044, CONST-045, CONST-046, CONST-047, CONST-048, CONST-049,
CONST-050, CONST-051, CONST-052, CONST-053, CONST-054.

**Classification:** universal (per §11.4.17). No escape hatch.
Severity-equivalent to a §11.4 PASS-bluff at the constitutional-
enforcement layer — without §11.4.32, every other rule is a
decorative anchor rather than an enforced gate.

### §11.4.30 — .gitignore + No-Versioned-Build-Artifacts Mandate (User mandate, 2026-05-15)

**Forensic anchor — verbatim user mandate (2026-05-15):**

> "every project module, every Submodule, every servcie and
> apolication MUST HAVE proper .gitignore file! We MUST NOT git
> version build artifacts, cache files, tmp files, main .env
> file(s) or any files containing sensitive data, API keys or
> token! Any build derivate which we can recreate by executing
> proper mechanism for generating MUST NOT be versioned! We MUST
> pay attention what is going to be commited every time we are
> preparing to execute commit! If any violetion is detected it
> MUST be fixed before commit is executed!"

**Operative rule.** Every project module, owned-by-us submodule,
service, and application under this Constitution MUST ship a
proper `.gitignore` covering its full set of forbidden-from-version-
control patterns. The following file/directory classes MUST NEVER
appear in version control:

1. **Build artefacts** — anything produced by a build / compile /
   package step that can be regenerated from sources:
   - Binaries (`/bin/`, `/build/`, `/dist/`, `/out/`, `target/`,
     `*.exe`, `*.dll`, `*.so`, `*.dylib`, `*.a`, `*.o`, `*.class`,
     `*.pyc`).
   - Generated source files where the generator is committed (e.g.
     protobuf `.pb.go` may be checked in OR ignored — project
     decides — but never both).
   - Bundled assets where the bundler is committed.

2. **Cache files** — anything a tool regenerates on demand:
   - `__pycache__/`, `.pytest_cache/`, `.mypy_cache/`,
     `.ruff_cache/`, `node_modules/`, `.next/`, `.nuxt/`,
     `.cache/`, `.gradle/`, `.idea/cache/`, `.vscode-test/`,
     `target/`, `.terraform/`, language-server caches.

3. **Temp files** — `*.tmp`, `*.swp`, `*.swo`, `*~`, `.DS_Store`,
   `Thumbs.db`, IDE backup files, `*.orig`, `*.rej`.

4. **Sensitive-data files** — anything containing credentials,
   tokens, keys, or personal data:
   - `.env`, `.env.*` (allow `.env.example` / `.env.sample` /
     `.env.template` with placeholder values only — never real
     secrets even as examples).
   - `*.pem`, `*.key`, `*.crt`, `*.p12`, `*.pfx`,
     `id_rsa*`, `id_ed25519*`, `*.kdbx`, `.netrc`,
     `secrets/` directory trees.
   - `api_keys.sh`, any file containing `BEGIN PRIVATE KEY`,
     credential tokens, or session cookies.

5. **Generated reports / logs** — `*.log`, `coverage.out`,
   `*.coverage`, `htmlcov/`, `*.gcda`, `*.gcno`, screenshots/
   recordings that aren't reference assets.

6. **OS / IDE / personal-state files** — `.idea/`, `.vscode/`
   (except shareable `.vscode/settings.json` etc. if explicitly
   project-shared), `.history/`, `.svn/`, editor-state files.

7. **Test playback artefacts** (§11.4.14) — every test's runtime
   capture goes under an ignored evidence directory unless the
   capture IS the reference asset.

**Anti-bluff invariant.** Per CONST-035 / §11.4 the presence of a
`.gitignore` line alone is not sufficient — the project MUST also
verify that no file matching the forbidden patterns is currently
tracked. A `.gitignore` that lists `*.log` while `app.log` sits
tracked in the repo is a §11.4.30 violation of equal severity to
no `.gitignore` at all.

**Pre-commit attention.** Every commit author (human OR agent)
MUST inspect `git diff --staged` and `git status` BEFORE executing
the commit. If a staged path matches any forbidden class, the
commit MUST be aborted and the issue fixed (un-stage the path,
add to `.gitignore`, scrub if already-tracked). Gate
`CM-GITIGNORE-PRECOMMIT-AUDIT`: pre-commit hook (or commit wrapper
in §2) inspects every staged path against the forbidden-pattern
matrix; hits abort the commit with a directed error pointing the
operator at the specific offending path and the canonical fix.
Paired mutation (§1.1): stage a `*.log` → gate FAILs.

**Cascade reach.** This rule applies recursively to every owned-by-
us submodule per CONST-047 and to every owned-submodule's nested
non-owned trees within their working copy. The `.gitignore` files
themselves are project-specific in their concrete patterns but
universally bound to the rule's normative force.

**Secret-leak intersection.** §11.4.30 composes tightly with
§11.4.10 (Credentials-handling mandate / CONST-042) and §12.1.
A `.env` leak is BOTH a §11.4.30 violation (build/sensitive file
versioned) AND a §11.4.10 violation (credential leak). The
combined severity is **release-blocker requiring rotation +
post-mortem** per §11.4.10.

**Coverage of "recreatable" content.** When in doubt about
whether something is a build derivative: if there exists a
documented, scripted, or automated mechanism that recreates the
file from sources, the file is a build derivative and MUST be
ignored. The committed sources MUST include the generator
(Makefile target, npm script, codegen invocation), so any
downstream consumer regenerates the artefact on demand.

**Classification:** universal (per §11.4.17). No escape hatch
beyond the explicit exceptions enumerated above (e.g., `.env.example`
placeholder files). Severity-equivalent to a §11.4 PASS-bluff at
the repository-hygiene layer — a tracked build artefact silently
drifts vs. its source over time, producing the same class of
"works-on-my-machine" surprise that the §11.4 anti-bluff covenant
forbids at the test layer.

**Composition.** §11.4.30 composes with §1 (test coverage —
ignored files don't get spuriously included in coverage stats),
§2 (commit-wrapper enforces the pre-commit gate), §9.1
(destructive-operation safeguards — never `git clean` an
operator's working tree to "fix" a violation), §11.4.10
(credentials-handling), §11.4.12 (auto-generated docs sync —
generators committed, outputs ignored only if recreatable on
demand from the same generator),  §11.4.17 (universal —
applies to every consuming project), §11.4.18 (script docs —
generator scripts documented), §11.4.20 (subagent delegation
for cross-submodule .gitignore audit sweeps), §11.4.25
(coverage ledger lists `.gitignore` presence per submodule),
§11.4.26 (constitution-update workflow — the constitution
submodule's own `.gitignore` complies), §11.4.27 (no-fakes:
test fixtures that ARE the reference asset are tracked; runtime
captures are ignored), §11.4.28 (submodules-as-equal-codebase:
each submodule's `.gitignore` audited on equal basis), §11.4.29
(the renamed paths in the lowercase migration MUST also be
properly ignored where applicable), CONST-047 (recursive
governance reach).

### §11.4.29 — Lowercase-Snake_Case-Naming Mandate (User mandate, 2026-05-15)

**Forensic anchor — verbatim user mandate (2026-05-15):**

> "naming convention for Submodules and directories (applied deep
> into hierarchy recursively) - all directories and Submodules MSUT
> HAVE lowercase names with space separator between the words of
> '_' character (snake-case)! All existing Submodules and
> directories which are not following this rule MUST BE renamed!
> However, since this will most likely break some of the
> functionalities renaming we do MUST BE applied to all references
> to particular Submodule or directory! Everywhere where particular
> Submodule directory are referenced proper updates MUST BE applied
> - all configuration files, documentation and relevant materials,
> links to Submodules and directories, source code that points to
> them, etc. There MUST BE reasonable exceptions for this rules -
> source code for programming languages or Submodules which apply
> different naming convention - Android, Java, Kotlin and others.
> Root directory for such applications, services or Submdoules can
> follow OUR convention, but EVERYTHING inside still MUST follow
> language / technology specific rules! We apply this rules per
> common sense basis and it MUST NOT be the cause of bigger issues
> such as technology breaking! Upstreams directory which all of our
> projects and Submodules have MUST BE renamed to the lowercase
> letters too, however root project containing the install_upstreams
> system command (it is exported in out paths in our .bashrc or
> .zshrc) MUST BE updated to fully work with both Upstreams and
> upstreams directory. That change if it is not already applied
> MUST BE done, commited and pushed! ... NOTE: Rules lowercase /
> snake-case do apply to all project files as well and references
> to it and from them! Every change done MUST BE covered with all
> supported test types, full automation tests for validation and
> verififcation and fully applied and followed anti-bluff policy
> and all anti-bluff rules!"

**Operative rule.** Every directory, submodule, and file under
the parent project's working tree MUST use a **lowercase,
snake_case** name (ASCII letters / digits / underscores, words
separated by `_`). Existing names that violate the rule
(`HelixCode/`, `Challenges/`, `Containers/`, `HelixAgent/`,
`HelixQA/`, `Security/`, `Github-Pages-Website/`, `Upstreams/`,
`Dependencies/`, etc.) MUST be renamed as part of the migration
window opened by this clause. Every reference in the codebase MUST
be updated atomically with the rename: configuration files,
documentation, user manuals, diagrams, scripts, source-code
imports, links, governance files. **Reference drift after a
rename is a §11.4.29 violation** of equal severity to the rename
itself.

**Exceptions (common-sense scope).** The rule MUST NOT break
language-/technology-specific conventions:

- **Programming-language source roots** that mandate a specific
  case (Java / Kotlin package paths, Android resource folders,
  Apple framework directories, C# / Swift project layouts) keep
  their language-mandated names. The submodule's root directory
  follows our convention; the language-specific subtree inside
  follows its own.
- **Vendor / upstream submodules** (third-party orgs not in our
  owned set) keep their upstream-mandated names — we MUST NOT
  rename a third party's repo.
- **Build-tooling artefacts** (`node_modules/`, `__pycache__/`,
  `.git/`, `target/`, `build/`, `bin/`) keep their tool-mandated
  names.

When in doubt, the test "does renaming break the technology?"
trumps the snake_case rule. The §11.4.29 spirit is operator-
ergonomics + reference-discoverability, not pedantic uniformity at
the cost of technology compatibility.

**`Upstreams/` → `upstreams/` transition.** The constitution
submodule's installer (`install_upstreams.sh`) — exported on
operator paths via `.bashrc` / `.zshrc` — MUST support **both**
`Upstreams/` and `upstreams/` directory layouts during the
migration window, so existing checkouts keep working while
consuming projects rename at their own pace. The installer reads
whichever directory exists; if both exist the lowercase wins.
After every project under this Constitution has migrated, the
uppercase fallback MAY be retired by a deliberate amendment, but
the migration window remains open as long as ANY owned project
still ships the uppercase form.

**Project-Toolkit Upstreamable submodule synchronisation.** The
Upstreamable / Project-Toolkit machinery that propagates governance
into every consuming project MUST be fetched + pulled before any
rename batch, and MUST itself comply with this rule. Any
Upstreamable submodule lacking BOTH-directory support is a
release blocker for the rename program.

**Test coverage of renames.** Every batch of renames MUST ship
with: (i) a regression test that verifies every reference to the
renamed entity now resolves to the new name (no stale references
left); (ii) a full CONST-050(B) test-type matrix run against the
post-rename tree; (iii) anti-bluff (CONST-035) wire-evidence
captured during the runtime verification. A rename batch without
all three is a §11.4.29 violation.

**Cascade reach.** This rule applies recursively through every
owned-by-us submodule layer (per CONST-047) and applies equally
to the consuming project and its owned submodules (per CONST-051).
Per CONST-051(C) — dependencies at the parent root — the renamed
paths MUST be the only canonical location; old-name aliases
remain only as transitional symlinks if absolutely required, and
those symlinks MUST be removed on next-N-cycle review (project-
configurable, recommended ≥3 release cycles).

**Phased execution.** Because the rename touches every reference,
the execution MUST be planned as fine-grained phases per the
operator's explicit instruction: comprehensive brainstorming,
phase-divided plan, fine-grained tasks/subtasks with enormous
detail, every change covered by every applicable test type. The
phases run in parallel with mainstream work (§11.4.20 subagent
delegation is the natural fit for cross-submodule rename
sweeps).

**Classification:** universal (per §11.4.17). No escape hatch
beyond the explicit common-sense exceptions enumerated above.
Severity-equivalent to a §11.4 PASS-bluff at the
reference-integrity layer — a half-completed rename that leaves
broken references is worse than no rename at all because it
silently breaks consumers.

**Composition.** §11.4.29 composes with §1 (four-layer floor for
every rename batch), §1.1 (paired mutation: rename without
updating a reference → gate FAILs), §11.4.12 (regenerate auto-
generated docs on rename), §11.4.17 (universal — no project-
specific assumptions), §11.4.18 (script-doc-sync after renamed
script paths), §11.4.20 (subagent delegation for cross-cutting
rename sweeps), §11.4.25 (every renamed path appears in coverage
ledger), §11.4.26 (constitution-submodule rename pipeline), §11.4.27
(rename-touch test types apply across the matrix), §11.4.28 (owned
submodule renames cascade per CONST-047), CONST-047 (recursive
governance reach).

### §11.4.28 — Submodules-As-Equal-Codebase + Decoupling + Dependency-Layout Mandate (User mandate, 2026-05-15)

**Forensic anchor — verbatim user mandate (2026-05-15):**

> "All existing Submodules in the project that we are controlling and
> belong to some our organizations (vasic-digital, HelixDevelopment,
> red-elf, ATMOSphere1234321, Bear-Suite, BoatOS123456, Helix-Flow,
> Helix-Track, Server-Factory — we can ALWAYS check dynamically using
> GitHub and GitLab CLIs) are equal parts of the project's codebase!
> We MUST work on that code as much as we do with main project's
> codebase! All on equal basis! Equally important! We MUST take it
> into the account, analyze it, extend it, create missing tests, do
> full testing of it, fill the gaps (if any), fix any issues that we
> discover or they pop-up, write and extend the documentation, user
> guides, manulas, diagrams, graphs, SQL definitions, Website(s) and
> all other relevant materials! We MUST NEVER modify Submodules to
> bring into them any project specific context since they all MUST
> BE ALWAYS fully decoupled, project not-aware, fully reusable and
> modular (by any other project(s)), completely testable! All
> Submodule dependencies that are used by Submodule MUST BE acessed
> from the root of the project! We MUST NOT have nested Submodule
> dependencies but accessing each from proper location from the root
> of the project — directly from project's root project_name/
> submodule_name or some more proper structure project_name/
> submodules/submodule_name! This MUST BE heavily enforced and
> respected so no chaos and mess is created with various dependencies
> we may have!"

**Operative rule.** Three cooperating invariants govern every
consuming project's relationship with its owned-by-us submodules
(those whose upstream `origin` lives under one of the operator-
listed orgs — `vasic-digital`, `HelixDevelopment`, `red-elf`,
`ATMOSphere1234321`, `Bear-Suite`, `BoatOS123456`, `Helix-Flow`,
`Helix-Track`, `Server-Factory` — or any additional org the
operator subsequently authorises, the canonical list discoverable
at any time via `gh org list` / `glab` / the orgs' public APIs):

**(A) Equal-codebase invariant.** Every owned-by-us submodule is
an **equal part** of the consuming project's codebase. The
consuming project's engineering practice — analysis, extension,
test creation, gap-filling, bug-fix, documentation (user manual,
guides, diagrams, graphs, SQL definitions, website pages, any
other authoring surface) — applies to each owned submodule on
equal basis. A round of work that improves only the main project
while leaving an owned-submodule deficiency unaddressed is a
§11.4.28 violation, severity-equivalent to a §11.4 PASS-bluff at
the project-scope layer. Coverage ledgers (§11.4.25) MUST list
every owned submodule as an in-scope target. CONST-047 (recursive
cascade) governs the propagation of governance changes; §11.4.28
is the engineering-content counterpart that mandates the same
attention to non-governance content.

**(B) Decoupling / reusability invariant.** Owned submodules MUST
remain **fully decoupled** from any specific consuming project.
No project-specific context, hardcoded paths, hostnames, asset
names, naming schemes, or runtime assumptions may be introduced
into an owned submodule's source tree. Every owned submodule
MUST be:

- **Project-not-aware** — its code, tests, and docs make no
  reference to which parent project consumes it.
- **Fully reusable** — any future Helix-family or third-party
  project must be able to consume the submodule unmodified.
- **Modular** — its public surface is the only documented
  integration contract; internal layout may evolve without
  breaking consumers.
- **Completely testable** — every public surface has standalone
  tests (per the §11.4.27 100%-test-type matrix) that pass when
  the submodule is checked out as a standalone repo, without
  any parent-project rigging.

A commit that adds `project_name/...` strings, hostnames belonging
to a specific deployment, or other parent-project context to a
submodule's source tree is a §11.4.28 violation. The honest path
when a submodule needs information from the parent project is
configuration injection (env var, config file, constructor
parameter) — never a hardcoded reach into the parent's tree.

**(C) Dependency-layout invariant.** Every dependency that an
owned submodule itself consumes MUST be accessible **from the
root of the parent project** at one of two canonical paths:

```
<project_root>/<submodule_name>/          # flat layout
<project_root>/submodules/<submodule_name>/   # grouped layout
```

**Nested-submodule chains are FORBIDDEN.** A submodule MUST NOT
have its own `.gitmodules` entries that pull in further owned-
by-us repos (transitive own-org submodule recursion). Every
dependency required by submodule X MUST be added to the parent
project at the canonical path above; X reaches it via documented
import / SDK path / runtime resolver — never via its own nested
submodule pointer.

Rationale: nested own-org submodule chains cause version-drift
chaos (two consumers of `LLMsVerifier` end up at different SHAs
because each parent picked a different transitive path). The
flat / grouped layout makes the consuming project's submodule
graph a tree-of-depth-1, which any developer can audit at a
glance via `git submodule status` from the project root.

Third-party submodules (not under our orgs) are exempt — they
MAY appear at any depth as the upstream's structure dictates.
The invariant applies only to our owned set.

**Audit + enforcement.**

- Gate `CM-OWNED-SUBMODULE-EQUAL-ENGINEERING` (project-side):
  every release-gate sweep verifies each owned submodule has
  current test runs, coverage entries (§11.4.25), and
  documentation freshness on par with the main project. Stale
  submodules surface as §11.4.28 violations (Status:
  Operator-blocked or In progress per §11.4.21 — never
  "ignored").
- Gate `CM-OWNED-SUBMODULE-DECOUPLING` (submodule-side): every
  owned submodule's pre-commit hook (or equivalent) greps the
  staged diff for parent-project names / hostnames / asset
  names. Hits abort the commit until refactored to
  configuration injection.
- Gate `CM-OWNED-SUBMODULE-LAYOUT` (project-side): the parent
  project's pre-merge sweep verifies (i) every owned submodule
  sits at `<root>/<name>/` or `<root>/submodules/<name>/`,
  (ii) no owned submodule contains a nested `.gitmodules` entry
  whose upstream is in our org list, and (iii) every dependency
  declared by an owned submodule has a corresponding
  parent-project submodule entry at the canonical path.
- Paired mutations (§1.1) for all three gates: plant the
  forbidden pattern → gate FAILs; restore → gate PASSes.

**Workflow integration.** Honoring §11.4.28 in practice:

- Engineering rounds plan in submodule-aware tranches: "improve
  feature X in main; in same round, audit + improve the X-
  related surface in submodule Y; cascade governance per
  CONST-047 as usual".
- The §11.4.25 coverage ledger row format is extended with a
  `submodule` column so coverage rolls up across the whole
  owned set.
- Cross-submodule refactors that touch shared types or
  interfaces ship as a single change-window: parent + every
  affected owned submodule advanced in lockstep (§3 submodule-
  first-commit discipline + §2.1 multi-upstream push).

**Classification:** universal (per §11.4.17). No escape hatch.
Composes with: §1 (four-layer test floor reaches submodules too),
§1.1 (false-positive immunity), §3 (submodule changes propagate
through submodule commits first), §11.4.17 (universal-vs-project
classification), §11.4.20 (subagent delegation for the cross-
submodule audit sweep), §11.4.25 (full-automation coverage
ledger expanded to submodules), §11.4.26 (constitution-update
workflow's submodule-pointer-bump step), §11.4.27 (100%-test-
type coverage applies to every submodule's standalone surface),
CONST-047 (recursive governance cascade). A round of work
that violates §11.4.28 is a release blocker for the consuming
project, severity-equivalent to a §11.4 PASS-bluff at the
codebase-completeness layer.

### §11.4.27 — No-Fakes-Beyond-Unit-Tests + 100%-Test-Type-Coverage Mandate (User mandate, 2026-05-15)

**Forensic anchor — verbatim user mandate (2026-05-15):**

> "Mocks, stubs, placeholders, TODOs or FIXMEs are allowed to exist
> ONLY in Unit tests! All other test types MUST interract with real
> fully implemented System! No fakes, empty implementations or
> bluffing is allowed of any kind! All codebase of the project
> MUST BE 100% covered with every supported test type: unit tests,
> integration tests, e2e tests, full automation tests, security
> tests, ddos tests, scaling tests, chaos tests, stress tests,
> performance tests, benchmarking tests, ui tests, ux tests,
> Challenges (fully incorporating our Challenges Submodule
> — https://github.com/vasic-digital/Challenges). EVERYTHING MUST
> BE tested using HelixQA (fully incorporating HelixQA Submodule
> — https://github.com/HelixDevelopment/HelixQA). HelixQA MUST BE
> used with all possible written tests suites (test banks) for
> every applications, service, platform, etc and execution of the
> full HelixQA QA autonomous sessions! All required dependency
> Submodules MUST BE added into the project as well (fully
> recursive!!!)."

**Operative rule.** Two cooperating invariants:

**(A) No-fakes-beyond-unit-tests.** Mocks, stubs, fakes,
placeholders, in-memory facsimile implementations, `TODO`,
`FIXME`, "for now", "in production this would", or any
empty-implementation pattern are PERMITTED only inside unit-test
sources (e.g., `*_test.go` files invoked WITHOUT the integration
build tag; `tests/unit/`; equivalent per-language conventions).
Every other test type — integration, end-to-end, full automation,
security, DDoS, scaling, chaos, stress, performance, benchmarking,
UI, UX, Challenges, HelixQA suites — MUST exercise the **real,
fully implemented system** against real infrastructure (real
databases, real HTTP endpoints, real containers, real downstream
services, real captured devices). A non-unit test that imports
mocks, in-memory repositories, fabricated provider responses, or
placeholder structs is a §11.4.27 violation regardless of how
green its summary line looks — severity-equivalent to a §11.4
PASS-bluff. The same prohibition extends to **production code**:
no mock import path may be reachable from any code path that runs
in production binaries. Pre-build gate
`CM-NO-FAKES-BEYOND-UNIT-TESTS` scans the non-unit test trees and
production trees for the forbidden patterns; paired mutation
plants a fake → gate FAILs.

**(B) 100% test-type coverage with every supported type.** Every
project under this Constitution MUST cover its entire codebase
with **every supported test type** the project's domain warrants:

1. **Unit** — fast, isolated, mocks permitted per (A).
2. **Integration** — multi-component, no mocks, real backing
   services.
3. **End-to-end (E2E)** — full user-flow exercise on target
   topology.
4. **Full automation** — orchestrated suites exercising every
   feature × platform combination (§11.4.25 coverage ledger).
5. **Security** — authn/authz boundaries, secret-leak scans
   (§11.4.10), input-fuzzing, dependency-CVE scanning, threat-
   model verification.
6. **DDoS** — request-flood resilience at advertised throughput
   tier, with rate-limit + back-pressure assertions.
7. **Scaling** — horizontal + vertical scale behaviour under
   linear load growth, including replica add/remove transitions.
8. **Chaos** — controlled failure injection (network partition,
   process kill, disk full, clock skew) verifying graceful
   degradation paths.
9. **Stress** — sustained load above advertised tier, asserting
   bounded resource exhaustion + clean recovery.
10. **Performance** — latency / throughput / tail-latency
    invariants vs SLO baselines.
11. **Benchmarking** — micro + macro benchmark suites with
    historical p95-drift detection (§11.4.24 build-resource
    composition).
12. **UI** — visual-regression + DOM-state + interaction-flow
    coverage on every target platform's UI surface.
13. **UX** — flow-correctness + accessibility + i18n + visual-
    cue ordering (§11.4.23 composition).
14. **Challenges** — `vasic-digital/Challenges` submodule fully
    incorporated; per-feature Challenge scripts covering real
    user use-cases with captured runtime evidence.
15. **HelixQA** — `HelixDevelopment/HelixQA` submodule fully
    incorporated; ALL written test banks executed; full
    autonomous QA sessions run as part of release gates.

Per-type 100% coverage means: for every feature × platform cell
in the §11.4.25 coverage ledger, the cell carries a verified
PASS evidence pointer for **each supported test type the cell
warrants** (a CLI-only feature warrants unit + integration +
E2E + full-automation + security + chaos + stress + performance
+ Challenges + HelixQA; a UI feature additionally warrants UI +
UX; a network service additionally warrants DDoS + scaling +
benchmarking). Gaps are tracked per §11.4.15 with explicit
`UNCONFIRMED:` / `PENDING_FORENSICS:` / `OPERATOR-BLOCKED:` reasons.

**Required submodule incorporation (recursive).** Every project
consuming this Constitution MUST add the following as Git
submodules (or vendored equivalents authorised by the operator),
fully recursively per CONST-047 / §11.4.x cascade:

- `Challenges` — `git@github.com:vasic-digital/Challenges.git`
- `HelixQA` — `git@github.com:HelixDevelopment/HelixQA.git`
- Any additional functionality submodules under
  `vasic-digital/*` or `HelixDevelopment/*` orgs that the
  consuming project depends on (do not duplicate work the
  organisations already maintain).

Submodule pointers MUST be bumped to upstream HEAD in the SAME
commit as any dependent cascade work (§11.4.26 step 7). Pointer
drift = §11.4.27 violation.

**HelixQA autonomous sessions.** "Full HelixQA QA autonomous
sessions" means: HelixQA's orchestrator drives the consuming
project's running surface end-to-end, executing every test bank
the project has registered with it, capturing wire evidence per
check (status + body bytes + body-head + duration + screenshots
for UI), and producing a session report that is itself committed
via the §11.4.22 lightweight doc-sync wrapper. A green
autonomous-session report without captured wire evidence is a
§11.4 PASS-bluff at the QA-orchestration layer.

**Composition.** §11.4.27 composes with: §1 (four-layer floor),
§7.1 (positive-evidence-only), §11.4.1 (FAIL-bluffs forbidden),
§11.4.2 (recorded-evidence), §11.4.3 (per-topology dispatch),
§11.4.6 (no-guessing), §11.4.10 (credentials-handling — security
test category), §11.4.15 / §11.4.16 (status + type tracking),
§11.4.17 (universal-vs-project classification), §11.4.20
(subagent delegation for orchestrating the test-type matrix),
§11.4.22 (lightweight doc-sync for coverage ledgers and session
reports), §11.4.25 (full-automation-coverage — §11.4.27 is its
strict expansion into per-type-of-test territory). It does NOT
supersede them. CONST-047 (recursive submodule application)
governs the cascade reach.

**Classification:** universal (per §11.4.17). No escape hatch.
A project shipping with mocks reachable from non-unit-test paths
OR missing required test-type coverage is **not delivering a
stable product** — release blocker for every consuming project,
severity-equivalent to a §11.4 PASS-bluff at the release-gate
layer.

---

### §11.4.33 — Type-aware closure-status vocabulary (User mandate, 2026-05-15)

**Forensic anchor — direct user mandate (verbatim, 2026-05-15):**

> "make sure we use proper wording for the workable item completion
> status in Issues, Issues_Summary and Fixed docs: - Fixed -> into
> the proper wording depending on the workable item type (task,
> feature, and so on) - for example: Fixed, Implemented, Completed.
> Add this important detail in our root Constitution, CLAUDE.MD and
> AGENTS.MD so it is ALWAYS respected and followed!"

**Classification:** §11.4.17-classified **universal** — naming
discipline applies to every project that tracks work items by type.
Bug closures aren't "implemented", feature deliveries aren't "fixed",
and infrastructure refactors aren't either. Type-mismatched closure
vocabulary is a quiet but persistent semantic-drift bluff at the
documentation layer — it makes greppable releases lie about what
shipped.

**The mandate.** §11.4.15 defined the lifecycle Status closed-set
including the closure terminal value `Fixed (→ Fixed.md)`. §11.4.16
defined the Type closed-set `{Bug | Feature | Task}`. §11.4.33
binds the two: the closure terminal value MUST agree with the item
Type, drawn from this 3-element closed map:

| Item `**Type:**` | Closure `**Status:**` value |
|---|---|
| `Bug` | `Fixed (→ Fixed.md)` |
| `Feature` | `Implemented (→ Fixed.md)` |
| `Task` | `Completed (→ Fixed.md)` |

The `(→ Fixed.md)` suffix is preserved across all three so the
existing migration-discipline tooling (Issues.md → Fixed.md atomic
move per §11.4.19) continues to work without per-Type branching.
Generators (`generate_issues_summary.sh`, `generate_fixed_summary.sh`,
status-counter helpers, the §11.4.23 colorizer) MUST treat the three
terminal values as semantically equivalent (all map to "closed,
positive evidence captured") while preserving the literal in the
emitted document.

**No escape hatch.** Closing a `Feature` with `Fixed (→ Fixed.md)`
or a `Task` with `Implemented (→ Fixed.md)` is a §11.4.33 violation.
Pre-build gate (recommended, per consuming project) `CM-CLOSURE-
VOCAB-TYPE-AWARE` walks every Fixed.md heading + every Issues.md
heading whose `**Status:**` is one of the three terminal values, and
asserts the Status value matches the item's `**Type:**` per the
table. Paired mutation flips a Bug entry's status from
`Fixed (→ Fixed.md)` to `Implemented (→ Fixed.md)` → gate FAILs.

**Propagation.** Composes with §11.4.15 (item-status tracking),
§11.4.16 (item-type tracking), §11.4.19 (Fixed-document column
alignment), §11.4.23 (colorisation — the closed-state palette
applies regardless of which of the three terminal words is used).

---

### §11.4.34 — Reopened-source attribution mandate (User mandate, 2026-05-15)

**Forensic anchor — direct user mandate (verbatim, 2026-05-15):**

> "when we reopen some workable item (bug, task or feature) we MUST
> HAVE details on who did reopened this and why (- Reopened status
> needs: by who, AI or User + details in main Issues doc.). For
> example, reopened by AI or reopened by real User, why - test
> failed, manual testing detected problem, etc. Adapt our docs for
> this - Issues, Isssues_SUmmary and Fixed."

**Classification:** §11.4.17-classified **universal** — every
project that uses §11.4.15's `Reopened` lifecycle value benefits
from knowing the reopen source + cause. Without this, reopen-thrash
patterns (the same item bouncing between Fixed and Reopened across
cycles) cannot be diagnosed, and the §11.4.7 demotion-evidence rule
loses its forensic counterparty (you cannot evaluate whether a
reopen was operator-side observation or agent-side over-restoration
without provenance).

**The mandate.** Every Issues.md (or equivalent project tracker)
heading whose `**Status:**` value is `Reopened` MUST carry, within
8 non-blank lines of the heading, a `**Reopened-Details:**` line
that captures four sub-facts:

- **By:** `AI` or `User` (the source-of-truth observer who flipped
  the status). `AI` covers in-loop reopens (test failure, gate
  regression, captured-evidence retrospect). `User` covers operator-
  side observations (manual testing, end-user report, design
  reconsideration).
- **On:** ISO date (`YYYY-MM-DD`).
- **Reason:** one-line cause classification — chosen from a closed
  vocabulary `{ test-failed | manual-testing-detected |
  captured-evidence-contradicts | end-user-report |
  cycle-re-discovered | design-reconsidered }`. Other values are
  permitted with explicit `Reason: <free text>` annotation but the
  closed list MUST be tried first.
- **Evidence:** path to or short description of the captured
  artefact that justifies the reopen — log file, recording, gate
  failure ID, operator quote, etc. Reopens without evidence are
  §11.4.6 / §11.4.7 violations: the reopen IS a demotion-from-Fixed
  classification change, and demotion requires positive evidence
  captured under the conditions that re-exposed the defect.

The Issues_Summary.md (or equivalent) Status column MUST distinguish
the four `Reopened` sub-states by source so a sweep query for
"reopens by AI in the last 30 days" is mechanically possible.
Suggested column rendering: `Reopened (AI: test-failed)` vs
`Reopened (User: manual-testing)`.

**No escape hatch.** A `Reopened` entry without
`**Reopened-Details:**` is a §11.4.34 violation. Pre-build gate
(recommended, per consuming project) `CM-ITEM-REOPENED-DETAILS`
mirrors `CM-ITEM-OPERATOR-BLOCKED-DETAILS` (Phase 39.AT pattern):
walks every actionable heading, scans 8 non-blank lines for a
`**Status:** Reopened` line, then continues scanning for
`**Reopened-Details:**`. Missing details line emits WARN initially,
hardens to FAIL once backlog is fully populated.

**Propagation.** Composes with §11.4.6 (no-guessing — the Reason
must be drawn from the closed vocabulary or explicitly annotated;
no `likely/probably/maybe` causes), §11.4.7 (demotion-evidence —
reopen IS a demotion from Fixed), §11.4.15 (item-status tracking —
extends the `Reopened` value's discipline), §11.4.21 (Operator-
blocked discipline — same audit-line pattern with the same gate
shape).

---

### §11.4.35 — Canonical-root inheritance clarity (User mandate, 2026-05-15)

**Forensic anchor — direct user mandate (verbatim, 2026-05-15):**

> "Parent AGENTS.MD or CLAUDE.MD are located under constitution
> directory (Submodule) containing these parent (root) which files
> we are inheriting inside the project! Pay attention to this and
> make sure you ALWAYS follow this rule! Same applies to the root
> Constitution file!"
>
> "If needed (and we think it is needed it seems) add into the root
> Constitution, AGENTS.MD and CLAUDE.MD located in constitution
> directory (Submodule) which we are inheriting that the root
> (parent) Constitution, AGENTS.MD and CLAUDE.MD are not the ones
> in root of the project but inside the constitution directory
> (Submodule). We are inheriting it and if project specific rules
> have to be added or project specific constraints which are not
> universal and reusable, then they go into the Constitution,
> CLAUDE.MD and AGENTS.MD of the project directory itself!"

**Classification:** §11.4.17-classified **universal** — every
project that consumes this constitution as a Git submodule MUST
unambiguously distinguish the **canonical root** (the constitution
submodule's three files) from the **consumer extensions** (the
project's own three files).

**The defect this anchor closes.** Loose terminology — "parent
CLAUDE.md", "root CLAUDE.md", "main constitution" — used without a
file-path anchor causes a quiet but persistent confusion between
the inheriting copy and the source-of-truth. AI agents have already
been observed editing the consumer-side `CLAUDE.md` when the User's
intent was to extend the canonical layer (or vice-versa), causing
universal rules to leak into project-specific copies and
project-specific rules to be falsely promoted as universal. The
defect compounds: once a rule is misfiled, future propagation gates
treat the misfile as canonical and silently spread it.

**The mandate.** The three files in **this constitution submodule**
(`constitution/Constitution.md`, `constitution/CLAUDE.md`,
`constitution/AGENTS.md`) are the **canonical root** — also called
the **parent** files. They contain only universal rules per
§11.4.17 — rules that any project consuming this submodule benefits
from.

The three files in **the consuming project's repository root**
(`<project-root>/CLAUDE.md`, `<project-root>/AGENTS.md`, optionally
`<project-root>/Constitution.md` or equivalent) are the **consumer
extensions**. They MUST start with the inheritance pointer per the
existing constitution/CLAUDE.md "How inheritance works" section.
They contain only project-specific rules per §11.4.17 — rules that
reference particular hardware, vendor names, regulatory regions,
internal asset names, or project-private conventions.

**Operative invariants that follow:**

1. **When in doubt about which file to edit:** if the rule is reusable
   across any project, edit the constitution submodule's file. If the
   rule references project-private specifics (a hardware revision, a
   vendor SDK version, a regional constraint, a particular service),
   edit the consumer's file. Default to consumer-side when uncertain
   (per §11.4.17 — narrower scope is cheap to widen later, the
   reverse is expensive).

2. **Terminology anchor.** When prose in any file in this
   constitutional family references "the parent CLAUDE.md" or "the
   root Constitution," the referent is the constitution-submodule
   file at `constitution/<filename>`, never the consumer's file.
   When it references "the project CLAUDE.md" or "this project's
   AGENTS.md," the referent is the consumer-side file at
   `<project-root>/<filename>`. AI agents reading this constitution
   MUST resolve ambiguous pronouns ("the CLAUDE.md", "the
   constitution") via this rule.

3. **Universal rules added to the consumer side are misfiled.** Per
   §11.4.17 commit-time check, before adding a `MUST` to the consumer
   file, the author assesses whether it would benefit other projects
   that consume this constitution. If yes, lift it to the
   constitution submodule first.

4. **Project-specific rules added to the constitution submodule are
   misfiled.** Per §11.4.17, before adding a `MUST` to the
   constitution submodule, the author assesses whether it references
   project-private specifics. If yes, demote it to the consumer
   file (or genericise it to a universal form first).

5. **Propagation gates target both layers but their contents
   differ.** The existing `CM-COVENANT-114-N-PROPAGATION` gate
   family verifies that anchor TEXT for §11.4.N exists in EVERY
   `CLAUDE.md` and `AGENTS.md` across the project. The
   constitution-submodule files carry the **canonical** text; the
   consumer files carry **compact propagation pointers** that
   reference the canonical authority by file path. Both forms count
   as valid presence; the gate is satisfied when any form is found.

6. **`@constitution/CLAUDE.md` import (Claude-Code-style) and the
   pointer-block fallback (Aider/Codex/Gemini-style) are equivalent.**
   The consumer's CLAUDE.md MUST start with one of:
   - The native import: `@constitution/CLAUDE.md`
   - The portable pointer-block per the `## INHERITED FROM
     constitution/CLAUDE.md` heading defined in
     `constitution/CLAUDE.md` "How inheritance works".

7. **No silent demotion or silent promotion.** Moving a rule
   between layers MUST be a visible commit — `git mv` of a section
   if it's a clean clone, or an explicit "Lifted from <project> to
   constitution per §11.4.35" / "Demoted from constitution to
   <project> per §11.4.35" line in the commit message. AI agents
   MUST NOT silently re-author a §11.4.X anchor in the wrong layer
   and call it propagation.

**Pre-build gate (recommended, per consuming project):**

- **`CM-CANONICAL-ROOT-CLARITY`** — verifies (a) consumer's
  `CLAUDE.md` opens with the inheritance pointer (either `@import`
  or `## INHERITED FROM constitution/CLAUDE.md` heading), (b) the
  constitution submodule's three files are present at the expected
  path, (c) no `## INHERITED FROM` block in the constitution
  submodule's own files (those ARE the source-of-truth, not
  consumers).

**Propagation.** Composes with §11.4.17 (universal-vs-project
classification — §11.4.35 defines the file-layer split that
§11.4.17 classifies INTO), §11.4.18 (script documentation
discipline — same canonical-vs-consumer file-layer rule applies to
docs/scripts/). Reading order: this anchor first, then §11.4.17
for the classification rule.

**No escape hatch.** Misfiling a rule between layers IS a §11.4.35
violation regardless of intent. The fix is `git mv` + commit per
invariant 7, not "leave both copies in place to be safe" —
duplicates silently diverge over time.

### §11.4.36 — Mandatory install_upstreams on clone/add Mandate (User mandate, 2026-05-15)

**Forensic anchor — verbatim user mandate (2026-05-15):**

> "Every Submodule or Git repository we add or clone MUST BE
> upstreams installed using Upstreamable utility which MUST BE
> available through exported paths of the host system (in .bashrc
> or .zhrc) using install_upstreams command executed from the root
> of the cloned (added) repository - only if in it is Upstreams or
> upstreams directory present with bash script files (recipes) for
> all repository's upstreams!"

**Operative rule.** Every time an operator or agent adds or
clones a Git repository (`git clone`, `git submodule add`,
`incorporate-submodule` per §11.4.31, etc.) under any consuming
project of this Constitution, the post-clone procedure MUST be:

1. `cd` into the newly-cloned (or newly-added submodule's)
   working tree.
2. If the working tree contains an `upstreams/` directory (or
   legacy `Upstreams/` per the §11.4.29 transition) populated
   with one or more `*.sh` recipe files declaring upstream Git
   SSH URLs (the canonical declaration format defined by this
   constitution submodule's `Upstreams/*.sh` shape), the operator
   or agent MUST invoke `install_upstreams` from that directory.
3. `install_upstreams` is a host-system utility installed on
   the operator's `PATH` via `.bashrc` or `.zshrc` export.
   Implementation lives in the constitution submodule
   (`install_upstreams.sh`); operators alias / symlink it onto
   `PATH` once per host setup. The utility reads the recipe files,
   configures every declared upstream as a named git remote, and
   fans out `origin` push URLs across all declared upstreams.
4. If no `upstreams/` directory is present, no `install_upstreams`
   invocation is required.
5. If `upstreams/` is present but `install_upstreams` is not on
   `PATH`, the operator MUST install it (per the constitution
   submodule's setup docs) BEFORE making the clone usable.
6. Skipping step 2 when an `upstreams/` directory IS present is a
   §11.4.36 violation — the next push from that working tree will
   land on only one upstream, breaking §2.1 (Multi-upstream push
   is the norm).

**Pre-commit attention.** Before the first commit lands inside
the newly-cloned working tree, the operator MUST verify that
`install_upstreams` has been executed (when applicable). The
quickest check: `git remote -v | grep -c push` reports the
expected upstream count. If it reports `1` while
`upstreams/*.sh` declares more, abort the commit and run
`install_upstreams` first.

**Automation.** The constitution submodule's tooling (the future
`incorporate-submodule` per §11.4.31, the existing
`scripts/init-submodules.sh` patterns in consuming projects) MUST
auto-invoke `install_upstreams` as part of any clone / add
operation when the target tree has an `upstreams/` directory.
Operator-explicit manual invocation remains supported.

**Gate `CM-INSTALL-UPSTREAMS-ON-CLONE`.** Pre-merge gate inspects
every owned-by-us submodule pointer commit and verifies that:
(a) if `upstreams/` (or legacy `Upstreams/`) is present in the
submodule's tree, (b) the submodule's local checkout has at least
as many configured push URLs as the declared recipe count.
Paired mutation (§1.1): remove one upstream from local
`origin --push` config → gate FAILs.

**Composition.** §11.4.36 composes with §2 (single-entrypoint
commit/push wrapper), §2.1 (multi-upstream push is the norm — this
rule is its setup-time complement), §3 (submodule changes propagate
through submodule commits first — requires multi-upstream parity),
§9.2 / CONST-043 (no force-push — the multi-upstream wrap-up makes
unforced parity easy), §11.4.17 (universal — every consuming
project's clone procedure), §11.4.20 (subagent delegation when
batch-cloning), §11.4.28 / CONST-051 (owned-submodule discipline),
§11.4.29 / CONST-052 (`Upstreams/` → `upstreams/` transition is
exactly this rule's scope), §11.4.30 / CONST-053 (`.gitignore`
ignores `upstreams/` only if the project explicitly decides not to
track recipes, which is unusual — recipes ARE source of truth and
SHOULD be tracked), §11.4.31 / CONST-054 (submodule-dependency-
manifest works alongside upstreams recipes: helix-deps.yaml lists
WHAT to add at parent root, upstreams/ recipes list WHERE to push
the resulting clones).

**Classification:** universal (per §11.4.17). No escape hatch.
Severity-equivalent to §2.1 multi-upstream-push-violation at the
clone-time setup layer — without the post-clone install, the
working tree silently has a single-upstream blind spot.

---

### §11.4.37 — Fetch-before-edit mandate (User mandate, 2026-05-15)

**Forensic anchor — verbatim user mandate (2026-05-15):**

> "Make sure that feedback_fetch_before_edit memory rule is part of
> our constitution Submodule - the root Consitution, AGENTS.MD and
> CLAUDE.MD. Validate and verify that Proejct-Toolkit and all
> Submodules do inherit all of them! Follow the constitution
> Submodule documentation for details."

**Background.** In multi-agent / multi-upstream codebases — where
parallel Claude Code, Cursor, Aider, Codex, Gemini CLI, or human
operator sessions may operate on overlapping scope — the local
working tree's state can lag behind the canonical upstream state by
the time any given agent receives a task. Acting on stale local
state produces three failure modes documented in the originating
session (2026-05-15):

1. **Redundant work** — the agent re-does what a parallel session
   already finished, wasting tokens and operator review time. (In
   the originating incident, "Gitee removal" had already been
   committed upstream by a parallel agent 25 minutes earlier; the
   second agent's `git remote remove gitee` was a no-op echo of
   work already done.)
2. **False confidence** — the agent reports completion of work that
   was already done by someone else, with no mechanical signal that
   their commit duplicates upstream history.
3. **Divergent history** — if the agent commits a parallel
   "completion" of already-done work, the result is two siblings of
   the same change, doubling the conflict surface for the next push
   attempt to multi-upstream remotes (§2.1).

**The mandate.** The FIRST git-touching action of any session, on
any consuming project that participates in this constitution, MUST
be:

```bash
git fetch --all --prune
git log --oneline HEAD..@{u}              # parent
git submodule foreach --recursive 'git fetch --all --prune --quiet'
```

If `HEAD..@{u}` is non-empty, the agent MUST integrate (ff-merge,
rebase, or — if non-fast-forward — surface to operator per §11.4.4)
BEFORE issuing any local edit, scanner run, or test cycle. The
fetch step is non-negotiable even when the operator's directive is
phrased as "do X immediately" — the 30-second check prevents
hour-long conflict reconciliation later.

**Scope.** Applies to:

1. The consuming project root.
2. Every owned submodule (per §11.4.28) — recursive.
3. The constitution submodule itself (§11.4.26 step 1 makes this
   explicit for constitution-side edits; §11.4.37 generalises it
   to ANY edit on the consuming project, not only constitution
   edits).
4. Any dependency cloned via `incorporate-submodule` (§11.4.31) or
   `git submodule add` (§11.4.36).

**Anti-bluff invariant.** The fetch+log check MUST produce captured
evidence — the actual `HEAD..@{u}` output, even if empty. Skipping
the check on the basis of "I just fetched" or "nothing could have
changed in the last N minutes" is a §11.4.6 (no-guessing)
violation: the remote state is not knowable without a fetch.

**Composition.** Composes with §2.1 (multi-upstream push — without
the fetch, the agent can't know which upstream has the canonical
ref), §11.4.4 (test-interrupt-on-discovery — newly-fetched commits
that contradict the planned work are exactly the "freshly
discovered defect" that triggers cycle interruption), §11.4.6
(no-guessing — remote state requires fetch, not assumption),
§11.4.20 (subagent delegation — parallel subagents MUST coordinate
through fetched state, never assumed-local state), §11.4.26
(constitution update workflow — this rule generalises §11.4.26 step
1 to ALL edits, not only constitution-file edits), §11.4.32
(post-constitution-pull validation — fetch-before-edit happens
BEFORE the constitution-pull sweep §11.4.32 mandates).

**Gates.** Pre-build gate `CM-FETCH-BEFORE-EDIT-AUDIT` (when
implemented in the consuming project) audits the most-recent commit
range against the upstream HEAD at the commit's parent — if the
parent ref was not the upstream HEAD at the time the commit was
authored, FAIL. Paired mutation (§1.1): synthetic commit whose
parent is N commits behind the then-current upstream HEAD — gate
must FAIL.

**Classification:** universal (per §11.4.17). The rule has no
project-specific assumptions — it applies to any multi-upstream /
multi-agent codebase. No escape hatch. Severity-equivalent to a
§11.4 PASS-bluff at the planning layer — acting on stale local
state is the operational analog of asserting truth from unverified
premises.

### §11.4.38 — Installable-Asset Evidence Mandate (User mandate, 2026-05-17)

**Forensic anchor — verbatim operator report (2026-05-17):**

> "app does not have a launcher icon anymore — the latest published
> app tester build(s). how come app passed anti-bluff checks?"

For any user-distributable build artifact (package, bundle, installer,
or container image produced by the build pipeline and distributed to
end users), tests and challenges MUST open the artifact and verify
each user-visible asset is **present** and **non-degenerate**.

"User-visible asset" includes (non-exhaustive):

- Application icons for every density / resolution tier declared in
  the artifact metadata, including any platform-specific icon format
  (multi-resolution container, adaptive XML, symbol set, etc.) that
  the target OS uses when the minimum supported OS version requires it.
- Splash screens declared in the install metadata.
- Application name strings as declared in the install metadata.
- Any other asset whose absence causes the user to be unable to
  identify, launch, or interact with the installed application from
  the OS launcher / home screen / app drawer.

**A PASS without opening the artifact and verifying the asset chain
end-to-end is a §11.4 PASS-bluff**, regardless of whether source
files exist and tests otherwise pass. The specific failure mode this
rule targets is: source file exists → build pipeline packages it →
post-build checks pass at the source layer → artifact ACTUALLY
produced with the asset stripped or misconfigured, and no gate ever
opens the artifact to verify.

**Required evidence:** the anti-bluff challenge for a user-distributable
artifact MUST produce per-asset PASS/FAIL lines showing: (a) the asset
entry exists in the artifact package listing, (b) the asset is
non-empty / non-degenerate (size ≥ platform-defined minimum OR
format-validated), (c) where the OS's asset-resolution path involves
indirection (alias, XML reference chain, density-qualifier override),
the full chain is traced to the final rendered resource.

**Consuming-project implementation:** each consuming project ships one
challenge script per artifact type that opens the produced artifact and
verifies every declared user-visible asset. The challenge MUST run as
part of the project's standard QA gate (equivalent of `make qa-all`).

**Root cause of §11.4.38 introduction:** a consuming project shipped
multiple releases with the application icon absent on the target OS
because: (1) the icon XML used a resource type that the OS resolves
differently above a specific API level, (2) all pre-ship challenges
verified source files only, none opened the packaged artifact. This
is a pure §11.4 PASS-bluff — every test and challenge reported green
while the end user saw no icon.

Classification: universal (per §11.4.17). No escape hatch. Severity-
equivalent to a §11.4 PASS-bluff at the artifact-packaging layer.
Composes with §11.4.1–§11.4.5 (evidence requirements), §11.4.25
(full automation coverage), §11.4.27 (no fakes beyond unit tests —
source-layer checks of a distributable artifact are the distributable-
layer analog of unit-test-only coverage). See Constitution §11.4.38
for the full mandate.

### §11.4.39 — Per-Feature On-Device End-User Validation Mandate (iter-76, 2026-05-17)

Every user-facing feature in a consuming project MUST have at least one HelixQA scenario
that exercises the feature from cold-launch with **positive runtime evidence**:

- A screenshot or screen recording captured at a named checkpoint.
- At least one assertion of type `screenshot`, `accessibility_count`,
  `accessibility_node`, `ocr_text`, `pixel_histogram`, or `editor_state`.
- Evidence files written to a discoverable output directory so every PASS
  is cross-verifiable after the fact.

Scenarios MUST be RE-EXECUTED on every release candidate to catch cross-iteration
regression. A scenario authored but never re-run on subsequent iterations degrades
to a metadata-only gate — a §11.4 PASS-bluff at the regression layer.

**Authoring rules (consuming project sets project-specific paths):**

1. Scenarios are stored in a canonical bank directory designated by the consuming
   project (e.g. `<banks-root>/feature-coverage/`).
2. Each scenario YAML MUST include: `name`, `version`, `metadata`, `platforms`,
   `test_cases`, and at least one step with `evidence_required: true` and a
   specific `evidence_type`.
3. A **coverage matrix** document MUST exist listing feature × iteration × scenario.
   Matrix rules: (a) new iteration MUST add ≥ 1 scenario per new user-facing
   feature; (b) prior scenarios MUST NOT be deleted (mark as `status: retired` if
   feature is removed); (c) all non-retired scenarios MUST PASS for ship-ready.
4. A **static gate** (challenge script) MUST assert the scenario count ≥ N (where N
   is the number of user-facing features registered in the coverage matrix) and that
   each YAML contains a `evidence_type:` assertion.
5. **Portable host tooling**: evidence-validation scripts MUST use POSIX-portable
   file-size helpers (e.g. `wc -c < file`) instead of OS-specific commands
   (e.g. GNU `stat -c%s`) to avoid silent 0-byte reports on BSD/macOS hosts.
   A regression challenge MUST verify the portable helper on the actual host.

**iOS / platform-deferred pattern:** scenarios written platform-agnostically with
the target platform listed in a comment deferral (e.g. `# iOS: deferred — tracker #X`)
are valid; add the platform to the `platforms:` list when the automation toolchain
becomes available — no structural change to the scenario is needed.

Classification: universal (§11.4.17). Composes with §7.1, §11.4 (anti-bluff),
§11.4.25 (full automation coverage), §11.4.27 (no fakes), §11.4.38 (artifact
evidence). No escape hatch — a feature without an on-device scenario is NOT
covered per §11.4.25 invariant 2. See Constitution §11.4.39 for the full mandate.

### §11.4.40 — Full-suite retest before release tag mandate (User mandate, 2026-05-17)

**Forensic anchor — verbatim user mandate (2026-05-17):**

> "Please, do complete retests with all existing tests (multi-hours
> efforts) when all new workable items are done, fixed, polished and
> verified. Time is essential! We should already have this in our
> (root) Constitution, CLAUDE.MD and AGENTS.MD."

**Operative rule.** A release tag (any `vX.Y.Z` / `X.Y.Z-suffix`
identifier MUST NOT be created until a **COMPLETE retest with ALL
existing tests** has been executed on a clean baseline AFTER every
workable item in the batch is done, fixed, polished, and
individually verified. A "spot-check" retest that runs only the
tests directly touched by the batch is FORBIDDEN — it misses
interaction defects between the batch's fixes and previously-
stable code paths.

The complete retest comprises:

1. **Pre-build verification full sweep** — every gate in the
   project's pre-build script runs; 0 FAIL required.
2. **Post-build verification full sweep** — every gate in the
   project's post-build script runs against the freshly-assembled
   image; 0 FAIL required.
3. **On-device 4-phase cycle** (e.g. `test_all_fixes.sh` or
   project equivalent) on **EVERY owned device** (the full
   topology at that point in time). Each phase (Immediate Fresh
   Flash / After Reboot / After Factory Reset / After Final
   Reboot) MUST complete; no phase may be skipped. Phase summaries
   captured.
4. **Meta-test full mutation sweep** — every paired mutation in
   `meta_test_false_positive_proof.sh` (or project equivalent)
   executed; every gate proven non-bluff.
5. **Test bank full sweep** — if a Challenge-driven test bank
   exists, every Challenge in the bank covered by a full QA
   session (not a sub-set).
6. **Issues.md / Fixed.md state audit** — no item silently
   demoted; every Reopened item has §11.4.34 `Reopened-Details`;
   every closure has captured-evidence per §11.4.5; no
   `Status:` value outside the §11.4.15 closed-set.
7. **CONTINUATION.md sync check** — per §12.10, document
   reflects current state at the moment of tagging.

**Time is essential.** A complete retest is typically a **12–48
hour elapsed effort** depending on parallelism, device count,
and meta-test mutation count. This is NOT optional and NOT
abbreviated. Operators should plan release cadence with this
duration in mind, NOT skip the retest to ship faster. Skipping
the retest is the exact "tests passed but feature broken" failure
mode §11.4 specifically prohibits.

**Composition with §11.4.4.** Per-fix retest (`test_all_fixes.sh`
run after each individual fix lands) is STILL mandatory per
§11.4.4. §11.4.40 is the **additional final integrity check** that
runs after the BATCH is complete — catching interaction defects
that individual per-fix retests cannot see in isolation.

**Composition with §11.4.7.** The complete retest is the
authoritative captured-evidence baseline for any closure of
items present in the batch. If a §11.4.7-promoted item PASSed
its per-fix retest but FAILs the full-suite retest, the closure
MUST be reverted and the item moved back to `In progress` —
captured-evidence-contradicts under same-conditions per §11.4.7.

**Composition with §11.4.39.** Per-feature on-device end-user
validation runs as part of step 3 (on-device cycle) — every
feature's wrapper-test fires during the full-suite retest. The
two mandates are complementary: §11.4.39 covers individual feature
validation breadth; §11.4.40 covers release-time integration depth.

**Gate `CM-FULL-SUITE-RETEST-MANDATE`.** Pre-tag gate inspects
the release-candidate state and verifies that within the last
72 hours of the candidate commit, evidence exists of (a) full
pre-build + post-build run, (b) on-device 4-phase cycle on every
owned device, (c) meta-test full sweep, (d) Issues.md/Fixed.md
audit pass. Evidence captured in `docs/changelogs/<tag>.md`
per §11.4.4(c) requirements. Paired mutation (§1.1): strip
`Full-suite retest evidence` block from a changelog → gate FAILs.

**Classification:** universal (per §11.4.17) — every consuming
project's release procedure. No escape hatch — there is no
`--skip-full-retest` flag, no `--quick-release` mode. Operators
who feel time-pressured to skip the full retest should instead
delay the release until the retest completes; shipping unverified
code is worse than delayed shipping.

### §11.4.41 — Iteration-discipline mandate (User mandate, 2026-05-18)

**Forensic anchor — verbatim user mandate (2026-05-18):**

> "Are we clear about working iterations and sorting priorites for
> testing and fixing? We first fix top and middle critical priorites
> → We flash and test all of these → If nothing is broken and no new
> issues are reported by users or found we run full system testing
> (many hours for everything) → if anything is still broken or new
> issues are reported we get back to fixing → Cycle repeats. Make
> sure this is absolutely clear and mandatory foundation of our root
> (constitution Submodule) Constitution, AGENTS.MD and CLAUDE.MD!
> We MUST WORK in this manner until otherwise has been told."

**Operative rule.** Project work proceeds in priority-ordered
iteration cycles. Each cycle is a closed loop of five steps that
MUST run in order; advancing past any step before its acceptance
condition is met is a §11.4 bluff equivalent to skipping the step
entirely.

**The five-step cycle:**

1. **Priority-ordered fix selection.** Open the project's issue
   tracker, filter to items whose `**Status:**` is one of `Queued |
   In progress | Reopened | Operator-blocked` (per §11.4.15
   closed-set), sort by severity DESC then intra-group criticality
   DESC (per §11.4.12 sort order), select ONLY items classified
   `Top critical` or `Middle critical` for the current batch. `Low`
   items are explicitly DEFERRED until the critical batch is closed.
2. **Batch implementation.** Land source-side fixes for the selected
   batch per §11.4.9 (batch-source-fixes-before-rebuild) — every
   non-runtime-dependent fix lands BEFORE the next rebuild, every
   fix gets the §11.4.4 four-layer coverage (pre-build gate +
   post-build gate + on-device test + paired mutation).
3. **Smoke-test gate.** After flash, run the SMOKE bundle:
   (a) anti-bluff baseline (`meta_test_false_positive_proof.sh` for
   gates touched by this batch), (b) every `test_*.sh` whose name
   matches a fix in this batch, (c) the critical-path regression
   probe (boot + launcher + WiFi + audio + secondary-display
   routing core), (d) the §11.4.39 per-feature on-device validation
   for any feature touched. Estimated runtime: <30 minutes on the
   parallel device fleet. Smoke MUST emit zero FAIL and zero
   unclassified WARN.
4. **Full-system-test gate.** ONLY if (a) smoke is GREEN AND (b) no
   new operator/user report has surfaced during the batch's
   validation window, run the §11.4.40 complete retest (all 7 steps
   including 12–48 h on-device 4-phase cycle on every owned device).
   If smoke FAILed OR a new report arrived, the full-system test is
   FORBIDDEN; loop back to step 1 with the new evidence added to the
   priority queue.
5. **Release-readiness or loop.** If full-system test is GREEN AND
   no new report arrived during it, the batch is release-ready (the
   §11.4.40 tagging procedure may proceed pending operator
   authorization). Otherwise loop back to step 1.

**Priority taxonomy (binds existing severity convention).** `Top
critical` = severity `C` (Critical per Issues.md convention) AND
intra-group criticality `5`. `Middle critical` = severity `C` with
intra-group `1`–`4` OR severity `M` (Major) with any intra-group
score. `Low` = severity `L` per the existing `[C/M/L]` taxonomy
documented in §11.4.12. Severity `WARN` items are treated as `Low`
for iteration-discipline purposes.

**Cycle repeats.** The five-step loop continues, fed by the
priority queue, until the operator explicitly authorizes a release.
There is no upper bound on iteration count; "we've cycled enough"
is not a Constitution-recognised stopping condition. Time is
essential per §11.4.40 BUT the cycle MUST NOT be truncated to ship
faster — that is exactly the bluff §11.4 forbids.

**Composition.** §11.4.4 (per-fix retest inside step 2) +
§11.4.7 (closures require same-conditions positive evidence; step 4
is authoritative baseline) + §11.4.9 (source-side batching inside
step 2) + §11.4.34 (Reopened items attribute By: AI / User) +
§11.4.40 (the multi-hour full-suite retest IS step 4 — §11.4.41 is
the meta-loop conductor binding the instruments).

**Anti-bluff coupling.** Per §11.4.2 + §11.4.5, every smoke-test
and full-system-test PASS MUST carry positive captured evidence of
user-visible behaviour. Tests AND HelixQA Challenges bound equally —
a Challenge that scores PASS without applicable analysis is a §11.4
PASS-bluff.

**No escape hatch.** No `--skip-priority-batch`, `--skip-smoke`,
`--full-suite-only`, or `--release-without-loop` flag exists.
Subagents performing autonomous work default to the §11.4.41 path.
Operators who feel time-pressured to short-circuit the loop should
add capacity (more devices in parallel, more agent slots) rather
than skip steps. Shipping under-validated code is worse than delayed
shipping.

**Gate `CM-COVENANT-114-41-PROPAGATION`** mirrors
`CM-COVENANT-114-40-PROPAGATION` 1:1 — every CLAUDE.md / AGENTS.md
in the covenant file set carries the §11.4.41 anchor. Paired
mutation strips the anchor literal from one consumer file → gate
FAILs.

**Classification:** universal (per §11.4.17) — every consuming
project's iteration workflow.

### §11.4.42 — TDD-Fix-Discipline Mandate (User mandate, 2026-05-18)

**Forensic anchor — verbatim user mandate (2026-05-18):**

> "Make sure you do validate and verify every fix! Make sure you
> first do the fix on live device using ADB if that is possible,
> once fix is confirmed, make sure that it is fully applied into
> our codebase ... It is important to note that we shall start by
> creating test which confirms the issue (fails as expected), and
> ones the fix is produced it becomes positive - it does pass with
> success! No bluff policy is mandatory and nothing can be bluffed!
> Every step of this process MUST BE 100% bluff-free and
> bluff-proofed!"

**Operative rule.** Every fix MUST follow the 5-step TDD-fix
workflow:

1. **RED — Failing test FIRST.** Before any code change, author a
   test (or extend an existing one) that exercises the user-visible
   path of the reported defect and FAILs for that defect specifically.
   Per §11.4.1 the FAIL MUST be a real product defect (not a
   script-bug induced FAIL). Per §11.4.2 the FAIL run MUST produce
   captured evidence (logcat / dumpsys / screenrecord / dmesg /
   `/sys` snapshot / sink-side probe). The test identifier MUST
   cite the §-letter or Fix-# under repair. A RED step that
   "happens to pass because the underlying probe lifecycle isn't
   wired" is itself a §11.4 PASS-bluff.

2. **LIVE-ADB-PROBE — try the fix on the running device first
   (when feasible).** For mutable surfaces — `setprop persist.*`,
   `settings put`, `pm clear`, `am force-stop`, `am start`,
   `cmd wifi`, `cmd media_session`, ad-hoc `/sys` writes, boot-
   script edits pushed to `/vendor/bin/`, test-fixture replacement —
   the operator MUST attempt the fix on the running device via
   `adb shell` first. The fast adb-loop (~5 min per attempt)
   replaces the build-flash-test loop (~6 h per attempt) for
   confirmation of the hypothesis. The live-probe IS NOT the fix;
   it is the EXPERIMENT that proves the hypothesis is correct
   before the source-side investment.

   **Live-probe is INFEASIBLE (exception, must rebuild)** for:
   kernel changes, AOSP framework (frameworks/base/), hardware HAL
   changes, vendor/ partition contents, init.rc service
   definitions, sepolicy, ro.* build properties (immutable
   post-boot), AOSP-build-time XML / resource overlays,
   Android.bp/Android.mk changes, signed-system-app contents
   (LOCAL_CERTIFICATE := platform). Each exception MUST be cited
   in the commit message as `LIVE_PROBE_INFEASIBLE: <reason>`.

3. **GREEN — apply the fix to source code.** The source patch MUST
   achieve the same effect on the device as the live probe. Per
   §11.4.9 the source change is batched with other source-side
   fixes where appropriate. Build via the project's containerized
   build (§12.9). Flash via the project's flash script. The bytes
   on the assembled image MUST land where the post-build gate
   expects (per §11.4.4(b) four-layer requirement).

4. **VERIFY — re-run the RED test, must now PASS.** Per §11.4.7
   demotion-evidence: the PASS MUST come from the SAME conditions
   that initially FAILed (same device, same firmware NOW carrying
   the fix, same load profile, same cycle position). Per §11.4.5
   the PASS MUST carry positive captured evidence (presence +
   correctness — RMS amplitude, ffprobe channel count, frame count,
   OCR text, sink codec state, etc.). Per §11.4.2 video tests
   MUST cross-check via the recording-analyzer. Per §11.4.41 a
   reliability check at the iteration count (typically 10
   iterations) MUST PASS all iterations — a single intermittent
   FAIL keeps the item in `In progress` per §11.4.7.

5. **DOCUMENT — update every relevant doc in the SAME commit.**
   Per §11.4.4(c): `docs/Issues.md` → `docs/Fixed.md` migration
   with type-aware closure vocabulary per §11.4.33
   (Bug → `Fixed`, Feature → `Implemented`, Task → `Completed`);
   the project's CLAUDE.md Applied Fixes Reference row;
   per-version `docs/changelogs/<tag>.md` entry; affected
   user-facing guides under `docs/guides/`; HelixQA bank entry per
   §11.4.4(b); `docs/CONTINUATION.md` per §12.10; project memory
   file if non-obvious.

**Composition.** §11.4.42 is the workflow that ENACTS the existing
covenant. Composes with: §11.4.1 (the RED FAIL is a real defect),
§11.4.2 (captured evidence at both RED and VERIFY), §11.4.3
(topology dispatch in the RED test), §11.4.4 (four-layer coverage
at GREEN), §11.4.5 (quality analysis at VERIFY), §11.4.6 (no
guessing during the LIVE-PROBE hypothesis statement —
`UNCONFIRMED:` until probe proves it), §11.4.7 (demotion-evidence
at VERIFY — same conditions), §11.4.8 (research citation precedes
step 1), §11.4.9 (GREEN is batched), §11.4.40 (full-suite retest
is the release-tag-time additional check), §11.4.41 (10-iteration
reliability loop IS step 4's inner cycle).

**Gate `CM-COVENANT-114-42-PROPAGATION`.** Pre-build gate verifies
the §11.4.42 anchor is present in every CLAUDE.md / AGENTS.md
across the covenant file set. Paired mutation strips the anchor
literal from one consumer file → gate FAILs.

**Classification:** universal (per §11.4.17) — every consuming
project's fix workflow. **No escape hatch.** No `--skip-red-test`,
`--no-live-probe`, `--skip-verify`, `--skip-document` flag exists.
"I'll add the test after the fix" is the exact PASS-bluff pattern
§11.4 forbids because the test authored after the fix demonstrates
only that the test agrees with the fix, not that the test catches
the bug.

### §11.4.43 — Document Revision Header Mandate (User mandate, 2026-05-18)

**Forensic anchor — verbatim user mandate (2026-05-18):**

> "Add this change / improvement as background work in parallel
> with our mainstream work. All documents (Issues, Issues_Summary,
> Fixed, Continuation doc and all others MUST HAVE revision number!
> Revision number with information such as: last date and time when
> document was modified MUST GO at the top of the document below the
> main H1 title. Add all relevant information about the document as
> well. However, last date and time document has been modified and
> revision number are MANDATORY! Revision number shall be the whole
> number 1, 2, 3, etc. Document all this in our root (constitution
> Submodule) Constitution, AGENTS.MD and CLAUDE.MD as mandatory
> rule(s) and constraints we MUST HAVE! No bluff is allowed of any
> kind!"

**The mandate.** Every IN-scope tracked Markdown document MUST
carry a header block directly below the H1 title containing two
MANDATORY fields:

- `**Revision:** N` where N is a monotonic positive integer (1, 2,
  3, ...). Never decremented. Never reset on rewrite. A freshly-
  created IN-scope document starts at Revision 1.
- `**Last modified:** YYYY-MM-DDTHH:MM:SSZ` (ISO 8601 UTC).

Optional encouraged fields: `**Description:**`, `**Authority:**`,
`**Maintainer:**`, `**Scope:**`, `**Auto-generated-from:**`
(auto-generated docs only), `**Status:**` (plan docs only).

**Header format (canonical):**

```markdown
# Document Title

**Revision:** 47
**Last modified:** 2026-05-18T13:42:00Z
**Description:** Open / in-flight bug + work tracker
**Authority:** Constitution §11.4 covenant
**Maintainer:** Operator + AI loop per §11.4.41

<content...>
```

YAML front-matter and HTML-comment headers are FORBIDDEN — they
are invisible to humans scrolling the raw Markdown and break the
"all relevant information about the document" visibility clause.

**IN scope (revision header MANDATORY):** `docs/Issues.md`,
`docs/Issues_Summary.md`, `docs/Fixed.md`, `docs/Fixed_Summary.md`,
`docs/CONTINUATION.md`, `docs/guides/**/*.md`,
`docs/research/**/*.md`, `docs/scripts/**/*.md`,
`docs/changelogs/**/*.md`, `docs/superpowers/plans/**/*.md`,
`docs/hardware/**/*.md`, and every other tracked Markdown under
`docs/`.

**OUT scope (revision header NOT required):** `CLAUDE.md` /
`AGENTS.md` (every layer — already version-tracked via VERSION
file + inheritance pointer per §11.4.35; adding a per-file
revision would duplicate authority and obscure the canonical-root
contract); `README.md` / `CONTRIBUTING.md` / `LICENSE` / `NOTICE` /
`VERSION` / `OWNERS` (standard metadata); rendered HTML/PDF
artifacts (revision inherited from source Markdown); auto-
generated docs that already carry an embedded generation-time
stamp.

**Auto-bump tooling:**
- `scripts/doc_revision_bump.sh <file>` — manual entry point,
  idempotent (no-op if Last-modified within 5 s of `date -u`).
- `.git/hooks/pre-commit` — automatic entry point; walks staged
  IN-scope docs, calls the bump for each, re-stages.
- `scripts/testing/sync_issues_docs.sh` — composes the bump for
  Issues_Summary + Fixed_Summary after regeneration.
- `scripts/commit_docs.sh` — calls the bump before staging so
  operators who skipped the hook installation are still covered.

**Composition with §12.10.** CONTINUATION.md already carries
`Last updated:` per §12.10. §11.4.43 adds `**Revision:** N`
directly under H1 + reuses the existing `Last updated:` line as
the §11.4.43 `Last modified:` line. One source of truth, two
pointers — no duplication.

**Composition with §11.4.12.** Issues_Summary.md / Fixed_Summary.md
inherit the revision number of their source-of-truth Markdown at
generation time; they are NOT incremented independently.

**Composition with §11.4.23.** HTML colorizer preserves the
revision header in the colorized HTML — pandoc renders the bold
lines as styled `<p><strong>...</strong></p>` blocks which the
colorizer leaves alone (only Issues-table rows are mutated).

**Gates:** `CM-DOC-REVISION-HEADER-PRESENT` walks IN-scope docs
and asserts both mandatory fields appear within 15 lines below the
H1 title; `CM-COVENANT-114-43-PROPAGATION` asserts the anchor
literal is present in every covenant file. Paired mutations strip
the `**Revision:**` line OR the anchor literal → gates FAIL.

**Classification:** universal (per §11.4.17). **No escape hatch** —
no `--skip-revision-bump`, `--no-header`, `--allow-missing-revision`
flag exists. Operators who feel pressured to skip the bump should
land smaller commits, not bypass the discipline.

### §11.4.44 — Integration-Status-Doc Maintenance Mandate (User mandate, 2026-05-18)

**Forensic anchor — verbatim user mandate (2026-05-18):**

> "Make sure this Markdown document is regularly updated to reflect
> current up to date state of full integration ... Whole integrations
> MUST be regularly updated and retested! Keep the Markdown document
> ALWAYS up to date and ALWAYS exported into PDF and HTML! Make sure
> document is ALWAYS in sync! Add all this into our Constitution,
> AGENTS.MD and CLAUDE.MD."

**Generalisation note.** §11.4.44 is the generic form of §12.10
(CONTINUATION.md) applied to every domain integration. §12.10
binds the canonical handoff document specifically; §11.4.44
generalises the sync-and-evidence pattern to every non-trivial
integration (Dolby/Arvus, NanoKVM, Firebase, Widevine L1/L3, Play
Protect, Netflix, Cuttlefish, Chromecast, WiFi chip, ES8388 codec,
Sonos, AC-3, Google Stack, HiFi audio, TV apps, etc.). Without
this generalisation each new integration re-invents the same sync
wrapper, revision-header discipline, captured-evidence requirement,
and operator-blocked surface — duplicating effort and risking
drift.

**Operative rule (10 sub-points — every Status.md MUST hold ALL).**

Every integration-status document at
`docs/<domain>/<integration>/Status.md`:

1. MUST exist when a domain integration is non-trivial (more than
   one fix / test / gate landing for that integration).
2. MUST carry the §11.4.43 revision header directly below the H1
   title (Revision + Last modified + Description + Authority +
   Maintainer + Scope).
3. MUST be auto-synced (HTML + PDF) on every related-test-cycle
   completion AND every fix touching the integration. "Auto-synced"
   means the wrapper from sub-point 5 is invoked; manual
   regeneration is forbidden as the sole path because operators
   will forget.
4. MUST be auto-colorized per §11.4.23 — Status column cells
   colored by lifecycle state, Type cells colored by Type,
   operator-blocked rows visually distinct.
5. MUST have a sync wrapper invocable as
   `bash scripts/testing/sync_integration_status.sh <Status.md>`
   OR a per-integration thin shell that delegates to the generic
   wrapper. The thin shell exists so operators can type a short
   command per integration without remembering paths.
6. MUST live under `docs/<domain>/<integration>/` directory
   structure — consistent layout, discovery by glob remains O(1).
7. MUST include a captured-evidence-driven status table per
   §11.4.5 — every status claim cites the test log path, recording
   file path, or sink-probe report that backs it. Status claims
   without evidence are §11.4 PASS-bluffs.
8. MUST distinguish status values per §11.4.6 / §11.4.7: PASS /
   FAIL / SKIP / PENDING_FORENSICS / OPERATOR-BLOCKED — closed
   vocabulary, mechanically distinguishable, no implicit values.
9. MUST list operator-blocked items at the top of the document
   (just below the revision header) so an operator scanning the
   Status.md finds action items in O(1) — not buried 200 lines
   deep in a chronological evidence log.
10. MUST be referenced from `docs/CONTINUATION.md` §3 (Active
    work) when any item in the Status.md is non-terminal (Queued /
    In progress / Reopened / Operator-blocked) — composes with
    §12.10 so the canonical handoff document points at the
    integration-status doc rather than re-stating its contents.

**Gates:**

- `CM-COVENANT-114-44-PROPAGATION` — anchor text propagated to
  every CLAUDE.md / AGENTS.md across the covenant file set.
- `CM-AF-INTEGRATION-STATUS-DOCS` — discovers all
  `docs/**/Status.md` via glob, verifies each carries the §11.4.43
  header, has a sync wrapper, HTML+PDF exports are mtime-current
  vs the source, colorization applied (cell-status class present
  in the colorized HTML).

**Paired meta-test mutations** (§1.1 compliance):
propagation strip → propagation gate FAILs;
delete `**Revision:**` from a Status.md → status-docs gate FAILs;
touch Status.md without re-syncing → mtime mismatch FAILs;
inject `likely` outside `UNCONFIRMED:` block → existing
`CM-NO-GUESSING-MANDATE` catches it (composition catch).

**Composition.** §11.4.5 (captured evidence in every row),
§11.4.6 / §11.4.7 (status vocabulary closed-set), §11.4.12 (sync
wrapper pattern reused for HTML+PDF re-export), §11.4.13 (sink-side
captured evidence is a specific instance of the generic rule),
§11.4.15 (status values), §11.4.22 (commit_docs.sh wrapper),
§11.4.23 (colorizer extends to Status.md HTML), §11.4.43 (every
Status.md carries the revision header), §12.10 (CONTINUATION.md
references Status.md paths in §3).

**No escape hatch** — no `--skip-status-sync`,
`--no-revision-bump-on-status`, `--allow-stale-html` flag.
Operators who feel pressured to skip the sync should land smaller,
more frequent integration commits rather than batching status
updates into one giant push.

**Classification:** universal (per §11.4.17).

### §11.4.45 — Validate-recent-work-before-post-flash-tests mandate (User mandate, 2026-05-18)

**Forensic anchor — verbatim user mandate (2026-05-18):**

> "We see that on newly flashed devices we execute all post flash
> tests. Make sure we do execute them all after we validate and
> verify all recent work from the Issues and Continuation docs
> first! Once all new / latest work is fully validated and verified,
> no new issues found, nothing is discovered broken or faulty, then
> we run all post-flash tests! If validation and verification of
> recent work fails for any reason, and we must go back to fix
> anything that popped up we do not have to run post-flash tests!
> We MUST save time! All post-flash tests can be executed only
> after recent work on features and issues is fully validated and
> confirmed with complete anti-bluff policy enforced! Add this so
> it is absolutely clear into our root (constitution Submodule)
> Constitution, AGENTS.MD and CLAUDE.MD! Start following all these
> rules IMMIDIATELY! Iff required abort all post-flash testing if
> it is in progress!"

**Operative rule.** After every device flash, the orchestrator
MUST first run a recent-work validation pass before any full
post-flash suite (`test_all_fixes.sh` or project equivalent). The
validation pass enumerates recent work from three docs (Issues.md /
Fixed.md / CONTINUATION.md §3), maps each recent item to its
on-device test binding, runs ONLY those tests, classifies each
result per §11.4.6, and demands 100% green before the full suite
is permitted.

**Definition of "recent work" (closed-set):**

- `docs/Issues.md` actionable headings with `**Status:**` ∈
  `{In progress, Ready for testing, Reopened}` (per §11.4.15
  closed-set).
- `docs/Fixed.md` headings closed within `--max-age-days N`
  (default 7).
- `docs/CONTINUATION.md` §3 "Active work" sub-headings listed as
  IN PROGRESS or BLOCKED.

**Recent-work test binding.** Each recent item's on-device test is
discovered via §-letter or Fix # match against the project's
test_*.sh filenames OR an explicit `Test:` line in the item
heading. Items without an on-device test are §11.4.4 four-layer-
coverage violations (a fix without an on-device test is forbidden)
— flagged as VALIDATION-PASS-BLOCKED until the test lands.

**Authorization sequence (machine-enforced):**

1. `scripts/testing/recent_work_validate.sh --device <serial>`
   runs; writes `/data/local/tmp/.recent_work_validated` on the
   device IFF all targeted tests return PASS with captured
   evidence.
2. The full suite (`test_all_fixes.sh`) checks for the marker file
   at entry; absent or stale (older than the last flash boot
   epoch) → refuses to proceed with exit code 11.
3. Marker is invalidated automatically on reboot — the orchestrator
   stores the device boot epoch in the marker and re-validates.

**Anti-bluff during validation.** Each recent-work item that
landed a fix in this batch MUST have a paired §11.4.42 RED test
(captured before the fix) AND the same test now GREEN (captured
after the fix). A GREEN with no prior RED is itself the bluff
§11.4 forbids — the gate FAILs.

**Honest classification of validation FAILs.** Per §11.4.6:
PRODUCT defect (real regression — block full-suite, surface to
operator), TEST-INFRA defect (test-script bug — fix per §11.4.1 at
source layer, re-run), BLUFFY-THRESHOLD (e.g. SLO floor wrong —
re-baseline), or UNCONFIRMED (not reproducible in isolation — tag
per §11.4.7 PENDING_CYCLE_RETEST, NEVER silently demote).

**Composition.** §11.4.4 (STOP-on-discovery) + §11.4.6 (no-
guessing) + §11.4.7 (demotion-evidence) + §11.4.40 (full-suite
gate) + §11.4.41 (iteration discipline — smoke-test ≡ recent-work-
validation) + §11.4.42 (RED test for each recent-work item IS the
validation test) + §11.4.43 (revision header determines recency) +
§12.10 (CONTINUATION.md source-of-truth for §3 Active work).

**Gates:**

- `CM-COVENANT-114-45-PROPAGATION` — anchor literal present in
  every CLAUDE.md / AGENTS.md across the covenant file set.
- `CM-AF-RECENT-WORK-VALIDATION-GATE` — asserts
  `scripts/testing/recent_work_validate.sh` exists + executable +
  sources the anti-bluff library + the full-suite orchestrator
  contains the entry-gate check.
- `CM-AF-VALIDATION-ARTIFACT-FILE` — asserts the marker file path
  `/data/local/tmp/.recent_work_validated` is literal-identical
  across helper + orchestrator + propagation-block + this
  Constitution section.

Paired mutations strip the anchor / remove the entry-gate / flip
the marker path → respective gate FAILs.

**No escape hatch.** No `--skip-validation`, `--full-suite-always`,
`--ignore-recent-work` flag is permitted. The full-suite-without-
validation pattern is the precise "tests passed but feature
broken" failure mode §11.4 specifically prohibits. The 60–90 min
validation pass is ALWAYS faster than 4–6 h of full-suite chasing
a defect.

**Classification:** universal (per §11.4.17).

### §11.4.46 — Firebase Data Review Mandate (User mandate, 2026-05-18)

**Forensic anchor — verbatim user mandate (2026-05-18):**

> "We MUST regularly before every bigger working round check
> Firebase information gathered so far: Crashlytics (all fatals,
> non-fatals and ANRs), Analytics data and Performance data. For
> anything problematic depending on severity proper workable items
> (issues) MUST be created (Issues, Issues_Summary docs) with full
> references (links) to original data on Firebase. We MUST make
> sure we do not create for same issues multiple entries, so we
> MUST distinguish between same issue manifested in different forms
> (stacktraces)! Everything MUST BE comprehensive and in-depth
> level of details so any changes we do (or fixes) do solve the
> original root problems!"

**The mandate.** Before every "bigger working round" (pre-build,
pre-flash, pre-tag, daily, post-deployment burn-in) the operator/
loop MUST execute the Firebase review pass via
`scripts/firebase/review_round.sh`. The pass queries Crashlytics
(fatals + non-fatals + ANRs) + Analytics + Performance, classifies
each finding by the §11.4.46 severity table, dedup-maps to existing
Issues.md entries via the three-tier algorithm, and drafts new
Issue entries for unrecognised findings. Skipping the pass is a
§11.4 PASS-bluff: Firebase IS the captured evidence from real
end-user devices; ignoring it is the precise "tests pass, feature
broken in the wild" failure mode §11.4 prohibits.

**Five mandatory elements** (ALL must hold):

1. **Trigger cadence (5 trigger types).** Pre-build (blocking,
   <24 h freshness), pre-flash (blocking, <24 h), pre-tag
   (blocking, <6 h), daily 09:00 UTC default (non-blocking
   sweep), post-deployment burn-in T+24 h (non-blocking).
2. **Three-source query.** Crashlytics + Analytics + Performance
   — ALL three. Skipping one source is a §11.4 PASS-bluff (Firebase
   reports a regression on the skipped axis and we never see it).
3. **Issues.md output.** Every "problematic" finding MUST map to
   either (a) a new Issues.md entry, OR (b) a recognised existing
   entry via the dedup algorithm. Both paths produce a full
   Firebase Console URL in the entry's metadata so any future
   agent can re-fetch the raw data without rebuilding context.
4. **Three-tier deduplication.** Tier 1 (exact Firebase Issue-ID
   match) → Tier 2 (stacktrace-similarity cluster hash: top-3
   non-generic frames normalised + crash class → SHA-256 first 8
   hex chars) → Tier 3 (monthly operator merge review). Multiple
   Issues.md entries pointing at the same underlying root cause is
   a §11.4 violation (operator chases ghosts; root cause stays
   unfixed).
5. **Comprehensive root-cause analysis.** Every Firebase-sourced
   Issue carries the §11.4.4(a) systematic-debugging output —
   Phase 1 evidence, Phase 2 pattern, Phase 3 root-cause hypothesis
   (UNCONFIRMED until §11.4.42 RED test reproduces), Phase 4 fix
   direction. Comment-only entries ("crash in App X") are
   PASS-bluff stubs and FAIL the Issue-xref gate.

**Severity classification:** Crashlytics FATAL impactedUsers > 10
last 7d → Critical; 1–10 → Major; 0 but historic → Low. NON-FATAL
> 100/day → Major; 10–100 → Low; < 10 → Informational. ANR
> 1% sessions → Major; 0.1–1% → Low. Performance KPI regression
> 20% → Major; 10–20% → Low. Analytics funnel-drop > 50% → Major;
25–50% → Low; feature_used regression > 75% → Major. Composes
with §11.4.16 Type assignment.

**Gates:**

- `CM-COVENANT-114-46-PROPAGATION` — anchor present across every
  CLAUDE.md / AGENTS.md in the covenant file set.
- `CM-AF-FIREBASE-REVIEW-CADENCE` — `scripts/firebase/review_round.sh`
  exists, executable, contains the 7-stage pipeline literals +
  dedup algorithm + severity table.
- `CM-AF-FIREBASE-ISSUE-XREF` — every Issues.md entry whose
  `**Source:**` is `Firebase Crashlytics` / `Firebase Analytics` /
  `Firebase Performance` carries `**Firebase Issue IDs:**` +
  `**Firebase URL:**` + (`**Stacktrace Cluster Hash:**` for
  Crashlytics OR `**KPI:**` for Performance OR `**Funnel:**` for
  Analytics).

Paired mutations strip the anchor / rename the review_round
function / remove the Firebase-URL field from the template →
respective gate FAILs.

**Composition.** §11.4.4 (STOP-on-discovery), §11.4.4(a)
(systematic-debugging), §11.4.6 (no-guessing — Firebase data IS
captured evidence), §11.4.7 (demotion-evidence — a previously-
Fixed Issue resurfacing in Firebase IS positive captured evidence
the fix didn't hold; reopen attribution = "AI: captured-evidence-
contradicts" per §11.4.34), §11.4.10 (credentials — never log the
bearer token), §11.4.12 (Issues_Summary sync), §11.4.14 (cleanup
of `/tmp/firebase_review_*` work-dirs), §11.4.15 (Status: Queued),
§11.4.16 (Type per severity), §11.4.34 (Reopened-Details on
Firebase-resurface), §11.4.41 (implicit step 2 inclusion),
§11.4.42 (RED test per stacktrace before fix lands), §11.4.43
(revision header on every Firebase-sourced Issue), §11.4.44
(Firebase Status.md at `docs/firebase/status/Status.md`), §11.4.45
(validation pass consults latest Firebase delta).

**No escape hatch.** No `--skip-firebase-review`, `--no-issue-from-
firebase`, `--firebase-review-not-applicable` flag is permitted.
The operator MAY filter by minimum severity (`--severity-min
major`) to reduce noise but the pass itself MUST execute.

**Classification:** universal (per §11.4.17) — every consuming
project that ships to real end-user devices benefits from the same
review cadence and the same dedup algorithm.

### §11.4.47 — UI-Driven Video Testing Mandate (User mandate, 2026-05-18)

**Forensic anchor — verbatim user mandate (2026-05-18):**

> "We MUST make sure that all video playback testing with 2nd display
> is performed by fully automatically using the application's UI / UX,
> with full navigation, choice of video and clicks to real UI buttons
> to play or switch / stop videos being played! Maybe direct execution
> of Intents or Broadcasts does not have reported issues! We MUST test
> ALL WAYS users or Systems may / could play some video contents or
> streams! For all applications, all video and audio stream types!
> All supported codecs! EVERYTHING verified with 2nd display on D3
> device and every other device with connected 2nd display and Avrus
> for proper codec(s) used in its Web Interface / Dashboard! Write as
> much as possible new tests for all supported test types!"

**Why the existing video-test set is insufficient.** The legacy
`test_video_routing.sh` (v33), `test_video_secondary_display.sh`,
`test_video_playback_automation.sh` (v1) plus the 53 per_app_video
wrappers all dispatch playback via `am start -a android.intent.action
.VIEW` or via MediaSession `cmd media_session play` — surfaces that
skip the app's own content-selection UI, player-surface allocation,
MediaSession lifecycle (start/pause/stop), and back-button cleanup.
A defect like §CL routing-race or §CM frozen-frame mid-back-press
cannot reproduce via Intent dispatch because Intent dispatch
re-launches the app cold each time and `am force-stop` is a clean
cleanup path that masks the leak.

**Operative rule.** Every video-playback test that asserts
secondary-display routing MUST traverse the user-equivalent UI
path. Mandatory 5-surface coverage per video app:

1. **Surface A — Launch via launcher icon.** `am start -n
   <launcher-pkg>/<launcher-activity>` then `uiautomator dump`
   → locate app icon tile → `input tap X Y`. NOT `am start
   <video-pkg>/<MainActivity>` (skips launcher).
2. **Surface B — Navigate to content list.** Per-app driver
   script knows the app's home-tab → content-tab swipe / tap
   sequence. Asserts at least one content tile is visible via
   `uiautomator dump` content-desc / text match.
3. **Surface C — Select + play.** Tap a specific content tile
   (driver records the picked tile's content-desc as captured
   evidence). Wait for player surface visible.
4. **Surface D — In-app control interaction.** Pause via in-app
   pause button (not `input keyevent KEYCODE_MEDIA_PAUSE`),
   resume via in-app play button, in-app rapid switch to a
   second video (covers §CL).
5. **Surface E — Stop via back button.** `input keyevent
   KEYCODE_BACK` to exit player. Assert §11.4.14 cleanup:
   VOM `activeDecoder == null`, secondary surface cleared,
   no orphan MediaSession.

App-coverage matrix: every video-capable app in PRODUCT_PACKAGES
MUST have a UI-driven driver script set (Layer 2 per Section 7
design) AND at least one scenario that uses it. Today: 15 apps
covered fully in the initial batch (VK Video, MPV, Lampa as
fully-implemented; remaining 12 as templated stubs per Section 8).
Expansion to all 53 video-app entries is queued as follow-up work
under §O Issues.md per-app matrix.

Stream-type matrix: progressive HTTP / HLS / DASH / RTMP / file-
local / DRM-protected. Per app, the driver script tags which
stream types its picked content exercises. Aggregator emits a
coverage matrix per cycle so gaps are visible.

Codec matrix: H.264 / H.265 / VP9 / AV1 / MPEG-2 / MP4V (video) +
AC-3 / E-AC-3 / TrueHD / DTS / DTS-HD / MLP / Opus / AAC (audio).
Per scenario, the codec assertion is made via `dumpsys media
.metrics` (decoder name in event log) AND via Arvus codec-state
probe (audio side) per §11.4.13.

**Secondary-display verification.** On any device with HDMI-A-1
attached (detected via `dumpsys display | grep "Display 2"`):
- Captured-evidence: dual_display_record.sh ON for both displays
  per §11.4.5
- Assertion: `ffprobe -count_frames` on secondary mp4 reports
  > N frames within 3 s of play-action timestamp
- Anti-assertion: `ffprobe -count_frames` on primary mp4 reports
  ONLY launcher/home pixels during playback window (no
  video-decoder output)
- VOM cross-check: `dumpsys video_output_manager` shows
  `activeDecoder != null` during playback and `== null` after
  stop within 3 s

When secondary absent (D2 default topology): SKIP per §11.4.3
with explicit reason "topology: no secondary display attached".
NEVER FAIL on missing topology.

**Arvus codec-state mandate.** For every test asserting an audio
codec (AC-3, E-AC-3, TrueHD, DTS, etc.) — composed with §11.4.13
+ §CG:
- During playback window, call `arvus_probe_codec_state` ≥ 3
  times at 1 s intervals (transients fade by sample 2-3)
- Call `arvus_screenshot_capture` per §CG to attach visual
  evidence of the dashboard
- Assert reported codec matches expected via
  `arvus_assert_codec_format <regex>`
- ARVUS_HOST unreachable (ABK4 not joined / sink off) → SKIP
  per §11.4.3, never FAIL

**Pre-build gates:**
- `CM-COVENANT-114-47-PROPAGATION` — asserts anchor literal
  present in every CLAUDE.md / AGENTS.md across parent + 10
  owned submodules + HelixQA dependencies (42-file scan).
- `CM-AF-UI-DRIVEN-VIDEO-COVERAGE` — asserts the directory
  `device/rockchip/rk3588/tests/ui_driven/` exists, contains
  `lib/ui_driver.sh` reference + scenarios/ subdir +
  per-app driver subdirs for at least the 3 reference apps
  (vk_video, mpv, lampa), and that `scripts/testing/
  run_ui_driven_video_suite.sh` is executable.
- Paired mutations: deleting `ui_driver.sh` → CM-AF-UI-DRIVEN-
  VIDEO-COVERAGE FAILs; stripping the anchor literal →
  CM-COVENANT-114-47-PROPAGATION FAILs.

**No escape hatch.** No `--use-intent-shortcut` /
`--skip-ui-traverse` / `--legacy-intent-mode` flag exists. The
discipline exists because Intent-based dispatch is exactly the
class of test that PASSes while users hit real defects (§11.4
forensic anchor). Operators who feel UI-driven tests are "too
slow" should land scenario-level parallelism (multi-device
fan-out) rather than bypass the discipline.

**Composition.**
- §11.4.3 — topology dispatch (secondary present vs absent)
- §11.4.5 — captured-evidence quality (every UI tap captured)
- §11.4.13 — Arvus codec-state mandate
- §11.4.14 — playback cleanup verified via UI back-button path
- §11.4.42 — RED-test-first discipline (initial UI tests RED
  against §CL/§CM)
- §11.4.43 — revision header on every plan/driver doc
- §CG — Arvus dashboard screenshot

**Classification:** universal (per §11.4.17). Applies to every
project that consumes the constitution submodule AND ships any
video-capable Android app.

### §11.4.48 — Dual-Approach Testing Mandate (User mandate, 2026-05-18)

**Forensic anchor — verbatim user mandate (2026-05-18):**

> "Kinopoisk playback of 5.1 audio supported movies MUST BE done via
> UI / UX full automation and via execution of Intents (or Broadcasts)
> directly both! We could have shared tests base and specialized part
> which will run / play the movie with properly chose audio track
> (5.1). Document everything up to the smallest details! Create as
> much as needed new tests for all supported test types and
> Challenges!"

**Composition with §11.4.47.** §11.4.47 mandated UI-driven traversal
for every video routing test, eliminating the Intent-only PASS-bluffs.
§11.4.48 REFINES rather than replaces: every feature test ships in
BOTH variants — UI-driven AND Intent-driven — over a shared assertion
base. Either alone is a §11.4 PASS-bluff for the OPPOSITE half of the
stack. UI catches app-side bugs (content selection, player surface
allocation, MediaSession lifecycle, in-app overlays, back-button
cleanup). Intent catches framework/system-server bugs (Intent extras
parsing, MediaCodec.configure hook MIME routing, IVideoOutputManager
bind timing, broadcast permission gating, headless cron automation
paths).

**Operative rule — 5 mandatory elements:**

1. **Both variants required.** Every feature test exercising a
   user-visible behaviour MUST ship both `<feature>_ui.sh`
   (uiautomator-based, §11.4.47 surfaces A–E) AND `test_<feature>_
   intent.sh` (`am start --es` / `am broadcast`-based). Either alone
   is forbidden.
2. **Shared assertion base.** Codec-state assertions, captured-
   evidence collection (screen-recording, ffprobe, RMS amplitude
   analysis), Arvus codec-state probe + dashboard screenshot, and
   §11.4.14 cleanup MUST be implemented in a single POSIX-sh library
   (`tests/lib/dual_approach_test_base.sh`) and reused by BOTH
   variants of every dual-approach test. Code duplication in the
   shared layer is forbidden.
3. **Specialised driver code.** UI variant uses §11.4.47 per-app
   driver scripts under `tests/ui_driven/<app>/`. Intent variant
   uses `am start --es content_id <id> --es audio_track_id <track>`
   / `am broadcast -a <action>` directly. Each variant's specialised
   layer is responsible ONLY for "how the playback gets started";
   everything downstream of "playback is now happening" routes
   through the shared base.
4. **Comprehensive documentation per test.** Every dual-approach
   test set ships with: (a) §11.4.43 revision header in BOTH variant
   scripts, (b) per-feature contract under `docs/dual_approach/
   <feature>.md` describing the captured-evidence pairing and
   operator-side verification, (c) Issues.md / Fixed.md entry
   cross-linking both variant paths.
5. **Kinopoisk 5.1 EAC3 is the canonical first implementation.** The
   shared base + Kinopoisk 5.1 UI variant + Kinopoisk 5.1 Intent
   variant land in the same batch as this mandate. Subsequent
   features (Netflix Dolby Atmos, MPV DTS-HD, Lampa+TorrServe HEVC,
   VLC FLAC) port to the same pattern. The §CN subagent's fix to
   the underlying decoder pipeline is the FIRST GREEN target of
   these tests; both variants are RED per §11.4.42 until §CN lands.

**Captured-evidence directory contract.** Both variants write to
mirror-structured directories `qa-results/dual_approach/<F>/<run-
ts>/{ui,intent}/`. Identical filenames; orchestrator diffs the two
`result.json` files. Status mismatch (UI=PASS but Intent=FAIL or
vice-versa) is itself a finding — it pinpoints which half of the
stack contains the bug.

**Pre-build gates:**
- `CM-COVENANT-114-48-PROPAGATION` — anchor literal in every
  CLAUDE.md / AGENTS.md across parent + 10 owned submodules +
  HelixQA dependencies (42-file scan).
- `CM-AF-DUAL-APPROACH-COVERAGE` — `tests/lib/dual_approach_test_
  base.sh` exists + sources anti_bluff / ui_driver / credentials +
  exports `dat_init` / `dat_start_capture` / `dat_assert_codec_
  state` / `dat_assert_video_frames` / `dat_assert_audio_channels` /
  `dat_arvus_dashboard_capture` / `dat_cleanup` / `dat_report_
  finding`.
- `CM-AF-KINOPOISK-5-1-DUAL-COVERAGE` — both
  `tests/ui_driven/kinopoisk/kinopoisk_5_1_play_movie_ui.sh` AND
  `tests/test_kinopoisk_5_1_play_movie_intent.sh` exist + both
  source the shared base + both reference EAC3 codec + both assert
  5.1 / 6-channel.
- Paired mutations (3): strip anchor → propagation gate FAILs;
  delete UI variant → coverage gate FAILs; delete Intent variant
  → coverage gate FAILs.

**No escape hatch.** No `--ui-only` / `--intent-only` / `--skip-
dual` flag exists. The discipline exists because either-alone is
the PASS-bluff pattern §11.4 specifically prohibits. Operators who
feel dual variants are "too slow" should land scenario-level
parallelism rather than bypass the discipline.

**Composition.**
- §11.4.3 — topology dispatch (Arvus reachable, secondary present)
- §11.4.5 — captured-evidence content-quality analysis
- §11.4.6 — UNCONFIRMED tagging for un-verified Kinopoisk element IDs
- §11.4.10 — credentials never echoed, per-device per-service loader
- §11.4.13 — Arvus codec-state mandate (out-of-band evidence)
- §11.4.14 — playback cleanup via EXIT trap in shared base
- §11.4.17 — universal classification
- §11.4.42 — RED-first TDD (both variants RED until §CN fix lands)
- §11.4.43 — revision header on every variant script + design doc
- §11.4.47 — UI-driven traversal (this MANDATE refines, not replaces)
- §CG — Arvus dashboard screenshot via Presenter receiver
- §CB — credentials loader

**Classification:** universal (per §11.4.17). Applies to every
project that consumes the constitution submodule AND ships any
Android app whose user-visible behaviour can be triggered through
both UI and Intent/Broadcast paths.

### §11.4.49 — Deterministic Consistency Mandate (User mandate, 2026-05-18)

**Forensic anchor — verbatim user mandate (2026-05-18):**

> "Our anti-bluff / bluff-proofed / proof-driven work MUST satisfy
> the following: not a single feature, System or application flow,
> use case, edge case or procedural action(s) MUST NOT partially
> work, or sometimes work and sometimes not! There is only one truth
> that MUST BE fulfilled - no matter how many times we repeat all
> these scenarios with variations in data, System state(s) and speed
> of execution, results MUST BE consistent and successful without
> exception! No false positives or bluffing of any kind is allowed!
> We MUST add as much full automation tests which will use real
> System and Applications UI and UX with all flows, use cases and
> edge cases as needed or as much as it is possible!"

**Why this anchor exists.** §11.4.7 already forbids the vocabulary
`intermittent` / `transient` / `flake` in closure narratives, but
that's a textual ban — operators could still let a test "PASS once,
FAIL once, PASS again" and report only the first PASS. §11.4.49
closes that gap MECHANICALLY by requiring every PASS to come from
N identical iterations rather than from a single observation.

**Operative rule — 5 mandatory elements:**

1. **N-iteration deterministic outcome.** Every test that PASSes
   MUST have been executed N times (default N=3, N=10 for cycle-
   validation suites) against the same firmware MD5 + same device
   + same topology and produced IDENTICAL PASS in every iteration.
   A test whose outcome diverges across iterations is auto-FAIL
   per this mandate — there is no "first PASSed therefore X was
   a flake" path. §11.4.7's expanded forbidden-vocabulary list is
   enforced mechanically here.

2. **Edge-case + flow + use-case coverage.** Every public API
   path (Activity / Service / Broadcast receiver / ContentProvider
   URI / IPC interface / JNI entry / sysprop write / sysfs node /
   init.rc trigger) MUST have ≥1 dedicated test that drives it.
   Untested paths surface in a feature-coverage-matrix audit and
   block release at the 99% threshold (ratchet sequence 70 → 85
   → 95 → 99 mirrors §11.4.18 the existing project-side
   docs-coverage ratchet).

3. **Reliability check helper.** Project anti-bluff helper library
   ships `ab_run_n_times <test_name> <N> <fn> [args...]`:
   - Loops N times, captures exit code + evidence-hash per iter
   - Asserts all N exit codes identical AND all N evidence-hashes
     identical
   - On any divergence: `ab_fail` with full N-iteration report
   - Per §11.4.7 forbidden vocabulary: NO operator-facing escape
     path converts a divergent N-iter run into PASS

4. **Feature-coverage-matrix audit.** Project ships
   `scripts/testing/feature_coverage_audit.sh`:
   - Walks source layers (every public API surface)
   - Walks test layers (test_*.sh references)
   - Emits coverage report at `qa-results/feature_coverage/
     <ISO-UTC>/coverage.tsv`
   - Pre-build gate enforces minimum threshold; threshold ratchets
     up each phase (70 → 85 → 95 → 99)

5. **Composes with every prior anti-bluff anchor.** §11.4.49 does
   NOT replace §11.4.42 / §11.4.47 / §11.4.48 — it adds the
   N-iter consistency dimension across all of them. RED-first TDD
   (§11.4.42) still applies: every new test starts RED and
   becomes GREEN after the fix lands. UI-driven (§11.4.47) and
   dual-approach (§11.4.48) still apply: every test ships in both
   variants AND each variant passes N iterations identically.

**Pre-build gates:**

- `CM-COVENANT-114-49-PROPAGATION` — anchor literal `§11.4.49`
  present in every CLAUDE.md / AGENTS.md across parent + 10 owned
  submodules + HelixQA dependencies (≥42-file scan; phase 1 uses
  5-canonical-file scan matching §11.4.48 propagation pattern).
- `CM-AF-RELIABILITY-CHECK-WIRED` — `ab_run_n_times` function
  literal present in `device/rockchip/rk3588/tests/lib/
  anti_bluff.sh` AND at least 3 on-device tests source-reference
  it. The 3-test floor ratchets upward each phase.
- `CM-AF-FEATURE-COVERAGE-MATRIX` — `scripts/testing/
  feature_coverage_audit.sh` exists + executable + has run within
  the last 7 days + most-recent coverage report meets the current
  threshold.

**Paired mutations (3):**

- Strip the `§11.4.49` anchor literal from `constitution/CLAUDE.md`
  via `sed -i 's|11\.4\.49|11.4.MUTATED|g'` → `CM-COVENANT-114-49-
  PROPAGATION` MUST FAIL.
- Rename `ab_run_n_times` to `ab_run_n_times_DISABLED` in
  `anti_bluff.sh` via targeted sed → `CM-AF-RELIABILITY-CHECK-
  WIRED` MUST FAIL.
- Move `scripts/testing/feature_coverage_audit.sh` aside via
  `mv` → `CM-AF-FEATURE-COVERAGE-MATRIX` MUST FAIL.

**No escape hatch.** No `--allow-flake`, `--first-pass-suffices`,
`--skip-n-iter`, `--skip-coverage-audit` flag exists. The
discipline exists because the user mandate is unambiguous:
"results MUST BE consistent and successful without exception."

**Composition.**
- §11.4.1 — FAIL-bluffs forbidden
- §11.4.2 — captured-evidence (every iteration captures its own)
- §11.4.5 — quality analysis (per-iteration content compared)
- §11.4.6 — no guessing (UNCONFIRMED required for any iteration-
  budget assumption)
- §11.4.7 — forbidden flake/intermittent vocabulary (enforced
  mechanically by this mandate)
- §11.4.42 — RED-first TDD (every new test starts RED, N-iter
  applies across the GREEN transition)
- §11.4.45 — validate-before-suite (N-iter applied at single-test
  scope first)
- §11.4.47 — UI-driven traversal (each UI traversal MUST be
  N-iter-consistent)
- §11.4.48 — dual-approach (both variants of every dual-approach
  test MUST pass N iterations identically)

**Classification:** universal (per §11.4.17). Applies to every
project that consumes the constitution submodule.

---

### §11.4.50 — Live-ADB-First Maximization Mandate (User mandate, 2026-05-18)

**Forensic anchor — verbatim user mandate (2026-05-18):**

> "Was it possible to max the fix and test it via ADB or it can be
> only done by making the fix and reflashing for validation and
> verification? If such option exists, we should always make the
> best of it! Making fix on live devices via ADB → Once done commit
> and push changes, rebuild System and reflash → Validate and
> verify everything (with the test we write as well). Make sure
> this idea(s) is (are) part of our root (constitution Submodule)
> Constitution, AGENTS.MD and CLAUDE.MD if they are not already!
> EVERY DETAIL IS IMPORTANT!!!! Not a single idea or idea's detail
> can be ignored, skipped, relativized or bluffed!"

§11.4.50 REFINES §11.4.42 step 2 ("LIVE-ADB-PROBE — try the fix on
the running device first") with mechanical enforcement: a per-file-
class decision matrix, a classifier helper, and a commit-message
footer literal.

**Operative rule (5 mandatory elements):**

1. **Classify every fix** by rebuild-requirement using the
   project's per-file-class decision matrix. No guessing
   (§11.4.6). Every file in the diff cites the matrix row that
   classified it.

2. **If LIVE_ADB_TESTABLE,** the operator MUST apply the fix to
   the running device via the appropriate `adb` channel first
   (`adb push` for scripts, `setprop persist.*` for runtime
   properties, `mount -o remount,rw /vendor` for boot scripts,
   `pm install -r` for APKs built locally via gradle). Run the
   §11.4.42 RED test against the live-probed device, capture
   positive-evidence PASS, THEN commit source-side + rebuild +
   reflash as belt-and-suspenders re-validation. Commit message
   footer MUST state `LIVE_ADB_VALIDATED: yes` with one-line
   description of the live-probe sequence.

3. **If REQUIRES_REBUILD,** the operator proceeds directly to
   source-side fix + rebuild + flash. Commit message footer MUST
   state `REQUIRES_REBUILD: <reason>` citing the matrix row that
   classified the file. Categories of REQUIRES_REBUILD: kernel,
   AOSP framework Java / AIDL, native C++ inside APEX, sepolicy,
   init.rc, `ro.*` build properties (immutable post-boot),
   `Android.bp` / `Android.mk` / `BoardConfig.mk`, XML resource
   overlays, codec XML inside APEX, ramdisk-bundled artifacts.

4. **If mixed batch,** commit footer states
   `LIVE_ADB_VALIDATED: partial` and enumerates per-file
   classification. Per §11.4.9 batching is preferred; live-probe
   the testable files first, then batch with the rebuild-required
   ones into a single rebuild.

5. **Helper script enforces classification mechanically.** The
   project provides `classify_fix_rebuild_requirement.sh` which
   walks `git diff --name-only`, looks up each file against the
   matrix, and emits the recommended commit-message footer. No
   operator-facing override flag converts an unclassified path
   to LIVE_ADB_TESTABLE by default — unmatched paths classify as
   `REQUIRES_REBUILD: unmatched-path` (safe default per §11.4.6).

**Per-file-class decision matrix (canonical):**

| File class | Rebuild required? | Reason |
|---|---|---|
| `*test_*.sh` / `tests/lib/*.sh` (on-device) | NO | adb push to /data/local/tmp/tests/ |
| Host-side test scripts | NO | host script — no device interaction |
| `atmosphere-*.sh` boot scripts | DEPENDS | adb push to /vendor/bin/ after remount |
| Markdown docs / Constitution / plans / Issues / Fixed / CONTINUATION | NO | host docs — no firmware impact |
| Forked-player Kotlin (Presenter, MPV, SmartTube, TorrServe, Lampa, VLC, etc.) | YES via gradle local build + `adb install -r` | APK re-link required but no full firmware rebuild |
| Framework Java (`frameworks/base/**/*.java`) | YES | system_server requires reboot at minimum |
| AIDL (`*.aidl`) | YES | stub generation requires recompile |
| Native C++ (`external/**/*.cpp`, `frameworks/native/**/*.cpp`) | YES | builds into APEX or system library |
| APEX libraries (`vendor/**/lib/**/*.so` inside APEX path) | YES | squashfs read-only by Mainline integrity |
| Kernel sources (`kernel-5.10/**`) | YES | requires kernel rebuild + boot.img |
| sepolicy (`*.te`) | YES | requires policy build |
| `init.rc` | YES | parsed at boot only |
| `ro.*` build properties | YES | immutable post-boot |
| `persist.*` runtime properties | NO | `setprop persist.*` mutable |
| XML resource overlays | YES | RRO recompile |
| `media_codecs_*.xml` | YES | APEX-bundled |
| `display_settings.xml` (userdata) | DEPENDS | adb push possible if SELinux permits |
| `Android.bp` / `Android.mk` / `device.mk` / `BoardConfig.mk` | YES | rebuilt-into-image artifacts |
| Test fixture binary assets | NO | adb push to /data/local/tmp/ |

Pre-build gates: `CM-COVENANT-114-50-PROPAGATION` (anchor across
canonical files) + `CM-AF-CLASSIFY-FIX-HELPER-EXISTS` (helper
present + sentinel literals) + `CM-AF-LIVE-ADB-FIRST-COMMIT-MARKER`
(advisory WARN that scans recent commits for the footer literal).
Three paired meta-test mutations.

**Composition.**
- §11.4.42 — TDD-fix workflow (§11.4.50 REFINES step 2 with the
  mechanical classifier).
- §11.4.9 — batch-source-fixes-before-rebuild (compose: live-ADB-
  test individually, then batch-commit).
- §11.4.6 — no guessing (each classification justified by matrix
  row; unmatched paths default to rebuild-required, never silent
  testable).
- §11.4.45 — validate-recent-work-before-post-flash (live-probe IS
  implicit pre-validation).
- §11.4.47 — UI-driven tests (live-probe CAN use uiautomator over
  adb shell).
- §11.4.48 — dual-approach (live-probe applies to both UI and
  Intent variants).
- §11.4.49 — deterministic consistency (live-probe runs N
  iterations on the live device before commit).

**No escape hatch** — no `--skip-classify`, `--assume-rebuild`,
`--no-footer-required` flag exists. The discipline exists because
the user mandate is unambiguous: "EVERY DETAIL IS IMPORTANT!!!!
Not a single idea or idea's detail can be ignored, skipped,
relativized or bluffed!"

**Classification:** universal (per §11.4.17). Applies to every
project that consumes the constitution submodule — the matrix
itself MAY be project-specific (each consumer adapts the
file-class list to its own source tree), but the mandate to
classify-before-commit + the LIVE_ADB_VALIDATED / REQUIRES_REBUILD
footer literals + the classify-helper-script + the three pre-build
gates are universal.

---

## §12. Host-session safety — directly OR indirectly signing the user out is FORBIDDEN

Every script, test, helper, and AI agent governed by this
Constitution MUST respect host-session safety. Non-compliance is a
release blocker.

### §12.1 Forbidden operations — directly OR indirectly

1. **Suspending the host**: `systemctl suspend`, `pm-suspend`,
   `loginctl suspend`, DBus `org.freedesktop.login1.Suspend`, GNOME
   idle-suspend, lid-close handler.
2. **Hibernating / hybrid-sleeping**: any `Hibernate` / `HybridSleep`
   / `SuspendThenHibernate` method.
3. **Logging out the user**: `loginctl terminate-session`,
   `pkill -u <user>`, `systemctl --user --kill`, anything that
   signals `user@<uid>.service`.
4. **Unbounded-memory operations** inside `user@<uid>.service`
   cgroup. Any single command expected to exceed ~4 GiB RSS MUST
   be wrapped in a bounded execution scope (e.g.
   `bounded_run` from a project helper library that wraps
   `systemd-run --user --scope -p MemoryMax=...`).
5. **Programmatic rfkill toggles, lid-switch handlers, or
   power-button handlers** — these cascade into idle-actions.
6. **Disabling systemd-logind, GDM, or session managers** "to make
   things faster" — even temporary stops leave the system unable
   to recover.

### §12.2 Required safeguards

Every script in this project that performs heavy work (build,
transcription, model inference, large compression, multi-GB git
operations) MUST:

1. Source the project's host-safety helper library at the top.
2. Call its pre-flight check and **abort if it fails**.
3. Wrap any subprocess expected to exceed ~4 GiB RSS in a bounded
   execution scope so the kernel OOM killer is contained to that
   scope and cannot escalate to user.slice.
4. Cap parallelism (`-j`) to fit available RAM (estimate
   per-job-peak-RSS and divide into the budget).

### §12.3 Container hygiene

Containers (Docker / Podman) the project owns or relies on MUST:

1. Declare an explicit memory limit (`mem_limit` / `--memory` /
   `MemoryMax`).
2. Set `OOMPolicy=stop` in their systemd unit to avoid retry loops.
3. Use exponential-backoff restart policies, never immediate retry.
4. Be clean-slate destroyed and rebuilt after any host crash or
   session loss so stale lock files don't keep producing failures.

### §12.6 Memory-Budget Ceiling — 60% MAXIMUM

**Forensic anchor — direct user mandate:**

> "First make sure that whatever we do through our procedures
> related to this project MUST NOT use more than 60% of total system
> memory! All processes MUST be able to function normally!"

**The mandate.** Project procedures MUST NOT use more than **60%
of total system RAM**. The remaining 40% is reserved for the
operator's other workloads so the host can keep serving them while
project work proceeds.

**The protections:**

1. `HOST_SAFETY_MAX_MEM_PCT` defaults to 60.
2. `HOST_SAFETY_BUDGET_GB` is computed at source-time from
   `MemTotal × MAX_PCT/100`, in GiB.
3. Bounded execution scopes clamp `MemoryMax` down to the budget
   if the caller asks for more.
4. The build script's parallelism is computed as
   `min(nproc, floor(budget_gb / per_job_peak_rss_gb))`.
5. Heavy work MUST be wrapped in a bounded execution scope so the
   kernel OOM-kills only the scope — `user@<uid>.service` stays
   alive.

**No escape hatch.** §12.6 has NO operator-facing override flag.
The cap exists for the operator's own protection; bypassing it is
the bluff the §11.4 covenant specifically prohibits.

### §12.10 Continuation document — sacred invariant

**Forensic anchor — direct user mandate:**

> "during any work we perfrom, during Phases implementation,
> debugging and fixing, during ANY effort we have the Continuation
> document MUST BE maintained and it MUST NOT BE out of sync with
> current work we are doing! If for any reson we stop our work, we
> MUST BE able to continue any time, with current work, exactly
> where we have left of and from any CLI agent or any LLM model we
> chose! Nothing can be broken or faulty in maintained Continuation
> document!"

**The mandate.** A single, canonical, machine-readable handoff
document — `docs/CONTINUATION.md` — must always reflect the live
state of the project. Any agent (human, Claude Code, Cursor, Aider,
Codex, Gemini CLI, any future LLM) must be able to resume work
**exactly where the previous session left off** by reading this
single file.

**Mandatory protections:**

1. **`docs/CONTINUATION.md` MUST exist** at the project root. Its
   absence is a release blocker.
2. **Every non-trivial state change** MUST update this document in
   the same commit as the work itself.
3. **Top-of-file timestamp** is updated on every edit. Stale
   timestamps trigger gate failure.
4. **Section §3 "Active work"** lists every IN PROGRESS / BLOCKED
   item with enough detail that any agent can resume without
   conversation context — concrete commands, file paths,
   monitor IDs.
5. **Section §0 "How to use this document"** contains the verbatim
   resumption prompt — a single block any operator can paste into
   any CLI agent.
6. **Document MUST be self-contained.** No hyperlinks to ephemeral
   external systems as the only source of truth.

**No escape hatch.** §12.10 has NO operator-facing override flag
for the existence requirement. The discipline exists for the
operator's own protection.

---

## Appendix A — Mutation testing — academic and industrial foundations

The anti-bluff / paired-mutation policy in §1.1 is rooted in the
**mutation testing** literature. References that the consuming
project SHOULD cite when explaining its meta-test harness:

- Jia, Y. & Harman, M. (2011). *An Analysis and Survey of the
  Development of Mutation Testing*. IEEE Transactions on Software
  Engineering, 37(5).
- DeMillo, R.A., Lipton, R.J., Sayward, F.G. (1978). *Hints on Test
  Data Selection: Help for the Practicing Programmer*. IEEE Computer.
- Open-source mutation testers worth studying:
  - **PIT** (Java) — https://pitest.org/
  - **Stryker** (JS / C# / Scala) — https://stryker-mutator.io/
  - **Cosmic Ray** (Python) — https://github.com/sixty-north/cosmic-ray
  - **mutmut** (Python) — https://mutmut.readthedocs.io/
  - **mull** (LLVM-IR) — https://mull.readthedocs.io/

The §1.1 paired-mutation policy is a **lightweight** variant of
mutation testing applied at the gate-assertion layer rather than at
the production-code layer. It does not need a mutation framework;
it needs ONE mutation per gate that proves the gate catches the
break. This is computationally cheap (O(gates), not O(production
code lines)) and produces a strong "bluff-immunity" guarantee.

---

## Appendix B — Recursive inheritance & path-independence

Projects that include this constitution submodule MUST tolerate
**arbitrary submodule depth**. Between the main project root and
any consuming submodule there may be N intermediate levels. To
locate this constitution submodule from any depth, every project
SHOULD provide a helper that walks up parents until it finds
`constitution/Constitution.md` (the file you are reading right
now) OR follows `git rev-parse --show-superproject-working-tree`
recursively. The constitution submodule ships
`find_constitution.sh` for exactly this purpose; nested submodules
can source it without knowing their own depth.

---

## Appendix C — Multi-upstream push

This constitution submodule is hosted on multiple Git providers,
and consuming projects often are too. The submodule ships an
`install_upstreams.sh` helper (or invokes the `install_upstreams`
system command from the parent toolkit) that reads `Upstreams/*.sh`
declarations and configures all remotes locally.

Every commit to the constitution submodule MUST be pushed to ALL
configured upstreams. Use a shell helper that iterates `git remote`
and pushes one by one, OR configure `origin` with multiple push
URLs (`git remote set-url --add --push origin <url>` per remote).

---
