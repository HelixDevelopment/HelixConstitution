# Cross-Project Forensics — Corpus 3: `helix_code` (+ 224 recursive submodules)

| Field | Value |
|---|---|
| Revision | 2 |
| Created | 2026-07-22 |
| Status | COMPLETE — all phases landed (classification / tracker / root git / fleet / synthesis / UNKNOWN ledger) |
| Corpus | `/home/milos/Factory/projects/tools_and_research/helix_code` (READ-ONLY) |
| Analyst | Fable subagent (T1/main - claude4), BG-QUALITY-ROOTCAUSE third corpus |
| Companion table | `helix_code_repo_classification.tsv` (full 224-row classification) |

**Purpose.** Third corpus in the cross-project quality root-cause research. ATMOSphere (corpus 1) has full tracker machinery and shows ~52% reopen-per-fix + 95% of done-claims unguarded. `claude_toolkit` (corpus 2) has NO tracker machinery. `helix_code` HAS the full machinery (`docs/Issues.md`, `docs/Fixed.md`, `docs/workable_items.db`, `docs/requests/`, CLAUDE.md governance) — so it is the natural experiment: **does having the machinery change the numbers?**

Every number in this document carries the command that produced it. Absences are control-needled per §11.4.201(7)(b). Unreadable repos are reported `UNKNOWN:` with reason, never silently absorbed.

---

## 0. Corpus verification (measured, not trusted)

```
$ git rev-parse --abbrev-ref HEAD            → main
$ git rev-list --count HEAD                  → 2611
$ git log -1 --format='%H %ci'               → 9b0b9a3ed3e 2026-07-22 01:58:17 +0500
$ git config --file .gitmodules --get-regexp '^submodule\..*\.path$' | wc -l  → 130 declared
$ git submodule status --recursive | wc -l   → 224 recursive
```

All four dispatch-time figures reproduce.

### 0.1 First finding — author-identity collapse (root repo)

```
$ git log --format='%ae|%an' | sort | uniq -c | sort -rn
   2320 test@example.com|Test User
    215 i@mvasic.ru|Milos Vasic
     58 ai-agent@helixdevelopment.local|HelixCode Agent
     13 i@mvasic.ru|Милош Васић
      2 i@mvasic.ru|Милош Васић 🇷🇸 🇷🇺
      1 milos85vasic.3rd@gmail.com|Test User
      1 milos85vasic.2nd@gmail.com|Test User
      1 milos85vasic.2nd@gmail.com|Milos Vasic
```

**89% of root-repo commits (2,320/2,611) are authored under the placeholder identity `test@example.com` / "Test User".** Implication for THIS analysis: per-author attribution inside our own repos is unusable; "our commits" in third-party submodules must be detected by remote-ref divergence + identity-set match, not by author alone. Implication for governance: commit attribution (who/which agent/which track authored a change) is unrecoverable from `git log` in this corpus — an §11.4.208-class ledger cannot be reconstructed from git here.

---


## 1. Classification of all 224 recursive submodules

Full table: [`helix_code_repo_classification.tsv`](helix_code_repo_classification.tsv) (224 rows + header; columns: path, remote_url, org_class, total_commits, local_only_commits, our_identity_commits, testuser_commits, class).

Method (per repo, all read-only):
```
url   = git -C <p> config --get remote.origin.url
total = git -C <p> rev-list --count HEAD
local = git -C <p> rev-list --count HEAD --not --remotes     # commits on HEAD not on any remote ref
ours  = git -C <p> log --format='%ae' | grep -ciE 'mvasic|milos85vasic|helixdevelopment'
tu    = git -C <p> log --format='%ae' | grep -ci '^test@example.com$'
```
Class rules: our-org remote + (ours>0 or testuser>0) → **OURS_DEVELOPED**; our-org remote + zero of our commits → **OURS_FORK_MIRROR** (a fork of upstream vendored under our org, carrying only upstream history); third-party remote → **THIRD_PARTY_VENDORED**.

