## A. Tooling / harness gaps — RESOLVED

### A1. `commit_all.sh` doesn't recurse into nested submodules to commit pending pointer changes

**Status:** Fixed (→ Fixed.md)
**Type:** Bug

* **Closure cycle:** Phase 25.3 (1.1.5-dev-0.0.7).
* **Closure commit:** opt-in `--auto-cascade` flag + meta-test wired as `CM-A1-METATEST` (see commit log around 2026-04-30).
* **Captured evidence:** `test_commit_all_nested_detection.sh` Invariant 4 — asserts the flag is exposed in `--help`, default is OFF, the message-required guard is present, and the failure counter is wired (4 anti-bluff guards). Result: 5 PASS / 0 FAIL / 1 ACTION.
* **Regression-protection:** `CM-A1-METATEST` pre-build gate + paired mutation in `meta_test_false_positive_proof.sh`.
* **Migrated from Issues.md A1 on 2026-05-05.**

### A1.b. `commit_all.sh` validate_submodules() pipefail regression

**Status:** Fixed (→ Fixed.md)
**Type:** Bug

* **Closure cycle:** Phase 23.5 (1.1.5-dev-0.0.7).
* **Closure commit:** `7351a8320a0`.
* **Fix:** wrapped the inner pipeline in a subshell with `|| true` so an empty-status submodule no longer aborts the parent: `sub_dirty=$(cd "$sm_path" && (git status --porcelain 2>/dev/null | grep -vE '^\s*m\s' | head -1) || true)`. Subshell-scoped `|| true` (not outer-`$()`-scoped) lets pipefail still catch *real* git failures inside the subshell where they matter.
* **Anti-bluff lens:** this was a **success-bluff inversion** — the script ran loudly, validated all 20 submodules, declared success on each, and then died silently. The user-visible signal was indistinguishable from "script crashed for unknown reasons" but the actual content of the run was "no work done because the safety check killed itself before doing the work."
* **Captured evidence:** Phase 23.5 commit `7351a8320a0` flowed cleanly through commit_all.sh end-to-end: validate_submodules → stage_changes (1 file, +13/-9) → do_commit → push to github + vasicdigitalmirror.
* **Regression-protection:** A1's meta-test umbrella covers A1.b too — both "silently does nothing" and "loudly fails" are caught by the same harness.
* **Migrated from Issues.md A1.b on 2026-05-05.**

### A2. `SharedModules` pointer in `smarttube-player` recorded at `8cdd62b52` (stale by one commit)

**Status:** Fixed (→ Fixed.md)
**Type:** Task

* **Closure cycle:** Phase 23.3 (1.1.5-dev-0.0.7).
* **Why it persisted:** unblocked once A1 landed (was a downstream consequence of the A1 cascade gap).
* **Captured evidence:** SharedModules HEAD = `5aa4af893` (§12 Incident #2 anchor commit).
* **Migrated from Issues.md A2 on 2026-05-05.**

### A3. `test_all_fixes.sh` per-suite timeout was tight + cascaded ADB drops on SIGKILL

**Status:** Fixed (→ Fixed.md)
**Type:** Bug

* **Closure cycle:** 1.1.5-dev-0.0.7 (Phase 20.0 hardening).
* **Closure commit:** `137c0a2054e` ("single source of truth Issues.md + test_all_fixes.sh wrapper hardening, User mandate 2026-04-29").
* **Fix landed:**
  * Bumped `SUITE_TIMEOUT` 3600 → 5400 (90 min cap) in `device/rockchip/rk3588/tests/test_all_fixes.sh:68`.
  * Added `adb_recover_after_timeout()` helper at lines 70-75 that runs `adb kill-server && adb start-server` and waits for the targeted device to come back to `state=device`. Wired into both the `run_device_test` and `run_device_test_nohup` TIMEOUT branches at line 189.
* **Captured evidence:** Phase 25.2 verification confirmed both lines present and SUITE_TIMEOUT=5400. Next regression run hitting TIMEOUT will surface the recovery hook output.
* **Follow-up tracked as Bug #11 (Issues.md G7):** soft per-category timeouts to surface hangs faster than 90 min.
* **Migrated from Issues.md A3 + G3 on 2026-05-05.**

---

