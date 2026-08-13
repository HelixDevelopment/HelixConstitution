# Operator Complaint Mining — Corpus 4 (Claude Code session transcripts)

| Field | Value |
|---|---|
| Revision | 2 |
| Created | 2026-07-22 |
| Last modified | 2026-07-22T21:20:00Z |
| Status | COMPLETE (single-session mining pass; UNKNOWN register in §10) |
| Author | BG-SESSION-COMPLAINTS forensic mining agent (T1/main - claude4, Fable) |
| Part of | BG-QUALITY-ROOTCAUSE (see `ROOT_CAUSE_ANALYSIS.md`, corpora 1–3) |

## 0. What this corpus is and why it outranks the tracker

Corpora 1–3 measured what the **tracker recorded**. This corpus measures what the
**operator actually experienced**: the first-touch failure reports typed into
interactive agent sessions at the moment of discovery, unmediated by any tracker.
Phase 1 established that the operator-driven reopens left **no tracker events at
all** while every recorded reopen event was attributed "AI" — so the transcripts
are the primary record of the detection channel the tracker never captured.
Where complaints and tracker records disagree, the gap IS the finding.

## 1. Corpus definition (measured — every number carries its command)

- Stores: **2 unique** transcript stores.
  - `/home/milos/.claude-shared/projects/` — every per-alias
    `~/.claude-<alias>/projects` is a symlink to it (verified:
    `readlink -f` of all `/home/milos/.claude-*/projects` resolves here for
    every alias; inode check confirmed identity).
  - `/home/milos/.claude/projects/` — the default-alias store, a REAL separate
    directory (distinct inode), 52 JSONL transcripts incl.
    `-mnt-track4-atmosphere-t4`.
- Sizes: shared store 7.9 GB (`du -sh`), 486 project dirs (`ls | wc -l`),
  16,478 JSONL at full depth (`find -name '*.jsonl' | wc -l`), of which
  9,754 at depth ≤2; the deeper ones are 6,113 `subagents/*.jsonl`
  (agent-channel), `wf_*` workflow transcripts (SDK channel), and `archive/`
  real sessions (notably the pre-multi-track atmosphere path
  `-run-media-milosvasic-DATA4TB-Projects-Android-15`).
- Event schema (verified empirically on real lines, not assumed):
  one JSON event per line; operator-relevant events have `type=="user"`,
  `.message.role=="user"`, `.message.content` string (typed prompt) or array
  (tool results / blocks); `isSidechain==true` marks subagent threads whose
  "user" messages are **agent-authored**; `entrypoint` distinguishes
  `cli` (interactive operator) from `sdk-py`/`sdk-cli` (agent-spawned
  headless workers). `isMeta` marks harness-injected user events.

**Operator channel definition used throughout:** `type==user` ∧ `role==user` ∧
`entrypoint=="cli"` ∧ `isSidechain!=true` ∧ `isMeta!=true` ∧ path not under
`subagents/` ∧ text not a command/hook wrapper (`<command-`, `<bash-`,
`<local-command`, `Caveat:`, `[Request interrupted`). Everything else is the
agent channel and is excluded from complaint attribution.

## 2. Method

Streaming line-parse (never whole-file reads into context), substring pre-filter
before JSON parse, malformed lines counted and reported (never a silent zero).
Complaint detection = tiered regex battery over operator-channel prompts, with
per-occurrence negation-context checks so standing directive language
("no bluff of any kind", "no false results") does NOT count as a complaint —
only affirmative failure reports do. Credential-shaped strings redacted before
any excerpt is stored (§11.4.10). Dedup by normalized-text hash (multi-track
re-paste of the same complaint counts once per day).

Control needles (§11.4.201(7)(b)): every absence claim in this report carries a
known-present needle run through the same pipeline; see §9.

## 2.1 The recorded side of the comparison (read-only, measured 2026-07-22)