| Class | Count | Meaning for this analysis |
|---|---|---|
| OURS_DEVELOPED | **77** | Our development happened here → deep pass |
| OURS_FORK_MIRROR | **48** | Fork under our org, **0 our-identity + 0 local-only commits** — only upstream history; CANNOT exhibit our reopen pattern (fact, per-repo verifiable in the TSV) |
| THIRD_PARTY_VENDORED | **99** | Third-party remote, 0 local-only + 0 our-identity commits — other people's development cycles; CANNOT exhibit our reopen pattern |

Control needles (§11.4.201(7)(b)) proving the instruments can see:
- Identity grep: `git -C constitution log --format='%ae'` → 292× `i@mvasic.ru` (non-null through the same pipe that returned 0 for aider).
- Local-only instrument: a repo with NO remote refs would report `local_only == total` (non-zero), so a 0 can only mean "remote refs exist and cover HEAD" — verified `cli_agents/aider` has `refs/remotes/origin/{HEAD,main,debug-works}`.
- `helix_qa` shows 897 total vs 585 matched — the gap is `catalogizer-dev@localhost` (298) + `catalogizer-dev@noreply.local` (14), **also our identities** (imported Catalogizer-project history), not third-party contamination.
- `cli_agents/agent-deck` (7 test@example.com commits on a fork): verified ours by content — a 2026-02/03 `init`/`Revert`/`fix(remote): harden SSH…` cycle.

**Headline fact:** all 48 fork-mirrors — including the big ones the dispatch flagged (`aider` 13,138 commits, `codex` 7,281, `gemini-cli` 6,249, `cline` 6,091, `qwen-code` 6,124, `vtcode` 6,009) — carry ZERO commits by us and ZERO local-only commits. Every one of the 99 third-party vendored repos likewise. **Our development in this corpus lives in exactly 78 repos: the root + 77 OURS_DEVELOPED submodules.** Deep pass covers the root, the 10 dispatch-named `submodules/*` engines, the constitution + claude-toolkit chain, and batch analysis of the remaining small engine repos.

Notable inside OURS_DEVELOPED (by our-commit volume): root 2,611 · `submodules/helix_agent` 2,790 (2,760 ours) · `submodules/helix_qa` 897 · `submodules/llms_verifier` 667 · `submodules/claude-toolkit/submodules/LLMsVerifier` 646 (duplicate mount of the same engine) · `submodules/helix_llm` 421 · `submodules/challenges` 418 (mounted twice: also under claude-toolkit) · `submodules/containers` 398 (mounted twice) · constitution 292 · `submodules/claude-toolkit` 208 · `submodules/llm_provider` 182 · `submodules/vision_engine` 172 · `submodules/llm_orchestrator` 171 · `submodules/doc_processor` 160 · `submodules/security` 148 — plus ~60 smaller single-purpose engine repos (20–140 commits each).

**Duplicate-mount observation:** `challenges`, `containers`, and `LLMsVerifier`/`llms_verifier` each appear TWICE in the tree (directly under `submodules/` and again under `submodules/claude-toolkit/submodules/`) at slightly different commit counts (e.g. llms_verifier 667 vs 646) — two gitlink pointers to the same engine drifting independently; the §11.4.28(C) nested-chain carve-out surface where the §11.4.206 divergent-copies hazard lives.

## 2. Tracker mining — `docs/workable_items.db` (read-only)

DB: `docs/workable_items.db` (748 KB, mtime 2026-07-13 — 9 days older than HEAD 2026-07-22; the tracker lags the last week of commits). Companion docs: `docs/Issues.md` (4.5 KB — prefix conventions only, ZERO open items) + `docs/Fixed.md` (280 KB, 156 `##` headings).

```
sqlite3 -readonly docs/workable_items.db "SELECT COUNT(*) FROM items"                     → 344 rows
sqlite3 -readonly … "SELECT COUNT(DISTINCT atm_id) FROM items"                            → 239 distinct ids
   (PK is (atm_id, current_location, representation) — one ticket can appear as Issues-tombstone + Fixed-row + table/section forms)
Status: Fixed 166 · Implemented 95 · Completed 80 · Obsolete 3 → 344/344 TERMINAL, 0 open, 0 Reopened, 0 Operator-blocked
Type:   Bug 166 · Feature 95 · Task 83
Prefixes: HXC 152 · FIX 72 · VEN/HXV/HXA 3 each · HXQ/HXL 2 · PAN/OPS 1
```

