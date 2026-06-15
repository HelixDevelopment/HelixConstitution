#!/usr/bin/env python3
# charts-engine / lib / render.py
#
# Purpose:   Headless chart-rendering primitives (matplotlib Agg backend — no
#            X server). P1 renderer. vl-convert/Vega-Lite is the P2 upgrade
#            (deterministic, declarative) per the P0 tool study; matplotlib is
#            chosen for P1 because it is already on the host (no install friction).
# Inputs:    label/value row lists from lib/wi_query.py.
# Outputs:   PNG + SVG chart files (deterministic enough for the golden validator:
#            same data -> identical pixel dimensions + non-empty bytes).
# Side-effects: writes files under the caller-provided output dir ONLY.
# Dependencies: matplotlib (Agg). No project-specific data anywhere (§11.4.28).
"""Headless chart rendering for the workable-items charts engine."""

import os

import matplotlib

# Force the non-interactive Agg backend BEFORE importing pyplot so no DISPLAY /
# X server is ever required (CI + headless host safe).
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402  (must follow matplotlib.use)


# Fixed figure geometry so the golden validator can assert exact pixel
# dimensions deterministically (a degenerate/empty render would mismatch).
_FIG_W_IN = 10.0
_FIG_H_IN = 6.0
_DPI = 100  # => 1000 x 600 px canvas

# A small, stable, colour-blind-friendly palette (Okabe-Ito subset). Bars cycle
# through it deterministically by index so re-renders are byte-stable.
_PALETTE = [
    "#0072B2", "#E69F00", "#009E73", "#D55E00",
    "#CC79A7", "#56B4E9", "#F0E442", "#999999",
]


def _truncate(label, limit=42):
    """Long free-text labels (e.g. descriptive severity strings) are truncated
    for legibility — the underlying DB value is unchanged; this is display only."""
    label = str(label)
    return label if len(label) <= limit else label[: limit - 1] + "…"


def bar_chart(rows, title, xlabel, ylabel, out_basepath, pending_data_note=None):
    """Render a horizontal bar chart from (label, count) rows.

    rows:            list[(label, int)] drawn from REAL DB data.
    out_basepath:    path WITHOUT extension; '.png' + '.svg' are written.
    pending_data_note: if set, stamped on the figure (honest §11.4.6 marker for
                     charts that can only show a snapshot, not a time-series).
    Returns dict {png, svg, rows_drawn, total}. Empty rows render an explicit
    'no data' chart (never a fabricated bar)."""
    labels = [_truncate(r[0]) for r in rows]
    values = [int(r[1]) for r in rows]
    total = sum(values)

    fig, ax = plt.subplots(figsize=(_FIG_W_IN, _FIG_H_IN), dpi=_DPI)
    if rows:
        ypos = range(len(labels))
        colors = [_PALETTE[i % len(_PALETTE)] for i in range(len(labels))]
        ax.barh(list(ypos), values, color=colors)
        ax.set_yticks(list(ypos))
        ax.set_yticklabels(labels, fontsize=8)
        ax.invert_yaxis()  # largest at top
        for i, v in enumerate(values):
            ax.text(v, i, f" {v}", va="center", fontsize=8)
        ax.set_xlabel(xlabel)
        ax.set_ylabel(ylabel)
    else:
        # Honest empty-state — NOT a fabricated data point (§11.4.6).
        ax.text(0.5, 0.5, "no data in DB for this chart",
                ha="center", va="center", transform=ax.transAxes, fontsize=12)
        ax.set_axis_off()

    full_title = title if total == 0 else f"{title}  (n={total})"
    ax.set_title(full_title, fontsize=12, fontweight="bold")

    if pending_data_note:
        fig.text(0.5, 0.01, pending_data_note, ha="center", fontsize=8,
                 color="#B00020", style="italic", wrap=True)

    fig.tight_layout(rect=(0, 0.03, 1, 1) if pending_data_note else None)

    os.makedirs(os.path.dirname(out_basepath), exist_ok=True)
    png = out_basepath + ".png"
    svg = out_basepath + ".svg"
    fig.savefig(png)
    fig.savefig(svg)
    plt.close(fig)
    return {"png": png, "svg": svg, "rows_drawn": len(rows), "total": total}


def grouped_pair_chart(pairs, title, out_basepath):
    """Render a small 2-3 category open-vs-closed snapshot.
    pairs: list[(label, int)] (e.g. [('Open', N), ('Closed', M)]).
    Same return contract as bar_chart."""
    return bar_chart(pairs, title, xlabel="Items", ylabel="", out_basepath=out_basepath)