Tracker (`docs/workable_items.db`, opened `mode=ro`): 619 items; `item_history`
events: Updated 288, Opened 287, Completed 25, Obsolete 25, **Reopened 25**,
Fixed 24, Implemented 2. **All 25 Reopened events are attributed `by='AI'`**
(`SELECT by, count(*) FROM item_history WHERE event_type LIKE '%eopen%' GROUP BY by`)
— zero operator-attributed reopen events exist, confirming the Phase-1 finding
that the operator detection channel bypasses the tracker entirely. The recorded
reopens concentrate on 15 items: ATM-277 ×4 (stale paused-frame on 2nd display),
ATM-346/349/328/329 (audio output/focus), ATM-347/353 (player crashes),
ATM-350/406 (2nd-display routing), ATM-351 (MPV 4K quality), ATM-352
(subtitles on wrong display), plus 2 design-mockup tasks and 1 DB-tooling item.

Release anchors for clustering (git tags in this checkout, `git for-each-ref`):
dense tag storm 2026-04-18→04-29 (1.1.3→1.1.5 series), 05-09→05-23
(1.1.5-dev-0.0.8→14), 05-28 (1.1.6), 05-31 (1.1.7), 06-04 (1.1.8),
06-08 (1.1.9), 07-12 (1.2.0-dev-0.0.1), 07-13 (atmosphere-1.2.1-dev-0.0.4).
Known flash events not represented by tags (from the durable session record):
1.2.1-dev-0.0.7 flashed 2026-07-16; 0.0.8 built 2026-07-21. Caveat: tags are
gated on validation, so a "release delivered to the operator" is sometimes a
flash without a tag; both anchor sets are used in §5.

## 3. Results — headline numbers

Commands: pass-2 extractor `extract_op_prompts.py` (walks both stores, skips
`subagents/`, keeps `type==user ∧ role==user ∧ entrypoint==cli ∧ ¬sidechain ∧
¬meta ∧ ¬wrapper-prefix`), classifier `classify_op.py` + hand-audited
`final_classify.py`. All intermediates under `/tmp/opm/`; the deliverable is
`complaints.tsv` beside this file (91 classified rows, redacted).

| Measure | Value |
|---|---|
| JSONL files walked (both stores, full depth) | 16,555 |
| Files in operator extraction (subagent transcripts excluded) | 9,843 |
| **Operator-channel prompts (the entire real operator voice)** | **2,039** |
| Corpus time coverage (first→last operator prompt) | **2026-05-26 → 2026-07-22 (58 days)** |
| Pattern-battery raw matches (operator channel, deduped hash+day) | 83 |
| + `ISSUE:`/`BUG:`-prefixed reports the battery missed | 8 |
| **Classified complaint-candidate rows (deliverable)** | **91** |
| **Class A — verified first-touch defect reports** | **23** |
| Class B — recurrence meta-complaints ("reopened over and over") | 5 |
| Class C — verification-trust complaints ("verified docs are garbage", "flash didn't take") | 3 |
| Class D — QA-pressure / directive-context (excluded from complaint totals) | 45 |
| Class E — carrier false-positives (pasted covenant / mandate boilerplate) | 15 |
| Verification probes (operator questioning claimed verification) | 3 unique |
| Malformed JSONL lines | 0 observed in pass 2; pass 1 (aborted at ~2.3 GB) had recorded 0 to that point |

**The single most important structural fact:** the interactive operator channel
is TINY — 2,039 prompts against ~16.5k transcripts. Everything else in the
stores is agent-generated. Any mining of this corpus that does not first
isolate `entrypoint=="cli"` and strip the three junk classes (§9) measures the
agents talking to themselves, not the operator.

**Coverage truncation (load-bearing caveat):** nothing before 2026-05-26
survives in either store. The April 1.1.3→1.1.5 tag-storm era has ZERO
transcript coverage; all absence claims are bounded to the 58-day window.

## 4. Recurrence by subsystem (experienced reopen counts)

