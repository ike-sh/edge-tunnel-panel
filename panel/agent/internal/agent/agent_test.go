package agent

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

type fakeRunner struct {
	paths map[string]bool
	calls []string
}

func (f *fakeRunner) Run(ctx context.Context, name string, args ...string) CommandResult {
	f.calls = append(f.calls, name+" "+strings.Join(args, " "))
	return CommandResult{Stdout: "ok", ExitCode: 0}
}

func (f *fakeRunner) LookPath(name string) (string, error) {
	if f.paths != nil && f.paths[name] {
		return "/usr/bin/" + name, nil
	}
	return "", errors.New("missing")
}

func testConfig(t *testing.T) Config {
	t.Helper()
	cfg := DefaultConfig()
	cfg.ControllerURL = "http://127.0.0.1:18080"
	cfg.ControllerToken = "secret-token"
	cfg.NodeID = "node-a"
	cfg.NodeName = "edge-node"
	cfg.EnableTasks = true
	cfg.ConfigDir = filepath.Join(t.TempDir(), "etc")
	cfg.StateDir = filepath.Join(t.TempDir(), "state")
	cfg.TaskResultLimitKB = 1
	cfg.MaxConcurrentTasks = 1
	return cfg
}

func TestConfigFromEnv(t *testing.T) {
	t.Setenv("EDGE_CONTROLLER_URL", "http://controller:18080/")
	t.Setenv("EDGE_CONTROLLER_TOKEN", "token")
	t.Setenv("EDGE_NODE_ID", "node-env")
	t.Setenv("EDGE_NODE_NAME", "edge-a")
	t.Setenv("EDGE_NODE_ROLE", "entry")
	t.Setenv("EDGE_ENABLE_TASKS", "true")
	t.Setenv("EDGE_ENABLE_WRITE_ACTIONS", "true")
	t.Setenv("EDGE_AGENT_CONFIG_DIR", "/tmp/edge-config")
	t.Setenv("EDGE_AGENT_STATE_DIR", "/tmp/edge-state")
	cfg := ConfigFromEnv()
	if cfg.ControllerURL != "http://controller:18080" || cfg.ControllerToken != "token" {
		t.Fatalf("env config not loaded: %+v", cfg)
	}
	if cfg.NodeID != "node-env" {
		t.Fatalf("node id env not applied: %+v", cfg)
	}
	if cfg.NodeName != "edge-a" || cfg.NodeRole != "entry" || !cfg.EnableTasks || !cfg.EnableWriteActions {
		t.Fatalf("env values not applied: %+v", cfg)
	}
	if cfg.ConfigDir != "/tmp/edge-config" || cfg.StateDir != "/tmp/edge-state" {
		t.Fatalf("env dirs not applied: %+v", cfg)
	}
}

func TestConfigFlagsOverrideEnv(t *testing.T) {
	t.Setenv("EDGE_CONTROLLER_URL", "http://env-controller:18080")
	t.Setenv("EDGE_CONTROLLER_TOKEN", "env-token")
	t.Setenv("EDGE_NODE_ID", "env-node")
	cfg := ConfigFromEnv()
	cfg.ControllerURL = "http://flag-controller:18080/"
	cfg.ControllerToken = "flag-token"
	cfg.NodeID = "flag-node"
	if err := cfg.Normalize(); err != nil {
		t.Fatal(err)
	}
	if err := cfg.Validate(); err != nil {
		t.Fatal(err)
	}
	if cfg.ControllerURL != "http://flag-controller:18080" || cfg.ControllerToken != "flag-token" || cfg.NodeID != "flag-node" {
		t.Fatalf("flag values should override env values: %+v", cfg)
	}
}

func TestAgentOnceAcceptsFlags(t *testing.T) {
	cfg := DefaultConfig()
	cfg.ControllerURL = "http://127.0.0.1:18080/"
	cfg.ControllerToken = "flag-token"
	cfg.NodeID = "flag-node"
	cfg.NodeName = "edge-node"
	cfg.NodeRole = "backend"
	cfg.EnableTasks = true
	cfg.EnableWriteActions = true
	cfg.ConfigDir = t.TempDir()
	cfg.StateDir = t.TempDir()
	if err := cfg.Normalize(); err != nil {
		t.Fatal(err)
	}
	if err := cfg.Validate(); err != nil {
		t.Fatalf("once-style flag config should validate: %v", err)
	}
}

