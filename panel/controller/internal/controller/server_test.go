package controller

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
)

func testServer(t *testing.T) http.Handler {
	store, err := OpenStore(filepath.Join(t.TempDir(), "store.json"))
	if err != nil {
		t.Fatal(err)
	}
	return NewServer(store, "agent-token", "operator-token", true, t.TempDir())
}

func post(t *testing.T, h http.Handler, path, token string, body any) *httptest.ResponseRecorder {
	raw, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPost, path, bytes.NewReader(raw))
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, req)
	return rr
}

func get(t *testing.T, h http.Handler, path, token string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodGet, path, nil)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, req)
	return rr
}

func TestHealthName(t *testing.T) {
	rr := get(t, testServer(t), "/api/v1/health", "")
	if rr.Code != 200 || !strings.Contains(rr.Body.String(), "edge-tunnel-controller") {
		t.Fatalf("bad health: %d %s", rr.Code, rr.Body.String())
	}
}

func TestLogin(t *testing.T) {
	h := testServer(t)
	if rr := post(t, h, "/api/v1/login", "", map[string]any{"token": "wrong"}); rr.Code != 401 {
		t.Fatalf("expected 401 got %d", rr.Code)
	}
	if rr := post(t, h, "/api/v1/login", "", map[string]any{"token": "operator-token"}); rr.Code != 200 {
		t.Fatalf("expected 200 got %d %s", rr.Code, rr.Body.String())
	}
}

func TestAgentRegisterAndReport(t *testing.T) {
	h := testServer(t)
	if rr := post(t, h, "/api/v1/agent/register", "agent-token", map[string]any{"node_name": "edge-node", "role": "relay"}); rr.Code != 200 {
		t.Fatalf("register failed: %d %s", rr.Code, rr.Body.String())
	}
	if rr := post(t, h, "/api/v1/agent/report", "agent-token", map[string]any{"node_name": "edge-node", "role": "relay", "capabilities": map[string]any{"supports_agent_status": true}}); rr.Code != 200 {
		t.Fatalf("report failed: %d %s", rr.Code, rr.Body.String())
	}
	rr := get(t, h, "/api/v1/nodes", "operator-token")
	if rr.Code != 200 || !strings.Contains(rr.Body.String(), "edge-node") {
		t.Fatalf("list nodes failed: %d %s", rr.Code, rr.Body.String())
	}
}

func TestBootstrapAgentInstallCommand(t *testing.T) {
	h := testServer(t)
	rr := post(t, h, "/api/v1/bootstrap/agent-install-command", "operator-token", map[string]any{"controller_url": "http://example:18080", "node_name": "edge-node", "role": "entry"})
	body := rr.Body.String()
	if rr.Code != 200 || !strings.Contains(body, "edge-tunnel-panel") || !strings.Contains(body, "install-agent.sh") || !strings.Contains(body, "edge-node") {
		t.Fatalf("bad command: %d %s", rr.Code, body)
	}
}

func TestTaskCreateListAndResult(t *testing.T) {
	h := testServer(t)
	create := post(t, h, "/api/v1/tasks", "operator-token", map[string]any{"node_id": "node-a", "action": "collect_agent_status"})
	if create.Code != 200 {
		t.Fatalf("task create failed: %d %s", create.Code, create.Body.String())
	}
	list := get(t, h, "/api/v1/agent/tasks?node_id=node-a", "agent-token")
	if list.Code != 200 || !strings.Contains(list.Body.String(), "collect_agent_status") {
		t.Fatalf("agent task list failed: %d %s", list.Code, list.Body.String())
	}
	var resp APIResponse
	_ = json.Unmarshal(create.Body.Bytes(), &resp)
	data, _ := json.Marshal(resp.Data)
	var task Task
	_ = json.Unmarshal(data, &task)
	result := post(t, h, "/api/v1/agent/tasks/"+task.ID+"/result", "agent-token", map[string]any{"status": "succeeded", "result_stdout": "ok"})
	if result.Code != 200 || !strings.Contains(result.Body.String(), "succeeded") {
		t.Fatalf("task result failed: %d %s", result.Code, result.Body.String())
	}
}

func TestDangerousPayloadRejected(t *testing.T) {
	h := testServer(t)
	for _, key := range []string{"command", "cmd", "shell", "script", "raw_nft", "raw_iptables", "raw_ip_route"} {
		rr := post(t, h, "/api/v1/tasks", "operator-token", map[string]any{"node_id": "n1", "action": "apply_network_profile", key: "bad"})
		if rr.Code != 400 {
			t.Fatalf("expected rejection for %s: %d %s", key, rr.Code, rr.Body.String())
		}
	}
}

func TestRebootRequiresConfirm(t *testing.T) {
	h := testServer(t)
	denied := post(t, h, "/api/v1/tasks", "operator-token", map[string]any{"node_id": "n1", "action": "reboot_node"})
	if denied.Code != 400 {
		t.Fatalf("reboot without confirm should fail: %d %s", denied.Code, denied.Body.String())
	}
	allowed := post(t, h, "/api/v1/tasks", "operator-token", map[string]any{"node_id": "n1", "action": "reboot_node", "confirm": true})
	if allowed.Code != 200 {
		t.Fatalf("reboot with confirm should pass: %d %s", allowed.Code, allowed.Body.String())
	}
}

func TestApplyCreatesTasks(t *testing.T) {
	h := testServer(t)
	cases := []struct{ path, action string }{
		{"/api/v1/network-profiles/1/apply", "apply_network_profile"},
		{"/api/v1/entries/1/apply", "apply_entry_config"},
		{"/api/v1/forwards/1/apply", "apply_forward_config"},
		{"/api/v1/pbr-policies/1/apply", "apply_pbr_config"},
	}
	for _, tc := range cases {
		rr := post(t, h, tc.path, "operator-token", map[string]any{"node_id": "node-a"})
		if rr.Code != 202 || !strings.Contains(rr.Body.String(), tc.action) {
			t.Fatalf("apply failed for %s: %d %s", tc.path, rr.Code, rr.Body.String())
		}
	}
}

func TestTokenRedaction(t *testing.T) {
	masked := redactToken("abcdefghijklmnop")
	if strings.Contains(masked, "abcdefgh") || !strings.HasSuffix(masked, "mnop") {
		t.Fatalf("bad redaction: %s", masked)
	}
}
