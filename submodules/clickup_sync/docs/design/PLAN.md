# clickup_sync — Phased Plan

**Revision:** 1
**Last modified:** 2026-06-09T00:00:00Z
**Status:** PLAN ONLY (Phase 0). No phase below is executed by this document. Effort estimates are honest rough orders-of-magnitude, NOT commitments — this is a multi-day initiative.
**Authority:** Operator mandate (ClickUp bidirectional-sync). Companion to `DESIGN.md`.

---

## Honest framing (§11.4.6)

This is **multi-day** work. Each phase ships its own 4-layer test gate per
§11.4.4(b): pre-build/CI gate + autonomous test + paired §1.1 meta-test
mutation + (where user-visible) HelixQA Challenge. NO phase advances until
its predecessor is green. EVERY ClickUp-touching step defaults to
`--dry-run`; the FIRST real ClickUp write happens ONLY in P9, and only
after operator authorization. The §11.4.28-vs-operator-convention placement
(`DESIGN.md` §1.4) is a **P1 BLOCKING operator decision** (§11.4.66).

| Effort key | meaning |
|---|---|
| S | ≤ half a day | M | ~1 day | L | 2–3 days | XL | 3+ days |

---

## P0 — Research [DONE / PARTIAL]

ClickUp API surface (REST endpoints, custom-statuses/types/tags model,
webhook events + signature, rate limits), conflict-resolution patterns.
**STATE (FACT):** the research subagent's `RISK_ANALYSIS.md` + webhook
findings are NOT present in this worktree
(`docs/research/` empty). The architecture is research-independent (all
ClickUp constants are config-injected, `PENDING_RESEARCH:`), but the
concrete event names / rate-limit numbers / custom-field-type ids MUST be
landed (re-run the research pass + commit `docs/research/RISK_ANALYSIS.md`)
**before P3 init-sync and P5 webhooks**. — Effort: S (re-confirm) · Gate:
research doc present + cites sources.

## P1 — Repo + scaffold + IDs
Create `clickup_sync` PUBLIC repo (vasic-digital, GitHub+GitLab), Go module
scaffold, `helix-deps.yaml`, `.gitignore`, `upstreams/` recipes,
README/CLAUDE/AGENTS/QWEN + md/html/pdf/docx exports, the `clickup_sync.yaml`
config schema + `config.Detect()` no-op guard (§9 guard). **BLOCKING
operator decision (§11.4.66):** Option A (nested) vs Option B (root +
by-reference) per `DESIGN.md` §1.4 — recommend B. — Effort: M · Gate:
`config.Detect()` unit test (env-unset → clean exit 0) + paired mutation.

## P2 — Read-only pull + DB-mirror
`pull` (ClickUp → DB) read-only on ClickUp; the `clickup_binding` table
(additive, in `docs/workable_items.db`); canonical-mapper unit tests. NO
ClickUp writes. — Effort: L · Gate: integration pull→assert canonical
equality (sandbox fixture) + binding-table round-trip + paired mutation.

## P3 — Dry-run init-sync + status/type/label mirror
`init-sync --dry-run` prints the status-set/type/column-ORDER/label diff;
`--apply` (sandbox list only) + the result-validation re-read asserting our
System's order. Requires P0 research landed. — Effort: L · Gate: dry-run
plan correctness + apply→validate on sandbox + paired mutation (wrong column
order → validation FAILs).

## P4 — push + conflict-resolution
`push` (DB/docs → ClickUp, sandbox); the echo-guard (`helix_sync_rev`); the
§3.2 `resolve()` algorithm; `bidirectional` single-pass; idempotency +
SQLite-txn atomicity. — Effort: XL · Gate: resolve()-truth-table unit
(paired-mutation cell-flip) + e2e push→edit-clickup→pull + concurrent-edit
true-conflict → operator-block (no data loss).

## P5 — webhook + cron
`webhook-serve` (signature-verify, dedupe, SSRF-hardened, echo-guard) +
`self-sync` systemd-timer/cron backstop. Requires P0 webhook findings. —
Effort: L · Gate: signed-event integration + SSRF security test
(paired-mutation: drop guard → test FAILs) + replay-dedupe + cron sweep
repairs injected drift.

## P6 — Deleted-doc class + DOCX export
The `Deleted` status (constitution §11.4.26 + §11.4.66 operator-gated
status-CHECK change), `Deleted.md`/`Deleted_Summary.md`, `## Deleted` bottom
sections, docs_chain PR-DC-1 (DOCX) + PR-DC-2 (Deleted class). Four-format
export Issues/Fixed/Deleted. — Effort: L · Gate: delete-anywhere →
Deleted-everywhere e2e + four-format export freshness + paired mutation.

## P7 — full bidirectional + reconcile
`reconcile` full-sweep backstop; complete `bidirectional` over the full item
set; the §3.3 transactional/replay guarantees end-to-end. — Effort: L ·
Gate: reconcile repairs every injected-drift class + idempotent-replay +
paired mutation.

## P8 — 100% tests + HelixQA
Complete the §7 matrix (unit/integration/e2e/stress/chaos/security/perf) +
the `clickup-sync` Challenge bank entry + an autonomous HelixQA session +
the `clickup-sync` skill + MCP server. All anti-bluff captured evidence. —
Effort: XL · Gate: full matrix green on sandbox + every gate paired-mutation
FAILs on negation + HelixQA `result.json` PASS.

## P9 — initial real sync both directions
FIRST real (non-dry-run) production sync — operator-authorized only. Pre-op
§9.2 hardlinked DB backup; `init-sync --apply` on the real list; one
supervised `bidirectional`; then `self-sync` cron enabled. — Effort: M ·
Gate: post-sync reconcile reports zero drift + captured evidence + operator
sign-off.

---

## Per-phase 4-layer gate template (§11.4.4(b))

1. pre-build/CI gate (config/contract assertions, SKIP-with-reason when
   `CLICKUP_*` unset per §11.4.96).
2. autonomous test (unit/integration/e2e against sandbox/fixture, captured
   evidence under `qa-results/clickup_sync/<run-id>/`).
3. paired §1.1 meta-test mutation (negate the invariant → gate FAILs).
4. HelixQA Challenge (P8+, user-visible surface).

NO force-push at any phase (§11.4.113). Every commit multi-upstream
(§2.1). docs four-format-synced (§11.4.65 + DOCX).
