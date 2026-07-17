// Package server REST handler tests. Exercises every handler via httptest
// against a real in-memory store (no mocks, §11.4.27).
package server

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/HelixDevelopment/HelixConstitution/scripts/scheduled-work-engine/internal/store"
)

// --- helpers ----------------------------------------------------------------

func jsonBody(v any) *bytes.Reader {
	b, _ := json.Marshal(v)
	return bytes.NewReader(b)
}

func createItem(t *testing.T, h http.Handler, title string) store.Item {
	t.Helper()
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/api/v1/items", jsonBody(map[string]string{"title": title}))
	req.Header.Set("Content-Type", "application/json")
	h.ServeHTTP(w, req)
	if w.Code != http.StatusCreated {
		t.Fatalf("createItem %q: want 201, got %d %s", title, w.Code, w.Body.String())
	}
	var it store.Item
	json.NewDecoder(w.Body).Decode(&it)
	return it
}

// --- listItems --------------------------------------------------------------

func TestListItemsEmpty(t *testing.T) {
	eng := engineFor(t)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/items", nil)
	eng.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("want 200, got %d", w.Code)
	}
	var body map[string]any
	json.NewDecoder(w.Body).Decode(&body)
	if int(body["count"].(float64)) != 0 {
		t.Fatalf("want count=0, got %v", body["count"])
	}
}

func TestListItemsReturnsCreated(t *testing.T) {
	eng := engineFor(t)
	createItem(t, eng, "alpha")
	createItem(t, eng, "beta")
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/items", nil)
	eng.ServeHTTP(w, req)
	var body map[string]any
	json.NewDecoder(w.Body).Decode(&body)
	if int(body["count"].(float64)) != 2 {
		t.Fatalf("want count=2, got %v", body["count"])
	}
}

func TestListItemsFilterByStatus(t *testing.T) {
	eng := engineFor(t)
	it := createItem(t, eng, "will-be-done")
	// mark done
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/api/v1/items/"+it.ID+"/done", nil)
	eng.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("markDone: %d", w.Code)
	}
	// list done only
	w2 := httptest.NewRecorder()
	req2, _ := http.NewRequest("GET", "/api/v1/items?status=done", nil)
	eng.ServeHTTP(w2, req2)
	var body map[string]any
	json.NewDecoder(w2.Body).Decode(&body)
	if int(body["count"].(float64)) != 1 {
		t.Fatalf("want 1 done, got %v", body["count"])
	}
}

// --- getItem ----------------------------------------------------------------

func TestGetItemFound(t *testing.T) {
	eng := engineFor(t)
	it := createItem(t, eng, "findme")
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/items/"+it.ID, nil)
	eng.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("want 200, got %d", w.Code)
	}
	var got store.Item
	json.NewDecoder(w.Body).Decode(&got)
	if got.Title != "findme" {
		t.Fatalf("want title=findme, got %q", got.Title)
	}
}

func TestGetItemNotFound(t *testing.T) {
	eng := engineFor(t)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/items/nonexistent", nil)
	eng.ServeHTTP(w, req)
	if w.Code != http.StatusNotFound {
		t.Fatalf("want 404, got %d", w.Code)
	}
}

// --- updateStatus -----------------------------------------------------------

func TestUpdateStatusOK(t *testing.T) {
	eng := engineFor(t)
	it := createItem(t, eng, "update-me")
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("PATCH", "/api/v1/items/"+it.ID+"/status",
		jsonBody(map[string]string{"status": "in-progress", "notes": "started"}))
	req.Header.Set("Content-Type", "application/json")
	eng.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("want 200, got %d %s", w.Code, w.Body.String())
	}
	var got store.Item
	json.NewDecoder(w.Body).Decode(&got)
	if got.Status != store.StatusInProgress || got.Notes != "started" {
		t.Fatalf("unexpected: %+v", got)
	}
}

func TestUpdateStatusInvalid(t *testing.T) {
	eng := engineFor(t)
	it := createItem(t, eng, "bad-status")
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("PATCH", "/api/v1/items/"+it.ID+"/status",
		jsonBody(map[string]string{"status": "bogus"}))
	req.Header.Set("Content-Type", "application/json")
	eng.ServeHTTP(w, req)
	if w.Code != http.StatusBadRequest {
		t.Fatalf("want 400, got %d", w.Code)
	}
}

func TestUpdateStatusNotFound(t *testing.T) {
	eng := engineFor(t)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("PATCH", "/api/v1/items/nonexistent/status",
		jsonBody(map[string]string{"status": "done"}))
	req.Header.Set("Content-Type", "application/json")
	eng.ServeHTTP(w, req)
	if w.Code != http.StatusNotFound {
		t.Fatalf("want 404, got %d", w.Code)
	}
}

// --- markDone ---------------------------------------------------------------

func TestMarkDoneOK(t *testing.T) {
	eng := engineFor(t)
	it := createItem(t, eng, "finish-me")
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/api/v1/items/"+it.ID+"/done",
		jsonBody(map[string]string{"notes": "verified"}))
	req.Header.Set("Content-Type", "application/json")
	eng.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("want 200, got %d %s", w.Code, w.Body.String())
	}
	var got store.Item
	json.NewDecoder(w.Body).Decode(&got)
	if got.Status != store.StatusDone {
		t.Fatalf("want done, got %q", got.Status)
	}
}

