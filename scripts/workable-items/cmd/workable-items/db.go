// db.go — SQLite access layer for the workable-items single-source-of-truth.
//
// §11.4.93 / §11.4.95: the DB at docs/workable_items.db is the authoritative
// registry. This file owns schema application + item/segment persistence +
// read-back. CGO go-sqlite3 driver.
package main

import (
	"database/sql"
	_ "embed"
	"fmt"
	"os"
	"path/filepath"

	_ "github.com/mattn/go-sqlite3"
)

// schemaSQL is the authoritative DDL, embedded so the binary is self-contained
// (no runtime dependency on the schema.sql file location).
//
//go:embed schema_embed.sql
var schemaSQL string

// openDB opens (creating if absent) the SQLite DB at path and applies the
// schema. The schema is idempotent (CREATE TABLE IF NOT EXISTS), so re-opening
// an existing DB is safe.
func openDB(path string) (*sql.DB, error) {
	if dir := filepath.Dir(path); dir != "" && dir != "." {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return nil, fmt.Errorf("create db dir %q: %w", dir, err)
		}
	}
	db, err := sql.Open("sqlite3", path+"?_foreign_keys=on")
	if err != nil {
		return nil, fmt.Errorf("open sqlite %q: %w", path, err)
	}
	if _, err := db.Exec(schemaSQL); err != nil {
		db.Close()
		return nil, fmt.Errorf("apply schema: %w", err)
	}
	return db, nil
}

// item is the in-memory representation of a workable item row.
type item struct {
	AtmID           string
	Type            string
	Status          string
	Severity        string
	Title           string
	Description     string
	ForensicAnchor  string
	ClosureCriteria string
	ComposesWith    string
	CurrentLocation string // "Issues" | "Fixed"
	BodyMD          string
}

// segment is one ordered piece of a source document: either an item reference
// or verbatim raw prose.
type segment struct {
	Document string // "Issues" | "Fixed"
	Seq      int
	Kind     string // "item" | "raw"
	AtmID    string // when Kind=="item"
	Raw      string // when Kind=="raw"
}

// replaceDocument wipes prior state for a document and persists the freshly
// parsed items + segments inside a single transaction (atomic md→db sync).
// Items are keyed by atm_id (PRIMARY KEY); an atm_id may appear in only one
// document, which the parser guarantees by partitioning Issues vs Fixed.
func replaceDocument(db *sql.DB, document string, items []item, segs []segment) error {
	tx, err := db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	// Clear segments for this document; clear items whose current_location is
	// this document (so a full two-document sync rebuilds everything).
	if _, err := tx.Exec(`DELETE FROM doc_segments WHERE document = ?`, document); err != nil {
		return fmt.Errorf("clear segments: %w", err)
	}
	if _, err := tx.Exec(`DELETE FROM items WHERE current_location = ?`, document); err != nil {
		return fmt.Errorf("clear items: %w", err)
	}

	insItem, err := tx.Prepare(`INSERT INTO items
		(atm_id, type, status, severity, title, description,
		 forensic_anchor, closure_criteria, composes_with,
		 current_location, body_md)
		VALUES (?,?,?,?,?,?,?,?,?,?,?)`)
	if err != nil {
		return err
	}
	defer insItem.Close()

	for _, it := range items {
		if _, err := insItem.Exec(it.AtmID, it.Type, it.Status,
			nullable(it.Severity), it.Title, it.Description,
			nullable(it.ForensicAnchor), nullable(it.ClosureCriteria),
			nullable(it.ComposesWith), it.CurrentLocation, it.BodyMD); err != nil {
			return fmt.Errorf("insert item %s: %w", it.AtmID, err)
		}
	}

	insSeg, err := tx.Prepare(`INSERT INTO doc_segments
		(document, seq, kind, atm_id, raw) VALUES (?,?,?,?,?)`)
	if err != nil {
		return err
	}
	defer insSeg.Close()

	for _, s := range segs {
		if _, err := insSeg.Exec(s.Document, s.Seq, s.Kind,
			nullable(s.AtmID), nullableRaw(s.Raw, s.Kind)); err != nil {
			return fmt.Errorf("insert segment %s#%d: %w", s.Document, s.Seq, err)
		}
	}

	if _, err := tx.Exec(`UPDATE meta SET value=?, last_modified=datetime('now') WHERE key='last_sync_direction'`, "md-to-db"); err != nil {
		return err
	}
	if _, err := tx.Exec(`UPDATE meta SET value=datetime('now') WHERE key='last_sync_timestamp'`); err != nil {
		return err
	}
	return tx.Commit()
}

func nullable(s string) any {
	if s == "" {
		return nil
	}
	return s
}

// nullableRaw stores raw only for raw segments (empty raw on an item segment
// is legitimate and must remain NULL).
func nullableRaw(s, kind string) any {
	if kind != "raw" {
		return nil
	}
	return s
}

// loadItems returns every item row, ordered by atm_id.
func loadItems(db *sql.DB) ([]item, error) {
	rows, err := db.Query(`SELECT atm_id, type, status,
		COALESCE(severity,''), title, description,
		COALESCE(forensic_anchor,''), COALESCE(closure_criteria,''),
		COALESCE(composes_with,''), current_location, COALESCE(body_md,'')
		FROM items ORDER BY atm_id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []item
	for rows.Next() {
		var it item
		if err := rows.Scan(&it.AtmID, &it.Type, &it.Status, &it.Severity,
			&it.Title, &it.Description, &it.ForensicAnchor,
			&it.ClosureCriteria, &it.ComposesWith, &it.CurrentLocation,
			&it.BodyMD); err != nil {
			return nil, err
		}
		out = append(out, it)
	}
	return out, rows.Err()
}

// renderDocument reassembles a document's source text from doc_segments +
// items.body_md, walked in seq order — the byte-identical-round-trip path.
func renderDocument(db *sql.DB, document string) (string, error) {
	// Body lookup scoped to THIS document — the same atm_id may exist in both
	// trackers (Issues tombstone + Fixed closure), so keying on atm_id alone
	// would cross-wire the bodies.
	bodyByID := map[string]string{}
	brows, err := db.Query(`SELECT atm_id, COALESCE(body_md,'') FROM items WHERE current_location = ?`, document)
	if err != nil {
		return "", err
	}
	for brows.Next() {
		var id, body string
		if err := brows.Scan(&id, &body); err != nil {
			brows.Close()
			return "", err
		}
		bodyByID[id] = body
	}
	brows.Close()
	if err := brows.Err(); err != nil {
		return "", err
	}

	rows, err := db.Query(`SELECT seq, kind, COALESCE(atm_id,''), COALESCE(raw,'')
		FROM doc_segments WHERE document = ? ORDER BY seq`, document)
	if err != nil {
		return "", err
	}
	defer rows.Close()

	var sb []byte
	for rows.Next() {
		var seq int
		var kind, atmID, raw string
		if err := rows.Scan(&seq, &kind, &atmID, &raw); err != nil {
			return "", err
		}
		switch kind {
		case "raw":
			sb = append(sb, raw...)
		case "item":
			body, ok := bodyByID[atmID]
			if !ok {
				return "", fmt.Errorf("segment references unknown item %q", atmID)
			}
			sb = append(sb, body...)
		}
	}
	return string(sb), rows.Err()
}
