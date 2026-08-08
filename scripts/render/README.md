# Governance render pipeline (§11.4.65 export-sync)

Regenerates the governance Markdown → `{.html,.docx,.pdf}` "twins" so the rendered
siblings never drift from the canonical `.md`. Run after editing any of
`Constitution.md`, `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `QWEN.md`.

## Usage

```bash
# pandoc 3.10 (3.10.1 is output-equivalent for this corpus); weasyprint for PDF.
# pin weasyprint==69.0 to match the historical PDF Producer exactly.
SOURCE_DATE_EPOCH=1785674948 PANDOC=pandoc bash scripts/render/render-governance-twins.sh
```

- `assets/governance-template.html5` — the pandoc HTML template. Its `<head>` (incl. the
  embedded OpenDesign stylesheet) reproduces the operator's historical renders
  **byte-for-byte** (verified: HEAD diff = 0 for all five docs). Title/body parameterized.
- `assets/od-styles.html` — the OpenDesign `<style>` block, kept as a standalone reference
  (already embedded in the template).

## Recipe (reverse-engineered + round-trip verified 2026-08-07)

`pandoc <doc>.md -f gfm -t html5 -s -M lang=en -M title=<doc> -M pagetitle=<doc> -V pandoc-version=3.10 --template=assets/governance-template.html5 --wrap=auto`

- **`-f gfm`**: matches heading-IDs, suppresses table `<colgroup>` widths, smart-off — all
  verified against the historical renders.
- **`document-css` off + OpenDesign styles**: baked into the template `<head>`.
- **docx**: `pandoc -f gfm -t docx` (stock reference doc; deterministic via `SOURCE_DATE_EPOCH`).
- **pdf**: `weasyprint <doc>.html <doc>.pdf` (Creator inherits `pandoc 3.10` from the HTML
  generator meta; pin `weasyprint==69.0` for an exact Producer match).

## Known deviation from pre-2026-08-07 historical renders

The historical HTML passed the body through a **non-standard post-step that escaped literal
`"` → `&quot;`** (no pandoc reader/writer/flag produces this — proven in
`../../_tests/evidence/render58/ANALYSIS.md`). This pipeline emits **standard pandoc output**
(literal `"`), which **renders identically** in every browser/PDF. A handful of long TOC
`<a href>` lines also wrap at a different column — again visually identical. The `<head>`,
OpenDesign styling, heading anchors, section content, and structure are exact.
