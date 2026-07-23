# PHASE 4 — anti_bluff Submodule: Independent Review (§11.4.142 / §11.4.194 / §11.4.209)

| Field | Value |
|---|---|
| Revision | 1 |
| Last modified | 2026-07-22T23:36:54Z |
| Reviewer | (T1/main - claude1) independent review seam — NOT the build subagent |
| Review substrate (§11.4.209) | **Fable** (claude-fable-5), xhigh effort — Fable available, no fallback used |
| Scope | `constitution/submodules/anti_bluff/` @ `1e193e10bfbe6653db9ad18bfadff0767710f413` + constitution incorporation commit `439b6a07ca2660ed438dfdbbc6f0661f51107fdd` + public repos `github.com/vasic-digital/anti_bluff` / `gitlab.com/vasic-digital/anti_bluff` |
| Method | Every load-bearing claim independently re-executed (§11.4.6 — the build report was NOT trusted); every reported absence control-needled (§11.4.201(7)(b)); mutation probes run on temp COPIES only (working tree untouched, verified clean before and after) |

## Verdict

**NO-GO** (this round) — **0 BLOCKING / 2 IMPORTANT / 4 NIT**. Per §11.4.134
the review re-arms after forward-only remediation; both IMPORTANT findings have
small, mechanical, forward-only fixes (§11.4.113 — no history rewrite needed or
proposed). The core engineering is sound and honestly evidenced: **no seam
passed its own golden-bad**, the RED baseline is genuine and independently
reproduced, the out-of-box test is real, the repos are secret-clean, and the
incorporation is clean and ff-only on all six mirrors.

## 1. What was independently verified (all PASS — captured in this session)

1. **Full suite re-run, twice (§11.4.50):** `test/run_all.sh` → 41 PASS / 0
   FAIL / exit 0, both iterations; verdict lines byte-identical across my two
   runs AND byte-identical to the committed `test/evidence/GREEN_iter1.txt` /
   `GREEN_iter2.txt` (diff empty). Claimed per-suite counts verified by
   enumeration: needle 9 (A1,B1,C1,D1,E1,F1,G1,H1,H2), custody 18
   (A1–A3,B1,C1,D1,E1,E2,F1,G1,H1–H5,I1,I2,J1), evidence-class 6 (A1–F1),
   out-of-box 8 (OB1–OB8) = 41.
