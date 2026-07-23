# Cross-project quality forensics — second corpus (claude_toolkit)

| Field | Value |
|---|---|
| Revision | 2 |
| Created | 2026-07-22T15:30:00Z |
| Last modified | 2026-07-22T16:20:00Z |
| Status | COMPLETE |
| Author | (T1/main - claude4) cross-project forensic subagent, Fable, §11.4.182 |
| Corpus | `claude_toolkit` (operator-named; a shell/JS/Go developer-tooling repo — multi-account Claude CLI orchestration + provider-alias routing. 289 commits, 2026-05-26 → 2026-07-22) — READ-ONLY analysis, git history + files only. Nothing in the corpus was edited or executed. |
| Role | Second corpus for BG-QUALITY-ROOTCAUSE: cross-project validation of the reopen/bluff root-cause hypotheses on a DIFFERENT stack (bash/JS/Go tooling vs an AOSP firmware tree) with a DIFFERENT governance shape (no tracker, no gates-until-recently). Siblings: first-corpus internal forensics + `EXTERNAL_RESEARCH.md`. |
| Anti-bluff | Every number carries its command (§11.4.6). Every reported absence carries a control needle (§11.4.201(7)(b)). `find -newermt` was not used anywhere in this analysis (known-unreliable instrument). Unanswerable questions are marked `UNKNOWN:` with what would settle them. |

---

## 0. Executive summary

1. **The recurrence signature exists in full force WITHOUT any tracker machinery.** 77 of 289 commits (26.6%) are fix-typed; **38 adjacent same-scope fix-after-fix pairs landed within 24 hours of each other** — half of all fixes were followed within a day by another fix to the same subsystem. At least **11 distinct defects took ≥2 committed attempts; median attempts per multi-attempt defect = 3; maximum = 7** (one proxy-compatibility defect consumed **six consecutive releases in ~3.5 hours**, the sixth titled "complete fix").
2. **The "released fix that did not hold" root-caused (§3):** the first fix (2026-07-21) repaired the *value* (a config pin) while the *writer* — a launch path that unconditionally persists an ephemeral proxy port into a durable config with no restore-on-exit — kept re-breaking it within hours. A release titled "fully working" shipped ~12 h before the same route was measured dead in the field. The category is **value-fix vs invariant-fix**: fixing the data a defective writer produced, instead of the writer, guarantees recurrence at the frequency of the writer's execution. Even the eventual invariant-fix needed a second commit (a concurrency hardening) **2 minutes after its release**.
3. **The control-case verdict (§4) is split, and both halves matter:** the failure *causes* (green-suite-broken-product, wrong-layer testing, value-fixes, instrument false-nulls, stale-artifact shadows) appear in full without tracker machinery — so those causes are **deeper than tracker hygiene** and the first corpus's tracker-centric explanation is **incomplete**. But tracker absence removes the recurrence *signal* entirely: this project has **no reopen counter at all** — its 7-attempt chain is visible only through git archaeology, and one provider was mis-pruned on artifact grounds with nothing to reopen. The first corpus's silent-counter finding (§11.4.214) is this corpus's limit case.
4. **Governance rules existed as prose, not seams — reproduced (§5):** anti-bluff doctrine is present in all four agent-governance files, yet the repo has **zero git hooks and zero CI** (measured, control-needled), and its "MANDATORY" release gate is bound only by a comment. The gate was created **only after** a release shipped with the whole test suite green while every router alias on the real host was bricked — the project's own in-source forensic note says so verbatim.
5. **The corpus independently re-invented the constitution's mechanisms after being burned (§7):** route-attribution evidence lines, fail-closed verdicts, restart receipts (sink-side proof), a live release gate, self-validating tests (break-the-fixture-and-assert-FAIL), a schema-versioned verification cache so "results from older, weaker logic are never replayed". Convergent evolution in an unrelated project is strong evidence those mechanisms are general engineering necessities, not first-corpus idiosyncrasies.
6. **The instrument-reliability class is pervasive (§6)** — six distinct instances in the corpus's own history (swallowed `ccr restart` failures serving the wrong provider; a test runner with silent false-greens; a BRE regex-dialect guard dropping a function; SIGPIPE aborting session resolution; a `$`-token eaten out of a commit subject by shell interpolation; a changelog "Verified" count off by 111) — **plus two instances produced live by this very analysis** (§6.7), demonstrating the class's base rate even under §11.4.201 discipline.

