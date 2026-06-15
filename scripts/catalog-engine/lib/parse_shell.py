#!/usr/bin/env python3
# catalog-engine / lib / parse_shell.py
#
# Purpose:   Parse a shell test script into a structured catalog record:
#            name, description, step_by_step, source markers (RED_MODE /
#            ab_pass_with_evidence / pc_assert / FEATURE annotation / ATM-NNN /
#            version), and the section banners that drive step_by_step.
#            §11.4.18 in-source-header-driven; every field is DERIVED from the
#            source text — never authored (the anti-bluff contract).
# Usage:     records = parse_shell_file(path, type_root)
# Inputs:    absolute path to a *.sh test file + the type-root tag.
# Outputs:   a dict matching the §2 schema (subset derivable from one file).
# Side-effects: none — read-only.
# Dependencies: stdlib only (re, os).
# Cross-refs: docs/research/test_catalog/P0_design.md §2 derivation rules.
"""Shell test-script parser for the catalog engine (decoupled, §11.4.28)."""

import os
import re

# ---- detection regexes (cited in P0 §2) --------------------------------------
_RE_RED_MODE = re.compile(r"\bRED_MODE\b|[A-Z0-9_]+_RED_MODE\b")
_RE_AB_PASS_EVIDENCE = re.compile(r"\bab_pass_with_evidence\b")
_RE_PC_ASSERT = re.compile(r"\bpc_assert_[a-z_]*|\bphysical_confirmation\b")
_RE_AV_LIVENESS = re.compile(r"\bav_quality_battery\b|\bvideo_liveness\b|\bvf_assert_[a-z_]*")
_RE_CAPTURE = re.compile(r"\bscreenrecord\b|\btinycap\b|\bscreencap\b|\barvus_probe\b")
_RE_FEATURE = re.compile(r"#\s*§?11\.4\.69\s+FEATURE:\s*([a-z][a-z0-9_]*)")
_RE_FEATURE_VAR = re.compile(r"AB_FEATURE_CLASS=([a-z][a-z0-9_]*)")
_RE_ATM = re.compile(r"\bATM-([0-9]+)\b")
_RE_VERSION = re.compile(r"\bv([0-9]+\.[0-9]+(?:\.[0-9]+)?)\b")
_RE_AB_RUN_N = re.compile(r"\bab_run_n_times\b")
_RE_SECTION_BANNER = re.compile(r"^#\s*={2,}\s*(.+?)\s*={2,}\s*$")
_RE_NUMBERED = re.compile(r"^#\s*\((\d+)\)\s*(.+)$")
_RE_AB_SEND_ACTION = re.compile(r"ab_send_action\s+[\"']([^\"']+)[\"']")
_RE_AB_PASS_DESC = re.compile(r"ab_pass(?:_with_evidence)?\s+[\"']([^\"']+)[\"']")
_RE_SOURCES_ANTIBLUFF = re.compile(r"anti_bluff\.sh")

# header title forms: "# <name> — ..." / "# <name>: ..." / "# <name>.sh — ..."
_RE_HEADER_TITLE = re.compile(r"^#\s+(\S[^—:]*?(?:\.sh)?)\s*[—:-]\s*(.+)$")
_RE_PURPOSE = re.compile(r"^#\s*(?:Purpose|PURPOSE):\s*(.*)$")


def _read_lines(path):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            return fh.read().splitlines()
    except OSError:
        return []


def _header_block(lines):
    """Return the leading comment block (lines after shebang up to first blank
    or first non-comment line)."""
    block = []
    started = False
    for i, ln in enumerate(lines):
        if i == 0 and ln.startswith("#!"):
            continue
        if ln.startswith("#"):
            started = True
            block.append(ln)
            continue
        # stop at first blank or first executable line once block started
        if started:
            break
        if ln.strip() == "":
            # leading blank before any comment — keep scanning
            continue
        break
    return block


