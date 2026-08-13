# PROJECT GAP AUDIT — ATMOSphere, measured 2026-07-23 (Phase 5a of BG-QUALITY-ROOTCAUSE)

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-07-23 |
| Last modified | 2026-07-23T04:59:28Z |
| Status | COMPLETE — read-only audit; every count measured this session with its command (Appendix A); §11.4.201(7)(b) control needles before every reported absence |
| Author | (T1/main - claude1) Phase-5a audit subagent, Fable, §11.4.182 |
| Inputs | `../ROOT_CAUSE_ANALYSIS.md` (PC-1..PC-9, MU-1..MU-6, M1..M19) · `../OPERATOR_COMPLAINT_MINING.md` (+ `../complaints.tsv`) · `../solutions/README.md` + SOL-01..SOL-10 |
| Mandate | Operator directive (verbatim): *"Current project MUST BE fully evaluated and fixed after everything is fully done and all violations, gaps and weak spots and danger zones fixed! We MUST make sure that next 0.0.9 release that we will ship DOES WORK from 'a to z' and for QA team during manual testing to find any bug/issue or inconsistency to be almost impossible!"* |
| Consumer | Phase 5b remediation (GATED on the Phase-4 `anti_bluff` submodule for its helper layer; per-item gating stated in §4) |

---

## 0. The honest bar (§11.4.6)

"Almost impossible for QA to find a bug" is achievable as: **(a) the known-recurring failure
classes made mechanically impossible to ship** (a terminal status cannot exist without
class-matched evidence; a release tag cannot mint while any registered guard lacks a verdict on
the candidate artifact; a recurrence cannot silently re-enter as a fresh id), **plus (b) real
detection pressure applied BEFORE QA** (the first-touch smoke + the most-reopened set exercised
on the flashed candidate, first). It is NOT a guarantee of zero defects — no mechanism below
claims that, and any document that did would itself be the §11.4 bluff this audit exists to
prevent. The measured discriminator (ROOT_CAUSE §7) is the design target: every fix whose
done-claim was preceded by an on-device RED→GREEN flip on the shipping artifact recorded zero
reopens; every fix confirmed at source-green bounced. Phase 5b's job is to make that
discriminator the only path to "done" — and to run it against the 0.0.9 candidate before QA
touches it.

## 1. Executive summary — the gap register, counted

All figures measured 2026-07-23 in this checkout (commands in Appendix A). Where a figure
reproduces a ROOT_CAUSE baseline it is flagged `[=M#]`; deltas are stated.

