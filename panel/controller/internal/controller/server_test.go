package controller

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func testServer(t *testing.T) http.Handler {
	return testServerWithWebDir(t, t.TempDir())
}

func testServerWithWebDir(t *testing.T, webDir string) http.Handler {
	store, err := OpenStore(filepath.Join(t.TempDir(), "store.json"))
	if err != nil {
		t.Fatal(err)
	}
	return NewServer(store, "agent-token", "operator-token", true, webDir)
}

func testOpenServer(t *testing.T) http.Handler {
	store, err := OpenStore(filepath.Join(t.TempDir(), "store.json"))
	if err != nil {
		t.Fatal(err)
	}
	return NewServer(store, "agent-token", "operator-token", false, t.TempDir())
}

func testWebServer(t *testing.T) http.Handler {
	webDir := t.TempDir()
	if err := os.WriteFile(filepath.Join(webDir, "index.html"), []byte("<!doctype html><title>Edge Tunnel Panel</title>"), 0644); err != nil {
		t.Fatal(err)
	}
	assetsDir := filepath.Join(webDir, "assets")
	if err := os.MkdirAll(assetsDir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(assetsDir, "app.js"), []byte(`console.log("ok")`), 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(assetsDir, "app.css"), []byte("body{color:#fff}"), 0644); err != nil {
		t.Fatal(err)
	}
	return testServerWithWebDir(t, webDir)
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

func deleteReq(t *testing.T, h http.Handler, path, token string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodDelete, path, nil)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, req)
	return rr
}

func postFromRemote(t *testing.T, h http.Handler, path, token, remoteAddr string, body any) *httptest.ResponseRecorder {
	raw, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPost, path, bytes.NewReader(raw))
	req.RemoteAddr = remoteAddr
	req.Header.Set("Content-Type", "application/json")
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
	if rr := post(t, h, "/api/v1/agent/register", "agent-token", map[string]any{"id": "node-stable", "node_name": "edge-node", "role": "relay"}); rr.Code != 200 {
		t.Fatalf("register failed: %d %s", rr.Code, rr.Body.String())
	}
	if rr := post(t, h, "/api/v1/agent/report", "agent-token", map[string]any{"id": "node-stable", "node_name": "edge-node", "role": "relay", "capabilities": map[string]any{"supports_agent_status": true}}); rr.Code != 200 {
		t.Fatalf("report failed: %d %s", rr.Code, rr.Body.String())
	}
	if rr := post(t, h, "/api/v1/agent/register", "agent-token", map[string]any{"id": "node-stable", "node_name": "edge-node", "role": "relay"}); rr.Code != 200 {
		t.Fatalf("second register failed: %d %s", rr.Code, rr.Body.String())
	}
	rr := get(t, h, "/api/v1/nodes", "operator-token")
	if rr.Code != 200 || !strings.Contains(rr.Body.String(), "edge-node") {
		t.Fatalf("list nodes failed: %d %s", rr.Code, rr.Body.String())
	}
	var resp APIResponse
	if err := json.Unmarshal(rr.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	raw, _ := json.Marshal(resp.Data)
	var nodes []Node
	if err := json.Unmarshal(raw, &nodes); err != nil {
		t.Fatal(err)
	}
	if len(nodes) != 1 || nodes[0].ID != "node-stable" {
		t.Fatalf("expected one stable node, got %+v", nodes)
	}
}

func TestReportObservedPublicIPFromRemoteAddr(t *testing.T) {
	h := testServer(t)
	rr := postFromRemote(t, h, "/api/v1/agent/report", "agent-token", "216.23.88.67:12345", map[string]any{"id": "node-ip", "node_name": "edge-node", "role": "backend"})
	if rr.Code != 200 {
		t.Fatalf("report failed: %d %s", rr.Code, rr.Body.String())
	}
	list := get(t, h, "/api/v1/nodes", "operator-token")
	if !strings.Contains(list.Body.String(), `"public_ip":"216.23.88.67"`) || strings.Contains(list.Body.String(), `"private_ip":"216.23.88.67"`) {
		t.Fatalf("bad public/private IP fields: %s", list.Body.String())
	}
}

