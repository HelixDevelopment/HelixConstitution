package mcp

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/HelixDevelopment/HelixConstitution/scripts/scheduled-work-engine/internal/store"
)

func newDispatcher() *Dispatcher {
	s, _ := store.Open("")
	return New(s)
}

func req(method string, id string, params interface{}) Request {
	var p json.RawMessage
	if params != nil {
		p, _ = json.Marshal(params)
	}
	return Request{JSONRPC: "2.0", ID: json.RawMessage(`"` + id + `"`), Method: method, Params: p}
}

func TestInitialize(t *testing.T) {
	d := newDispatcher()
	resp := d.Handle(req("initialize", "1", nil))
	if resp == nil || resp.Error != nil {
		t.Fatalf("initialize failed: %+v", resp)
	}
	m := resp.Result.(map[string]interface{})
	if m["protocolVersion"] != ProtocolVersion {
		t.Fatalf("bad protocolVersion: %v", m["protocolVersion"])
	}
}

func TestNotificationNoReply(t *testing.T) {
	d := newDispatcher()
	// no id => notification
	if resp := d.Handle(Request{JSONRPC: "2.0", Method: "notifications/initialized"}); resp != nil {
		t.Fatalf("notification must not reply, got %+v", resp)
	}
}

func TestToolsList(t *testing.T) {
	d := newDispatcher()
	resp := d.Handle(req("tools/list", "2", nil))
	tools := resp.Result.(map[string]interface{})["tools"].([]map[string]interface{})
	names := map[string]bool{}
	for _, tl := range tools {
		names[tl["name"].(string)] = true
	}
	for _, want := range []string{"create_work_item", "list_work_items", "mark_work_item_done", "list_overdue_work", "list_needs_verification"} {
		if !names[want] {
			t.Fatalf("missing tool %s", want)
		}
	}
}

func TestToolCallCreateThenList(t *testing.T) {
	d := newDispatcher()
	// create
	resp := d.Handle(req("tools/call", "3", toolCallParams{Name: "create_work_item", Arguments: json.RawMessage(`{"title":"deploy build","status":"blocked"}`)}))
	res := resp.Result.(map[string]interface{})
	if res["isError"].(bool) {
		t.Fatalf("create tool errored: %+v", res)
	}
	text := res["content"].([]map[string]interface{})[0]["text"].(string)
	if !strings.Contains(text, "deploy build") {
		t.Fatalf("create text missing title: %s", text)
	}
	// list needs-verification (blocked qualifies)
	resp2 := d.Handle(req("tools/call", "4", toolCallParams{Name: "list_needs_verification", Arguments: json.RawMessage(`{}`)}))
	text2 := resp2.Result.(map[string]interface{})["content"].([]map[string]interface{})[0]["text"].(string)
	if !strings.Contains(text2, "deploy build") {
		t.Fatalf("needs-verification did not include blocked item: %s", text2)
	}
}

func TestToolCallUnknownTool(t *testing.T) {
	d := newDispatcher()
	resp := d.Handle(req("tools/call", "5", toolCallParams{Name: "nonexistent", Arguments: json.RawMessage(`{}`)}))
	res := resp.Result.(map[string]interface{})
	if !res["isError"].(bool) {
		t.Fatalf("unknown tool should report isError=true, got %+v", res)
	}
}

func TestMethodNotFound(t *testing.T) {
	d := newDispatcher()
	resp := d.Handle(req("bogus/method", "6", nil))
	if resp.Error == nil || resp.Error.Code != -32601 {
		t.Fatalf("want -32601, got %+v", resp.Error)
	}
}
