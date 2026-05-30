## GS-2. ATMOSphere VLC/MPV local 5.1 audio reaches HDMI as multichannel (not downmixed to stereo) — `Fixed (→ Fixed.md)` (Phase 39 §GS-2, 2026-05-28)

**Status:** Fixed (→ Fixed.md)
**Type:** Bug
**Phase:** 39 §GS-2 (sub-item of the §GS local-A/V umbrella; §GS-1/§GS-3/§GS-4/§GS-5 remain open in Issues.md)
**Closure commit:** vlc-player `cb6c472db` (§GS-2 `--stereo-mode=0` auto-layout — NOT the unsafe digital-output passthrough flip which would silence ES8388/USB/BT).
**Closure cycle:** 1.1.7-dev, validated on D3 (`998fd36615e99484`).

### Root cause + fix

VLC fork shipped `KEY_AUDIO_DIGITAL_OUTPUT=false` default → libVLC downmixed multichannel to stereo AudioTrack, never feeding Fix #112's multichannel HDMI LPCM path. Fix: `--stereo-mode=0` auto channel-layout (safe — preserves ES8388/USB/BT outputs, unlike a digital-output passthrough flip). MPV path already negotiates the multichannel layout.

### Captured evidence (D3, §11.4.69 `audio_output` + §11.4.5 channel-count)

- `qa-results/validate_d3_rkmpp_20260528T204713Z/logcat_playback.txt` — D3 local 5.1 source decoded `(aac 6ch 48000 Hz)` → `[af:v] [in] 48000Hz 5.1 6ch floatp` → `AO: [audiotrack] 48000Hz 5.1 6ch float` (5.1 layout reached AudioTrack, NOT downmixed to stereo).
- `qa-results/validate_d3_rkmpp_20260528T204713Z/media_session.txt` — MPV MediaSession `state=PLAYING(3)` during the capture.
- Cross-ref Fix #136 §EM (`qa-results/phase39em_multichannel_validation_20260519T031824Z/`) — the AudioFlinger `AT::add channelMask=0000003F` (5.1) / `sampleRate=48000` HDMI multichannel pipeline this 5.1 stream feeds.

### Regression-protection

Pre-build gate `CM-EM-5-1-MULTICHANNEL-HDMI-VERIFIED` (Fix #136) protects the multichannel HDMI Out devicePort + the end-to-end playback path; paired meta-test mutation strips the `am start ... VIEW` playback invocation → gate FAILs.

### Note

This closes only the §GS-2 5.1-audio sub-item. The §GS-1 HW-4K-decode CRUX remains DEFERRED (open in Issues.md): the player forks decode in SW (HW `hevc_rkmpp`/`v4l2m2m`/`mediacodec` paths all fail format-conversion — captured in `qa-results/validate_d3_rkmpp_20260528T204713Z/gs1_decoder_chain.txt`); SW decode works.

---

