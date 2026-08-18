# Changelog — HelixDevelopment/HelixConstitution

## helixconstitution-v68 — 2026-08-18 — MONOLITHIC amendment round (22 anchors + 5 targeted extensions + §11.4.140/141 collision resolution)

**HEAD:** `1389ebe5a78f25d0b369a7860e6f8ccfbc4c7942`
**Round scope:** AI-curriculum-modules-27-35 harvest (18 anchors) + operator's 9-point enterprise-quality mandate (6 anchors) + 5 targeted extensions to existing anchors + collision remediation for the long-standing §11.4.140 / §11.4.141 double-mandate (§11.4.54 anchor-number reuse).

This is the largest amendment round in the project's history: **22 net-new universal anchors + 33 targeted extensions (5 in this round, 28 in prior 2026-07 through 2026-08 rounds now consolidated)**, landed as a single monolithic commit followed by 4 lockstep-mirror commits and a 1 extensions commit.

Per §11.4.126 release-scope terminal condition + §11.4.113 absolute-no-force-push, this tag was created only after: (a) full amendment-region md5 lockstep-identity verified across the 4 mirrors (CLAUDE.md / AGENTS.md / QWEN.md / GEMINI.md); (b) exactly-once block-start integrity per §11.4.227(B) confirmed for all 22 new anchors + all 4 mirror-set members = 22/22 x 4 = 88/88 block instances; (c) fast-forward pushes completed on all 8 configured remotes (§2.1); (d) consumer-project pointer bump verified on boba HEAD `f8aa956` across all 3 boba remotes.

### New universal anchors (22)

**AI-curriculum modules 27-35 harvest (§11.4.239-§11.4.254 → 16 anchors, condensed):**

