#!/system/bin/sh
# golden_good_test.sh — GOLDEN-GOOD fixture for the catalog self-validation.
#
# Purpose: A test that GENUINELY carries the bluff-proof + physical-evidence
#   markers, so the catalog generator MUST derive bluff_proofed=true AND
#   physical_evidence=true. If the generator EVER derives false for this
#   fixture, the deriver is broken (§11.4.107(10) analyzer self-validation).
#
# §11.4.69 FEATURE: audio_output
# §11.4.115 polarity switch present:
RED_MODE=${GOLDEN_RED_MODE:-1}

. lib/anti_bluff.sh
. lib/physical_confirmation.sh

# === SECTION A: capture audio + assert sink ===
tinycap /data/local/tmp/cap.wav -d 0 -c 2 -r 48000 -b 16
pc_assert_channel_count /data/local/tmp/cap.wav 2

ab_run_n_times "golden_good audio" 3 do_capture
ab_pass_with_evidence "audio plays at 2ch" /data/local/tmp/cap.wav
