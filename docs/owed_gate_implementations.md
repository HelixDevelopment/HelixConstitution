# Owed gate implementations — §11.4.227(A) deferral registry

**Revision:** 1
**Last modified:** 2026-08-20T11:24:06Z
**Description:** The tracked work items every row of `scripts/gates/gate_ledger_deferrals.tsv` points at.
**Authority:** §11.4.227(A) (named-gate ledger + monotone-decrease ratchet), §11.4.197 (started work reaches a terminal state), §11.4.6 (no-guessing).

## Why this document exists

§11.4.227(A) requires every `CM-*` gate named in the governance corpus to be **either**
implemented in an executable gate site **or** covered by a **registered deferral pointing at a
tracked item**. Silent gate debt is forbidden, and so is deleting a name to lower the count.

The 66 gates below are named in the corpus but not yet implemented. Each needs a genuine
per-domain harness (a build-reproducibility comparison, a SLSA attestation verifier, a contract
broker, a diagram-accuracy oracle, …). **Implementing them as stubs that cannot FAIL would be
the exact §11.4 bluff this corpus forbids** — a gate that cannot refuse is decoration, and
per §11.4.115(F) a guard never observed FAILing on a genuinely-broken artifact is unvalidated
instrumentation that mints nothing. So they are registered as **owed debt**, visibly counted and
monotone-decreasing, rather than faked green.

**Honest boundary (§11.4.6):** registering a deferral proves the debt is *tracked*, not that the
gate *works*. Each item is discharged only when its executable site lands with a paired §1.1
mutation observed to make it FAIL.

## Acceptance criteria (apply to every `OWED-GATE-*` item)

An item is discharged when **all** hold:

1. An executable gate site exists under `scripts/` carrying the gate's literal name structurally
   (§11.4.201(7)(a) — a prose carrier never counts).
2. A paired §1.1 mutation exists and was **observed** to make the gate FAIL before the gate is
   trusted (§11.4.115(F) observation-before-trust).
3. Golden-good **and** golden-bad fixtures are wired, plus a negative control where a
   false-positive refusal is possible (§11.4.107(10), §11.4.201(1)).
4. Any absence the gate reports is control-needle-proven (§11.4.201(7)(b)).
5. The gate's row moves out of `gate_ledger_deferrals.tsv`, and the ledger baseline in
   `scripts/gates/gate_ledger_baseline.txt` ratchets **down**, never up (§11.4.227(A)).

## A. Owed gate implementations


### §11.4.27

- **OWED-GATE-053** — `CM-TEST-TYPE-BREADTH-SEVEN-CANONICAL`
  - **Must assert:** asserts a consuming project's suite covers all seven canonical test types where applicable with honest SKIP-with-reason where not
  - **Blocked on:** needs the canonical type list and per-type detector as consumer DATA

### §11.4.33

- **OWED-GATE-012** — `CM-CLOSURE-VOCAB-TYPE-AWARE`
  - **Must assert:** asserts every closed item Status matches its Type - Bug to Fixed, Feature to Implemented, Task to Completed
  - **Blocked on:** the Issues/Fixed tracker DATA is consumer-owned and absent from this project-agnostic repo

### §11.4.234

- **OWED-GATE-013** — `CM-COMMIT-PUSH-ALWAYS-UNBLOCKED`
  - **Must assert:** asserts a failing validation yields a clear per-check report and a documented remediation path, never an opaque hung or rejected push
  - **Blocked on:** the consumer binds its own commit/push script path as DATA per 11.4.35
- **OWED-GATE-019** — `CM-DEDICATED-HOOK-VALIDATION-SCRIPT`
  - **Must assert:** asserts hook validations run as an explicit named stage of a dedicated idempotent commit/push script
  - **Blocked on:** the consumer binds the script path as DATA per 11.4.35
- **OWED-GATE-029** — `CM-HOOKS-NEVER-BLOCK-PUSH`
  - **Must assert:** asserts core.hooksPath does not gate routine commit/push while the hook file itself stays preserved and unmodified
  - **Blocked on:** the consumer binds its repo and hook paths as DATA
- **OWED-GATE-038** — `CM-NO-GATE-LOST-ON-HOOK-DISCONNECT`
  - **Must assert:** asserts every check a disconnected hook performed still executes at a named script stage or release gate
  - **Blocked on:** needs the consumer-owned stage list and deferral registry

### §11.4.236

