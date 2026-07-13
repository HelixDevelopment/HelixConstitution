package adapter

import (
	"database/sql"
	"fmt"
	"sort"
	"strings"

	"github.com/HelixDevelopment/HelixConstitution/scripts/doc_integrity/internal/config"
	"github.com/HelixDevelopment/HelixConstitution/scripts/doc_integrity/internal/model"
	_ "github.com/mattn/go-sqlite3"
)

// loadSQLite reads the workable-items DB READ-ONLY (DESIGN §1.2 — the tool never
// mutates the DB; that stays with the `workable-items` SoT tool). Columns are
// the same logical→physical mapping used by every adapter, so the DB source is
// treated identically to a spreadsheet row.
func loadSQLite(src config.Source, path string) (LoadResult, error) {
	table := src.Table
	if table == "" {
		if src.Tables != nil {
			table = src.Tables["items"]
		}
	}
	if table == "" {
		table = "items"
	}

	// Open READ-ONLY so the tool can never mutate the workable-items DB
	// (DESIGN §1.2). _query_only is a second belt-and-braces guard.
	dsn := "file:" + path + "?mode=ro&_query_only=true"
	db, err := sql.Open("sqlite3", dsn)
	if err != nil {
		return LoadResult{}, fmt.Errorf("%w: open sqlite %q: %v", ErrSourceUnavailable, path, err)
	}
	defer db.Close()
	if err := db.Ping(); err != nil {
		return LoadResult{}, fmt.Errorf("%w: ping sqlite %q: %v", ErrSourceUnavailable, path, err)
	}

	// Deterministic column order for the SELECT + PresentColumns.
	logicals := make([]string, 0, len(src.Columns))
	for k := range src.Columns {
		logicals = append(logicals, k)
	}
	sort.Strings(logicals)

	cols := make([]string, len(logicals))
	for i, l := range logicals {
		cols[i] = src.Columns[l]
	}
	if len(cols) == 0 {
		return LoadResult{}, fmt.Errorf("%w: sqlite source %q has no columns mapping",
			ErrSourceUnavailable, src.ID)
	}

	query := fmt.Sprintf("SELECT %s FROM %s", quotedList(cols), quoteIdent(table))
	rows, err := db.Query(query)
	if err != nil {
		return LoadResult{}, fmt.Errorf("%w: query %q: %v", ErrSourceUnavailable, table, err)
	}
	defer rows.Close()

	present := map[string]bool{}
	for _, l := range logicals {
		present[l] = true // the query succeeded, so every mapped column exists
	}

	var records []model.Record
	rowNo := 0
	for rows.Next() {
		rowNo++
		holders := make([]sql.NullString, len(cols))
		ptrs := make([]any, len(cols))
		for i := range holders {
			ptrs[i] = &holders[i]
		}
		if err := rows.Scan(ptrs...); err != nil {
			return LoadResult{}, fmt.Errorf("%w: scan %q row %d: %v", ErrSourceUnavailable, table, rowNo, err)
		}
		vals := map[string]string{}
		for i, l := range logicals {
			if holders[i].Valid {
				vals[l] = strings.TrimSpace(holders[i].String)
			}
		}
		locator := fmt.Sprintf("%s.%s", table, vals["item_id"])
		if id := vals["item_id"]; id == "" {
			locator = fmt.Sprintf("%s#row%d", table, rowNo)
		}
		records = append(records, buildRecord(src, vals, locator))
	}
	if err := rows.Err(); err != nil {
		return LoadResult{}, fmt.Errorf("%w: iterate %q: %v", ErrSourceUnavailable, table, err)
	}
	return LoadResult{Records: records, PresentColumns: present}, nil
}

func quoteIdent(s string) string {
	return `"` + strings.ReplaceAll(s, `"`, `""`) + `"`
}

func quotedList(cols []string) string {
	q := make([]string, len(cols))
	for i, c := range cols {
		q[i] = quoteIdent(c)
	}
	return strings.Join(q, ", ")
}
