package server

import (
	"bytes"
	"net/http"
	"strconv"
	"strings"

	"github.com/andybalholm/brotli"
	"github.com/gin-gonic/gin"
)

// brotliMinSize is the smallest response body worth brotli-compressing. Below
// this, compression framing overhead outweighs the saving; and a bodyless
// status (1xx / 204 / 304) must never carry a Content-Encoding at all. The
// created-item JSON payload (~185 bytes) is above this threshold, so the
// happy-path REST responses still compress.
const brotliMinSize = 128

// brotliWriter buffers the response body so the middleware can decide, AFTER
// the handler runs, whether the body is (a) large enough to be worth
// compressing and (b) permitted to carry a body at all. It is a full-buffer
// writer, appropriate here because the service only emits small JSON responses
// (no streaming / SSE); a streaming surface would need a size-triggered flush
// instead.
type brotliWriter struct {
	gin.ResponseWriter
	buf     bytes.Buffer
	status  int
	quality int
}

// WriteHeader records the intended status AND forwards it to the underlying
// gin writer (gin records the status without flushing). Forwarding matters on
// the panic path: if the handler panics, finish() is never called, and the
// Recovery middleware's AbortWithStatus flushes the correct status through the
// still-pristine underlying writer.
func (w *brotliWriter) WriteHeader(status int) {
	w.status = status
	w.ResponseWriter.WriteHeader(status)
}

func (w *brotliWriter) Write(data []byte) (int, error) { return w.buf.Write(data) }

func (w *brotliWriter) WriteString(s string) (int, error) { return w.buf.WriteString(s) }

// bodylessStatus reports whether an HTTP status MUST NOT carry a body (and
// therefore never a Content-Encoding): 1xx informational, 204 No Content,
// 304 Not Modified.
func bodylessStatus(status int) bool {
	return status == http.StatusNoContent ||
		status == http.StatusNotModified ||
		(status >= 100 && status < 200)
}

// finish flushes the buffered response to the underlying writer, brotli-
// compressing ONLY when the status permits a body AND the body clears the
// size threshold. Called explicitly after c.Next() (never deferred) so a
// panic bypasses it and leaves the Recovery middleware a clean writer.
func (w *brotliWriter) finish() {
	status := w.status
	if status == 0 {
		status = http.StatusOK
	}
	body := w.buf.Bytes()
	h := w.ResponseWriter.Header()

	// Bodyless statuses: flush the status alone, never a body or an encoding.
	if bodylessStatus(status) {
		h.Del("Content-Encoding")
		h.Del("Content-Length")
		w.ResponseWriter.WriteHeader(status)
		w.ResponseWriter.WriteHeaderNow()
		return
	}

	// Small bodies: pass through uncompressed with an exact Content-Length.
	if len(body) < brotliMinSize {
		h.Del("Content-Encoding")
		h.Set("Content-Length", strconv.Itoa(len(body)))
		w.ResponseWriter.WriteHeader(status)
		if len(body) > 0 {
			_, _ = w.ResponseWriter.Write(body)
		} else {
			w.ResponseWriter.WriteHeaderNow()
		}
		return
	}

	// Worth compressing.
	h.Set("Content-Encoding", "br")
	h.Del("Content-Length") // length is unknown until after compression
	w.ResponseWriter.WriteHeader(status)
	bw := brotli.NewWriterLevel(w.ResponseWriter, w.quality)
	_, _ = bw.Write(body)
	_ = bw.Close()
}

// Brotli returns gin middleware that compresses responses with Brotli
// (RFC 7932) for clients that accept it. Bodyless statuses (204/304/1xx) and
// bodies below brotliMinSize pass through uncompressed so tiny/empty responses
// carry neither a spurious Content-Encoding nor net-negative framing overhead.
func Brotli(quality int) gin.HandlerFunc {
	if quality < brotli.BestSpeed {
		quality = brotli.DefaultCompression
	}
	if quality > brotli.BestCompression {
		quality = brotli.BestCompression
	}
	return func(c *gin.Context) {
		if !strings.Contains(c.GetHeader("Accept-Encoding"), "br") {
			c.Next()
			return
		}
		// The response varies by Accept-Encoding regardless of whether this
		// particular one ends up compressed (size/bodyless threshold).
		c.Header("Vary", "Accept-Encoding")
		bw := &brotliWriter{ResponseWriter: c.Writer, quality: quality}
		c.Writer = bw
		c.Next()
		bw.finish()
	}
}