- **OWED-GATE-045** — `CM-QA-DEPLOY-READINESS-GATE`
  - **Must assert:** asserts no manual-QA hand-off occurs without a machine-written PASS verdict whose artifact fingerprint equals the candidate
  - **Blocked on:** requires a verdict store keyed on artifact fingerprint

### §11.4.237

- **OWED-GATE-054** — `CM-TRANSLATION-CONTEXT-SPIRIT-REVIEW`
  - **Must assert:** asserts each localized artifact carries an independent review verdict with per-dimension rationale across the six dimensions
  - **Blocked on:** requires a translation-review verdict store and a reviewer substrate

### §11.4.238

- **OWED-GATE-036** — `CM-MANUAL-QA-FINDS-NOTHING-NEW`
  - **Must assert:** asserts a manual QA pass discovered zero previously-unknown defects
  - **Blocked on:** requires a discovery-channel ledger recording each defect's origin channel
- **OWED-GATE-046** — `CM-QA-IS-THE-DISCOVERER`
  - **Must assert:** asserts every out-of-band discovery triggers a coverage-escape audit and registers a new automated check that would have caught it
  - **Blocked on:** requires the discovery-channel ledger

### §11.4.239

- **OWED-GATE-015** — `CM-CRITICAL-INVARIANT-FAILURE-PATH-DOD`
  - **Must assert:** asserts every change touching money, safety, availability or integrity carries explicit failure-path scenarios as passing tests mapped to verdict pairs
  - **Blocked on:** needs a consumer criticality classification and wiring into the 11.4.146(D3) status-custody chain

### §11.4.240

- **OWED-GATE-034** — `CM-LEAST-PRIVILEGE-CAPABILITY-NOT-INSTRUCTION`
  - **Must assert:** asserts producer-versus-gate separation is enforced by capability - filesystem scope, branch protection, store isolation - never by prompt or policy text
  - **Blocked on:** requires CI permission-model introspection
- **OWED-GATE-041** — `CM-PRODUCER-NOT-VERIFIER-SCOPE-SPLIT`
  - **Must assert:** asserts producer, oracle, gate and verifier resolve to distinct actors with no collapse involving the producer
  - **Blocked on:** requires an actor-scope registry

### §11.4.241

- **OWED-GATE-032** — `CM-ILLEGAL-STATE-LADDER-PREFERENCE`
  - **Must assert:** asserts each load-bearing invariant lands at the strongest rung the toolchain supports - types over API-shape over lint over property-test over runtime-assert
  - **Blocked on:** needs per-language toolchain capability detection and a rung classifier

### §11.4.242

- **OWED-GATE-005** — `CM-BISECTION-BEFORE-BLAME`
  - **Must assert:** asserts regression localisation used bisection from the last known-good tag with a monotone-observable precheck rather than blame-log walking
  - **Blocked on:** needs a per-investigation evidence record format, none adopted yet

### §11.4.243

- **OWED-GATE-011** — `CM-CHARACTERIZATION-BEFORE-LEGACY-MODIFICATION`
  - **Must assert:** asserts behaviour-changing edits to legacy code are preceded by a landed green characterization baseline
  - **Blocked on:** needs a legacy-classification rule and a baseline-precedence record

### §11.4.244

- **OWED-GATE-009** — `CM-CAN-I-DEPLOY-GATE-WIRED`
  - **Must assert:** asserts deploy is blocked unless the provider-by-consumer compatibility matrix is all-green, with a missing contract treated as a first-class refusal
  - **Blocked on:** requires a contract broker holding deployed-version state
- **OWED-GATE-014** — `CM-CONTRACT-TESTS-BOTH-SIDES`
  - **Must assert:** asserts each changed cross-boundary carries consumer-published and provider-verified contract tests on both sides
  - **Blocked on:** requires a contract broker and a boundary inventory

### §11.4.245

- **OWED-GATE-040** — `CM-ORACLE-STRATEGY-NAMED-AND-INDEPENDENT`
  - **Must assert:** asserts each test names its oracle strategy from the closed seven-member set and that the oracle is structurally independent of the code under test
  - **Blocked on:** requires an oracle-annotation convention and parser, none adopted

### §11.4.246

- **OWED-GATE-007** — `CM-BUILD-HERMETICITY`
  - **Must assert:** asserts no undeclared build inputs - every dependency version-pinned and lockfile-hashed, no unpinned network reach, no host-env leakage
  - **Blocked on:** requires a sandboxed no-network build harness that does not exist here
