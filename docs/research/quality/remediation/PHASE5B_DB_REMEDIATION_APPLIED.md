# PHASE 5B — DB-only remediation APPLIED (BG-QUALITY-ROOTCAUSE, doable-now slice)

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-07-23 |
| Last modified | 2026-07-23T04:35:00Z (+05 host clock) |
| Status | COMPLETE — all writes applied via the sanctioned `workable-items` binary; zero raw-SQL writes; zero ids deleted/renumbered (§11.4.54); no commit/push (conductor lands the DB) |
| Author | (T1/main - claude1) Phase-5b remediation subagent, Fable, §11.4.182 |
| Inputs | `PROJECT_GAP_AUDIT.md` (measured requirements) · `../OPERATOR_COMPLAINT_MINING.md` (+ `../complaints.tsv`) · `docs/workable_items.db` (every audit figure re-verified live before acting, §11.4.6) |
| §9.2 backup | `docs/workable_items.db.bak-phase5b-1784762212` — **plain `cp`**, verified DISTINCT inodes (live=9635790, backup=9656953; not a hardlink). `PRAGMA integrity_check` = ok BEFORE and AFTER all writes |
| Scope honored | DB + derived docs only. Untouched: `pre_build_verification.sh`, `meta_test_false_positive_proof.sh`, `constitution/submodules/`, all of /mnt/track2..4, all L3 test files |

## 0. Write ledger (complete — 10 sanctioned-tool writes, nothing else)

| # | Verb | Target | Effect |
|---|---|---|---|
| 1–3 | `update --description` | ATM-812, ATM-793, ATM-800 | §11.4.214 duplicate/candidate links appended (T1); tool wrote its own `Updated` audit rows |
| 4–9 | `diary add` (User, FAIL) | ATM-277, ATM-352, ATM-351, ATM-789, ATM-788, ATM-797 | Operator reopen-channel backfill (T2); `test_diary` entry_id 103–108 |
| 10 | `reopen` (AI, captured-evidence-contradicts) | ATM-799 | Demotion Fixed→Reopened, relocated Fixed→Issues (T3) |

Post-write DB facts: 619 distinct ids (unchanged — nothing deleted/renumbered), `item_history` 676→680 rows (3 `Updated` + 1 `Reopened`, all tool-minted), `test_diary` +6 User rows, `PRAGMA integrity_check`=ok, WAL checkpointed (`wal_checkpoint(TRUNCATE)` → 0|0|0).

## 1. T1 — same-defect re-mint links (SOL-07 / §11.4.214)

Every pair's BOTH full bodies were read from the DB before the verdict (§11.4.186 negative-control applied; no auto-merge; no item closed, obsoleted, or merged — links only, §11.4.54).

### Pair 1 — ATM-812 ≙ ATM-788 → **SAME-DEFECT (confirmed) → LINK-only**
- Verdict basis: ATM-788 Defect A = primary brightness slider has no effect (operator, 2026-07-16T20:48:42Z); ATM-812 = brightness sliders do not affect connected displays (operator, 2026-07-21, 0.0.8 QA). Same user-visible defect re-reported 5 days later under a new id; mining §4 row states it verbatim ("same defect, NEW id, 5 days later").
- Scope honesty recorded in the link: ATM-788's Defect B (slider spacing ≙ ATM-438) is NOT part of ATM-812; ATM-812 additionally carries the two-overlay dimming workaround SPEC, which stays tracked there (nothing merged, nothing lost).
- Chain note recorded: ATM-788's own body maps Defect A to still-Reopened **ATM-437** (candidate chain head). Both ATM-437 and ATM-438 verified `Reopened`/open in the DB.
- Action: `**Duplicate-of:** ATM-788` block appended to ATM-812's description. ATM-788 is OPEN (`Queued`) ⇒ **LINK-only, no reopen minted** (§11.4.214 open-target rule — reopening an open item is undefined in the §11.4.15 status machine).

### Pair 2 — ATM-793 ≙ ATM-352 → **SAME-DEFECT (confirmed) → LINK-only**
- Verdict basis: ATM-352 (FIND-5/7) = subtitles render on PRIMARY instead of 2nd display, general across streaming apps, `Reopened` since 2026-06-09. ATM-793 = the Apple-TV instance (operator 2026-07-16T21:03:50Z, "has not been fixed at all!!!"); ATM-793's own body states the defect is NOT app-specific but the subtitle-forwarding path itself (siblings ATM-309/ATM-792; family ATM-239 `In testing`). Mining §6 chain 1: ≥3 operator-experienced cycles over 49 days.
- Action: `**Duplicate-of:** ATM-352` block appended to ATM-793's description. ATM-352 is OPEN (`Reopened`) ⇒ **LINK-only, no reopen minted**. ATM-793's §11.4.138 bluff-audit deliverable stays tracked on ATM-793.

