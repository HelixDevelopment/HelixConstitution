# Changelog — HelixDevelopment/HelixConstitution

## v1.0.0 — 2026-07-24 — first constitution version tag

This tag captures the constitution state at the end of the 2026-07-22→24
work round, bracketed by `helixcode-v1.1.0` (2026-07-12) and current HEAD.
**182 commits** of systematic governance codification, measurement-semantics
harvest, design-methodology round, and tooling hardening.

### Added

- **§11.4.216–223 — Design-methodology codification round (2026-07-22).**
  Eight new anchors codifying the design-methodology harvest from the
  Helix Thready MVP design: problem-first, research-before-design,
  architecture-before-components, data-first, security-by-design,
  testability-by-design, design-documentation, and iterative-design.
- **§11.4.224 — Test-first (TDD) for all work + >=85% code-coverage floor.**
  Necessary but never sufficient — coverage without runtime-evidence is a
  §11.4 bluff.
- **§11.4.225 — Measurement-semantics codification.** The distinction
  between carrier and thing, null-is-not-evidence, and the control-needle
  principle codified as mandatory rule.
- **§11.4.226 + §11.4.227 + §11.4.194(6) — Reopen / first-touch root-cause
  harvest.** Reopens now trigger a mandatory systematic-debugging pass and
  permanent regression guard; first-touch tasks are tracked to prevent
  silent re-entry.
- **§11.4.228 — Cross-agent extension lifecycle + speckit exports.**
  Defines the lifecycle for extensions shared across CLI agents and exports
  the speckit bridge documentation to all governance carrier files.
- **§11.4.115(G), §11.4.201(9)–(12), §11.4.67(6), §11.4.142-FACT** —
  Extensions from the HEL-010 systematic-debugging / measurement-semantics
  harvest of 2026-07-23.
- **Shell-instrument footgun checklist** (7 documented footguns — I1 through
  I7) encoding recurring instrument-caused failures.
- **Mechanical anti-bluff seams engine** (`submodules/anti_bluff`) —
  reusable, decoupled from any single project.
- **SpecKit-Superpowers bridge documentation** — comprehensive implementation
  guide for the constitution-powered bridge.

### Fixed

- **Credential scan (cred-scan) carrier strips #5, #6, #7.** Multiple
  false-positive carrier-identification bugs in detectors 1 and 2 patched
  (ATM-864): markdown-word heuristic, proximity-window over-match, and
  value-starts-with-reference/placeholder sigil.
- **Workable-items engine fixes:** reopen body-preservation, orphaned-bullets
  (F1), SQL index gaps (missing indexes on status/type/location/attribution),
  unbounded queries, dot-separator for non-canonical IDs.
- **SECURITY: `report_item.sh` hardened.** Replaced `eval` with `bash -c`;
  indirect expansion for credential checks.
- **Multitrack hardening:** owner-lock fix, probe-race fix, config
  alias-exclusion, conductor-slot exclusion, §11.4.201(4)/§11.4.111 PARSE
  guard.
- **Curl timeouts** added across the tooling surface.

### Docs

- Companion docs for §11.4.141 (`scoped_read.sh`, `token_efficiency_lib`,
  `context_compactor`) per §11.4.18.
- Pandoc twins regenerated for Rev 54 (§11.4.216–223 amendment).
- BG-QUALITY-ROOTCAUSE Phase 4 deliverables documented.
