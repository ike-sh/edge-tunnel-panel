package agent

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestRedactCleansSecrets(t *testing.T) {
	raw := []byte(`{"token":"abc","secret":"s","password":"p","privateKey":"k","custom_url":"https://example.com?token=abc","custom_cmd":"cmd --token abc"}`)
	redacted := string(RedactJSONBytes(raw))
	for _, leak := range []string{"abc", "--token abc", "https://example.com?token=abc"} {
		if strings.Contains(redacted, leak) {
			t.Fatalf("redaction leaked %q in %s", leak, redacted)
		}
	}
}

func TestCollectorDoesNotCrashWhenLQMissing(t *testing.T) {
	c := Collector{
		LQPath: filepath.Join(t.TempDir(), "missing-lq"),
		PublicIPFunc: func(context.Context) (string, error) {
			return "", errors.New("no network")
		},
	}
	report := c.Collect(context.Background(), Config{NodeID: "node-a", NodeName: "A", Role: "entry"})
	if report.CoreVersion != "missing" {
		t.Fatalf("expected missing core version, got %q", report.CoreVersion)
	}
	if report.Status != "degraded" {
		t.Fatalf("expected degraded, got %q", report.Status)
	}
	if report.Capabilities.LQAvailable {
		t.Fatalf("expected lq unavailable capabilities: %+v", report.Capabilities)
	}
	if report.NodeID != "node-a" {
		t.Fatalf("node id not preserved: %q", report.NodeID)
	}
}

func TestConfigParser(t *testing.T) {
	path := filepath.Join(t.TempDir(), "agent.yml")
	content := "controller_url: http://127.0.0.1:18080\nnode_id: n1\nnode_name: test\nrole: relay\ninterval_seconds: 5\ntoken: secret\nenable_tasks: true\ntask_interval_seconds: 3\ntask_timeout_seconds: 4\n"
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	cfg, err := LoadConfig(path)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.ControllerURL != "http://127.0.0.1:18080" || cfg.Role != "relay" || cfg.IntervalSeconds != 5 || !cfg.EnableTasks || cfg.TaskIntervalSeconds != 3 || cfg.TaskTimeoutSeconds != 4 {
		t.Fatalf("unexpected config: %+v", cfg)
	}
}

func TestWriteConfig(t *testing.T) {
	path := filepath.Join(t.TempDir(), "agent.yml")
	err := WriteConfig(path, Config{ControllerURL: "http://127.0.0.1:18080", Token: "secret-token", NodeName: "node-a", Role: "entry", IntervalSeconds: 7, EnableTasks: true, TaskIntervalSeconds: 8, TaskTimeoutSeconds: 9})
	if err != nil {
		t.Fatal(err)
	}
	cfg, err := LoadConfig(path)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Token != "secret-token" || cfg.Role != "entry" || cfg.NodeName != "node-a" || cfg.IntervalSeconds != 7 || !cfg.EnableTasks || cfg.TaskIntervalSeconds != 8 || cfg.TaskTimeoutSeconds != 9 {
		t.Fatalf("unexpected config: %+v", cfg)
	}
	if runtime.GOOS != "windows" {
		info, err := os.Stat(path)
		if err != nil {
			t.Fatal(err)
		}
		if info.Mode().Perm() != 0o600 {
			t.Fatalf("expected 0600 config mode, got %o", info.Mode().Perm())
		}
	}
}

func TestCollectorBadJSONDegrades(t *testing.T) {
	lqPath := filepath.Join(t.TempDir(), "lq")
	if err := os.WriteFile(lqPath, []byte("placeholder"), 0o700); err != nil {
		t.Fatal(err)
	}
	c := Collector{
		LQPath: lqPath,
		PublicIPFunc: func(context.Context) (string, error) {
			return "203.0.113.10", nil
		},
		CommandFunc: func(_ context.Context, _ string, args ...string) (string, error) {
			if len(args) == 1 && args[0] == "--version" {
				return "leikwan-toolkit 1.4.0 LTS", nil
			}
			return "{bad-json", nil
		},
	}
	report := c.Collect(context.Background(), Config{NodeID: "node-a", NodeName: "A", Role: "relay", IntervalSeconds: 9})
	if report.Status != "degraded" {
		t.Fatalf("expected degraded, got %q", report.Status)
	}
	if len(report.RecentErrors) == 0 {
		t.Fatalf("expected recent JSON parse errors")
	}
	if report.IntervalSeconds != 9 {
		t.Fatalf("interval not reported: %d", report.IntervalSeconds)
	}
	if !report.Capabilities.LQAvailable || report.Capabilities.SupportsStatusJSON || report.Capabilities.SupportsDoctorJSON {
		t.Fatalf("bad json capabilities should be degraded but available without json support: %+v", report.Capabilities)
	}
}

