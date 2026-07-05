// Package mcp implements a Model Context Protocol (MCP) JSON-RPC 2.0
// dispatcher for the scheduled-work service. The same Dispatcher backs
// both the MCP-over-HTTP endpoint (POST /mcp) and the MCP-over-stdio mode
// used by the Claude Code plugin, and (via the acp package) the
// ACP-equivalent stdio surface — one implementation, three transports.
package mcp

import (
	"encoding/json"
	"fmt"
	"time"

	"github.com/HelixDevelopment/HelixConstitution/scripts/scheduled-work-engine/internal/store"
)

// ProtocolVersion is the MCP protocol revision this server implements.
const ProtocolVersion = "2024-11-05"

// ServerName / ServerVersion identify the server in initialize responses.
const (
	ServerName    = "scheduled-work-engine"
	ServerVersion = "0.1.0"
)

// Request is a JSON-RPC 2.0 request.
type Request struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id,omitempty"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params,omitempty"`
}

// Response is a JSON-RPC 2.0 response.
type Response struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id,omitempty"`
	Result  interface{}     `json:"result,omitempty"`
	Error   *RPCError       `json:"error,omitempty"`
}

// RPCError is a JSON-RPC 2.0 error object.
type RPCError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

// Dispatcher routes MCP methods to the store.
type Dispatcher struct {
	Store *store.Store
}

// New returns a Dispatcher for the given store.
func New(s *store.Store) *Dispatcher { return &Dispatcher{Store: s} }

// Handle processes one JSON-RPC request and returns the response. A nil
// response means the request was a notification (no id) requiring no reply.
func (d *Dispatcher) Handle(req Request) *Response {
	isNotification := len(req.ID) == 0
	resp := &Response{JSONRPC: "2.0", ID: req.ID}
	switch req.Method {
	case "initialize":
		resp.Result = map[string]interface{}{
			"protocolVersion": ProtocolVersion,
			"capabilities":    map[string]interface{}{"tools": map[string]interface{}{}},
			"serverInfo":      map[string]interface{}{"name": ServerName, "version": ServerVersion},
		}
	case "notifications/initialized", "initialized":
		return nil // notification
	case "ping":
		resp.Result = map[string]interface{}{}
	case "tools/list":
		resp.Result = map[string]interface{}{"tools": toolDefs()}
	case "tools/call":
		result, rpcErr := d.callTool(req.Params)
		if rpcErr != nil {
			resp.Error = rpcErr
		} else {
			resp.Result = result
		}
	default:
		if isNotification {
			return nil
		}
		resp.Error = &RPCError{Code: -32601, Message: "method not found: " + req.Method}
	}
	if isNotification {
		return nil
	}
	return resp
}

type toolCallParams struct {
	Name      string          `json:"name"`
	Arguments json.RawMessage `json:"arguments"`
}

func (d *Dispatcher) callTool(raw json.RawMessage) (interface{}, *RPCError) {
	var p toolCallParams
	if err := json.Unmarshal(raw, &p); err != nil {
		return nil, &RPCError{Code: -32602, Message: "invalid params: " + err.Error()}
	}
	payload, err := d.execTool(p.Name, p.Arguments)
	if err != nil {
		// Tool-level errors are reported inside the result with isError=true
		// per MCP semantics (so the model sees them), not as a JSON-RPC error.
		return toolResult(fmt.Sprintf("ERROR: %v", err), true), nil
	}
	return toolResult(payload, false), nil
}

func toolResult(text string, isErr bool) map[string]interface{} {
	return map[string]interface{}{
		"content": []map[string]interface{}{{"type": "text", "text": text}},
		"isError": isErr,
	}
}

