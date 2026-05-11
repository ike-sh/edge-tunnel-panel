package agent

import (
	"context"
	"encoding/json"
	"errors"
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
	if report.NodeID != "node-a" {
		t.Fatalf("node id not preserved: %q", report.NodeID)
	}
}

func TestConfigParser(t *testing.T) {
	path := filepath.Join(t.TempDir(), "agent.yml")
	content := "controller_url: http://127.0.0.1:18080\nnode_id: n1\nnode_name: test\nrole: relay\ninterval_seconds: 5\ntoken: secret\n"
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	cfg, err := LoadConfig(path)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.ControllerURL != "http://127.0.0.1:18080" || cfg.Role != "relay" || cfg.IntervalSeconds != 5 {
		t.Fatalf("unexpected config: %+v", cfg)
	}
}

func TestWriteConfig(t *testing.T) {
	path := filepath.Join(t.TempDir(), "agent.yml")
	err := WriteConfig(path, Config{ControllerURL: "http://127.0.0.1:18080", Token: "secret-token", NodeName: "node-a", Role: "entry", IntervalSeconds: 7})
	if err != nil {
		t.Fatal(err)
	}
	cfg, err := LoadConfig(path)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Token != "secret-token" || cfg.Role != "entry" || cfg.NodeName != "node-a" || cfg.IntervalSeconds != 7 {
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
	var doc map[string]any
	if err := json.Unmarshal(report.Doctor, &doc); err != nil || doc["overall"] != "OK" {
		t.Fatalf("doctor not parsed: %s err=%v", report.Doctor, err)
	}
}
