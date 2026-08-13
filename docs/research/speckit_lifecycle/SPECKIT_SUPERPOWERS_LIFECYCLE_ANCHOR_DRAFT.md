# DRAFT — Speckit → Superpowers Development-Lifecycle Anchor

**Revision:** 1
**Last modified:** 2026-07-23T00:00:00Z
**Status:** DRAFT — NOT YET APPLIED. Prepared by (T1/main - claude4) on operator
directive 2026-07-23. The conductor merges this into `constitution/Constitution.md`
(+ the four CLAUDE/AGENTS/QWEN/GEMINI lockstep mirrors per §11.4.157) AFTER the
agent currently owning those files lands (§11.4.119 single-resource-owner).
**Anchor number:** deliberately UNASSIGNED here — written as `§11.4.NNN`. Next
free number at draft time is **§11.4.226** (highest landed anchor is §11.4.225,
constitution/CLAUDE.md Rev 63, 2026-07-23), but another agent is actively minting
in `Constitution.md` RIGHT NOW, so the conductor assigns the final number at merge
(also mind the pre-existing §11.4.140/§11.4.141 number-collision noted in Rev 62 —
do not reuse either). Substitute `NNN` throughout (including both gate names)
before landing.
**Reference implementation (proving project):** ATMOSphere Track 1
(`/mnt/track1/atmosphere-t1`) — Spec Kit 0.13.5.dev0 initialized 2026-07-23 with
`--integration claude` (skills mode), speckit constitution v1.0.0 at
`.specify/memory/constitution.md` (+ ingestion record + 1,981-file corpus
manifest), `speckit-superpowers-bridge` v1.1.0 installed as a Spec Kit extension
with its `after_tasks` handoff hook registered in `.specify/extensions.yml`.

---

## Proposed anchor text (compact-summary form, ready for the mirrors)

**§11.4.NNN — Speckit → Superpowers development lifecycle: Spec Kit owns the
WHAT, Superpowers enforces the HOW, bridged mechanically — mandatory for every
governed project (Operator mandate, 2026-07-23).** Operator requirements
(verbatim intent, four clauses): (1) every project MUST initialize Spec Kit
(`specify init . --integration claude` from the project root, extensions/
plugins/Skills authored where needed to make this runnable from a claude-toolkit
alias session); (2) once initialized, the project MUST create its speckit
constitution via the speckit `constitution` command, built from EVERYTHING in
the constitution submodule + all project-level constitution overrides/extensions
+ all documentation in the main README + all documents referenced from README +
everything under `docs/` fully recursively — parsed, processed, analyzed into
the speckit constitution; (3) from then on the workflow is: create workable
item(s) fully per the constitution and bring all components + documents up to
date and in sync with them → pass the workable item(s) as the reference into
speckit `specify` (with extra detail + references to every related doc under
`docs/`, any depth) → `clarify` → `plan` → `tasks` → `analyze` → hand the
ENTIRE implementation to Superpowers via the bridge plugin; (4) separation of
concerns is preserved: **SpecKit defines the WHAT** (constitution, `spec.md`,
`plan.md`, `tasks.md` — the design source of truth); **Superpowers enforces the
HOW** (TDD, systematic debugging, code review — preventing jump-to-coding);
bridge = `speckit-superpowers-bridge`, whose `after_tasks` hook writes the
handoff file and whose `/speckit-superpowers-bridge` command tells Superpowers
to execute `tasks.md` with its native skills. Operative clauses: **(A)
INITIALIZED, PROVEN** — `.specify/` present with the project's agent
integration installed; "initialized" is a verified runtime state (§11.4.6/
§11.4.201(11)): the integration's commands/skills actually resolve in a live
session, never assumed from files-on-disk; any load-bearing agent settings
(hook wiring, e.g. the §11.4.210 request-capture hook) are §9.2-backed-up
before init and proven to survive it byte-identical. **(B) DERIVED
CONSTITUTION, HONEST CORPUS** — the speckit constitution at
`.specify/memory/constitution.md` is a GENERATED, SUBORDINATE distillation of
the canonical stack (constitution submodule + project governance layer, per
§11.4.35); when they disagree the canonical stack wins and the speckit file is
regenerated (one-way flow, §11.4.206 single-writer discipline); a corpus too
large for one invocation is chunked DETERMINISTICALLY with an in-repo ingestion
record + machine-generated corpus manifest stating exactly what was full-text
ingested vs structurally ingested vs enumerated-only — a truncated corpus
presented as complete is a §11.4/§11.4.6 bluff. **(C) THE LIFECYCLE** — every
feature flows: fully-formed workable item(s) in the §11.4.93/§11.4.95 SSoT
(docs in sync per §11.4.202/§11.4.106) → `specify` referencing the workable
item(s) + every related doc at any depth → `clarify` → `plan` → `tasks` →
`analyze` → bridge handoff → Superpowers-driven implementation (TDD §11.4.224/
§11.4.43/§11.4.115, systematic debugging §11.4.102, subagent-driven §11.4.70/
§11.4.20, independent review §11.4.125/§11.4.142/§11.4.194 on the §11.4.209
substrate); skipping a stage, or implementing through `speckit.implement` /
free-hand coding while a Superpowers handoff exists, is a lifecycle violation.
**(D) BOUNDARY GUARDED MECHANICALLY** — the bridge's guard hooks
(`before_clarify`/`before_plan`/`before_tasks`/`before_implement`) and
`after_tasks` handoff hook are REGISTERED and ENABLED in
`.specify/extensions.yml`; Spec Kit contract changes are blocked while an
implementation handoff is executing, and native Superpowers planning is
blocked while Spec Kit owns the design artifacts — the WHAT/HOW seam is
enforced by the hooks, never by agent memory (§11.4.109 anti-forgetting
pattern). **(E) HONEST BOUNDARY (§11.4.6)** — the lifecycle governs design
and implementation FLOW; it replaces NOTHING downstream: four-layer coverage
(§11.4.4(b)), runtime signatures on a clean target (§11.4.108), the §11.4.40
full-suite retest, and the §11.4.185 manual-QA final gate all still apply to
the Superpowers-implemented result; the speckit artifacts are additional
design custody, not substitute evidence. Classification: universal (§11.4.17)
— the consuming project supplies its integration name, corpus roots, and
bridge install source as DATA per §11.4.35. Composes §11.4.6/.17/.20/.35/
.43/.70/.93/.95/.102/.106/.108/.109/.115/.119/.125/.142/.185/.194/.201/.202/
.205/.206/.209/.210/.224/§9.2. Propagation gate
`CM-COVENANT-114-NNN-PROPAGATION` (literal `11.4.NNN` across the consumer
fleet) + recommended mechanism gate `CM-SPECKIT-SDD-LIFECYCLE-WIRED` (five
invariants: (i) `.specify/` present with an installed integration whose
commands resolve; (ii) `.specify/memory/constitution.md` exists, is non-template
— zero `[ALL_CAPS]` placeholder tokens, verified with a control-needle run of
the same pattern against the pristine template which MUST hit — and carries
the derived-view/canonical-stack subordination clause; (iii) the ingestion
record + corpus manifest exist beside it; (iv) the bridge extension is
installed + enabled with the `after_tasks` → handoff hook present in
`.specify/extensions.yml`; (v) load-bearing agent hook wiring survived init —
the settings file's request-capture hook entry is present and its self-validation
test passes) + paired §1.1 mutation (delete the `after_tasks` hook entry from
`.specify/extensions.yml` → invariant (iv) FAILs; restore the constitution to
its placeholder template → invariant (ii) FAILs; remove the ingestion record →
invariant (iii) FAILs; strip the `11.4.NNN` literal from a mirror → the
propagation gate FAILs). **Canonical authority:** constitution submodule
[`Constitution.md`](../../../Constitution.md) §11.4.NNN. Non-compliance is a
release blocker. No escape hatch — no `--skip-speckit-init`,
`--freehand-implementation-OK`, `--constitution-from-memory`,
`--truncated-corpus-as-complete`, `--bypass-bridge-handoff`,
`--speckit-implement-during-handoff` flag.