Class-A defect reports by primary subsystem (multi-tag texts take the
first-priority tag): display_ui 7, video_playback 5, subtitles 4, audio 3,
network 1, boot_flash 1, device_stability 1, other(toolkit) 1. Grouping by
DEFECT FAMILY rather than tag — the form that maps onto the tracker:

| Defect family | Operator-experienced report occasions (dated) | Tracker ids in the family (measured) | Recorded reopen events for the family |
|---|---|---|---|
| Video/subtitles routed to WRONG display (2nd-display enforcing) | ≥5: 2026-05-29 ("subtitles are still being played on 1st display"), 07-16 ×4 (ATM-787/790/792/793/794 sources), 07-17 ("first video clip … played on primary display instead of 2nd"), 07-21 ×2 (ATM-809 YouTube no picture, ATM-814 Kinopoisk) | ≥8: ATM-352, ATM-239, ATM-277, ATM-787, ATM-790, ATM-793, ATM-794, ATM-809, ATM-814 | 6 (ATM-352 ×2 on 06-09, ATM-277 ×4 on 07-09..14) — all `by='AI'` |
| Audio output switching | ≥3: 05-28 ("5.1 movies … as stereo"), 07-16 (switch dialog hangs, endless spinner), 07-17 (re-raise) | ≥7: ATM-306, ATM-346, ATM-361, ATM-451, ATM-474, ATM-789, ATM-799 | 2 (ATM-346 ×2 on 06-09); ATM-346 sits in status `Reopened` since then |
| 4K local playback glitch | 3: 05-28 (VLC/MPV compare), 06-09 (FIND-10), 07-16 (ATM-800) | ≥2: ATM-351, ATM-800 | 2 (ATM-351 ×2) |
| YouTube usable at all (cert/sign-in/playback) | 4: 05-29 ("again got same error … device is not certified"), 07-16 (sign-in as Google Pixel), 07-17, 07-21 | ≥3 ids | 0 |
| Brightness sliders ineffective on connected displays | 2: 07-16 (ATM-788), 07-21 (ATM-812 — same defect, NEW id, 5 days later) | 2 | 0 |
| exFAT USB mount | ≥2: 07-16 titled "REGRESSION: exFAT USB flash drive no longer mounts" | ≥1 (ATM-797) | 0 |