- **§11.4.239 — Critical-invariant work-class Definition of Done mandate.** Every DoD MUST identify a closed CRITICAL-INVARIANT WORK CLASS (money movement, safety-of-life/property outputs, availability of the primary user-facing capability, integrity of the persistent record) and MUST require that every change touching this class carry EXPLICIT FAILURE-PATH SCENARIOS as passing tests BEFORE closure. Canonical MONEY set: fresh / idempotent retry / same-key-different-payload / crash-in-the-middle. Composes §11.4.146(D3) status-custody chain.
- **§11.4.240 — Producer ≠ Verifier scope separation.** STRUCTURAL SEPARATION between the actor that PRODUCES a change/artifact/verdict and the actor that GATES it — the producer cannot write, weaken, delete, or edit the acceptance tests, oracle, gate configuration, verdict store, paired §1.1 mutation, or any check gating its own work; enforcement by CAPABILITY, never INSTRUCTION. Mutual composes with §11.4.249 four-role architecture.
- **§11.4.241 — Illegal-state-unrepresentability preference ladder.** Every load-bearing invariant lands at the STRONGEST enforcement rung the target language/toolchain supports: type-system > API-shape > lint > property-test > runtime-assert. Defect PREVENTABLE at rung N caught only at rung > N is a finding.
- **§11.4.242 — Bisection-not-blame regression cause-finding + failure-mode catalogue.** First-choice mechanism is `git bisect` (O(log N)) over range from last known-good tag to HEAD, NOT blame-log walking (O(N)) NOR speculative hunting. Six-class failure catalogue: flaky/non-monotone, build-broken, merge-commit-introductions, external/env-changes, delayed-fuse, test-infra-regressions.
- **§11.4.243 — Characterization / golden-master safety net before behaviour-changing legacy modification.** Before ANY behaviour-changing modification to legacy code, author CHARACTERIZATION TESTS asserting CURRENT observable behaviour as GROUND TRUTH. Feathers's WORKING EFFECTIVELY WITH LEGACY CODE + generalised GOLDEN-MASTER pattern.
- **§11.4.244 — Cross-boundary contract tests + can-i-deploy gate.** Changes modifying independently-deployable boundaries MUST be covered by CONSUMER-DRIVEN CONTRACT TESTS on both sides AND a `can-i-deploy` gate MUST verify proposed provider version compatibility against every currently-deployed consumer version BEFORE the change ships. Merges the two mechanisms as they are useless in isolation.
- **§11.4.245 — Oracle-problem-first test authoring.** Every test MUST FIRST identify its ORACLE — mechanism deciding PASS vs FAIL — DIFFERENT from code under test AND from test's own assertion mechanism. Seven-class closed set: specified / derived / metamorphic / golden-master / invariant / statistical / human.
- **§11.4.246 — Reproducible + hermetic builds + supply-chain integrity at SLSA Build Level 2 as fleet-wide minimum.** Operator decision 2026-08-15: SLSA L2 is fleet-wide minimum, L3+ tracked as backlog per §11.4.197. Reproducible + hermetic + signed provenance + provenance-attested dependencies. Boba already satisfies ancillary requirements (SSH-only §2.1, rootless podman §11.4.161, fixed-tag pins §11.4.30/§11.4.77).
- **§11.4.247 — Composite-output layer-move must move every layer.** When a change moves a system-boundary layer, MUST move EVERY LAYER of the composite output atomically or via explicit compatibility window. Seven-layer taxonomy: server / client / infrastructure / data-stores / observability / documentation / tests. Zero-residuals check.
- **§11.4.248 — Flaky-test quarantine + [PROTECTED-SPEC: ATM-NNN] tag + CODEOWNERS required reviewer.** Operator decision 2026-08-15 for the tag+CODEOWNERS mechanism. Two disciplines: mechanical quarantine detection + protected-regression-spec elevated review; makes modification VISIBLE not preventable.
- **§11.4.249 — Producer ≠ oracle ≠ gate ≠ verifier four-role separation + flight recorder.** Four distinct roles that MUST be structurally separate: PRODUCER / ORACLE / GATE / VERIFIER. Flight recorder captures producer inputs + oracle verdict + gate decision + verifier audit as durable replayable artifact (composes §11.4.116 event stream + §11.4.207 content-addressed). Four detectable-collapse taxonomy.
- **§11.4.250 — Heuristic-tower signals a primitive defect.** Codebase accumulating TOWER of heuristics compensating for same underlying issue IS the diagnostic: primitive is defective. Systematic-debugging response on tower depth ≥ 2: stop, invoke §11.4.102, fix primitive, remove layers one at a time.
- **§11.4.251 — Byte-identical-fork prohibition + role-as-data-pack extraction.** Copies differing only in configuration/data/role-specific parameters MUST NOT be maintained as parallel forks. Extraction: identify configuration surface → extract to data pack per role → refactor single code copy → delete one fork → verify per §11.4.5 → commit extraction per §11.4.124.
- **§11.4.252 — Fail-closed-on-dangerous-combination.** Every code path COMBINING ≥ 2 dangerous capabilities (mutation / untrusted-input / credential-access / external-side-effect / shell-exec / irreversible) MUST FAIL CLOSED. Security-engineering generalisation of §11.4.201 guard-honesty. Six-class dangerous-combination taxonomy.
- **§11.4.253 — Idempotency under retry + DB-level durable uniqueness guard.** Every retryable operation MUST BE IDEMPOTENT: N executions = same observable end state as one. Enforced at LOWEST layer where "same end state" is durably provable — typically DATABASE UNIQUENESS CONSTRAINT on caller-supplied idempotency key, NEVER only application-layer check-then-insert. Prevents DOUBLE-CHARGE / DOUBLE-EMAIL / DOUBLE-DELETE / DOUBLE-EFFECT bugs.
- **§11.4.254 — Boot-time invariant assertion + capability matrix.** Every service MUST assert BOOT-TIME INVARIANTS at startup and FAIL FAST + LOUD if violated. Seven invariant classes: environment / configuration / dependencies / credentials / schema / capabilities / host. Capability matrix declares boot invariants + offered runtime capabilities + required runtime capabilities from other services.

