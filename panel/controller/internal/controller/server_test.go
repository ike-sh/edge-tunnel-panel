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

func init() {
	_ = os.Setenv("EDGE_LEGACY_V1_API", "1")
}

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

func mustPostNode(t *testing.T, h http.Handler, id, name, publicIP, privateIP string) {
	t.Helper()
	body := map[string]any{"id": id, "node_name": name, "role": "node", "public_ip": publicIP, "private_ip": privateIP}
	rr := post(t, h, "/api/v1/agent/report", "agent-token", body)
	if rr.Code != 200 {
		t.Fatalf("post node failed: %d %s", rr.Code, rr.Body.String())
	}
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
	rr := postFromRemote(t, h, "/api/v1/agent/report", "agent-token", "216.23.101.103:23456", map[string]any{"id": "node-net", "node_name": "edge-node", "role": "backend", "easytier_ip": "10.144.0.23/16", "easytier_dhcp_enabled": true, "easytier_cidr": "10.144.0.0/16", "easytier_status": "active", "easytier_peer_count": 1, "easytier_has_remote_peer": true, "easytier_best_latency_ms": 146.8, "easytier_packet_loss": "0.0%", "easytier_tunnels": []any{"udp", "tcp"}, "easytier_route_type": "DIRECT", "easytier_network_ok": true})
	if rr.Code != 200 {
		t.Fatalf("report failed: %d %s", rr.Code, rr.Body.String())
	}
	body := get(t, h, "/api/v1/nodes", "operator-token").Body.String()
	for _, want := range []string{`"easytier_network_ok":true`, `"easytier_best_latency_ms":146.8`, `"easytier_packet_loss":"0.0%"`, `"easytier_route_type":"DIRECT"`, `"easytier_ip":"10.144.0.23/16"`, `"easytier_dhcp_enabled":true`} {
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
	rr := post(t, h, "/api/v1/bootstrap/agent-install-command", "operator-token", map[string]any{"controller_url": "http://example:18080", "node_name": "edge-node", "version": "v0.3.1"})
	body := rr.Body.String()
	if rr.Code != 200 ||
		!strings.Contains(body, "edge-tunnel-panel") ||
		!strings.Contains(body, "quick-install.sh") ||
		!strings.Contains(body, "--version v0.3.1") ||
		!strings.Contains(body, "--url http://example:18080") ||
		!strings.Contains(body, "--name edge-node") ||
		!strings.Contains(body, `"root_command"`) ||
		!strings.Contains(body, `"sudo_command"`) ||
		!strings.Contains(body, `| bash -s --`) ||
		!strings.Contains(body, `| sudo bash -s --`) ||
		!strings.Contains(body, `"can_copy":true`) {
		t.Fatalf("bad install cmd: %d %s", rr.Code, body)
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

func TestBootstrapAgentCommandWithMirrors(t *testing.T) {
	h := testServer(t)
	rr := post(t, h, "/api/v1/bootstrap/agent-install-command", "operator-token", map[string]any{"controller_url": "http://example:18080", "download_source": "mirror", "github_mirrors": "https://gh.llkk.cc/,https://gh.ddlc.top/"})
	body := rr.Body.String()
	if rr.Code != 200 || !strings.Contains(body, "--cn") || !strings.Contains(body, "gh.llkk.cc") || !strings.Contains(body, "mirror_root_commands") {
		t.Fatalf("mirror command missing: %d %s", rr.Code, body)
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
	for _, key := range []string{"command", "cmd", "shell", "script", "raw_" + "nft", "raw_" + "iptables", "raw_" + "ip_route"} {
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

func TestNetworkLinkQuickApplyCreatesLink(t *testing.T) {
	h := testServer(t)
	_ = postFromRemote(t, h, "/api/v1/agent/report", "agent-token", "203.0.113.20:12345", map[string]any{"id": "entry-link", "node_name": "entry", "role": "entry", "easytier_status": "active", "easytier_peer_count": 1, "easytier_network_ok": true, "easytier_best_latency_ms": 100.5, "easytier_packet_loss": "0.0%", "easytier_route_type": "DIRECT"})
	_ = post(t, h, "/api/v1/agent/report", "agent-token", map[string]any{"id": "backend-link", "node_name": "backend", "role": "backend", "easytier_status": "active", "easytier_peer_count": 1, "easytier_network_ok": true})
	rr := post(t, h, "/api/v1/network-links/quick-apply", "operator-token", map[string]any{"name": "edge-net", "entry_node_id": "entry-link", "backend_node_id": "backend-link", "port": 11010, "protocols": []any{"tcp", "udp"}})
	body := rr.Body.String()
	if rr.Code != 202 || !strings.Contains(body, `"link"`) || !strings.Contains(body, `"entry_task"`) || !strings.Contains(body, `"backend_task"`) {
		t.Fatalf("network link quick apply failed: %d %s", rr.Code, body)
	}
	list := get(t, h, "/api/v1/network-links", "operator-token")
	if list.Code != 200 || !strings.Contains(list.Body.String(), `"status":"active"`) || !strings.Contains(list.Body.String(), `"best_latency_ms":100.5`) {
		t.Fatalf("network links list missing status: %d %s", list.Code, list.Body.String())
	}
}

func TestNetworkLinkVerifyCreatesTasks(t *testing.T) {
	h := testServer(t)
	_ = postFromRemote(t, h, "/api/v1/agent/report", "agent-token", "203.0.113.21:12345", map[string]any{"id": "entry-verify", "node_name": "entry", "role": "entry"})
	_ = post(t, h, "/api/v1/agent/report", "agent-token", map[string]any{"id": "backend-verify", "node_name": "backend", "role": "backend"})
	created := post(t, h, "/api/v1/network-links/quick-apply", "operator-token", map[string]any{"entry_node_id": "entry-verify", "backend_node_id": "backend-verify"})
	var resp APIResponse
	_ = json.Unmarshal(created.Body.Bytes(), &resp)
	raw, _ := json.Marshal(resp.Data)
	var data struct {
		Link NetworkLink `json:"link"`
	}
	_ = json.Unmarshal(raw, &data)
	verify := post(t, h, "/api/v1/network-links/"+data.Link.ID+"/verify", "operator-token", map[string]any{})
	if verify.Code != 202 || !strings.Contains(verify.Body.String(), "verify_network_connectivity") {
		t.Fatalf("verify should create tasks: %d %s", verify.Code, verify.Body.String())
	}
}

func TestForwardCreateRequiresLandingHost(t *testing.T) {
	h, link := testConnectedNetworkLink(t)
	rr := post(t, h, "/api/v1/forwards", "operator-token", map[string]any{"network_link_id": link.ID, "name": "forward-18081", "protocol": "tcp", "public_listen_port": 18081, "landing_port": 8080})
	if rr.Code != 400 || !strings.Contains(rr.Body.String(), "landing_host") {
		t.Fatalf("landing host should be required: %d %s", rr.Code, rr.Body.String())
	}
}

func TestForwardCreateRejectsCIDRLandingHost(t *testing.T) {
	h, link := testConnectedNetworkLink(t)
	rr := post(t, h, "/api/v1/forwards", "operator-token", map[string]any{"network_link_id": link.ID, "name": "forward-18081", "protocol": "tcp", "public_listen_port": 18081, "landing_host": "10.0.0.5/24", "landing_port": 8080})
	if rr.Code != 400 || !strings.Contains(rr.Body.String(), "CIDR") {
		t.Fatalf("CIDR landing host should be rejected: %d %s", rr.Code, rr.Body.String())
	}
}

func TestForwardCreateRejectsIPv6LandingHost(t *testing.T) {
	h, link := testConnectedNetworkLink(t)
	rr := post(t, h, "/api/v1/forwards", "operator-token", map[string]any{"network_link_id": link.ID, "name": "forward-18081", "protocol": "tcp", "public_listen_port": 18081, "landing_host": "fd00::1", "landing_port": 8080})
	if rr.Code != 400 || !strings.Contains(rr.Body.String(), "IPv6") {
		t.Fatalf("IPv6 landing host should be rejected: %d %s", rr.Code, rr.Body.String())
	}
}

func TestForwardCreateEasyTierTransportUsesLandingNodeEasyTierIP(t *testing.T) {
	h, link := testConnectedNetworkLink(t)
	rr := post(t, h, "/api/v1/forwards", "operator-token", map[string]any{"network_link_id": link.ID, "name": "forward-18081", "protocol": "tcp", "public_listen_port": 18081, "landing_host": "1.2.3.4", "landing_port": 8080, "transport_mode": "easytier"})
	if rr.Code != 200 {
		t.Fatalf("forward create failed: %d %s", rr.Code, rr.Body.String())
	}
	var resp APIResponse
	_ = json.Unmarshal(rr.Body.Bytes(), &resp)
	raw, _ := json.Marshal(resp.Data)
	var forward Forward
	_ = json.Unmarshal(raw, &forward)
	if forward.EntryNodeID != "entry-link-forward" || forward.LandingNodeID != "backend-link-forward" || forward.BackendNodeID != "backend-link-forward" {
		t.Fatalf("forward did not inherit A/B nodes: %+v", forward)
	}
	if forward.TransportMode != "easytier" || forward.TunnelTargetHost != "10.144.0.2" || strings.Contains(forward.TunnelTargetHost, "/") {
		t.Fatalf("tunnel target should use B EasyTier IP without CIDR: %+v", forward)
	}
	if forward.LandingHostRaw != "1.2.3.4" || forward.LandingPort != 8080 || forward.PublicListenPort != 18081 {
		t.Fatalf("landing fields not saved: %+v", forward)
	}
}

func TestForwardCreatePublicTransportUsesLandingNodePublicIP(t *testing.T) {
	h := testServer(t)
	_ = postFromRemote(t, h, "/api/v1/agent/report", "agent-token", "203.0.113.60:12345", map[string]any{"id": "entry-public-forward", "node_name": "entry", "easytier_status": "active", "easytier_peer_count": 1, "easytier_network_ok": true})
	_ = postFromRemote(t, h, "/api/v1/agent/report", "agent-token", "198.51.100.77:23456", map[string]any{"id": "backend-public-forward", "node_name": "backend", "easytier_status": "active", "easytier_peer_count": 1, "easytier_network_ok": true, "easytier_ip": "10.144.0.7/16"})
	linkResp := post(t, h, "/api/v1/network-links/quick-apply", "operator-token", map[string]any{"name": "edge-net", "entry_node_id": "entry-public-forward", "backend_node_id": "backend-public-forward"})
	link := networkLinkFromResponse(t, linkResp)
	rr := post(t, h, "/api/v1/forwards", "operator-token", map[string]any{"network_link_id": link.ID, "name": "public-forward", "protocol": "udp", "public_listen_port": 18082, "landing_host": "backend.example.com", "landing_port": 5353, "transport_mode": "public"})
	if rr.Code != 200 || !strings.Contains(rr.Body.String(), `"tunnel_target_host":"198.51.100.77"`) || !strings.Contains(rr.Body.String(), `"landing_host_raw":"backend.example.com"`) {
		t.Fatalf("public transport should use B public IP: %d %s", rr.Code, rr.Body.String())
	}
}

func TestForwardCreateRejectsInactiveNetworkLink(t *testing.T) {
	h := testServer(t)
	_ = postFromRemote(t, h, "/api/v1/agent/report", "agent-token", "203.0.113.50:12345", map[string]any{"id": "entry-not-ready", "node_name": "entry", "easytier_status": "inactive"})
	_ = post(t, h, "/api/v1/agent/report", "agent-token", map[string]any{"id": "backend-not-ready", "node_name": "backend", "easytier_status": "inactive", "easytier_ip": "10.144.0.2/16"})
	linkResp := post(t, h, "/api/v1/network-links/quick-apply", "operator-token", map[string]any{"entry_node_id": "entry-not-ready", "backend_node_id": "backend-not-ready"})
	link := networkLinkFromResponse(t, linkResp)
	rr := post(t, h, "/api/v1/forwards", "operator-token", map[string]any{"network_link_id": link.ID, "name": "http", "protocol": "tcp", "public_listen_port": 18081, "landing_host": "1.2.3.4", "landing_port": 8080})
	if rr.Code != 400 || !strings.Contains(rr.Body.String(), "not connected") {
		t.Fatalf("not-ready link should be rejected: %d %s", rr.Code, rr.Body.String())
	}
}

func TestForwardCreateAndApplyCreatesTwoTasks(t *testing.T) {
	h, link := testConnectedNetworkLink(t)
	rr := post(t, h, "/api/v1/forwards/create-and-apply", "operator-token", map[string]any{"network_link_id": link.ID, "name": "forward-18081", "protocol": "both", "public_listen_port": 18081, "landing_host": "1.2.3.4", "landing_port": 8080})
	if rr.Code != 202 {
		t.Fatalf("create-and-apply failed: %d %s", rr.Code, rr.Body.String())
	}
	var resp APIResponse
	_ = json.Unmarshal(rr.Body.Bytes(), &resp)
	raw, _ := json.Marshal(resp.Data)
	var data struct {
		Forward     Forward `json:"forward"`
		EntryTask   Task    `json:"entry_task"`
		LandingTask Task    `json:"landing_task"`
	}
	_ = json.Unmarshal(raw, &data)
	if data.EntryTask.NodeID != "entry-link-forward" || data.EntryTask.Action != "apply_entry_forward_config" {
		t.Fatalf("entry task should target A node: %+v", data.EntryTask)
	}
	if data.LandingTask.NodeID != "backend-link-forward" || data.LandingTask.Action != "apply_landing_forward_config" {
		t.Fatalf("landing task should target B node: %+v", data.LandingTask)
	}
	if data.Forward.Status != "applying" || data.Forward.LastApplyEntryTaskID != data.EntryTask.ID || data.Forward.LastApplyLandingTaskID != data.LandingTask.ID {
		t.Fatalf("forward should track both tasks: %+v", data.Forward)
	}
}

func TestForwardEntryTaskPayload(t *testing.T) {
	h, link := testConnectedNetworkLink(t)
	rr := post(t, h, "/api/v1/forwards/create-and-apply", "operator-token", map[string]any{"network_link_id": link.ID, "name": "entry-payload", "protocol": "tcp", "public_listen_port": 18083, "landing_host": "1.2.3.4", "landing_port": 8080})
	var resp APIResponse
	_ = json.Unmarshal(rr.Body.Bytes(), &resp)
	raw, _ := json.Marshal(resp.Data)
	var data struct {
		EntryTask Task `json:"entry_task"`
	}
	_ = json.Unmarshal(raw, &data)
	if data.EntryTask.Payload["stage"] != "entry" || data.EntryTask.Payload["tunnel_target_host"] != "10.144.0.2" || intValue(data.EntryTask.Payload["public_listen_port"]) != 18083 {
		t.Fatalf("bad entry payload: %+v", data.EntryTask.Payload)
	}
}

func TestForwardLandingTaskPayload(t *testing.T) {
	h, link := testConnectedNetworkLink(t)
	rr := post(t, h, "/api/v1/forwards/create-and-apply", "operator-token", map[string]any{"network_link_id": link.ID, "name": "landing-payload", "protocol": "udp", "public_listen_port": 18084, "landing_host": "backend.example.com", "landing_port": 9090})
	var resp APIResponse
	_ = json.Unmarshal(rr.Body.Bytes(), &resp)
	raw, _ := json.Marshal(resp.Data)
	var data struct {
		LandingTask Task `json:"landing_task"`
	}
	_ = json.Unmarshal(raw, &data)
	if data.LandingTask.Payload["stage"] != "landing" || data.LandingTask.Payload["landing_host_raw"] != "backend.example.com" || intValue(data.LandingTask.Payload["landing_port"]) != 9090 {
		t.Fatalf("bad landing payload: %+v", data.LandingTask.Payload)
	}
}

func TestForwardStatusUpdatesFromTwoStageApplyResult(t *testing.T) {
	h, link := testConnectedNetworkLink(t)
	created := post(t, h, "/api/v1/forwards/create-and-apply", "operator-token", map[string]any{"network_link_id": link.ID, "name": "forward-18081", "protocol": "tcp", "public_listen_port": 18081, "landing_host": "1.2.3.4", "landing_port": 8080})
	var resp APIResponse
	_ = json.Unmarshal(created.Body.Bytes(), &resp)
	raw, _ := json.Marshal(resp.Data)
	var data struct {
		Forward     Forward `json:"forward"`
		EntryTask   Task    `json:"entry_task"`
		LandingTask Task    `json:"landing_task"`
	}
	_ = json.Unmarshal(raw, &data)
	_ = post(t, h, "/api/v1/agent/tasks/"+data.EntryTask.ID+"/result", "agent-token", map[string]any{"status": "succeeded", "result": "{}"})
	mid := get(t, h, "/api/v1/forwards/"+data.Forward.ID, "operator-token")
	if !strings.Contains(mid.Body.String(), `"status":"applying"`) || !strings.Contains(mid.Body.String(), `"entry_stage_status":"succeeded"`) {
		t.Fatalf("entry result should keep rule applying: %d %s", mid.Code, mid.Body.String())
	}
	_ = post(t, h, "/api/v1/agent/tasks/"+data.LandingTask.ID+"/result", "agent-token", map[string]any{"status": "succeeded", "result": "{}"})
	final := get(t, h, "/api/v1/forwards/"+data.Forward.ID, "operator-token")
	if !strings.Contains(final.Body.String(), `"status":"applied"`) || !strings.Contains(final.Body.String(), `"landing_stage_status":"succeeded"`) {
		t.Fatalf("two stage result did not update forward: %d %s", final.Code, final.Body.String())
	}
}

func TestForwardRejectsDangerousPayload(t *testing.T) {
	h, link := testConnectedNetworkLink(t)
	rr := post(t, h, "/api/v1/forwards", "operator-token", map[string]any{"network_link_id": link.ID, "name": "bad", "protocol": "tcp", "public_listen_port": 1, "landing_host": "1.2.3.4", "landing_port": 2, "raw_" + "nft": "bad"})
	if rr.Code != 400 {
		t.Fatalf("dangerous forward payload should fail: %d %s", rr.Code, rr.Body.String())
	}
}
func TestNetworkLinkStatusUpdatesFromVerifyResult(t *testing.T) {
	h := testServer(t)
	_ = postFromRemote(t, h, "/api/v1/agent/report", "agent-token", "203.0.113.34:12345", map[string]any{"id": "entry-link-status", "node_name": "entry"})
	_ = post(t, h, "/api/v1/agent/report", "agent-token", map[string]any{"id": "backend-link-status", "node_name": "backend"})
	linkResp := post(t, h, "/api/v1/network-links/quick-apply", "operator-token", map[string]any{"entry_node_id": "entry-link-status", "backend_node_id": "backend-link-status"})
	link := decodeLinkFromResponse(t, linkResp)
	verify := post(t, h, "/api/v1/network-links/"+link.ID+"/verify", "operator-token", map[string]any{})
	var verifyResp APIResponse
	_ = json.Unmarshal(verify.Body.Bytes(), &verifyResp)
	raw, _ := json.Marshal(verifyResp.Data)
	var data map[string]any
	_ = json.Unmarshal(raw, &data)
	taskRaw, _ := json.Marshal(data["backend_task"])
	var task Task
	_ = json.Unmarshal(taskRaw, &task)
	_ = post(t, h, "/api/v1/agent/tasks/"+task.ID+"/result", "agent-token", map[string]any{"status": "succeeded", "result": `{"network_ok":true,"peer_count":1,"best_latency_ms":88.5,"packet_loss":"0.0%","tunnels":["udp","tcp"],"route_type":"DIRECT"}`})
	updated := get(t, h, "/api/v1/network-links/"+link.ID, "operator-token")
	if updated.Code != 200 || !strings.Contains(updated.Body.String(), `"status":"active"`) || !strings.Contains(updated.Body.String(), `"best_latency_ms":88.5`) {
		t.Fatalf("verify result did not update link: %d %s", updated.Code, updated.Body.String())
	}
}

func testConnectedNetworkLink(t *testing.T) (http.Handler, NetworkLink) {
	t.Helper()
	h := testServer(t)
	_ = postFromRemote(t, h, "/api/v1/agent/report", "agent-token", "203.0.113.60:12345", map[string]any{"id": "entry-link-forward", "node_name": "entry", "easytier_status": "active", "easytier_peer_count": 1, "easytier_network_ok": true, "easytier_best_latency_ms": 140.5, "easytier_packet_loss": "0.0%", "easytier_route_type": "DIRECT"})
	_ = post(t, h, "/api/v1/agent/report", "agent-token", map[string]any{"id": "backend-link-forward", "node_name": "backend", "easytier_status": "active", "easytier_peer_count": 1, "easytier_network_ok": true, "easytier_ip": "10.144.0.2/16"})
	linkResp := post(t, h, "/api/v1/network-links/quick-apply", "operator-token", map[string]any{"name": "edge-net", "entry_node_id": "entry-link-forward", "backend_node_id": "backend-link-forward"})
	return h, networkLinkFromResponse(t, linkResp)
}

func networkLinkFromResponse(t *testing.T, rr *httptest.ResponseRecorder) NetworkLink {
	t.Helper()
	if rr.Code != 202 {
		t.Fatalf("network link create failed: %d %s", rr.Code, rr.Body.String())
	}
	var resp APIResponse
	_ = json.Unmarshal(rr.Body.Bytes(), &resp)
	raw, _ := json.Marshal(resp.Data)
	var data struct {
		Link NetworkLink `json:"link"`
	}
	_ = json.Unmarshal(raw, &data)
	if data.Link.ID == "" {
		t.Fatalf("missing network link in response: %s", rr.Body.String())
	}
	return data.Link
}

func decodeLinkFromResponse(t *testing.T, rr *httptest.ResponseRecorder) NetworkLink {
	t.Helper()
	var resp APIResponse
	if err := json.Unmarshal(rr.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	raw, _ := json.Marshal(resp.Data)
	var data map[string]any
	if err := json.Unmarshal(raw, &data); err != nil {
		t.Fatal(err)
	}
	linkRaw, _ := json.Marshal(data["link"])
	var link NetworkLink
	if err := json.Unmarshal(linkRaw, &link); err != nil {
		t.Fatal(err)
	}
	return link
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

func TestPBRPolicyCRUDAndCreateApply(t *testing.T) {
	h, link := testConnectedNetworkLink(t)
	createForward := post(t, h, "/api/v1/forwards", "operator-token", map[string]any{"network_link_id": link.ID, "name": "forward-pbr", "protocol": "tcp", "public_listen_port": 18181, "landing_host": "198.51.100.10", "landing_port": 8080, "transport_mode": "easytier", "enabled": true})
	if createForward.Code != 200 {
		t.Fatalf("forward create failed: %d %s", createForward.Code, createForward.Body.String())
	}
	var forwardResp APIResponse
	_ = json.Unmarshal(createForward.Body.Bytes(), &forwardResp)
	raw, _ := json.Marshal(forwardResp.Data)
	var forward Forward
	_ = json.Unmarshal(raw, &forward)
	createPBR := post(t, h, "/api/v1/pbr-policies/create-and-apply", "operator-token", routeGroupPBRRequest(forward.ID))
	if createPBR.Code != 202 {
		t.Fatalf("pbr create apply failed: %d %s", createPBR.Code, createPBR.Body.String())
	}
	var resp struct {
		OK   bool `json:"ok"`
		Data struct {
			Policy PBRPolicy `json:"policy"`
			Task   Task      `json:"task"`
		} `json:"data"`
	}
	if err := json.Unmarshal(createPBR.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	if resp.Data.Policy.NodeID != forward.LandingNodeID || resp.Data.Policy.MatchPort != forward.TunnelTargetPort || resp.Data.Policy.MatchDstPort != forward.LandingPort {
		t.Fatalf("bad policy defaults: %+v forward=%+v", resp.Data.Policy, forward)
	}
	if resp.Data.Policy.RouteGroupName != "CN2" || resp.Data.Policy.RouteGroupGateway != "10.8.0.1" || resp.Data.Policy.RouteGroupTableID != 101 || resp.Data.Policy.RouteGroupTableName != "T_CN2" {
		t.Fatalf("bad route group fields: %+v", resp.Data.Policy)
	}
	if resp.Data.Task.Action != "apply_pbr_policy" || resp.Data.Task.NodeID != forward.LandingNodeID {
		t.Fatalf("bad pbr task: %+v", resp.Data.Task)
	}
	list := get(t, h, "/api/v1/pbr-policies", "operator-token")
	if list.Code != 200 || !strings.Contains(list.Body.String(), resp.Data.Policy.ID) {
		t.Fatalf("pbr list failed: %d %s", list.Code, list.Body.String())
	}
}

func TestPBRPolicyApplyVerifyDisableAndStatus(t *testing.T) {
	h, link := testConnectedNetworkLink(t)
	createForward := post(t, h, "/api/v1/forwards", "operator-token", map[string]any{"network_link_id": link.ID, "name": "forward-pbr-2", "protocol": "udp", "public_listen_port": 18182, "landing_host": "198.51.100.11", "landing_port": 5353, "transport_mode": "easytier", "enabled": true})
	var forwardResp APIResponse
	_ = json.Unmarshal(createForward.Body.Bytes(), &forwardResp)
	raw, _ := json.Marshal(forwardResp.Data)
	var forward Forward
	_ = json.Unmarshal(raw, &forward)
	createPBR := post(t, h, "/api/v1/pbr-policies", "operator-token", routeGroupPBRRequest(forward.ID))
	if createPBR.Code != 200 {
		t.Fatalf("pbr create failed: %d %s", createPBR.Code, createPBR.Body.String())
	}
	var pbrResp APIResponse
	_ = json.Unmarshal(createPBR.Body.Bytes(), &pbrResp)
	raw, _ = json.Marshal(pbrResp.Data)
	var policy PBRPolicy
	_ = json.Unmarshal(raw, &policy)
	apply := post(t, h, "/api/v1/pbr-policies/"+policy.ID+"/apply", "operator-token", map[string]any{})
	if apply.Code != 202 || !strings.Contains(apply.Body.String(), "apply_pbr_policy") {
		t.Fatalf("apply failed: %d %s", apply.Code, apply.Body.String())
	}
	verify := post(t, h, "/api/v1/pbr-policies/"+policy.ID+"/verify", "operator-token", map[string]any{})
	if verify.Code != 202 || !strings.Contains(verify.Body.String(), "verify_pbr_policy") {
		t.Fatalf("verify failed: %d %s", verify.Code, verify.Body.String())
	}
	disable := post(t, h, "/api/v1/pbr-policies/"+policy.ID+"/disable", "operator-token", map[string]any{})
	if disable.Code != 202 || !strings.Contains(disable.Body.String(), "disable_pbr_policy") {
		t.Fatalf("disable failed: %d %s", disable.Code, disable.Body.String())
	}
}

func TestPBRPolicyValidationAndDangerousPayload(t *testing.T) {
	h, link := testConnectedNetworkLink(t)
	createForward := post(t, h, "/api/v1/forwards", "operator-token", map[string]any{"network_link_id": link.ID, "name": "forward-pbr-bad", "protocol": "tcp", "public_listen_port": 18183, "landing_host": "198.51.100.12", "landing_port": 8080, "transport_mode": "easytier", "enabled": true})
	var forwardResp APIResponse
	_ = json.Unmarshal(createForward.Body.Bytes(), &forwardResp)
	raw, _ := json.Marshal(forwardResp.Data)
	var forward Forward
	_ = json.Unmarshal(raw, &forward)
	bad := post(t, h, "/api/v1/pbr-policies", "operator-token", map[string]any{"node_id": "missing"})
	if bad.Code != 400 {
		t.Fatalf("expected missing node failure: %d %s", bad.Code, bad.Body.String())
	}
	bad = post(t, h, "/api/v1/pbr-policies", "operator-token", map[string]any{"node_id": "backend-link-forward", "source_type": "static", "script": "bad"})
	if bad.Code != 400 || !strings.Contains(bad.Body.String(), "DANGEROUS_PAYLOAD") {
		t.Fatalf("dangerous payload not rejected: %d %s", bad.Code, bad.Body.String())
	}
	bad = post(t, h, "/api/v1/pbr-policies", "operator-token", map[string]any{"node_id": "backend-link-forward", "forward_rule_id": forward.ID})
	if bad.Code != 400 || !strings.Contains(bad.Body.String(), "route_group_name") {
		t.Fatalf("missing route group not rejected: %d %s", bad.Code, bad.Body.String())
	}
	badReq := routeGroupPBRRequest(forward.ID)
	badReq["route_group_table_name"] = "CN2"
	bad = post(t, h, "/api/v1/pbr-policies", "operator-token", badReq)
	if bad.Code != 400 || !strings.Contains(bad.Body.String(), "route_group_table_name") {
		t.Fatalf("bad table name not rejected: %d %s", bad.Code, bad.Body.String())
	}
	badReq = routeGroupPBRRequest(forward.ID)
	badReq["route_group_gateway"] = "not-ip"
	bad = post(t, h, "/api/v1/pbr-policies", "operator-token", badReq)
	if bad.Code != 400 || !strings.Contains(bad.Body.String(), "route_group_gateway") {
		t.Fatalf("bad gateway not rejected: %d %s", bad.Code, bad.Body.String())
	}
	badReq = routeGroupPBRRequest(forward.ID)
	badReq["node_id"] = forward.EntryNodeID
	bad = post(t, h, "/api/v1/pbr-policies", "operator-token", badReq)
	if bad.Code != 400 || !strings.Contains(bad.Body.String(), "landing node") {
		t.Fatalf("wrong node not rejected: %d %s", bad.Code, bad.Body.String())
	}
}

func TestRunDetectPBRRouteGroupsTaskAllowed(t *testing.T) {
	h, _ := testConnectedNetworkLink(t)
	rr := post(t, h, "/api/v1/tasks", "operator-token", map[string]any{"node_id": "backend-link-forward", "action": "detect_pbr_route_groups", "payload": map[string]any{}})
	if rr.Code != 200 || !strings.Contains(rr.Body.String(), "detect_pbr_route_groups") {
		t.Fatalf("detect route groups task not allowed: %d %s", rr.Code, rr.Body.String())
	}
}

func TestPBRSingleActivePerNode(t *testing.T) {
	h, link := testConnectedNetworkLink(t)
	firstForward := post(t, h, "/api/v1/forwards", "operator-token", map[string]any{"network_link_id": link.ID, "name": "forward-pbr-active-1", "protocol": "tcp", "public_listen_port": 18184, "landing_host": "198.51.100.14", "landing_port": 8080, "transport_mode": "easytier", "enabled": true})
	secondForward := post(t, h, "/api/v1/forwards", "operator-token", map[string]any{"network_link_id": link.ID, "name": "forward-pbr-active-2", "protocol": "tcp", "public_listen_port": 18185, "landing_host": "198.51.100.15", "landing_port": 8080, "transport_mode": "easytier", "enabled": true})
	var firstResp, secondResp APIResponse
	_ = json.Unmarshal(firstForward.Body.Bytes(), &firstResp)
	_ = json.Unmarshal(secondForward.Body.Bytes(), &secondResp)
	firstRaw, _ := json.Marshal(firstResp.Data)
	secondRaw, _ := json.Marshal(secondResp.Data)
	var first, second Forward
	_ = json.Unmarshal(firstRaw, &first)
	_ = json.Unmarshal(secondRaw, &second)
	created := post(t, h, "/api/v1/pbr-policies/create-and-apply", "operator-token", routeGroupPBRRequest(first.ID))
	if created.Code != 202 {
		t.Fatalf("first pbr failed: %d %s", created.Code, created.Body.String())
	}
	duplicateReq := routeGroupPBRRequest(second.ID)
	duplicateReq["route_group_name"] = "9929"
	duplicateReq["route_group_gateway"] = "10.7.0.1"
	duplicateReq["route_group_table_id"] = 102
	duplicateReq["route_group_table_name"] = "T_9929"
	duplicate := post(t, h, "/api/v1/pbr-policies/create-and-apply", "operator-token", duplicateReq)
	if duplicate.Code != 400 || !strings.Contains(duplicate.Body.String(), "active PBR") {
		t.Fatalf("duplicate active PBR not rejected: %d %s", duplicate.Code, duplicate.Body.String())
	}
}

func routeGroupPBRRequest(forwardID string) map[string]any {
	return map[string]any{
		"forward_rule_id":        forwardID,
		"route_group_name":       "CN2",
		"route_group_gateway":    "10.8.0.1",
		"route_group_table_id":   101,
		"route_group_table_name": "T_CN2",
		"route_group_matched_ip": "10.8.2.9",
		"enabled":                true,
	}
}

func TestNetworkLinkMSSDefaults(t *testing.T) {
	h := testServer(t)
	post(t, h, "/api/v1/agent/register", "agent-token", map[string]any{"id": "entry-mss", "name": "entry-mss", "role": "node"})
	postFromRemote(t, h, "/api/v1/agent/report", "agent-token", "198.51.100.12:1234", map[string]any{"id": "entry-mss", "name": "entry-mss", "role": "node", "hostname": "entry", "easytier_status": "active", "capabilities": map[string]bool{}})
	post(t, h, "/api/v1/agent/register", "agent-token", map[string]any{"id": "backend-mss", "name": "backend-mss", "role": "node"})
	postFromRemote(t, h, "/api/v1/agent/report", "agent-token", "198.51.100.13:1234", map[string]any{"id": "backend-mss", "name": "backend-mss", "role": "node", "hostname": "backend", "easytier_ip": "10.144.0.3/16", "easytier_status": "active", "capabilities": map[string]bool{}})
	rr := post(t, h, "/api/v1/network-links/quick-apply", "operator-token", map[string]any{"name": "mss-link", "network_name": "edge-net", "entry_node_id": "entry-mss", "backend_node_id": "backend-mss", "port": 11010, "protocols": []string{"tcp"}})
	if rr.Code != 202 {
		t.Fatalf("quick apply failed: %d %s", rr.Code, rr.Body.String())
	}
	var resp struct {
		OK   bool `json:"ok"`
		Data struct {
			Link NetworkLink `json:"link"`
		} `json:"data"`
	}
	_ = json.Unmarshal(rr.Body.Bytes(), &resp)
	if resp.Data.Link.MTU != 1380 || !resp.Data.Link.MSSClampEnabled || resp.Data.Link.MSSMode != "auto" {
		t.Fatalf("bad mss defaults: %+v", resp.Data.Link)
	}
}

func TestCreateDirectNetworkLink(t *testing.T) {
	h := testOpenServer(t)
	mustPostNode(t, h, "entry-direct", "entry-a", "203.0.113.10", "10.0.0.1")
	mustPostNode(t, h, "landing-direct", "landing-b", "198.51.100.20", "10.0.0.2")
	rr := post(t, h, "/api/v1/network-links", "", map[string]any{"link_type": "direct", "name": "ip-lc", "entry_node_id": "entry-direct", "landing_node_id": "landing-direct", "landing_reachable_host": "172.16.10.2", "transit_port": 18081, "protocols": []string{"tcp"}})
	if rr.Code != 200 {
		t.Fatalf("direct link failed: %d %s", rr.Code, rr.Body.String())
	}
	var resp struct {
		APIResponse
		Data struct {
			Link NetworkLink `json:"link"`
		} `json:"data"`
	}
	_ = json.Unmarshal(rr.Body.Bytes(), &resp)
	if resp.Data.Link.LinkType != "direct" || resp.Data.Link.LandingReachableHost != "172.16.10.2" {
		t.Fatalf("bad direct link: %+v", resp.Data.Link)
	}
}

func TestForwardDirectLinkUsesLandingReachableHost(t *testing.T) {
	h := testOpenServer(t)
	mustPostNode(t, h, "entry-direct-fwd", "entry-a", "203.0.113.10", "10.0.0.1")
	mustPostNode(t, h, "landing-direct-fwd", "landing-b", "198.51.100.20", "10.0.0.2")
	rr := post(t, h, "/api/v1/network-links", "", map[string]any{"link_type": "direct", "name": "direct", "entry_node_id": "entry-direct-fwd", "landing_node_id": "landing-direct-fwd", "landing_reachable_host": "172.16.10.2", "transit_port": 18081, "protocols": []string{"tcp"}})
	var linkResp struct {
		Data struct {
			Link NetworkLink `json:"link"`
		} `json:"data"`
	}
	_ = json.Unmarshal(rr.Body.Bytes(), &linkResp)
	create := post(t, h, "/api/v1/forwards", "", map[string]any{"network_link_id": linkResp.Data.Link.ID, "name": "direct-forward", "protocol": "tcp", "public_listen_port": 18081, "landing_host": "1.2.3.4", "landing_port": 8080})
	if create.Code != 200 {
		t.Fatalf("forward create failed: %d %s", create.Code, create.Body.String())
	}
	var fResp struct {
		Data Forward `json:"data"`
	}
	_ = json.Unmarshal(create.Body.Bytes(), &fResp)
	if fResp.Data.TransportMode != "direct" || fResp.Data.TunnelTargetHost != "172.16.10.2" {
		t.Fatalf("direct target not used: %+v", fResp.Data)
	}
}

func TestDeleteNodeCreatesCleanupTask(t *testing.T) {
	h := testOpenServer(t)
	mustPostNode(t, h, "cleanup-node", "cleanup", "203.0.113.10", "10.0.0.1")
	rr := deleteReq(t, h, "/api/v1/nodes/cleanup-node?mode=clean_deployed", "")
	if rr.Code != 202 {
		t.Fatalf("cleanup delete failed: %d %s", rr.Code, rr.Body.String())
	}
	if tasks := get(t, h, "/api/v1/tasks", ""); !strings.Contains(tasks.Body.String(), "cleanup_node_deployment") {
		t.Fatalf("cleanup task missing: %s", tasks.Body.String())
	}
}

func TestDiagnosticsRunCreatesTasks(t *testing.T) {
	h := testOpenServer(t)
	mustPostNode(t, h, "diag-node", "diag", "203.0.113.10", "10.0.0.1")
	rr := post(t, h, "/api/v1/diagnostics/run", "", map[string]any{"node_ids": []string{"diag-node"}, "include_controller": true})
	if rr.Code != 202 || !strings.Contains(rr.Body.String(), "diagnostic_id") {
		t.Fatalf("diagnostics failed: %d %s", rr.Code, rr.Body.String())
	}
	if tasks := get(t, h, "/api/v1/tasks", ""); !strings.Contains(tasks.Body.String(), "detect_pbr_route_groups") {
		t.Fatalf("diagnostic tasks missing: %s", tasks.Body.String())
	}
}