- **OWED-GATE-008** — `CM-BUILD-REPRODUCIBILITY`
  - **Must assert:** asserts two independent builds of identical source yield byte-identical artifacts or a diff-set fully accounted for by declared non-determinisms
  - **Blocked on:** requires building real artifacts twice on conformant hosts - this repo has no build pipeline
- **OWED-GATE-050** — `CM-SLSA-L2-PROVENANCE-VERIFIED`
  - **Must assert:** asserts signed SLSA Build Level 2 provenance - source URI, commit hash, builder identity, invocation, artifact hash - verifies against the artifact
  - **Blocked on:** requires a hosted tamper-resistant build platform emitting attestations
- **OWED-GATE-052** — `CM-SUPPLY-CHAIN-DEPS-PROVENANCE-ATTESTED`
  - **Must assert:** asserts dependencies are vendored hash-verified, provenance-attested at source, or mirrored through a hash-pinning registry
  - **Blocked on:** requires a dependency inventory and an attestation verifier

### §11.4.247

- **OWED-GATE-033** — `CM-LAYER-MOVE-COMPLETENESS-CHECK`
  - **Must assert:** asserts a boundary move leaves zero residual references across all seven layers or an explicit tracked compatibility window per residual
  - **Blocked on:** requires the consumer layer-taxonomy audit script and a layer inventory

### §11.4.248

- **OWED-GATE-025** — `CM-FLAKY-TEST-QUARANTINE-WIRED`
  - **Must assert:** asserts a test-history aggregator detects flakes, moves them to quarantine and opens a deadlined stabilisation item
  - **Blocked on:** requires multi-run test-history storage
- **OWED-GATE-044** — `CM-PROTECTED-REGRESSION-SPEC-GATE`
  - **Must assert:** asserts tests tagged PROTECTED-SPEC require the designated CODEOWNERS reviewer before merge
  - **Blocked on:** requires forge branch-protection and CODEOWNERS introspection

### §11.4.249

- **OWED-GATE-026** — `CM-FLIGHT-RECORDER-CAPTURED`
  - **Must assert:** asserts producer inputs, oracle verdict, gate decision and verifier audit are captured as a durable replayable artifact
  - **Blocked on:** requires an event-stream recorder
- **OWED-GATE-048** — `CM-ROLE-SEPARATION-DECLARED`
  - **Must assert:** asserts each load-bearing quality mechanism declares its four roles with no forbidden collapse
  - **Blocked on:** requires a role-declaration convention

### §11.4.250

- **OWED-GATE-028** — `CM-HEURISTIC-TOWER-TRIGGERS-PRIMITIVE-DEBUG`
  - **Must assert:** asserts a stack of two or more compensating heuristics triggers a primitive systematic-debug instead of adding layer N+1
  - **Blocked on:** needs a tower detector that distinguishes accreted mitigation from deliberate defense-in-depth

### §11.4.251

- **OWED-GATE-037** — `CM-NO-BYTE-IDENTICAL-FORK`
  - **Must assert:** asserts no two near-identical trees exist differing only by configuration values
  - **Blocked on:** requires a cross-tree similarity analyzer plus consumer-owned threshold DATA

### §11.4.252

- **OWED-GATE-017** — `CM-DANGEROUS-COMBINATION-FAIL-CLOSED`
  - **Must assert:** asserts every path combining two or more dangerous capabilities refuses on any unverifiable precondition and never fails open
  - **Blocked on:** needs a capability-taxonomy static analyzer, none exists

### §11.4.253

- **OWED-GATE-030** — `CM-IDEMPOTENCY-CHAOS-VERIFIED`
  - **Must assert:** asserts simultaneous-retry, mid-operation-crash and retry-after-apparent-success chaos cases all pass
  - **Blocked on:** requires a live database plus a fault-injection harness
- **OWED-GATE-031** — `CM-IDEMPOTENCY-DB-LEVEL-UNIQUE-GUARD`
  - **Must assert:** asserts every retryable operation carries an idempotency key guarded by a database UNIQUE constraint rather than an application-level check-then-insert
  - **Blocked on:** requires schema introspection of a real database

### §11.4.254

- **OWED-GATE-006** — `CM-BOOT-TIME-INVARIANT-ASSERTED`
  - **Must assert:** asserts each service asserts env, config, dependency, credential, schema and host invariants at boot and exits non-zero rather than serving
  - **Blocked on:** this repo ships no services, so it needs a consumer service inventory as DATA
