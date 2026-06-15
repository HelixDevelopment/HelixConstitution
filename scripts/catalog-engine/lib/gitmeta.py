#!/usr/bin/env python3
# catalog-engine / lib / gitmeta.py
#
# Purpose:   Derive created/updated dates per file from git history in ONE
#            `git log --name-only --follow`-free pass (P0 §3 perf note,
#            §11.4.82 iteration-speedup): a single `git log --name-status`
#            over the whole repo builds a path -> [dates] index in memory.
# Usage:     idx = build_date_index(repo); created,updated = idx.dates(path)
# Inputs:    repo root path.
# Outputs:   a DateIndex with .dates(repo_relative_path) -> (created, updated).
# Side-effects: runs `git log` read-only; honest UNCONFIRMED on failure.
# Dependencies: git on PATH (honest fallback if absent).
# Cross-refs: P0_design.md §3.
"""Git created/updated-date index (single-pass, decoupled)."""

import subprocess


class DateIndex:
    def __init__(self):
        # path -> list of ISO dates (newest first, as git log emits)
        self._map = {}

    def add(self, path, date):
        self._map.setdefault(path, []).append(date)

    def dates(self, repo_rel_path):
        d = self._map.get(repo_rel_path)
        if not d:
            return (None, None)
        # git log emits newest-first; updated = first, created = last
        return (d[-1], d[0])


def build_date_index(repo):
    """One `git log --name-only` pass → path->[dates] index. Honest empty
    index (all dates UNCONFIRMED) if git is unavailable or the call fails."""
    idx = DateIndex()
    try:
        # %x00 record separator; date then NUL then the file list (one per line)
        proc = subprocess.run(
            ["git", "-C", repo, "log", "--no-merges",
             "--date=short", "--pretty=format:@@@%ad", "--name-only"],
            capture_output=True, text=True, timeout=120,
        )
    except (OSError, subprocess.SubprocessError):
        return idx
    if proc.returncode != 0:
        return idx
    cur_date = None
    for raw in proc.stdout.splitlines():
        line = raw.rstrip("\n")
        if line.startswith("@@@"):
            cur_date = line[3:].strip()
            continue
        if not line.strip():
            continue
        if cur_date:
            idx.add(line.strip(), cur_date)
    return idx
