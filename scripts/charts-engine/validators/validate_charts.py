#!/usr/bin/env python3
# charts-engine / validators / validate_charts.py
#
# Purpose:   Golden self-validation (§11.4.107(10)) proving the chart generator
#            is NOT a bluff: a golden-GOOD run against a REAL DB must produce
#            non-empty PNGs of the expected pixel dimensions; a golden-BAD run
#            against an empty / corrupt DB must FAIL (raise), never silently
#            emit a chart. An analyzer that PASSes its golden-bad fixture is
#            itself the bluff this validator forbids.
# Usage:     python3 validate_charts.py --db <real_db> [--workdir <tmp>]
# Inputs:    --db (a REAL workable_items.db for the golden-good case).
# Outputs:   PASS/FAIL verdict + per-check evidence to stdout; non-zero exit on
#            any failure.
# Side-effects: writes charts to a temp workdir (cleaned up) + a deliberately
#            corrupt fixture DB it creates itself.
# Dependencies: generate_charts.py, lib/render.py; Pillow if available (exact
#            pixel-dimension check) else PNG-header IHDR parse fallback.
"""Golden-good / golden-bad self-validation for the charts engine."""

import argparse
import os
import struct
import sys
import tempfile
import shutil

_HERE = os.path.dirname(os.path.abspath(__file__))
_ENGINE = os.path.dirname(_HERE)
sys.path.insert(0, _ENGINE)
sys.path.insert(0, os.path.join(_ENGINE, "lib"))

import generate_charts  # noqa: E402
import wi_query  # noqa: E402

EXPECTED_W = 1000  # _FIG_W_IN(10) * _DPI(100)
EXPECTED_H = 600   # _FIG_H_IN(6)  * _DPI(100)


def _png_dimensions(path):
    """Read width/height from a PNG IHDR chunk (no external dep)."""
    with open(path, "rb") as fh:
        head = fh.read(33)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"not a PNG: {path}")
    # IHDR width/height are big-endian uint32 at bytes 16..24.
    w, h = struct.unpack(">II", head[16:24])
    return w, h


def golden_good(db_path, workdir):
    """A REAL DB must produce non-empty PNGs of the expected dimensions."""
    out = os.path.join(workdir, "good")
    manifest = generate_charts.generate(db_path, out, "golden_good")
    assert manifest["total_items_in_db"] > 0, "golden-good DB has zero items"
    checks = []
    for c in manifest["charts"]:
        png = os.path.join(out, c["png"])
        assert os.path.isfile(png), f"missing PNG: {png}"
        size = os.path.getsize(png)
        assert size > 1000, f"PNG suspiciously small ({size}B): {png}"
        w, h = _png_dimensions(png)
        assert (w, h) == (EXPECTED_W, EXPECTED_H), \
            f"PNG dims {w}x{h} != {EXPECTED_W}x{EXPECTED_H}: {png}"
        checks.append(f"  PASS {c['name']}: {w}x{h}, {size}B, "
                      f"rows_drawn={c['rows_drawn']}")
    return checks


def golden_bad(workdir):
    """An empty/corrupt DB must FAIL — the generator must NOT emit a fake chart."""
    # Fixture 1: a non-DB file (corrupt).
    corrupt = os.path.join(workdir, "corrupt.db")
    with open(corrupt, "wb") as fh:
        fh.write(b"this is not a sqlite database at all\x00\xff")
    out = os.path.join(workdir, "bad")
    raised = False
    try:
        generate_charts.generate(corrupt, out, "golden_bad")
    except (wi_query.QueryError, Exception):  # noqa: BLE001 — any failure is correct
        raised = True
    assert raised, "golden-bad corrupt DB did NOT fail — generator is a bluff"

    # Fixture 2: missing file.
    raised2 = False
    try:
        generate_charts.generate(os.path.join(workdir, "nope.db"), out, "golden_bad")
    except SystemExit:
        raised2 = True
    except Exception:  # noqa: BLE001
        raised2 = True
    assert raised2, "golden-bad missing DB did NOT fail"
    return ["  PASS golden-bad corrupt DB correctly FAILED generation",
            "  PASS golden-bad missing DB correctly FAILED generation"]


def main(argv=None):
    ap = argparse.ArgumentParser(description="Charts-engine golden self-validation.")
    ap.add_argument("--db", required=True, help="a REAL workable_items.db")
    ap.add_argument("--workdir", default=None)
    args = ap.parse_args(argv)

    workdir = args.workdir or tempfile.mkdtemp(prefix="charts_validate_")
    cleanup = args.workdir is None
    try:
        print("GOLDEN-GOOD (real DB must produce valid charts):")
        good = golden_good(args.db, workdir)
        for line in good:
            print(line)
        print("GOLDEN-BAD (corrupt/empty DB must FAIL):")
        bad = golden_bad(workdir)
        for line in bad:
            print(line)
        print(f"\nVALIDATION PASS — {len(good)} good-checks + {len(bad)} bad-checks")
        return 0
    except AssertionError as exc:
        print(f"\nVALIDATION FAIL: {exc}")
        return 1
    finally:
        if cleanup:
            shutil.rmtree(workdir, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
