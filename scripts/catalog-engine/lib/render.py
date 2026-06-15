#!/usr/bin/env python3
# catalog-engine / lib / render.py
#
# Purpose:   Render the catalog records into (a) a hierarchical Markdown catalog
#            (TYPE -> CLUSTER -> COMPONENT -> record) and (b) a self-contained
#            interactive HTML page (inlined catalog.json + a tiny vanilla-JS
#            search/filter/sort layer + per-record detail). Offline file://,
#            no server, no CDN (§11.4.8 self-contained precedent).
# Usage:     render_markdown(records, meta) -> str ; render_html(records, meta)
# Inputs:    records list (§2 schema) + a meta dict.
# Outputs:   markdown string / html string.
# Side-effects: none.
# Dependencies: stdlib only (json, html).
# Cross-refs: P0_design.md §4 interactive-HTML design.
"""Markdown + self-contained interactive HTML renderers (decoupled)."""

import html as _html
import json


def _group(records):
    """type -> cluster -> component -> [records]."""
    tree = {}
    for r in records:
        tree.setdefault(r["type"], {}) \
            .setdefault(r["cluster"], {}) \
            .setdefault(r["component"], []).append(r)
    return tree


def _badge(val):
    return "✅" if val else "❌"


def render_markdown(records, meta):
    tree = _group(records)
    lines = [
        "# Test Catalog — %s" % meta.get("title", "tests"),
        "",
        "**Revision:** 1  ",
        "**Last modified:** %s  " % meta.get("generated_at", ""),
        "**Records:** %d  " % len(records),
        "**Bluff-proofed:** %d  " % sum(1 for r in records if r["bluff_proofed"]),
        "**Physical-evidence:** %d  " % sum(
            1 for r in records if r["physical_evidence"]),
        "",
        "Every field below is DERIVED from the source by the catalog engine "
        "(§11.4.6 no-guessing — gaps marked UNCONFIRMED, never invented).",
        "",
    ]
    for typ in sorted(tree):
        lines.append("## %s" % typ)
        lines.append("")
        for cluster in sorted(tree[typ]):
            lines.append("### %s" % cluster)
            lines.append("")
            for comp in sorted(tree[typ][cluster]):
                lines.append("#### %s" % comp)
                lines.append("")
                lines.append("| Test | Bluff | Phys | Feature | Ver | Updated | "
                             "ATM |")
                lines.append("|---|:--:|:--:|---|---|---|---|")
                for r in sorted(tree[typ][cluster][comp], key=lambda x: x["id"]):
                    lines.append(
                        "| `%s` | %s | %s | %s | %s | %s | %s |" % (
                            r["id"], _badge(r["bluff_proofed"]),
                            _badge(r["physical_evidence"]),
                            r.get("feature_class") or "—",
                            r.get("version") or "—",
                            r.get("updated_date") or "—",
                            r.get("atm_id") or "—",
                        ))
                lines.append("")
    return "\n".join(lines) + "\n"


# ---- self-contained interactive HTML -----------------------------------------

_HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Test Catalog — __TITLE__</title>
<style>
:root{font-family:system-ui,Segoe UI,Roboto,Helvetica,Arial,sans-serif}
body{margin:0;background:#fafafa;color:#1a1a1a}
header{background:#1f2933;color:#fff;padding:14px 20px}
header h1{margin:0;font-size:18px}
header .meta{font-size:12px;opacity:.85;margin-top:4px}
.controls{display:flex;flex-wrap:wrap;gap:8px;padding:12px 20px;
  background:#eef2f6;position:sticky;top:0;z-index:5;border-bottom:1px solid #d0d7de}
.controls input,.controls select{padding:6px 8px;border:1px solid #c3ccd6;
  border-radius:4px;font-size:13px}
.controls input[type=search]{min-width:240px}
.count{font-size:12px;color:#52606d;align-self:center}
table{border-collapse:collapse;width:100%;font-size:13px}
th,td{padding:6px 10px;border-bottom:1px solid #e3e8ee;text-align:left;
  vertical-align:top}
th{background:#f3f6f9;cursor:pointer;position:sticky;top:54px;z-index:4;
  user-select:none}
tr:hover{background:#f6f9fc}
.badge{display:inline-block;width:18px;text-align:center;border-radius:3px;
  font-weight:600;print-color-adjust:exact;-webkit-print-color-adjust:exact}
.b-ok{background:#A8E6A8}.b-no{background:#FFCCCC}
code{background:#eef2f6;padding:1px 4px;border-radius:3px;font-size:12px}
.detail{display:none;background:#fbfdff}
.detail td{padding:10px 16px}
.detail pre{white-space:pre-wrap;font-size:12px;background:#f3f6f9;
  padding:8px;border-radius:4px;margin:4px 0}
.gap{color:#9a3b3b}
.steps li{margin:2px 0}
a{color:#0b6bcb}
</style></head><body>
<header><h1>Test Catalog — __TITLE__</h1>
<div class="meta">Generated __GENERATED__ · __NREC__ records · __NBLUFF__ \
bluff-proofed · __NPHYS__ physical-evidence — every field DERIVED from source \
(§11.4.6, no-guessing)</div></header>
<div class="controls">
  <input type="search" id="q" placeholder="search id / name / description…">
  <select id="ftype"><option value="">type: all</option></select>
  <select id="fcluster"><option value="">cluster: all</option></select>
  <select id="ffeat"><option value="">feature: all</option></select>
  <select id="fbluff"><option value="">bluff: all</option>
    <option value="1">bluff-proofed</option><option value="0">NOT</option></select>
  <select id="fphys"><option value="">physical: all</option>
    <option value="1">has evidence</option><option value="0">NONE</option></select>
  <span class="count" id="count"></span>
</div>
<table id="tbl"><thead><tr>
  <th data-k="id">ID</th><th data-k="type">Type</th><th data-k="cluster">Cluster</th>
  <th data-k="bluff_proofed">Bluff</th><th data-k="physical_evidence">Phys</th>
  <th data-k="feature_class">Feature</th><th data-k="version">Ver</th>
  <th data-k="updated_date">Updated</th><th data-k="atm_id">ATM</th>
</tr></thead><tbody id="rows"></tbody></table>
<script id="catalog-data" type="application/json">__DATA__</script>
<script>
const DATA = JSON.parse(document.getElementById('catalog-data').textContent);
const rowsEl = document.getElementById('rows');
const q = document.getElementById('q');
const sels = {type:document.getElementById('ftype'),
  cluster:document.getElementById('fcluster'),
  feature_class:document.getElementById('ffeat'),
  bluff:document.getElementById('fbluff'), phys:document.getElementById('fphys')};
let sortKey='id', sortAsc=true;
function uniq(k){return [...new Set(DATA.map(r=>r[k]).filter(Boolean))].sort();}
['type','cluster','feature_class'].forEach(k=>{const sk=k==='feature_class'?'feature_class':k;
  uniq(k).forEach(v=>{const o=document.createElement('option');o.value=v;o.textContent=v;
  sels[sk].appendChild(o);});});
function badge(v){return '<span class="badge '+(v?'b-ok':'b-no')+'">'+(v?'✓':'✗')+'</span>';}
function esc(s){return (s==null?'':String(s)).replace(/[&<>]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));}
function match(r){
  const text=(r.id+' '+r.name+' '+(r.description||'')).toLowerCase();
  if(q.value && !text.includes(q.value.toLowerCase())) return false;
  if(sels.type.value && r.type!==sels.type.value) return false;
  if(sels.cluster.value && r.cluster!==sels.cluster.value) return false;
  if(sels.feature_class.value && r.feature_class!==sels.feature_class.value) return false;
  if(sels.bluff.value!=='' && String(r.bluff_proofed?1:0)!==sels.bluff.value) return false;
  if(sels.phys.value!=='' && String(r.physical_evidence?1:0)!==sels.phys.value) return false;
  return true;
}
function render(){
  let rows=DATA.filter(match);
  rows.sort((a,b)=>{let x=a[sortKey],y=b[sortKey];x=x==null?'':x;y=y==null?'':y;
    return (x<y?-1:x>y?1:0)*(sortAsc?1:-1);});
  rowsEl.innerHTML='';
  rows.forEach(r=>{
    const tr=document.createElement('tr');tr.style.cursor='pointer';
    tr.innerHTML='<td><code>'+esc(r.id)+'</code></td><td>'+esc(r.type)+
      '</td><td>'+esc(r.cluster)+'</td><td>'+badge(r.bluff_proofed)+'</td><td>'+
      badge(r.physical_evidence)+'</td><td>'+esc(r.feature_class||'—')+'</td><td>'+
      esc(r.version||'—')+'</td><td>'+esc(r.updated_date||'—')+'</td><td>'+
      esc(r.atm_id||'—')+'</td>';
    const det=document.createElement('tr');det.className='detail';
    const steps=(r.step_by_step||[]).map(s=>'<li>'+esc(s.what||s.achieved||'')+
      (s.how?' <em>('+esc(s.how)+')</em>':'')+(s.result?' → '+esc(s.result):'')+'</li>').join('');
    det.innerHTML='<td colspan="9"><b>'+esc(r.name)+'</b><br>'+esc(r.description||'(no header description)')+
      '<br><small>source: <code>'+esc(r.source_path)+'</code> · created '+esc(r.created_date)+
      ' · quality '+esc(r.description_quality)+'</small>'+
      (r.bluff_proofed_reasons&&r.bluff_proofed_reasons.length?'<br>bluff: '+esc(r.bluff_proofed_reasons.join(', ')):'')+
      (r.physical_evidence_which&&r.physical_evidence_which.length?'<br>evidence: '+esc(r.physical_evidence_which.join(', ')):'')+
      (steps?'<ul class="steps">'+steps+'</ul>':'')+
      (r.derivation_gaps&&r.derivation_gaps.length?'<div class="gap">gaps: '+esc(r.derivation_gaps.join(', '))+'</div>':'')+
      '</td>';
    tr.addEventListener('click',()=>{det.style.display=det.style.display==='table-row'?'none':'table-row';});
    rowsEl.appendChild(tr);rowsEl.appendChild(det);
  });
  document.getElementById('count').textContent=rows.length+' / '+DATA.length+' shown';
}
document.querySelectorAll('th[data-k]').forEach(th=>th.addEventListener('click',()=>{
  const k=th.dataset.k; if(sortKey===k)sortAsc=!sortAsc;else{sortKey=k;sortAsc=true;}render();}));
q.addEventListener('input',render);
Object.values(sels).forEach(s=>s.addEventListener('change',render));
render();
</script></body></html>
"""


def render_html(records, meta):
    data = json.dumps(records, ensure_ascii=False)
    nbluff = sum(1 for r in records if r["bluff_proofed"])
    nphys = sum(1 for r in records if r["physical_evidence"])
    out = _HTML_TEMPLATE
    out = out.replace("__TITLE__", _html.escape(meta.get("title", "tests")))
    out = out.replace("__GENERATED__", _html.escape(meta.get("generated_at", "")))
    out = out.replace("__NREC__", str(len(records)))
    out = out.replace("__NBLUFF__", str(nbluff))
    out = out.replace("__NPHYS__", str(nphys))
    out = out.replace("__DATA__", data)
    return out
