#!/system/bin/sh
# golden_bad_test.sh — GOLDEN-BAD fixture for the catalog self-validation.
#
# Purpose: A metadata-only test that carries NONE of the bluff-proof /
#   physical-evidence markers (no RED_MODE, no _red suffix, no pc_assert,
#   no ab_pass_with_evidence, no tinycap/screenrecord/arvus, no FEATURE
#   annotation, no ab_run_n_times). The catalog generator MUST derive
#   bluff_proofed=false AND physical_evidence=false. If the generator EVER
#   derives true for this fixture, the analyzer itself is bluffing
#   (§11.4.107(10) / §11.4.138 "the analyzer is not the bluff").

# === SECTION A: configuration-only check ===
echo "checking a property is set"
if getprop ro.something | grep -q true; then
  echo "PASS: property present"
else
  echo "FAIL: property absent"
fi