func TestRedactionAndLimit(t *testing.T) {
	result := TaskResult{
		Result: `{"token":"secret-token"}` + strings.Repeat("x", 2048),
		Stdout: "Authorization: Bearer secret-token",
		Stderr: "EDGE_CONTROLLER_TOKEN=secret-token",
		Error:  "token=secret-token",
	}
	limited := LimitTaskResult(result, 1, "secret-token")
	joined := limited.Result + limited.Stdout + limited.Stderr + limited.Error
	if strings.Contains(joined, "secret-token") {
		t.Fatalf("secret leaked after redaction: %s", joined)
	}
	if !strings.Contains(limited.Result, "[TRUNCATED]") {
		t.Fatalf("long result not truncated: %d", len(limited.Result))
	}
}

func TestCollectStatusReturnsEdgeCapabilities(t *testing.T) {
	cfg := testConfig(t)
	runner := &fakeRunner{paths: map[string]bool{"easytier-core": true, "nft": true, "ip": true}}
	status := CollectStatus(context.Background(), cfg, runner)
	for _, key := range []string{
		"supports_agent_status",
		"supports_task_polling",
		"supports_network_profile",
		"supports_entry_apply",
		"supports_forward_apply",
		"supports_pbr_apply",
		"supports_ddns_apply",
		"supports_easytier_manage",
		"supports_firewall_reload",
	} {
		if _, ok := status.Capabilities[key]; !ok {
			t.Fatalf("missing capability %s in %+v", key, status.Capabilities)
		}
	}
}

func TestDangerousPayloadRejected(t *testing.T) {
	for _, key := range dangerousPayloadKeys {
		task := Task{Action: "collect_agent_status", Payload: map[string]any{key: "bad"}}
		if err := ValidateTask(task, testConfig(t)); err == nil {
			t.Fatalf("expected dangerous key %s to be rejected", key)
		}
	}
}

func TestAllowedActions(t *testing.T) {
	cfg := testConfig(t)
	cfg.EnableWriteActions = false
	if err := ValidateTask(Task{Action: "collect_agent_status", Payload: map[string]any{}}, cfg); err != nil {
		t.Fatalf("readonly action rejected: %v", err)
	}
	if err := ValidateTask(Task{Action: "apply_forward_config", Payload: map[string]any{}}, cfg); err == nil {
		t.Fatalf("write action should be rejected when disabled")
	}
	cfg.EnableWriteActions = true
	if err := ValidateTask(Task{Action: "apply_forward_config", Payload: map[string]any{}}, cfg); err != nil {
		t.Fatalf("write action rejected when enabled: %v", err)
	}
	if err := ValidateTask(Task{Action: "reboot_node", Payload: map[string]any{}}, cfg); err == nil {
		t.Fatalf("reboot without confirm should fail")
	}
	if err := ValidateTask(Task{Action: "reboot_node", Payload: map[string]any{"confirm": true}}, cfg); err != nil {
		t.Fatalf("reboot with confirm rejected: %v", err)
	}
}

func TestUnknownActionRejected(t *testing.T) {
	if err := ValidateTask(Task{Action: "unknown", Payload: map[string]any{}}, testConfig(t)); err == nil {
		t.Fatalf("unknown action should fail")
	}
	for action := range blockedActions {
		if err := ValidateTask(Task{Action: action, Payload: map[string]any{}}, testConfig(t)); err == nil {
			t.Fatalf("blocked action %s should fail", action)
		}
	}
}

func TestExecuteReadonlyTask(t *testing.T) {
	cfg := testConfig(t)
	runner := &fakeRunner{paths: map[string]bool{"nft": true, "ip": true}}
	result := ExecuteTask(context.Background(), cfg, runner, Task{Action: "collect_agent_status", Payload: map[string]any{}})
	if result.Status != "succeeded" || !strings.Contains(result.Result, "supports_agent_status") {
		t.Fatalf("bad readonly result: %+v", result)
	}
}

func TestApplyForwardWritesStructuredConfig(t *testing.T) {
	cfg := testConfig(t)
	cfg.EnableWriteActions = true
	payload := map[string]any{"protocol": "udp", "listen_port": 8443.0, "target_host": "10.144.1.9", "target_port": 443.0}
	result := ExecuteTask(context.Background(), cfg, &fakeRunner{}, Task{Action: "apply_forward_config", Payload: payload})
	if result.Status != "succeeded" {
		t.Fatalf("forward apply failed: %+v", result)
	}
	raw, err := os.ReadFile(forwardNFTPath(cfg))
	if err != nil {
		t.Fatal(err)
	}
	text := string(raw)
	if strings.Contains(text, "raw_nft") || !strings.Contains(text, "udp dport") {
		t.Fatalf("unexpected nft output: %s", text)
	}
	if _, err := os.Stat(forwardPath(cfg)); err != nil {
		t.Fatal(err)
	}
}