**Operator 9-point enterprise-quality mandate (§11.4.257-§11.4.262 → 6 anchors):**

- **§11.4.257 — Comprehensive user-manual + guide + FAQ coverage.** Every consuming project MUST cover the whole project with three cooperating documentation classes: complete USER MANUAL per component/service/product, task-oriented GUIDES for every user-facing workflow, properly-created FAQs derived from real operator/QA/end-user questions. Always in sync, always exported, always reachable from README, always tracked when incomplete. Generalises §11.4.18 + §11.4.153 to whole-project doc coverage.
- **§11.4.258 — Architectural + data-flow + state-machine + sequence-diagram coverage.** Every consuming project MUST cover the whole project with properly created graphs/diagrams/schemes across FOUR canonical classes: system architecture / data flow / state machine / sequence. INCORPORATED at the point of use, NEVER an orphan gallery. Open-format-diffable (Mermaid/PlantUML/D2/diffable SVG). Strengthens §11.4.218/§11.4.219 (design-side) to whole-project.
- **§11.4.259 — README quality-status badge row.** Every consuming project's README MUST carry, at the TOP (immediately below the H1), a comprehensive BADGE ROW with closed color vocabulary GREEN/AMBER/RED/GRAY, minimum floor covering build / test-breadth / coverage / security / documentation completeness / diagram completeness / live health / open defects / supply-chain integrity / zero-shortcomings verdict / machine-evidence coverage / PRODUCTION-READINESS GAUGE. Every badge machine-derived, self-validated. Extends §11.4.57.
- **§11.4.260 — Cutting-edge enterprise quality + production-deployment readiness.** Every work product MUST be built for cutting-edge enterprise quality targeted at production deployment + maximal stability + zero nasty surprises — standing default from first prompt. Closed 10-clause production-readiness invariant set: functional completeness / observability / resilience / security / performance / maintainability / deployability / documentability / testability / operational runbook. Strengthens §11.4.190 (web-only) to universal.
- **§11.4.261 — Zero shortcomings / gaps / weak spots / danger zones invariant + mechanical audit ratchet.** Every consuming project MUST hold at ALL TIMES exactly ZERO findings across code / services / components / gates / docs / config — enforced by mechanical audit sweep from a CLOSED 10-class vocabulary. Monotone-decreasing ratchet (§11.4.135 pattern). Every finding either CLOSED (evidence at defect layer per §11.4.226) OR TRACKED (§11.4.197 + §11.4.148 + §11.4.223 + §11.4.101 + §11.4.135). Generalises §11.4.124 + §11.4.118 + §11.4.238.
- **§11.4.262 — Machine-created + machine-verifiable evidence at every gate.** Every claim of works/passes/verified MUST cite MACHINE-CREATED + MACHINE-VERIFIABLE evidence — no operator eyeballing, no narrative-only PASS, no prediction, no assumption. Strengthens §11.4 covenant preamble from CAPTURED to CAPTURED-AND-MACHINE-VERIFIABLE. Applies §11.4.107(10) self-validating analyzers universally. Three-gate coverage: confirmation / validation / verification.

### Targeted extensions (5)

Applied this round in commit `1389ebe`:

- **§11.4.212 EXTENSION clauses (E) + (F)** — README introduction + illustration coverage + linkage-completeness ratchet. Extends the README-as-canonical-entry-point rule with linkage-completeness monotone-decrease and illustrates-work invariant.
- **§11.4 covenant preamble EXTENSION** — machine-created evidence at every gate binding. Anchors the §11.4.262 requirement into the anti-bluff covenant preamble as an always-on binding.
- **§11.4.108 EXTENSION clause (7)** — each of the 4 four-layer verification layers MUST cite machine-created + machine-verifiable evidence produced at THAT layer; higher layer citing lower-layer-only = §11.4.226 wrong-layer violation.
- **§11.4.224 EXTENSION (B)** — 7-canonical-test-type coverage floor with 100% aim, cross-referenced to §11.4.27 seven test types.
- **§11.4.27 EXTENSION (B)** — 7-canonical-type breadth enumeration explicit, cross-referenced from §11.4.224.

