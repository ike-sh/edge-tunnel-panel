package controller

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func testServer(t *testing.T) http.Handler {
	t.Helper()
	store, err := OpenStore(filepath.Join(t.TempDir(), "controller.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = store.Close() })
	return NewServer(store, "test-token", nil)
}

func postJSON(t *testing.T, h http.Handler, path, token string, body any) *httptest.ResponseRecorder {
	t.Helper()
	raw, err := json.Marshal(body)
	if err != nil {
		t.Fatal(err)
	}
	req := httptest.NewRequest(http.MethodPost, path, bytes.NewReader(raw))
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, req)
	return rr
}

func TestAgentReportRequiresToken(t *testing.T) {
	h := testServer(t)
	rr := postJSON(t, h, "/api/v1/agent/report", "", ReportRequest{NodeID: "node-a"})
	if rr.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d: %s", rr.Code, rr.Body.String())
	}
}

func TestRegisterAndReportWithToken(t *testing.T) {
	h := testServer(t)
	reg := postJSON(t, h, "/api/v1/agent/register", "test-token", RegisterRequest{NodeID: "node-a", NodeName: "A", Role: "entry"})
	if reg.Code != http.StatusOK {
		t.Fatalf("register failed: %d %s", reg.Code, reg.Body.String())
	}
	report := ReportRequest{
		NodeID: "node-a", NodeName: "A", Role: "entry", PublicIP: "1.2.3.4", PrimaryLANIP: "10.0.0.2",
		AgentVersion: Version, CoreVersion: "1.4.0 LTS", Status: "online", HealthScore: 96, IntervalSeconds: 30,
		Services: map[string]string{"nftables": "active"},
		Summary:  json.RawMessage(`{"entries_count":1,"forwards_count":1,"health_score":96}`),
		Doctor:   json.RawMessage(`{"overall":"OK","warnings":[],"suggestions":[]}`),
		Entries:  []EntryPayload{{Name: "public1", ListenPort: 8301, Protocol: "tcp,udp", PublicHost: "home.example.com", Status: "ok"}},
		Forwards: []ForwardPayload{{Name: "hk", EntryName: "public1", TargetHost: "10.0.0.8", TargetPort: 443, Protocol: "tcp,udp", Status: "ok"}},
	}
	rr := postJSON(t, h, "/api/v1/agent/report", "test-token", report)
	if rr.Code != http.StatusOK {
		t.Fatalf("report failed: %d %s", rr.Code, rr.Body.String())
	}
	req := httptest.NewRequest(http.MethodGet, "/api/v1/nodes", nil)
	out := httptest.NewRecorder()
	h.ServeHTTP(out, req)
	if out.Code != http.StatusOK || !strings.Contains(out.Body.String(), "node-a") {
		t.Fatalf("nodes output unexpected: %d %s", out.Code, out.Body.String())
	}
	reportsReq := httptest.NewRequest(http.MethodGet, "/api/v1/nodes/node-a/reports", nil)
	reportsOut := httptest.NewRecorder()
	h.ServeHTTP(reportsOut, reportsReq)
	if reportsOut.Code != http.StatusOK || !strings.Contains(reportsOut.Body.String(), "node-a") {
		t.Fatalf("reports output unexpected: %d %s", reportsOut.Code, reportsOut.Body.String())
	}
	rawReq := httptest.NewRequest(http.MethodGet, "/api/v1/nodes/node-a/raw", nil)
	rawOut := httptest.NewRecorder()
	h.ServeHTTP(rawOut, rawReq)
	if rawOut.Code != http.StatusOK || !strings.Contains(rawOut.Body.String(), "raw_json") {
		t.Fatalf("raw output unexpected: %d %s", rawOut.Code, rawOut.Body.String())
	}
	eventsReq := httptest.NewRequest(http.MethodGet, "/api/v1/nodes/node-a/events", nil)
	eventsOut := httptest.NewRecorder()
	h.ServeHTTP(eventsOut, eventsReq)
	if eventsOut.Code != http.StatusOK || !strings.Contains(eventsOut.Body.String(), "node status changed") {
		t.Fatalf("events output unexpected: %d %s", eventsOut.Code, eventsOut.Body.String())
	}
}

