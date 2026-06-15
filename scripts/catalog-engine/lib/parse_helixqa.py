#!/usr/bin/env python3
# catalog-engine / lib / parse_helixqa.py
#
# Purpose:   Parse an ATMOSphere HelixQA test-bank YAML into one catalog record
#            per test_case (Challenge). SCOPE DECISION (§11.4.28 decoupling,
#            cited in P1b report): ONLY the project-owned ATMOSphere banks under
#            tools/helixqa/banks/*.yaml are catalogued — they are the consumer-
#            injected ATMOSphere taxonomy. The project-agnostic HelixQA submodule
#            corpus (tools/helixqa/HelixQA/**.yaml — 73 files) belongs to a
#            DIFFERENT owned submodule and is OUT of the ATMOSphere catalog scope.
#            A test_case is a YAML list item carrying `- id:`/`- challenge_id:`
#            at test_cases depth; its sibling fields drive the record.
# Usage:     records = parse_helixqa_file(path, type_root)
# Inputs:    absolute path to an ATMOSphere bank YAML + type-root tag.
# Outputs:   a list of dicts matching the §2 schema (challenge subset).
# Side-effects: none — read-only.
# Dependencies: stdlib only (re, os). NO PyYAML — a tiny indentation-aware
#            list-item walker covers the bank schema (the same stdlib-only
#            decoupling the rest of the engine uses).
# Cross-refs: docs/research/test_catalog/P0_design.md §1; the 4 ATMOSphere banks
#            (atmosphere.yaml 35 + atmosphere_119_fix_coverage.yaml 7 +
#            atmosphere_v119.yaml 38 + atmosphere_release_gate_video.yaml 13).
"""ATMOSphere HelixQA test-bank parser for the catalog engine (decoupled)."""

import os
import re

_RE_ATM = re.compile(r"\bATM-([0-9]+)\b")
# §11.4.69 feature-class taxonomy tokens (closed set) — recognised in
# feature_class / domains / tags so the catalog can cluster a Challenge.
_FEATURE_TOKENS = (
    "audio_output", "audio_input", "video_display", "network_throughput",
    "network_connectivity", "bluetooth_a2dp", "bluetooth_pair", "touch_input",
    "sensor", "gpu_render", "storage_read", "storage_write",
    "mediacodec_decode", "mediacodec_encode", "miracast", "cast",
    "boot_service", "package_install", "permission_grant", "wifi_link",
    "wifi_throughput", "ethernet_link", "display_topology", "drm_playback",
    "subtitle_render",
)


def _read_lines(path):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            return fh.read().splitlines()
    except OSError:
        return []


def _strip_quotes(v):
    v = v.strip()
    if len(v) >= 2 and v[0] in "\"'" and v[-1] == v[0]:
        return v[1:-1]
    return v


def _list_item_indent(lines):
    """Find the most common indentation of `- id:` / `- challenge_id:` list
    items — that is the test_cases item depth. Returns the indent string."""
    counts = {}
    for ln in lines:
        m = re.match(r"^(\s*)-\s*(?:id|challenge_id):", ln)
        if m:
            counts[m.group(1)] = counts.get(m.group(1), 0) + 1
    if not counts:
        return None
    return max(counts.items(), key=lambda kv: kv[1])[0]