### Pair 3 — ATM-800 ≟ ATM-351 → **UNDECIDED → CANDIDATE-link only (deliberately NOT confirmed)**
- Verdict basis (§11.4.214(3) first-class outcome): ATM-351 has a NAMED root cause (ATMOSphere MPV 4K x265 10-bit, libmpv drm_prime interop → SW fallback). ATM-800's own body marks its mechanism UNCONFIRMED and its player unspecified, and enumerates non-MPV candidate mechanisms (IO, VOM surface handoff, HW-codec disablement). Confirming the duplicate would be a §11.4.6 guess; a wrong merge silently deletes a real defect.
- Action: `**Candidate-duplicate-of:** ATM-351` block appended to ATM-800's description, carrying the explicit DISCRIMINATOR (ATM-800 acceptance step 2: decoder identity + HW-vs-SW as FACT ⇒ resolve-through or declare distinct). Both open; no reopen owed on either verdict.

**Link losslessness proof (pre-write §11.4.201(7) control):** `update --description` regenerates `body_md` from the minimal template (SPK-481 truncation class). Before writing, each target's stored `body_md` was byte-compared against the exact `renderItemBody(columns)` reconstruction — **all three matched byte-identically** (3625/3510/5343 B), so regeneration with the appended description was provably lossless. Post-write: bodies grew by exactly the appended block (+1142/+1093/+1324 B), statuses unchanged (`Queued`), and the A20 audit instrument flipped 0→1 for all three pairs (`body/description LIKE '%<canonical>%'`).

**Restored-signal note (honest boundary, §11.4.6):** these prose links make the re-mints mechanically discoverable (the A20 query class) and satisfy §11.4.214's no-loss contract; they do NOT increment any `reopens_count` counter — per §11.4.214's open-target rule no reopen is OWED (all three canonical targets are open), so the reopens signal for these families is correctly carried by the still-open `Reopened` statuses plus the T2 diary rows below.

## 2. T2 — operator reopen-channel backfill (the 6 recurrences with zero User events)

Pre-write fact (re-verified): all 25 `item_history` Reopened events were `by='AI'`; the six operator-experienced recurrences (mining §4/§6) left zero tracker events. Per §11.4.214, **every family target is currently OPEN**, so minting `Reopened` history events for them is structurally forbidden (reopen presupposes a closure to demote from). The sanctioned vehicle used instead: **§11.4.149 `test_diary` rows with `tested_by='User'`** — the operator's manual-QA FAIL observations, mechanically queryable (`SELECT * FROM test_diary WHERE tested_by='User'`). No date fabricated: exact timestamps come from the §11.4.202 directive records / the mining doc; where only a date is recoverable the time is recorded literally as UNKNOWN.

| entry_id | Item (status at write) | date_time | feature_class | Operator occasion recorded |
|---|---|---|---|---|
| 103 | ATM-277 (`Reopened`) | 2026-07-16 (time UNKNOWN — QA burst 20:50–21:22) | video_display | "All reported issues with Watch here button still exist!" after 4 AI-attributed reopen cycles in one week; family failed first-touch again 07-21 (ATM-809/814) |
| 104 | ATM-352 (`Reopened`) | 2026-07-16T21:03:50Z | subtitle_render | "Subtitles never show on 2nd display… has not been fixed at all!!!" (entered tracker as ATM-793 — now linked) |
| 105 | ATM-351 (`Reopened`) | 2026-07-16T21:50:16Z | video_display | 4K glitch re-reported (entered as ATM-800 — candidate-linked); FAIL records the OBSERVATION, explicitly NOT a confirmation ATM-351's named mechanism recurred |
| 106 | ATM-789 (`Ready for testing`) | 2026-07-16T20:50:00Z (seconds UNKNOWN) | audio_output | Dialog-hang ISSUE + the 2026-07-17T10:28 `REMINDER ::` re-raise (13.6 h intake latency, NC-2); item minted only 07-18 |
| 107 | ATM-788 (`Queued`) | 2026-07-21 (time UNKNOWN) | display_topology | Defect A re-experienced during 0.0.8 QA; entered as ATM-812 (now linked); reopens signal never moved (PC-6) |
| 108 | ATM-797 (`Queued`) | 2026-07-16T21:23:17Z | storage_read | Operator-titled REGRESSION (exFAT worked on prior versions); NO prior terminal exFAT item exists in the tracker ⇒ no reopen target — the gap itself is documented in the row |