func TestTopologyAndBootstrapCommand(t *testing.T) {
	h := testServer(t)
	relay := ReportRequest{NodeID: "relay-1", NodeName: "relay", Role: "relay", Status: "online", IntervalSeconds: 30,
		Entries:  []EntryPayload{{Name: "public1", ListenPort: 8301, Protocol: "tcp,udp", PublicHost: "home.example.com", Status: "ok"}},
		Forwards: []ForwardPayload{{Name: "hk", EntryName: "public1", TargetHost: "10.0.0.8", TargetPort: 443, Protocol: "tcp,udp", Status: "ok"}},
	}
	entry := ReportRequest{NodeID: "entry-1", NodeName: "entry", Role: "entry", Status: "online", IntervalSeconds: 30}
	for _, report := range []ReportRequest{relay, entry} {
		rr := postJSON(t, h, "/api/v1/agent/report", "test-token", report)
		if rr.Code != http.StatusOK {
			t.Fatalf("report failed: %d %s", rr.Code, rr.Body.String())
		}
	}
	topologyReq := httptest.NewRequest(http.MethodGet, "/api/v1/topology", nil)
	topologyOut := httptest.NewRecorder()
	h.ServeHTTP(topologyOut, topologyReq)
	if topologyOut.Code != http.StatusOK {
		t.Fatalf("topology failed: %d %s", topologyOut.Code, topologyOut.Body.String())
	}
	for _, want := range []string{"relay-1", "entry-1", "entry-relay", "relay-target"} {
		if !strings.Contains(topologyOut.Body.String(), want) {
			t.Fatalf("topology missing %q: %s", want, topologyOut.Body.String())
		}
	}
	bootReq := httptest.NewRequest(http.MethodGet, "/api/v1/bootstrap/agent-command?controller_url=http://panel.local:18080?token=abc&role=relay&node_name=test-node", nil)
	bootOut := httptest.NewRecorder()
	h.ServeHTTP(bootOut, bootReq)
	if bootOut.Code != http.StatusOK {
		t.Fatalf("bootstrap failed: %d %s", bootOut.Code, bootOut.Body.String())
	}
	if strings.Contains(bootOut.Body.String(), "test-token") || strings.Contains(bootOut.Body.String(), "token=abc") || !strings.Contains(bootOut.Body.String(), "REDACTED") {
		t.Fatalf("bootstrap leaked or missed token redaction: %s", bootOut.Body.String())
	}
}

func TestRedactCleansSecrets(t *testing.T) {
	raw := []byte(`{"token":"abc","secret":"s","password":"p","privateKey":"k","custom_url":"https://example.com?token=abc","custom_cmd":"cmd --token abc","nested":{"Authorization":"Bearer abc"}}`)
	redacted := string(RedactJSONBytes(raw))
	for _, leak := range []string{"abc", "Bearer abc", "--token abc", "https://example.com?token=abc"} {
		if strings.Contains(redacted, leak) {
			t.Fatalf("redaction leaked %q in %s", leak, redacted)
		}
	}
	if !strings.Contains(redacted, "REDACTED") {
		t.Fatalf("expected REDACTED in %s", redacted)
	}
}