- **OWED-GATE-010** — `CM-CAPABILITY-MATRIX-PRESENT-AND-IN-SYNC`
  - **Must assert:** asserts the capability matrix declares boot invariants plus offered and required capabilities and stays fingerprint-fresh
  - **Blocked on:** needs a service inventory and an emitted-endpoint extractor

### §11.4.257

- **OWED-GATE-024** — `CM-FAQ-FROM-REAL-QUESTIONS`
  - **Must assert:** asserts a FAQ exists per component, derived from real operator, QA and end-user questions rather than invented
  - **Blocked on:** needs a component inventory and a captured question corpus
- **OWED-GATE-027** — `CM-GUIDE-PER-USER-WORKFLOW`
  - **Must assert:** asserts a task-oriented guide exists for every user-facing workflow
  - **Blocked on:** needs a workflow inventory as consumer DATA
- **OWED-GATE-055** — `CM-USER-MANUAL-PER-COMPONENT`
  - **Must assert:** asserts a complete user manual exists per component, service and product
  - **Blocked on:** needs a component inventory as consumer DATA

### §11.4.258

- **OWED-GATE-001** — `CM-ARCHITECTURE-DIAGRAM-PRESENT-ACCURATE`
  - **Must assert:** asserts a system-architecture diagram exists in an open diffable format, renders non-blank, and matches the live deployed topology
  - **Blocked on:** needs a diagram renderer plus a topology-extraction oracle able to prove diagram-vs-reality accuracy - neither exists in-repo
- **OWED-GATE-018** — `CM-DATAFLOW-DIAGRAM-PER-SERVICE`
  - **Must assert:** asserts a data-flow diagram per service, accurate against real data movement and embedded at its point of use
  - **Blocked on:** same renderer and accuracy-oracle gap as the architecture diagram gate
- **OWED-GATE-020** — `CM-DIAGRAM-EMBEDDED-NOT-ORPHAN`
  - **Must assert:** asserts every diagram is referenced from a README-reachable document rather than living in an orphan gallery
  - **Blocked on:** depends on the diagram inventory the other 11.4.258 gates establish
- **OWED-GATE-049** — `CM-SEQUENCE-DIAGRAM-PER-CRITICAL-WORKFLOW`
  - **Must assert:** asserts a sequence diagram per critical user workflow and per critical cross-component protocol
  - **Blocked on:** needs a workflow inventory and a renderer
- **OWED-GATE-051** — `CM-STATEMACHINE-DIAGRAM-PER-STATEFUL-ENTITY`
  - **Must assert:** asserts a state-machine diagram per stateful entity matching that entity's real transitions
  - **Blocked on:** needs an entity inventory and a transition extractor

### §11.4.259

- **OWED-GATE-002** — `CM-BADGE-CLOSED-COLOR-VOCABULARY`
  - **Must assert:** asserts every README badge colour is drawn from the closed set green/amber/red/gray with every gray carrying an explicit reason
  - **Blocked on:** needs a badge-row parser and a consumer-owned badge set defined as DATA per 11.4.35
- **OWED-GATE-003** — `CM-BADGE-MACHINE-DERIVED-SOURCE`
  - **Must assert:** asserts each badge value traces to a machine-derived provenance source and is never hand-typed
  - **Blocked on:** requires a per-badge provenance computer wired to build, test, coverage and security sources that do not yet exist
- **OWED-GATE-004** — `CM-BADGE-SELF-VALIDATED`
  - **Must assert:** asserts the badge computer passes golden-good, golden-bad and negative-control fixtures per 11.4.107(10)
  - **Blocked on:** depends on the badge computer landing first
- **OWED-GATE-042** — `CM-PRODUCTION-READINESS-GAUGE`
  - **Must assert:** asserts the composite readiness gauge reads green only when every invariant and every blocker is clear
  - **Blocked on:** depends on the readiness tracker and the badge computer
- **OWED-GATE-047** — `CM-README-BADGE-ROW-AT-TOP`
  - **Must assert:** asserts the badge row sits directly below the H1 and above the introduction
  - **Blocked on:** the consumer badge set is undefined and a README structural parser is needed

### §11.4.260

- **OWED-GATE-016** — `CM-CUTTING-EDGE-POSTURE-ALWAYS-ON`
  - **Must assert:** asserts the ten production-readiness invariants are evaluated for every change
  - **Blocked on:** depends on the production-readiness tracker landing first
