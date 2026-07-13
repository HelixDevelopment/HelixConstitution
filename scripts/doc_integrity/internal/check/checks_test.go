package check

import (
	"strings"
	"testing"

	"github.com/HelixDevelopment/HelixConstitution/scripts/doc_integrity/internal/config"
	"github.com/HelixDevelopment/HelixConstitution/scripts/doc_integrity/internal/model"
	"github.com/HelixDevelopment/HelixConstitution/scripts/doc_integrity/internal/normalize"
)

func rec(source, id, ticket, subject, scope, start, deadline string, deps ...string) model.Record {
	r := model.Record{
		SourceID:    source,
		ItemID:      id,
		Ticket:      ticket,
		Subject:     subject,
		SubjectNorm: normalize.Subject(subject),
		ScopeNorm:   normalize.Scope(scope),
		Start:       normalize.Date(start),
		Deadline:    normalize.Date(deadline),
		Deps:        deps,
		Locator:     source + ":" + id,
	}
	return r
}

func ds1(src config.Source, present map[string]bool, recs ...model.Record) *Dataset {
	cfg := &config.Config{
		Dedup:        config.DedupCfg{KeyFields: []string{"subject_norm", "scope_norm"}},
		CrossdocJoin: config.CrossdocJoin{Key: "ticket", Compare: []string{"timeline", "status", "type"}},
		Thresholds:   config.Thresholds{SubjectSimilarity: 0.9},
	}
	return NewDataset(cfg, []SourceData{{Src: src, Records: recs, Present: present}})
}

func hasRule(fs []Finding, rule string) *Finding {
	for i := range fs {
		if fs[i].RuleID == rule {
			return &fs[i]
		}
	}
	return nil
}

func TestDedup01TicketDuplicate(t *testing.T) {
	src := config.Source{ID: "plan", Kind: "markdown-table"}
	ds := ds1(src, nil,
		rec("plan", "1", "ATM-1", "Alpha", "a", "", ""),
		rec("plan", "2", "ATM-1", "Beta", "b", "", ""),
	)
	f := Dedup(ds)
	if hasRule(f, "DEDUP-01") == nil {
		t.Fatalf("expected DEDUP-01 for duplicate ticket, got %+v", f)
	}
}

func TestDedup02SubjectScopeDuplicate(t *testing.T) {
	src := config.Source{ID: "plan"}
	ds := ds1(src, nil,
		rec("plan", "1", "ATM-1", "NanoKVM screen display", "screen-display", "2026-11-06", "2026-11-09"),
		rec("plan", "2", "ATM-2", "NanoKVM screen display", "screen-display", "2026-11-06", "2026-12-01"),
	)
	f := Dedup(ds)
	got := hasRule(f, "DEDUP-02")
	if got == nil {
		t.Fatalf("expected DEDUP-02 for same subject+scope, got %+v", f)
	}
	if !strings.Contains(got.Message, "DIVERGENT") {
		t.Errorf("divergent-timeline duplicate should be flagged as such: %s", got.Message)
	}
}

func TestDedup02DistinctScopeNoFalsePositive(t *testing.T) {
	src := config.Source{ID: "plan"}
	ds := ds1(src, nil,
		rec("plan", "2.5.1", "ATM-1", "NanoKVM integration", "integration", "2026-10-01", "2026-10-05"),
		rec("plan", "2.5.2", "ATM-2", "NanoKVM protocol config", "protocol-config", "2026-10-06", "2026-10-09"),
		rec("plan", "5.2.1", "ATM-3", "NanoKVM screen display", "screen-display", "2026-11-04", "2026-11-06"),
	)
	if f := Dedup(ds); len(f) != 0 {
		t.Fatalf("distinct-scope NanoKVM tasks must NOT be flagged (§3.2), got %+v", f)
	}
}

func TestDedup02AllowlistExempts(t *testing.T) {
	src := config.Source{ID: "plan"}
	ds := ds1(src, nil,
		rec("plan", "1", "ATM-1", "Recurring sweep", "sweep", "2026-11-06", "2026-11-09"),
		rec("plan", "2", "ATM-2", "Recurring sweep", "sweep", "2026-11-06", "2026-11-09"),
	)
	ds.Cfg.Dedup.Allowlist = []string{"recurring sweep|sweep"}
	if f := Dedup(ds); hasRule(f, "DEDUP-02") != nil {
		t.Fatalf("allow-listed key must be exempt, got %+v", f)
	}
}