func TestOfflineAndEmptyCollections(t *testing.T) {
	store, err := OpenStore(filepath.Join(t.TempDir(), "controller.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()
	h := NewServer(store, "test-token", nil)
	rr := postJSON(t, h, "/api/v1/agent/report", "test-token", ReportRequest{NodeID: "old-node", NodeName: "old", Role: "relay", Status: "online", IntervalSeconds: 1})
	if rr.Code != http.StatusOK {
		t.Fatalf("report failed: %d %s", rr.Code, rr.Body.String())
	}
	_, err = store.db.Exec(`UPDATE nodes SET last_seen=? WHERE node_id=?`, time.Now().Add(-10*time.Second).UTC().Format(time.RFC3339), "old-node")
	if err != nil {
		t.Fatal(err)
	}
	nodesReq := httptest.NewRequest(http.MethodGet, "/api/v1/nodes", nil)
	nodesOut := httptest.NewRecorder()
	h.ServeHTTP(nodesOut, nodesReq)
	if nodesOut.Code != http.StatusOK || !strings.Contains(nodesOut.Body.String(), `"status":"offline"`) {
		t.Fatalf("expected offline node, got %d %s", nodesOut.Code, nodesOut.Body.String())
	}
	entriesReq := httptest.NewRequest(http.MethodGet, "/api/v1/entries", nil)
	entriesOut := httptest.NewRecorder()
	h.ServeHTTP(entriesOut, entriesReq)
	if entriesOut.Code != http.StatusOK || strings.TrimSpace(entriesOut.Body.String()) != "[]" {
		t.Fatalf("expected empty entries array, got %d %s", entriesOut.Code, entriesOut.Body.String())
	}
	forwardsReq := httptest.NewRequest(http.MethodGet, "/api/v1/forwards", nil)
	forwardsOut := httptest.NewRecorder()
	h.ServeHTTP(forwardsOut, forwardsReq)
	if forwardsOut.Code != http.StatusOK || strings.TrimSpace(forwardsOut.Body.String()) != "[]" {
		t.Fatalf("expected empty forwards array, got %d %s", forwardsOut.Code, forwardsOut.Body.String())
	}
}

func TestReportRawJSONRedacted(t *testing.T) {
	h := testServer(t)
	body := map[string]any{
		"node_id":       "node-secret",
		"status":        "online",
		"custom_url":    "https://example.com/update?token=abc",
		"custom_cmd":    "cmd --token abc",
		"Authorization": "Bearer abc",
		"privateKey":    "key",
	}
	rr := postJSON(t, h, "/api/v1/agent/report", "test-token", body)
	if rr.Code != http.StatusOK {
		t.Fatalf("report failed: %d %s", rr.Code, rr.Body.String())
	}
	rawReq := httptest.NewRequest(http.MethodGet, "/api/v1/nodes/node-secret/raw", nil)
	rawOut := httptest.NewRecorder()
	h.ServeHTTP(rawOut, rawReq)
	for _, leak := range []string{"Bearer abc", "token=abc", "cmd --token abc", "privateKey\":\"key"} {
		if strings.Contains(rawOut.Body.String(), leak) {
			t.Fatalf("raw endpoint leaked %q in %s", leak, rawOut.Body.String())
		}
	}
}

func TestPlansLifecycleAndRedaction(t *testing.T) {
	h := testServer(t)
	report := ReportRequest{
		NodeID: "relay-1", NodeName: "liqun-relay", Role: "relay", Status: "online", IntervalSeconds: 30,
		Entries:  []EntryPayload{{Name: "public1", ListenPort: 8301, Protocol: "tcp,udp", PublicHost: "home.example.com", Status: "ok"}},
		Forwards: []ForwardPayload{{Name: "hk", EntryName: "public1", TargetHost: "10.0.0.8", TargetPort: 443, Protocol: "tcp,udp", Status: "ok"}},
	}
	if rr := postJSON(t, h, "/api/v1/agent/report", "test-token", report); rr.Code != http.StatusOK {
		t.Fatalf("report failed: %d %s", rr.Code, rr.Body.String())
	}
	createBody := map[string]any{
		"type":           "create_forward",
		"title":          "Add hk forward",
		"target_node_id": "relay-1",
		"payload_json": map[string]any{
			"target_host": "10.0.0.8",
			"target_port": 443,
			"protocol":    "tcp,udp",
			"token":       "abc",
			"custom_cmd":  "cmd --token abc",
			"privateKey":  "key",
		},
	}
	created := postJSON(t, h, "/api/v1/plans", "", createBody)
	if created.Code != http.StatusCreated {
		t.Fatalf("create plan failed: %d %s", created.Code, created.Body.String())
	}
	if strings.Contains(created.Body.String(), "abc") || strings.Contains(created.Body.String(), "privateKey\":\"key") {
		t.Fatalf("plan create leaked secret: %s", created.Body.String())
	}
	var plan Plan
	if err := json.Unmarshal(created.Body.Bytes(), &plan); err != nil {
		t.Fatal(err)
	}
	listReq := httptest.NewRequest(http.MethodGet, "/api/v1/plans", nil)
	listOut := httptest.NewRecorder()
	h.ServeHTTP(listOut, listReq)
	if listOut.Code != http.StatusOK || !strings.Contains(listOut.Body.String(), "Add hk forward") {
		t.Fatalf("list plans failed: %d %s", listOut.Code, listOut.Body.String())
	}
	nodesBefore := httptest.NewRecorder()
	h.ServeHTTP(nodesBefore, httptest.NewRequest(http.MethodGet, "/api/v1/nodes", nil))
	entriesBefore := httptest.NewRecorder()
	h.ServeHTTP(entriesBefore, httptest.NewRequest(http.MethodGet, "/api/v1/entries", nil))
	forwardsBefore := httptest.NewRecorder()
	h.ServeHTTP(forwardsBefore, httptest.NewRequest(http.MethodGet, "/api/v1/forwards", nil))
	generateReq := httptest.NewRequest(http.MethodPost, fmt.Sprintf("/api/v1/plans/%d/generate", plan.ID), nil)
	generateOut := httptest.NewRecorder()
	h.ServeHTTP(generateOut, generateReq)
	if generateOut.Code != http.StatusOK {
		t.Fatalf("generate plan failed: %d %s", generateOut.Code, generateOut.Body.String())
	}
	for _, want := range []string{"command_groups", "checklist", "markdown", "This plan is manual-only", "lq --version"} {
		if !strings.Contains(generateOut.Body.String(), want) {
			t.Fatalf("generated plan missing %q: %s", want, generateOut.Body.String())
		}
	}
	for _, leak := range []string{"abc", "privateKey", "custom_cmd", "systemctl restart", "nft ", "iptables", "curl | bash", "bash -c", "eval "} {
		if strings.Contains(generateOut.Body.String(), leak) {
			t.Fatalf("generated plan leaked or used forbidden command %q: %s", leak, generateOut.Body.String())
		}
	}
	markReq := postJSON(t, h, fmt.Sprintf("/api/v1/plans/%d/mark", plan.ID), "", MarkPlanRequest{
		ExecutionStatus: "succeeded",
		ExecutionNote:   "manual result token=abc",
		ManualResult:    `{"checked":true,"privateKey":"key"}`,
	})
	if markReq.Code != http.StatusOK || !strings.Contains(markReq.Body.String(), `"execution_status":"succeeded"`) {
		t.Fatalf("mark failed: %d %s", markReq.Code, markReq.Body.String())
	}
	if strings.Contains(markReq.Body.String(), "token=abc") || strings.Contains(markReq.Body.String(), "privateKey") {
		t.Fatalf("mark leaked secret: %s", markReq.Body.String())
	}
	markdownReq := httptest.NewRequest(http.MethodGet, fmt.Sprintf("/api/v1/plans/%d/markdown", plan.ID), nil)
	markdownOut := httptest.NewRecorder()
	h.ServeHTTP(markdownOut, markdownReq)
	if markdownOut.Code != http.StatusOK || !strings.Contains(markdownOut.Body.String(), "This plan is manual-only") {
		t.Fatalf("markdown failed: %d %s", markdownOut.Code, markdownOut.Body.String())
	}
	for _, leak := range []string{"abc", "privateKey", "custom_cmd", "Authorization"} {
		if strings.Contains(markdownOut.Body.String(), leak) {
			t.Fatalf("markdown leaked %q: %s", leak, markdownOut.Body.String())
		}
	}
	regenerateReq := httptest.NewRequest(http.MethodPost, fmt.Sprintf("/api/v1/plans/%d/regenerate", plan.ID), nil)
	regenerateOut := httptest.NewRecorder()
	h.ServeHTTP(regenerateOut, regenerateReq)
	if regenerateOut.Code != http.StatusOK || !strings.Contains(regenerateOut.Body.String(), "command_groups") {
		t.Fatalf("regenerate failed: %d %s", regenerateOut.Code, regenerateOut.Body.String())
	}
	nodesAfter := httptest.NewRecorder()
	h.ServeHTTP(nodesAfter, httptest.NewRequest(http.MethodGet, "/api/v1/nodes", nil))
	if nodesBefore.Body.String() != nodesAfter.Body.String() {
		t.Fatalf("plan generation changed nodes: before=%s after=%s", nodesBefore.Body.String(), nodesAfter.Body.String())
	}
	entriesAfter := httptest.NewRecorder()
	h.ServeHTTP(entriesAfter, httptest.NewRequest(http.MethodGet, "/api/v1/entries", nil))
	if entriesBefore.Body.String() != entriesAfter.Body.String() {
		t.Fatalf("plan mark/regenerate changed entries: before=%s after=%s", entriesBefore.Body.String(), entriesAfter.Body.String())
	}
	forwardsAfter := httptest.NewRecorder()
	h.ServeHTTP(forwardsAfter, httptest.NewRequest(http.MethodGet, "/api/v1/forwards", nil))
	if forwardsBefore.Body.String() != forwardsAfter.Body.String() {
		t.Fatalf("plan mark/regenerate changed forwards: before=%s after=%s", forwardsBefore.Body.String(), forwardsAfter.Body.String())
	}
	archiveReq := httptest.NewRequest(http.MethodPost, fmt.Sprintf("/api/v1/plans/%d/archive", plan.ID), nil)
	archiveOut := httptest.NewRecorder()
	h.ServeHTTP(archiveOut, archiveReq)
	if archiveOut.Code != http.StatusOK || !strings.Contains(archiveOut.Body.String(), `"status":"archived"`) {
		t.Fatalf("archive failed: %d %s", archiveOut.Code, archiveOut.Body.String())
	}
}

func TestSwitchEntryPlanWarnings(t *testing.T) {
	h := testServer(t)
	created := postJSON(t, h, "/api/v1/plans", "", map[string]any{
		"type":           "switch_entry",
		"title":          "Switch primary",
		"target_node_id": "relay-1",
		"payload_json":   map[string]any{"entry": "public2"},
	})
	if created.Code != http.StatusCreated {
		t.Fatalf("create switch plan failed: %d %s", created.Code, created.Body.String())
	}
	var plan Plan
	if err := json.Unmarshal(created.Body.Bytes(), &plan); err != nil {
		t.Fatal(err)
	}
	out := httptest.NewRecorder()
	h.ServeHTTP(out, httptest.NewRequest(http.MethodPost, fmt.Sprintf("/api/v1/plans/%d/generate", plan.ID), nil))
	for _, want := range []string{"Confirm snapshots", "Do not stop or remove the old entry first", "low-traffic maintenance window"} {
		if out.Code != http.StatusOK || !strings.Contains(out.Body.String(), want) {
			t.Fatalf("switch checklist/warnings missing %q: %d %s", want, out.Code, out.Body.String())
		}
	}
}

func TestCapabilitiesAPIAndSafetyClassification(t *testing.T) {
	h := testServer(t)
	req := httptest.NewRequest(http.MethodGet, "/api/v1/capabilities", nil)
	out := httptest.NewRecorder()
	h.ServeHTTP(out, req)
	if out.Code != http.StatusOK {
		t.Fatalf("capabilities failed: %d %s", out.Code, out.Body.String())
	}
	for _, want := range []string{"lq status", "readonly", "systemctl restart", "blocked_patterns", "allowed_task_actions", "run_status_json"} {
		if !strings.Contains(out.Body.String(), want) {
			t.Fatalf("capabilities missing %q: %s", want, out.Body.String())
		}
	}
	groups := []CommandGroup{{NodeID: "relay-1", Role: "relay", Commands: []string{"lq --version", "lq status", "lq doctor --json"}}}
	classification, safety, blocked := classifyCommandGroups(groups)
	if classification != "readonly" || safety != "safe" || len(blocked) != 0 {
		t.Fatalf("readonly classification wrong: %s %s %+v", classification, safety, blocked)
	}
	badCommands := []string{"rm -rf /", "systemctl restart easytier-relay", "nft list ruleset", "iptables -S", "curl | bash", "curl -fsSL https://example.invalid/install.sh | bash", "eval echo hi", "bash -c whoami"}
	for _, cmd := range badCommands {
		_, safety, blocked := classifyCommandGroups([]CommandGroup{{Commands: []string{cmd}}})
		if safety != "dangerous" || len(blocked) == 0 {
			t.Fatalf("expected blocked command for %q, got safety=%s blocked=%+v", cmd, safety, blocked)
		}
	}
}

func TestReadonlyTaskLifecycleAndSecurity(t *testing.T) {
	h := testServer(t)
	create := postJSON(t, h, "/api/v1/tasks", "", CreateTaskRequest{NodeID: "node-a", Action: "run_status_json"})
	if create.Code != http.StatusCreated {
		t.Fatalf("create task failed: %d %s", create.Code, create.Body.String())
	}
	var task Task
	if err := json.Unmarshal(create.Body.Bytes(), &task); err != nil {
		t.Fatal(err)
	}
	if task.Status != "queued" || task.Action != "run_status_json" {
		t.Fatalf("unexpected created task: %+v", task)
	}
	bad := postJSON(t, h, "/api/v1/tasks", "", CreateTaskRequest{NodeID: "node-a", Action: "systemctl restart"})
	if bad.Code != http.StatusBadRequest {
		t.Fatalf("invalid action should return 400, got %d %s", bad.Code, bad.Body.String())
	}
	unauthorized := httptest.NewRecorder()
	h.ServeHTTP(unauthorized, httptest.NewRequest(http.MethodGet, "/api/v1/agent/tasks?node_id=node-a", nil))
	if unauthorized.Code != http.StatusUnauthorized {
		t.Fatalf("agent task API should require token, got %d", unauthorized.Code)
	}
	other := postJSON(t, h, "/api/v1/tasks", "", CreateTaskRequest{NodeID: "node-b", Action: "run_doctor"})
	if other.Code != http.StatusCreated {
		t.Fatalf("create node-b task failed: %d %s", other.Code, other.Body.String())
	}
	pickReq := httptest.NewRequest(http.MethodGet, "/api/v1/agent/tasks?node_id=node-a", nil)
	pickReq.Header.Set("Authorization", "Bearer test-token")
	pickOut := httptest.NewRecorder()
	h.ServeHTTP(pickOut, pickReq)
	if pickOut.Code != http.StatusOK {
		t.Fatalf("pick failed: %d %s", pickOut.Code, pickOut.Body.String())
	}
	if !strings.Contains(pickOut.Body.String(), `"node_id":"node-a"`) || strings.Contains(pickOut.Body.String(), `"node_id":"node-b"`) {
		t.Fatalf("agent received wrong node tasks: %s", pickOut.Body.String())
	}
	longOut := strings.Repeat("x", 70*1024) + " token=abc privateKey=key"
	result := postJSON(t, h, fmt.Sprintf("/api/v1/agent/tasks/%d/result", task.ID), "test-token", TaskResultRequest{
		Status:       "succeeded",
		ResultStdout: longOut,
		ResultStderr: "Authorization: Bearer abc custom_url=https://example.com?token=abc",
		ExitCode:     0,
		Error:        "password=abc",
	})
	if result.Code != http.StatusOK {
		t.Fatalf("result failed: %d %s", result.Code, result.Body.String())
	}
	body := result.Body.String()
	for _, leak := range []string{"token=abc", "Bearer abc", "privateKey=key", "password=abc"} {
		if strings.Contains(body, leak) {
			t.Fatalf("task result leaked %q: %s", leak, body)
		}
	}
	if !strings.Contains(body, "[TRUNCATED]") || !strings.Contains(body, `"status":"succeeded"`) {
		t.Fatalf("task result should be truncated and succeeded: %s", body)
	}
	listReq := httptest.NewRequest(http.MethodGet, "/api/v1/tasks", nil)
	listOut := httptest.NewRecorder()
	h.ServeHTTP(listOut, listReq)
	if listOut.Code != http.StatusOK || !strings.Contains(listOut.Body.String(), `"status":"succeeded"`) {
		t.Fatalf("list tasks unexpected: %d %s", listOut.Code, listOut.Body.String())
	}
}

func TestPlanPreflightAndBlockedCommandSanitization(t *testing.T) {
	h := testServer(t)
	missing := postJSON(t, h, "/api/v1/plans", "", map[string]any{
		"type":  "create_forward",
		"title": "Missing target",
	})
	if missing.Code != http.StatusCreated {
		t.Fatalf("create missing plan failed: %d %s", missing.Code, missing.Body.String())
	}
	var missingPlan Plan
	if err := json.Unmarshal(missing.Body.Bytes(), &missingPlan); err != nil {
		t.Fatal(err)
	}
	preflightMissing := httptest.NewRecorder()
	h.ServeHTTP(preflightMissing, httptest.NewRequest(http.MethodPost, fmt.Sprintf("/api/v1/plans/%d/preflight", missingPlan.ID), nil))
	if preflightMissing.Code != http.StatusOK || !strings.Contains(preflightMissing.Body.String(), "target node is required") {
		t.Fatalf("missing target preflight unexpected: %d %s", preflightMissing.Code, preflightMissing.Body.String())
	}
	if strings.Contains(preflightMissing.Body.String(), "token=abc") {
		t.Fatalf("preflight leaked token: %s", preflightMissing.Body.String())
	}

	offlinePlan := postJSON(t, h, "/api/v1/plans", "", map[string]any{
		"type":           "create_forward",
		"title":          "Unknown target",
		"target_node_id": "unknown-relay",
	})
	var plan Plan
	if err := json.Unmarshal(offlinePlan.Body.Bytes(), &plan); err != nil {
		t.Fatal(err)
	}
	out := httptest.NewRecorder()
	h.ServeHTTP(out, httptest.NewRequest(http.MethodPost, fmt.Sprintf("/api/v1/plans/%d/preflight", plan.ID), nil))
	if out.Code != http.StatusOK || !strings.Contains(out.Body.String(), "target node has not reported yet") {
		t.Fatalf("unknown target preflight missing warning: %d %s", out.Code, out.Body.String())
	}

	store, err := OpenStore(filepath.Join(t.TempDir(), "controller.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()
	h2 := NewServer(store, "test-token", nil)
	report := ReportRequest{NodeID: "offline-relay", NodeName: "offline", Role: "relay", Status: "online", IntervalSeconds: 1}
	if rr := postJSON(t, h2, "/api/v1/agent/report", "test-token", report); rr.Code != http.StatusOK {
		t.Fatalf("report failed: %d %s", rr.Code, rr.Body.String())
	}
	if _, err := store.db.Exec(`UPDATE nodes SET last_seen=? WHERE node_id=?`, time.Now().Add(-10*time.Second).UTC().Format(time.RFC3339), "offline-relay"); err != nil {
		t.Fatal(err)
	}
	offlineCreated := postJSON(t, h2, "/api/v1/plans", "", map[string]any{
		"type":           "create_forward",
		"title":          "Offline target",
		"target_node_id": "offline-relay",
	})
	var offline Plan
	if err := json.Unmarshal(offlineCreated.Body.Bytes(), &offline); err != nil {
		t.Fatal(err)
	}
	offlineOut := httptest.NewRecorder()
	h2.ServeHTTP(offlineOut, httptest.NewRequest(http.MethodPost, fmt.Sprintf("/api/v1/plans/%d/preflight", offline.ID), nil))
	if offlineOut.Code != http.StatusOK || !strings.Contains(offlineOut.Body.String(), "status=offline") {
		t.Fatalf("offline preflight missing status warning: %d %s", offlineOut.Code, offlineOut.Body.String())
	}

	bad := Plan{Type: "create_forward", Title: "bad", TargetNodeID: "relay-1"}
	groups := []CommandGroup{{NodeID: "relay-1", Role: "relay", Commands: []string{"lq status", "systemctl restart easytier-relay", "nft list ruleset"}}}
	classification, safety, blocked := classifyCommandGroups(groups)
	if classification != "blocked" || safety != "dangerous" || len(blocked) != 2 {
		t.Fatalf("expected dangerous blocked classification: %s %s %+v", classification, safety, blocked)
	}
	clean := flattenCommandGroups(sanitizeCommandGroups(groups))
	for _, forbidden := range []string{"systemctl restart", "nft "} {
		if strings.Contains(strings.Join(clean, "\n"), forbidden) {
			t.Fatalf("sanitized commands still contain %q: %+v", forbidden, clean)
		}
	}
	md := buildPlanMarkdown(bad, []string{"warn token=abc"}, sanitizeCommandGroups(groups), baseChecklist(), json.RawMessage(`{"Authorization":"Bearer abc"}`), []string{"lq status"}, "dangerous", "blocked")
	for _, leak := range []string{"token=abc", "Bearer abc", "systemctl restart", "nft "} {
		if strings.Contains(md, leak) {
			t.Fatalf("markdown leaked blocked/secret %q: %s", leak, md)
		}
	}
}
