package adapter

import (
	"fmt"

	"github.com/HelixDevelopment/HelixConstitution/scripts/doc_integrity/internal/config"
	"github.com/HelixDevelopment/HelixConstitution/scripts/doc_integrity/internal/model"
	"github.com/xuri/excelize/v2"
)

// loadXLSX reads an .xlsx sheet via the mature pure-Go excelize/v2 (DESIGN §1.3
// — the lone Python advantage of openpyxl is fully covered here, so the whole
// tracker toolchain stays single-language Go).
func loadXLSX(src config.Source, path string) (LoadResult, error) {
	f, err := excelize.OpenFile(path)
	if err != nil {
		return LoadResult{}, fmt.Errorf("%w: open xlsx %q: %v", ErrSourceUnavailable, path, err)
	}
	defer f.Close()

	sheet := src.SheetName
	if sheet == "" {
		list := f.GetSheetList()
		idx := src.Sheet
		if idx <= 0 {
			idx = 1
		}
		if idx > len(list) {
			return LoadResult{}, fmt.Errorf("%w: xlsx %q has %d sheets, want #%d",
				ErrSourceUnavailable, path, len(list), idx)
		}
		sheet = list[idx-1]
	}

	rows, err := f.GetRows(sheet)
	if err != nil {
		return LoadResult{}, fmt.Errorf("%w: read sheet %q: %v", ErrSourceUnavailable, sheet, err)
	}
	hr := src.HeaderRow
	if hr < 1 || hr > len(rows) {
		return LoadResult{}, fmt.Errorf("%w: header row %d out of range (rows=%d)",
			ErrSourceUnavailable, hr, len(rows))
	}

	header := rows[hr-1]
	// header label (normalised) → column index
	headerIndex := map[string]int{}
	for i, h := range header {
		headerIndex[normalizeHeader(h)] = i
	}
	// logical name → column index (via configured header mapping)
	logicalIdx := map[string]int{}
	for logical, h := range src.Columns {
		if idx, ok := headerIndex[normalizeHeader(h)]; ok {
			logicalIdx[logical] = idx
		}
	}

	var records []model.Record
	for ri := hr; ri < len(rows); ri++ {
		row := rows[ri]
		if isEmptyRow(row) {
			continue
		}
		vals := map[string]string{}
		for logical, idx := range logicalIdx {
			if idx < len(row) {
				vals[logical] = row[idx]
			}
		}
		// A1-style locator: column letter of the item_id (or first mapped) col.
		colLetter := "A"
		if idx, ok := logicalIdx["item_id"]; ok {
			if cl, e := excelize.ColumnNumberToName(idx + 1); e == nil {
				colLetter = cl
			}
		}
		locator := fmt.Sprintf("%s!%s%d", sheet, colLetter, ri+1)
		records = append(records, buildRecord(src, vals, locator))
	}

	return LoadResult{
		Records:        records,
		PresentColumns: presentFromHeaders(src.Columns, headerIndex),
		RawHeaders:     header,
	}, nil
}

func isEmptyRow(row []string) bool {
	for _, c := range row {
		if c != "" {
			return false
		}
	}
	return true
}