---

## 1. Corpus identity + why it is a valid control case

Commands for the identity facts:

```
$ git log --format='%h|%ad|%s' --date=iso-strict | wc -l        → 289 commits
$ git log --format=... | tail -1                                 → f83ef23 2026-05-26 "Init."
$ git log -1 --format=...                                        → a8fbbee 2026-07-22 (HEAD, branch main)
$ grep -c 'Auto-commit' <log>                                    → 17  (early era has no semantic subjects)
```

Tracker/guard machinery census (the control variable):

```
$ ls  →  docs/ qa-results/ exist;  NO Issues.md, NO Fixed.md, NO workable-items DB
$ ls .git/hooks/ | grep -v '\.sample$'   → empty (rc=1);  needle: 13 entries total incl. samples
$ ls -a .github → rc=2 (absent);  ls .gitlab-ci.yml → rc=2 (absent)
```

So: **no work-item tracker, no reopen counter, no commit-seam hook, no CI.** What it DOES have: a hermetic sandbox test suite (`scripts/tests/`, 30+ test files incl. self-validating fixtures), a proof-evidence directory (`scripts/tests/proof/`), governance files (CLAUDE/AGENTS/GEMINI/QWEN.md, each carrying anti-bluff content — `grep -c` → 2 mentions per file), and — since 2026-07-22 only — a release-gate script. This is exactly the shape needed to test whether the first corpus's failure modes require tracker machinery to occur, or only to be *seen*.

---

## 2. The recurrence signature measured in git

### 2.1 Aggregate numbers

| Metric | Value | Command |
|---|---|---|
| Total commits | 289 | `git log --format='%h' \| wc -l` |
| Fix-typed commits | **77 (26.6%)** | `grep -cE '\|(fix\|hotfix)[(:]' <log>` |
| Release-marked commits | 32 | `grep -icE '\|(release\|v[0-9]+\.[0-9]+\.[0-9]+)' <log>` |
| Reverts | 0 | `grep -ic revert <log>` (needle: `grep -c 'un-fossilise'` → 2 — the instrument sees the file) |
| Versioned releases v1.1.0 → v1.25.4 | ~24 in 36 days | release list, `docs(release)`/`release:` subjects |
| Fix commits touching the God-file `scripts/lib.sh` | **38 of 77 (49%)** | per-fix `git show --name-only` census |
| **Adjacent same-scope fix→fix pairs within 24 h** | **38** | awk over `(epoch, scope)` pairs from conventional-commit scopes |

Per-scope recurrence (scopes with ≥2 fixes; `within24h` = adjacent same-scope pairs <86400 s apart):

```
providers      fixes=29  within24h_pairs=17
session        fixes=7   within24h_pairs=3
toolkit        fixes=6   within24h_pairs=4
(no scope)     fixes=5   within24h_pairs=3
unify          fixes=4   within24h_pairs=3
proxy          fixes=4   within24h_pairs=2
tests          fixes=3   within24h_pairs=2
scripts/toon   fixes=2   within24h_pairs=1
llmsverifier   fixes=2   within24h_pairs=1
install        fixes=2   within24h_pairs=1
cma            fixes=2   within24h_pairs=1
```

Zero reverts + 77 fixes is itself a signature: failed fixes here are never rolled back, they are **fixed forward** — which is precisely why attempt-chains, not revert-chains, are the recurrence fingerprint in an untracked repo.

### 2.2 Named multi-attempt defect chains (manual clustering, evidence = commit subjects + dates)

