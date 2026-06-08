package ixtf

import (
	"context"
	"strings"
	"testing"
)

type fakeRunner struct {
	lastName string
	lastArgs []string
	stdout   string
	stderr   string
	exitCode int
	err      error
}

func (f *fakeRunner) Run(ctx context.Context, name string, args ...string) (string, string, int, error) {
	f.lastName = name
	f.lastArgs = args
	if f.err != nil {
		return f.stdout, f.stderr, f.exitCode, f.err
	}
	return f.stdout, f.stderr, f.exitCode, nil
}

func TestAllowedSubcommand(t *testing.T) {
	if !AllowedSubcommand("health") {
		t.Fatal("health should be allowed")
	}
	if AllowedSubcommand("purge") {
		t.Fatal("purge should not be allowlisted")
	}
	if AllowedSubcommand("bash") {
		t.Fatal("bash should not be allowlisted")
	}
}

func TestValidateArgsRejectsShellInjection(t *testing.T) {
	if err := validateArgs("health", []string{"; rm -rf /"}); err == nil {
		t.Fatal("should reject shell metacharacters")
	}
}

func TestRedactSecrets(t *testing.T) {
	in := "ET_NETWORK_SECRET=supersecret123\nIXTF1:abc123token"
	out := Redact(in)
	if strings.Contains(out, "supersecret123") || strings.Contains(out, "abc123token") {
		t.Fatalf("secrets not redacted: %s", out)
	}
}

func TestBridgeRunAllowlisted(t *testing.T) {
	runner := &fakeRunner{stdout: "HEALTH_STATUS=healthy\nET_NETWORK_SECRET=hidden"}
	b := &Bridge{InstallPath: "/opt/ix-transit-fabric/install.sh", BashPath: "bash"}
	res, err := b.Run(context.Background(), runner, "health")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !strings.Contains(res.Stdout, "HEALTH_STATUS=healthy") {
		t.Fatalf("stdout missing health: %q", res.Stdout)
	}
	if strings.Contains(res.Stdout, "hidden") {
		t.Fatal("secret should be redacted")
	}
	if len(runner.lastArgs) < 2 || runner.lastArgs[1] != "health" {
		t.Fatalf("unexpected args: %v", runner.lastArgs)
	}
}

func TestBridgeRejectsUnknownSubcommand(t *testing.T) {
	b := NewBridge()
	_, err := b.Run(context.Background(), &fakeRunner{}, "uninstall")
	if err == nil {
		t.Fatal("expected error for uninstall")
	}
}

func TestActionMapping(t *testing.T) {
	sub, ok := SubcommandForAction("ix_read_health")
	if !ok || sub != "health" {
		t.Fatalf("bad mapping: %q %v", sub, ok)
	}
	if !IsReadAction("ix_read_health") {
		t.Fatal("should be read action")
	}
	if !IsWriteAction("ix_write_import_code") {
		t.Fatal("should be write action")
	}
}
