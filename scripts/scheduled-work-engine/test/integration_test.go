// Package test holds the integration test that ACTUALLY boots the HTTP/3
// (QUIC) server and round-trips a real request over HTTP/3 with brotli
// compression — no mocks (constitution §11.4.27 no-fakes-beyond-unit).
package test

import (
	"bytes"
	"context"
	"crypto/tls"
	"encoding/json"
	"io"
	"net"
	"net/http"
	"strconv"
	"testing"
	"time"

	"github.com/andybalholm/brotli"
	"github.com/quic-go/quic-go/http3"

	"github.com/HelixDevelopment/HelixConstitution/scripts/scheduled-work-engine/internal/server"
	"github.com/HelixDevelopment/HelixConstitution/scripts/scheduled-work-engine/internal/store"
)

// bootH3 starts the real gin engine over a real HTTP/3 server on an
// ephemeral UDP port and returns the base URL + a shutdown func.
func bootH3(t *testing.T) (string, *http.Client, func()) {
	t.Helper()
	st, err := store.Open("") // in-memory
	if err != nil {
		t.Fatal(err)
	}
	engine := server.NewEngine(&server.API{Store: st}, brotli.DefaultCompression)
	tlsCfg, err := server.SelfSignedTLS("localhost")
	if err != nil {
		t.Fatal(err)
	}

	udpConn, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 0})
	if err != nil {
		t.Fatal(err)
	}
	addr := udpConn.LocalAddr().(*net.UDPAddr)

	h3 := &http3.Server{Handler: engine, TLSConfig: tlsCfg}
	go func() { _ = h3.Serve(udpConn) }()

	// HTTP/3-only client. InsecureSkipVerify: dev self-signed cert.
	tr := &http3.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true, NextProtos: []string{"h3"}},
	}
	client := &http.Client{Transport: tr, Timeout: 10 * time.Second}

	base := "https://127.0.0.1:" + strconv.Itoa(addr.Port)
	// Wait for the server to accept QUIC connections.
	waitReady(t, client, base+"/healthz")

	return base, client, func() {
		tr.Close()
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		_ = h3.Shutdown(ctx)
		udpConn.Close()
	}
}

func waitReady(t *testing.T, c *http.Client, url string) {
	t.Helper()
	deadline := time.Now().Add(8 * time.Second)
	for time.Now().Before(deadline) {
		resp, err := c.Get(url)
		if err == nil {
			resp.Body.Close()
			if resp.StatusCode == 200 && resp.Proto == "HTTP/3.0" {
				return
			}
		}
		time.Sleep(100 * time.Millisecond)
	}
	t.Fatalf("HTTP/3 server did not become ready at %s", url)
}

// readBody transparently brotli-decodes when the server advertised it.
func readBody(t *testing.T, resp *http.Response) []byte {
	t.Helper()
	var r io.Reader = resp.Body
	if resp.Header.Get("Content-Encoding") == "br" {
		r = brotli.NewReader(resp.Body)
	}
	data, err := io.ReadAll(r)
	if err != nil {
		t.Fatalf("read body: %v", err)
	}
	return data
}

