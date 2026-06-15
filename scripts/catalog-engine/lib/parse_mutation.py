#!/usr/bin/env python3
# catalog-engine / lib / parse_mutation.py
#
# Purpose:   Parse the §1.1 paired-mutation file into one catalog record per
#            mutation block. The canonical mutation-block idiom is
#            `— CM-<ID> mutation: <what-the-mutation-does> —` (the banner the
#            meta-test prints before mutating a source file, asserting the
#            paired gate FAILs, then restoring). Each block becomes one record
#            (type=meta-test-mutation) carrying the gate it PAIRS with (§1.1).
#            The gate↔mutation pair IS the catalog relationship that proves a
#            gate is not a bluff gate (§11.4.107(10) / §11.4.120).
# Usage:     records = parse_mutation_file(path, type_root)
# Inputs:    absolute path to meta_test_false_positive_proof.sh + type-root tag.
# Outputs:   a list of dicts matching the §2 schema (mutation subset) +
#            a `pairs_gate` field = the CM-<ID> the mutation breaks.
# Side-effects: none — read-only.
# Dependencies: stdlib only (re, os).
# Cross-refs: docs/research/test_catalog/P0_design.md §1 (649 raw CM-* tokens;
#            570 are mutation DEFINITIONS via the em-dash banner idiom).
"""§1.1 paired-mutation parser for the catalog engine (decoupled, §11.4.28)."""

import os
import re

# Canonical mutation-DEFINITION idiom (em-dash banner, NOT the gate cross-ref
# comment).  Example:  echo; echo "— CM-MC20 mutation: remove INVISIBLE … —"
# Captures (1) the gate id it pairs with, (2) the "what the mutation does".
_RE_MUT_DEF = re.compile(
    r"—\s*(CM-[A-Z0-9_-]+)\s+mutation:\s*(.*?)\s*(?:—|$)"
)
# Secondary header idiom that precedes a block:  # ---- Gate CM-<ID>: <desc>
_RE_GATE_HDR = re.compile(r"^#\s*-{2,}\s*Gate\s+(CM-[A-Z0-9_-]+):\s*(.*?)\s*-*\s*$")
# The assertion that proves the mutation makes the gate FAIL (§1.1 contract).
_RE_EXPECT_FAIL = re.compile(r"\bexpect_prebuild_fail(?:_count)?\b")
_RE_ATM = re.compile(r"\bATM-([0-9]+)\b")


def _read_lines(path):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            return fh.read().splitlines()
    except OSError:
        return []


def parse_mutation_file(path, type_root):
    """Parse one meta-test file → list of mutation records.

    One record per DISTINCT mutation block (the em-dash banner). The block's
    `pairs_gate` is the CM-<ID> it breaks. We also scan a small window after
    the banner for the `expect_prebuild_fail` assertion (the §1.1 contract that
    the paired gate genuinely FAILs under the mutation) and a preceding
    `# ---- Gate CM-<ID>: <desc>` header for the gate's own description.
    """
    repo_rel_basename = os.path.basename(path)
    lines = _read_lines(path)
    records = []
    seen = {}                  # gate_id -> record (first block wins)
    # pre-index the gate-header comments so a mutation can inherit the gate desc
    gate_hdr_desc = {}
    for ln in lines:
        mh = _RE_GATE_HDR.match(ln)
        if mh:
            gate_hdr_desc.setdefault(mh.group(1), mh.group(2).strip())

    for lineno, ln in enumerate(lines, start=1):
        m = _RE_MUT_DEF.search(ln)
        if not m:
            continue
        gate_id = m.group(1)
        what = (m.group(2) or "").strip()
        if gate_id in seen:
            continue
        # confirm the §1.1 contract: an expect_prebuild_fail in the next 12 lines
        proves_fail = False
        for look in lines[lineno:lineno + 12]:
            if _RE_EXPECT_FAIL.search(look):
                proves_fail = True
                break
        matm = _RE_ATM.search(what)
        atm_id = "ATM-%s" % matm.group(1) if matm else None
        gate_desc = gate_hdr_desc.get(gate_id, "")

        steps = [{
            "what": "mutate source so the paired gate's invariant breaks: %s"
                    % (what or gate_id),
            "how": "in-place mutation + expect_prebuild_fail + restore",
            "achieved": "paired gate FAILs under mutation"
                        if proves_fail else "",
            "result": "FAIL-asserted" if proves_fail else "",
            "source": "mutation-block",
        }]

        derivation_gaps = []
        if not what:
            derivation_gaps.append("no-mutation-description")
        if not proves_fail:
            # §11.4.6: state as fact only what we can see. We did NOT find an
            # expect_prebuild_fail in the window — flag it, do not assume.
            derivation_gaps.append("expect_prebuild_fail-not-found-in-window")

        rec = {
            "id": "%s-mutation" % gate_id,
            "name": "%s mutation — %s" % (gate_id, what) if what
                    else "%s mutation" % gate_id,
            "type": type_root,                  # "meta-test-mutation"
            "subtypes": ["paired_mutation"],
            "description": what,
            "description_quality": "mutation-banner" if what else "header-only",
            "step_by_step": steps,
            "how_tokens": [],
            # A mutation is itself a META-TEST: it PROVES its paired gate is not
            # a bluff gate (§11.4.107(10)). We mark bluff_proofed=True when the
            # §1.1 expect_prebuild_fail contract is present (the mutation
            # genuinely forces the gate to FAIL) — that IS the anti-bluff seam.
            "bluff_proofed": proves_fail,
            "bluff_proofed_reasons": (
                ["expect_prebuild_fail(§1.1 pair-proof)"] if proves_fail else []),
            "physical_evidence": False,
            "physical_evidence_which": [],
            "feature_class": None,
            "version": "unversioned",
            "atm_id": atm_id,
            "status": "meta_test_mutation",
            "sources_anti_bluff": False,
            "source_path": None,                # filled by scan.py
            "source_line": lineno,
            "source_file": repo_rel_basename,
            "derivation_gaps": derivation_gaps,
            # the §1.1 catalog relationship — the gate this mutation protects.
            "pairs_gate": gate_id,
            "gate_description": gate_desc,
        }
        seen[gate_id] = rec
        records.append(rec)

    return records
