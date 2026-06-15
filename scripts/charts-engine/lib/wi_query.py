#!/usr/bin/env python3
# charts-engine / lib / wi_query.py
#
# Purpose:   Read-only query layer over the workable-items SQLite DB
#            (§11.4.93/.95 single source of truth). Mirrors the schema CONTRACT
#            consumed by the Go `workable-items` report subcommand — knows ONLY
#            the column names, NEVER any project-specific data (§11.4.28 decoupled).
# Inputs:    --db <path> (a workable_items.db conforming to the documented schema).
# Outputs:   Python dicts/lists of (label, count) rows + history facts; NO writes.
# Side-effects: NONE (opens the DB read-only via the `file:...?mode=ro` URI).
# Dependencies: python3 stdlib `sqlite3` only.
# Cross-refs: docs/research/charts_engine_bg004/P0_catalogue_and_tools.md §2 (schema),
#            constitution/scripts/workable-items/cmd/workable-items/db.go (sibling Go layer).
"""Read-only workable-items query layer for the charts engine.

Anti-bluff (§11.4.6 / §11.4.107): every query returns the REAL rows from the DB
plus the exact total row count it drew from, so a generator can cite it. There is
no fabricated data path — an empty result returns an empty list, never a synthetic
filler row.
"""

import sqlite3
from contextlib import contextmanager


# The documented status closed-set (§11.4.15 / §11.4.21 / §11.4.90). "Open" =
# any non-terminal status; "closed" = the four terminal (→ Fixed.md) statuses.
TERMINAL_STATUSES = {
    "Fixed (→ Fixed.md)",
    "Implemented (→ Fixed.md)",
    "Completed (→ Fixed.md)",
    "Obsolete (→ Fixed.md)",
}

# Closure event types in item_history (the time-series feed for burndown/CFD).
CLOSURE_EVENTS = {"Fixed", "Implemented", "Completed", "Obsolete"}


class QueryError(Exception):
    """Raised on a malformed / missing / non-conforming DB (honest FAIL, never a
    silent empty result that a caller could mistake for 'no data')."""


@contextmanager
def _connect_ro(db_path):
    """Open the DB strictly read-only. A missing file or a file lacking the
    `items` table raises QueryError so a corrupt/empty DB FAILs loudly (the
    golden-bad self-validation path of §11.4.107(10))."""
    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    except sqlite3.OperationalError as exc:
        raise QueryError(f"cannot open DB read-only: {db_path}: {exc}") from exc
    try:
        # Probe the contract: the `items` table MUST exist with the expected cols.
        cur = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='items'"
        )
        if cur.fetchone() is None:
            raise QueryError(
                f"DB {db_path} has no 'items' table — not a workable-items DB"
            )
        yield conn
    finally:
        conn.close()


def total_items(db_path):
    with _connect_ro(db_path) as conn:
        return conn.execute("SELECT COUNT(*) FROM items").fetchone()[0]


# Allow-list of the ONLY SQL label-expressions this module may build a GROUP BY
# from. SQLite cannot bind a column/identifier as a `?` parameter, so the SELECT
# list is necessarily string-built — the allow-list guarantees every interpolated
# value is a vetted, hardcoded constant defined HERE, never caller/user input.
# (Closes CWE-89: no untrusted data can reach the f-string.)
_ALLOWED_LABEL_EXPRS = {
    "status",
    "type",
    "COALESCE(NULLIF(severity,''),'(unset)')",
}


def _group_count(db_path, label_expr, order_desc=True):
    """Generic GROUP BY count over a vetted label-expression. `label_expr` MUST
    be one of `_ALLOWED_LABEL_EXPRS` — any other value raises QueryError BEFORE
    any SQL is built, so no untrusted string can ever be interpolated.
    Returns list[(label, count)]; total drawn = sum(count)."""
    if label_expr not in _ALLOWED_LABEL_EXPRS:
        raise QueryError(
            f"refusing to GROUP BY non-allow-listed expression: {label_expr!r}"
        )
    order = "ORDER BY COUNT(*) DESC, 1 ASC" if order_desc else "ORDER BY 1 ASC"
    with _connect_ro(db_path) as conn:
        # label_expr is provably a member of the frozen allow-list above —
        # the f-string interpolates only a vetted constant (no SQL injection).
        rows = conn.execute(  # nosec B608 — interpolated value is allow-listed
            f"SELECT {label_expr} AS label, COUNT(*) AS n "  # noqa: S608
            f"FROM items GROUP BY label {order}"
        ).fetchall()
    return [(str(r[0]), int(r[1])) for r in rows]


def status_distribution(db_path):
    return _group_count(db_path, "status")


def type_distribution(db_path):
    return _group_count(db_path, "type")


def severity_distribution(db_path):
    # Severity is free-text; collapse NULL/'' to '(unset)'. Long descriptive
    # severities are kept verbatim (the DB is the source of truth — we do not
    # invent buckets), but a generator may choose to truncate for legibility.
    return _group_count(db_path, "COALESCE(NULLIF(severity,''),'(unset)')")


def open_vs_closed(db_path):
    """Open vs closed snapshot, two complementary cuts:
      - by current_location: Issues (open tracker) vs Fixed (closed tracker)
      - by status terminality: non-terminal vs terminal status
    Returns dict with both so the generator can show the honest split."""
    with _connect_ro(db_path) as conn:
        loc = conn.execute(
            "SELECT current_location, COUNT(*) FROM items GROUP BY current_location"
        ).fetchall()
        statuses = conn.execute("SELECT status, COUNT(*) FROM items GROUP BY status").fetchall()
    by_location = {str(r[0]): int(r[1]) for r in loc}
    open_n = sum(int(r[1]) for r in statuses if r[0] not in TERMINAL_STATUSES)
    closed_n = sum(int(r[1]) for r in statuses if r[0] in TERMINAL_STATUSES)
    return {
        "by_location": by_location,
        "by_status_terminality": {"Open": open_n, "Closed": closed_n},
    }


def history_event_summary(db_path):
    """Facts about item_history coverage — the honest gate for time-series charts.
    Returns dict event_type -> (count, min_date, max_date). EMPTY closure events
    means a real burndown is PENDING_DATA (§11.4.6)."""
    with _connect_ro(db_path) as conn:
        # item_history may legitimately be absent in a minimal DB; treat as empty.
        has = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='item_history'"
        ).fetchone()
        if has is None:
            return {}
        rows = conn.execute(
            "SELECT event_type, COUNT(*), MIN(on_date), MAX(on_date) "
            "FROM item_history GROUP BY event_type"
        ).fetchall()
    return {str(r[0]): (int(r[1]), r[2], r[3]) for r in rows}


def has_closure_history(db_path):
    """True iff item_history carries at least one closure/reopen event — the
    precondition for a faithful (non-bluff) time-series burndown."""
    summ = history_event_summary(db_path)
    return any(ev in summ and summ[ev][0] > 0 for ev in CLOSURE_EVENTS | {"Reopened"})