func TestReportDoesNotOverwritePrivateIPWithPublicIP(t *testing.T) {
	h := testServer(t)
	rr := postFromRemote(t, h, "/api/v1/agent/report", "agent-token", "216.23.101.103:23456", map[string]any{"id": "node-private", "node_name": "edge-node", "role": "backend", "private_ip": "10.0.0.5"})
	if rr.Code != 200 {
		t.Fatalf("report failed: %d %s", rr.Code, rr.Body.String())
	}
	list := get(t, h, "/api/v1/nodes", "operator-token")
	if !strings.Contains(list.Body.String(), `"public_ip":"216.23.101.103"`) || !strings.Contains(list.Body.String(), `"private_ip":"10.0.0.5"`) {
		t.Fatalf("bad public/private IP fields: %s", list.Body.String())
	}
}

func TestReportStoresEasyTierNetworkHealth(t *testing.T) {
	h := testServer(t)
	rr := postFromRemote(t, h, "/api/v1/agent/report", "agent-token", "216.23.101.103:23456", map[string]any{"id": "node-net", "node_name": "edge-node", "role": "backend", "easytier_status": "active", "easytier_peer_count": 1, "easytier_has_remote_peer": true, "easytier_best_latency_ms": 146.8, "easytier_packet_loss": "0.0%", "easytier_tunnels": []any{"udp", "tcp"}, "easytier_route_type": "DIRECT", "easytier_network_ok": true})
	if rr.Code != 200 {
		t.Fatalf("report failed: %d %s", rr.Code, rr.Body.String())
	}
	body := get(t, h, "/api/v1/nodes", "operator-token").Body.String()
	for _, want := range []string{`"easytier_network_ok":true`, `"easytier_best_latency_ms":146.8`, `"easytier_packet_loss":"0.0%"`, `"easytier_route_type":"DIRECT"`} {
		if !strings.Contains(body, want) {
			t.Fatalf("missing %s in node response: %s", want, body)
		}
	}
}

func TestNodeStatusOnlineByLastSeen(t *testing.T) {
	store := &Store{data: StoreFile{Nodes: []Node{{ID: "node-online", LastSeenAt: time.Now().UTC().Add(-30 * time.Second)}}}}
	nodes := store.listNodes()
	if len(nodes) != 1 || nodes[0].Status != "online" || !strings.Contains(nodes[0].StatusReason, "recent") {
		t.Fatalf("expected online node, got %+v", nodes)
	}
}

func TestNodeStatusStaleByLastSeen(t *testing.T) {
	store := &Store{data: StoreFile{Nodes: []Node{{ID: "node-stale", LastSeenAt: time.Now().UTC().Add(-2 * time.Minute)}}}}
	nodes := store.listNodes()
	if len(nodes) != 1 || nodes[0].Status != "stale" || !strings.Contains(nodes[0].StatusReason, "90") {
		t.Fatalf("expected stale node, got %+v", nodes)
	}
}

func TestNodeStatusOfflineByLastSeen(t *testing.T) {
	store := &Store{data: StoreFile{Nodes: []Node{{ID: "node-offline", LastSeenAt: time.Now().UTC().Add(-6 * time.Minute)}}}}
	nodes := store.listNodes()
	if len(nodes) != 1 || nodes[0].Status != "offline" || !strings.Contains(nodes[0].StatusReason, "5") {
		t.Fatalf("expected offline node, got %+v", nodes)
	}
}

func TestNodeStatusMissingLastSeenOffline(t *testing.T) {
	store := &Store{data: StoreFile{Nodes: []Node{{ID: "node-missing"}}}}
	nodes := store.listNodes()
	if len(nodes) != 1 || nodes[0].Status != "offline" {
		t.Fatalf("expected missing last_seen to be offline, got %+v", nodes)
	}
}

