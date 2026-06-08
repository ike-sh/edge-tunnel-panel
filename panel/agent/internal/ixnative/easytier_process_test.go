package ixnative

import (
	"context"
	"strings"
	"testing"
)

func TestEasyTierUnitAction(t *testing.T) {
	runner := &fakeSystemdRunner{}
	out, err := EasyTierUnitAction(context.Background(), runner, "p1", EasyTierActionStatus)
	if err != nil {
		t.Fatal(err)
	}
	if runner.calls[0][1] != "status" || runner.calls[0][2] != "edge-tunnel-easytier@p1.service" {
		t.Fatalf("unexpected call: %v", runner.calls[0])
	}
	_ = out
}

func TestProvisionEasyTierLifecycle(t *testing.T) {
	dir := t.TempDir()
	sysDir := t.TempDir()
	old := getenv
	defer func() { getenv = old }()
	getenv = func(key string) string {
		switch key {
		case "IXTF_EASYTIER_DIR":
			return dir
		case "IXTF_SYSTEMD_DIR":
			return sysDir
		case "EDGE_IX_SYSTEMD_APPLY":
			return "true"
		default:
			return ""
		}
	}
	runner := &fakeSystemdRunner{}
	out, err := ProvisionEasyTierLifecycle(context.Background(), runner, map[string]any{
		"profile_id": "p1",
		"config":     map[string]any{"NETWORK_NAME": "ix-net"},
	})
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out["easytier_config"].(string), "p1.toml") {
		t.Fatalf("unexpected out: %v", out)
	}
}
