package agent

import (
	"context"
	"errors"
	"os"
	"path/filepath"
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