| # | Defect | Attempts | Window | Chain |
|---|---|---|---|---|
| 1 | Poe proxy request/response compatibility | **7** | 06-21 21:49 → 06-22 10:28 (~13 h) | tool-format → auto-start → all aliases → gzip → `$ref` schemas → "**complete fix**" (v1.7.0) → port-ready check (v1.7.1). **Six releases in ~3.5 h (06-21 21:50 → 06-22 01:21) each titled a Poe-proxy fix.** |
| 2 | ccr binary identity + launch ("is the thing I'm launching the right binary, and did it launch") | **5** | 07-18 → 07-22 (4 days) | launch grammar → identity guard (v1.18.1) → migration marker for identity check → stale-bundled-ccr self-heal (v1.25.1) → PATH-shadowing doppelgänger resolve-by-stable-path (v1.25.2) |
| 3 | Session CWD-hook / cross-project hijack | **5** | 07-10 19:14 → 07-11 14:05 (<20 h) | v1.13.0 fix + **four same-day follow-ups** (hook in 2nd wrapper; gate when not in worktree; migration marker; migration guard) |
| 4 | helixagent endpoint / proxy-address fossil (§3) | **3 committed** (+1 in-field failure between) | 07-21 14:31 → 07-22 19:52 | value-fix → invariant-fix → concurrency harden **2 min post-release** |
| 5 | CLAUDE_BIN resolution / empty-command alias | 3 | 06-29 → 07-12 (2 weeks) | resolve across npm/brew → self-heal rc lines → self-heal in both wrappers (v1.13.2) |
| 6 | Output-token clamp | 3 | 07-18 14:20 → 07-19 02:34 | cap (v1.16.0) → clamp ≤128000 + isolate guards (same day) → test hardening (v1.18.1) |
| 7 | Test-runner false-greens | 2 | 07-19, 6 min apart | "unmask 5 hidden failures" → "harden runner against silent false-green" |
| 8 | Orphaned provider records | 2 | 07-19, 45 min apart | prune → distinguish the two orphan classes |
| 9 | toon byte-parity | 2 | 07-22 | review fix → re-review fix |
| 10 | llmsverifier auth/compat | 2 | 06-16 | auth-header patch → cohere compat + fallback |
| 11 | install rc-line hygiene | 2 | 06-29 | resolve → self-heal dangling/duplicate lines |

**≥11 distinct defects took ≥2 committed attempts. Attempt distribution {7,5,5,3,3,3,2,2,2,2,2} → median 3.** Clustering is conservative (subjects + file overlap only); the true count is a lower bound. `UNKNOWN:` recurrences inside the 17-commit "Auto-commit" era (2026-05-26 → early June) — subjects carry no information; settling it would require per-commit diff archaeology, out of proportion here.

### 2.3 Release-to-recurrence latency

| Release claim | Recurrence evidence | Latency |
|---|---|---|
| v1.25.0 (07-22 01:55) "…HelixAgent **fully working**…" | v1.25.1 (07-22 12:42): "router aliases refused to launch"; the gate's in-source forensic note: "v1.25.1 shipped with the whole sandbox suite green while **EVERY router alias on the real host was bricked**" | **~11 h** |
| v1.25.4 (07-22 19:50) "un-fossilise… (kill 502 class)" | a8fbbee (07-22 19:52) hardens the fix's own marker r-m-w against lost updates | **2 min** |
| v1.6.4 (06-21 21:50) "Poe proxy fix" | v1.6.5 (06-21 22:43) "Poe proxy fix" | **53 min** |
| v1.6.9 (06-21 23:46) | v1.7.0 (06-22 01:21) "Poe proxy **complete** fix" | 95 min |
| v1.7.0 "complete fix" | v1.7.1 (06-22 10:28) port-ready check for the same proxy | ~9 h |
| f72a756 (07-21 14:31) helixagent pin fixed | route re-fossilised in the field by 07-21 16:36Z (first-corpus DIAGNOSIS §3.4, watchdog log) | **~7 h** |

The latency distribution is **minutes-to-hours, not weeks** — meaning in this corpus recurrence was not a slow decay but an immediate consequence of fixing the wrong layer. The word "complete" appearing in the 6th attempt of a chain is the linguistic form of the same claim-vs-reality gap the first corpus measures with reopen counters.

---

## 3. Case study: the released fix that did not hold (the fossil defect)

This is the single most instructive object in the corpus: a defect **fixed, released, and measured still live in production on first touch** — reproduced in a second, independent project, with the whole causal chain recoverable from git.

