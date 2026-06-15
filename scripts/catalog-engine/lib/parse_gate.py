#!/usr/bin/env python3
# catalog-engine / lib / parse_gate.py
#
# Purpose:   Parse the pre-build verification gate file into one catalog record
#            per `CM-*` gate. The canonical gate-definition idiom is
#            `echo -n "  CM-<ID>: <what-it-checks>... "` — that line both
#            DEFINES the gate AND carries its human-readable "what it checks"
#            description. Each such line becomes one record (type=pre-build-gate).
#            §11.4.6 — every field DERIVED from the gate-definition line; the
#            source line number is captured so a reader can jump to the gate.
# Usage:     records = parse_gate_file(path, type_root)
# Inputs:    absolute path to pre_build_verification.sh + type-root tag.
# Outputs:   a list of dicts matching the §2 schema (gate subset).
# Side-effects: none — read-only.
# Dependencies: stdlib only (re, os).
# Cross-refs: docs/research/test_catalog/P0_design.md §1 (632 raw CM-* tokens;
#            510 are gate DEFINITIONS via the echo-n idiom — the rest are
#            cross-reference mentions in comments, which do NOT define a gate).
"""Pre-build CM-* gate parser for the catalog engine (decoupled, §11.4.28)."""

import os
import re

# Canonical gate-DEFINITION idiom (the line that prints the gate banner just
# before running its check):  echo -n "  CM-<ID>: <description>... "
# Captures (1) the gate id, (2) the description, with the trailing "..." dropped.
_RE_GATE_DEF = re.compile(
    r'echo\s+-n\s+"\s*(CM-[A-Z0-9_-]+):\s*(.*?)\s*(?:\.\.\.)?\s*"'
)

# ATM-NNN reference inside the gate description (§11.4.54), if present.
_RE_ATM = re.compile(r"\bATM-([0-9]+)\b")
# Fix #NN reference inside the description (project cross-ref).
_RE_FIX = re.compile(r"\bFix #([0-9]+)\b")
# §-letter / §11.4.NN anchor reference inside the description.
_RE_SECTION = re.compile(r"§\s*([0-9A-Za-z.]+)")
# Feature-class hint (§11.4.69 taxonomy token) appearing literally in the desc.
_RE_FEATURE = re.compile(
    r"\b(audio_output|audio_input|video_display|network_throughput|"
    r"network_connectivity|bluetooth_a2dp|bluetooth_pair|touch_input|sensor|"
    r"gpu_render|storage_read|storage_write|mediacodec_decode|"
    r"mediacodec_encode|miracast|cast|boot_service|package_install|"
    r"permission_grant|wifi_link|wifi_throughput|ethernet_link|"
    r"display_topology|drm_playback|subtitle_render)\b"
)


def _read_lines(path):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            return fh.read().splitlines()
    except OSError:
        return []


def parse_gate_file(path, type_root):
    """Parse one pre-build verification file → list of gate records.

    One record per DISTINCT `CM-<ID>` gate-definition line (the echo-n banner).
    If a gate id is printed more than once (rare — multi-part gate) the FIRST
    occurrence wins for the description; the source_line is the first banner.
    """
    repo_rel_basename = os.path.basename(path)
    lines = _read_lines(path)
    records = []
    seen = {}   # gate_id -> record (dedup; first definition wins)

    for lineno, ln in enumerate(lines, start=1):
        m = _RE_GATE_DEF.search(ln)
        if not m:
            continue
        gate_id = m.group(1)
        desc = (m.group(2) or "").strip()
        if gate_id in seen:
            continue   # first definition wins; later banners are sub-parts
        # derive cross-references from the description
        matm = _RE_ATM.search(desc)
        atm_id = "ATM-%s" % matm.group(1) if matm else None
        mfix = _RE_FIX.search(desc)
        fix_ref = "Fix #%s" % mfix.group(1) if mfix else None
        msec = _RE_SECTION.search(desc)
        section_ref = ("§" + msec.group(1)) if msec else None
        mfeat = _RE_FEATURE.search(desc.lower())
        feature_class = mfeat.group(1) if mfeat else None

        # step_by_step for a gate = the single check it performs (the banner).
        steps = [{
            "what": "pre-build assert: %s" % desc if desc else "pre-build gate",
            "how": "echo-n banner + check", "achieved": "", "result": "",
            "source": "gate-definition-line",
        }]

        derivation_gaps = []
        if not desc:
            derivation_gaps.append("no-gate-description")

        rec = {
            "id": gate_id,
            "name": "%s — %s" % (gate_id, desc) if desc else gate_id,
            "type": type_root,                  # "pre-build-gate"
            "subtypes": ["pre_build_gate"],
            "description": desc,
            "description_quality": "gate-banner" if desc else "header-only",
            "step_by_step": steps,
            "how_tokens": [],
            # A gate is a SOURCE-layer check (§11.4.108) — it is NOT itself a
            # captured-evidence test. bluff_proofed/physical_evidence describe
            # RUNTIME tests; for a static gate both are False BY CONSTRUCTION.
            # The gate's anti-bluff guarantee comes from its PAIRED MUTATION
            # (parse_mutation.py), surfaced as the catalog gate↔mutation join.
            "bluff_proofed": False,
            "bluff_proofed_reasons": [],
            "physical_evidence": False,
            "physical_evidence_which": [],
            "feature_class": feature_class,
            "version": "unversioned",
            "atm_id": atm_id,
            "fix_ref": fix_ref,
            "section_ref": section_ref,
            "status": "gate",
            "sources_anti_bluff": False,
            "source_path": None,                # filled by scan.py
            "source_line": lineno,
            "source_file": repo_rel_basename,
            "derivation_gaps": derivation_gaps,
            # join key — filled at scan time by cross-referencing the mutation
            # corpus; default None means "no paired mutation found yet".
            "paired_mutation": None,
        }
        seen[gate_id] = rec
        records.append(rec)

    return records