| # | Gap category | Measured magnitude (today) | Closes with | First-touch-QA risk |
|---|---|---|---|---|
| G1 | Status-without-custody (PC-1) | 52/108 terminal items zero-history (48%) `[=M2]`; 13/26 Reopened without a Reopened event `[=M4]`; **14 items** with impossible sequences (reopens>0, terminal events=0); **173/187 (92.5%) done-claimers unguarded** `[=M7]`; 25/25 reopen events "AI" `[=M6]` | SOL-01 + SOL-04 | HIGH — this is the population the operator's 6/6-broken sample came from |
| G2 | Unimplemented named gates (PC-4) | **239/413** CM-* name-literals with no implementation in the two canonical gate sites (upper bound — see the measured join-gap in §2.2); 85 explicit "gate-code = separate work item" deferrals `[=M12]`; custody seams (sweep, ratchet, `CM-STATUS-CUSTODY`) still absent `[=M11]` | SOL-05 (ledger + ratchet) | MEDIUM directly; HIGH indirectly (it is why G1/G6 persist) |
| G3 | Tracker scope-coverage (SOL-08 axis) | **289/1173 (24.6%)** main-repo commits in the last 60 days carry a tracked id; 75.4% of commit volume runs beside the tracker | SOL-08 | MEDIUM — untracked work is invisible to every custody/coverage seam |
| G4 | Operator-experienced recurrences invisible to the tracker (PC-6) | ≥3 same-defect re-mint pairs with **zero cross-links in the DB** (ATM-812≙ATM-788, ATM-793≙ATM-352-family, ATM-800≙ATM-351-family — link queries returned 0); 6 operator-experienced recurrences with zero reopen events (mining §4); `duplicate-of` used only 5× ever | SOL-07 (+ SOL-01 intake) | **HIGHEST** — these are the defects that keep coming back and the ranking signal is blind to them |
| G5 | Measurement/FAIL-bluff surface (PC-5) | **60 files / 413 piped-`grep -q`-under-pipefail sites** (SOL-03 census re-confirmed; −1 site vs the 414 baseline); release-gating concentration: `pre_build_verification.sh` **118 sites**, `build.sh` 16, `regression_guard_suite.sh` 4, `commit_all.sh` 4, `release_tag.sh` 1 | SOL-03 | HIGH for release-blocking false-FAILs; the false-PASS direction is the worse polarity |
| G6 | Cross-layer verification gaps (PC-3 / §11.4.108) | 82 PENDING-BUILD claim-moves in 60 days; terminal-event evidence classes: **30/51 source-ish vs 21/51 runtime-ish**; live instance: **ATM-799 closed `Fixed` 07-18 with evidence literally "(PENDING-DEVICE)"**; verdict store holds **zero verdicts for the 0.0.8 artifact** (built 07-21 02:44; only snapshot = 07-19); that snapshot: 74 guard rows → **24 PASS / 26 FAIL / 24 SKIP** | SOL-02 + SOL-04 + a verdict run on the candidate | **HIGHEST** — the "bounces on first touch" set is exactly this |
| G7 | 0.0.9 first-touch danger zones | 61 open critical-severity items; ranked family list in §3 (wrong-display routing ≥9 ids incl. the in-flight ATM-816 refactor; audio switching ≥7 ids; subtitles 3-cycle 49-day chain; brightness pair with **zero guards**; 0.0.7's crash-on-boot = 0-minutes-to-first-defect precedent) | SOL-02/04 + targeted guards + §11.4.132 ordering | This IS the QA session |

**What is already fixed (measured, credit where landed):** the release seam is genuinely wired —
`scripts/testing/release_tag.sh:125-135` invokes `scripts/testing/release_verdict_coverage.sh`,
and `regression_guard_suite.sh:577-586` exits 3 on any PENDING ("ABSENCE of a verdict blocks").
A first-touch smoke guard exists and is registered (`ATM-826` → `smoke_first_touch.sh`, 48 KB,
executable, wired in `test_all_fixes.sh`, finding_ids covering ATM-809/810/811/814/819/821).
The 2026-07-18 remediation of M9/M10 is real. The remaining holes are upstream of that seam
(status-write, intake, measurement) and downstream of it (no verdict run has ever been minted on
a release candidate — §5 UNKNOWN-6 of ROOT_CAUSE remains true today).

## 2. The measured record per gap

### 2.1 G1 — Status-without-custody (PC-1), on today's DB

DB: `docs/workable_items.db`, opened `sqlite3 -readonly`. Corpus needle: 619 distinct items
(non-zero → path sighted) `[=M1]`.

- **Terminal-status items:** 108 (`Fixed` 50 + `Completed` 53 + `Implemented` 5). Of these,
  **52 have ZERO `item_history` rows of any kind** (48%). Needle: `item_history` holds 676 rows.
- **Terminal events vs terminal statuses:** only 51 terminal events exist (Fixed 24 +
  Implemented 2 + Completed 25) for 108 terminal-status items — even among the items WITH
  history, most terminal transitions left no terminal event.
- **Reopened without custody:** 13 of 26 currently-Reopened items have no `Reopened` event `[=M4]`.
- **Impossible sequences (the R1 class):** 14 items carry reopen events but ZERO terminal events
  — you cannot reopen what was never closed; the terminal transitions bypassed the ledger:
  `ATM-277 (4/0)` — R1 itself, the stale-paused-frame-on-2nd-display defect, still `Reopened`
  today — plus `ATM-346, ATM-347, ATM-349, ATM-350, ATM-351, ATM-352, ATM-353 (2/0 each)` and
  `ATM-328, ATM-329, ATM-406, ATM-610, ATM-611, SPK-609 (1/0)`. Note the cluster: **8 of the 14
  are the June-09 audio/video reopen block — the exact families the operator kept hitting.**
- **Attribution bias:** all 25 recorded reopen events say `by='AI'`; the six operator-driven
  reopens (mining §4) left no events `[=M6]`.
- **Unguarded done-claims:** done-claiming = terminal + `Ready for testing` = **187** distinct
  ids. Guard registry (`device/rockchip/rk3588/tests/regression_guard/registry.tsv`): 90 rows,
  59 distinct lead keys (44 item-shaped), 70 item-shaped ids counting the `finding_ids` alias
  column. Join: **14 done-claimers guarded** (ATM-018, ATM-310, ATM-341, ATM-343, ATM-348,
  ATM-354, ATM-435, ATM-470, ATM-654, ATM-655, ATM-756, ATM-789, ATM-799, SPK-512) → **173
  (92.5%) unguarded** `[=M7]`. Needle: known-registered ATM-826 resolves through the same join
  path.
- **The PC-9 parking lot:** 79 items sit in `Ready for testing` (last_modified 07-09→07-20) —
  42% of the done-claiming population is design-complete-but-unverified work that reads as
  "done, awaiting a formality."

**Worst offenders (named):** ATM-277 (4 reopens, 0 terminal events, status `Reopened`, family
guarded but never verdict-GREEN on a shipped artifact); ATM-346 (audio output switcher, Reopened
since 06-09, 2/0); ATM-352 (subtitles-on-primary, Reopened, 2/0, re-minted as ATM-793); ATM-351
(4K glitch, Reopened, 2/0, re-minted as ATM-800); ATM-799 (see G6 — terminal WITH evidence that
says PENDING-DEVICE).

**Closure:** SOL-01 (custody triggers at the DB write seam + full-table sweep at build) +
SOL-04 (evidence-class-at-closure). POCs exist and are GREEN (65/65, solutions §5.1); per
§11.4.205 they carry no force until wired — the wiring is the Phase 5b item.

### 2.2 G2 — The unimplemented-gate surface (PC-4)

- Named `CM-*` gates in `constitution/Constitution.md`: **413** `[=M12]`.
- Name-literals resolving in the two canonical gate sites (`pre_build_verification.sh` — 1,028
  distinct CM-* tokens, a superset including project-local gates — plus
  `constitution/scripts/gates/` — 25 tokens): 413 − 239 = 174. **Unimplemented by
  name-literal: 239** (ROOT_CAUSE measured 241 five days ago; SOL-05's instrument measured 234;
  the deltas are methodological and stated in SOL-05 §1).
- **Measured join-gap (a §11.4.201(7)(b) needle caught it live in this session):**
  `CM-RELEASE-VERDICT-COVERAGE` appears in the "unimplemented" list, yet its MECHANISM is fully
  implemented and wired (`scripts/testing/release_verdict_coverage.sh` invoked from
  `release_tag.sh`) — the gate-name literal simply appears nowhere under `scripts/`
  (grep across `scripts/` returned zero files; needle: the literal resolves in
  `Constitution.md`). Therefore 239 is an **upper bound on missing mechanisms and an exact count
  of missing name→implementation joins.** Both facts matter: the join gap is precisely why a
  ledger (SOL-05) is needed — without a name→file mapping, "implemented" is not mechanically
  decidable, and every future census will wobble.
- 85 literal `gate-code = separate work item` deferrals `[=M12]`.
- **The M11 custody seams remain absent today** (six days after their design): no
  `CM-STATUS-CUSTODY` literal anywhere in `scripts/`, `pre_build_verification.sh`, or
  `constitution/scripts/gates/` (needle for the same instrument: the
  `CM-RELEASE-VERDICT-COVERAGE` literal resolves in `Constitution.md` through the same grep
  path); no custody sweep script; no adoption-ratchet file (`ls` on both candidate paths:
  absent).

**Ranking by load-bearing weight (which of the 239 matter for 0.0.9):** the gates guarding
first-touch-failing features and the custody chain outrank doc gates by construction. The
load-bearing subset: `CM-STATUS-CUSTODY` (G1), `CM-GUARD-VERDICT-MACHINE-WRITTEN` (G6),
`CM-RECURRENCE-LINKS-NOT-MINTS` (G4), `CM-GUARD-ASSERTS-REAL-CONDITION` +
`CM-METRIC-VALIDATED-AGAINST-DONE` (G5), `CM-AF-RECENT-WORK-VALIDATION-GATE` /
`CM-AF-VALIDATION-ARTIFACT-FILE` (§11.4.46 — the post-flash recent-work gate that would have
caught 0.0.7's crash-on-boot class), `CM-RISK-ORDERED-VALIDATION-PRIORITY` +
`CM-MOST-REOPENED-EXTRA-DEPTH-LIVE-TEST` (§3 ordering). The ~150 propagation/doc/design gates in
the list are real debt but not 0.0.9-blocking; SOL-05's ratchet is how the backlog shrinks
without a day-one red wall.

### 2.3 G3 — Tracker scope-coverage

Last 60 days, main repo: 1,173 commits; 289 (24.6%) carry an `ATM-|SPK-|FIND-` id in the subject
(needle: ATM-808 resolves). Roughly three quarters of commit volume is invisible to every
id-keyed custody, guard, and coverage join in this audit — the helix_code analogue (corpus 3:
~80% untracked) reproduced at home. Honest bound: subject-line ids are a proxy; commits whose
bodies carry ids or that are legitimately id-free (merges, doc regen) inflate the untracked
share — SOL-08's walker classifies properly; this number sizes the hole, it does not adjudicate
individual commits.

### 2.4 G4 — Operator-experienced recurrences the tracker cannot see (PC-6)

Cross-referencing `OPERATOR_COMPLAINT_MINING.md` §4/§6 against today's DB:

| Recurrence the operator hit | Tracker state today | Custody state |
|---|---|---|
| Brightness sliders ineffective (07-16 ATM-788 → 07-21 **ATM-812, same defect, new id**) | Both open (`Queued`); ATM-812's body/description references ATM-788 **zero times** (query returned 0) | **Zero guards** for either id (registry hits = 0/0) — the only complaint family with NO guard coverage at all |
| Subtitles on primary display (05-29 → ATM-352 → ATM-239 → 07-16 **ATM-793 new id**) | ATM-352 `Reopened`, ATM-239 `In testing`, ATM-793 `Queued`; ATM-793 references ATM-352 **zero times** | Family guarded (11 registry hits on ATM-793) but no candidate verdict |
| 4K local glitch (05-28 → ATM-351 → 07-16 **ATM-800 new id**, "mechanism unconfirmed") | ATM-351 `Reopened`, ATM-800 `Queued`; no link | 1-2 registry hits; no candidate verdict |
| Watch-here / 2nd-display routing (ATM-277 ×4 → 07-16 still broken → 07-21 ATM-809/ATM-814) | ATM-277 `Reopened`; ATM-809 `In progress`; ATM-814 `Queued` | 7 registry hits on ATM-277 + smoke guard; no candidate verdict |
| Audio-switch dialog hang (07-16 ISSUE → 13.6 h REMINDER re-raise → ATM-789) | ATM-789 `Ready for testing` | Guarded (3 hits) + in the guarded∩done set — needs the candidate verdict |
| exFAT USB regression (ATM-797, title says REGRESSION) | `Queued` | 2 registry hits |

The `reopens_count` signal is blind to every row above (the re-mints never incremented the
originals), and `duplicate-of` has been used 5 times in the project's entire history — intake
dedup (SOL-07 / §11.4.214) is unwired in practice. Per §11.4.214's open-target rule, all three
re-mint pairs take **LINK-only** (every target is currently open — no reopen event is owed).

**NC-1..NC-3 (mining §7) remain unclosed by any SOL:** external-state drift on an unchanged
artifact (YouTube cert died with zero code change) needs a SCHEDULED standing probe, not a
seam gate; complaint-intake latency (13.6 h re-raise) needs the §11.4.210 hook path exercised;
no operator-checkable liveness surface exists. These are carried into §3 as punch items, not
silently absorbed.

### 2.5 G5 — The measurement-layer FAIL/PASS-bluff surface (PC-5)

Census re-confirmed: 148 pipefail scripts under `scripts/` + `device/rockchip/rk3588/tests/`;
**60 files contain piped `grep -q` under pipefail; 413 total sites** (baseline said 414 — the
−1 delta is real drift or pattern-boundary, either way within noise; the SIGPIPE hazard itself
was measured 400/400 false-absent at 2 MB in SOL-03's POC). Release-gating classification
(measured per file): `pre_build_verification.sh` **118 sites** (the single most load-bearing
concentration — a false-FAIL here blocks 0.0.9 spuriously, a false-PASS ships it broken);
`build.sh` 16; `regression_guard_suite.sh` 4; `commit_all.sh` 4; `release_tag.sh` 1;
`release_verdict_coverage.sh` 0 (clean); `git_hooks/pre-commit` 0 (clean). Priority within the
413: the 143 sites in those six release-path files first; the long tail (flash.sh, helpers)
after.

### 2.6 G6 — Cross-layer verification gaps (PC-3 / §11.4.108) — the "bounces on first touch" set

- **82 PENDING-BUILD claim-moves** in the last 60 days of git history (ROOT_CAUSE's 2-month
  window measured 69; the count has grown).
- **Terminal-event evidence classes:** of the 51 terminal events carrying evidence, **30 cite
  source-ish artifacts** (research docs, source diffs, gate names) vs 21 runtime-ish
  (qa-results/recordings/device paths). The discriminator says the 30 are the bounce
  candidates.
- **Live worst offender:** `ATM-799` (audio jack ES8388 switch) — history row: `Fixed`
  2026-07-18, evidence ending in **"(PENDING-DEVICE)"**. A terminal status whose own evidence
  string states the device layer was never exercised. It is guarded (3 registry rows) — the
  guard has simply never emitted a verdict on a shipped artifact.
- **The verdict store vs the candidate:** `qa-results/regression_guard/` holds exactly ONE
  fingerprint — `verdict_latest_93f4f1fd51859f45.tsv`, dated **2026-07-19**, i.e. before the
  0.0.8 build (`.last_build_timestamp` = 2026-07-21 02:44:28). Content: 74 guard rows → **24
  PASS / 26 FAIL / 24 SKIP**. Meaning today: (a) 26 registered guards were FAILING at the last
  measured run and nothing in the record shows them turning; (b) the 0.0.8 artifact — the one QA
  tested — has **zero** verdicts; (c) the release seam, correctly, would refuse a 0.0.9 tag
  right now for full-registry PENDING. The seam works; the pipeline has never fed it a
  candidate run. §11.4.135's REQUIRES-REBUILD-PENDING semantics make this honest on an
  intermediate artifact and blocking on the candidate — the blocking half has never been
  exercised end-to-end (ROOT_CAUSE §8's last UNCONFIRMED, still true).
- **Recent closures (since 07-16), individually:** ATM-785 (runtime-ish, GREEN 33/33 host-side
  — sound), ATM-803 (RED+GREEN+negative-control host-side — sound), ATM-815 (Nova retirement,
  doc evidence — Task, acceptable class), **ATM-799 (PENDING-DEVICE — the live PC-3 instance)**.
  1 of 4 recent closures is a device-feature closed at source-green.

### 2.7 G7 — Danger zones for the 0.0.9 QA session

Base rates: 0.0.7 = crash-loop on first boot (0 minutes to first defect); 0.0.8 = 12 minutes to
first defect (YouTube-on-2nd-display, sound-no-picture); ~90% of class-A complaints land within
hours of a flash. 61 open critical-severity items today. The ranked family list is §3's spine.
One structural risk multiplier stands out: **ATM-816 (`In progress`, Critical) is an in-flight
REFACTOR of the video-reproduction path to a fullscreen-mirroring middle-solution** — the single
highest-blast-radius change targeted at 0.0.9, landing in exactly the family that broke first
touch in BOTH prior releases, while ATM-819 (`In progress`) records that the family's
full-automation pipeline itself reported GREEN-while-broken. If 0.0.9 ships ATM-816 without the
candidate verdict run + smoke-first ordering, the 12-minute pattern repeats deterministically.

## 3. The punch-list — top 10 by first-touch-QA risk (the Phase 5b execution order)

Each row: what QA will hit → the mechanism that makes it impossible-or-caught → gating.
"NOW" = autonomously doable in this checkout today; gate legend in §4.

| # | Punch item | Why it is the risk (measured) | Mechanism (SOL) | Gating |
|---|---|---|---|---|
| P1 | **Run the full regression-guard suite on the 0.0.9 candidate and mint the verdict file; triage the 26 standing FAILs from the 07-19 snapshot first** | Zero verdicts exist for any shipped artifact; 26 guards FAILING at last run; the release seam has never been fed a candidate; both prior releases failed ≤12 min in guarded families | SOL-02 (seam already wired — this is its first real execution) + §11.4.130/132 ordering | BUILD + DEVICE (D1 `998fd36615e99484`; D2 unavailable per the durable record) |
| P2 | **Wrong-display video routing family under the ATM-816 refactor: RED-baseline the refactor against `smoke_first_touch.sh` + the FIND-1/ATM-277/ATM-819 guards BEFORE it merges; smoke runs FIRST post-flash** | ≥9 ids; first-touch failure in BOTH prior releases; the refactor is the largest in-flight blast radius; the family's own automation is the recorded bluff (ATM-819) | SOL-04 (class-matched evidence: pixels/liveness, never greps) + existing smoke guard + §11.4.132 | Source-side NOW; verification BUILD + DEVICE |
| P3 | **Wire SOL-01 custody (DB triggers + full-table sweep) so no new terminal status can land without an event + class-matched evidence; honesty-sweep the existing 52 zero-history terminal items and the ATM-799 class** (re-classify or attach evidence via the sanctioned tool — never raw SQL) | 48% zero-history; 14 impossible sequences; ATM-799 terminal with "(PENDING-DEVICE)" evidence; the 6/6-broken sample came from exactly this population | SOL-01 + SOL-04 | NOW (DB writes via sanctioned tool; the pre-build sweep wiring coordinates with Phase 4 — contention path `pre_build_verification.sh`) |
| P4 | **Intake dedup + link backfill: land the SOL-07 intake check; LINK the three measured re-mint pairs (ATM-812→ATM-788, ATM-793→ATM-352, ATM-800→ATM-351); backfill the six operator-experienced reopens as User-attributed history events** | The fragility signal is blind exactly on the repeat offenders; 25/25 events "AI"; `duplicate-of` used 5× ever; §11.4.214 open-target rule ⇒ LINK-only (no reopen minting owed) | SOL-07 (+ SOL-01 intake half) | NOW |
| P5 | **Audio-switching family: verify ATM-799 on the candidate FIRST (its guard exists and has never run on a shipped artifact); ATM-789 + ATM-346 through their guards at §11.4.189 extra depth** | Audio = operator top priority (§11.4.72); ATM-346 `Reopened` since 06-09; ATM-799 is the live source-green closure; dialog-hang needed a 13.6 h re-raise to even get tracked | SOL-02 execution + §11.4.189 | BUILD + DEVICE |
| P6 | **Author the missing brightness guard (ATM-788/ATM-812) — the only complaint family with ZERO guard coverage — RED on the current artifact per §11.4.115** | Operator hit it twice, 5 days apart, two ids, no guard, no link; a guaranteed third hit otherwise | §11.4.115 RED-first + registry row | Authoring NOW; RED validation DEVICE |
| P7 | **Needle the release path: apply SOL-03's needled-measurement primitive to the 143 piped-`grep -q` sites in the six release-gating files (pre_build 118, build.sh 16, suite 4, commit_all 4, release_tag 1)** | A false-FAIL blocks 0.0.9 spuriously (operator trust damage per §11.4.201(1)); a false-PASS ships it broken; 400/400 false-absent reproduction at 2 MB is on file | SOL-03 | NOW for the library + non-contended files; `pre_build_verification.sh` edits coordinate with Phase 4 |
| P8 | **First-boot/crash-loop + exFAT + touch-degradation smoke: extend `smoke_first_touch.sh` (or register siblings) for boot-to-launcher-stable, exFAT mount (ATM-797), sustained-touch (ATM-818), CEC power (ATM-817)** | 0.0.7's 0-minute crash-loop had no first-boot smoke; ATM-797 is a titled REGRESSION; both are cheap deterministic probes | §11.4.135 registry rows + §11.4.46 recent-work gate | Authoring NOW; validation BUILD + DEVICE |
| P9 | **Land the SOL-05 gate ledger + ratchet (name→implementing-file mapping; monotone-decrease baseline over the 239)** — including the measured join-gap class (mechanism-implemented-without-literal) | 239 name-unimplemented; the custody seams themselves sat prose for 6 days; without the ledger every future census wobbles and new gates join the 239 | SOL-05 | NOW |
| P10 | **Stand up the NC-1 scheduled standing probe (YouTube/device-cert reachability on a timer, not at seams) + the SOL-09 detection-pressure scheduler so guards run between releases, not only at them** | A shipped feature died with NO code change (05-29 cert drift); corpus-3 recurrence latency = the next sweep, not the next use | SOL-09 + new scheduled probe (NC-1 is outside every current SOL — honest gap being closed, not silently absorbed) | Scheduler NOW; live probe DEVICE + network |

**Deliberately-surfaced operator decisions (never autonomous, §11.4.122/§11.4.66):**
(a) the §11.4.140/§11.4.141 anchor-number collision (fleet-wide citation change — already
flagged in the constitution status log); (b) the semantics of the 79-item `Ready for testing`
parking lot (PC-9 — attaching an evidence precondition per state is a governance change);
(c) SOL-05 ratchet + §11.4.224 coverage-floor brownfield adoption mode; (d) triage priority of
the 26 standing guard FAILs if any prove to be won't-fix-class. Phase 5b should batch these
into ONE §11.4.66 interactive round rather than four blocking stops.

## 4. Doability matrix (what gates what)

| Gate | Items | Notes |
|---|---|---|
| **NOW (autonomous, this checkout, no build/device)** | P3 (DB custody wiring + honesty sweep), P4 (dedup + links + User-reopen backfill), P6/P8 authoring halves, P7 library + non-contended files, P9 ledger+ratchet, P10 scheduler half; drafting the P2 RED baselines | DB writes go through the sanctioned mutation tool only (raw SQL is the PC-1 bypass being closed); constitution-submodule edits follow §11.4.26 |
| **Phase-4 (`anti_bluff` submodule) gated** | The helper layer P3/P7 call into (`ab_*` evidence/needle helpers), and any edit to `pre_build_verification.sh` / `meta_test_false_positive_proof.sh` (Phase 4's declared contention paths) | Submodule not present yet (probe: `constitution/submodules/` = clickup_sync, continuum, session_orchestrator, token_optimizer). Everything in the NOW column is structured to not block on it |
| **BUILD gated** | P1, P5, P8-validation, P2-verification (need the 0.0.9 candidate artifact) | One containerized build at a time (§12.9) |
| **DEVICE gated** | P1, P2, P5, P6-RED, P8, P10-live | D1 `998fd36615e99484` only; D2 `66ff9c4f51f00ee7` unavailable per the durable session record — §11.4.3 topology-honest single-device verdicts, never a faked dual-device PASS |
| **OPERATOR gated** | The four decisions listed in §3 | Batch into one §11.4.66 round |

## 5. UNKNOWN / honest-boundary register

- **UNKNOWN: the true reopen rate.** Still an undercount (G4 proves the re-mint channel is
  live); a corrected figure requires the P4 link backfill to land first.
- **UNKNOWN: how many of the 239 name-unimplemented gates have mechanism-without-literal
  implementations** (the CM-RELEASE-VERDICT-COVERAGE class). ≥1 proven; a full resolution IS
  the P9 ledger — hand-auditing 239 names here would reproduce the census wobble the ledger
  exists to end.
- **UNKNOWN: the verdict-snapshot device identity.** `verdict_latest_93f4f1fd51859f45.tsv`
  carries `device_serial 93f4f1fd51859f45`, which matches neither durable-record serial (D1
  `998fd36615e99484`, D2 `66ff9c4f51f00ee7`). Phase 5b must resolve which physical device
  produced it before treating its 24 PASSes as evidence for anything (§11.4.200's
  verify-the-intended-target class).
- **UNCONFIRMED: that the 26 guard FAILs of 07-19 are all still-live defects** — some may have
  been fixed by 0.0.8 work; only the P1 candidate run decides (§11.4.7 — same-conditions
  evidence, not inference).
- **Boundary:** commit-subject id-bearing (G3) is a proxy for "tracked"; the audit sizes the
  hole, SOL-08 adjudicates it. The G5 site count is syntactic exposure, not proven-broken —
  the 400/400 SIGPIPE reproduction proves the hazard class, not each site.
- **Boundary:** this audit proves gaps EXIST and are closable; it does not certify that closing
  them yields zero QA findings (§0). Discovery pressure (§11.4.118) beyond the known families
  remains Phase 5b/QA's job — the enumerated-coverage claim, not the clean-bill claim.

## 6. Anti-bluff certification

Read-only on the project: nothing was written except this file (`remediation/` created for it).
The DB was opened `-readonly` for every query. No governance file, gate site, test, or Phase-4
path was touched; no commit, no push. Every count above was produced this session by the
commands in Appendix A; every reported absence ran a control needle through the same instrument
path first, and one needle FAILED usefully (§2.2's join-gap — reported as a finding, not
absorbed). `find -newermt` was not used anywhere (known-blind on this host). Figures reproduced
from the input corpus are cited `[=M#]`; live deltas from the baselines (413-vs-414 sites,
239-vs-241 gates, 82-vs-69 PENDING-BUILD moves) are stated, not smoothed.

## Appendix A — measurement commands (all run 2026-07-23, repo root `/mnt/track1/atmosphere-t1`)

| Ref | Command | Needle |
|---|---|---|
| A1 | `sqlite3 -readonly docs/workable_items.db "SELECT COUNT(DISTINCT atm_id) FROM items"` → 619 | non-zero corpus |
| A2 | terminal: `...WHERE status IN ('Fixed (→ Fixed.md)','Implemented (→ Fixed.md)','Completed (→ Fixed.md)')` → 108; minus `atm_id IN (SELECT atm_id FROM item_history)` → **52** | `SELECT COUNT(*) FROM item_history` → 676 |
| A3 | `SELECT event_type, COUNT(*) FROM item_history GROUP BY event_type` → Updated 288 / Opened 287 / Completed 25 / Obsolete 25 / Reopened 25 / Fixed 24 / Implemented 2 | — |
| A4 | Reopened-status minus Reopened-event ids → **13**; `SELECT "by", COUNT(*) ... event_type='Reopened' GROUP BY "by"` → AI 25 | — |
| A5 | per-id `SUM(Reopened), SUM(terminal)` HAVING r>0 AND t=0 → **14 ids** (ATM-277 4/0 top) | second rows return 2/0 distinct ids |
| A6 | done-claiming 4-status query → **187**; registry keys `awk -F'\t' '!/^#/&&NF>1{print $1}' registry.tsv \| sort -u` → 59 (44 item-shaped); + col7 aliases → 70; `comm -12` join → **14** guarded | ATM-826 resolves through the join |
| A7 | registry rows `awk NF>1` count → 90 | header schema read via `cat -A` |
| A8 | verdict store `ls qa-results/regression_guard/` → 1 fingerprint (20260719T204913Z / 93f4f1fd51859f45); rows `awk '$1=="row"'` → 74; verdict col → 24 PASS / 26 FAIL / 24 SKIP | `.last_build_timestamp` → 1784583868 = 2026-07-21 02:44 (+05) |
| A9 | seam wiring: `grep -n regression_guard\|verdict scripts/testing/release_tag.sh` → invocation at :125-135; suite PENDING semantics `grep -nE 'exit 3\|PENDING' regression_guard_suite.sh` → exit 3 block at :577-586 | known token `OWNED_SUBMODULES` → 5 hits |
| A10 | gates: `grep -oE 'CM-[A-Z0-9-]+' constitution/Constitution.md \| sort -u` → 413; same over `pre_build_verification.sh` → 1,028; over `constitution/scripts/gates/` → 25; `comm -23` → **239** | known-implemented in-prebuild resolves; `CM-STATUS-CUSTODY` in unimpl list = 1 |
| A11 | join-gap: `grep -rln CM-RELEASE-VERDICT-COVERAGE scripts/` → **0 files** while `scripts/testing/release_verdict_coverage.sh` exists + is invoked | literal resolves in `Constitution.md` via same grep form |
| A12 | M11: `grep -rln CM-STATUS-CUSTODY scripts/ pre_build_verification.sh constitution/scripts/gates/` → 0; `ls *ratchet*` both paths → absent | A11's needle (same instrument, known-present literal) |
| A13 | deferrals: `grep -c "gate-code = separate work item" constitution/Constitution.md` → 85 | — |
| A14 | pipefail census: 148 pipefail files; `xargs grep -lE '\| *grep -q'` → **60 files**; `grep -cE` sum → **413 sites**; per-file: pre_build 118 / build.sh 16 / suite 4 / commit_all 4 / release_tag 1 / release_verdict_coverage 0 / pre-commit 0 | first candidate files listed (flash.sh, ...) |
| A15 | scope: `git log --since=2026-05-24 --oneline \| wc -l` → 1,173; subjects matching `(ATM\|SPK\|FIND)-[0-9]+` → **289** | ATM-808 resolves |
| A16 | `git log --since=2026-05-24 --pretty=%s%b \| grep -ciE 'PENDING-BUILD'` → **82** | — |
| A17 | recent terminal closures since 07-16 → 4 ids; their `item_history.evidence_path` printed verbatim (ATM-799 ends "(PENDING-DEVICE)") | — |
| A18 | terminal-event evidence classes (qa-results/recording/wav/mp4/device ⇒ runtime-ish) → 21 runtime-ish / 30 other; 51/51 non-empty | — |
| A19 | `Ready for testing` → 79 ids, last_modified 2026-07-09..2026-07-20; open critical → 61 | — |
| A20 | family links: ATM-812 body/description LIKE '%ATM-788%' → 0; ATM-793 LIKE '%ATM-352%' → 0; `obsolete_details` reasons → duplicate-of 5 | non-zero on other reason values proves query path |
| A21 | registry hits per family id (`grep -c <id> registry.tsv`): ATM-788 0, ATM-812 0, ATM-277 7, ATM-793 11, ATM-346 5, ATM-789 3, ATM-351 1, ATM-800 2, ATM-809 1, ATM-814 1, ATM-797 2 | ATM-819 → 4 |
| A22 | `smoke_first_touch.sh` present (48,965 B, exec) at `device/rockchip/rk3588/tests/`, referenced from `test_all_fixes.sh`, registered as ATM-826 row 1 of registry | — |
| A23 | Phase-4 probe: `ls constitution/submodules/` → clickup_sync, continuum, session_orchestrator, token_optimizer (no `anti_bluff`) | dir listing non-empty |

**Instrument notes for reproducers:** the host `grep` is a different regex engine than habitual
(`\|` is a literal under `-E`) — all alternations above use unescaped `|`; never read a
pipeline's exit through a formatter; `find -newermt` is blind on this host; the A6 join is
id-shaped-keys only — 15 non-item registry keys (FY, EM, FIND-*, ...) join nothing by
construction and are part of G2's ledger work.
