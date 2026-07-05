// Package acp provides the stdio JSON-RPC serve loop that backs both the
// MCP-over-stdio transport (Claude Code plugin) and the ACP-equivalent
// surface.
//
// HONEST NOTE ON ACP (constitution §11.4.6, §11.4.99):
// "ACP" (Agent Client Protocol, agentclientprotocol.com) is an emerging
// JSON-RPC-2.0-over-stdio protocol whose full session/prompt-turn model is
// designed for interactive coding AGENTS, not for a stateless work-queue
// service. Implementing the complete ACP agent lifecycle here would be
// inventing behaviour that does not fit this service. Instead this package
// exposes the SAME newline-delimited JSON-RPC-2.0-over-stdio transport ACP
// uses, dispatching to the identical tool set as the MCP surface. It is
// therefore an ACP-EQUIVALENT adapter, clearly labelled — not a claim of
// full ACP-agent conformance. A consuming ACP client speaks JSON-RPC to it
// exactly as it would to an MCP stdio server.
package acp

import (
	"bufio"
	"encoding/json"
	"io"

	"github.com/HelixDevelopment/HelixConstitution/scripts/scheduled-work-engine/internal/mcp"
)

// Serve runs a newline-delimited JSON-RPC 2.0 loop over r/w, dispatching
// every request to the given MCP dispatcher. It returns when r reaches EOF.
func Serve(d *mcp.Dispatcher, r io.Reader, w io.Writer) error {
	scanner := bufio.NewScanner(r)
	scanner.Buffer(make([]byte, 0, 64*1024), 8*1024*1024)
	enc := json.NewEncoder(w)
	for scanner.Scan() {
		line := scanner.Bytes()
		if len(line) == 0 {
			continue
		}
		var req mcp.Request
		if err := json.Unmarshal(line, &req); err != nil {
			_ = enc.Encode(mcp.Response{
				JSONRPC: "2.0",
				Error:   &mcp.RPCError{Code: -32700, Message: "parse error: " + err.Error()},
			})
			continue
		}
		resp := d.Handle(req)
		if resp == nil {
			continue // notification, no reply
		}
		if err := enc.Encode(resp); err != nil {
			return err
		}
	}
	return scanner.Err()
}