### 2.1 The reopen record: ZERO — and how much that record is worth

```
SELECT event_type, COUNT(*) FROM item_history GROUP BY event_type
→ Updated 158 · Opened 36 · Fixed 18 · Completed 17 · Implemented 3 · Obsolete 3 · Reopened 0
```

- **Zero `Reopened` events across the entire corpus.** Control needle: the `event_type` CHECK constraint includes `'Reopened'` (schema supports it) and six other event types flow through the same query path (non-null through the same instrument) — the zero is a real record-zero, not a blind instrument.
- **The audit trail is thin, exactly the ATMOSphere pattern**: 239 distinct ids but only 36 `Opened` events and 41 terminal events (18+17+3+3) against 344 terminal status rows → **~88% of terminal statuses have NO corresponding terminal history event** ("statuses moved with zero history rows"). Consequence: had recurrences occurred and been handled informally, this table would NOT show them — the recorded zero is weak evidence on its own and MUST be cross-checked against git (§2.3, §3).

### 2.2 §11.4.214 check — did recurrences enter as NEW ids?

Fuzzy title comparison across all 239 distinct ids (difflib ratio > 0.72 on normalized titles): **exactly 1 pair** — `HXC-052` vs `HXC-053` (`background_tasks go.mod build break — capitalised replace paths` vs `conversation go.mod build break — capitalised replace path`), which are two genuinely DISTINCT instances of one defect *class* in two different submodules (the §11.4.214(4) negative-control case: same-subject, distinct items, correctly NOT merged). **No new-id-instead-of-reopen laundering is detectable at the title level in this corpus** — unlike ATMOSphere, where ≥5 recurrence chains re-entered as new ids.

### 2.3 Git cross-check — fixes dated AFTER the recorded closure

Joining `items.closure_date` against every fix-class commit mentioning the ticket id:

```
tickets with FIX commits dated AFTER their recorded closure_date: 3
  HXC-097 closed 2026-06-15 → 2026-07-09 "fix(i18n): reconcile 5 remaining HXC-097 test failures (§11.4.120)"   ← GENUINE silent reopen (24-day latency), no Reopened event recorded
  HXC-051 closed 2026-06-09 → 2026-06-17 type↔status metadata reclassification (Task→Bug)                       ← metadata repair, not defect return
  HXC-044 closed 2026-06-09 → 2026-06-16 summary-counting repair ("HXC-044 was silently dropped" from Fixed_Summary) ← doc-pipeline repair, not defect return
```

**Corrected reopen census: recorded 0 / 341 closures (0%); git-visible ≥ 1 / 341 (~0.3%).** One confirmed under-record (HXC-097) — the reopen-event discipline failed even in this corpus, but the magnitude is ~two orders below ATMOSphere's 52%.

## 3. Git-history deep pass — root repo (2,611 commits, 2026-04-27 → 2026-07-22)

