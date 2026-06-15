#!/usr/bin/env python3
# catalog-engine / lib / derive.py
#
# Purpose:   Cluster/component taxonomy derivation (§2 cluster rule). Loads a
#            PROJECT-injected taxonomy config (keyword->cluster map) and derives
#            the cluster + component bucket from name + feature_class + tokens.
#            §11.4.28 — the engine knows NO clusters; the project injects them.
# Usage:     tx = load_taxonomy(path); cluster = tx.cluster_for(record)
# Inputs:    a taxonomy YAML/JSON path (keyword map); a record dict.
# Outputs:   cluster string + component string (UNCONFIRMED -> 'uncategorised').
# Side-effects: none.
# Dependencies: stdlib only (json; minimal YAML fallback).
# Cross-refs: P0_design.md §2 + §4 hierarchy.
"""Cluster/component derivation from an injected taxonomy (decoupled)."""

import json
import os
import re


def _load_mapping(path):
    """Load a {keyword: cluster} mapping from JSON or a flat 'key: value' YAML.
    No external YAML dependency — a tiny flat-map parser covers the contract."""
    if not path or not os.path.isfile(path):
        return {}, []
    text = open(path, "r", encoding="utf-8").read()
    if path.endswith(".json"):
        data = json.loads(text)
        return data.get("keyword_cluster", {}), data.get("clusters", [])
    # flat YAML: a 'keyword_cluster:' block of '  keyword: cluster' lines and
    # an optional 'clusters:' list of '  - name' lines.
    kw = {}
    clusters = []
    section = None
    for raw in text.splitlines():
        ln = raw.rstrip()
        if not ln.strip() or ln.lstrip().startswith("#"):
            continue
        if re.match(r"^\S", ln):
            section = ln.split(":", 1)[0].strip()
            continue
        if section == "keyword_cluster" and ":" in ln:
            k, v = ln.strip().split(":", 1)
            kw[k.strip()] = v.strip()
        elif section == "clusters" and ln.strip().startswith("-"):
            clusters.append(ln.strip()[1:].strip())
    return kw, clusters


class Taxonomy:
    def __init__(self, keyword_cluster, clusters):
        # longest keyword first so 'video_routing' beats 'video'
        self._kw = sorted(keyword_cluster.items(),
                          key=lambda kv: -len(kv[0]))
        self.clusters = clusters

    def cluster_for(self, record):
        hay = " ".join(filter(None, [
            record.get("id", ""), record.get("name", ""),
            record.get("feature_class") or "",
            " ".join(record.get("subtypes", [])),
            record.get("description", "") or "",
        ])).lower()
        for kw, cl in self._kw:
            if kw.lower() in hay:
                return cl
        return "uncategorised"

    def component_for(self, record, cluster):
        """Finer feature bucket = cluster/<first distinguishing token>."""
        stem = record.get("id", "")
        # strip the test_ prefix + common suffixes for a readable component
        comp = re.sub(r"^test_", "", stem)
        comp = re.sub(r"(_red|_stress_chaos|_chaos|_guard)$", "", comp)
        # collapse very long stems to first 4 underscore tokens
        toks = comp.split("_")
        if len(toks) > 4:
            comp = "_".join(toks[:4])
        return "%s/%s" % (cluster, comp) if cluster != "uncategorised" else comp


def load_taxonomy(path):
    kw, clusters = _load_mapping(path)
    return Taxonomy(kw, clusters)
