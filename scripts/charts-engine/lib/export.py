#!/usr/bin/env python3
# charts-engine / lib / export.py
#
# Purpose:   Four-format wrapper (§11.4.65) for a chart landing document:
#            write the Markdown landing doc next to the PNG/SVG, then render
#            HTML (pandoc) + PDF (weasyprint) siblings.
# Inputs:    a landing-doc title + body markdown + output path.
# Outputs:   <doc>.md + <doc>.html + <doc>.pdf. HTML/PDF are best-effort —
#            a missing pandoc/weasyprint is reported HONESTLY as a SKIP, never
#            a fake success (§11.4.106 ToolAbsentError discipline).
# Side-effects: writes files under the caller-provided dir ONLY; shells out to
#            pandoc + weasyprint if present on PATH.
# Dependencies: pandoc + weasyprint (optional — honest SKIP if absent).
"""Markdown landing-doc + HTML + PDF export for chart landing pages."""

import os
import shutil
import subprocess


def _tool(name):
    return shutil.which(name)


def write_landing_doc(md_path, markdown_body):
    """Write the Markdown landing doc (the source of truth for the export)."""
    os.makedirs(os.path.dirname(md_path), exist_ok=True)
    with open(md_path, "w", encoding="utf-8") as fh:
        fh.write(markdown_body)
    return md_path


def export_html_pdf(md_path):
    """Render <doc>.html (pandoc) + <doc>.pdf (weasyprint) from the Markdown.
    Returns dict {html, pdf, skipped:[...]} — `skipped` enumerates any
    unavailable tool with an honest reason (never a fabricated artefact)."""
    base = os.path.splitext(md_path)[0]
    html_path = base + ".html"
    pdf_path = base + ".pdf"
    result = {"html": None, "pdf": None, "skipped": []}

    doc_dir = os.path.dirname(os.path.abspath(md_path))
    abs_md = os.path.abspath(md_path)
    abs_html = os.path.abspath(html_path)
    pandoc = _tool("pandoc")
    if pandoc:
        # Run pandoc FROM the doc directory (cwd=doc_dir) with absolute in/out
        # paths so the relative PNG references resolve, and --embed-resources
        # base64-inlines them → portable single-file HTML (§11.4.65).
        subprocess.run(
            [pandoc, abs_md, "-s", "--embed-resources",
             "--resource-path", doc_dir, "-o", abs_html],
            check=True, timeout=60, cwd=doc_dir,
        )
        result["html"] = html_path
    else:
        result["skipped"].append("html: pandoc absent on PATH")

    weasyprint = _tool("weasyprint")
    if weasyprint and result["html"]:
        subprocess.run(
            [weasyprint, html_path, pdf_path],
            check=True, timeout=60,
        )
        result["pdf"] = pdf_path
    elif not weasyprint:
        result["skipped"].append("pdf: weasyprint absent on PATH")
    elif not result["html"]:
        result["skipped"].append("pdf: skipped because html step skipped")

    return result
