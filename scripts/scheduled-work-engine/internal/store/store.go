package store

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sort"
	"sync"
	"time"

	"github.com/google/uuid"
)

// ErrNotFound is returned when an item id does not exist.
var ErrNotFound = errors.New("scheduled-work item not found")

// ErrInvalidStatus is returned when a status outside the closed set is set.
var ErrInvalidStatus = errors.New("invalid status")

// ErrEmptyTitle is returned when a create request has no title.
var ErrEmptyTitle = errors.New("title is required")

// Store is an embedded, CGO-free, JSON-file-backed persistence layer.
//
// Justification (constitution §11.4.6 — decision stated, not guessed):
// a reminder / scheduled-work queue is a low-write-volume workload. A
// JSON-file store needs zero CGO (unlike mattn/go-sqlite3), zero extra
// module dependency (unlike BoltDB), is trivially portable across every
// supported platform (§11.4.81), and is human-inspectable for debugging.
// Durability is provided by write-temp-then-rename atomic replace. A mutex
// serialises all access so concurrent HTTP/3 handlers never corrupt the
// file.
type Store struct {
	mu    sync.RWMutex
	path  string
	items map[string]Item
	// now is injectable for deterministic tests (§11.4.50).
	now func() time.Time
}

// Open loads (or creates) a JSON store at path. A missing file yields an
// empty store; a corrupt file returns an error rather than silently
// dropping data (§11.4.6).
func Open(path string) (*Store, error) {
	s := &Store{path: path, items: map[string]Item{}, now: time.Now}
	if path == "" {
		return s, nil // in-memory only (tests)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return s, nil
		}
		return nil, err
	}
	if len(data) == 0 {
		return s, nil
	}
	var list []Item
	if err := json.Unmarshal(data, &list); err != nil {
		return nil, err
	}
	for _, it := range list {
		s.items[it.ID] = it
	}
	return s, nil
}

// SetClock overrides the time source (tests only).
func (s *Store) SetClock(now func() time.Time) { s.now = now }

// flush writes the store to disk atomically. Caller must hold s.mu.
func (s *Store) flush() error {
	if s.path == "" {
		return nil
	}
	list := make([]Item, 0, len(s.items))
	for _, it := range s.items {
		list = append(list, it)
	}
	sort.Slice(list, func(i, j int) bool { return list[i].CreatedAt.Before(list[j].CreatedAt) })
	data, err := json.MarshalIndent(list, "", "  ")
	if err != nil {
		return err
	}
	dir := filepath.Dir(s.path)
	if dir != "" {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return err
		}
	}
	tmp, err := os.CreateTemp(dir, ".scheduled-work-*.tmp")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		os.Remove(tmpName)
		return err
	}
	if err := tmp.Sync(); err != nil {
		tmp.Close()
		os.Remove(tmpName)
		return err
	}
	if err := tmp.Close(); err != nil {
		os.Remove(tmpName)
		return err
	}
	if err := os.Rename(tmpName, s.path); err != nil {
		return err
	}
	// Best-effort fsync of the containing directory so the rename itself is
	// durable across a power loss (the file's own tmp.Sync above covers its
	// data, but not the directory entry that now points the store path at it).
	fsyncDir(dir)
	return nil
}

// fsyncDir best-effort fsyncs a directory so a prior os.Rename into it is
// persisted. NON-FATAL by contract (§11.4.1 — introduces no new failure mode):
// the rename already succeeded, so the store is consistent in memory and on
// disk; a dir-fsync error (some filesystems return EINVAL on directory Sync)
// must NOT roll back an otherwise-durable write.
func fsyncDir(dir string) {
	if dir == "" {
		dir = "."
	}
	d, err := os.Open(dir)
	if err != nil {
		return
	}
	_ = d.Sync()
	_ = d.Close()
}

// CreateParams are the inputs for Create.
type CreateParams struct {
	Title       string
	Description string
	Status      Status // optional; defaults to StatusScheduled
	DueAt       *time.Time
	Tags        []string
	Source      string
	Notes       string
}

// Create inserts a new item and returns it.
func (s *Store) Create(p CreateParams) (Item, error) {
	if p.Title == "" {
		return Item{}, ErrEmptyTitle
	}
	st := p.Status
	if st == "" {
		st = StatusScheduled
	}
	if !IsValidStatus(st) {
		return Item{}, ErrInvalidStatus
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	now := s.now().UTC()
	it := Item{
		ID:          uuid.NewString(),
		Title:       p.Title,
		Description: p.Description,
		Status:      st,
		DueAt:       p.DueAt,
		Tags:        p.Tags,
		Source:      p.Source,
		Notes:       p.Notes,
		CreatedAt:   now,
		UpdatedAt:   now,
	}
	s.items[it.ID] = it
	if err := s.flush(); err != nil {
		delete(s.items, it.ID)
		return Item{}, err
	}
	return it, nil
}

// Get returns a single item by id.
func (s *Store) Get(id string) (Item, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	it, ok := s.items[id]
	if !ok {
		return Item{}, ErrNotFound
	}
	return it, nil
}

// List returns items, newest-created first, optionally filtered by
// EFFECTIVE status (so "overdue" is queryable).
func (s *Store) List(filter Status) []Item {
	s.mu.RLock()
	defer s.mu.RUnlock()
	now := s.now().UTC()
	out := make([]Item, 0, len(s.items))
	for _, it := range s.items {
		if filter != "" && it.EffectiveStatus(now) != filter {
			continue
		}
		out = append(out, it)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].CreatedAt.After(out[j].CreatedAt) })
	return out
}

// Overdue returns open items whose DueAt has passed.
func (s *Store) Overdue() []Item { return s.List(StatusOverdue) }

// NeedsVerification returns open items a REMINDER must confirm before an
// agent reports the work done (blocked / uncertain / overdue).
func (s *Store) NeedsVerification() []Item {
	s.mu.RLock()
	defer s.mu.RUnlock()
	now := s.now().UTC()
	out := make([]Item, 0)
	for _, it := range s.items {
		if it.NeedsVerification(now) {
			out = append(out, it)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].CreatedAt.After(out[j].CreatedAt) })
	return out
}

// UpdateStatus sets a new (settable) status and refreshes UpdatedAt.
func (s *Store) UpdateStatus(id string, st Status, notes string) (Item, error) {
	if !IsValidStatus(st) {
		return Item{}, ErrInvalidStatus
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	it, ok := s.items[id]
	if !ok {
		return Item{}, ErrNotFound
	}
	prev := it
	it.Status = st
	if notes != "" {
		it.Notes = notes
	}
	it.UpdatedAt = s.now().UTC()
	s.items[id] = it
	if err := s.flush(); err != nil {
		s.items[id] = prev
		return Item{}, err
	}
	return it, nil
}

// MarkDone is a convenience for UpdateStatus(id, StatusDone, notes).
func (s *Store) MarkDone(id, notes string) (Item, error) {
	return s.UpdateStatus(id, StatusDone, notes)
}

// Delete removes an item.
func (s *Store) Delete(id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	it, ok := s.items[id]
	if !ok {
		return ErrNotFound
	}
	delete(s.items, id)
	if err := s.flush(); err != nil {
		s.items[id] = it
		return err
	}
	return nil
}

// Count returns the number of stored items.
func (s *Store) Count() int {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return len(s.items)
}