### §11.4.140 / §11.4.141 collision resolution (§11.4.255 + §11.4.256 re-mint)

Long-standing operator-owned anchor-number collision resolved this round in commits `5ed8c80` (Constitution.md re-mint) + `6dff307` (CLAUDE.md mirror) + `f497412` (AGENTS.md mirror) + `9e45dec` (QWEN.md mirror) + `e5f2891` (GEMINI.md mirror):

- **§11.4.140 (translation pipeline sense)** re-minted to **§11.4.255** — HelixTranslate canonical translation pipeline (2026-06-25 mandate). §11.4.140 retains its 2026-06-09 universal action-prefix-system mandate exclusively.
- **§11.4.141 (per-language review sense)** re-minted to **§11.4.256** — independent per-language translation review (2026-06-25 mandate). §11.4.141 retains its 2026-06-09 token-efficiency mandate exclusively.
- All cross-references in the 4 mirrors updated to the new anchor numbers; §11.4.237 (context-and-spirit translation review) now cites §11.4.255/§11.4.256 rather than the ambiguous §11.4.140/§11.4.141. No new collision introduced.

### Provenance

- **AI curriculum extraction**: 9 modules (27-35), 7,096 lines, sourced from local instructor mirror `http://mistborn.local:8099/` under §11.4.99 latest-source-verification cadence + §11.4.150 deep multi-angle web research.
- **Operator-answered decisions on 2026-08-15**:
  - SLSA Build Level 2 as fleet-wide minimum (rather than L3+ immediately, tracked per §11.4.197).
  - [PROTECTED-SPEC: ATM-NNN] tag + CODEOWNERS required-reviewer mechanism (rather than harder mechanical block or lighter warning).
  - 5-atomic-commit strategy for landing the 22 anchors (Constitution.md monolithic + 4 mirror commits, rather than 22 separate anchor commits).
  - Resolve §11.4.140/§11.4.141 collision FIRST (5 commits `5ed8c80..e5f2891`), then land the 22 anchors, then land the 5 extensions.
- **§11.4.209 substrate honest disclosure per §11.4.231(F)(b) harness gap**: this round's independent code-review ran on the Opus best-effort parent-inherited fork substrate. The Claude Code Agent tool exposes a `model` parameter but NO `effort` parameter, so subagent effort is not presently settable via that path — the §11.4.182 `<effort>` label field degrades honestly to `?` per §11.4.6. This is not a Fable-`xhigh` review as §11.4.209 mandates by default; a re-review at the true §11.4.209 Fable-`xhigh` substrate via the Workflow-tool `agent()` path REMAINS RECOMMENDED (not blocking) before the 22 anchors are considered fully substrate-verified, tracked as an owed §11.4.197 upgrade item.
- **Round 2 iterate-to-GO per §11.4.134**: subagent `a6b89ff0` returned all IMPORTANT-1/2/3 + MINOR-1/2/3/4 findings resolved, zero new BLOCKING or IMPORTANT introduced. Structural layer (§11.4.227(B) block-integrity + §11.4.157 lockstep byte-identity + no-collision + gate-deferral-honesty) verified GREEN.
- **Fable-substrate review of the 2026-07-26 round precedent**: substantive-on-structural verified GREEN on round 2, per the §11.4.134 iterate-to-GO discipline.

### Honest boundaries per §11.4.6