func TestApplyPBRWritesStructuredScript(t *testing.T) {
	cfg := testConfig(t)
	cfg.EnableWriteActions = true
	payload := map[string]any{"match_source": "10.0.0.0/24", "table_id": 100.0, "gateway": "10.144.0.1", "priority": 1000.0}
	result := ExecuteTask(context.Background(), cfg, &fakeRunner{}, Task{Action: "apply_pbr_config", Payload: payload})
	if result.Status != "succeeded" {
		t.Fatalf("pbr apply failed: %+v", result)
	}
	raw, err := os.ReadFile(pbrApplyPath(cfg))
	if err != nil {
		t.Fatal(err)
	}
	text := string(raw)
	if strings.Contains(text, "raw_ip_route") || !strings.Contains(text, "ip rule add") {
		t.Fatalf("unexpected pbr script: %s", text)
	}
}

func TestClientRegisterReportTasksResult(t *testing.T) {
	var sawRegister, sawReport, sawResult bool
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer secret-token" {
			t.Fatalf("missing auth")
		}
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/api/v1/agent/register":
			sawRegister = true
			_, _ = w.Write([]byte(`{"ok":true,"data":{}}`))
		case "/api/v1/agent/report":
			sawReport = true
			_, _ = w.Write([]byte(`{"ok":true,"data":{}}`))
		case "/api/v1/agent/tasks":
			_, _ = w.Write([]byte(`{"ok":true,"data":[{"id":"t1","node_id":"node-a","action":"collect_agent_status","payload":{},"status":"pending"}]}`))
		case "/api/v1/agent/tasks/t1/result":
			sawResult = true
			_, _ = w.Write([]byte(`{"ok":true,"data":{}}`))
		default:
			t.Fatalf("unexpected path %s", r.URL.Path)
		}
	}))
	defer server.Close()
	cfg := testConfig(t)
	cfg.ControllerURL = server.URL
	client := NewHTTPClient(cfg)
	report := ReportFromStatus(cfg, CollectStatus(context.Background(), cfg, &fakeRunner{}))
	if err := client.Register(context.Background(), report); err != nil {
		t.Fatal(err)
	}
	if err := client.Report(context.Background(), report); err != nil {
		t.Fatal(err)
	}
	tasks, err := client.FetchTasks(context.Background(), "node-a")
	if err != nil || len(tasks) != 1 {
		t.Fatalf("fetch tasks failed: tasks=%+v err=%v", tasks, err)
	}
	if err := client.SubmitTaskResult(context.Background(), "t1", TaskResult{Status: "succeeded"}); err != nil {
		t.Fatal(err)
	}
	if !sawRegister || !sawReport || !sawResult {
		t.Fatalf("server did not see expected requests")
	}
}

type fakeClient struct {
	tasks       []Task
	inFlight    int32
	maxInFlight int32
	results     int32
}

func (f *fakeClient) Register(context.Context, ReportRequest) error      { return nil }
func (f *fakeClient) Report(context.Context, ReportRequest) error        { return nil }
func (f *fakeClient) FetchTasks(context.Context, string) ([]Task, error) { return f.tasks, nil }
func (f *fakeClient) SubmitTaskResult(context.Context, string, TaskResult) error {
	cur := atomic.AddInt32(&f.inFlight, 1)
	if cur > atomic.LoadInt32(&f.maxInFlight) {
		atomic.StoreInt32(&f.maxInFlight, cur)
	}
	time.Sleep(5 * time.Millisecond)
	atomic.AddInt32(&f.inFlight, -1)
	atomic.AddInt32(&f.results, 1)
	return nil
}

func TestProcessTasksSerializes(t *testing.T) {
	cfg := testConfig(t)
	client := &fakeClient{tasks: []Task{
		{ID: "1", Action: "collect_agent_status", Payload: map[string]any{}},
		{ID: "2", Action: "collect_agent_status", Payload: map[string]any{}},
	}}
	if err := ProcessTasks(context.Background(), cfg, client, &fakeRunner{}); err != nil {
		t.Fatal(err)
	}
	if client.maxInFlight != 1 || client.results != 2 {
		t.Fatalf("expected serial results, max=%d results=%d", client.maxInFlight, client.results)
	}
}