**The experienced-vs-recorded delta.** In-window the tracker holds 25 Reopened
events (= 18 distinct item-reopens; the 06-09 block double-recorded 7 items),
**100% attributed `by='AI'`**. Against that: at least **6 operator-experienced
recurrences with ZERO corresponding reopen events** — "All reported issues with
Watch here button still exist!", "Subtitles never show on 2nd display …
has not been fixed at all!!!", the 07-17 re-raises (2), ATM-797's own
"REGRESSION" title, ATM-812 duplicating ATM-788. This independently reproduces
Phase 1's "six operator-driven reopens left no tracker events" from the
opposite side of the seam — and the fate of every one of them is visible here:
**each entered the tracker as a NEW id** (PC-6 measured live at the intake
seam): the 07-16 QA burst minted ATM-786…ATM-800, the 07-21 burst minted
ATM-809…ATM-824, including exact same-defect re-mints (ATM-793 ≙ ATM-352's
defect; ATM-812 ≙ ATM-788; ATM-800 ≙ ATM-351's family). The `reopens_count`
signal of the original ids never moved.

## 5. Post-release clustering

Directly measured, first time for this project. Complaints cluster HARD on
flash/QA events, not on tag dates per se:

- **0.0.7 (flashed 2026-07-16):** QA session starts 19:42 with the very first
  touch broken — "flashed device after flashing is crashing after booting
  Android! It entered in crashing loop" — followed by **8 `ISSUE:` reports in
  32 minutes (20:50→21:22)**; 10 class-A reports on the day. The operator's
  own 07-19 summary: "Go through all 10+ ISSUES we have reported during manual
  QA testing of release 0.0.7."
- **0.0.8 (built 07-21, QA same morning):** session opens 09:45 ("We will be
  reporting issues one by one…"), **first defect at 09:57 — 12 minutes to
  first failure** (YouTube on 2nd display: sound but no picture), 3 class-A in
  32 minutes; 6 QA bug ids minted that day (ATM-809/810/812/814/818/821).
- **Old era, 1.1.6 window (05-26→29):** the raw pattern-match rate jumps from
  4.88 to 17.19 matches per 100 operator prompts across the 05-28 tag (3.5×),
  driven by the 05-28/29 manual-test session (VLC 4K glitches, 5.1-as-stereo,
  seek-freeze, subtitles-on-1st-display, YouTube-cert-again).
- Baseline across the window: 6.35 raw pattern matches per 100 operator
  prompts (65/1024 atmosphere-family); class-A reports concentrate ~90% within
  hours of a flash/QA event. **"Broken on first touch" is not a feeling — it
  is 12 minutes (0.0.8) and 0 minutes (0.0.7 crash-on-boot) measured.**
- Empty windows around the May-09/20/23 and 06-04/08 anchors are corpus
  truncation or zero-operator-activity days (denominator = 0 shown in the
  data), NOT evidence of complaint-free releases.

## 6. Complaint→fix→complaint chains (latencies)

1. **Subtitles-on-primary-display** — 05-29 complaint → FIND-5/7 → ATM-352
   reopened 06-09 → ATM-239 "In testing" → **07-16 21:02 "Subtitles never show
   on 2nd display, always on primary one!!! THis has not been fixed at
   all!!!"** (new id ATM-793) → follow-up directives 07-17. ≥3
   operator-experienced cycles over 49 days; recorded reopen events for the
   family: 2, all "AI".
2. **2nd-display routing / watch-here** — ATM-277 recorded reopen-fix cycles
   ×4 inside ONE week (07-09→14, all "AI") → operator first touch 07-16:
   "All reported issues with Watch here button still exist!" + one-way toggle
   (ATM-790/794) → 0.0.8 first touch 07-21: ATM-809 (no picture), ATM-814
   (Kinopoisk on primary). The feature failed the operator's touch in BOTH
   releases following its 4th recorded reopen; zero further reopen events.
3. **Audio output switch** — 05-28 "5.1 … as stereo" → ATM-346 reopened 06-09
   (status still `Reopened` today) → 07-16 20:50 dialog-hang ISSUE →
   unanswered → **07-17 10:28 operator re-sends the identical ISSUE as
   `REMINDER ::` on another track (13.6 h re-raise latency)** → item ATM-789
   minted 07-18 (~1.6 days complaint→item). Family spans ≥7 ids over 51 days.
4. **4K playback glitch** — 05-28 → ATM-351 reopened 06-09 → 07-16 ATM-800
   ("mechanism unconfirmed"). 49-day span, 3 occasions, 2 recorded reopens.
5. **Cross-project control (claude-toolkit v1.24.0)** — 07-20 20:07 operator
   leaves for the night ("You are on your own until the morning … Having the
   best possible, most stable build made until the mor[ning]") → **07-20 08:20
   (prior morning build) "We cant open any providers alias!"** → 07-22 06:55
   "Why helixaget … cant be even opened!?!?!?! **Wasnt all this tested before
   the release!?!**". Same first-touch shape, different project, no device
   involved — the failure mode is pipeline-generic, not RK3588-specific.

## 7. Operator-named verification-failure causes vs PC-1..PC-9

The operator's lived words map onto the forensic causes — and name two the
taxonomy does not cover:

| Operator's words (verbatim, dated) | PC mapping |
|---|---|
| "Wasnt all this tested before the release!?!" (07-22, toolkit) | **PC-2 / PC-7** — absence of verification indistinguishable from verification; guards never run where the defect lives |
| "we have not fixed something properly!" (07-16, 0.0.7 crash-loop) | **PC-3** — source/artifact green read as done |
| "its flash didn't take (came back on the old Jul-9 build)" (07-14, quoted agent admission the operator escalates) | **PC-3** at the ARTIFACT→RUNTIME seam (the §11.4.200 deploy-verify class) — validated work never reached the device |
| ATM-819 (07-21, from QA): "TEST-PIPELINE BLUFF: video-to-TV full-automation reports GREEN…" | **PC-8 / PC-5** — wrong-layer oracle certifying a user-visible property; the operator filed the pipeline itself as a bug |
| "All reported issues with Watch here button still exist!" / "has not been fixed at all!!!" (07-16) | **PC-6 + PC-3** — recurrence under new ids; re-fix never reached the operator's device in working form |
| "Documents we have verified are garbage!" (06-29) | **PC-5** family — the verifying instruments/documents themselves false |
| "All issues reopened multiple times must be fully confirmed, validated and verified during live testing!" (07-16 05:36 — BEFORE the QA that found them still broken) | **PC-1/PC-9** — the operator already distrusts terminal statuses; the same evening proves him right |

**Causes visible ONLY in this corpus (candidates to add to the taxonomy):**

- **NC-1 — External-state drift on an unchanged artifact.** "We again got same
  error message when tried to use YouTube, device is not certified …
  **Yesterday with same flashed image we used to play videos!**" (05-29). A
  delivered feature died with NO code change — server-side/device-registration
  state drift. PC-1..PC-9 are all pipeline-internal; nothing covers
  environment/external-service drift breaking a shipped feature between two
  touches. A verification regime that only re-runs at build/release seams is
  structurally blind to it (argues for the §11.4.128/§11.4.135 standing-guard
  direction: guards on a SCHEDULE, not only at seams).
- **NC-2 — Complaint intake latency/evaporation.** The audio-switch-hang
  ISSUE needed a 13.6 h `REMINDER ::` re-raise on a different track before an
  item was minted ~1.6 days after first report. The operator carries the
  retransmission burden; a session death between report and mint loses the
  report entirely (the §11.4.210 hook was un-wired precisely then — its own
  forensic anchor). Intake is a fourth loss seam alongside PC-1/2/6.
- **NC-3 — No operator-checkable liveness signal.** "I toggled the outlet,
  check 66ff9c4f, however not sure that app is working att all!" (07-16). The
  operator cannot OBSERVE whether a deployed component is alive; every check
  routes through the agent, which is exactly the party whose claims are under
  audit. Deliverables lack an independent, human-readable health surface.

**Convergence verdict:** the operator's experienced causes CONFIRM PC-2, PC-3,
PC-5, PC-6, PC-7, PC-8 independently (different instrument, same physics), add
NC-1..NC-3, and provide no evidence against any PC. PC-4 (rules-as-prose) and
PC-9 (vocabulary ambiguity) are not directly nameable by a user experiencing
failures — their fingerprints are the B/C-class complaints instead.

## 8. Cross-project comparison

Class-A defect reports by project: atmosphere family 18 (track1 12, track3 2,
Android-15 old-era 3, main-atmosphere 0 — its window predates the QA drives),
claude-toolkit 2, tmux 1, code-server 1, svord-toolkit 1, **helix-code 0,
helix-ota 0**.

- Complaints concentrate where a release is DELIVERED TO A TARGET the operator
  physically touches (device flash, toolkit alias rollout). They are absent
  where nothing was hand-touched in-window.
- **helix-code (corpus 3, ~0.3% recorded reopens):** 92 operator prompts
  in-window (denominator needled — 12 of them mention test/release/deploy),
  zero complaints through the same battery. This is consistent with BOTH
  "releases work" AND "no first-touch exercise occurred". The toolkit
  datapoint decides the interpretation: the one time a non-atmosphere
  deliverable in this corpus WAS first-touched (aliases, 07-20/22), it failed
  immediately and the operator asked "wasn't all this tested before the
  release!?". **Corpus 3's low reopen rate therefore cannot be read as quality
  evidence; it is detection-pressure-limited** — precisely the Phase-1
  hypothesis, now with a live counter-example.
- The complaint SHAPE is uniform across projects (first touch → immediate
  failure → verification-trust question); only the FREQUENCY differs, and it
  tracks operator-touch frequency, not project quality.

## 9. Control needles and instrument notes

**Instrument incidents hit DURING this mining (all §11.4.201(7) shapes, logged
as they happened):**

1. **Self-match carrier, twice in one poll.** A liveness poll
   `pgrep -f mine_complaints.py … pgrep -f extract_op_prompts` reported both
   passes RUNNING when **neither process existed** — the poll's own shell
   cmdline carried both pattern strings. Resolution: `ps -eo pid,args` with the
   real script path, per §11.4.196(D). Every process-liveness claim below was
   re-measured with the path-anchored form.
2. **Detached-orphan reaping.** Pass 1 (launched `nohup … &` inside a
   background task that exits immediately) was killed externally at ~2.3 GB
   read with no traceback on stderr — the harness reaps detached children of
   completed tasks. UNKNOWN: exact reaping trigger. Remedy applied: long
   passes run as the tracked background command itself (the §11.4.89 pattern);
   the rerun completed normally.
3. **Truncated-line JSON.** `head -c` sampling produces an unterminated-string
   parse error on the boundary line by construction — sampling switched to
   line-whole `head -n`/`jq`. Malformed-line counts in the real pass are
   reported in §3, never absorbed.
4. **Over-eager redaction as carrier.** The `sk-…` credential regex matched
   inside the literal `task-notification` (`…ta` + `sk-notification…`),
   corrupting excerpts. Fixed with a left-boundary guard
   `(?<![A-Za-z0-9])sk-`; §11.4.10 posture retained (over-redaction is the
   fail-safe direction; no credential is ever reproduced).
5. **Junk classes in the "user" role.** Three harness-generated event classes
   masquerade as user messages and dominated the naive operator channel:
   `<task-notification>` blocks (640 of 866 operator-channel matches in the
   partial pass), compaction summaries ("This session is being continued…",
   194/866), and `Caveat:` wrappers. All are excluded by prefix from both the
   numerator (complaints) and the denominator (operator prompts). A naive
   "user-role" mining of this corpus without these filters overcounts by >25×.

**Control needles:**

- N1 (corpus reach): the distinctive operator typo `documetn` (from a real
  2026-07-17 interactive directive) found by independent grep in
  `-run-media…Android-15/93f6aeeb….jsonl` and `-mnt-track1-atmosphere-t1`
  transcripts — the pipeline's project set demonstrably includes both eras.
- N2 (channel visibility): verified below in §9a after the extract pass —
  the same event found by grep must appear in the operator-prompt extract.
- N3 (pattern-battery visibility): the known 2026-07-16/17 manual-QA
  complaint sessions must surface in the complaint set; verified in §4.

**§9a — needle results (all run through the SAME pipeline path as the claims
they certify):**

- N2 PASS: the operator-typed token `documetn` (found by independent grep in
  raw transcripts) appears in the operator-prompt extract exactly once
  (`grep -c documetn op_prompts.tsv` → 1) — the extraction path sees real
  operator events end-to-end.
- N3 PASS: the known 07-16/17 manual-QA complaint sessions surface as 10 + 2
  class-A rows with verbatim excerpts (§5, §6) — the battery + ISSUE-prefix
  union sees the ground-truth channel.
- helix-code absence needled: 92 operator prompts from helix-code passed
  through the identical `hits_for()` path that produced complaints in 7 other
  projects; the zero is a measurement, not blindness (§8 carries the honest
  interpretation limit).
- Battery-miss check (the needle that FAILED and was fixed): 8 of 21
  `ISSUE:`-prefixed ground-truth reports carried NO battery pattern
  ("sign-in as Google Pixel", "brightness sliders do not affect…"), proving
  phrase-batteries alone under-count first-touch reports by ~35% — the
  deliverable unions the reporting-directive channel; any future re-run MUST
  do the same.
- Carrier subtraction verified: 13 prompts carry the pasted §11.4 covenant
  literal ("…does not work and can[']t be used"), 5 carry the multi-track
  kickoff mandate ("No change applied using su…"); all 15 are class E, none
  count as complaints. Without this subtraction the complaint count inflates
  ~18% with pure governance boilerplate.

## 10. UNKNOWNs

- **UNKNOWN: everything before 2026-05-26.** Neither store retains earlier
  transcripts; the April tag-storm era (14 tags in 12 days) has zero
  operator-voice coverage. The experienced-reopen floor measured here is
  therefore itself an undercount of the project's full history.
- **UNKNOWN: agent-channel complaint relays.** Pass 1 (which also recorded
  agent-channel matches) was killed at ~2.3 GB (§9 incident 2); its partial
  data (1,981 agent rows) was not used. How often the conductor relays
  operator complaints verbatim into worker prompts is unmeasured.
- **UNKNOWN: the exact reaping trigger** that killed the detached pass-1
  process (no traceback, no OOM evidence collected). Operationally closed by
  running long passes as tracked commands.
- **UNKNOWN: session-file duplication factor.** The same user event appears in
  multiple session files (forks/resumes — one probe event appeared 6×);
  hash+day dedup absorbs it for counts, but the per-file multiplicity was not
  quantified corpus-wide.
- **UNKNOWN: 1:1 mapping of every 0.0.7 QA utterance to a tracker id.**
  ATM-786/796/798 have no matching `ISSUE:` transcript row (relayed from
  prose or from a session fragment not captured); no loss PROVEN, but the
  complete report→item ledger for 07-16 was not established row-by-row.
- **UNKNOWN: whether helix-code deliverables work** (§8) — zero complaints is
  consistent with both readings; only a first-touch exercise decides it.
- **PENDING_FORENSICS: NC-1 scope.** How many other "worked yesterday, same
  image" failures exist is unmeasured — the battery has no pattern for
  external-state drift phrased positively; only the 05-29 instance was found
  (via `same_again`).

## 11. Deliverables and reproduction

- `complaints.tsv` (beside this file): 91 classified, redacted, deduped
  operator-channel rows — columns
  `ts, class, store, project, session, branch, patterns, strong, subsystems, hash, textlen, excerpt`.
- Class key: `A_defect_report` (verified first-touch defect), `B_recurrence_meta`,
  `C_verification_trust`, `D_qa_pressure`/`D_directive_context` (not
  complaints; context), `E_carrier_*` (false positives, retained for audit).
- Reproduction: `/tmp/opm/{extract_op_prompts.py, classify_op.py,
  final_classify.py}` (session-local; re-runnable read-only against the
  stores). Every count in this report is regenerated by those three scripts.
- §11.4.10: all excerpts passed THREE redaction layers (credential-shape,
  e-mail/`Пароль`, and a post-write high-entropy-token scrub after one `su`
  credential was found surviving the phrase-shaped regexes — found by audit,
  scrubbed, and the residual scan now shows only the benign "ri`sk-`free"
  carrier). The QA-account prompt (Qobuz) is redacted in the deliverable.

## 12. Anti-bluff certification

No count in this document is estimated: each traces to a command over the
extract or the read-only tracker DB. Absences carry needles (§9a). The two
instrument failures that occurred during the work (self-match carrier,
detached-orphan reaping) are reported in §9, not absorbed. The corpus
truncation boundary (2026-05-26) is stated wherever it bounds a claim.
Transcripts were opened READ-ONLY; nothing under `~/.claude*` was modified;
the tracker DB was opened `mode=ro`; no commit/push was performed.
