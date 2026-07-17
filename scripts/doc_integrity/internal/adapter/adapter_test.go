package adapter

import (
	"database/sql"
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/HelixDevelopment/HelixConstitution/scripts/doc_integrity/internal/config"
	_ "github.com/mattn/go-sqlite3"
	"github.com/xuri/excelize/v2"
)

func writeTemp(t *testing.T, name, content string) (dir, path string) {
	t.Helper()
	dir = t.TempDir()
	path = filepath.Join(dir, name)
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return dir, name
}

func TestMarkdownTableAdapter(t *testing.T) {
	md := "# t\n\n| № | Ticket | Task | Deadline |\n|---|--------|------|----------|\n| 1.1 | ATM-1 | Alpha | 2026-08-10 |\n| 1.2 | ATM-2 | Beta | 2026-08-20 |\n\nafter\n"
	dir, name := writeTemp(t, "plan.md", md)
	src := config.Source{ID: "plan", Kind: "markdown-table", Path: name, Columns: map[string]string{
		"item_id": "№", "ticket": "Ticket", "name_en": "Task", "deadline": "Deadline",
	}}
	lr, err := Load(src, dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(lr.Records) != 2 {
		t.Fatalf("want 2 records, got %d", len(lr.Records))
	}
	if lr.Records[0].Ticket != "ATM-1" || lr.Records[0].ItemID != "1.1" {
		t.Fatalf("bad first record: %+v", lr.Records[0])
	}
	if lr.Records[1].Deadline == nil {
		t.Fatal("deadline should parse")
	}
	if !lr.PresentColumns["deadline"] {
		t.Fatal("deadline column should be present")
	}
}

func TestMarkdownTableMissingColumn(t *testing.T) {
	md := "| № | Ticket | Task | Due |\n|---|---|---|---|\n| 1.1 | ATM-1 | Alpha | 2026-08-10 |\n"
	dir, name := writeTemp(t, "plan.md", md)
	src := config.Source{ID: "plan", Kind: "markdown-table", Path: name, Columns: map[string]string{
		"deadline": "Deadline",
	}}
	lr, err := Load(src, dir)
	if err != nil {
		t.Fatal(err)
	}
	if lr.PresentColumns["deadline"] {
		t.Fatal("renamed 'Due' column must NOT resolve 'deadline' as present")
	}
}

func TestMarkdownHeadingsAdapter(t *testing.T) {
	md := "# Issues\n\n## §4.1. [ATM-500] Some feature\n**Type:** Feature\n**Status:** Fixed (→ Fixed.md)\n**Start:** 2026-08-01\n**Deadline:** 2026-08-10\n**Depends:** ATM-100, ATM-101\n\n## §4.2. [ATM-501] Another\n**Type:** Bug\n**Status:** Queued\n"
	dir, name := writeTemp(t, "issues.md", md)
	src := config.Source{ID: "issues", Kind: "markdown-headings", Path: name}
	lr, err := Load(src, dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(lr.Records) != 2 {
		t.Fatalf("want 2 records, got %d", len(lr.Records))
	}
	r := lr.Records[0]
	if r.Ticket != "ATM-500" || r.Type != "Feature" || r.Status != "Fixed (→ Fixed.md)" {
		t.Fatalf("bad heading parse: %+v", r)
	}
	if len(r.Deps) != 2 || r.Deps[0] != "ATM-100" {
		t.Fatalf("deps parse wrong: %v", r.Deps)
	}
	if r.ItemID != "4.1" {
		t.Fatalf("section id parse wrong: %q", r.ItemID)
	}
	if r.Subject == "" {
		t.Fatal("subject should be extracted from heading")
	}
}

func TestXLSXAdapter(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "plan.xlsx")
	f := excelize.NewFile()
	sheet := f.GetSheetName(0)
	rows := [][]string{
		{"№", "Ticket", "Task", "Deadline"},
		{"1.1", "ATM-1", "Alpha", "2026-08-10"},
		{"1.2", "ATM-2", "Beta", "2026-08-20"},
	}
	for i, row := range rows {
		for j, v := range row {
			cell, _ := excelize.CoordinatesToCellName(j+1, i+1)
			if err := f.SetCellStr(sheet, cell, v); err != nil {
				t.Fatal(err)
			}
		}
	}
	if err := f.SaveAs(path); err != nil {
		t.Fatal(err)
	}
	src := config.Source{ID: "plan", Kind: "xlsx", Path: "plan.xlsx", HeaderRow: 1, Columns: map[string]string{
		"item_id": "№", "ticket": "Ticket", "name_en": "Task", "deadline": "Deadline",
	}}
	lr, err := Load(src, dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(lr.Records) != 2 {
		t.Fatalf("want 2 records, got %d", len(lr.Records))
	}
	if lr.Records[0].Ticket != "ATM-1" || lr.Records[0].Deadline == nil {
		t.Fatalf("bad xlsx record: %+v", lr.Records[0])
	}
	if !lr.PresentColumns["ticket"] {
		t.Fatal("ticket column must be present in xlsx")
	}
}

func TestXLSXMissingFileSkips(t *testing.T) {
	src := config.Source{ID: "plan", Kind: "xlsx", Path: "nope.xlsx", Columns: map[string]string{"item_id": "№"}}
	_, err := Load(src, t.TempDir())
	if !errors.Is(err, ErrSourceUnavailable) {
		t.Fatalf("missing xlsx must yield ErrSourceUnavailable (honest SKIP §11.4.3), got %v", err)
	}
}

func TestSQLiteAdapter(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "wi.db")
	db, err := sql.Open("sqlite3", path)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`CREATE TABLE items (atm_id TEXT, type TEXT, status TEXT, title TEXT, cur TEXT);
		INSERT INTO items VALUES ('ATM-1','Feature','Implemented (→ Fixed.md)','Alpha','Fixed');
		INSERT INTO items VALUES ('ATM-2','Bug','Queued','Beta','Issues');`); err != nil {
		t.Fatal(err)
	}
	db.Close()

	src := config.Source{ID: "db", Kind: "sqlite", Path: "wi.db", Table: "items", Columns: map[string]string{
		"ticket": "atm_id", "type": "type", "status": "status", "title": "title", "location": "cur",
	}}
	lr, err := Load(src, dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(lr.Records) != 2 {
		t.Fatalf("want 2 rows, got %d", len(lr.Records))
	}
	var found bool
	for _, r := range lr.Records {
		if r.Ticket == "ATM-1" {
			found = true
			if r.Type != "Feature" || r.Location != "Fixed" {
				t.Fatalf("bad sqlite mapping: %+v", r)
			}
		}
	}
	if !found {
		t.Fatal("ATM-1 row not read from sqlite")
	}
}

func TestSQLiteMissingFileSkips(t *testing.T) {
	src := config.Source{ID: "db", Kind: "sqlite", Path: "nope.db", Table: "items", Columns: map[string]string{"ticket": "atm_id"}}
	_, err := Load(src, t.TempDir())
	if !errors.Is(err, ErrSourceUnavailable) {
		t.Fatalf("missing sqlite must yield ErrSourceUnavailable, got %v", err)
	}
}
