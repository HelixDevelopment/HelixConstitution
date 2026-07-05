// Package server hardening tests (constitution §11.4.43 TDD RED-first,
// §11.4.115 polarity). These exercise the REAL gin engine + REAL store (no
// mocks, §11.4.27) via httptest, asserting the network-facing hardening
// added for non-loopback binds: request body-size cap, optional bearer-token
// auth, and production TLS 1.3 pinning.
package server

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"math/big"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/HelixDevelopment/HelixConstitution/scripts/scheduled-work-engine/internal/store"
)

// engineFor builds an engine over a fresh in-memory store with brotli off.
func engineFor(t *testing.T) http.Handler {
	t.Helper()
	st, err := store.Open("")
	if err != nil {
		t.Fatal(err)
	}
	return NewEngine(&API{Store: st}, -1)
}

// --- WARNING #1: request body-size limit -----------------------------------

func TestMaxBodyRejectsOversized(t *testing.T) {
	t.Setenv("SWQ_MAX_BODY_BYTES", "64")
	eng := engineFor(t)

	// Oversized body (> 64 bytes) MUST be rejected cleanly (413), never read
	// into unbounded memory.
	big := `{"title":"` + strings.Repeat("A", 200) + `"}`
	if len(big) <= 64 {
		t.Fatalf("test setup: oversized body not actually oversized (%d)", len(big))
	}
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/api/v1/items", bytes.NewReader([]byte(big)))
	req.Header.Set("Content-Type", "application/json")
	eng.ServeHTTP(w, req)
	if w.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("oversized body: want 413, got %d body=%s", w.Code, w.Body.String())
	}

	// A normal (small) body still succeeds.
	small := `{"title":"ok"}`
	w2 := httptest.NewRecorder()
	req2, _ := http.NewRequest("POST", "/api/v1/items", bytes.NewReader([]byte(small)))
	req2.Header.Set("Content-Type", "application/json")
	eng.ServeHTTP(w2, req2)
	if w2.Code != http.StatusCreated {
		t.Fatalf("small body: want 201, got %d body=%s", w2.Code, w2.Body.String())
	}
}

func TestMaxBodyAppliesToMCP(t *testing.T) {
	t.Setenv("SWQ_MAX_BODY_BYTES", "64")
	eng := engineFor(t)
	big := `{"jsonrpc":"2.0","id":"1","method":"tools/call","params":{"name":"create_work_item","arguments":{"title":"` + strings.Repeat("Z", 200) + `"}}}`
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/mcp", bytes.NewReader([]byte(big)))
	req.Header.Set("Content-Type", "application/json")
	eng.ServeHTTP(w, req)
	if w.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("oversized MCP body: want 413, got %d body=%s", w.Code, w.Body.String())
	}
}

func TestMaxBodyDefaultAllowsNormalPayload(t *testing.T) {
	// No env override => default 1 MiB; a normal payload succeeds.
	eng := engineFor(t)
	body := `{"title":"normal","description":"a reasonable description","source":"conductor"}`
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/api/v1/items", bytes.NewReader([]byte(body)))
	req.Header.Set("Content-Type", "application/json")
	eng.ServeHTTP(w, req)
	if w.Code != http.StatusCreated {
		t.Fatalf("normal body under default limit: want 201, got %d", w.Code)
	}
}

// --- #3: optional bearer-token auth ----------------------------------------

