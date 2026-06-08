package agent

import (
	"context"
	"encoding/json"
	"testing"
)

type ixFakeRunner struct {
	lastArgs []string
	stdout   string
}

func (f *ixFakeRunner) Run(ctx context.Context, name string, args ...string) CommandResult {
	f.lastArgs = append([]string{name}, args...)
	return CommandResult{Stdout: f.stdout, ExitCode: 0}
}

func (f *ixFakeRunner) LookPath(name string) (string, error) {
	return name, nil
}

func TestDispatchIXReadHealth(t *testing.T) {
	runner := &ixFakeRunner{stdout: "HEALTH_STATUS=healthy"}
	cfg := testConfig(t)
	cfg.EnableWriteActions = true
	result := ExecuteTask(context.Background(), cfg, runner, Task{
		Action:  "ix_read_health",
		Payload: map[string]any{},
	})
	if result.Status != "succeeded" {
		t.Fatalf("expected succeeded, got %s: %s", result.Status, result.Error)
	}
	if len(runner.lastArgs) < 3 || runner.lastArgs[2] != "health" {
		t.Fatalf("unexpected command: %v", runner.lastArgs)
	}
	var parsed struct {
		Subcommand string `json:"subcommand"`
	}
	if err := json.Unmarshal([]byte(result.Result), &parsed); err != nil {
		t.Fatal(err)
	}
	if parsed.Subcommand != "health" {
		t.Fatalf("expected health subcommand, got %s", parsed.Subcommand)
	}
}

func TestDispatchIXWriteRejectedWhenDisabled(t *testing.T) {
	cfg := testConfig(t)
	cfg.EnableWriteActions = false
	result := ExecuteTask(context.Background(), cfg, &ixFakeRunner{}, Task{
		Action:  "ix_write_import_code",
		Payload: map[string]any{"code": "IXTF1:test"},
	})
	if result.Status != "failed" || result.Error == "" {
		t.Fatalf("expected write rejection, got %+v", result)
	}
}

func TestDispatchNativeCreateNAT(t *testing.T) {
	t.Setenv("EDGE_IX_NATIVE", "true")
	t.Setenv("IXTF_PROFILES_DIR", t.TempDir())
	cfg := testConfig(t)
	cfg.EnableWriteActions = true
	result := ExecuteTask(context.Background(), cfg, &ixFakeRunner{}, Task{
		Action: "ix_write_create_nat",
		Payload: map[string]any{
			"profile_id": "nat-ix-listener-1",
			"config": map[string]any{
				"NAT_PUBLIC_HOST": "nat.test",
				"LANDING_HOST":    "land.test",
			},
		},
	})
	if result.Status != "succeeded" {
		t.Fatalf("expected succeeded, got %s: %s", result.Status, result.Error)
	}
	if !contains(result.Result, `"native":true`) {
		t.Fatalf("expected native result, got %s", result.Result)
	}
}

func TestDispatchNativeApplyRules(t *testing.T) {
	t.Setenv("EDGE_IX_NATIVE", "true")
	t.Setenv("IXTF_NFT_DIR", t.TempDir())
	cfg := testConfig(t)
	cfg.EnableWriteActions = true
	result := ExecuteTask(context.Background(), cfg, &ixFakeRunner{}, Task{
		Action: "ix_write_apply_rules",
		Payload: map[string]any{
			"profile_id": "p1",
			"config": map[string]any{
				"LANDING_HOST": "10.0.0.2",
				"LANDING_PORT": float64(50000),
				"TRANSIT_PORT": float64(40000),
			},
		},
	})
	if result.Status != "succeeded" {
		t.Fatalf("expected succeeded, got %s: %s", result.Status, result.Error)
	}
	if !contains(result.Result, `"nft_path"`) {
		t.Fatalf("expected nft_path in result, got %s", result.Result)
	}
}

func contains(s, sub string) bool {
	return len(s) >= len(sub) && (s == sub || len(sub) == 0 || indexSubstring(s, sub) >= 0)
}

func indexSubstring(s, sub string) int {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return i
		}
	}
	return -1
}
