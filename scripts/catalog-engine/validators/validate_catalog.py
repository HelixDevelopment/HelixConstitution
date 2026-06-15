#!/usr/bin/env python3
# catalog-engine / validators / validate_catalog.py
#
# Purpose:   Self-validation of the catalog DERIVER (§11.4.107(10) /
#            §11.4.138). Runs the parser on BOTH golden fixtures and asserts:
#            golden_good -> bluff_proofed=True AND physical_evidence=True;
#            golden_bad  -> bluff_proofed=False AND physical_evidence=False.
#            A deriver that passes the golden-bad as bluff-proof is itself a
#            bluff gate -> this validator FAILs (non-zero exit).
# Usage:     python3 validators/validate_catalog.py     (exit 0 = GREEN)
# Inputs:    none — uses the bundled fixtures/.
# Outputs:   prints PASS/FAIL per assertion; non-zero exit on any FAIL.
# Side-effects: none.
# Dependencies: lib/parse_shell.py.
# Cross-refs: P0_design.md §7 self-validation contract.
"""Golden-good / golden-bad deriver self-validation (the analyzer anti-bluff)."""

import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_ENGINE = os.path.dirname(_HERE)
sys.path.insert(0, os.path.join(_ENGINE, "lib"))

import parse_shell  # noqa: E402

_FIX = os.path.join(_ENGINE, "fixtures")


def _check(name, cond):
    status = "PASS" if cond else "FAIL"
    print("  [%s] %s" % (status, name))
    return cond


def run():
    good = parse_shell.parse_shell_file(
        os.path.join(_FIX, "golden_good_test.sh"), "on_device")
    bad = parse_shell.parse_shell_file(
        os.path.join(_FIX, "golden_bad_test.sh"), "on_device")

    print("golden-good (MUST derive bluff_proofed=T, physical_evidence=T):")
    ok = True
    ok &= _check("good.bluff_proofed is True", good["bluff_proofed"] is True)
    ok &= _check("good.physical_evidence is True",
                 good["physical_evidence"] is True)
    ok &= _check("good.feature_class == audio_output",
                 good["feature_class"] == "audio_output")

    print("golden-bad (MUST derive bluff_proofed=F, physical_evidence=F):")
    ok &= _check("bad.bluff_proofed is False", bad["bluff_proofed"] is False)
    ok &= _check("bad.physical_evidence is False",
                 bad["physical_evidence"] is False)
    ok &= _check("bad.feature_class is None", bad["feature_class"] is None)

    print("VERDICT: %s" % ("GREEN — deriver is not bluffing"
                           if ok else "RED — deriver self-validation FAILED"))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(run())
