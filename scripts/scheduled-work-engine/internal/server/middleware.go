package server

import (
	"crypto/subtle"
	"net/http"
	"os"
	"strconv"

	"github.com/gin-gonic/gin"
)

// defaultMaxBodyBytes is the request body cap when SWQ_MAX_BODY_BYTES is unset
// or invalid: 1 MiB. The service handles small JSON items; an unbounded body
// on a non-loopback bind is a trivial memory-exhaustion vector.
const defaultMaxBodyBytes int64 = 1 << 20 // 1 MiB

// maxBodyBytes resolves the request body cap from SWQ_MAX_BODY_BYTES.
// A missing / unparseable / non-positive value falls back to the 1 MiB
// default — there is intentionally NO "unlimited" setting (that is the
// vulnerability this cap exists to close).
func maxBodyBytes() int64 {
	v := os.Getenv("SWQ_MAX_BODY_BYTES")
	if v == "" {
		return defaultMaxBodyBytes
	}
	n, err := strconv.ParseInt(v, 10, 64)
	if err != nil || n <= 0 {
		return defaultMaxBodyBytes
	}
	return n
}

// MaxBody returns gin middleware that caps the request body at n bytes by
// installing http.MaxBytesReader before any handler reads it. An oversized
// body then fails the JSON bind with *http.MaxBytesError (surfaced as 413 by
// the bind helpers) instead of being read into unbounded memory.
func MaxBody(n int64) gin.HandlerFunc {
	return func(c *gin.Context) {
		if c.Request != nil && c.Request.Body != nil {
			c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, n)
		}
		c.Next()
	}
}

// authToken resolves the optional bearer token from SWQ_AUTH_TOKEN. When
// empty, auth is disabled (frictionless loopback single-user default).
func authToken() string { return os.Getenv("SWQ_AUTH_TOKEN") }

// BearerAuth returns gin middleware that requires
// `Authorization: Bearer <token>` on the request. The comparison is
// constant-time to avoid leaking the token via timing. It is only wired when
// SWQ_AUTH_TOKEN is set; a non-loopback bind SHOULD set it.
func BearerAuth(token string) gin.HandlerFunc {
	want := []byte("Bearer " + token)
	return func(c *gin.Context) {
		got := []byte(c.GetHeader("Authorization"))
		if subtle.ConstantTimeCompare(got, want) != 1 {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
			return
		}
		c.Next()
	}
}
