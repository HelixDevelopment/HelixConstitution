# PHASE 4 — anti_bluff Submodule: Incorporation Record

| Field | Value |
|---|---|
| Revision | 1 |
| Last modified | 2026-07-23T00:00:00Z |
| Author | (T1/main - claude1) BG-QUALITY-ROOTCAUSE Phase 4 subagent, Fable, §11.4.182 |
| Mandate | Operator directive (verbatim in §0) — full incorporation via the constitution submodule, new `anti_bluff` repos under vasic-digital via GitHub + GitLab CLIs, out-of-the-box for every consumer |
| Inputs | `README.md` (this dir — 10 SOL docs + 11 POC suites, 65/65 GREEN RED-first), `../ROOT_CAUSE_ANALYSIS.md`, `../GAMECHANGERS_ANALYSIS.md`, `../TOOLING_STACK_VERIFICATION.md` |
| Classification | universal (§11.4.17) — the engine carries zero project literals; consumers supply DB path + vocabulary as DATA (§11.4.35) |

## 0. The operator's mandate (verbatim)

> "do full incorporation of everything into the Project and the System through the constitution
> Submodule to which we will add newly created Submodule (with newly created repos using GitHub
> and GitLab CLIs under vasic-digital organization)! Incorporated solution MUST WORK out of the
> box with any project which incorporates constitution Submodule as soon as they fetch and pull
> the changes and Submodule is cloned. Lets call the repo for new Submodule: anti_bluff."

## 1. What shipped (this slice — genuinely-binding, self-validated seams)

Per the honest-scope rule this is the FIRST COHERENT SLICE (the three
highest-leverage mechanisms per the measured ranking), not the whole program.
Everything not listed here is OWED (§6) — nothing un-built is claimed.

| Mechanism | Seam it binds | Shipped as | Golden-bad result (the self-validation) |
|---|---|---|---|
| **SOL-03 needled measurement primitive** | every load-bearing measurement | `lib/needle.sh` (`nq_absent` / `nq_count` / `nq_stream_contains`) | injected see-nothing grep → `INSTRUMENT-BLIND(2)`, never `CERTIFIED-ABSENT`; alternation query + literal needle → `NEEDLE-CLASS-MISMATCH(3)`; mid-line carrier does NOT satisfy an anchored query (negative control); 2 MB SIGPIPE payload read PRESENT by construction |
| **SOL-01 status custody at the DB layer** | status-write (triggers travel WITH the data — bind raw `sqlite3` writers) + build (full-table sweep) | `seams/status_custody/` (`apply_custody.sh` + templated triggers + `custody_sweep.sh`) | raw un-evidenced terminal `UPDATE` → `CUSTODY-REFUSED` (trigger abort); identical RED/GREEN fingerprints → refused (§11.4.115(F)); un-staged `Reopened` → refused; `item_history` UPDATE → refused; legacy DB flagged by sweep NAMING the item; open item NOT flagged (§11.4.201(1) negative control); empty table → `SWEEP-BLIND-OR-EMPTY(2)` never PASS |
| **SOL-04 evidence-class-at-closure** | status-write (the discriminator: runtime-vs-source at closure) | `seams/evidence_class/evidence_class_check.sh` | grep transcript wearing a runtime label → `WRONG-LAYER`; fieldless label → `SHAPE-INCOMPLETE`; artifact evidence for a user-visible defect → `CLASS-INSUFFICIENT`; source-on-source ACCEPTED (negative control — no false refusal); unreadable evidence → `BLIND(2)` |

Consumer-data surface (zero project literals, §11.4.28/§11.4.177): DB path via
`--db`, terminal vocabulary via `AB_TERMINAL_STATUSES` (suffixed literals like
`Fixed (→ Fixed.md)` proven in test case I), instrument via `SQLITE`/`NQ_GREP`.
`install.sh` with no arguments REFUSES with usage — it never guesses a
project's paths (§11.4.6). `apply_custody.sh` proves the refusal LIVE on the
target DB inside a never-committed transaction (zero residue) before reporting
success — `PROBE-REFUSED-OK` is the §11.4.108 runtime signature.