func TestAgentUnregisterMarksOffline(t *testing.T) {
	h := testServer(t)
	_ = post(t, h, "/api/v1/agent/register", "agent-token", map[string]any{"id": "node-off", "node_name": "edge-node"})
	rr := post(t, h, "/api/v1/agent/unregister", "agent-token", map[string]any{"node_id": "node-off", "reason": "agent purge"})
	if rr.Code != 200 {
		t.Fatalf("unregister failed: %d %s", rr.Code, rr.Body.String())
	}
	list := get(t, h, "/api/v1/nodes", "operator-token")
	if !strings.Contains(list.Body.String(), `"status":"offline"`) || !strings.Contains(list.Body.String(), "agent purge") {
		t.Fatalf("node should be offline after unregister: %s", list.Body.String())
	}
}

func TestUnregisterMissingNodeDoesNotPanic(t *testing.T) {
	rr := post(t, testServer(t), "/api/v1/agent/unregister", "agent-token", map[string]any{"node_id": "missing", "reason": "agent purge"})
	if rr.Code != 200 || !strings.Contains(rr.Body.String(), `"unregistered":false`) {
		t.Fatalf("missing unregister should be ok: %d %s", rr.Code, rr.Body.String())
	}
}

func TestDeleteNode(t *testing.T) {
	h := testServer(t)
	if rr := post(t, h, "/api/v1/agent/register", "agent-token", map[string]any{"id": "node-delete", "node_name": "edge-node"}); rr.Code != 200 {
		t.Fatalf("register failed: %d %s", rr.Code, rr.Body.String())
	}
	if rr := deleteReq(t, h, "/api/v1/nodes/node-delete", "operator-token"); rr.Code != 200 {
		t.Fatalf("delete failed: %d %s", rr.Code, rr.Body.String())
	}
	if rr := get(t, h, "/api/v1/nodes/node-delete", "operator-token"); rr.Code != 404 {
		t.Fatalf("expected deleted node 404, got %d %s", rr.Code, rr.Body.String())
	}
}

func TestDeleteMissingNodeReturns404(t *testing.T) {
	if rr := deleteReq(t, testServer(t), "/api/v1/nodes/missing", "operator-token"); rr.Code != 404 {
		t.Fatalf("expected 404, got %d %s", rr.Code, rr.Body.String())
	}
}

func TestDeleteNodeDoesNotDeleteTasks(t *testing.T) {
	h := testServer(t)
	_ = post(t, h, "/api/v1/agent/register", "agent-token", map[string]any{"id": "node-with-task", "node_name": "edge-node"})
	created := post(t, h, "/api/v1/tasks", "operator-token", map[string]any{"node_id": "node-with-task", "action": "collect_agent_status", "payload": map[string]any{}})
	if created.Code != 200 {
		t.Fatalf("task create failed: %d %s", created.Code, created.Body.String())
	}
	_ = deleteReq(t, h, "/api/v1/nodes/node-with-task", "operator-token")
	tasks := get(t, h, "/api/v1/tasks?node_id=node-with-task", "operator-token")
	if tasks.Code != 200 || !strings.Contains(tasks.Body.String(), "collect_agent_status") {
		t.Fatalf("task history should remain: %d %s", tasks.Code, tasks.Body.String())
	}
}

func TestDeleteNodeReappearsOnReport(t *testing.T) {
	h := testServer(t)
	_ = post(t, h, "/api/v1/agent/register", "agent-token", map[string]any{"id": "node-reappear", "node_name": "edge-node"})
	_ = deleteReq(t, h, "/api/v1/nodes/node-reappear", "operator-token")
	rr := post(t, h, "/api/v1/agent/report", "agent-token", map[string]any{"id": "node-reappear", "node_name": "edge-node", "role": "backend"})
	if rr.Code != 200 {
		t.Fatalf("report after delete failed: %d %s", rr.Code, rr.Body.String())
	}
	list := get(t, h, "/api/v1/nodes", "operator-token")
	if !strings.Contains(list.Body.String(), "node-reappear") {
		t.Fatalf("live agent should reappear after report: %s", list.Body.String())
	}
}