- **OWED-GATE-043** — `CM-PRODUCTION-READINESS-TRACKER-PRESENT`
  - **Must assert:** asserts the per-component by invariant by evidence-source readiness tracker exists and is fresh
  - **Blocked on:** needs a component inventory as consumer DATA
- **OWED-GATE-058** — `CM-ZERO-NASTY-SURPRISES-AUDIT`
  - **Must assert:** asserts no known-broken code ships, no gate is silenced and no test is disabled without a tracked follow-up
  - **Blocked on:** depends on the findings sweep and a tracker

### §11.4.261

- **OWED-GATE-021** — `CM-EVERY-FINDING-CLOSED-OR-TRACKED`
  - **Must assert:** asserts each audit-sweep finding is either closed with defect-layer evidence or carries a tracked item plus a regression guard
  - **Blocked on:** depends on the findings sweep and a tracker
- **OWED-GATE-056** — `CM-ZERO-FINDINGS-AUDIT-SWEEP`
  - **Must assert:** asserts the ten-class findings sweep runs and emits a machine-readable findings ledger
  - **Blocked on:** requires the sweep script plus per-class golden-good and golden-bad fixtures
- **OWED-GATE-057** — `CM-ZERO-FINDINGS-MONOTONE-RATCHET`
  - **Must assert:** asserts per-class and total findings counts never increase
  - **Blocked on:** depends on the sweep and an operator-owned brownfield baseline decision per 11.4.66

### §11.4.262

- **OWED-GATE-022** — `CM-EVIDENCE-ANALYZER-SELF-VALIDATED`
  - **Must assert:** asserts every evidence analyzer passes golden-good, golden-bad and negative-control fixtures
  - **Blocked on:** requires the analyzer fleet to exist before it can be validated
- **OWED-GATE-023** — `CM-EVIDENCE-LAYER-MATCH-108`
  - **Must assert:** asserts each 11.4.108 layer PASS cites evidence produced AT that layer, rejecting wrong-layer echo
  - **Blocked on:** requires a four-layer verdict store
- **OWED-GATE-035** — `CM-MACHINE-EVIDENCE-AT-EVERY-GATE`
  - **Must assert:** asserts every works, passes or verified claim cites machine-created evidence by path, sha256 and timestamp
  - **Blocked on:** requires a content-addressed evidence store
- **OWED-GATE-039** — `CM-NO-NARRATIVE-ONLY-PASS`
  - **Must assert:** asserts no PASS rests on prose, operator eyeballing or an absence-of-error observation
  - **Blocked on:** requires the evidence store to mechanically distinguish narrative from artifact

## B. Token-extraction artifacts — not real gate names

These eight tokens are **not** gates. They are artifacts of the ledger's per-line token
extractor. They are **deferred rather than removed** because `gate_ledger_removals.tsv` is only
consulted in `check` mode for names **absent** from the ledger — these tokens are still present
in the corpus, so a removal citation never fires for them (proven empirically, not assumed).
Per §11.4.227(A) a name is never deleted to lower the count; the fix is a **naming/wrap cleanup
in the corpus prose**, after which these tokens stop being extracted and the ratchet drops by 8.

**Acceptance criteria for every `OWED-NAMING-*` item:** the producing prose is rewritten so the
token is no longer emitted — range endpoints written with their full `-PROPAGATION` suffix, and
hyphen-wrapped names re-flowed so no line ends mid-name — verified by re-running
`gate_ledger.sh generate` and confirming the bare token no longer appears in the ledger.

### B.1 Prose-range artifacts (Constitution.md line 9)

The sentence *"Propagation gates CM-COVENANT-114-239 through CM-COVENANT-114-254 +
CM-COVENANT-114-257 through CM-COVENANT-114-262"* writes each range endpoint **without** the
`-PROPAGATION` suffix the group shares. The extractor stops at the space, emitting a bare token.
Each real gate (`CM-COVENANT-114-NNN-PROPAGATION`) is present in all five governance files.

- **OWED-NAMING-003** — `CM-COVENANT-114-239` → real gate `CM-COVENANT-114-239-PROPAGATION`
- **OWED-NAMING-004** — `CM-COVENANT-114-254` → real gate `CM-COVENANT-114-254-PROPAGATION`
- **OWED-NAMING-005** — `CM-COVENANT-114-257` → real gate `CM-COVENANT-114-257-PROPAGATION`
- **OWED-NAMING-006** — `CM-COVENANT-114-262` → real gate `CM-COVENANT-114-262-PROPAGATION`

