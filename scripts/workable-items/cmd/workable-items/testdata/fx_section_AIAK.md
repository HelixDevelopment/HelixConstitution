## AI/AK. Phase 39.AW (2026-05-14) — D3 wired touch panel + UI scaling closure cycle

### AI. D3 wired touch panel non-functional — `Phase 39.AW + 39.AY closure, 2026-05-14`

**Status:** Fixed (→ Fixed.md)
**Type:** Bug

* **Closure cycle:** Phase 39.AW source-side + Phase 39.AY captured-evidence verification (1.1.5-dev, between 0.0.11 and pre-Sonos tag).
* **Closure commits:** source `011fcd5b15b` (Phase 39.AW source-side fix); Phase 4 verification `qa-results/d3_phase4_postflash_20260514_1649/PHASE_4_VERDICT.md`.
* **Discovery:** D3's primary touch panel was reconnected via wired-direct HDMI + 2 USB ports (operator hardware change). Touch input did NOT work despite the panel being functional via the previous wireless connection. Phase 1 captured-evidence (`qa-results/d3_phase1_forensics_20260514_1453/d3_touch_forensics_*`) via live ADB revealed the panel is `wch.cn USB2IIC_CTP_CONTROL` (USB VID `32d7` PID `0001`) — a THIRD vendor not in `atmosphere-touch-config.sh`'s hardcoded list of Nuvoton V5000 (`222a:0002`) and QDtech MPI7009 (`0712:0009`). The bridge presents 3 USB-HID interfaces (event8 mouse, event7 keyboard, event6 touch); without an IDC file at `/vendor/usr/idc/Vendor_32d7_Product_0001.idc`, Android InputManager could not reliably classify event6 as a touchscreen.
* **Source-side fix:** new `device/rockchip/rk3588/idc/Vendor_32d7_Product_0001.idc` declaring `touch.deviceType=touchScreen` + `touch.orientationAware=1` + `device.internal=1` + `cursor.mode=navigation`. `device/rockchip/rk3588/device.mk` PRODUCT_COPY_FILES entry deploys to `/vendor/usr/idc/`. `device/rockchip/rk3588/bin/atmosphere-touch-config.sh` extended with the new VID:PID dispatch to HDMI1/HDMI2 displays.
* **Phase 4 captured-evidence (post-flash, firmware UTC `1778764554`):** `getevent -lp` on event6 now reports `input props: INPUT_PROP_DIRECT` ← Android NOW classifies as direct-touch (touchscreen). Full multitouch protocol exposed: `ABS_MT_SLOT (max 9 = 10-finger MT)`, `ABS_MT_POSITION_X`, `ABS_MT_POSITION_Y`, `ABS_MT_TRACKING_ID`, `MSC_TIMESTAMP`. Pre-fix baseline had `input props: <none>` and only `ABS_X/Y` non-MT.
* **Regression-protection:** `CM-AI-WIRED-TOUCH-FORENSICS` pre-build gate (Phase 39.AP, 8 invariants) + paired mutation in `meta_test_false_positive_proof.sh` strips `systematic-debugging Phase 1` citation literal → gate FAILs. On-device `test_d3_wired_touch_forensics.sh` runs per topology dispatch via `test_all_fixes.sh`.
* **Why this matters:** Without this fix, a fleet-wide hardware variation (different OEM touch panel) silently broke touch input — the failure mode the §11.4 covenant exists to catch. Phase 1 captured-evidence ADB probe (§11.4.21 path #1) rewrote my original hypothesis triplet (a/b/c) to reveal an unanticipated (b) variant: a third vendor that the existing config infrastructure never knew about.
* **Cross-references:** Builds on the existing IDC infrastructure pattern + Fix #43 / #47 (input device classification policy). Uses §11.4.21 self-resolution exhaustion mandate (path #1 ADB) for the entire 4-phase cycle.

### AK. D3 touch display UI rendered too large (per-display density fix) — `Phase 39.AW + 39.AY closure, 2026-05-14`

**Status:** Fixed (→ Fixed.md)
**Type:** Bug

* **Closure cycle:** Phase 39.AW + 39.AY (1.1.5-dev, between 0.0.11 and pre-Sonos tag).
* **Closure commits:** source `011fcd5b15b`; Phase 4 verification `qa-results/d3_phase4_postflash_20260514_1649/PHASE_4_VERDICT.md`.
* **Discovery:** Operator reported "icons, everything, the whole UI is too big" on D3's wired touch display. Phase 1 captured-evidence (`d3_ui_scaling_forensics_*`) revealed the panel reports DRM modes `2560x1440 / 1920x1200 / 1920x1080` (NOT MPI7009's `1024x600` — a DIFFERENT higher-resolution panel) and was rendering at xxhdpi bucket (`ro.sf.lcd_density=320`). UI assets designed for a smaller HDPI screen were rendering oversized on this physically-modest higher-resolution panel.
* **Source-side fix:** `device/rockchip/common/display_settings.xml` ADDED `forcedDensity="213"` (tvdpi bucket) to the `local:0` block only. `local:1` (TV pass-through) and `local:2` (4K monitor) UNCHANGED at `forcedDensity="320"` — non-regression mandate satisfied per User-explicit instruction: *"Not a single other display configuration and resolution can be affected, only this particular touch display when connected!"*.
* **Phase 4 captured-evidence (post-flash):** `wm density -d 0` reports `Physical density: 320 / Override density: 213` (was 320 with NO override pre-fix). `wm density -d 2` still reports `Physical density: 213 / Override density: 320` (TV pass-through UNCHANGED). Display 1 unaffected. Non-regression PASS.
* **Regression-protection:** `CM-AK-UI-SCALING-FORENSICS` pre-build gate (Phase 39.AS, 8 invariants — wm-density-per-display + DRM-EDID-probe + runtime-display-settings-probe + non-regression-baseline + screencap-evidence + decision-guide-section).
* **Why this matters:** Per-display density override is the rare case where a config-level fix produces user-visible quality-of-life improvement without any source-code change. The captured-evidence cycle proved the change is precisely scoped — display 0 affected, others UNCHANGED, as the user mandated.
* **Cross-references:** Builds on Fix #80 (HDMI dual-display detection). Uses §11.4.5 captured-evidence per-display probe pattern.