2. **Every golden-bad genuinely refuses (observed live in MY runs, not the
   report's):** SOL-03 — injected see-nothing grep → `INSTRUMENT-BLIND(2)`
   never `CERTIFIED-ABSENT`; alternation query + bare-literal needle →
   `NEEDLE-CLASS-MISMATCH(3)`; 2 MB SIGPIPE payload read PRESENT via
   read-to-EOF; mid-line carrier does NOT satisfy an anchored query (negative
   control). SOL-01 — raw `sqlite3` un-evidenced terminal `UPDATE` →
   `CUSTODY-REFUSED` (trigger abort); identical RED/GREEN fingerprints →
   refused; un-staged `Reopened` → refused; `item_history` `UPDATE`/`DELETE` →
   refused; open in-progress item NOT flagged by the sweep (§11.4.201(1)
   false-positive guard); empty items table → `SWEEP-BLIND-OR-EMPTY(2)` never
   PASS. SOL-04 — grep transcript wearing a runtime label → `WRONG-LAYER`;
   fieldless label → `SHAPE-INCOMPLETE`; artifact evidence on a user-visible
   defect → `CLASS-INSUFFICIENT`; source-on-source ACCEPTED (negative
   control); unreadable evidence → `BLIND(2)`. **No seam passed its own
   golden-bad.**
3. **Tests are RED-capable, proven by 3 independent mutations on temp copies**
   (repo untouched; §11.4.115(F) observation-before-trust): (M1) stripping the
   `custody_terminal_refuse` trigger from the template → custody suite FAILs
   (B1 "seam does not bind" + G1 + H-family); (M2) downgrading needle.sh
   blind-detection `return 2` → `return 0` → needle suite FAILs (C1); (M3)
   removing the WRONG-LAYER grep-echo branch → evidence-class suite FAILs
   (B1). All three exits non-zero with precise finding lines.
4. **§11.4.224 RED-first (claim 2):** `test/evidence/RED_initial.txt` shows
   4/4 suites RED exit 1 with per-suite missing-artifact reasons. I
   **independently reproduced the transcript byte-for-byte** by copying ONLY
   the test files into a clean temp dir (no implementations, no commits) and
   running `run_all.sh` — the diff against the committed transcript is empty.
   Combined with (3), the tests are RED-capable and not assertion-free; the
   §11.4.224(A) observation-before-trust bar (Rev-60 disambiguation:
   authorship order is not the condition) is met.
5. **Out-of-box hermetic test is REAL (claim 3):** re-run by me from the
   incorporated clone `constitution/submodules/anti_bluff/` → 8/8 PASS. It
   `git clone`s the COMMITTED tree into a throwaway consumer, runs the
   documented `install.sh --db consumer.db --init`, and proves via plain
   `sqlite3` (no wrapper, no mock) that a raw un-evidenced terminal `UPDATE`
   on the consumer's own DB is `CUSTODY-REFUSED`, that a full-custody write
   lands with a DB-written audit row, and that sweep/evidence-class/needle all
   run from the clone. An uncommitted file cannot pass it (clone of committed
   state only) — verified by construction in `test_out_of_box.sh:40`.
6. **Constitution incorporation (claim 4):** depth-1 — NO `.gitmodules`
   inside anti_bluff (zero nested own-org submodules); `helix-deps.yaml`
   present, §11.4.31-conformant (`schema_version`, `deps: []`,
   `transitive_handling.recursive: true`, `conflict_resolution:
   operator-required`); gitlink at constitution HEAD = `1e193e1` (== both
   mirror tips). **ff-only:** `439b6a07` has exactly ONE parent —
   `6fd244ebe51f` (the pre-add HEAD) — and stages exactly 3 paths by name
   (`.gitmodules`, `submodules/anti_bluff`, the PHASE4 record); no history
   rewrite anywhere. My own `git ls-remote` on ALL SIX constitution mirrors
   (gitflic, github/HelixDevelopment, gitlab/helixdevelopment1, gitverse,
   github/vasic-digital, gitlab/vasic-digital) returns `main ==
   439b6a07ca2660ed438dfdbbc6f0661f51107fdd`.
7. **Project-literal scan (claim 4), control-needled:** the operative literal
   set — `atmosphere`, `rk3588`, `/mnt/track`, serials `998fd36615e99484` /
   `66ff9c4f51f00ee7`, `orange.?pi`, `presenter`, `kinopoisk`, `mistiq`,
   `vader`, `SPK-` — is **clean** across the tracked tree (instrument proven
   seeing: needle `anti_bluff` → 3 files; ERE path proven: 4 hits on the
   custody file). One fixture-string exception found and graded NIT-1 below.
8. **Public-repo hygiene (claim 5):** secrets scan over the FULL history (2
   commits, 20 unique paths enumerated from `rev-list --all`) across 10
   credential pattern classes (`sk-`, `ghp_`, `glpat-`, `AKIA`, `xox[baprs]-`,
   private-key blocks, `CLAUDE_CODE_OAUTH`, `ANTHROPIC_API_KEY`, `password=`,
   `Authorization: Bearer`) — **clean**, with the instrument's sight proven by
   a known-present needle through the same path. `.gitignore` covers the
   §11.4.30 classes incl. `.env`/`.env.*` with `.env.example` carve-out.
   **LICENSE:** MIT (vasic-digital, 2026) present + declared in README §7 —
   appropriate for a public reusable engine. Visibility: GitHub `PUBLIC` (gh
   API JSON); GitLab public PROVEN by **unauthenticated HTTPS** `ls-remote`
   succeeding (a private repo would refuse) — matching the
   continuum/containers/docs_chain convention.
9. **`ls-remote` fingerprints (claim 6), my own run:** GitHub
   `refs/heads/main` = `1e193e10bfbe6653db9ad18bfadff0767710f413`; GitLab
   `refs/heads/main` = `1e193e10bfbe6653db9ad18bfadff0767710f413`; local HEAD
   = same. All three identical — the report's fingerprint table is accurate.
10. **Parse-clean (§11.4.67):** `bash -n` OK on all 11 scripts. Submodule
    worktree clean (`git status --porcelain` empty) before and after review —
    the reviewed files ARE the shipped files.

## 2. Findings (ranked; every fix FORWARD-ONLY per §11.4.113)

### IMPORTANT-1 — INSERT-path bypass of the status-write seam; the "UNWRITABLE for every writer" claim is overbroad and the README honest-boundaries section omits it

- **Where:** `seams/status_custody/custody_triggers.sql:22-23` (T1 is `BEFORE
  UPDATE OF status` only), `:41-43` (T2 same), `:54-56` (T3 same);
  `install.sh:12-14` ("a terminal status without a registered guard + RED/GREEN
  verdict pair ... is UNWRITABLE — for every writer, including raw sqlite3");
  `custody_triggers.sql:2-6` ("bind EVERY writer"); `README.md:94-109` (§4
  honest boundaries enumerates DROP TRIGGER, fabricated fields, oracle
  calibration, Obsolete, concurrency — but NOT this path);
  `PHASE4_ANTIBLUFF_APPLIED.md:29` (golden-bad table implies universal
  raw-writer binding).
- **Captured evidence (my live probe, this session):** on a fully-triggered DB
  (5/5 triggers verified), `INSERT INTO items(atm_id,title,type,status)
  VALUES('REV-001','insert bypass probe','Bug','Fixed');` was **ACCEPTED** —
  un-evidenced terminal status written, **zero** `item_history` rows. The
  sweep then caught it (`CUSTODY-FINDING[C1]` + `CUSTODY-FINDING[C4]`, exit 1)
  — defense-in-depth holds at Seam B, but the preventive write seam is silent.
- **Failure scenario (§11.4.194(1) — un-enumerated input dimension):** any
  import/migration/sync/backfill writer that INSERTS rows already in terminal
  status — exactly the raw-DB-write class §11.4.146(D3) exists for — lands an
  un-evidenced "Fixed" with no refusal and no audit row. Detection is deferred
  to the next sweep run, and **consumer sweep wiring is OWED** (README §5.5),
  so an out-of-box consumer that only ran `install.sh` has NO active layer on
  the INSERT path. The write-seam scenario space has two entry dimensions
  (UPDATE, INSERT); only one was covered and the other was assumed away —
  the exact §11.4.194 forbidden gap ("verifying one and assuming the rest").
- **Forward fix:** (a) add `BEFORE INSERT` twins of T1/T2 (+ either an
  `AFTER INSERT` audit row for status≠default or a documented exclusion) in
  `custody_triggers.sql`; bump `apply_custody.sh`/sweep C0 trigger census 5→7;
  (b) add paired test cases — golden-bad (INSERT-with-terminal refused) +
  negative control (INSERT `'In progress'` accepted); (c) until (a) lands,
  amend `install.sh:12-14`, `custody_triggers.sql:2-6`, and README §4 to name
  the INSERT path as a known boundary. New commits on both mirrors, ff-only,
  then constitution gitlink bump.

### IMPORTANT-2 — §11.4.224 coverage floor neither measured nor honestly tracked as owed

- **Where:** `README.md:111-126` (§5 OWED register) +
  `PHASE4_ANTIBLUFF_APPLIED.md:112-140` (§6 OWED) — neither carries the
  §11.4.224(B)/(E) code-coverage measurement for this NEW executable bash
  corpus (11 scripts). No percentage was claimed anywhere (honest — no
  fabricated figure, §11.4.6), but §11.4.224(E) is explicit: where the
  measurement is not run, the floor must land as an §11.4.3/§11.4.69
  SKIP-with-reason + a tracked §11.4.197 item — "NEVER a silently-dropped
  floor". Here it is silently absent from an otherwise thorough OWED register
  that does track §11.4.85 stress/chaos and CM-gate wiring.
- **Corroborating measurement (mine, control-needled — instrument proven
  seeing via a 2-line needle child; suite ran GREEN under instrumentation;
  5,306 trace lines):** `BASH_ENV`-propagated `PS4` line-trace during the full
  suite yields executed-unique-line lower bounds of 39%–66% per file
  (needle.sh 60%, ab_sql_lib 61%, apply_custody 45%, custody_sweep 48%,
  evidence_class_check 66%, install.sh 39%). **Honest instrument limits
  (§11.4.6):** LINE not branch coverage; multi-line commands/heredocs trace
  only their first line so the numerator systematically undercounts against a
  raw non-comment-line denominator — these figures are evidence that a REAL
  calibrated measurement is owed, NOT a proven sub-85% verdict. (First
  measurement attempt returned an all-zero result; per §11.4.201(7)(b) the
  zero was treated as INSTRUMENT-BLIND, re-instrumented, and needle-proven
  before any figure above was recorded.)
- **Forward fix:** add "§11.4.224 coverage measurement (kcov or calibrated
  PS4-trace) + per-corpus threshold calibration" to README §5 + the PHASE4
  record §6 as a tracked §11.4.197 item; run it in the next slice.

### NIT-1 — ATMOSphere-derived fixture string vs the "ZERO project literals" claim

- **Where:** `test/test_evidence_class.sh:49` — `RUNTIME_OBSERVABLE: grep: 5
  hits for RouteToSecondary in VideoOutputManagerService.java`.
  `VideoOutputManagerService` + `RouteToSecondary` are ATMOSphere-internal
  framework names inside a golden-bad fixture of a PUBLIC repo whose README
  header and `helix-deps.yaml:21` claim "ZERO project literals". Functionally
  inert (§11.4.201(7)(a) — a mention, not a binding; the engine's behavior is
  fully project-agnostic, confirmed by the clean operative-literal scan), but
  it contradicts the claim's letter and leaks a private project's internal
  class name into a public repo. (`ATM-001`-style fixture ids are NOT flagged
  — `ATM-NNN` is the §11.4.54 universal anchor's own canonical example.)
- **Forward fix:** genericise the fixture string (e.g. `RouteFeature in
  SomeVideoService.java`) in a follow-up commit.

### NIT-2 — `nq_stream_contains` certifies absence without a control needle

- **Where:** `lib/needle.sh:86-100`. The stream variant closes the SIGPIPE
  false-absent class (proven) but reports `ABSENT` with no needle argument —
  the blind-instrument class that file-mode `nq_absent` refuses (`return 2`)
  is uncovered in stream mode (a blind `NQ_GREP` yields count 0 → `ABSENT(1)`,
  not `BLIND(2)`; only producer failure is detected). README §4's "measurements
  not routed through needle.sh stay exposed" covers un-routed measurements, not
  this in-library asymmetry.
- **Forward fix:** accept an optional needle after the query (mirroring
  `nq_absent` semantics) OR name the boundary explicitly in the file header +
  README §4.

### NIT-3 — PHASE4 record header timestamp is a rounded placeholder

- **Where:** `PHASE4_ANTIBLUFF_APPLIED.md:6` — `Last modified:
  2026-07-23T00:00:00Z`; the incorporation commit's real UTC time is
  `2026-07-22T23:21:19Z`. §11.4.44 wants the real edit timestamp (same Minor
  class as the Rev-63 M1 remediation precedent). Forward fix on next touch.

### NIT-4 — incorporated clone's origin pushes to GitHub only

- **Where:** `constitution/submodules/anti_bluff` local config — `origin` push
  URL = GitHub only, while the sibling `continuum` submodule's origin fans to
  GitHub + GitLab; a future push from THIS clone would reach one mirror
  (§2.1 multi-upstream norm). No `upstreams/` recipe dir ships, so §11.4.36
  auto-wiring cannot apply. (Both mirrors DID receive the current HEAD — this
  concerns future pushes from the incorporated clone only.)
- **Forward fix:** add the GitLab push URL to origin in the incorporated clone
  (local config, no commit) and/or ship an `upstreams/` recipe dir next slice.

## 3. Summary for the conductor

| Question | Answer |
|---|---|
| Did any seam pass its own golden-bad? | **NO** — all golden-bads refuse, verified live in my own runs + 3 mutation probes on temp copies all caught |
| RED-first genuine? | **YES** — committed RED transcript independently reproduced byte-for-byte from tests-without-implementations |
| Out-of-box test real? | **YES** — 8/8 from the incorporated clone; real `git clone` of committed state, real raw-`sqlite3` refusal on the consumer DB |
| Incorporation clean? | **YES** — depth-1, valid `helix-deps.yaml`, operative-literal set clean (control-needled), ff-only single-parent commit on `6fd244e`, all 6 mirrors at `439b6a07` |
| Public repos secret-clean + licensed? | **YES** — full-history 10-class scan clean (needled); MIT LICENSE; PUBLIC verified on both hosts (GitLab via unauthenticated HTTPS) |
| Fingerprints | **CONFIRMED** — `1e193e10bfbe6653db9ad18bfadff0767710f413` on local + GitHub + GitLab (my own `ls-remote`) |
| Verdict | **NO-GO this round** — 0 BLOCKING / 2 IMPORTANT / 4 NIT; forward-only remediation, then re-review to GO per §11.4.134 |

## 4. Anti-bluff certification of this review

- Every PASS above was observed in MY OWN executions this session, never
  copied from the build report (§11.4.6); the suite was run twice with
  identical verdict lines (§11.4.50) and cross-diffed against the committed
  GREEN evidence.
- Every reported absence (literals, secrets) ran a control needle through the
  SAME instrument + path before being reported (§11.4.201(7)(b)); one of my
  own instruments went blind mid-review (first coverage attempt), was treated
  as INSTRUMENT-BLIND per the discipline, and was re-proven seeing before any
  figure was recorded.
- Mutation probes ran exclusively on temp copies; the submodule worktree was
  verified clean (`git status --porcelain` empty) — review-only constraints
  honored: no edits, no commits, no pushes, no repo changes; the forbidden
  files (`pre_build_verification.sh`, `meta_test_false_positive_proof.sh`,
  `docs/workable_items.db`, /mnt/track2-4) were not touched.
- Review substrate: Fable, xhigh effort (§11.4.209) — recorded above.