func TestCollectorParsesStatusAndDoctorJSON(t *testing.T) {
	lqPath := filepath.Join(t.TempDir(), "lq")
	if err := os.WriteFile(lqPath, []byte("placeholder"), 0o700); err != nil {
		t.Fatal(err)
	}
	statusJSON := `{"role":"relay","easytier_ip":"10.198.1.1","health_score":96,"overall":"OK","entries_total":1,"forwards_total":1,"entries":[{"name":"public1","listen_port":8301,"protocols":["tcp","udp"],"public_host":"home.example.com","status":"ok"}],"forwards":[{"name":"hk","entry_name":"public1","target_host":"10.0.0.8","target_port":443,"protocols":["tcp","udp"],"status":"ok"}]}`
	doctorJSON := `{"overall":"OK","warnings":["none"],"suggestions":["none"]}`
	c := Collector{
		LQPath: lqPath,
		PublicIPFunc: func(context.Context) (string, error) {
			return "203.0.113.10", nil
		},
		CommandFunc: func(_ context.Context, _ string, args ...string) (string, error) {
			if len(args) == 1 && args[0] == "--version" {
				return "leikwan-toolkit 1.4.0 LTS", nil
			}
			if len(args) == 2 && args[0] == "status" {
				return statusJSON, nil
			}
			if len(args) == 2 && args[0] == "doctor" {
				return doctorJSON, nil
			}
			return "", nil
		},
	}
	report := c.Collect(context.Background(), Config{NodeID: "node-a", Role: "unknown", IntervalSeconds: 15})
	if report.Role != "relay" || report.EasyTierIP != "10.198.1.1" || report.HealthScore != 96 {
		t.Fatalf("status fields not parsed: %+v", report)
	}
	if len(report.Entries) != 1 || report.Entries[0].Name != "public1" {
		t.Fatalf("entries not parsed: %+v", report.Entries)
	}
	if len(report.Forwards) != 1 || report.Forwards[0].Name != "hk" {
		t.Fatalf("forwards not parsed: %+v", report.Forwards)
	}
	if !report.Capabilities.LQAvailable || !report.Capabilities.SupportsStatusJSON || !report.Capabilities.SupportsDoctorJSON || !report.Capabilities.SupportsForwardList || !report.Capabilities.SupportsDDNSOverview {
		t.Fatalf("capabilities not detected: %+v", report.Capabilities)
	}
	var doc map[string]any
	if err := json.Unmarshal(report.Doctor, &doc); err != nil || doc["overall"] != "OK" {
		t.Fatalf("doctor not parsed: %s err=%v", report.Doctor, err)
	}
}

func TestReadonlyTaskActionMappingAndRejection(t *testing.T) {
	args, ok := TaskActionArgs("list_forwards")
	if !ok || strings.Join(args, " ") != "forward list" {
		t.Fatalf("unexpected list_forwards mapping: %v %v", args, ok)
	}
	lqPath := filepath.Join(t.TempDir(), "lq")
	if err := os.WriteFile(lqPath, []byte("placeholder"), 0o700); err != nil {
		t.Fatal(err)
	}
	var gotName string
	var gotArgs []string
	c := Collector{
		LQPath: lqPath,
		TaskCommandFunc: func(_ context.Context, name string, args ...string) (string, string, int, error) {
			gotName = name
			gotArgs = append([]string(nil), args...)
			return "ok token=abc", "privateKey=key", 0, nil
		},
	}
	result := ExecuteTask(context.Background(), c, Config{TaskTimeoutSeconds: 5}, Task{ID: 1, NodeID: "node-a", Action: "list_forwards"})
	if result.Status != "succeeded" || gotName != lqPath || strings.Join(gotArgs, " ") != "forward list" {
		t.Fatalf("unexpected task result=%+v name=%s args=%v", result, gotName, gotArgs)
	}
	if strings.Contains(result.ResultStdout, "token=abc") || strings.Contains(result.ResultStderr, "privateKey=key") {
		t.Fatalf("task output was not redacted: %+v", result)
	}
	rejected := ExecuteTask(context.Background(), c, Config{}, Task{Action: "rm"})
	if rejected.Status != "rejected" || rejected.ExitCode == 0 {
		t.Fatalf("invalid action should be rejected: %+v", rejected)
	}
}