def parse_helixqa_file(path, type_root):
    """Parse one ATMOSphere bank YAML → list of Challenge records.

    Each record is keyed by the list item's `id` (the stable Challenge handle).
    Sibling fields collected per item: challenge_id, name, feature_class,
    related_issue, dispatches_to, category, priority, required_evidence (count).
    """
    basename = os.path.basename(path)
    lines = _read_lines(path)
    item_indent = _list_item_indent(lines)
    records = []
    if item_indent is None:
        return records

    item_indent_len = len(item_indent)
    # Walk items: an item starts at a `- ` line at item_indent and continues
    # until the next `- ` at the same indent OR a line dedented to <= that.
    i = 0
    n = len(lines)
    while i < n:
        ln = lines[i]
        m = re.match(r"^(\s*)-\s*(\S[^:]*):\s*(.*)$", ln)
        if not (m and m.group(1) == item_indent):
            i += 1
            continue
        # collect this item's field block (the `- ` line + deeper-indented kids)
        fields = {}
        # the first inline key on the `- ` line
        first_key = m.group(2).strip()
        first_val = m.group(3)
        fields[first_key] = _strip_quotes(first_val) if first_val.strip() else ""
        # sub-keys: indented deeper than the `- ` item content column
        child_floor = item_indent_len + 2   # the `- ` consumes 2 cols
        evidence_count = 0
        j = i + 1
        cur_list_key = None
        while j < n:
            sub = lines[j]
            if not sub.strip():
                j += 1
                continue
            indent = len(sub) - len(sub.lstrip())
            # next list item at item depth OR a dedent ends this item
            mnext = re.match(r"^(\s*)-\s*\S", sub)
            if indent <= item_indent_len and (mnext and len(mnext.group(1)) == item_indent_len):
                break
            if indent < child_floor:
                break
            sm = re.match(r"^\s+([A-Za-z_][\w]*):\s*(.*)$", sub)
            if sm and indent == child_floor:
                k = sm.group(1).strip()
                v = sm.group(2)
                fields[k] = _strip_quotes(v) if v.strip() else ""
                cur_list_key = k if not v.strip() else None
            elif cur_list_key == "required_evidence" and \
                    re.match(r"^\s+-\s+", sub):
                evidence_count += 1
            j += 1

        # build the record
        cid = fields.get("id") or fields.get("challenge_id") or "unknown"
        name = fields.get("name") or cid
        feature_class = (fields.get("feature_class") or "").strip() or None
        if not feature_class:
            blob = " ".join([cid, name, fields.get("domains", ""),
                             fields.get("tags", "")]).lower()
            for tok in _FEATURE_TOKENS:
                if tok in blob:
                    feature_class = tok
                    break
        related = fields.get("related_issue") or ""
        matm = _RE_ATM.search(related) or _RE_ATM.search(name) or \
            _RE_ATM.search(cid)
        atm_id = "ATM-%s" % matm.group(1) if matm else None
        dispatches_to = fields.get("dispatches_to") or None

        steps = [{
            "what": "HelixQA Challenge: %s" % name,
            "how": "dispatches_to %s" % dispatches_to if dispatches_to
                   else "dispatch",
            "achieved": "PASS only on %d required_evidence token(s)"
                        % evidence_count if evidence_count else "",
            "result": "", "source": "helixqa-bank",
        }]

        derivation_gaps = []
        if not dispatches_to:
            derivation_gaps.append("no-dispatches_to(challenge-not-wired)")
        if evidence_count == 0:
            # §11.4.69: a Challenge with no required_evidence tokens cannot PASS
            # on captured evidence — flag it (do not assume it is a bluff, the
            # bank may carry evidence in another field; surface for review).
            derivation_gaps.append("no-required_evidence-tokens")
        if not feature_class:
            derivation_gaps.append("feature_class-absent")

        # physical_evidence for a Challenge = it carries required_evidence tokens
        # (the §11.4.69 evidence-ledger gate scores PASS ONLY on real artefacts).
        phys = ["required_evidence(%d)" % evidence_count] if evidence_count else []

        rec = {
            "id": cid,
            "name": name,
            "type": type_root,                  # "helixqa-challenge"
            "subtypes": ["helixqa_challenge"],
            "description": name,
            "description_quality": "challenge-name",
            "step_by_step": steps,
            "how_tokens": [],
            # bluff_proofed for a Challenge = it dispatches to a real on-device
            # test (the §11.4.4(b) layer-4 contract — a Challenge that does not
            # dispatch to a runtime test is a metadata-only bluff).
            "bluff_proofed": bool(dispatches_to),
            "bluff_proofed_reasons": (
                ["dispatches_to:%s" % os.path.basename(dispatches_to)]
                if dispatches_to else []),
            "physical_evidence": bool(phys),
            "physical_evidence_which": phys,
            "feature_class": feature_class,
            "version": "unversioned",
            "atm_id": atm_id,
            "category": fields.get("category") or None,
            "priority": fields.get("priority") or None,
            "dispatches_to": dispatches_to,
            "required_evidence_count": evidence_count,
            "status": "helixqa_challenge",
            "sources_anti_bluff": False,
            "source_path": None,                # filled by scan.py
            "source_file": basename,
            "derivation_gaps": derivation_gaps,
        }
        records.append(rec)
        i = j
    return records