func TestHTTP3BrotliRoundTripLifecycle(t *testing.T) {
	base, client, shutdown := bootH3(t)
	defer shutdown()

	// 1. CREATE over HTTP/3 with Accept-Encoding: br.
	createBody, _ := json.Marshal(map[string]interface{}{
		"title":  "flash D1 firmware",
		"status": "blocked",
		"source": "conductor",
	})
	req, _ := http.NewRequest("POST", base+"/api/v1/items", bytes.NewReader(createBody))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept-Encoding", "br")
	resp, err := client.Do(req)
	if err != nil {
		t.Fatalf("create over h3: %v", err)
	}
	if resp.Proto != "HTTP/3.0" {
		t.Fatalf("expected HTTP/3.0, got %s", resp.Proto)
	}
	if enc := resp.Header.Get("Content-Encoding"); enc != "br" {
		t.Fatalf("expected brotli Content-Encoding 'br', got %q", enc)
	}
	var created store.Item
	if err := json.Unmarshal(readBody(t, resp), &created); err != nil {
		t.Fatalf("decode created (post-brotli): %v", err)
	}
	resp.Body.Close()
	if created.ID == "" || created.Title != "flash D1 firmware" || created.Status != store.StatusBlocked {
		t.Fatalf("bad created item: %+v", created)
	}
	t.Logf("H3+brotli CREATE ok: id=%s status=%s", created.ID, created.Status)

	// 2. LIST needs-verification (blocked qualifies) over HTTP/3 + brotli.
	resp2 := getBr(t, client, base+"/api/v1/items/needs-verification")
	var nv struct {
		Items []store.Item `json:"items"`
		Count int          `json:"count"`
	}
	json.Unmarshal(readBody(t, resp2), &nv)
	resp2.Body.Close()
	if nv.Count != 1 || nv.Items[0].ID != created.ID {
		t.Fatalf("needs-verification mismatch: %+v", nv)
	}
	t.Logf("H3+brotli LIST needs-verification ok: count=%d", nv.Count)

	// 3. MARK DONE over HTTP/3.
	doneReq, _ := http.NewRequest("POST", base+"/api/v1/items/"+created.ID+"/done",
		bytes.NewReader([]byte(`{"notes":"verified: sink codec present"}`)))
	doneReq.Header.Set("Content-Type", "application/json")
	doneReq.Header.Set("Accept-Encoding", "br")
	dr, err := client.Do(doneReq)
	if err != nil {
		t.Fatalf("mark-done over h3: %v", err)
	}
	var done store.Item
	json.Unmarshal(readBody(t, dr), &done)
	dr.Body.Close()
	if done.Status != store.StatusDone {
		t.Fatalf("mark-done did not set status: %+v", done)
	}
	t.Logf("H3+brotli MARK-DONE ok: status=%s notes=%q", done.Status, done.Notes)

	// 4. VERIFY: needs-verification now empty (state delta captured).
	resp4 := getBr(t, client, base+"/api/v1/items/needs-verification")
	var nv2 struct {
		Count int `json:"count"`
	}
	json.Unmarshal(readBody(t, resp4), &nv2)
	resp4.Body.Close()
	if nv2.Count != 0 {
		t.Fatalf("after mark-done needs-verification should be 0, got %d", nv2.Count)
	}
	t.Logf("H3+brotli VERIFY ok: needs-verification now count=%d", nv2.Count)
}

func TestHTTP3MCPEndpoint(t *testing.T) {
	base, client, shutdown := bootH3(t)
	defer shutdown()

	// MCP tools/call create_work_item over HTTP/3.
	body := `{"jsonrpc":"2.0","id":"1","method":"tools/call","params":{"name":"create_work_item","arguments":{"title":"mcp over h3"}}}`
	req, _ := http.NewRequest("POST", base+"/mcp", bytes.NewReader([]byte(body)))
	req.Header.Set("Content-Type", "application/json")
	resp, err := client.Do(req)
	if err != nil {
		t.Fatalf("mcp over h3: %v", err)
	}
	defer resp.Body.Close()
	if resp.Proto != "HTTP/3.0" {
		t.Fatalf("expected HTTP/3.0, got %s", resp.Proto)
	}
	data := readBody(t, resp)
	var rpc struct {
		Result struct {
			Content []struct {
				Text string `json:"text"`
			} `json:"content"`
			IsError bool `json:"isError"`
		} `json:"result"`
	}
	if err := json.Unmarshal(data, &rpc); err != nil {
		t.Fatalf("decode mcp resp: %v (%s)", err, data)
	}
	if rpc.Result.IsError || len(rpc.Result.Content) == 0 {
		t.Fatalf("mcp create errored or empty: %s", data)
	}
	if !bytes.Contains([]byte(rpc.Result.Content[0].Text), []byte("mcp over h3")) {
		t.Fatalf("mcp create text missing title: %s", rpc.Result.Content[0].Text)
	}
	t.Logf("H3 MCP tools/call create_work_item ok")
}

func getBr(t *testing.T, c *http.Client, url string) *http.Response {
	t.Helper()
	req, _ := http.NewRequest("GET", url, nil)
	req.Header.Set("Accept-Encoding", "br")
	resp, err := c.Do(req)
	if err != nil {
		t.Fatalf("GET %s: %v", url, err)
	}
	return resp
}
