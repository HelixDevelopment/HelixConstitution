#!/usr/bin/env python3
# charts-engine / generate_charts.py
#
# Purpose:   Universal workable-items charts engine entry point (BG-004, P1).
#            Generates the distribution + open-vs-closed snapshot chart family
#            from a workable-items SQLite DB, plus an honest PENDING_DATA
#            burndown placeholder while item_history lacks closure events.
# Usage:     python3 generate_charts.py --db <workable_items.db> \
#                                        --out <output-root-dir> \
#                                        --context <context-name>
# Inputs:    --db (required), --out (required), --context (optional, default
#            'default'). ZERO consumer-project specifics — the consumer passes
#            DB path + output root + context at runtime (§11.4.28 decoupled).
# Outputs:   <out>/<context>/<chart>.{png,svg} + a landing.md + landing.{html,pdf}
#            + a manifest.json citing the REAL row counts each chart drew from.
# Side-effects: writes only under <out>/<context>/.
# Dependencies: lib/wi_query.py, lib/render.py, lib/export.py; matplotlib;
#            pandoc + weasyprint (optional, honest SKIP if absent).
# Cross-refs: docs/research/charts_engine_bg004/P0_catalogue_and_tools.md,
#            P1_build_report.md.
"""Universal workable-items charts engine — P1 generators."""

import argparse
import datetime
import json
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_HERE, "lib"))

import wi_query  # noqa: E402
import render  # noqa: E402
import export  # noqa: E402


def _utc_now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _md_table(header, rows):
    out = ["| " + " | ".join(header) + " |",
           "|" + "|".join(["---"] * len(header)) + "|"]
    for r in rows:
        out.append("| " + " | ".join(str(c) for c in r) + " |")
    return "\n".join(out)