func TestBootstrapAgentInstallCommand(t *testing.T) {
	h := testServer(t)
	rr := post(t, h, "/api/v1/bootstrap/agent-install-command", "operator-token", map[string]any{"controller_url": "http://example:18080", "node_name": "edge-node", "role": "entry", "version": "v0.2.2-test"})
	body := rr.Body.String()
	if rr.Code != 200 ||
		!strings.Contains(body, "edge-tunnel-panel") ||
		!strings.Contains(body, "install-agent.sh") ||
		!strings.Contains(body, "--version v0.2.2-test") ||
		!strings.Contains(body, "--controller-url http://example:18080") ||
		!strings.Contains(body, "--node-name edge-node") ||
		!strings.Contains(body, "--role entry") ||
		!strings.Contains(body, `"root_command"`) ||
		!strings.Contains(body, `"sudo_command"`) ||
		!strings.Contains(body, `| bash -s --`) ||
		!strings.Contains(body, `| sudo bash -s --`) ||
		!strings.Contains(body, `"can_copy":true`) {
		t.Fatalf("bad command: %d %s", rr.Code, body)
	}
}

func TestBootstrapAgentInstallCommandsContainToken(t *testing.T) {
	h := testServer(t)
	rr := post(t, h, "/api/v1/bootstrap/agent-install-command", "operator-token", map[string]any{"controller_url": "http://example:18080"})
	body := rr.Body.String()
	if rr.Code != 200 || !strings.Contains(body, "root_command") || !strings.Contains(body, "sudo_command") || !strings.Contains(body, "agent-token") || !strings.Contains(body, `"can_copy":true`) {
		t.Fatalf("full command missing token: %d %s", rr.Code, body)
	}
}

func TestOpenModeAllowsOperatorAPIWithoutToken(t *testing.T) {
	rr := get(t, testOpenServer(t), "/api/v1/nodes", "")
	if rr.Code != 200 {
		t.Fatalf("open mode should allow operator API without token: %d %s", rr.Code, rr.Body.String())
	}
}