### AQ. test_all_fixes.sh orchestrator — ANDROID_SERIAL inheritance gap caused 107 SKIPs in Phase 2 — `Phase 39.BQ closure, 2026-05-16`

**Status:** Completed (→ Fixed.md)
**Type:** Task

* **Closure cycle:** Phase 39.BQ (User mandate 2026-05-15, §11.4.1 script-bug).
* **Discovery:** Phase 39.BM `test_all_fixes.sh` cycle on D3 reported Phase 2 (After Reboot) summary: `Suites run: 114 / Suites passed: 6 / Suites failed: 2 / Suites skipped: 107`. All 107 SKIPs traced to sub-test scripts hard-failing on missing `ANDROID_SERIAL` env var.
* **Root cause (captured-evidence from orchestrator + sub-test source audit 2026-05-16):** 22 sub-test scripts (`test_streaming_kinopoisk.sh`, `test_streaming_rutube.sh`, `test_streaming_ivi.sh`, `test_streaming_smarttube.sh`, `test_streaming_stress_visual.sh`, `test_visual_coverage_all_apps.sh`, `test_launcher_titles.sh`, `test_audio_coverage_all_outputs.sh`, `test_audio_stress_capture.sh`, `test_netflix_tv_ui_visual.sh`, `test_orientation_d9_steady_state.sh`, `test_lampa_qa.sh`, `test_video_routing_bug21_mirror_surface.sh`, et al for Bug #22 / #23) read `ANDROID_SERIAL` from their host env. The orchestrator's `run_device_test` helper invoked them via `adb shell sh test.sh` — but `adb shell` does NOT propagate host env vars to the device shell. The on-device `sh` invocation had no `ANDROID_SERIAL` → hard-fail SKIP at each sub-test's top guard.
* **Source-side fix:** `device/rockchip/rk3588/tests/test_all_fixes.sh:346` adds `run_host_test()` helper that uses host `bash` (not `adb shell sh`) with `ANDROID_SERIAL` propagated. Five mis-dispatched invocations (Bug #13 / #21 / #22 / #23 / D9 orientation) migrated from `run_device_test` to `run_host_test`.
* **Captured-evidence (Phase 39.BP cycle after fix):** Phase 2 PASS rate jumped from **5% → 75%** — direct §11.4.5 captured-evidence proof the dispatch table fix lifted real PASSes that had been masked behind ANDROID_SERIAL-related SKIPs.
* **Regression-protection:** `CM-ANDROID-SERIAL-PROPAGATION` planned (gate asserts the `run_host_test` helper exists in `test_all_fixes.sh` AND ≥5 sub-tests are invoked via it). Currently deferred — the dispatch is a test-orchestrator script rather than a shipping artifact, so a paired-mutation gate would only assert the orchestrator's structure (still valuable per §11.4.1 — to land in next cycle).
* **Why this matters:** This is the exact §11.4 failure mode the covenant exists to catch — 107 sub-tests SKIPped is invisible "all green" reporting when the underlying tests never ran. Skipped-count is mechanically distinguishable from PASS-count per §11.4.1, but the fix unmasks the actual PASS/FAIL signal on a major fraction of the suite.
* **Cross-references:** Companion to §AP (host adb-server resilience — Phase 39.BT). Same root-class as §AT (test-side stale assertions). Both demonstrate the §11.4.1 "FAIL-bluffs equally forbidden" principle: a SKIP-bluff (script-bug masking real signal) and a FAIL-bluff (stale assertion against removed control) are equally damaging — both must be fixed at the test layer, not patched in call sites.

### AW. D9 orientation watchdog losing race — `Phase 39.BV closure, end-to-end validated on D4 Phase 39.CJ, 2026-05-16`

**Status:** Fixed (→ Fixed.md)
**Type:** Bug

* **Closure cycle:** Phase 39.BV source-side fix + Phase 39.CJ D4 end-to-end captured-evidence (User mandate 2026-05-15 Pavel #4 forensic anchor).
* **Discovery:** Phase 39.BP D3 cycle 30/30 readings = 1 despite watchdog running at 1Hz polling — deterministic race-loss against synchronous framework writers.
* **Root cause (CONFIRMED via subagent agentId a8dd6a0ac86c82908):** `DeviceStateRotationLockSettingController.readPersistedSetting()` at `frameworks/base/packages/SystemUI/.../DeviceStateRotationLockSettingController.java:141-166` → `mRotationPolicyWrapper.setRotationLock()` → `WindowManagerService.thawRotation()` → `DisplayRotation.setUserRotation()` (writes ACCELEROMETER_ROTATION=1) on every DeviceState change. D9's dual-display topology triggers DeviceState changes far more frequently than D1/D2. Polling at 1Hz cannot win this race.
* **Source-side fix (Phase 39.BV Option B):** Created `device/rockchip/atmosphere/presenter/Presenter/src/main/java/com/atmosphere/presenter/RotationLockObserver.kt` (~190 lines) — Kotlin ContentObserver on `Settings.System.ACCELEROMETER_ROTATION` URI; reacts within ~50ms of any write; preserves Phase 39.BG §AN Layer 3 Netflix bypass via `ROTATION_OWNER_PACKAGES` set; uses `ActivityManager.getRunningAppProcesses()` for foreground detection (no shell exec). Wired into `PresenterService.kt` onCreate + onDestroy. `atmosphere-orientation-watchdog.sh` `INTERVAL_SEC` reduced from 1 to 60 — now serves as a safety-net heartbeat in case Presenter is killed.
* **Pre-build gates:** `CM-AW-ROTATION-OBSERVER-PRESENT` (8 invariants: ContentObserver registration, ACCELEROMETER_ROTATION URI literal, TARGET_VALUE=0, Netflix bypass preserved, Phase 39.BV citation, PresenterService onCreate start, PresenterService onDestroy stop, watchdog cadence ≥30s) + `CM-D9-WATCHDOG-FAST-INTERVAL` amended to accept observer-primary topology (legacy INTERVAL_SEC=1 OR observer-primary INTERVAL_SEC≥30).
* **Paired mutation:** strips `registerContentObserver(URI` → gate FAILs with `content-observer-not-registered`.
* **Phase 39.CJ D4 captured-evidence 2026-05-16T19:32Z (build v2 MD5 519e32e8465b28c02845c1b3eae31094):** test injected foreign write `settings put system accelerometer_rotation 1`, read back at 300ms / 600ms / 900ms intervals — **ALL THREE READS returned `0`**. RotationLockObserver caught the write and reverted within the first 300ms read window. Pre-fix shell watchdog at 1000ms polling could not have caught this in 300ms — direct empirical proof the observer is the primary correction surface as designed.
* **Why this matters:** D9 dual-display rotation glitches were end-user-visible (Pavel #4 user-mandate forensic anchor). The polling-only approach was a §11.4.7 demotion-evidence violation — claiming "INTERVAL_SEC=1 closes the <5s aggressor race window" without acknowledging the underlying race is event-driven and polling has a fundamental floor. Event-driven ContentObserver is the architecturally-correct surface per AOSP 15 `frameworks/base/core/java/android/database/ContentObserver.java` documentation.
* **Cross-references:** Fix #65 always-portrait mandate (the original specification that the watchdog enforces), Phase 39.BG §AN Layer 3 Netflix bypass (preserved in the observer), §11.4.7 demotion-evidence rule (the rule the original watchdog-only approach silently violated).

### AX. tap-undim AccessibilityService not observing TYPE_TOUCH_INTERACTION_START — `Phase 39.BW closure, end-to-end validated on D4 Phase 39.CJ, 2026-05-16`

**Status:** Fixed (→ Fixed.md)
**Type:** Bug

* **Closure cycle:** Phase 39.BW source-side fix + Phase 39.CJ D4 end-to-end captured-evidence (User mandate 2026-05-15 Phase 39.AZ regression).
* **Discovery:** Phase 39.BP D3 cycle: brightness dimmed correctly (102→10 in 6s), but `input tap 200 400` followed by 1.2s wait did NOT restore brightness — tap-undim broken.
* **Root cause (CONFIRMED via subagent agentId a0c94d28bafb49485):** architectural decoupling between TWO parallel dimming paths — (1) `PrimaryDisplayDimController.kt` (Kotlin, in-Presenter) has working tap-undim via `PresenterAccessibilityService` TYPE_TOUCH_INTERACTION_START forwarding, (2) `atmosphere-idle-dim-daemon.sh` (Fix #132 shell daemon) was 100% polling-based at **5000ms** default with NO touch hook at all. The §AX test exercises path #2; a 1.2s test window cannot observe a state transition that requires 5s polling — design contradiction.
* **Source-side fix (Phase 39.BW Option A):** dropped `IDLE_DIM_POLL_MS` default `5000 → 1000` at `device/rockchip/rk3588/bin/atmosphere-idle-dim-daemon.sh:127`. Source inline citation: Phase 39.BW §AX captured-evidence + 1.2s test-window justification.
* **Pre-build gate:** `CM-AX-IDLE-DIM-POLL-1S` (4 invariants — default==1000 literal, no legacy 5000, Phase 39.BW citation, §AX rationale literal).
* **Paired mutation:** flip `IDLE_DIM_POLL_MS:-1000` → `IDLE_DIM_POLL_MS:-5000` → gate FAILs with `default-not-1000ms` + `legacy-5000-default-still-present`.
* **Phase 39.CJ D4 captured-evidence 2026-05-16T19:34Z (build v2 MD5 519e32e8465b28c02845c1b3eae31094):** D4 brightness baseline = 10 (idle-dim state observed); `input tap 200 400` injected; sleep 2; brightness re-read = **102 (RESTORED)**. Daemon `persist.atmosphere.idle_dim.last_action=restore` + `last_action_epoch_ms=959310`. Phase 39.BW IDLE_DIM_POLL_MS=1000 default + idle-dim daemon properly detected tap-induced `mLastUserActivityTime` update and restored brightness to operator's preferred value within 2 seconds. Pre-fix this would have stayed at 10 for up to 5s.
* **Why this matters:** Pre-fix, end-users saw a "dead screen" for up to 5s after touching it from idle. Subjectively this looks like the device is broken — exactly the kind of user-visible defect the §11.4 covenant exists to prevent. Option C (extend `PresenterAccessibilityService` to forward TYPE_TOUCH_INTERACTION_START to the shell daemon via setprop `atmosphere.idle_dim.touch_epoch_ms`) remains queued as Phase 39.BW.2 for sub-50ms reaction — Option A alone closes the user-visible defect.
* **Cross-references:** Phase 39.AZ idle-dim daemon (Fix #132) — the original implementation that §AX patched. §AJ idle-dim mandate (User mandate 2026-05-14). Phase 39.U-α `screen_off_timeout=60000` design.