### B.2 Hyphen line-wrap artifacts (mirror files)

A gate name hyphen-wrapped across a line break yields a prefix ending in `-`, which the
extractor's trailing-punctuation stripper (`sed -E 's/[-.,:;)]+$//'`) turns into a bare token.
**All four have zero standalone occurrences corpus-wide** (boundary-anchored check, control-needle
verified) — they exist only as wrapped prefixes.

- **OWED-NAMING-001** — `CM-AF-KINOPOISK-5-1-DUAL` → real gate `CM-AF-KINOPOISK-5-1-DUAL-COVERAGE` (wrap at `AGENTS.md:960`)
- **OWED-NAMING-002** — `CM-AF-UI-DRIVEN-VIDEO` → real gate `CM-AF-UI-DRIVEN-VIDEO-COVERAGE` (wrap at `AGENTS.md:927`)
- **OWED-NAMING-007** — `CM-OPERATOR-BLOCKED-SELF` → real gate `CM-OPERATOR-BLOCKED-SELF-RESOLUTION-AUDIT` (wrap at `AGENTS.md:306`)
- **OWED-NAMING-008** — `CM-OPERATOR-BLOCKED-SELF-RESOLUTION` → same real gate, wrapped at a different point (`CLAUDE.md:440`)

## Note on `CM-COVENANT-114-27-PROPAGATION`

Investigated and **refuted as an artifact**. `Constitution.md:2645` reads *"existing
`CM-COVENANT-114-27-PROPAGATION` stays unchanged (literal `11.4.27` unchanged, stays GREEN)"* —
a deliberate reference to the real propagation gate for anchor §11.4.27, which exists as a real
anchor heading. It is a genuine gate name, not a range truncation, and it falls in the
`*-PROPAGATION` scope rather than the mechanism-gate scope covered here.

---

## B. Landed-but-not-wired: the 29 engine-driven propagation gates

**Status (§11.4.6 honest, measured 2026-08-20):** 29 `cm_covenant_114_*_propagation.sh`
gates (§11.4.27, §11.4.234, §11.4.236–§11.4.262) are IMPLEMENTED as executable gate
sites driven by `scripts/gates/lib/covenant_propagation_engine.sh` plus a 29-row data
pack, each with a paired `*_mutation_test.sh`. Measured facts, not claims:

- `bash -n` / `sh -n`: 83/83 clean.
- §1.1 mutations: 29 × 8 fixtures → `29 entries, 29 exit-0`. Every defect class
  (MISSING / DUPLICATED / DIVERGENT-HEAD / DIVERGENT-BODY / FENCE-MISSING) FAILs;
  every clean fixture (POINTER-OK / CLEAN control / ANCHOR-BOUNDARY) PASSes.
- Ledger delta, proven on a control scratch tree:
  `BEFORE IMPLEMENTED=36 UNIMPL=449` → `AFTER IMPLEMENTED=65 UNIMPL=420`.
  The §11.4.227(A) ratchet moved from **violated** (`449>420 fails=1`) to
  **satisfied** (`420==420 fails=0`) *because of these files*.

**They are NOT yet wired.** No runner, hook, or pre-build stage invokes them.
Per §11.4.227(A) an anchor's done-state is its SEAM landing, not its TEXT landing;
per §11.4.201(8) the ledger's 420 is a metric on a PROXY, and it reaches its true
target only when these gates are implemented **and wired and un-holed**. The GREEN
ratchet must not be read as "§11.4.227(A) satisfied in substance."

### B.1 Findings from the independent adversarial verification (2026-08-20)

Report: `adversarial-review.md` (session scratch). Findings F1–F3 are **defects in the
shared engine**, a faithful port of the already-landed 230-template — they therefore
exist in `main` today via the 5 pre-existing standalone gates, independent of this
batch. These 29 widen the surface; they did not create the hole.

- **OWED-GATE-ADV-F1 (CRITICAL)** — pointer carve-out swallows real propagation loss.
  All four project-root consumer carriers are `is_pointer_carrier`-true yet restate
  anchors; deleting a whole anchor block from all four still exits 0
  (`4 POINTER-INHERITANCE-SKIP, 0 MISSING`). The entire consumer layer can lose any
  anchor with all gates green.
