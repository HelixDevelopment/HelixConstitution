## [ATM-248] D11 — VideoOutputManager service binding regression — `Completed (→ Fixed.md)` (Phase 30d / Fix #126c, RECLASSIFIED test-logic bug, 2026-05-30 burn-down migration)

**Status:** Completed (→ Fixed.md) — RESOLVED — Phase 30d (Fix #126c). **Was a TEST LOGIC BUG, NOT a product defect.**
**Type:** Task

**Original captured evidence:** D2 `test_all_fixes.sh` Phase 4 sub-test B2 reported verbatim:

> `[FAIL] B2: hook fired but VideoOutputManager never bound — service wiring broken`

**Initial wrong hypothesis:** that the framework's MediaCodec.configure hook fires but the bind to the VideoOutputManager AIDL service silently fails — implying real product wiring regression.

**Actual root cause (found by Phase 30d systematic-debugging investigation of the MediaCodec.java source):**

`MediaCodec.java` line 2559 emits the `ATMOSphere: video decoder configure` log line UNCONDITIONALLY for every video MIME, BEFORE checking whether VOM has a secondary display, before checking codec name, before checking video dimensions. There are **3 legitimate code paths through the hook where HOOK_HITS fires but `registerVideoDecoder` is NEVER called by design**:

  - (a) `vom.hasSecondaryDisplay() == false` — emits "ATMOSphere: No secondary display" log, returns early. Correct behavior on no-TV setups.
  - (b) `codecName.startsWith("c2.rk.")` — emits "ATMOSphere: Rejecting HW codec" log, sets `forceSwFallback`. ExoPlayer retries with SW codec which DOES reach VOM.
  - (c) `minDim < 200` — silent thumbnail filter. Correct behavior.

D2's Phase 4 captured evidence corroborates path (a):
- `WARN: 1.2: Secondary HDMI-A-1 is disconnected (no secondary display)` — D2 had no TV connected
- `B1 PASS: hook fired 2 time(s)` — hook reached line 2559
- `B3 PASS: routing decision logged 2 time(s)` — log went down a routing-decision branch (in this case, "ATMOSphere: No secondary display")
- `B2 FAIL` — bug in the test: it didn't account for the legitimate no-VOM-call branches

**Fix #126c (Phase 30d):** B2 sub-test in `test_witness_mediacodec_hook.sh` rewritten to grep for `NO_SECONDARY_HITS` ("ATMOSphere: No secondary display" log) and `HW_REJECT_HITS` ("ATMOSphere: Rejecting HW codec" log). Logic flow:

  - VOM_HITS ≥ 1 → PASS (VOM was called).
  - HOOK_HITS ≥ 1 AND NO_SECONDARY_HITS ≥ 1 → SKIP (legitimate no-VOM-call: no TV).
  - HOOK_HITS ≥ 1 AND HW_REJECT_HITS ≥ 1 → SKIP (legitimate no-VOM-call: HW codec → SW fallback retry).
  - HOOK_HITS ≥ 1 (no other branch) → FAIL with refined message "hook reached registerVideoDecoder branch but VOM never logged" + diagnostic packet (genuine service-wiring failure case).
  - HOOK_HITS == 0 → SKIP (covered by B1).

**Captured-evidence locks against regression:** `scripts/testing/test_d11_diagnostic_capture.sh` — 10 invariants now (was 7); pre-build gate `CM-D11-DIAGNOSTIC` covers it; paired mutation in `meta_test_false_positive_proof.sh`.

**Lesson learned:** the §11.4 covenant cuts both ways. A test that incorrectly fires FAIL on a legitimate code path is itself a §11.4 violation — it produces a false-failure signal that masks real signal AND obscures the device's real working state. The Phase 30d investigation surfaced this exact pattern: D11 looked like a real product defect but was actually the test framework lying about the device. Systematic debugging (Phase 1 root-cause investigation) found the truth in 30 minutes by tracing the actual code; the wrong-hypothesis Phase 30c diagnostic enhancement would have wasted next cycle's investigation time chasing a non-existent service-wiring bug.

**Migration note (2026-05-30, §11.4.19 atomic move):** migrated from Issues.md §H region. Type = Task (test-logic correction) → terminal vocab `Completed (→ Fixed.md)` per §11.4.33. ATM-248 assigned at migration (item had no prior ATM-NNN). Distinct from the Phase 25.4 audit-summary D11 bookkeeping entry (ATM-249) — same legacy "D11" label, different items.

---