func TestReadonlyTaskMissingLQAndTimeout(t *testing.T) {
	missing := Collector{LQPath: filepath.Join(t.TempDir(), "missing-lq")}
	result := ExecuteTask(context.Background(), missing, Config{}, Task{Action: "run_status"})
	if result.Status != "failed" || result.ExitCode != 127 || !strings.Contains(result.Error, "lq missing") {
		t.Fatalf("missing lq should fail clearly: %+v", result)
	}
	lqPath := filepath.Join(t.TempDir(), "lq")
	if err := os.WriteFile(lqPath, []byte("placeholder"), 0o700); err != nil {
		t.Fatal(err)
	}
	timeoutCollector := Collector{
		LQPath: lqPath,
		TaskCommandFunc: func(ctx context.Context, _ string, _ ...string) (string, string, int, error) {
			<-ctx.Done()
			return "", "", 1, ctx.Err()
		},
	}
	timedOut := ExecuteTask(context.Background(), timeoutCollector, Config{TaskTimeoutSeconds: 1}, Task{Action: "run_status"})
	if timedOut.Status != "failed" || !strings.Contains(timedOut.Error, "timeout") {
		t.Fatalf("timeout should fail cleanly: %+v", timedOut)
	}
}

func TestRunDoesNotPollTasksWhenDisabled(t *testing.T) {
	var taskPolls int
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/api/v1/agent/register", "/api/v1/agent/report":
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"status":"ok"}`))
		case "/api/v1/agent/tasks":
			taskPolls++
			_, _ = w.Write([]byte(`[]`))
		default:
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
	}))
	defer server.Close()
	cfg := Config{ControllerURL: server.URL, Token: "test-token", NodeID: "node-a", NodeName: "node-a", Role: "relay", IntervalSeconds: 1, EnableTasks: false}
	if err := Run(context.Background(), cfg, true, false); err != nil {
		t.Fatalf("run failed: %v", err)
	}
	if taskPolls != 0 {
		t.Fatalf("expected no task polls when disabled, got %d", taskPolls)
	}
}

func TestClientTaskAPIsRedactBody(t *testing.T) {
	var resultBody bytes.Buffer
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer test-token" {
			t.Fatalf("missing auth header")
		}
		switch r.URL.Path {
		case "/api/v1/agent/tasks":
			_ = json.NewEncoder(w).Encode([]Task{{ID: 7, NodeID: "node-a", Action: "run_status", Status: "queued"}})
		case "/api/v1/agent/tasks/7/result":
			_, _ = resultBody.ReadFrom(r.Body)
			_, _ = w.Write([]byte(`{"status":"ok"}`))
		default:
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
	}))
	defer server.Close()
	client := NewClient(Config{ControllerURL: server.URL, Token: "test-token"})
	tasks, err := client.GetTasks(context.Background(), "node-a")
	if err != nil || len(tasks) != 1 || tasks[0].ID != 7 {
		t.Fatalf("get tasks failed: tasks=%+v err=%v", tasks, err)
	}
	if err := client.ReportTaskResult(context.Background(), 7, TaskResultRequest{Status: "failed", ResultStdout: "token=abc", ResultStderr: "privateKey=key"}); err != nil {
		t.Fatalf("report result failed: %v", err)
	}
	if strings.Contains(resultBody.String(), "token=abc") || strings.Contains(resultBody.String(), "privateKey=key") {
		t.Fatalf("client leaked task result body: %s", resultBody.String())
	}
}