- **Fix-class commits**: 328 `fix(...)`/`fix:` subjects (12.6% of all commits); 478 commits mention "fix" anywhere; **3 reverts** total.
- **Attempts-to-stick** (fix commits per ticket, for the 68 tickets referenced from fix commits): `1×: 57 tickets · 2×: 7 · 3×: 1 · 4×: 2 · 9×: 1` → **median attempts-to-stick = 1; 84% of ticketed defects fixed in a single fix commit.** The outliers are big multi-phase Tasks, not bouncing bugs: HXC-014 (stress+chaos coverage program, 9 fix commits inside a 2-day window = in-flight iteration), HXC-097 (i18n, 4 — includes the one genuine post-closure return), HXC-036 (i18n boot-wiring, 4 — one root cause, phased landing).
- **Long-gap same-scope chains** (>14 days between fix commits on the same `fix(scope)`): 18 scopes — but scope granularity is coarse (`fix(llm)` = many unrelated defects), so this is an upper bound on recurrence, not a count of it.
- **Evidence discipline inside fix commits**: of 328 fix commits, **76% reference a test**, **46% reference evidence/proof/captured/qa-results**, **29% reference a gate or paired mutation**. `docs/Fixed.md` closures carry long §11.4.102 root-cause + RED→GREEN + paired-mutation narratives with `docs/qa/<id>/` evidence paths (e.g. HXC-036: root cause proven by module-wide grep = 0 `SetTranslator` call sites; fix verified by the 3 originally-failing integration tests flipping green + a paired mutation proving the wiring is load-bearing).
- **Development-cycle shape**: entire corpus is 3 months old (first commit 2026-04-27); 5 tags, all in the first half (helixcode-v1.0.0/v1.1.0 + 3 prefixed dev tags); no external release channel. Work arrives in intense bursts (e.g. HXC-014's 9 fixes in 2 days; the 2026-05-29 round closing 5+ items in one day).

### 3.1 The i18n case — this corpus's own "tests green, feature broken" forensic

`HXC-036` (Fixed.md, 2026-05-29): 74 packages emitted raw i18n message-ID keys to users because the boot-time translator wiring was NEVER written — **unit tests passed because they asserted the Noop echo**. Surfaced only when HXC-029's §11.4.98 self-driving integration sweep hit real output. And the SAME subsystem produced the corpus's one genuine silent reopen (HXC-097, closed 2026-06-15, 5 test failures reconciled 2026-07-09). The corpus independently reproduces the ATMOSphere lesson at n=1: the defect class that bounced is the one whose original PASS was an echo-assertion (wrong-layer oracle), and the recurrence latency (24 days) matched the next full sweep, not the next use — i.e. detection waited for the next time someone LOOKED (§11.4.118).

## 4. Submodule fleet deep pass (77 OURS_DEVELOPED repos)

Batch over every OURS_DEVELOPED repo (`git -C <p> log --format='%s'` classified per repo; full per-repo rows reproducible from the classification TSV):

```
77 repos · 13,704 commits · 2,201 fix-class commits (16.1%) · 14 reverts · 14 duplicate-fix-subject groups
```

Top fix-volume repos (fixes/total): `cli_agents/agent-deck` 741/2,386 — **upstream fork history, only 2 of those fixes are ours** (needle: `git log --author=test@example.com` → 7 commits, 2 fixes — both the same `fix(remote): harden SSH…` subject landed twice within 2h on 2026-03-02, an in-flight duplicate, not a reopen) · `helix_agent` 538/2,790 (19%) · `helix_qa` 150/897 (17%) · `helix_llm` 68/421 · `llms_verifier` 65/667 · `containers` 58/398 · `challenges` 53/418 · `claude-toolkit` 53/208 · constitution 31/292. Near-zero reverts fleet-wide (14/13,704) — failed fixes are fixed FORWARD, matching corpus 2's finding that attempt-chains, not revert-chains, are the recurrence fingerprint.

### 4.1 The corpus's own natural experiment: helix_agent (untracked) vs root (tracked)

**`submodules/helix_agent` — 2,790 commits (MORE than the root repo) — has NO tracker**: no `docs/Issues.md`, no `docs/workable_items.db` (`ls` → No such file), and the root DB carries exactly **3 HXA items** for those 2,790 commits. DB coverage overall: HXC 152 + FIX 72 (legacy date-keyed pipe-table closure rows, all `representation='table'`) = 224 of 239 ids are root-scope; **all ~11,000 submodule commits map to 15 tracked items**. The zero-reopen record of §2 covers ONLY the root-repo work.

helix_agent monthly fix ratio: `2025-12: 1% → 2026-01: 7% → 02: 23% → 03: 29% → 04: 24% (249 fixes in one month) → 05: 25% → 06: 36%` — and its per-scope chains show the multi-attempt churn shape in full force, invisible to any counter:

- **`fix(debate)`: 34 fix commits across 11 distinct days spanning 2026-02-24 → 2026-04-11 (7 weeks)**, with burst-quiet-return cycles (11 on 03-18; quiet 15 days; 6 on 03-30; return 04-07, 04-11). Subjects narrate one feature repeatedly not-working for the user: "fix prompt framing … to deliver actual answers" → "pass system context … for proper answers" → "skip 4-Pass validation …, fix hallucination" → "eliminate /workspace hallucination" (same day, twice) → "intent classifier now handles conversational messages" (+8 days) → "orchestrator path also refuses empty 200 responses" (+4 days).
- **`fix(tests)`: 75 commits over 6 months** (peak 39 in 2026-04) — the tests THEMSELVES were the most-repaired artifact (the §11.4.1 test-layer-defect churn signature).
- helix_agent activity collapsed after the governance era began (105 → 36 → 14 commits/mo from May) as work moved into the tracked root repo — so **untracked-ness, pre-governance-era, and early-maturity are confounded** in this comparison and cannot be separated with this data (§11.4.6 honest boundary).

## 5. Cross-corpus synthesis — the machinery question answered on three corpora

| Measure | Corpus 1: ATMOSphere (machinery + hardware + daily manual QA) | Corpus 2: claude_toolkit (NO machinery; from sibling report `CROSS_PROJECT_CLAUDE_TOOLKIT.md`) | Corpus 3a: helix_code ROOT (machinery, governance-era) | Corpus 3b: helix_agent (same operator, NO tracker, pre-governance) |
|---|---|---|---|---|
| Fix-commit ratio | — | 26.6% (77/289) | 12.6% (328/2,611) | 19.3% (538/2,790), peak 29%/mo |
| Recorded reopen rate | 52% per recorded fix (known undercount) | no counter exists | **0 recorded / ~0.3% git-corrected (1/341)** | no counter exists |
| Multi-attempt defects | pervasive (95% of done-claims unguarded; 6/6 operator sample broken) | ≥11 chains; median 3, max 7 attempts | 11/68 ticketed defects ≥2 fix commits; **median attempts-to-stick = 1 (84% single-fix)** | subsystem chains (debate 34 attempts / 7 weeks) |
| Recurrence latency | days-to-weeks (next manual QA) | **minutes-to-hours** (next use) | 24 days — the one case landed at the NEXT SWEEP, not next use | days-to-weeks within bursts |
| Reverts | low | 0 | 3 | 0 |
| Closure evidence class | historically source-green (the discriminator's losing side) | hermetic sandbox suite | fix commits: 76% cite a test, 46% evidence/captured, 29% gate/mutation; closures cite runtime RED→GREEN + paired mutation | none recorded |

**Answer to the dispatch question ("this repo HAS the machinery — does it do better, the same, or worse?"): the tracked half does DRAMATICALLY better (~0.3% vs 52%) — but the machinery is NOT what the data says the lever is.** Three reasons, stated with their evidence:

1. **Machinery presence does not predict the rate.** Corpus 1 and corpus 3a BOTH have the full machinery (same constitution family, same DB schema, same operator) and sit two orders of magnitude apart. Corpus 2 and corpus 3b both LACK it and show the same multi-attempt churn shape as corpus 1. The 2×2 is fully populated: {machinery, no-machinery} × {high-churn, low-churn} all occur. The machinery cannot be the causal lever; this independently confirms corpus 2's Conclusion 1 (tracker = signal/custody, not prevention) from a corpus that has the machinery, where corpus 2 proved it from one that lacks it.
2. **What separates corpus 3a from corpus 1 is detection pressure + target layer + closure-evidence class.** (a) ATMOSphere ships firmware to physical devices exercised DAILY by an operator — recurrences get SEEN; helix_code root has zero external users and detection happens only when a sweep looks (its single recurrence surfaced exactly at the next sweep, 24 days later — §11.4.118: we only see what we test). **The ~0.3% is therefore an evidence-bounded FLOOR, not a proven ceiling** — "fixes stick" and "nobody re-looks" are both consistent with it, and this corpus cannot discriminate (UNKNOWN-1 below). (b) ATMOSphere's four-layer SOURCE→ARTIFACT→RUNTIME-ON-CLEAN-TARGET gap (§11.4.108) structurally does not exist for host Go binaries run in place — an entire recurrence CLASS (stale-artifact shadows, flash-to-wrong-target) is absent by construction. (c) Where corpus 3a's closures cite runtime evidence at high rate, its fixes stuck at median 1 attempt.
3. **The ATMOSphere discriminator survives, at low power, from both directions.** Corpus 1: every fix preceded by an on-target RED→GREEN flip held; every source-green fix bounced. Corpus 3a: the fix population is runtime-evidence-heavy and ~everything held (median attempts 1) — consistent, but with no variance to test WITHIN the corpus. The corpus's ONE bouncing defect family (i18n, HXC-036→HXC-097) is exactly the discriminator's predicted loser: the original PASS was a wrong-layer echo-assertion (unit tests asserting the NoopTranslator echo while users saw raw keys), and it produced BOTH the corpus's biggest fix (74 packages, wiring never written, "tests green feature broken") AND its only silent reopen. n=1, but the sign is right, and no case contradicts it.

**Constitution-relevant distillations (for the conductor's synthesis; nothing landed as an anchor here):**
- The three-corpus data assigns the prevention load to the ORACLE/DETECTION layer (§11.4.108 layer completeness, §11.4.115 RED-on-broken-artifact, §11.4.118 discovery pressure, §11.4.201 instrument integrity) and the signal/custody load to the tracker (§11.4.55/§11.4.132(d)/§11.4.189/§11.4.214) — same division of labour corpus 2 derived; corpus 3 adds the machinery-present control cell that makes it a full 2×2.
- **A zero-reopen record from a corpus without standing detection pressure is not evidence of quality** — corpus 3a's history table would have been blind to recurrences (88% of terminal statuses have no history rows; the one real reopen got no Reopened event even here, in the best-disciplined corpus). Any §11.4.132(d)/§11.4.189 ranking fed from such a DB ranks noise. The reopens-counter is only as good as (i) the event-writing seam (§11.4.205's enforced-not-advisory test fails here too) and (ii) the detection pressure feeding it.
- **Tracker scope-coverage is a distinct failure axis from tracker discipline**: corpus 3 kept an exemplary tracker for the root repo while 80% of its commit volume (the submodule fleet, including its single largest repo) ran untracked beside it. A coverage gate ("every repo in the workspace maps its work to the SSoT") is a different check from any existing anchor, which all assume the work IS in the tracker's scope.
- The author-identity collapse (89% `test@example.com`) makes git-side attribution unrecoverable — an §11.4.208-class ledger cannot be reconstructed after the fact; identity hygiene is a precondition for any future forensic of this kind.

## 6. UNKNOWN ledger (§11.4.6 — every gap left open, with what would settle it)

- `UNKNOWN-1`: whether corpus 3a's 341 closed items WORK TODAY (the analogue of ATMOSphere's 6/6-broken operator sample). Settling it requires running helix_code's own suites/HelixQA banks — forbidden here (corpus is READ-ONLY, running its scripts prohibited). Until sampled, ~0.3% is a floor under weak detection pressure, not a quality ceiling.
- `UNKNOWN-2`: recurrences inside coarse `fix(scope)` chains (18 scopes with >14-day gaps) — scope granularity cannot distinguish distinct defects from returns; settling needs per-commit diff clustering (out of proportion; the ticket-level join in §2.3 is the higher-precision instrument and found 1).
- `UNKNOWN-3`: the tracked-vs-untracked effect size in §4.1 is confounded with governance-era and code-maturity (helix_agent churn peaked BEFORE the constitution existed, 2026-05-14). Not separable from this data.
- `UNKNOWN-4`: the last ~9 days of work (DB mtime 2026-07-13 vs HEAD 2026-07-22, incl. the helixllm-mode work) are not in the tracker — any item opened in that window is invisible to §2. Settling: re-run §2 after the next DB sync.
- `UNKNOWN-5`: 3 duplicate-mount engine pairs (`challenges`, `containers`, `llms_verifier`/`LLMsVerifier`) drift at different gitlink commits (667 vs 646 etc.) — whether divergent content or merely lag was not determined (read-only; a `git log A..B` between the two mounts would settle it).
- No repo in the 224 was unreadable: all 224 submodules initialized and clean (`git submodule status --recursive` flags all-space); zero `UNKNOWN` rows in the classification TSV.

*Report complete 2026-07-22. Every number above reproduces from the quoted command run read-only against `/home/milos/Factory/projects/tools_and_research/helix_code` at HEAD `9b0b9a3ed3e`.*
