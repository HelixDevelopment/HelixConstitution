// sync.go — the functional subcommands: md-to-db, db-to-md, validate, diff.
//
// §11.4.93 bidirectional sync between the Markdown trackers and the SQLite
// single-source-of-truth, plus closed-set validation (§11.4.15/16/91).
package main

import (
	"flag"
	"fmt"
	"os"
	"sort"
)

// syncMDToDB parses Issues.md + Fixed.md and upserts the DB.
func syncMDToDB(args []string) int {
	fs := flag.NewFlagSet("sync md-to-db", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	issuesPath := fs.String("issues", "", "path to Issues.md")
	fixedPath := fs.String("fixed", "", "path to Fixed.md")
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}
	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "sync md-to-db: --db is required")
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "sync md-to-db: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	total := 0
	if *issuesPath != "" {
		content, err := os.ReadFile(*issuesPath)
		if err != nil {
			fmt.Fprintf(os.Stderr, "sync md-to-db: read issues: %v\n", err)
			return exitUsage
		}
		items, segs := parseIssues(string(content))
		if err := replaceDocument(db, "Issues", items, segs); err != nil {
			fmt.Fprintf(os.Stderr, "sync md-to-db: persist issues: %v\n", err)
			return exitUsage
		}
		fmt.Printf("Issues.md: %d items, %d segments\n", len(items), len(segs))
		total += len(items)
	}
	if *fixedPath != "" {
		content, err := os.ReadFile(*fixedPath)
		if err != nil {
			fmt.Fprintf(os.Stderr, "sync md-to-db: read fixed: %v\n", err)
			return exitUsage
		}
		items, segs := parseFixed(string(content))
		if err := replaceDocument(db, "Fixed", items, segs); err != nil {
			fmt.Fprintf(os.Stderr, "sync md-to-db: persist fixed: %v\n", err)
			return exitUsage
		}
		fmt.Printf("Fixed.md: %d items, %d segments\n", len(items), len(segs))
		total += len(items)
	}
	if *issuesPath == "" && *fixedPath == "" {
		fmt.Fprintln(os.Stderr, "sync md-to-db: at least one of --issues / --fixed is required")
		return exitUsage
	}
	fmt.Printf("synced %d total items into %s\n", total, *dbPath)
	return exitOK
}

// syncDBToMD regenerates Issues.md + Fixed.md from the DB segments.
func syncDBToMD(args []string) int {
	fs := flag.NewFlagSet("sync db-to-md", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	outIssues := fs.String("out-issues", "", "output path for regenerated Issues.md")
	outFixed := fs.String("out-fixed", "", "output path for regenerated Fixed.md")
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}
	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "sync db-to-md: --db is required")
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "sync db-to-md: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	if *outIssues != "" {
		text, err := renderDocument(db, "Issues")
		if err != nil {
			fmt.Fprintf(os.Stderr, "sync db-to-md: render issues: %v\n", err)
			return exitUsage
		}
		if err := os.WriteFile(*outIssues, []byte(text), 0o644); err != nil {
			fmt.Fprintf(os.Stderr, "sync db-to-md: write issues: %v\n", err)
			return exitUsage
		}
		fmt.Printf("wrote %s (%d bytes)\n", *outIssues, len(text))
	}
	if *outFixed != "" {
		text, err := renderDocument(db, "Fixed")
		if err != nil {
			fmt.Fprintf(os.Stderr, "sync db-to-md: render fixed: %v\n", err)
			return exitUsage
		}
		if err := os.WriteFile(*outFixed, []byte(text), 0o644); err != nil {
			fmt.Fprintf(os.Stderr, "sync db-to-md: write fixed: %v\n", err)
			return exitUsage
		}
		fmt.Printf("wrote %s (%d bytes)\n", *outFixed, len(text))
	}
	if *outIssues == "" && *outFixed == "" {
		fmt.Fprintln(os.Stderr, "sync db-to-md: at least one of --out-issues / --out-fixed is required")
		return exitUsage
	}
	return exitOK
}