Every row cites `constitution/docs/research/quality/OPERATOR_COMPLAINT_MINING.md` as evidence_path and states in `action_taken` WHY no status change / no Reopened event was minted.

## 3. T3 — honesty sweep (false-terminal / zero-custody)

### 3.1 DEMOTED (status genuinely wrong): **ATM-799** — the live PC-1 instance
- Pre-write facts (re-verified): status `Fixed (→ Fixed.md)` in Fixed; its `Fixed` history event's evidence string literally ends **"(PENDING-DEVICE)"**; its own body documents the device-gated validation was honestly SKIPped — then the closure outran that.
- Action: `reopen --who AI --when 2026-07-23 --why captured-evidence-contradicts --incident constitution/docs/research/quality/remediation/PROJECT_GAP_AUDIT.md` → status `Reopened`, relocated Fixed→Issues, `Reopened-Details` upserted, body preserved (single-Status body pre-verified; source-side work context intact — the item's true position, source-landed-awaiting-device-validation, remains readable in its body). History now carries a LEGAL `Opened→Fixed→Reopened` sequence.

### 3.2 PROVABLY WRONG but demotion TOOL-BLOCKED (operator review): **ATM-380**
- Facts: column `Completed (→ Fixed.md)` / location Fixed; its body's own top `**Status:**` line reads `In progress`; title says "runtime confirm pending"; body carries SIX non-terminal sub-items (D1/D2/D4/D5 `In progress`, D6 `Operator-blocked`, D7 `Queued`) plus `[ATM-008] §M.M3` at `Ready for testing` — and **ATM-008 has NO separate DB row**, so open work is invisible inside a Completed item. Its sole history row says the Completed event was minted mechanically during doc-sync ("status already terminal"), not from evidence.
- WHY not demoted: `canonicalizeBodyStatusLine` (parse.go:496-516) patches the **LAST** `**Status:**` line of a body. In ATM-380's composite legacy body the last Status line belongs to sub-item **D8** (genuinely Completed with evidence) — ANY status write via `update`/`reopen` would corrupt D8's record. Raw SQL is forbidden (audit P3 / PC-1 bypass class). A wrong write is worse than a documented block (§11.4.101).
- **Tool defect exposed (report to the SOL-01/tooling stream):** the same last-line semantics power the column↔body desync oracle — D8's terminal line MATCHES the column, so `validate` cannot see ATM-380's top-level `In progress` desync. A §11.4.201 false-negative inside the custody tooling itself, on composite multi-Status legacy bodies. Remediation prescription: split the composite item (sub-items → own ids) or teach the engine heading-adjacent-Status semantics FIRST, then demote ATM-380.

### 3.3 The 14 impossible-sequence items (reopens>0, terminal-events=0) — statuses verified RIGHT, ledger hole documented
Re-verified live: ATM-277(4/0); ATM-346/347/349/350/351/352/353(2/0); ATM-328/329/406/610/611/SPK-609(1/0).
- **ATM-347 — reclassified NOT-impossible (audit refinement):** it carries a terminal **`Obsolete`** event (2026-07-22, `feature-removed`, nova retirement, + a complete `obsolete_details` row citing ATM-815). The audit's terminal-count included only Fixed/Implemented/Completed. Its current state is evidence-backed; only the historical pre-06-09 hole below applies.
- **The other 13:** 12 currently `Reopened`, 1 `Ready for testing` (ATM-353) — all OPEN, all consistent with live defects (three of them freshly operator-corroborated by the T2 rows). Case (b): current status RIGHT; the missing rows are the PRE-reopen terminal events (the June-09 block's terminal transitions bypassed the ledger). **NOT backfilled**, for three §11.4.6 reasons: (i) the binary has no history-append verb — every history-writing verb also changes state; (ii) raw SQL is the exact PC-1 bypass this remediation exists to close; (iii) the events' on_date/evidence would have to be invented (their `closure_date` columns are empty) — a fabricated custody row is itself a bluff. The reconstruction (git archaeology of Fixed.md per item + an engine-side `history backfill` verb) is the owed SOL-01 follow-up.
- **No blanket demotion performed:** demoting live-and-consistent `Reopened` statuses to "fix" a ledger hole would falsify current state.

### 3.4 The 52 zero-history terminal items — swept, ZERO demotions earned, trail gap documented
Instruments run (each with a control needle through the same path):
1. **PENDING-marker sweep** (`PENDING-DEVICE|PENDING-BUILD|pending device` over body_md) → **0 hits among the 52** (needle: the same LIKE instrument finds ATM-799's marker → 1). The only terminal items project-wide carrying the markers were ATM-799 (§3.1, demoted) and ATM-380 (§3.2, tool-blocked).
2. **Body-status desync sweep** (every `**Status:**` line in each body vs the terminal column) → **0 desyncs / 0 embedded non-terminal sub-statuses among the 52** (needle: the same instrument sees ATM-380's `In progress` first line).
3. **Closure-narrative sampling** of the no-evidence-marker subset (ATM-254, ATM-420, ATM-497 read in full) → substantive closure content (documented-hardware-limitation MITIGATED rationale; full forensic anchor + root cause; feature scope with implementation paths). Marker census over all 52: 12 carry `Evidence:` lines, 33 carry qa-results//docs-research/ artifact paths.
- **Disposition: all 52 = case (b)** — no contradiction detected between any item's terminal status and its own recorded closure content; the missing artifact is the LEDGER ROW (these are legacy closures that predate/bypassed the history discipline, `closure_date` empty on all 52). Backfill TOOL-BLOCKED for the same three reasons as §3.3.
- **Honest boundary (§11.4.6):** "contradiction-swept clean" is what these instruments prove. They do NOT prove each closure was genuinely device-validated (the audit's G6 source-ish-evidence concern, 30/51, stands). That question is decided by the P1/P5 candidate verdict run on the 0.0.9 artifact (BUILD+DEVICE gated), not by DB edits — demoting any of the 52 without a per-item contradiction would be a §11.4.201(1) false-positive refusal (its own bluff class).

### 3.5 Left UNKNOWN / for operator or follow-up streams
- **ATM-380** — action decision (split vs engine fix first; §3.2).
- **Pre-existing `validate` violations (NOT introduced by this work — proven by running `validate` on the pre-write backup: byte-identical output, exit 1 both sides):** ATM-434/440/441 column `Reopened` vs body `Ready for testing` (owned by the toggle-fix stream) + SPK-481 Operator-blocked unblock-choices format. Untouched — other streams own those items.
- **Ledger-backfill capability** (the §3.3/§3.4 gap): needs an engine `history backfill` verb with explicit backfill marking, or SOL-01's wiring — tracked follow-up, not silently absorbed.

## 4. Derived docs regenerated FROM the DB (§11.4.106) — ATM-840 no-truncation protocol
1. `sync db-to-md` → **TEMP dir first** (`/tmp/phase5b/export_temp/`).
2. **Containment proof:** 616/619 items' `body_md` contained **byte-identically** in the temp export; the 3 exceptions are exactly the pre-existing desync trio (ATM-434/440/441) whose ONLY delta is the exporter canonicalizing the single Status line to the column value (unified-diff proven: one line each, −9 B, zero truncation).
3. **Shrinkage proof vs the current tracked docs:** per-item section comparison → **0 shrunk, 0 missing**; grown = exactly my 3 link targets (+ the expected ATM-799 Fixed→Issues relocation, verified present-in-Issues / absent-from-Fixed).
4. Only then the REAL regeneration: `export --db docs/workable_items.db --out-issues docs/Issues.md --out-fixed docs/Fixed.md` (explicit paths per the ATM-839 false-null guard; exit 0 read via PIPESTATUS, not through a pipe) → Issues.md, Fixed.md, Issues_Summary, Fixed_Summary + HTML/DOCX/PDF for all four. Real Issues.md/Fixed.md **byte-identical** (`cmp`) to the pre-verified temp export.
5. `PRAGMA wal_checkpoint(TRUNCATE)` → 0|0|0; final `PRAGMA integrity_check` → ok.

## 5. Anti-bluff certification
- Every audit figure was re-verified from the live DB before any write (§11.4.6); one audit refinement found and recorded (ATM-347, §3.3).
- Every link/reopen/diary row cites its evidence path (mining doc / gap audit); no date, time, alias, or mechanism was invented — unrecoverable times are recorded literally UNKNOWN.
- Every absence claim above ran a control needle through the same instrument path (§11.4.201(7)(b)); one instrument trap was hit live and corrected in-session (a `validate | tail; echo $?` pipeline read TAIL's exit — re-measured with the real exit, which is 1, pre-existing).
- All writes went through the sanctioned binary; zero raw-SQL writes; zero ids deleted/renumbered; zero force-push; zero commits/pushes (conductor lands the DB atomically).
- **§11.4.224 note:** this slice is data remediation — NO new executable artifact was added (no script, gate, hook, or mutation), so no TDD ceremony was invented to appear compliant; the two tool defects found (lastBodyStatus composite-body class; the validate exit-1-with-report behavior relied on here) are handed to the tooling stream, where their fixes will carry RED-first coverage.
- `find -newermt` was not used anywhere.