## 2. TDD + evidence trail (§11.4.224 — observed, not narrated)

1. **RED first:** all 4 test suites authored before any implementation existed;
   run captured at `test/evidence/RED_initial.txt` — 4/4 suites RED, exit 1.
2. **GREEN:** `test/evidence/GREEN_iter1.txt` + `GREEN_iter2.txt` — 4/4 suites,
   **41 checks PASS** (needle 9, custody 18, evidence-class 6, out-of-box 8),
   two iterations with IDENTICAL verdict lines and exit 0 (§11.4.50).
3. **A real defect was caught by the RED-capable suite during the build** (the
   suites are not ceremony): the first `apply_custody.sh` used a
   `sed "s\x01…"` substitution whose `\x01` is NOT a control character inside
   bash double quotes — the template marker survived, the triggers never
   landed, and 11 checks failed loudly. Fixed by replacing sed with bash
   `${var//pat/rep}` (literal replacement side — no metacharacter surface) plus
   a post-substitution needle asserting the marker is gone. This is instrument
   trap class §11.4.201(7)(c) (the path is part of the instrument), consistent
   with the ledger in `README.md` §5.2.
4. Parse-clean per §11.4.67: `bash -n` OK on all 11 scripts.

## 3. Repo creation — really created, CLI evidence (never faked)

Pre-flight control needles (§11.4.201(7)(b)): `gh auth status` → logged in as
`milos85vasic`, and the instrument proven seeing by `gh repo view
vasic-digital/continuum` → `{"name":"continuum","visibility":"PUBLIC"}`;
`glab auth status` → logged in as `milos85vasic`, `glab repo view
vasic-digital/continuum` returned the real project. Then:

| Step | Command | Result |
|---|---|---|
| GitHub create | `gh repo create vasic-digital/anti_bluff --public …` | `https://github.com/vasic-digital/anti_bluff`, rc=0 |
| GitLab create | `glab repo create vasic-digital/anti_bluff --public …` | `https://gitlab.com/vasic-digital/anti_bluff`, rc=0 |
| Read-back (a tool's success message is not proof, §11.4.200) | `gh repo view` + `glab repo view` on the NEW repo | both resolve, `PUBLIC` |
| Push | `git push origin main` (origin push-fans to both mirrors, continuum pattern) | both `[new branch] main -> main` |
| Verify-after-write | `git ls-remote` on BOTH mirrors vs local HEAD | all three = `1e193e10bfbe6653db9ad18bfadff0767710f413` |

## 4. Constitution incorporation (§11.4.26 + §11.4.28(C))

1. Fetch-first: constitution `github/main` had moved `9261537..6fd244e`
   (3 doc-harvest commits, zero file overlap with other agents' uncommitted
   work — verified by `comm` of the two file sets); integrated `--ff-only` to
   `6fd244e`.
2. `git submodule add git@github.com:vasic-digital/anti_bluff.git
   submodules/anti_bluff` — depth-1 under the §11.4.28(C) carve-out, ships
   `helix-deps.yaml` (§11.4.31), nests ZERO further own-org submodules.
3. Cloned gitlink verified at `1e193e1` (== both mirrors).
4. Staged BY NAME (`.gitmodules`, `submodules/anti_bluff`, this record) — never
   `git add -A` (§11.4.26 step 4); other agents' in-flight files untouched.
5. Constitution HEAD after the incorporation commit + per-remote push results:
   recorded in the Phase-4 final report (the commit is made after this file is
   written so its own sha cannot appear inside itself — §11.4.6).

## 5. The out-of-the-box proof (hermetic — not asserted, executed)

`test/test_out_of_box.sh` does exactly what a consumer does and nothing else:
`git clone` of the COMMITTED tree into a throwaway consumer project → one
documented command (`install.sh --db consumer.db --init`) → assertions. Result
**8/8 PASS**, run TWICE: once inside the repo's own suite, and once again FROM
THE INCORPORATED CLONE at `constitution/submodules/anti_bluff/` (the exact
artifact consumers receive):

- OB2/OB3 — one-command install succeeds; installer output carries
  `PROBE-REFUSED-OK` (live refusal on the consumer DB, zero residue).
- OB4 — **a raw `sqlite3` un-evidenced terminal write on the consumer DB is
  REFUSED** (`CUSTODY-REFUSED`): the seam binds out of the box, even for
  writers that bypass every wrapper.
- OB5 — a full-custody write lands AND the DB writes its own audit row.
- OB6/OB7/OB8 — sweep, evidence-class checker, and needle library all run from
  the clone (the checker refuses a grep-echo; the needle certifies an absence
  only with a sighted needle).

An uncommitted implementation file cannot pass this test — only the shipped
tree travels (§11.4.108 SOURCE≠ARTIFACT applied to the packaging itself).

## 6. OWED (next slices — honest register, §11.4.197 tracked follow-ups)

Proven POCs exist for every item below under `solutions/poc/`; none of them is
claimed shipped:

1. **SOL-02 coverage-aware verdict semantics at the release-tag seam** (absence
   of a verdict blocks like a FAIL; the fixture-B replay of the 61-guards/exit-0
   incident) — next by measured leverage.
2. **Stop-seam completion gate + PostToolUse detective hooks** (ghost-edit
   checksum + exit-code) — the two unoccupied runtime seams from
   GAMECHANGERS_ANALYSIS.
3. **Go-native fuzzing corpus-replay** (committed crashers re-run in every
   `go test`) — the Go component of the submodule (this slice is pure
   bash+SQL; no Gin service is needed anywhere per the gamechangers finding).
4. **Deterministic conformance** (`go-arch-lint`-style, never similarity
   scoring); SOL-05 gate ledger + implementation ratchet; SOL-06 anchor-block
   integrity; SOL-07 intake dedup + writer-repair; SOL-08 scope coverage;
   SOL-09 detection-pressure scheduler; SOL-10 MU-layer mechanics.
5. **Consumer wiring** — `CM-*` pre-build gate code invoking `custody_sweep.sh`
   / `evidence_class_check.sh` from consuming projects' suites + paired §1.1
   mutations (per §11.4.205 the wiring lands with its golden-bad in the SAME
   commit, as a separate tracked item per consumer); ATMOSphere's
   `docs/workable_items.db` adoption (schema mapping + the §11.4.66
   operator-gated legacy-backlog ratchet per SOL-01 §6.2) is deliberately NOT
   done here — the conductor owns parent-repo integration.
6. **§11.4.85 stress/chaos suites** (trigger throughput under ≥10 concurrent
   writers is UNPROVEN — stated in the README's honest boundaries), `Obsolete`
   evidence shape, adoption lint for un-needled `| grep -q` sites, four-format
   doc exports for this record.

## 7. Anti-bluff certification

- No PASS above is metadata-only: every mechanism's PASS is a captured refusal
  or acceptance OBSERVED in a real sqlite/bash execution, transcripts committed
  under `test/evidence/` in the anti_bluff repo at `1e193e1`.
- Every reported absence in this phase ran a control needle first (CLI auth
  needles, sqlite instrument needles, template-marker needle, sweep emptiness
  needle); `find -newermt` was not used anywhere.
- The repos were verified by READ-BACK and `ls-remote` fingerprint match, never
  by the creating tool's own success message.
- The out-of-box claim is made ONLY for what the hermetic test exercises
  (clone → install → custody seam binds + sibling instruments run); mechanisms
  in §6 are OWED and carry no out-of-box claim.
- RED transcripts precede the implementations (§11.4.224), and the one defect
  the suite caught mid-build (the sed substitution) is reported in §2.3, not
  hidden.