def generate(db_path, out_root, context):
    """Generate the P1 chart family. Returns a manifest dict citing REAL counts."""
    if not os.path.isfile(db_path):
        raise SystemExit(f"ERROR: --db not found: {db_path}")

    ctx_dir = os.path.join(out_root, context)
    os.makedirs(ctx_dir, exist_ok=True)

    total = wi_query.total_items(db_path)
    manifest = {
        "engine": "charts-engine",
        "phase": "P1",
        "generated_at": _utc_now(),
        "db_path": os.path.abspath(db_path),
        "context": context,
        "total_items_in_db": total,
        "charts": [],
        "renderer": "matplotlib-agg",
        "renderer_p2_upgrade": "vl-convert/Vega-Lite (deterministic, declarative)",
    }

    # --- (a) status distribution ---
    status_rows = wi_query.status_distribution(db_path)
    status = render.bar_chart(
        status_rows, "Workable items by Status", "Items", "Status",
        os.path.join(ctx_dir, "status_distribution"),
    )
    manifest["charts"].append({
        "name": "status_distribution", "title": "Workable items by Status",
        "rows_drawn": status["rows_drawn"], "items_charted": status["total"],
        "data": [[lbl, n] for lbl, n in status_rows],
        "png": os.path.relpath(status["png"], out_root),
        "svg": os.path.relpath(status["svg"], out_root),
        "pending_data": False,
    })

    # --- (b) type distribution ---
    type_rows = wi_query.type_distribution(db_path)
    typ = render.bar_chart(
        type_rows, "Workable items by Type", "Items", "Type",
        os.path.join(ctx_dir, "type_distribution"),
    )
    manifest["charts"].append({
        "name": "type_distribution", "title": "Workable items by Type",
        "rows_drawn": typ["rows_drawn"], "items_charted": typ["total"],
        "data": [[lbl, n] for lbl, n in type_rows],
        "png": os.path.relpath(typ["png"], out_root),
        "svg": os.path.relpath(typ["svg"], out_root),
        "pending_data": False,
    })

    # --- (c) severity distribution ---
    sev_rows = wi_query.severity_distribution(db_path)
    sev = render.bar_chart(
        sev_rows, "Workable items by Severity", "Items", "Severity",
        os.path.join(ctx_dir, "severity_distribution"),
    )
    manifest["charts"].append({
        "name": "severity_distribution", "title": "Workable items by Severity",
        "rows_drawn": sev["rows_drawn"], "items_charted": sev["total"],
        "data": [[lbl, n] for lbl, n in sev_rows],
        "png": os.path.relpath(sev["png"], out_root),
        "svg": os.path.relpath(sev["svg"], out_root),
        "pending_data": False,
    })

    # --- (d) open-vs-closed snapshot ---
    ovc = wi_query.open_vs_closed(db_path)
    ovc_pairs = [
        ("Open (Issues)", ovc["by_location"].get("Issues", 0)),
        ("Closed (Fixed)", ovc["by_location"].get("Fixed", 0)),
    ]
    ovc_chart = render.grouped_pair_chart(
        ovc_pairs, "Open vs Closed (by tracker location)",
        os.path.join(ctx_dir, "open_vs_closed"),
    )
    manifest["charts"].append({
        "name": "open_vs_closed", "title": "Open vs Closed (by tracker location)",
        "rows_drawn": ovc_chart["rows_drawn"], "items_charted": ovc_chart["total"],
        "data": [[lbl, n] for lbl, n in ovc_pairs],
        "by_status_terminality": ovc["by_status_terminality"],
        "png": os.path.relpath(ovc_chart["png"], out_root),
        "svg": os.path.relpath(ovc_chart["svg"], out_root),
        "pending_data": False,
    })

    # --- (e) burndown: HONEST PENDING_DATA snapshot (no fabricated time-series) ---
    hist = wi_query.history_event_summary(db_path)
    has_closure = wi_query.has_closure_history(db_path)
    if has_closure:
        # Closure events exist -> a real time-series is possible. P1 still ships
        # the snapshot remaining-count; the true time-series lands in P2/P3.
        pending_note = None
        burndown_pending = False
    else:
        pending_note = (
            "PENDING_DATA: time-series burndown requires item_history "
            "closure/reopen events; none recorded yet — snapshot shown instead."
        )
        burndown_pending = True
    open_remaining = ovc["by_status_terminality"]["Open"]
    closed_done = ovc["by_status_terminality"]["Closed"]
    burndown_rows = [("Remaining (open)", open_remaining), ("Done (closed)", closed_done)]
    burndown = render.bar_chart(
        burndown_rows,
        "Burndown snapshot (remaining vs done)" if burndown_pending
        else "Burndown snapshot",
        "Items", "", os.path.join(ctx_dir, "burndown_snapshot"),
        pending_data_note=pending_note,
    )
    manifest["charts"].append({
        "name": "burndown_snapshot", "title": "Burndown snapshot",
        "rows_drawn": burndown["rows_drawn"], "items_charted": burndown["total"],
        "data": [[lbl, n] for lbl, n in burndown_rows],
        "png": os.path.relpath(burndown["png"], out_root),
        "svg": os.path.relpath(burndown["svg"], out_root),
        "pending_data": burndown_pending,
        "pending_data_reason": pending_note,
        "item_history_event_summary": {
            ev: {"count": c, "min_date": mn, "max_date": mx}
            for ev, (c, mn, mx) in hist.items()
        },
    })

    # --- Landing doc (Markdown) + four-format export ---
    md_lines = [
        f"# Workable-items charts — context `{context}`",
        "",
        f"**Generated:** {manifest['generated_at']}  ",
        f"**Source DB:** `{manifest['db_path']}`  ",
        f"**Total items in DB:** {total}  ",
        f"**Renderer:** {manifest['renderer']} "
        f"(P2 upgrade: {manifest['renderer_p2_upgrade']})",
        "",
        "Every chart below is generated from REAL workable-items DB rows. The "
        "row count each chart drew from is cited (§11.4.6 — no fabricated data).",
        "",
    ]
    for c in manifest["charts"]:
        md_lines.append(f"## {c['title']}")
        md_lines.append("")
        if c.get("pending_data"):
            md_lines.append(f"> {c['pending_data_reason']}")
            md_lines.append("")
        md_lines.append(f"![{c['name']}]({c['name']}.png)")
        md_lines.append("")
        md_lines.append(f"*Rows drawn: {c['rows_drawn']} · "
                        f"items charted: {c['items_charted']}*")
        md_lines.append("")
        md_lines.append(_md_table(["Label", "Count"], c["data"]))
        md_lines.append("")
    md_body = "\n".join(md_lines) + "\n"

    md_path = os.path.join(ctx_dir, "landing.md")
    export.write_landing_doc(md_path, md_body)
    exp = export.export_html_pdf(md_path)
    manifest["landing_doc"] = {
        "md": os.path.relpath(md_path, out_root),
        "html": os.path.relpath(exp["html"], out_root) if exp["html"] else None,
        "pdf": os.path.relpath(exp["pdf"], out_root) if exp["pdf"] else None,
        "export_skipped": exp["skipped"],
    }

    manifest_path = os.path.join(ctx_dir, "manifest.json")
    with open(manifest_path, "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=2)
    manifest["manifest_path"] = os.path.relpath(manifest_path, out_root)
    return manifest


def main(argv=None):
    ap = argparse.ArgumentParser(description="Universal workable-items charts engine (P1).")
    ap.add_argument("--db", required=True, help="path to a workable_items.db")
    ap.add_argument("--out", required=True, help="output root directory")
    ap.add_argument("--context", default="default", help="context/sub-directory name")
    args = ap.parse_args(argv)

    manifest = generate(args.db, args.out, args.context)
    print(json.dumps({
        "total_items_in_db": manifest["total_items_in_db"],
        "context": manifest["context"],
        "charts": [
            {"name": c["name"], "rows_drawn": c["rows_drawn"],
             "items_charted": c["items_charted"], "pending_data": c["pending_data"]}
            for c in manifest["charts"]
        ],
        "landing_doc": manifest["landing_doc"],
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