func TestMarkDoneEmptyBodyTolerated(t *testing.T) {
	eng := engineFor(t)
	it := createItem(t, eng, "no-body")
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/api/v1/items/"+it.ID+"/done", nil)
	eng.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("empty body markDone: want 200, got %d %s", w.Code, w.Body.String())
	}
}

func TestMarkDoneNotFound(t *testing.T) {
	eng := engineFor(t)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/api/v1/items/nonexistent/done", nil)
	eng.ServeHTTP(w, req)
	if w.Code != http.StatusNotFound {
		t.Fatalf("want 404, got %d", w.Code)
	}
}

// --- deleteItem -------------------------------------------------------------

func TestDeleteItemOK(t *testing.T) {
	eng := engineFor(t)
	it := createItem(t, eng, "delete-me")
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("DELETE", "/api/v1/items/"+it.ID, nil)
	eng.ServeHTTP(w, req)
	if w.Code != http.StatusNoContent {
		t.Fatalf("want 204, got %d", w.Code)
	}
	// confirm gone
	w2 := httptest.NewRecorder()
	req2, _ := http.NewRequest("GET", "/api/v1/items/"+it.ID, nil)
	eng.ServeHTTP(w2, req2)
	if w2.Code != http.StatusNotFound {
		t.Fatalf("after delete: want 404, got %d", w2.Code)
	}
}

func TestDeleteItemNotFound(t *testing.T) {
	eng := engineFor(t)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("DELETE", "/api/v1/items/nonexistent", nil)
	eng.ServeHTTP(w, req)
	if w.Code != http.StatusNotFound {
		t.Fatalf("want 404, got %d", w.Code)
	}
}

// --- overdue ----------------------------------------------------------------

func TestOverdueEndpoint(t *testing.T) {
	// create an item with DueAt in the past via a dedicated store
	st, _ := store.Open("")
	st.SetClock(func() time.Time { return time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC) })
	past := time.Date(2025, 12, 31, 0, 0, 0, 0, time.UTC)
	st.Create(store.CreateParams{Title: "old", DueAt: &past})
	api := &API{Store: st}
	eng2 := NewEngine(api, -1)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/items/overdue", nil)
	eng2.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("want 200, got %d", w.Code)
	}
	var body map[string]any
	json.NewDecoder(w.Body).Decode(&body)
	if int(body["count"].(float64)) != 1 {
		t.Fatalf("want 1 overdue, got %v", body["count"])
	}
}

// --- needsVerification ------------------------------------------------------

func TestNeedsVerificationEndpoint(t *testing.T) {
	st, _ := store.Open("")
	st.Create(store.CreateParams{Title: "blocked", Status: store.StatusBlocked})
	st.Create(store.CreateParams{Title: "normal"})
	api := &API{Store: st}
	eng := NewEngine(api, -1)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/items/needs-verification", nil)
	eng.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("want 200, got %d", w.Code)
	}
	var body map[string]any
	json.NewDecoder(w.Body).Decode(&body)
	if int(body["count"].(float64)) != 1 {
		t.Fatalf("want 1 needs-verification, got %v", body["count"])
	}
}

// --- healthz ----------------------------------------------------------------

func TestHealthzReturnsOK(t *testing.T) {
	eng := engineFor(t)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/healthz", nil)
	eng.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("want 200, got %d", w.Code)
	}
	var body map[string]any
	json.NewDecoder(w.Body).Decode(&body)
	if body["status"] != "ok" {
		t.Fatalf("want status=ok, got %v", body["status"])
	}
}

// --- writeStoreErr mapping --------------------------------------------------

func TestWriteStoreErrMappings(t *testing.T) {
	api := &API{Store: nil}
	eng := NewEngine(api, -1)

	// NotFound
	st, _ := store.Open("")
	api.Store = st
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/items/ghost", nil)
	eng.ServeHTTP(w, req)
	if w.Code != http.StatusNotFound {
		t.Fatalf("not found: want 404, got %d", w.Code)
	}

	// InvalidStatus
	w2 := httptest.NewRecorder()
	req2, _ := http.NewRequest("PATCH", "/api/v1/items/ghost/status",
		jsonBody(map[string]string{"status": "invalid"}))
	req2.Header.Set("Content-Type", "application/json")
	eng.ServeHTTP(w2, req2)
	// This returns 404 (item not found before status check) — verify no 500
	if w2.Code == http.StatusInternalServerError {
		t.Fatalf("invalid status on missing item should not 500, got %d", w2.Code)
	}

	// EmptyTitle via create
	w3 := httptest.NewRecorder()
	req3, _ := http.NewRequest("POST", "/api/v1/items",
		jsonBody(map[string]string{"title": ""}))
	req3.Header.Set("Content-Type", "application/json")
	eng.ServeHTTP(w3, req3)
	if w3.Code != http.StatusBadRequest {
		t.Fatalf("empty title: want 400, got %d", w3.Code)
	}
}

// --- malformed JSON ---------------------------------------------------------

func TestMalformedJSONReturns400(t *testing.T) {
	eng := engineFor(t)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/api/v1/items", bytes.NewReader([]byte("{bad json")))
	req.Header.Set("Content-Type", "application/json")
	eng.ServeHTTP(w, req)
	if w.Code != http.StatusBadRequest {
		t.Fatalf("malformed JSON: want 400, got %d", w.Code)
	}
}