func TestTime01StartAfterDeadline(t *testing.T) {
	src := config.Source{ID: "plan"}
	ds := ds1(src, nil, rec("plan", "1", "ATM-1", "X", "x", "2026-08-20", "2026-08-10"))
	if hasRule(Timeline(ds), "TIME-01") == nil {
		t.Fatal("expected TIME-01 for start-after-deadline")
	}
}

func TestTime02DeadlineBeforeDependency(t *testing.T) {
	src := config.Source{ID: "plan", Columns: map[string]string{"deadline": "Deadline"}}
	ds := ds1(src, nil,
		rec("plan", "1.1", "ATM-1", "Base", "base", "2026-08-01", "2026-08-20"),
		rec("plan", "1.2", "ATM-2", "Dep", "dep", "2026-08-10", "2026-08-25", "1.1"),
	)
	if hasRule(Timeline(ds), "TIME-02") == nil {
		t.Fatal("expected TIME-02 for deadline-before-dependency")
	}
}

func TestTime03Cycle(t *testing.T) {
	src := config.Source{ID: "plan"}
	ds := ds1(src, nil,
		rec("plan", "1.1", "ATM-1", "A", "a", "2026-08-01", "2026-08-05", "1.2"),
		rec("plan", "1.2", "ATM-2", "B", "b", "2026-08-06", "2026-08-10", "1.1"),
	)
	if hasRule(Timeline(ds), "TIME-03") == nil {
		t.Fatal("expected TIME-03 for dependency cycle")
	}
}

func TestTime01bNoDatesNotGated(t *testing.T) {
	src := config.Source{ID: "plan", Columns: map[string]string{"deadline": "Deadline"}}
	ds := ds1(src, nil, rec("plan", "1", "ATM-1", "X", "x", "", ""))
	if hasRule(Timeline(ds), "TIME-01b") == nil {
		t.Fatal("expected TIME-01b for a planned item with no dates and no GATED marker")
	}
}

func TestTime01bGatedExempt(t *testing.T) {
	src := config.Source{ID: "plan", Columns: map[string]string{"deadline": "Deadline"}}
	r := rec("plan", "1", "ATM-1", "X", "x", "", "")
	r.Gated = true
	ds := ds1(src, nil, r)
	if hasRule(Timeline(ds), "TIME-01b") != nil {
		t.Fatal("GATED item must be exempt from TIME-01b")
	}
}

func TestCrossDocDivergentDeadline(t *testing.T) {
	cfg := &config.Config{CrossdocJoin: config.CrossdocJoin{Key: "ticket", Compare: []string{"timeline"}, Authoritative: "plan"}}
	planSrc := config.Source{ID: "plan"}
	mvpSrc := config.Source{ID: "mvp"}
	ds := NewDataset(cfg, []SourceData{
		{Src: planSrc, Records: []model.Record{rec("plan", "3.1", "ATM-400", "X", "x", "2026-09-01", "2026-09-01")}},
		{Src: mvpSrc, Records: []model.Record{rec("mvp", "", "ATM-400", "X", "x", "2026-09-01", "2026-09-17")}},
	})
	got := hasRule(CrossDoc(ds), "XDOC-01")
	if got == nil {
		t.Fatal("expected XDOC-01 for divergent deadline across sources")
	}
	if !strings.Contains(got.Message, "authoritative plan") {
		t.Errorf("cross-doc finding should name the authoritative source: %s", got.Message)
	}
}

func TestCrossDocConsistentNoFinding(t *testing.T) {
	cfg := &config.Config{CrossdocJoin: config.CrossdocJoin{Key: "ticket", Compare: []string{"timeline"}}}
	ds := NewDataset(cfg, []SourceData{
		{Src: config.Source{ID: "plan"}, Records: []model.Record{rec("plan", "3.1", "ATM-400", "X", "x", "2026-09-01", "2026-09-17")}},
		{Src: config.Source{ID: "mvp"}, Records: []model.Record{rec("mvp", "", "ATM-400", "X", "x", "2026-09-01", "2026-09-17")}},
	})
	if f := CrossDoc(ds); len(f) != 0 {
		t.Fatalf("consistent cross-doc items must not be flagged, got %+v", f)
	}
}

func TestIntegrityOrphanDep(t *testing.T) {
	src := config.Source{ID: "plan"}
	ds := ds1(src, nil, rec("plan", "1", "ATM-1", "X", "x", "", "", "ATM-999"))
	if hasRule(Integrity(ds), "INTEG-01") == nil {
		t.Fatal("expected INTEG-01 for orphan dependency")
	}
}