def _derive_name_description(lines, basename):
    header = _header_block(lines)
    name = None
    description = None
    purpose = None
    # Look for a Purpose: line anywhere in header (§11.4.18)
    for ln in header:
        m = _RE_PURPOSE.match(ln)
        if m and m.group(1).strip():
            purpose = m.group(1).strip()
            break
    # Title line: first comment after shebang of "# <name> — <desc>"
    for ln in header:
        m = _RE_HEADER_TITLE.match(ln)
        if m:
            cand_name = m.group(1).strip()
            # prefer the basename-matching title; else first dashed title
            name = cand_name
            description = m.group(2).strip()
            break
    if not name:
        name = basename
    if purpose:
        description = purpose
    if not description:
        # fall back to the first non-title comment paragraph
        para = []
        for ln in header[1:]:
            txt = ln.lstrip("#").strip()
            if txt == "" and para:
                break
            if txt:
                para.append(txt)
        description = " ".join(para) if para else ""
    quality = "purpose-header" if purpose else (
        "title-header" if description else "header-only"
    )
    return name, description, quality


def _derive_steps(lines):
    """Extract step_by_step from numbered header blocks (# (1) ...), section
    banners (# === SECTION ... ===), ab_send_action (the WHAT), and
    ab_pass/ab_pass_with_evidence descriptions (the RESULT)."""
    steps = []
    # 1) numbered header steps
    for ln in lines[:80]:
        m = _RE_NUMBERED.match(ln)
        if m:
            steps.append({
                "what": m.group(2).strip(), "how": "", "achieved": "",
                "result": "", "source": "header-numbered",
            })
    # 2) section banners + actions + pass-descriptions (body scan)
    for ln in lines:
        mb = _RE_SECTION_BANNER.match(ln)
        if mb:
            steps.append({
                "what": mb.group(1).strip(), "how": "", "achieved": "",
                "result": "", "source": "section-banner",
            })
            continue
        ma = _RE_AB_SEND_ACTION.search(ln)
        if ma:
            steps.append({
                "what": ma.group(1).strip(), "how": "ab_send_action",
                "achieved": "", "result": "", "source": "ab_send_action",
            })
            continue
        mp = _RE_AB_PASS_DESC.search(ln)
        if mp:
            steps.append({
                "what": "", "how": "", "achieved": mp.group(1).strip(),
                "result": "PASS", "source": "ab_pass",
            })
    return steps


def _derive_how_tokens(lines):
    """Collect the distinct command tokens the test runs (dumpsys/tinycap/
    screenrecord/ffprobe/...) for the step `how` summary."""
    tokens = set()
    cmd_re = re.compile(
        r"\b(dumpsys|tinycap|tinyplay|screenrecord|screencap|ffprobe|ffmpeg|"
        r"aplay|arvus_probe|uiautomator|am|pm|input|logcat|getprop|setprop|"
        r"cat|grep)\b"
    )
    for ln in lines:
        s = ln.strip()
        if s.startswith("#"):
            continue
        for m in cmd_re.finditer(s):
            tokens.add(m.group(1))
    return sorted(tokens)