### 3.1 Chronology (all timestamps +0500; commands: `git log -1 --format='%h %ad %s' <hash>`, plus the first-corpus DIAGNOSIS measurements of 2026-07-22 ~16:33–16:55)

| When | Event |
|---|---|
| 07-21 14:31 | `f72a756` **fix #1 (value-fix):** the provider pin pointed at the gateway it was supposed to route *through* (self-defeating config). Fix: repoint the stored `base_url` at the real backing server. The commit message itself documents the pre-gate era bluff: *"Before those gates existed it was badged `verified` on turns actually served by whichever provider ran last."* |
| 07-21 ~16:36Z | The launch path re-stamps the route; the durable config again names an **ephemeral proxy port** owned by an already-exited launch (first-corpus DIAGNOSIS §3.4, watchdog log census: 103 ticks on the dead route). |
| 07-22 01:55 | `5ac6a49` release v1.25.0: "…**HelixAgent fully working**…" |
| 07-22 12:42→16:33 | v1.25.1, v1.25.2, v1.25.3 — three more same-day fix-releases in the same blast radius (stale bundled binary; PATH-shadowing doppelgänger; a setting lost on generator regen). |
| 07-22 ~16:33 | **Field measurement (first corpus):** `Router.default` names `127.0.0.1:3457` — dead (curl `000`); the real backend is alive on `:18434` (curl `200`). A *second* provider (`poe`) carries the identical fossil, and its `502` had been recorded as a **provider outage** — it was pruned from a rotation list on artifact grounds. |
| 07-22 19:08 | `0382019` **fix #2 (invariant-fix):** CAS exit-repair + crash-safe stale-reap — the durable file may never outlive the ephemeral thing it names. |
| 07-22 19:50 | `18780db` release v1.25.4 "kill 502 class". |
| 07-22 19:52 | `a8fbbee` **fix #3:** hardens fix #2's own marker read-modify-write — it had a lost-update race across three un-serialised writers plus a word-split bug. Its body: the four findings came from fix #2's code review, were classified *non-blocking*, and were landed **2 minutes after the release**. |

### 3.2 Why the released fix did not hold — the root cause, stated generally

`f72a756` fixed the **data** (the stored endpoint value). The **writer** remained defective in four independent, compounding ways (all proven in the first-corpus DIAGNOSIS §§1–3 against `scripts/lib.sh`):

