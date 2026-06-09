# terse_output_guidance.md — §11.4.141 Measure M5 (output-token reduction)

| Field | Value |
|---|---|
| Revision | 1 |
| Last modified | 2026-06-09T00:00:00Z |
| Status | active |
| Authority | constitution submodule, universal (§11.4.17). Measure **M5** of §11.4.141 — output is ~5× input price, so terseness is cost-leveraged. |

> **Reusable instruction snippet.** Paste verbatim into a subagent dispatch / system
> instruction / agent-config to apply the §11.4.141 low-effort, concise-output discipline.
> **Presentation-only** — captured-evidence artefacts (§11.4.5/§11.4.69) are UNCHANGED; only
> the conductor's narration shrinks. `effort: "low"` is confined to the **mechanical**
> allowlist (§11.4.141 M2 / `subagent_model_tiering.md`) so **no reasoning / verdict path is
> degraded**.

---

## The snippet (paste verbatim)

```text
OUTPUT DISCIPLINE (§11.4.141 M5 — terse, cost-leveraged; presentation-only):
- Be concise. One line per milestone; no restatement of unchanged governance or rules.
- Do NOT echo file contents you only read; cite path:line instead.
- Final report: only what the caller needs to act — paths (absolute), the load-bearing
  facts, and the verdict. No recap of code you merely read.
- Structured output (JSON/TSV) wherever a sink consumes it — never prose a machine will parse.
- effort:"low" applies ONLY to mechanical work (search / grep / status / doc-export / parse /
  file-presence — the §11.4.141 M2 mechanical allowlist). NEVER lower effort on a
  reasoning / fix-design / code-review / verdict path.
- Terseness changes the NARRATION, never the EVIDENCE: every PASS still cites its captured
  artefact (§11.4.5 / §11.4.69); ab_pass_with_evidence is unchanged; no analysis is dropped.
- No emojis. No filler ("Sure!", "Great question", "Let me…"). State the result.
```

---

## Why it cannot lower quality

| Concern | Why M5 is safe |
|---|---|
| "Less output → less rigour?" | Output is *narration*. Evidence is captured to disk regardless (§11.4.5/§11.4.69). |
| "effort:low → weaker reasoning?" | `effort:low` is mechanical-only (M2 allowlist). Reasoning/verdict paths keep full effort. |
| "Could it drop a PASS's evidence?" | No — `ab_pass_with_evidence` and the captured-artefact requirement are untouched; a terse PASS still cites its artefact path. |

A config that suppresses *evidence capture* (not just narration) is the violation the §1.1
mutation exploits (the feature test's evidence assertion FAILs).

---

## Decoupling / reuse (§11.4.28)

The snippet names no project, package, model id, or path. Any consuming project pastes it
into its own dispatch flow as-is.

## Cross-references
- §11.4.141 (M5) · §11.4.141 M2 / `subagent_model_tiering.md` (the mechanical allowlist that
  bounds `effort:low`) · §11.4.5 / §11.4.69 (evidence unchanged) · §1.1 (suppress-evidence
  mutation) · §11.4.6 (no-guessing — state results, don't hedge).