func TestStrictModeRequiresOperatorToken(t *testing.T) {
	rr := get(t, testServer(t), "/api/v1/nodes", "")
	if rr.Code != 401 {
		t.Fatalf("strict mode should require token: %d %s", rr.Code, rr.Body.String())
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

func TestListTasksByNodeID(t *testing.T) {
	h := testServer(t)
	_ = post(t, h, "/api/v1/tasks", "operator-token", map[string]any{"node_id": "node-a", "action": "collect_agent_status", "payload": map[string]any{}})
	_ = post(t, h, "/api/v1/tasks", "operator-token", map[string]any{"node_id": "node-b", "action": "collect_agent_status", "payload": map[string]any{}})
	rr := get(t, h, "/api/v1/tasks?node_id=node-a", "operator-token")
	body := rr.Body.String()
	if rr.Code != 200 || !strings.Contains(body, "node-a") || strings.Contains(body, "node-b") {
		t.Fatalf("bad filtered tasks: %d %s", rr.Code, body)
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

func TestRunNodePreflightTaskAllowed(t *testing.T) {
	h := testServer(t)
	rr := post(t, h, "/api/v1/tasks", "operator-token", map[string]any{"node_id": "node-a", "action": "run_node_preflight", "payload": map[string]any{}})
	if rr.Code != 200 || !strings.Contains(rr.Body.String(), "run_node_preflight") {
		t.Fatalf("expected preflight task allowed: %d %s", rr.Code, rr.Body.String())
	}
}

func TestVerifyNetworkConnectivityTaskAllowed(t *testing.T) {
	h := testServer(t)
	rr := post(t, h, "/api/v1/tasks", "operator-token", map[string]any{"node_id": "node-a", "action": "verify_network_connectivity", "payload": map[string]any{}})
	if rr.Code != 200 || !strings.Contains(rr.Body.String(), "verify_network_connectivity") {
		t.Fatalf("expected network verification task allowed: %d %s", rr.Code, rr.Body.String())
	}
}

func TestInstallEasyTierTaskAllowed(t *testing.T) {
	h := testServer(t)
	rr := post(t, h, "/api/v1/tasks", "operator-token", map[string]any{"node_id": "node-a", "action": "install_or_update_easytier", "payload": map[string]any{}})
	if rr.Code != 200 || !strings.Contains(rr.Body.String(), "install_or_update_easytier") {
		t.Fatalf("expected install task allowed: %d %s", rr.Code, rr.Body.String())
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

func TestNetworkProfileCRUD(t *testing.T) {
	h := testServer(t)
	create := post(t, h, "/api/v1/network-profiles", "operator-token", map[string]any{"name": "prod", "network_name": "edge-prod", "listeners": []any{"tcp://0.0.0.0:11010"}, "peers": []any{"tcp://1.2.3.4:11010"}})
	if create.Code != 200 {
		t.Fatalf("create failed: %d %s", create.Code, create.Body.String())
	}
	var resp APIResponse
	if err := json.Unmarshal(create.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	raw, _ := json.Marshal(resp.Data)
	var profile NetworkProfile
	if err := json.Unmarshal(raw, &profile); err != nil {
		t.Fatal(err)
	}
	if profile.ID == "" || profile.NetworkSecret == "" || profile.CIDR != "10.144.0.0/16" || profile.ProtocolPreference != "auto" || len(profile.Listeners) != 1 || len(profile.Peers) != 1 {
		t.Fatalf("defaults not applied: %+v", profile)
	}
	update := postMethod(t, h, http.MethodPut, "/api/v1/network-profiles/"+profile.ID, "operator-token", map[string]any{"name": "prod-updated", "cidr": "10.200.0.0/16", "peers": []any{"udp://1.2.3.4:11010"}})
	if update.Code != 200 || !strings.Contains(update.Body.String(), "prod-updated") || !strings.Contains(update.Body.String(), "udp://1.2.3.4:11010") {
		t.Fatalf("update failed: %d %s", update.Code, update.Body.String())
	}
	list := get(t, h, "/api/v1/network-profiles", "operator-token")
	if list.Code != 200 || !strings.Contains(list.Body.String(), "prod-updated") {
		t.Fatalf("list failed: %d %s", list.Code, list.Body.String())
	}
	del := postMethod(t, h, http.MethodDelete, "/api/v1/network-profiles/"+profile.ID, "operator-token", nil)
	if del.Code != 200 {
		t.Fatalf("delete failed: %d %s", del.Code, del.Body.String())
	}
}

func TestNetworkProfileCreateRequiresName(t *testing.T) {
	rr := post(t, testServer(t), "/api/v1/network-profiles", "operator-token", map[string]any{"network_name": "edge-prod"})
	if rr.Code != 400 {
		t.Fatalf("expected name validation: %d %s", rr.Code, rr.Body.String())
	}
}

func TestNetworkProfileApplyCreatesTask(t *testing.T) {
	h := testServer(t)
	if rr := post(t, h, "/api/v1/agent/register", "agent-token", map[string]any{"id": "node-a", "node_name": "edge-a", "role": "backend"}); rr.Code != 200 {
		t.Fatalf("register failed: %d %s", rr.Code, rr.Body.String())
	}
	create := post(t, h, "/api/v1/network-profiles", "operator-token", map[string]any{"name": "prod", "network_name": "edge-prod", "listeners": []any{"tcp://0.0.0.0:11010"}, "peers": []any{"tcp://1.2.3.4:11010"}})
	var resp APIResponse
	_ = json.Unmarshal(create.Body.Bytes(), &resp)
	raw, _ := json.Marshal(resp.Data)
	var profile NetworkProfile
	_ = json.Unmarshal(raw, &profile)
	apply := post(t, h, "/api/v1/network-profiles/"+profile.ID+"/apply", "operator-token", map[string]any{"node_id": "node-a"})
	if apply.Code != 202 || !strings.Contains(apply.Body.String(), "apply_network_profile") || !strings.Contains(apply.Body.String(), "network_profile") || !strings.Contains(apply.Body.String(), "node-a") || !strings.Contains(apply.Body.String(), "tcp://1.2.3.4:11010") {
		t.Fatalf("apply did not create task: %d %s", apply.Code, apply.Body.String())
	}
}

func TestApplyBackendWithoutPeersRejected(t *testing.T) {
	h := testServer(t)
	_ = post(t, h, "/api/v1/agent/register", "agent-token", map[string]any{"id": "node-backend", "node_name": "backend", "role": "backend"})
	create := post(t, h, "/api/v1/network-profiles", "operator-token", map[string]any{"name": "prod", "network_name": "edge-prod", "peers": []any{}})
	var resp APIResponse
	_ = json.Unmarshal(create.Body.Bytes(), &resp)
	raw, _ := json.Marshal(resp.Data)
	var profile NetworkProfile
	_ = json.Unmarshal(raw, &profile)
	apply := post(t, h, "/api/v1/network-profiles/"+profile.ID+"/apply", "operator-token", map[string]any{"node_id": "node-backend"})
	if apply.Code != 400 || !strings.Contains(apply.Body.String(), "backend node requires") {
		t.Fatalf("backend without peers should be rejected: %d %s", apply.Code, apply.Body.String())
	}
}

func TestApplyPayloadPreservesPeers(t *testing.T) {
	h := testServer(t)
	_ = post(t, h, "/api/v1/agent/register", "agent-token", map[string]any{"id": "node-entry", "node_name": "entry", "role": "entry"})
	create := post(t, h, "/api/v1/network-profiles", "operator-token", map[string]any{"name": "prod", "network_name": "edge-prod", "listeners": []any{"tcp://0.0.0.0:11010"}, "peers": []any{"tcp://1.2.3.4:11010", "udp://1.2.3.4:11010"}})
	var resp APIResponse
	_ = json.Unmarshal(create.Body.Bytes(), &resp)
	raw, _ := json.Marshal(resp.Data)
	var profile NetworkProfile
	_ = json.Unmarshal(raw, &profile)
	apply := post(t, h, "/api/v1/network-profiles/"+profile.ID+"/apply", "operator-token", map[string]any{"node_id": "node-entry"})
	body := apply.Body.String()
	if apply.Code != 202 || !strings.Contains(body, "tcp://1.2.3.4:11010") || !strings.Contains(body, "udp://1.2.3.4:11010") {
		t.Fatalf("apply payload should preserve peers: %d %s", apply.Code, body)
	}
}

func TestQuickApplyCreatesEntryAndBackendTasks(t *testing.T) {
	h := testServer(t)
	_ = postFromRemote(t, h, "/api/v1/agent/report", "agent-token", "203.0.113.10:12345", map[string]any{"id": "entry-a", "node_name": "entry", "role": "entry"})
	_ = post(t, h, "/api/v1/agent/report", "agent-token", map[string]any{"id": "backend-a", "node_name": "backend", "role": "backend"})
	rr := post(t, h, "/api/v1/network-profiles/quick-apply", "operator-token", map[string]any{"name": "edge-net", "entry_node_id": "entry-a", "backend_node_id": "backend-a", "port": 11010, "protocols": []any{"tcp", "udp"}})
	body := rr.Body.String()
	if rr.Code != 202 || !strings.Contains(body, `"entry_task"`) || !strings.Contains(body, `"backend_task"`) || !strings.Contains(body, "tcp://203.0.113.10:11010") {
		t.Fatalf("quick apply failed: %d %s", rr.Code, body)
	}
}

func TestQuickApplyRejectsSameNode(t *testing.T) {
	h := testServer(t)
	_ = postFromRemote(t, h, "/api/v1/agent/report", "agent-token", "203.0.113.10:12345", map[string]any{"id": "node-a", "node_name": "entry", "role": "entry"})
	rr := post(t, h, "/api/v1/network-profiles/quick-apply", "operator-token", map[string]any{"entry_node_id": "node-a", "backend_node_id": "node-a"})
	if rr.Code != 400 || !strings.Contains(rr.Body.String(), "different") {
		t.Fatalf("same node should be rejected: %d %s", rr.Code, rr.Body.String())
	}
}

func TestQuickApplyRejectsMissingEntryPublicIP(t *testing.T) {
	h := testServer(t)
	_ = postFromRemote(t, h, "/api/v1/agent/report", "agent-token", "10.0.0.10:12345", map[string]any{"id": "entry-no-ip", "node_name": "entry", "role": "entry"})
	_ = post(t, h, "/api/v1/agent/report", "agent-token", map[string]any{"id": "backend-a", "node_name": "backend", "role": "backend"})
	rr := post(t, h, "/api/v1/network-profiles/quick-apply", "operator-token", map[string]any{"entry_node_id": "entry-no-ip", "backend_node_id": "backend-a"})
	if rr.Code != 400 || !strings.Contains(rr.Body.String(), "public_ip") {
		t.Fatalf("missing public ip should be rejected: %d %s", rr.Code, rr.Body.String())
	}
}

func TestQuickApplyPayloadHasBackendPeers(t *testing.T) {
	h := testServer(t)
	_ = postFromRemote(t, h, "/api/v1/agent/report", "agent-token", "203.0.113.11:12345", map[string]any{"id": "entry-b", "node_name": "entry", "role": "entry"})
	_ = post(t, h, "/api/v1/agent/report", "agent-token", map[string]any{"id": "backend-b", "node_name": "backend", "role": "backend"})
	rr := post(t, h, "/api/v1/network-profiles/quick-apply", "operator-token", map[string]any{"entry_node_id": "entry-b", "backend_node_id": "backend-b", "protocols": []any{"tcp", "udp"}})
	body := rr.Body.String()
	if rr.Code != 202 || !strings.Contains(body, `"target_mode":"backend"`) || !strings.Contains(body, "tcp://203.0.113.11:11010") || !strings.Contains(body, "udp://203.0.113.11:11010") {
		t.Fatalf("backend peers missing: %d %s", rr.Code, body)
	}
}

func TestQuickApplyPayloadHasEntryPeersEmpty(t *testing.T) {
	h := testServer(t)
	_ = postFromRemote(t, h, "/api/v1/agent/report", "agent-token", "203.0.113.12:12345", map[string]any{"id": "entry-c", "node_name": "entry", "role": "entry"})
	_ = post(t, h, "/api/v1/agent/report", "agent-token", map[string]any{"id": "backend-c", "node_name": "backend", "role": "backend"})
	rr := post(t, h, "/api/v1/network-profiles/quick-apply", "operator-token", map[string]any{"entry_node_id": "entry-c", "backend_node_id": "backend-c"})
	body := rr.Body.String()
	if rr.Code != 202 || !strings.Contains(body, `"target_mode":"entry"`) || !strings.Contains(body, `"entry_peers":[]`) {
		t.Fatalf("entry peers should be empty: %d %s", rr.Code, body)
	}
}

func postMethod(t *testing.T, h http.Handler, method, path, token string, body any) *httptest.ResponseRecorder {
	t.Helper()
	var reader *bytes.Reader
	if body == nil {
		reader = bytes.NewReader(nil)
	} else {
		raw, _ := json.Marshal(body)
		reader = bytes.NewReader(raw)
	}
	req := httptest.NewRequest(method, path, reader)
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, req)
	return rr
}

func TestTokenRedaction(t *testing.T) {
	masked := redactToken("abcdefghijklmnop")
	if strings.Contains(masked, "abcdefgh") || !strings.HasSuffix(masked, "mnop") {
		t.Fatalf("bad redaction: %s", masked)
	}
}

func TestServeWebIndex(t *testing.T) {
	rr := get(t, testWebServer(t), "/", "")
	if rr.Code != 200 || !strings.Contains(rr.Body.String(), "Edge Tunnel Panel") {
		t.Fatalf("bad index response: %d %s", rr.Code, rr.Body.String())
	}
}

func TestServeWebAssetJS(t *testing.T) {
	rr := get(t, testWebServer(t), "/assets/app.js", "")
	body := rr.Body.String()
	contentType := rr.Header().Get("Content-Type")
	if rr.Code != 200 || !strings.Contains(body, `console.log("ok")`) {
		t.Fatalf("bad js response: %d %s", rr.Code, body)
	}
	if strings.Contains(body, "<!doctype html>") || strings.HasPrefix(contentType, "text/html") {
		t.Fatalf("js returned html: content-type=%s body=%s", contentType, body)
	}
}

func TestServeWebAssetCSS(t *testing.T) {
	rr := get(t, testWebServer(t), "/assets/app.css", "")
	body := rr.Body.String()
	if rr.Code != 200 || !strings.Contains(body, "body{color:#fff}") {
		t.Fatalf("bad css response: %d %s", rr.Code, body)
	}
	if strings.Contains(body, "<!doctype html>") {
		t.Fatalf("css returned html: %s", body)
	}
}

func TestMissingStaticAssetReturns404(t *testing.T) {
	rr := get(t, testWebServer(t), "/assets/missing.js", "")
	if rr.Code != 404 || strings.Contains(rr.Body.String(), "<!doctype html>") {
		t.Fatalf("missing asset should be 404, got %d %s", rr.Code, rr.Body.String())
	}
}

func TestSPAFallback(t *testing.T) {
	rr := get(t, testWebServer(t), "/nodes", "")
	if rr.Code != 200 || !strings.Contains(rr.Body.String(), "Edge Tunnel Panel") {
		t.Fatalf("spa fallback failed: %d %s", rr.Code, rr.Body.String())
	}
}

func TestAPIRouteNotCapturedByWeb(t *testing.T) {
	rr := get(t, testWebServer(t), "/api/v1/health", "")
	if rr.Code != 200 || strings.Contains(rr.Body.String(), "<!doctype html>") || !strings.Contains(rr.Header().Get("Content-Type"), "application/json") {
		t.Fatalf("api route captured by web: %d %s %s", rr.Code, rr.Header().Get("Content-Type"), rr.Body.String())
	}
}

func TestPathTraversalBlocked(t *testing.T) {
	webDir := t.TempDir()
	parentSecret := filepath.Join(filepath.Dir(webDir), "secret")
	if err := os.WriteFile(filepath.Join(webDir, "index.html"), []byte("<!doctype html><title>Edge Tunnel Panel</title>"), 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(parentSecret, []byte("secret"), 0644); err != nil {
		t.Fatal(err)
	}
	req := httptest.NewRequest(http.MethodGet, "/../secret", nil)
	req.URL.RawPath = "/../secret"
	rr := httptest.NewRecorder()
	testServerWithWebDir(t, webDir).ServeHTTP(rr, req)
	if rr.Code == 200 && strings.Contains(rr.Body.String(), "secret") {
		t.Fatalf("path traversal leaked file: %d %s", rr.Code, rr.Body.String())
	}
	if rr.Code != 400 && rr.Code != 404 {
		t.Fatalf("expected traversal to be blocked, got %d %s", rr.Code, rr.Body.String())
	}
}