- **OWED-GATE-ADV-F2 (CRITICAL)** — one-line permanent exemption. Adding an
  `## INHERITED FROM …` line to a carrier and deleting its block → exit 0. Any carrier
  can be silently removed from the lockstep set by one documentation-looking line.
- **OWED-GATE-ADV-F3 (CRITICAL)** — lockstep hash truncatable by the corpus's own
  convention. A compact `- §11.4.N — …` citation inside a block collapses the hashed
  region to the heading; 17 of 18 body lines replaced with filler in one carrier → exit 0.
- **OWED-GATE-ADV-F4 (HIGH)** — 29/29 red on the clean tree (55 MISSING each, of which
  18 are vendored third-party trees the prune list does not exclude) → a §11.4.201(1)
  FAIL-bluff surface and §11.4.248 flake-decay risk. §11.4.255/§11.4.256 red is a
  **real** defect: the canonical constitution mirrors lack the re-minted blocks.
- **OWED-GATE-ADV-F5 (HIGH)** — verdict is a function of cwd; nothing pins the root.
  From the repo root the scan reaches outside the repository.
- **OWED-GATE-ADV-F6 (HIGH)** — three false-positive refusals of legitimate corpora
  (sanctioned cross-layer compact summary; §11.4.141 compact index bullet read as
  DUPLICATED; unrelated EOF appendix marking the last anchor DIVERGENT).
- **OWED-GATE-ADV-F7 (MEDIUM)** — 29 names, zero enforcement (the wiring gap above).
- **OWED-GATE-ADV-F8 (LOW)** — a real `### … (§11.4.27, …)` heading the regex misses;
  DIVERGENT lines print ambiguous basenames.

**Acceptance for F1–F6:** each fix is a change to the SHARED engine and therefore
alters the 5 already-landed gates' behaviour — a §11.4.120 reconciliation, with the
golden-FALSE fixture set extended per §11.4.201(1) so the corrected engine still does
not refuse a legitimately-compliant corpus. Not attempted in this batch: the operator's
implementation lock is in force, and engine surgery under a lock is exactly the
unreviewed-change class §11.4.142 forbids.

**Acceptance for F7:** wire the suite into a runner/pre-build stage, at which point the
420 ledger figure stops being a proxy and starts being enforcement.

---

## C. Merge-introduced deferrals (§11.4.263, arrived 2026-08-20 via upstream 502586c)

Upstream commit `502586c` ("anchor(§11.4.263): process-group signal-safety mandate")
named three CM-* gates with neither an implementation nor a registered deferral. The
§11.4.227(A) ratchet caught it correctly on the post-merge re-run — `unimplemented=423
baseline=420 fails=1` — which is the mechanism working, not a false positive.

Remediation taken: register the three against tracked items (the sanctioned §11.4.227(A)
path). The baseline was NOT raised: raising it is the ratchet-gaming channel the anchor
explicitly closes, and these gates remain OWED, not satisfied. Post-registration the
canonical wrapper returns `unimplemented=420 baseline=420 fails=0`.

- **OWED-GATE-059** — `CM-COVENANT-114-263-PROPAGATION`. Asserts the §11.4.263 anchor
  block-start is present exactly once per governance file and lockstep-identical across
  the mirror set. **Blocked on:** the shared propagation engine carries
  OWED-GATE-ADV-F1..F3 (Section B); landing a 30th gate on a holed engine widens the
  surface again. Reconcile the engine first per §11.4.120, then land this gate.
- **OWED-GATE-060** — `CM-KILLPG-PGID-GUARD`. Asserts every `killpg` / `kill(-pid)` call
  site in production code carries the `pid > 1 && pgid > 1` guard. **Blocked on:** needs a
  per-language call-site scanner plus its paired §1.1 mutation (remove the guard → the
  regression test must FAIL, per §11.4.115 observation-before-trust).
- **OWED-GATE-061** — `CM-TEST-MOCK-PID-EXPLICIT-INT`. Asserts every subprocess mock in
  test code sets `mock.pid` explicitly as `int` with `killpg` patched. **Blocked on:**
  needs a test-corpus scanner plus its paired §1.1 mutation (unset `mock.pid` → the
  assertion must catch the `pgid <= 1` attempt).

Honest boundary (§11.4.6): a DEFERRED gate is owed work that is tracked and visible — it
is NOT a gate that runs. §11.4.263's signal-safety mandate is therefore **unenforced
mechanically** in this repository today; only its anchor text binds.