func TestBearerAuthRequiredWhenTokenSet(t *testing.T) {
	t.Setenv("SWQ_AUTH_TOKEN", "s3cr3t-token")
	eng := engineFor(t)

	// (a) no Authorization header => 401
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/api/v1/items", bytes.NewReader([]byte(`{"title":"x"}`)))
	req.Header.Set("Content-Type", "application/json")
	eng.ServeHTTP(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("no auth header: want 401, got %d", w.Code)
	}

	// (b) wrong token => 401
	w2 := httptest.NewRecorder()
	req2, _ := http.NewRequest("POST", "/api/v1/items", bytes.NewReader([]byte(`{"title":"x"}`)))
	req2.Header.Set("Content-Type", "application/json")
	req2.Header.Set("Authorization", "Bearer wrong-token")
	eng.ServeHTTP(w2, req2)
	if w2.Code != http.StatusUnauthorized {
		t.Fatalf("wrong token: want 401, got %d", w2.Code)
	}

	// (c) correct token => 201
	w3 := httptest.NewRecorder()
	req3, _ := http.NewRequest("POST", "/api/v1/items", bytes.NewReader([]byte(`{"title":"x"}`)))
	req3.Header.Set("Content-Type", "application/json")
	req3.Header.Set("Authorization", "Bearer s3cr3t-token")
	eng.ServeHTTP(w3, req3)
	if w3.Code != http.StatusCreated {
		t.Fatalf("correct token: want 201, got %d body=%s", w3.Code, w3.Body.String())
	}

	// (d) /mcp is protected too
	w4 := httptest.NewRecorder()
	req4, _ := http.NewRequest("POST", "/mcp", bytes.NewReader([]byte(`{"jsonrpc":"2.0","id":"1","method":"tools/list"}`)))
	req4.Header.Set("Content-Type", "application/json")
	eng.ServeHTTP(w4, req4)
	if w4.Code != http.StatusUnauthorized {
		t.Fatalf("/mcp without token: want 401, got %d", w4.Code)
	}

	// (e) /healthz stays open (liveness probe) even with auth enabled
	w5 := httptest.NewRecorder()
	req5, _ := http.NewRequest("GET", "/healthz", nil)
	eng.ServeHTTP(w5, req5)
	if w5.Code != http.StatusOK {
		t.Fatalf("/healthz with auth enabled: want 200 (open), got %d", w5.Code)
	}
}

func TestBearerAuthDisabledByDefault(t *testing.T) {
	// SWQ_AUTH_TOKEN unset => behaviour unchanged, no auth required.
	os.Unsetenv("SWQ_AUTH_TOKEN")
	eng := engineFor(t)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/api/v1/items", bytes.NewReader([]byte(`{"title":"frictionless"}`)))
	req.Header.Set("Content-Type", "application/json")
	eng.ServeHTTP(w, req)
	if w.Code != http.StatusCreated {
		t.Fatalf("auth disabled: want 201 without any header, got %d", w.Code)
	}
}

// --- #6: production TLS pins TLS 1.3 ---------------------------------------

func TestLoadTLSPinsTLS13(t *testing.T) {
	dir := t.TempDir()
	certFile := filepath.Join(dir, "cert.pem")
	keyFile := filepath.Join(dir, "key.pem")
	writeSelfSignedPair(t, certFile, keyFile)

	cfg, err := LoadTLS(certFile, keyFile)
	if err != nil {
		t.Fatalf("LoadTLS: %v", err)
	}
	if cfg.MinVersion != tls.VersionTLS13 {
		t.Fatalf("production LoadTLS MUST pin TLS 1.3 (MinVersion=%x), got %x", tls.VersionTLS13, cfg.MinVersion)
	}
}

func writeSelfSignedPair(t *testing.T, certFile, keyFile string) {
	t.Helper()
	priv, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	serial, _ := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
	tmpl := x509.Certificate{
		SerialNumber:          serial,
		Subject:               pkix.Name{CommonName: "test"},
		NotBefore:             time.Now().Add(-time.Hour),
		NotAfter:              time.Now().Add(time.Hour),
		KeyUsage:              x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		BasicConstraintsValid: true,
		DNSNames:              []string{"localhost"},
	}
	der, err := x509.CreateCertificate(rand.Reader, &tmpl, &tmpl, &priv.PublicKey, priv)
	if err != nil {
		t.Fatal(err)
	}
	keyDER, err := x509.MarshalECPrivateKey(priv)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(certFile, pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(keyFile, pem.EncodeToMemory(&pem.Block{Type: "EC PRIVATE KEY", Bytes: keyDER}), 0o600); err != nil {
		t.Fatal(err)
	}
}