func TestIntegrityStatusTypeMismatch(t *testing.T) {
	src := config.Source{ID: "issues"}
	r := rec("issues", "4.1", "ATM-500", "X", "x", "", "")
	r.Type = "Feature"
	r.Status = "Fixed (→ Fixed.md)"
	ds := ds1(src, nil, r)
	if hasRule(Integrity(ds), "INTEG-02") == nil {
		t.Fatal("expected INTEG-02: a Feature must close Implemented, not Fixed (§11.4.33)")
	}
}

func TestIntegrityStatusTypeMatchNoFinding(t *testing.T) {
	src := config.Source{ID: "issues"}
	r := rec("issues", "4.1", "ATM-500", "X", "x", "", "")
	r.Type = "Feature"
	r.Status = "Implemented (→ Fixed.md)"
	ds := ds1(src, nil, r)
	if hasRule(Integrity(ds), "INTEG-02") != nil {
		t.Fatal("Feature+Implemented is correct, must not be flagged")
	}
}

func TestIntegrityLocationStatus(t *testing.T) {
	src := config.Source{ID: "db"}
	r := rec("db", "1", "ATM-1", "X", "x", "", "")
	r.Location = "Fixed"
	r.Status = "In progress"
	ds := ds1(src, nil, r)
	if hasRule(Integrity(ds), "INTEG-03") == nil {
		t.Fatal("expected INTEG-03: Fixed location with a non-terminal status")
	}
}

func TestStructuralMissingRequiredColumn(t *testing.T) {
	src := config.Source{ID: "plan", RequiredColumns: []string{"deadline"}, Columns: map[string]string{"deadline": "Deadline"}}
	ds := ds1(src, map[string]bool{"deadline": false}, rec("plan", "1", "ATM-1", "X", "x", "", ""))
	if hasRule(Structural(ds), "STRUCT-01") == nil {
		t.Fatal("expected STRUCT-01 for a missing required column")
	}
}

func TestStructuralDuplicateID(t *testing.T) {
	src := config.Source{ID: "plan"}
	ds := ds1(src, nil,
		rec("plan", "1.1", "ATM-1", "A", "a", "", ""),
		rec("plan", "1.1", "ATM-2", "B", "b", "", ""),
	)
	if hasRule(Structural(ds), "STRUCT-02") == nil {
		t.Fatal("expected STRUCT-02 for a duplicate item id")
	}
}

func TestStructuralIDPatternMismatch(t *testing.T) {
	src := config.Source{ID: "plan", IDPattern: `^[0-9]+(\.[0-9]+)*$`}
	ds := ds1(src, nil, rec("plan", "1.1b", "ATM-1", "A", "a", "", ""))
	if hasRule(Structural(ds), "STRUCT-02") == nil {
		t.Fatal("expected STRUCT-02 for id not matching id_pattern")
	}
}

func TestStructuralMonotonicOptIn(t *testing.T) {
	src := config.Source{ID: "plan", IDMonotonic: true}
	ds := ds1(src, nil,
		rec("plan", "2.5.2", "ATM-1", "A", "a", "", ""),
		rec("plan", "2.5.1", "ATM-2", "B", "b", "", ""),
	)
	if hasRule(Structural(ds), "STRUCT-02") == nil {
		t.Fatal("expected STRUCT-02 for out-of-monotonic-order id when id_monotonic is on")
	}
	// off by default → no finding
	src2 := config.Source{ID: "plan"}
	ds2 := ds1(src2, nil,
		rec("plan", "2.5.2", "ATM-1", "A", "a", "", ""),
		rec("plan", "2.5.1", "ATM-2", "B", "b", "", ""),
	)
	if hasRule(Structural(ds2), "STRUCT-02") != nil {
		t.Fatal("monotonic must be off by default (no false positive on real plans)")
	}
}

func TestRunAllDeterministic(t *testing.T) {
	src := config.Source{ID: "plan"}
	build := func() []Finding {
		ds := ds1(src, nil,
			rec("plan", "1", "ATM-1", "Dup", "d", "2026-11-06", "2026-11-09"),
			rec("plan", "2", "ATM-2", "Dup", "d", "2026-11-06", "2026-12-01"),
		)
		return RunAll(ds)
	}
	a, b := build(), build()
	if len(a) != len(b) {
		t.Fatalf("non-deterministic finding count: %d vs %d", len(a), len(b))
	}
	for i := range a {
		if a[i].RuleID != b[i].RuleID || a[i].Locator != b[i].Locator {
			t.Fatalf("non-deterministic ordering at %d: %+v vs %+v", i, a[i], b[i])
		}
	}
}