def parse_shell_file(path, type_root):
    """Parse one shell test → record dict (subset of the §2 schema)."""
    basename = os.path.basename(path)
    stem = re.sub(r"\.sh$", "", basename)
    lines = _read_lines(path)
    text = "\n".join(lines)

    name, description, desc_quality = _derive_name_description(lines, stem)
    steps = _derive_steps(lines)
    how_tokens = _derive_how_tokens(lines)

    # code_text = executable lines only (comments stripped). Code-marker
    # detection (RED_MODE / ab_pass_with_evidence / pc_assert / capture tools)
    # runs on code_text so a header that NAMES a marker in prose (e.g. a
    # fixture's "no RED_MODE here" sentence, or a test's own doc-comment) does
    # NOT falsely fire the marker. The §11.4.69 FEATURE annotation is BY DESIGN
    # a comment line, so feature_class still scans the full text.
    code_lines = []
    for ln in lines:
        s = ln.lstrip()
        if s.startswith("#") or s.startswith("#!"):
            continue
        # strip a trailing inline comment (best-effort; not quote-aware, but
        # marker tokens never legitimately live inside a trailing # comment)
        code = ln.split(" #", 1)[0]
        code_lines.append(code)
    code_text = "\n".join(code_lines)

    # sub-type tags
    subtypes = []
    if basename.endswith("_red.sh") or _RE_RED_MODE.search(code_text):
        subtypes.append("red_polarity")
    if "stress_chaos" in basename:
        subtypes.append("stress_chaos")
    elif "_chaos" in basename:
        subtypes.append("chaos")
    if "/ui_driven/" in path.replace("\\", "/"):
        subtypes.append("ui_driven")
    if "/tests/lib/" in path.replace("\\", "/"):
        subtypes.append("lib_helper")

    # bluff_proofed (code-marker detection on code_text only)
    bluff_reasons = []
    if basename.endswith("_red.sh"):
        bluff_reasons.append("filename:_red.sh")
    if _RE_RED_MODE.search(code_text):
        bluff_reasons.append("RED_MODE-marker")
    if _RE_PC_ASSERT.search(code_text):
        bluff_reasons.append("pc_assert")
    if _RE_AB_RUN_N.search(code_text):
        bluff_reasons.append("ab_run_n_times(det-consistency)")
    bluff_proofed = bool(bluff_reasons)

    # physical_evidence (code-marker detection on code_text only)
    phys = []
    if _RE_AB_PASS_EVIDENCE.search(code_text):
        phys.append("ab_pass_with_evidence")
    if _RE_PC_ASSERT.search(code_text):
        phys.append("pc_assert")
    if _RE_AV_LIVENESS.search(code_text):
        phys.append("av_liveness")
    if re.search(r"\bscreenrecord\b", code_text):
        phys.append("screen_recording")
    if re.search(r"\bscreencap\b", code_text):
        phys.append("screen_capture")
    if re.search(r"\btinycap\b", code_text):
        phys.append("audio_capture")
    if re.search(r"\barvus_probe\b", code_text):
        phys.append("sink_arvus")
    # The §11.4.69 FEATURE annotation is a STRUCTURED comment marker (by design
    # a comment), so it scans the full text — distinct from prose mentions of
    # capture tools, which must NOT count.
    if _RE_FEATURE.search(text) or _RE_FEATURE_VAR.search(code_text):
        phys.append("feature_annotation")
    physical_evidence = bool(phys)

    # feature_class
    mfeat = _RE_FEATURE.search(text) or _RE_FEATURE_VAR.search(text)
    feature_class = mfeat.group(1) if mfeat else None

    # atm_id (first occurrence)
    matm = _RE_ATM.search(text)
    atm_id = "ATM-%s" % matm.group(1) if matm else None

    # version (header vN.N token in the title/description line)
    version = None
    mver = _RE_VERSION.search(description or "")
    if not mver:
        # check first 5 header lines
        for ln in lines[:6]:
            mver = _RE_VERSION.search(ln)
            if mver:
                break
    if mver:
        version = "v" + mver.group(1)

    # status
    if "lib_helper" in subtypes:
        status = "lib_helper"
    elif "red_polarity" in subtypes:
        status = "red_baseline"
    else:
        status = "active"

    derivation_gaps = []
    if not description:
        derivation_gaps.append("no-description-header(§11.4.18)")
    if not steps:
        derivation_gaps.append("no-step-by-step-derivable")
    if not version:
        derivation_gaps.append("version-UNCONFIRMED")
    if feature_class is None and type_root == "on_device":
        derivation_gaps.append("feature_class-absent")

    return {
        "id": stem,
        "name": name,
        "type": type_root,
        "subtypes": subtypes,
        "description": description,
        "description_quality": desc_quality,
        "step_by_step": steps,
        "how_tokens": how_tokens,
        "bluff_proofed": bluff_proofed,
        "bluff_proofed_reasons": bluff_reasons,
        "physical_evidence": physical_evidence,
        "physical_evidence_which": phys,
        "feature_class": feature_class,
        "version": version or "unversioned",
        "atm_id": atm_id,
        "status": status,
        "sources_anti_bluff": bool(_RE_SOURCES_ANTIBLUFF.search(text)),
        "source_path": None,   # filled by scan.py (repo-relative)
        "derivation_gaps": derivation_gaps,
    }
