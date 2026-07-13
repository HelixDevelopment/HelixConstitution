package server

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"

	"github.com/HelixDevelopment/HelixConstitution/scripts/scheduled-work-engine/internal/mcp"
)

// mcpHTTP serves MCP JSON-RPC 2.0 over HTTP POST (streamable-HTTP style).
// A notification (no id) yields 204 No Content.
func (a *API) mcpHTTP(c *gin.Context) {
	var req mcp.Request
	if err := c.ShouldBindJSON(&req); err != nil {
		// An oversized body (MaxBody cap) is a transport-level violation → 413,
		// distinct from a malformed-but-small body → JSON-RPC parse error.
		var mbe *http.MaxBytesError
		if errors.As(err, &mbe) {
			c.JSON(http.StatusRequestEntityTooLarge, gin.H{"error": "request body too large"})
			return
		}
		c.JSON(http.StatusOK, mcp.Response{
			JSONRPC: "2.0",
			Error:   &mcp.RPCError{Code: -32700, Message: "parse error: " + err.Error()},
		})
		return
	}
	resp := mcp.New(a.Store).Handle(req)
	if resp == nil {
		c.Status(http.StatusNoContent)
		return
	}
	c.JSON(http.StatusOK, resp)
}