// execTool runs a named tool and returns a JSON string payload.
func (d *Dispatcher) execTool(name string, args json.RawMessage) (string, error) {
	switch name {
	case "create_work_item":
		var a struct {
			Title, Description, Status, Source, Notes string
			DueAt                                     *time.Time `json:"due_at"`
			Tags                                      []string
		}
		if err := json.Unmarshal(args, &a); err != nil {
			return "", err
		}
		it, err := d.Store.Create(store.CreateParams{
			Title: a.Title, Description: a.Description, Status: store.Status(a.Status),
			DueAt: a.DueAt, Tags: a.Tags, Source: a.Source, Notes: a.Notes,
		})
		return jsonOf(it, err)
	case "list_work_items":
		var a struct {
			Status string `json:"status"`
		}
		_ = json.Unmarshal(args, &a)
		return jsonOf(d.Store.List(store.Status(a.Status)), nil)
	case "get_work_item":
		id, err := idArg(args)
		if err != nil {
			return "", err
		}
		return jsonOf(d.Store.Get(id))
	case "update_work_item_status":
		var a struct{ ID, Status, Notes string }
		if err := json.Unmarshal(args, &a); err != nil {
			return "", err
		}
		return jsonOf(d.Store.UpdateStatus(a.ID, store.Status(a.Status), a.Notes))
	case "mark_work_item_done":
		var a struct{ ID, Notes string }
		if err := json.Unmarshal(args, &a); err != nil {
			return "", err
		}
		return jsonOf(d.Store.MarkDone(a.ID, a.Notes))
	case "list_overdue_work":
		return jsonOf(d.Store.Overdue(), nil)
	case "list_needs_verification":
		return jsonOf(d.Store.NeedsVerification(), nil)
	default:
		return "", fmt.Errorf("unknown tool: %s", name)
	}
}

func idArg(args json.RawMessage) (string, error) {
	var a struct {
		ID string `json:"id"`
	}
	if err := json.Unmarshal(args, &a); err != nil {
		return "", err
	}
	return a.ID, nil
}

func jsonOf(v interface{}, err error) (string, error) {
	if err != nil {
		return "", err
	}
	b, e := json.MarshalIndent(v, "", "  ")
	if e != nil {
		return "", e
	}
	return string(b), nil
}

// toolDefs returns the MCP tool schema list.
func toolDefs() []map[string]interface{} {
	strProp := func(desc string) map[string]interface{} {
		return map[string]interface{}{"type": "string", "description": desc}
	}
	return []map[string]interface{}{
		{
			"name":        "create_work_item",
			"description": "Record a scheduled work / reminder item (background-queue entry).",
			"inputSchema": map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"title":       strProp("short title of the work"),
					"description": strProp("full description"),
					"status":      strProp("scheduled|in-progress|blocked|uncertain|done|cancelled (default scheduled)"),
					"due_at":      strProp("RFC3339 timestamp when the work is due (optional)"),
					"source":      strProp("consumer-supplied origin label (optional)"),
					"notes":       strProp("free notes (optional)"),
					"tags":        map[string]interface{}{"type": "array", "items": map[string]interface{}{"type": "string"}},
				},
				"required": []string{"title"},
			},
		},
		{"name": "list_work_items", "description": "List work items, optionally filtered by effective status.",
			"inputSchema": map[string]interface{}{"type": "object", "properties": map[string]interface{}{"status": strProp("optional effective-status filter")}}},
		{"name": "get_work_item", "description": "Get one work item by id.",
			"inputSchema": map[string]interface{}{"type": "object", "properties": map[string]interface{}{"id": strProp("item id")}, "required": []string{"id"}}},
		{"name": "update_work_item_status", "description": "Update a work item's status (with optional notes).",
			"inputSchema": map[string]interface{}{"type": "object", "properties": map[string]interface{}{"id": strProp("item id"), "status": strProp("new status"), "notes": strProp("optional notes")}, "required": []string{"id", "status"}}},
		{"name": "mark_work_item_done", "description": "Mark a work item done. Only call AFTER verifying the real outcome.",
			"inputSchema": map[string]interface{}{"type": "object", "properties": map[string]interface{}{"id": strProp("item id"), "notes": strProp("verification evidence / notes")}, "required": []string{"id"}}},
		{"name": "list_overdue_work", "description": "List open items past their due time.",
			"inputSchema": map[string]interface{}{"type": "object", "properties": map[string]interface{}{}}},
		{"name": "list_needs_verification", "description": "List open items (blocked/uncertain/overdue) a REMINDER must confirm before reporting done.",
			"inputSchema": map[string]interface{}{"type": "object", "properties": map[string]interface{}{}}},
	}
}
