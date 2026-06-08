package ixnative

import (
	"context"
	"testing"
)

type fakeSystemdRunner struct {
	calls [][]string
}

func (f *fakeSystemdRunner) Run(ctx context.Context, name string, args ...string) (string, string, int, error) {
	f.calls = append(f.calls, append([]string{name}, args...))
	return "", "", 0, nil
}

func TestApplySystemdUnit(t *testing.T) {
	old := getenv
	defer func() { getenv = old }()
	getenv = func(key string) string {
		if key == "EDGE_IX_SYSTEMD_APPLY" {
			return "true"
		}
		return ""
	}
	runner := &fakeSystemdRunner{}
	if err := ApplySystemdUnit(context.Background(), runner, "p1"); err != nil {
		t.Fatal(err)
	}
	if len(runner.calls) != 3 {
		t.Fatalf("expected 3 systemctl calls, got %d", len(runner.calls))
	}
}

func TestApplySystemdUnitSkippedWhenDisabled(t *testing.T) {
	runner := &fakeSystemdRunner{}
	if err := ApplySystemdUnit(context.Background(), runner, "p1"); err != nil {
		t.Fatal(err)
	}
	if len(runner.calls) != 0 {
		t.Fatalf("expected no calls when disabled")
	}
}