---

## Merge notes for the conductor (not part of the anchor text)

1. **Gate CODE is a separate work item** (§11.4.6 — the gate CONTRACT above is
   drafted; no gate script is claimed shipped). The two gates + the four-part
   §1.1 mutation need implementations under the project's pre-build sweep +
   `meta_test_false_positive_proof.sh`, plus the `CM-COVENANT-114-NNN-PROPAGATION`
   standalone script under `constitution/scripts/gates/` per the recent-anchor
   convention.
2. Number assignment: replace every `NNN` (anchor heading, both gate names, the
   no-escape-hatch list is number-free) — next free was §11.4.226 at draft time;
   re-verify at merge (another agent is minting concurrently).
3. Mirrors: land the compact form above in CLAUDE.md/AGENTS.md/QWEN.md/GEMINI.md
   in lockstep (§11.4.157), exactly ONCE per mirror (Rev-60 F7 duplicated-anchor
   lesson).
4. Consumer-side instantiation for ATMOSphere (project layer, §11.4.35): the
   reference-implementation block at the top of this draft can seed the
   project-CLAUDE.md instantiation section (concrete paths: `.specify/memory/*`,
   the bridge install source, the `scripts/hooks/capture_operator_request.sh`
   survival check).
5. Evidence backing this draft (captured 2026-07-23, session T1/claude4):
   `specify init . --integration claude` run 1 exit 1 (non-interactive confirm)
   → run 2 with `--force` exit 0, git-status delta = 11 NEW untracked entries
   only (10 `.claude/skills/speckit-*` + `.specify/`), zero modified files;
   `.claude/settings.json` sha256 `977dc259…` identical before/after; capture-
   hook self-validation 20/20 PASS; bridge installed via
   `specify extension add <local-path> --dev` exit 0, `specify extension list`
   shows Enabled/3 commands/5 hooks; `bridge-status.sh` + `bridge-state.sh`
   exit 0; guard allow-path proven (`Guard allowed speckit.plan.`, exit 0);
   speckit constitution v1.0.0 validated zero-placeholder with control needle.
