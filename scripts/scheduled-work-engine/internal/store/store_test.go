package store

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func fixedClock(t time.Time) func() time.Time { return func() time.Time { return t } }

func TestCreateAndGet(t *testing.T) {
	s, _ := Open("")
	it, err := s.Create(CreateParams{Title: "email report"})
	if err != nil {
		t.Fatalf("create: %v", err)
	}
	if it.ID == "" || it.Status != StatusScheduled {
		t.Fatalf("bad item: %+v", it)
	}
	got, err := s.Get(it.ID)
	if err != nil || got.Title != "email report" {
		t.Fatalf("get: %v %+v", err, got)
	}
}

func TestCreateEmptyTitleRejected(t *testing.T) {
	s, _ := Open("")
	if _, err := s.Create(CreateParams{}); err != ErrEmptyTitle {
		t.Fatalf("want ErrEmptyTitle, got %v", err)
	}
}

func TestInvalidStatusRejected(t *testing.T) {
	s, _ := Open("")
	if _, err := s.Create(CreateParams{Title: "x", Status: Status("bogus")}); err != ErrInvalidStatus {
		t.Fatalf("want ErrInvalidStatus, got %v", err)
	}
	it, _ := s.Create(CreateParams{Title: "y"})
	if _, err := s.UpdateStatus(it.ID, Status("nope"), ""); err != ErrInvalidStatus {
		t.Fatalf("want ErrInvalidStatus on update, got %v", err)
	}
}

func TestUpdateAndMarkDone(t *testing.T) {
	s, _ := Open("")
	it, _ := s.Create(CreateParams{Title: "z"})
	up, err := s.UpdateStatus(it.ID, StatusInProgress, "started")
	if err != nil || up.Status != StatusInProgress || up.Notes != "started" {
		t.Fatalf("update: %v %+v", err, up)
	}
	if !up.UpdatedAt.After(it.UpdatedAt) && !up.UpdatedAt.Equal(it.UpdatedAt) {
		t.Fatalf("updatedAt not advanced")
	}
	done, err := s.MarkDone(it.ID, "verified: sink codec present")
	if err != nil || done.Status != StatusDone {
		t.Fatalf("markdone: %v %+v", err, done)
	}
}

func TestOverdueDerived(t *testing.T) {
	now := time.Date(2026, 7, 2, 12, 0, 0, 0, time.UTC)
	s, _ := Open("")
	s.SetClock(fixedClock(now))
	past := now.Add(-time.Hour)
	future := now.Add(time.Hour)
	itPast, _ := s.Create(CreateParams{Title: "overdue one", DueAt: &past})
	s.Create(CreateParams{Title: "future one", DueAt: &future})
	ov := s.Overdue()
	if len(ov) != 1 || ov[0].ID != itPast.ID {
		t.Fatalf("overdue want 1 (%s), got %d %+v", itPast.ID, len(ov), ov)
	}
	// A done item past due is NOT overdue.
	s.MarkDone(itPast.ID, "verified")
	if len(s.Overdue()) != 0 {
		t.Fatalf("done item still overdue")
	}
}

func TestNeedsVerification(t *testing.T) {
	now := time.Date(2026, 7, 2, 12, 0, 0, 0, time.UTC)
	s, _ := Open("")
	s.SetClock(fixedClock(now))
	past := now.Add(-time.Hour)
	s.Create(CreateParams{Title: "blocked item", Status: StatusBlocked})
	s.Create(CreateParams{Title: "uncertain item", Status: StatusUncertain})
	s.Create(CreateParams{Title: "overdue item", DueAt: &past})
	s.Create(CreateParams{Title: "plain scheduled"})
	nv := s.NeedsVerification()
	if len(nv) != 3 {
		t.Fatalf("needs-verification want 3, got %d %+v", len(nv), nv)
	}
}

func TestPersistenceRoundTrip(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "sw.json")
	s1, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	it, _ := s1.Create(CreateParams{Title: "persist me", Tags: []string{"audio"}, Source: "conductor"})
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("file not written: %v", err)
	}
	s2, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	got, err := s2.Get(it.ID)
	if err != nil || got.Title != "persist me" || len(got.Tags) != 1 || got.Source != "conductor" {
		t.Fatalf("reload mismatch: %v %+v", err, got)
	}
}

func TestListFilterByEffectiveStatus(t *testing.T) {
	now := time.Date(2026, 7, 2, 12, 0, 0, 0, time.UTC)
	s, _ := Open("")
	s.SetClock(fixedClock(now))
	past := now.Add(-time.Hour)
	s.Create(CreateParams{Title: "overdue", DueAt: &past})
	s.Create(CreateParams{Title: "plain"})
	if got := s.List(StatusOverdue); len(got) != 1 {
		t.Fatalf("filter overdue want 1, got %d", len(got))
	}
	if got := s.List(StatusScheduled); len(got) != 1 {
		t.Fatalf("filter scheduled want 1, got %d", len(got))
	}
	if got := s.List(""); len(got) != 2 {
		t.Fatalf("no filter want 2, got %d", len(got))
	}
}

func TestDeleteItem(t *testing.T) {
	s, _ := Open("")
	it, _ := s.Create(CreateParams{Title: "delete me"})
	if err := s.Delete(it.ID); err != nil {
		t.Fatalf("delete: %v", err)
	}
	if _, err := s.Get(it.ID); err != ErrNotFound {
		t.Fatalf("after delete: want ErrNotFound, got %v", err)
	}
}

func TestDeleteNotFound(t *testing.T) {
	s, _ := Open("")
	if err := s.Delete("nonexistent"); err != ErrNotFound {
		t.Fatalf("want ErrNotFound, got %v", err)
	}
}

func TestGetNotFound(t *testing.T) {
	s, _ := Open("")
	if _, err := s.Get("nonexistent"); err != ErrNotFound {
		t.Fatalf("want ErrNotFound, got %v", err)
	}
}

func TestCount(t *testing.T) {
	s, _ := Open("")
	if s.Count() != 0 {
		t.Fatalf("empty count: %d", s.Count())
	}
	s.Create(CreateParams{Title: "a"})
	s.Create(CreateParams{Title: "b"})
	if s.Count() != 2 {
		t.Fatalf("count after 2 creates: %d", s.Count())
	}
}

func TestConcurrentCreate(t *testing.T) {
	dir := t.TempDir()
	s, _ := Open(filepath.Join(dir, "c.json"))
	const n = 50
	done := make(chan struct{})
	for i := 0; i < n; i++ {
		go func() { s.Create(CreateParams{Title: "concurrent"}); done <- struct{}{} }()
	}
	for i := 0; i < n; i++ {
		<-done
	}
	if s.Count() != n {
		t.Fatalf("concurrent create lost writes: want %d got %d", n, s.Count())
	}
}
