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
