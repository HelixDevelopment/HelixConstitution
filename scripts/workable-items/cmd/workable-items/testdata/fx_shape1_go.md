## GO. 2nd display (Arvus monitor) immediate-sleep on D3 — secondary-display keep-awake WakeLock (= completes unimplemented §JU-4) — `Fixed (→ Fixed.md)` (Phase 39 §GO, 2026-05-28)

**Status:** Fixed (→ Fixed.md)
**Type:** Bug
**Phase:** 39 §GO
**Closure commit:** Presenter submodule `9581c5b` (§GO/§JU-4 persistent secondary-display WakeLock + 20s CEC re-knock); parent build carrying it validated on D3.
**Closure cycle:** 1.1.7-dev, validated on D3 (`998fd36615e99484`).

### Root cause (CONFIRMED, source-evidenced)

The §JU-4 persistent secondary-display WakeLock was specced but had NEVER been implemented — the pre-fix image (`6bb9de44`, Presenter HEAD `f523417`) shipped only the one-shot 30s-throttled CEC nudge (§GW/§JT `87cdc18`), a momentary "knock", not a "hold". The Arvus AVR's sub-30s idle-standby timer fired faster than the 30s CEC throttle, so the secondary monitor self-slept on no-signal after 2-3s. Grep of the entire Presenter source confirmed no `newWakeLock`/`SCREEN_BRIGHT_WAKE_LOCK`/`onAnyPlaybackStarted` path existed.

### Fix §GO (= completes §JU-4, REQUIRES_REBUILD)

`PresenterService.kt` acquires `PowerManager.SCREEN_BRIGHT_WAKE_LOCK | ON_AFTER_RELEASE` (`ATMOSphere:SecondaryDisplayKeepAwake`) in the VideoPlaybackDetector PLAYING callback + integrated video/music start paths; release on STOPPED after ≥5s debounce. Periodic CEC re-knock every ~20s during sustained playback (bypasses the 30s throttle for the keep-alive path). Cross-ref §JU, §JT, §GW, Fix #65, Fix #132.

### Captured evidence (D3, §11.4.7 same-conditions + §11.4.69 `video_display`/`display_topology`)

- `qa-results/validate_d3_117_20260528T160926Z/go_wakelock.log` — TWO held Presenter SCREEN_BRIGHT_WAKE_LOCKs: `WindowManager/displayId:2` (uid=1000 ws=com.atmosphere.presenter) + `ATMOSphere:SecondaryDisplayKeepAwake` (uid=10025), both `ON_AFTER_RELEASE`.
- `qa-results/validate_d3_117_20260528T160926Z/go_secondary_poll.log` — 3-minute 1s/10s-interval poll: `mPhysicalDisplayId=1 mState=ON` for EVERY sample during MPV playback (monitor stayed ON, no sleep).
- `qa-results/validate_d3_rkmpp_20260528T204713Z/go_wakelock.txt` + `go_display_states.txt` — re-confirmed in the rkmpp re-run: `ATMOSphere:SecondaryDisplayKeepAwake` ACQ logged, both `local:0` + `local:1 ("HDMI Screen")` report `state ON, committedState ON`.

### Regression-protection

Paired meta-test: strip the §JU-4 WakeLock acquisition → the §GO on-device test FAILs (monitor sleeps mid-playback). The §JU-4 WakeLock remains defensive-useful for any sink with an aggressive DPMS timer.

---