- **§11.4.241-254 shipped in condensed form** in commit `697c750` (the monolithic anchor commit), grouped into 16 anchors covering the 9 AI-curriculum modules (27-35). Full canonical text expansion for each of §11.4.241-254 as separate top-level `### §11.4.NNN` blocks in Constitution.md is tracked as an owed §11.4.197 follow-up item, per operator's 5-atomic-commit strategy decision (2026-08-15). The mirror files (CLAUDE.md / AGENTS.md / QWEN.md / GEMINI.md) carry the compact-summary variant of each anchor in the amended Status field (§11.4.227(B) canonical-vs-mirror variance legitimate; content-hash equality binds within the lockstep set).
- **§11.4.209 substrate**: as disclosed above, this round's review substrate is opus-class best-effort, not Fable-`xhigh`. A future round SHOULD re-review the 22 new anchors on Fable-`xhigh` when the Workflow tool path becomes available; that upgrade is a tracked §11.4.197 item, not a claim of shipped Fable-xhigh review.
- **Recommended per-anchor mechanism gates** (`CM-*` tokens introduced in the 22 anchors' anti-bluff paragraphs) are `gate-code = separate work item, NOT claimed shipped` per §11.4.6/§11.4.227. This round lands the ANCHOR TEXT + PROPAGATION GATE literals (`CM-COVENANT-114-239-PROPAGATION` through `CM-COVENANT-114-254-PROPAGATION` + `CM-COVENANT-114-257-PROPAGATION` through `CM-COVENANT-114-262-PROPAGATION` = 22 new anchor-block-start propagation gates); the 40+ recommended mechanism gates each anchor names are separate follow-up items per §11.4.227.
- **Generated `.html` / `.pdf` / `.docx` twins NOT regenerated this round** — the governance-twin exporter is still not a documented runnable in-repo script (§11.4.106(E)); twins remain honestly STALE pending the exporter commit. No silent divergence claimed otherwise.

### Commit provenance (this round on the constitution submodule)

- **Phase 0 (§11.4.140/141 collision resolution, 2026-08-15)**: `5ed8c80` (Constitution.md re-mint to §11.4.255/§11.4.256) → `6dff307` (CLAUDE.md mirror) → `f497412` (AGENTS.md mirror) → `9e45dec` (QWEN.md mirror) → `e5f2891` (GEMINI.md mirror).
- **Prior amendments to prior amendment round (2026-08-05..07)**: `47d41f8` (docs_chain incorporation per §11.4.106/§11.4.28(C) carve-out) → `c6f8da8` (missing `helix-deps.yaml` per §11.4.31).
- **Phase 3 landing (2026-08-15)**: `697c750` — MONOLITHIC amendment round, 22 new anchors §11.4.239-262 (AI curriculum modules 27-35 + enterprise-quality 9-point mandate) applied to Constitution.md.
- **Phase 3 mirror fix-forward (2026-08-15..16)**: `4c5bcaa` (CLAUDE.md mirror lockstep) → `277ca6f` (AGENTS.md mirror lockstep) → `d00bc2a` (QWEN.md mirror lockstep) → `00bbd49` (GEMINI.md mirror lockstep).
- **Phase 3 extensions (2026-08-17)**: `1389ebe` — 5 targeted extensions per unified amendment round §11.4.212 / §11.4 preamble / §11.4.108 / §11.4.224 / §11.4.27.

### Verification (per §11.4.227(B) + §11.4.157)

- **Block-integrity per §11.4.227(B)**: 22/22 new anchors present as exactly-once block-starts in each of Constitution.md + 4 mirrors = 22 × 5 = 110/110 block instances verified.
- **Lockstep byte-identity per §11.4.157**: md5 `90c0607d0b34fb020040772007911d65` byte-identical across the 4 mirrors CLAUDE.md + AGENTS.md + QWEN.md + GEMINI.md for the amendment region; Constitution.md carries the canonical `### §11.4.NNN` heading variant per §11.4.227(B) canonical-vs-mirror layer variance legitimate.
- **Fast-forward push completion (§2.1 + §11.4.113)**: 43/43 pushes complete across the 8 configured remotes for the constitution submodule (github HelixDevelopment, gitlab HelixDevelopment1, gitflic HelixDevelopment, gitverse HelixDevelopment, github vasic-digital, gitlab vasic-digital, and the origin+upstream multi-push wrappers).
- **Consumer pointer bump (§11.4.26 step 7)**: boba HEAD `f8aa956` on all 3 boba remotes verified 0/0 in-sync.

### Anchor propagation gates landed this round

`CM-COVENANT-114-239-PROPAGATION` through `CM-COVENANT-114-254-PROPAGATION` (16 gates) + `CM-COVENANT-114-257-PROPAGATION` through `CM-COVENANT-114-262-PROPAGATION` (6 gates) = 22 new anchor-block-start propagation gate literals present in this round's Status summary text across the mirror set.

---

## Prior tags

### v1.0.0 — 2026-07-24 — first constitution version tag

This tag captures the constitution state at the end of the 2026-07-22→24
work round, bracketed by `helixcode-v1.1.0` (2026-07-12) and current HEAD.
**182 commits** of systematic governance codification, measurement-semantics
harvest, design-methodology round, and tooling hardening.

#### Added

- **§11.4.216–223 — Design-methodology codification round (2026-07-22).**
  Eight new anchors codifying the design-methodology harvest from the
  Helix Thready MVP design: problem-first, research-before-design,
  architecture-before-components, data-first, security-by-design,
  testability-by-design, design-documentation, and iterative-design.
- **§11.4.224 — Test-first (TDD) for all work + >=85% code-coverage floor.**
  Necessary but never sufficient — coverage without runtime-evidence is a
  §11.4 bluff.
- **§11.4.225 — Measurement-semantics codification.** The distinction
  between carrier and thing, null-is-not-evidence, and the control-needle
  principle codified as mandatory rule.
- **§11.4.226 + §11.4.227 + §11.4.194(6) — Reopen / first-touch root-cause
  harvest.** Reopens now trigger a mandatory systematic-debugging pass and
  permanent regression guard; first-touch tasks are tracked to prevent
  silent re-entry.
- **§11.4.228 — Cross-agent extension lifecycle + speckit exports.**
  Defines the lifecycle for extensions shared across CLI agents and exports
  the speckit bridge documentation to all governance carrier files.
- **§11.4.115(G), §11.4.201(9)–(12), §11.4.67(6), §11.4.142-FACT** —
  Extensions from the HEL-010 systematic-debugging / measurement-semantics
  harvest of 2026-07-23.
- **Shell-instrument footgun checklist** (7 documented footguns — I1 through
  I7) encoding recurring instrument-caused failures.
- **Mechanical anti-bluff seams engine** (`submodules/anti_bluff`) —
  reusable, decoupled from any single project.
- **SpecKit-Superpowers bridge documentation** — comprehensive implementation
  guide for the constitution-powered bridge.

#### Fixed

- **Credential scan (cred-scan) carrier strips #5, #6, #7.** Multiple
  false-positive carrier-identification bugs in detectors 1 and 2 patched
  (ATM-864): markdown-word heuristic, proximity-window over-match, and
  value-starts-with-reference/placeholder sigil.
- **Workable-items engine fixes:** reopen body-preservation, orphaned-bullets
  (F1), SQL index gaps (missing indexes on status/type/location/attribution),
  unbounded queries, dot-separator for non-canonical IDs.
- **SECURITY: `report_item.sh` hardened.** Replaced `eval` with `bash -c`;
  indirect expansion for credential checks.
- **Multitrack hardening:** owner-lock fix, probe-race fix, config
  alias-exclusion, conductor-slot exclusion, §11.4.201(4)/§11.4.111 PARSE
  guard.
- **Curl timeouts** added across the tooling surface.

#### Docs

- Companion docs for §11.4.141 (`scoped_read.sh`, `token_efficiency_lib`,
  `context_compactor`) per §11.4.18.
- Pandoc twins regenerated for Rev 54 (§11.4.216–223 amendment).
- BG-QUALITY-ROOTCAUSE Phase 4 deliverables documented.
