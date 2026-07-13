// Command scheduled-work is the entry point for the scheduled-work-engine:
// a decoupled, project-agnostic reminder / background-queue tracking
// service exposing REST + MCP-over-HTTP over HTTP/3 (QUIC) with brotli
// compression, plus MCP-over-stdio and an ACP-equivalent stdio surface.
//
// Subcommands:
//
//	serve       Run the HTTP/3 (+ h1/h2 fallback) REST + MCP-HTTP server.
//	mcp-stdio   Run the MCP JSON-RPC server over stdio (Claude Code plugin).
//	acp-stdio   Run the ACP-equivalent JSON-RPC server over stdio.
//	version     Print version.
//
// All configuration is via flags / environment (§11.4.28 decoupling):
//
//	SWQ_ADDR           listen address       (default 127.0.0.1:8787)
//	SWQ_DB             JSON store path      (default ./scheduled_work.json)
//	SWQ_TLS_CERT       TLS cert file (optional; self-signed dev cert if unset)
//	SWQ_TLS_KEY        TLS key file  (optional)
//	SWQ_BROTLI         brotli quality 0-11, or -1 to disable (default 5)
//	SWQ_H3             "1" (default) enable HTTP/3, "0" h1/h2 only
//	SWQ_MAX_BODY_BYTES request body cap in bytes (default 1048576 = 1 MiB;
//	                   an oversized body is rejected with 413)
//	SWQ_AUTH_TOKEN     optional bearer token; when set, every REST + /mcp
//	                   request must carry "Authorization: Bearer <token>"
//	                   (/healthz stays open). Unset = frictionless loopback
//	                   default. A non-loopback bind SHOULD set it.
package main

import (
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	quic "github.com/quic-go/quic-go"
	"github.com/quic-go/quic-go/http3"

	"github.com/HelixDevelopment/HelixConstitution/scripts/scheduled-work-engine/internal/acp"
	"github.com/HelixDevelopment/HelixConstitution/scripts/scheduled-work-engine/internal/mcp"
	"github.com/HelixDevelopment/HelixConstitution/scripts/scheduled-work-engine/internal/server"
	"github.com/HelixDevelopment/HelixConstitution/scripts/scheduled-work-engine/internal/store"
)

const version = "0.1.0"

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}
	switch os.Args[1] {
	case "serve":
		if err := runServe(); err != nil {
			log.Fatalf("serve: %v", err)
		}
	case "mcp-stdio":
		if err := runStdio("mcp"); err != nil {
			log.Fatalf("mcp-stdio: %v", err)
		}
	case "acp-stdio":
		if err := runStdio("acp"); err != nil {
			log.Fatalf("acp-stdio: %v", err)
		}
	case "version", "-v", "--version":
		fmt.Println(version)
	default:
		usage()
		os.Exit(2)
	}
}

func usage() {
	fmt.Fprintf(os.Stderr, "scheduled-work %s\nusage: scheduled-work <serve|mcp-stdio|acp-stdio|version>\n", version)
}

func env(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func openStore() (*store.Store, error) {
	return store.Open(env("SWQ_DB", "./scheduled_work.json"))
}

func brotliQuality() int {
	q, err := strconv.Atoi(env("SWQ_BROTLI", "5"))
	if err != nil {
		return 5
	}
	return q
}

func runStdio(mode string) error {
	st, err := openStore()
	if err != nil {
		return err
	}
	d := mcp.New(st)
	fmt.Fprintf(os.Stderr, "[scheduled-work] %s-stdio ready (store=%s)\n", mode, env("SWQ_DB", "./scheduled_work.json"))
	return acp.Serve(d, os.Stdin, os.Stdout)
}

func runServe() error {
	st, err := openStore()
	if err != nil {
		return err
	}
	addr := env("SWQ_ADDR", "127.0.0.1:8787")
	engine := server.NewEngine(&server.API{Store: st}, brotliQuality())

	var tlsCfg *tls.Config
	if cert, key := os.Getenv("SWQ_TLS_CERT"), os.Getenv("SWQ_TLS_KEY"); cert != "" && key != "" {
		if tlsCfg, err = server.LoadTLS(cert, key); err != nil {
			return err
		}
	} else {
		if tlsCfg, err = server.SelfSignedTLS("localhost"); err != nil {
			return err
		}
		fmt.Fprintln(os.Stderr, "[scheduled-work] WARNING: using self-signed dev TLS cert (set SWQ_TLS_CERT/SWQ_TLS_KEY for production)")
	}

	h3enabled := env("SWQ_H3", "1") == "1"

	// TCP TLS server for HTTP/1.1 + HTTP/2 fallback. Timeouts bound every
	// phase of a request so a slow/idle/hostile client on a non-loopback bind
	// cannot pin a connection open indefinitely (slowloris-class defence).
	// ReadHeaderTimeout is the single most important one (a missing value lets
	// a client dribble headers forever).
	httpSrv := &http.Server{
		Addr:              addr,
		Handler:           engine,
		TLSConfig:         tlsCfg,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	var h3srv *http3.Server
	if h3enabled {
		// HTTP/3 (quic-go) exposes NO per-request ReadTimeout / WriteTimeout
		// analogue to http.Server (§11.4.6 — stated, not guessed: verified via
		// `go doc http3.Server`). The available bounds are the connection-idle
		// timeout (HTTP/3 layer), the QUIC-layer handshake + max-idle timeouts,
		// and the request-header size cap; those are set below. Per-request
		// body-size is bounded by the MaxBody middleware inside the engine.
		h3srv = &http3.Server{
			Addr:           addr,
			Handler:        engine,
			TLSConfig:      tlsCfg,
			IdleTimeout:    60 * time.Second,
			MaxHeaderBytes: 1 << 20, // 1 MiB request-header cap
			QUICConfig: &quic.Config{
				HandshakeIdleTimeout: 5 * time.Second,
				MaxIdleTimeout:       30 * time.Second,
				KeepAlivePeriod:      15 * time.Second,
			},
		}
		// Advertise h3 on the TLS/TCP responses.
		httpSrv.Handler = altSvc(h3srv, engine)
	}

	errCh := make(chan error, 2)
	go func() {
		fmt.Fprintf(os.Stderr, "[scheduled-work] REST+MCP (h1/h2) TLS on tcp %s\n", addr)
		if e := httpSrv.ListenAndServeTLS("", ""); e != nil && !errors.Is(e, http.ErrServerClosed) {
			errCh <- fmt.Errorf("h1/h2: %w", e)
		}
	}()
	if h3enabled {
		go func() {
			fmt.Fprintf(os.Stderr, "[scheduled-work] HTTP/3 (QUIC) on udp %s\n", addr)
			if e := h3srv.ListenAndServe(); e != nil && !errors.Is(e, http.ErrServerClosed) {
				errCh <- fmt.Errorf("h3: %w", e)
			}
		}()
	}

	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
	select {
	case e := <-errCh:
		return e
	case <-sig:
		fmt.Fprintln(os.Stderr, "[scheduled-work] shutting down")
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = httpSrv.Shutdown(ctx)
		if h3srv != nil {
			_ = h3srv.Close()
		}
		return nil
	}
}

// altSvc wraps the engine so every TCP/TLS response advertises the h3
// alternative service, letting clients upgrade to HTTP/3.
func altSvc(h3srv *http3.Server, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = h3srv.SetQUICHeaders(w.Header())
		next.ServeHTTP(w, r)
	})
}