// validateCmd asserts the §11.4 closed-set + clarity invariants over the DB.
func validateCmd(args []string) int {
	fs := flag.NewFlagSet("validate", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}
	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "validate: --db is required")
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "validate: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	items, err := loadItems(db)
	if err != nil {
		fmt.Fprintf(os.Stderr, "validate: %v\n", err)
		return exitUsage
	}

	statusSet := map[string]bool{}
	for _, s := range closedStatuses {
		statusSet[s] = true
	}
	typeSet := map[string]bool{"Bug": true, "Feature": true, "Task": true}

	var violations []string
	seen := map[string]bool{}
	for _, it := range items {
		// §11.4.54 — duplicate (atm_id, location). The composite PRIMARY KEY
		// makes this impossible at the storage layer (the same id MAY appear
		// once per tracker), but we assert it explicitly for clarity.
		key := it.AtmID + "\x00" + it.CurrentLocation
		if seen[key] {
			violations = append(violations, fmt.Sprintf("duplicate atm_id in %s: %s", it.CurrentLocation, it.AtmID))
		}
		seen[key] = true

		// §11.4.15/21/90 — status closed-set.
		if !statusSet[it.Status] {
			violations = append(violations, fmt.Sprintf("%s: status %q not in closed-set", it.AtmID, it.Status))
		}
		// §11.4.16 — type closed-set.
		if !typeSet[it.Type] {
			violations = append(violations, fmt.Sprintf("%s: type %q not in {Bug,Feature,Task}", it.AtmID, it.Type))
		}
		// §11.4.91 — description ≥6 words OR ≥40 chars.
		if wordCount(it.Description) < 6 && len(it.Description) < 40 {
			violations = append(violations, fmt.Sprintf("%s: description too short (%d words / %d chars): %q",
				it.AtmID, wordCount(it.Description), len(it.Description), it.Description))
		}
	}

	if len(violations) > 0 {
		sort.Strings(violations)
		fmt.Fprintf(os.Stderr, "validate: %d violation(s):\n", len(violations))
		for _, v := range violations {
			fmt.Fprintf(os.Stderr, "  - %s\n", v)
		}
		return exitUsage
	}
	fmt.Printf("validate: OK — %d items, all invariants satisfied\n", len(items))
	return exitOK
}

// diffCmd reports items whose parsed-from-Markdown state differs from the DB.
func diffCmd(args []string) int {
	fs := flag.NewFlagSet("diff", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	issuesPath := fs.String("issues", "", "path to Issues.md")
	fixedPath := fs.String("fixed", "", "path to Fixed.md")
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}
	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "diff: --db is required")
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "diff: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	dbItems, err := loadItems(db)
	if err != nil {
		fmt.Fprintf(os.Stderr, "diff: %v\n", err)
		return exitUsage
	}
	dbByID := map[string]item{}
	for _, it := range dbItems {
		dbByID[it.AtmID] = it
	}

	var parsed []item
	if *issuesPath != "" {
		c, err := os.ReadFile(*issuesPath)
		if err != nil {
			fmt.Fprintf(os.Stderr, "diff: read issues: %v\n", err)
			return exitUsage
		}
		its, _ := parseIssues(string(c))
		parsed = append(parsed, its...)
	}
	if *fixedPath != "" {
		c, err := os.ReadFile(*fixedPath)
		if err != nil {
			fmt.Fprintf(os.Stderr, "diff: read fixed: %v\n", err)
			return exitUsage
		}
		its, _ := parseFixed(string(c))
		parsed = append(parsed, its...)
	}

	differences := 0
	parsedSeen := map[string]bool{}
	for _, p := range parsed {
		parsedSeen[p.AtmID] = true
		d, ok := dbByID[p.AtmID]
		if !ok {
			fmt.Printf("+ %s present in Markdown, absent in DB\n", p.AtmID)
			differences++
			continue
		}
		if p.Status != d.Status {
			fmt.Printf("~ %s status: md=%q db=%q\n", p.AtmID, p.Status, d.Status)
			differences++
		}
		if p.Type != d.Type {
			fmt.Printf("~ %s type: md=%q db=%q\n", p.AtmID, p.Type, d.Type)
			differences++
		}
		if p.BodyMD != d.BodyMD {
			fmt.Printf("~ %s body differs (md=%d bytes db=%d bytes)\n", p.AtmID, len(p.BodyMD), len(d.BodyMD))
			differences++
		}
	}
	for _, d := range dbItems {
		if !parsedSeen[d.AtmID] {
			fmt.Printf("- %s present in DB, absent in Markdown\n", d.AtmID)
			differences++
		}
	}

	if differences == 0 {
		fmt.Println("diff: DB and Markdown are in sync")
		return exitOK
	}
	fmt.Printf("diff: %d difference(s)\n", differences)
	return exitUsage
}