1. **Ephemeral-into-durable:** the launch path persisted a scan-until-free ephemeral proxy port into a durable config file. The persisted value was not even reproducible across launches, let alone valid after exit (§11.4.111's resolve-by-stable-identity violated at the *lifetime* dimension, not just the naming dimension).
2. **Unconditional overwrite, last-launcher-wins:** plain jq assignment, no guard, no restore-on-exit — the route outlives the launch by design.
3. **Swallowed failure in the apply step:** `"$_ccr" restart >/dev/null 2>&1 || true` (`lib.sh:1580`) — a refused restart leaves the *previous* provider serving **while the config file reads back correct** (the project's own CLAUDE.md documents this consequence verbatim).
4. **No seam checked the invariant:** nothing asserted "the endpoint the durable config names is currently listening" — so the fossil was invisible to every green run until an end-to-end field probe hit it.

**General law this instantiates:** *a fix that repairs the artifact a defective writer produced, without repairing the writer, has a guaranteed recurrence horizon equal to the writer's next execution.* Here the writer ran on every alias launch, so the fix held for hours. The first corpus's "fixed-but-broken-on-first-touch" items and this corpus's fossil are the same object. Corroborating same-day siblings *inside this corpus*: v1.25.3 exists because a setting introduced in v1.25.2 **did not survive the generator regen** (same class: durable intent lost to a regenerating writer), and v1.25.1 exists because a **stale built artifact** shadowed the fixed source (SOURCE ≠ ARTIFACT, §11.4.108 layer 2).

### 3.3 And the invariant-fix itself needed a fix

Fix #2 introduced a marker file maintained by read-modify-write at three call sites with no mutual exclusion; review found the lost-update race pre-release; it was classified non-blocking; the release shipped; the harden landed 120 seconds later. Two lessons, both generic: (a) **a "harden X" commit immediately after "fix X" is a silent reopen** even when no tracker exists to record it; (b) review findings on a fix's *concurrency* are not "non-blocking nits" when the fix's whole purpose is state integrity (§11.4.194's assumed-away-factor pattern, at severity one notch lower).

### 3.4 Attribution note (§11.4.6)

The task framing "fixed, released, and still broken on first touch" compresses two fixes into one: the *committed-before-the-measurement* fix that failed to hold is `f72a756` (value-fix, 07-21); `0382019`/v1.25.4 (invariant-fix) was committed ~2.5 h *after* the 16:33 field measurement and has since been live-verified (release body: "8 valid aliases PING-OK, poe fossil-cleared to real 402"). The corrected statement is stronger, not weaker: **the value-fix failed within 7 hours; a release then claimed "fully working" on top of the still-defective writer; and the field caught it before the project did.**

---

## 4. The control-case answer: do the failure modes appear WITHOUT tracker machinery?

**Yes for the causes; the tracker's absence removes only the signal. Both halves are findings.**

### 4.1 Causes present without any tracker/guard machinery (occurrence is independent of tracker hygiene)

| First-corpus failure mode | This corpus, without tracker machinery | Evidence |
|---|---|---|
| Green suite, broken product | "v1.25.1 shipped with the whole sandbox suite green while EVERY router alias on the real host was bricked. The sandbox proves wrapper LOGIC; it is structurally blind to real-host state." | The project's own forensic comment, `scripts/claude-release-gate.sh` header |
| PASS attributed to the wrong thing (evidence non-attribution) | A provider "was badged `verified` on turns actually served by whichever provider ran last" | `f72a756` commit message; CLAUDE.md route-attribution doctrine |
| Fixed-but-broken-on-first-touch | §3 in full | measured |
| SOURCE ≠ ARTIFACT shadowing | stale bundled binary (v1.25.1); emitted alias file lagging `lib.sh` (first-corpus DIAGNOSIS §8.3.5 measured the deployed artifact at 0 hits while source had 4 — control-needled) | commit subjects + DIAGNOSIS |
| Evidence-claims drift | `8e8fb96` "docs(changelog): correct test_providers.sh count 294 → 405 in v1.24.0 **Verified** section" — a released Verified-claim off by 111 | commit subject |
| Guard asserting a proxy signal | the 4-min watchdog required `GET / == 200` where the healthy service answers 404 → permanent false positive masking real outages (first-corpus DIAGNOSIS §5; fixed same day with golden-good/bad/negative-control fixtures) | measured |
| Test instrument itself bluffing | "unmask 5 hidden failures — missing summary + SIGPIPE assertions"; "harden runner against **silent false-green**" | commit subjects, 07-19 |

**Conclusion 1:** these causes are **deeper than tracker hygiene**. A project with zero tracker debt, zero unguarded-item backlog, and zero reopen statistics still produced every one of them. Any first-corpus explanation that reduces the 95%-unguarded / 52%-reopen numbers to "the tracker discipline decayed" is therefore **incomplete**: the tracker records the disease; it does not cause or cure it. The shared upstream causes visible in both corpora are (a) **testing at the wrong layer** (hermetic/sandbox/source-grep green while the deployed, real-host, runtime layer is broken), (b) **value-fixes on writer-defects**, and (c) **unreliable instruments trusted without control needles**.

### 4.2 What tracker absence does cost (the signal side)

- The 7-attempt Poe chain, the 5-attempt ccr-identity chain, and the fossil chain exist **nowhere except in git subjects**. There is no reopen counter to rank fragility, so nothing steers extra scrutiny to the empirically-most-fragile subsystems (§11.4.132(d)/§11.4.189 have no input signal here at all).
- The `poe` mis-pruning (§3.1) shows the sharper cost: a *wrong verdict about a component* was acted on (removed from a rotation) **with no item to reopen when the verdict was falsified**. In a tracked project that is a §11.4.214 link+reopen; here the correction depends entirely on someone re-deriving the whole chain — which is what the first-corpus DIAGNOSIS had to do, at full forensic cost.
- **Conclusion 2:** the first corpus's silenced-reopen-counter finding (recurrences re-entering as new ids, §11.4.214) and this corpus are two points on one axis — *degraded signal* vs *no signal*. The machinery matters for **detection, prioritisation, and correction-of-verdicts**, not for preventing the underlying defect classes. Both corpora agree on that division of labour; neither contradicts it.

### 4.3 What this corpus has INSTEAD of a tracker — and its measured limit

Release cadence is the de-facto item granularity here (~24 versioned releases in 36 days), and the changelog carries per-release "Verified" sections. The measured limits of that substitute: a Verified count was wrong by 111 until corrected post-hoc (`8e8fb96`), and a release titled "fully working" preceded a total field brick by ~11 h. **A changelog is a claims ledger, not an evidence ledger** — it has no custody chain (§11.4.146(D3)) binding a claim to a verdict artifact, which is exactly the binding whose absence the first corpus measured as 95%-unguarded.

---

## 5. Testing + governance posture: prose vs seams

### 5.1 What exists

- 30+ test files under `scripts/tests/` incl. concurrency, conformance, path-shadowing, restart-selfheal, proxy, constitution tests; a proof directory with per-leg evidence files; `run-proof.sh` (6 legs).
- Genuinely good practice present: `test_constitution.sh` **breaks its own fixture and asserts the verifier fails** (golden-bad self-validation, the §11.4.107(10) pattern, independently arrived at); the route-attribution gate **fails closed** (`# FAIL: route-unproven` when the resolved route cannot be read); the verification cache is **schema-versioned** "so results from older, weaker logic are never replayed" (the stale-oracle class, pre-empted); billing errors are classified `SKIP-QUOTA`, not FAIL (§11.4.3/§11.4.201(1) analogue).

### 5.2 What binds — measured

```
$ ls .git/hooks/ | grep -v '\.sample$'      → empty (rc=1; needle: 13 total entries)
$ ls -a .github / .gitlab-ci.yml            → absent (rc=2 both)
$ grep -rln 'release-gate' scripts/ *.md    → the gate's own file, README.md, CHANGELOG.md — no calling seam
```

**Nothing mechanically binds any of it.** The suite runs when a human runs it. The release gate's "MANDATORY" is a comment: *"A release commit must not be made unless this gate exits 0"* — no hook, no CI, no wrapper refuses a release without a gate receipt. `UNKNOWN:` whether v1.25.4 actually ran the gate script — its release body cites live verification evidence ("8 valid aliases PING-OK"), which proves a live smoke of *some* form ran, but no gate receipt is committed; settling it would need the operator's shell history or a receipt convention that does not exist yet.

### 5.3 The hypothesis test

The first corpus's central governance hypothesis — **"the rules existed as prose consulted by agents, not conditions checked by seams, and therefore did not bind"** (§11.4.205's forensic shape) — is **reproduced exactly** here:

- Anti-bluff doctrine is present in all four governance files (measured: 2 mentions each; CLAUDE.md carries a full page of route-attribution doctrine) — and v1.25.1 still shipped bricked with everything green.
- The seam (release gate) was created **only after** the incident, on 2026-07-22 (v1.25.2), with the incident written into its header as justification — the same rule-follows-forensics pattern by which the first corpus's constitution grew every one of its anchors.
- Critical nuance the corpus adds: **test quantity and even test quality were not the gap** — the suite was extensive and partly self-validating. The gap was *layer* (hermetic sandbox vs real host) and *binding* (nothing refused the release). This sharpens the universal claim: prose→seam conversion and layer-completeness (§11.4.108's four layers) are the load-bearing variables; adding more same-layer tests is not.

---

## 6. Instrument-reliability class instances

The task's standing observation — most false findings have the shape *"a token that mentions X matched as X, or an instrument's silence was read as data"* (§11.4.201(6)-(8)) — is confirmed at high base rate in this corpus:

1. **Swallowed exit status with a serving-traffic consequence:** `scripts/lib.sh:1580` — `"$_ccr" restart >/dev/null 2>&1 || true`. The project's own CLAUDE.md: a genuinely refused restart "leaves the previous provider serving **while the file reads back correct**". `|| true` census: **77 in `lib.sh` alone** (`grep -c '|| true' scripts/lib.sh`; 16 more in `claude-providers.sh`).
2. **The exporter adapter soft-fail sweep:** `scripts/install.sh:176` — `"$LIB_DIR/claude-export-docs.sh" || cma_warn "doc export failed (continuing)"` — the exporter is run with **no arguments** (its whole default corpus) and any failure is downgraded to a warning; a broken export is indistinguishable from a green install.
3. **The test runner itself produced false-greens:** two commits on 07-19 ("unmask 5 hidden failures — missing summary + SIGPIPE assertions", "harden runner against silent false-green") — i.e. for some prior window, an unknown number of suite runs were green-by-instrument-defect. `UNKNOWN:` how many releases that window covers; settling it needs the runner defect's introduction commit bisected against release dates.
4. **Regex-dialect loss:** `fix(migration): cma_run dropped by BRE empty-group \(\) guard` (06-29) — a BRE/ERE dialect artifact silently dropped a function during migration (the §11.4.201(7)(c) "the path is part of the instrument" class, verbatim).
5. **Pipeline-exit semantics:** `fix(session): add || true guard on head -1 pipeline to prevent pipefail SIGPIPE from aborting session resolution` (07-17) — SIGPIPE + `pipefail` aborting a healthy path; note this fix is the *correct* use of `|| true`, illustrating that the class is about **knowing which status is load-bearing**, not about banning the construct.
6. **A token eaten out of a commit subject by the shell:** `24cdb33` reads "resolve  in tool schemas for Grok-4" — `cat -A` proves a double space where a `$`-prefixed JSON-schema keyword (`$ref`) was interpolated away inside double quotes at commit time. Even the repo's *history* carries interpolation loss.
7. **Two live instances produced by this analysis itself** (recorded per §11.4.6 because they demonstrate the base rate): (a) an `&&`-chained probe of `.git/hooks` returned a **false null** — the empty `grep -v sample` result short-circuited the chain and silently skipped the CI checks; re-measured with `;`-separated commands and explicit rc echoes. (b) an `awk -F'|'` field split on the git log **truncated every subject containing `||`** — the fix-list initially showed commit `1475814` as "fix(session): add " because its subject contains `|| true`; the delimiter was a carrier. Both were caught by needling, neither reached a conclusion — but both were one unchecked step away from a wrong reported absence.

**Generalisation this corpus supports:** in shell-based tooling the instrument-defect base rate is high enough that *any* zero/absence result not control-needled should be treated as unmeasured (§11.4.201(7)(b) as a hard floor, not a nicety) — and delimiter/dialect/exit-status layers must be enumerated as part of the instrument, because every one of the six historical instances above returned a clean, confident, wrong answer without crashing.

---

## 7. Contradictions and confirmations vs the first-corpus findings

### 7.1 Confirmations (independent reproduction)

1. **Reopen-without-tracker:** recurrence chains (median 3, max 7 attempts) exist in a tracker-less project; recurrence is a property of *fix methodology* (value-fix vs invariant-fix; wrong-layer validation), not of tracker bookkeeping.
2. **Green-run-on-broken-product:** reproduced verbatim, in the project's own words, without any of the first corpus's scale factors (no 300 GB tree, no device fleet, no multi-agent parallelism) — ruling out "project scale/complexity" as the necessary cause.
3. **Prose-not-seams:** reproduced (§5.3), including the rule-follows-forensics growth pattern.
4. **Instrument unreliability as a first-class defect source:** six historical + two live instances (§6).
5. **Stale-artifact/DEPLOYED-layer gap (§11.4.108):** three independent same-day instances (stale bundled binary; regen-lost setting; emitted-alias lag).
6. **Convergent evolution of the countermeasures:** route-attribution evidence lines, restart receipts, fail-closed unknowns, live release gate, golden-bad self-validation, schema-versioned oracle cache, SKIP-vs-FAIL classification — each independently invented here after an incident. The constitution's mechanisms are re-derivable from first principles by an unrelated project under the same failure pressure — the strongest available evidence of their universality.

### 7.2 Contradictions / corrections to the first-corpus framing (the valuable part)

1. **The tracker-centric causal story is incomplete.** The first corpus's headline numbers (95% of done-claims unguarded; 52% reopen rate) invite the reading "the tracker/guard machinery decayed, hence the bluff". This corpus falsifies the sufficiency of that reading: with **no** machinery to decay, the same causes fire at the same or higher frequency. The machinery's proven role is *signal and custody* (detection, prioritisation, verdict-correction), not prevention. Constitution consequence: anchors that only tighten tracker bookkeeping attack the symptom ledger; the prevention load rests on §11.4.108 (layer completeness), §11.4.201 (instrument integrity), §11.4.146(D3) (custody), and the writer-vs-value distinction (§7.3 below).
2. **"Fix committed" is the wrong unit of progress in both corpora, but this corpus shows it *quantitatively*:** half of all fixes were followed by another same-scope fix within 24 h. A "fix" is, empirically, a ~50%-probability hypothesis until it survives its first day in the field. First-corpus processes that mark items terminal on fix-commit + same-session green are calibrated against a coin flip.
3. **Small-project null result:** none of the first corpus's environmental suspects (host memory pressure, multi-track contention, submodule topology, agent crashes) are present here — yet the defect classes are. Environmental hardening (§12.x family) is therefore *not* the lever for this class, and forensics that stop at an environmental cause for a recurrence should be treated as incomplete (§11.4.102 four-phase arc must reach the writer/layer/instrument question).

### 7.3 Candidate universal rule distilled from this corpus (for the conductor's synthesis; NOT landed as an anchor here)

*Writer-repair rule:* when a defect consists of wrong **state** (config value, generated artifact, cache entry, route, marker), the fix is not the corrected state — it is the repaired **writer** plus the corrected state, plus a seam that asserts the invariant the state must satisfy ("the durable never outlives the ephemeral it names"; "the generated always carries the declared"). A state-only fix MUST be classified as a mitigation with a recurrence horizon equal to the writer's next run. Evidence: §3 (fossil, ~7 h horizon), v1.25.3 (regen loss, same-day horizon), v1.25.1 (stale artifact), plus the first corpus's fixed-but-broken batch. This composes with, but is not stated by, §11.4.108 (which spans layers of one artifact's pipeline; this spans *repetitions of the writer over time*).

---

## 8. Honest boundaries (§11.4.6)

1. **Clustering subjectivity:** §2.2's 11 chains come from manual clustering of commit subjects + file overlap. The mechanical adjacency metric (38 same-scope <24 h pairs) is fully reproducible; the chain count is a conservative lower bound, not an exact census.
2. **Scope-token granularity:** conventional-commit scopes are coarse (`providers` covers many features), so `within24h_pairs=17` for that scope over-counts *unrelated* adjacent fixes and under-counts cross-scope recurrences of one defect. The two metrics (mechanical + manual) bracket the truth from opposite sides.
3. **`UNKNOWN:` items** — carried inline: gate execution for v1.25.4 (§5.2); false-green runner exposure window (§6.3); Auto-commit-era recurrences (§2.2); and, inherited from the first-corpus DIAGNOSIS, the identity of the process that performed the 16:33 fossil-stamping launch.
4. **Survivorship:** git shows only defects that received fix commits. Defects observed but never fixed, or never observed, are invisible to every number here; nothing in this report estimates their volume.
5. **One-project control:** this is a single control case. It falsifies the *sufficiency* of the tracker-decay explanation; it cannot by itself establish frequency distributions across the population of projects — that is the external-literature sibling's job.
6. **Read-only compliance:** no file in the corpus was modified; no corpus script was executed; all evidence is from `git log/show/grep`, `ls`, `stat`, `cat -A`, `head`, `wc`, `awk` over read paths. The two in-flight uncommitted work streams in the corpus working tree (`scripts/lib.sh` anti-fossil deploy state, `scripts/toon/*`) were left untouched (`git status --porcelain` observed, not altered).
7. **`find -newermt`** was not used anywhere in this analysis.
