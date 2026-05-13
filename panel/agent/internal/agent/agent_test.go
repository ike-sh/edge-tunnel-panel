package agent

import (
	"archive/zip"
	"context"
	"errors"
	"net"
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

type failingRunner struct {
	fakeRunner
	failName string
}

func (f *failingRunner) Run(ctx context.Context, name string, args ...string) CommandResult {
	f.calls = append(f.calls, name+" "+strings.Join(args, " "))
	if name == f.failName {
		return CommandResult{Stderr: "failed", ExitCode: 1}
	}
	return CommandResult{Stdout: "ok", ExitCode: 0}
}

func (f *fakeRunner) LookPath(name string) (string, error) {
	if f.paths != nil && f.paths[name] {
		return "/usr/bin/" + name, nil
	}
	return "", errors.New("missing")
}

type installRunner struct {
	fakeRunner
	archive    string
	installDir string
}

func (r *installRunner) Run(ctx context.Context, name string, args ...string) CommandResult {
	r.calls = append(r.calls, name+" "+strings.Join(args, " "))
	if strings.HasSuffix(name, "easytier-core") && len(args) == 1 && args[0] == "--version" {
		return CommandResult{Stdout: "easytier v2.4.5", ExitCode: 0}
	}
	return r.fakeRunner.Run(ctx, name, args...)
}

func (r *installRunner) LookPath(name string) (string, error) {
	if r.installDir != "" {
		candidate := filepath.Join(r.installDir, name)
		if _, err := os.Stat(candidate); err == nil {
			return candidate, nil
		}
	}
	return r.fakeRunner.LookPath(name)
}

func testConfig(t *testing.T) Config {
	t.Helper()
	t.Setenv("EDGE_TEST", "1")
	oldSystemdDir := systemdSystemDir
	oldInstallDir := easyTierInstallDir
	systemdSystemDir = filepath.Join(t.TempDir(), "systemd-system")
	easyTierInstallDir = filepath.Join(t.TempDir(), "bin")
	t.Cleanup(func() {
		systemdSystemDir = oldSystemdDir
		easyTierInstallDir = oldInstallDir
	})
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
	t.Setenv("EDGE_REPORT_INTERVAL", "30s")
	t.Setenv("EDGE_TASK_POLL_INTERVAL", "10s")
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
	if cfg.ReportInterval != 30*time.Second || cfg.PollInterval != 10*time.Second {
		t.Fatalf("interval env not applied: %+v", cfg)
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

func TestPrivateIPCollectRFC1918Only(t *testing.T) {
	ifaces := []net.Interface{
		{Index: 1, Flags: net.FlagUp},
	}
	ipv4 := net.IPv4(10, 0, 0, 5)
	public := net.IPv4(216, 23, 88, 67)
	oldAddrs := interfaceAddrsFunc
	interfaceAddrsFunc = func(iface net.Interface) ([]net.Addr, error) {
		return []net.Addr{
			&net.IPNet{IP: public, Mask: net.CIDRMask(24, 32)},
			&net.IPNet{IP: ipv4, Mask: net.CIDRMask(24, 32)},
		}, nil
	}
	t.Cleanup(func() { interfaceAddrsFunc = oldAddrs })
	got := privateIPFromInterfaces(func() ([]net.Interface, error) { return ifaces, nil })
	if got != "10.0.0.5" {
		t.Fatalf("expected RFC1918 private IP only, got %q", got)
	}
}

func TestPublicIPNotUsedAsPrivateIP(t *testing.T) {
	ifaces := []net.Interface{{Index: 1, Flags: net.FlagUp}}
	oldAddrs := interfaceAddrsFunc
	interfaceAddrsFunc = func(iface net.Interface) ([]net.Addr, error) {
		return []net.Addr{&net.IPNet{IP: net.IPv4(216, 23, 88, 67), Mask: net.CIDRMask(24, 32)}}, nil
	}
	t.Cleanup(func() { interfaceAddrsFunc = oldAddrs })
	got := privateIPFromInterfaces(func() ([]net.Interface, error) { return ifaces, nil })
	if got != "-" {
		t.Fatalf("expected no private IP, got %q", got)
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

func TestApplyNetworkProfileWritesEasyTierConfig(t *testing.T) {
	cfg := testConfig(t)
	cfg.EnableWriteActions = true
	payload := map[string]any{"network_profile": map[string]any{"network_name": "edge-prod", "network_secret": "secret", "cidr": "10.144.0.0/16", "protocol_preference": "tcp", "peers": []any{"tcp://1.2.3.4:11010"}}}
	result := ExecuteTask(context.Background(), cfg, &fakeRunner{paths: map[string]bool{"easytier-core": true}}, Task{Action: "apply_network_profile", Payload: payload})
	if result.Status != "failed" && result.Status != "succeeded" {
		t.Fatalf("unexpected result: %+v", result)
	}
	raw, err := os.ReadFile(easyTierPath(cfg))
	if err != nil {
		t.Fatal(err)
	}
	text := string(raw)
	if !strings.Contains(text, `network_name = "edge-prod"`) || !strings.Contains(text, `default_protocol = "tcp"`) || !strings.Contains(text, `instance_name`) || !strings.Contains(text, `peer = ["tcp://1.2.3.4:11010"]`) {
		t.Fatalf("unexpected easytier config: %s", text)
	}
	if _, err := os.Stat(networkProfilePath(cfg)); err != nil {
		t.Fatal(err)
	}
}

func TestApplyNetworkProfileWritesSystemdService(t *testing.T) {
	cfg := testConfig(t)
	cfg.EnableWriteActions = true
	payload := map[string]any{"network_name": "edge-prod", "network_secret": "secret"}
	_ = ExecuteTask(context.Background(), cfg, &fakeRunner{paths: map[string]bool{"easytier-core": true}}, Task{Action: "apply_network_profile", Payload: payload})
	raw, err := os.ReadFile(easyTierServiceConfigPath(cfg))
	if err != nil {
		t.Fatal(err)
	}
	text := string(raw)
	if !strings.Contains(text, "Description=Edge Tunnel EasyTier") || !strings.Contains(text, "--network-name edge-prod") || !strings.Contains(text, "-l tcp://0.0.0.0:11010") {
		t.Fatalf("unexpected service: %s", text)
	}
}

func TestApplyNetworkProfileMissingBinaryReturnsError(t *testing.T) {
	cfg := testConfig(t)
	cfg.EnableWriteActions = true
	oldDownload := downloadEasyTierArchiveFunc
	downloadEasyTierArchiveFunc = func(ctx context.Context, url, dest string) error {
		return errors.New("network unavailable")
	}
	t.Cleanup(func() { downloadEasyTierArchiveFunc = oldDownload })
	result := ExecuteTask(context.Background(), cfg, &fakeRunner{}, Task{Action: "apply_network_profile", Payload: map[string]any{"network_name": "edge-prod"}})
	if result.Status != "failed" || !strings.Contains(result.Error, "download EasyTier failed") {
		t.Fatalf("expected download failure: %+v", result)
	}
	if _, err := os.Stat(easyTierPath(cfg)); err != nil {
		t.Fatalf("config should still be written: %v", err)
	}
}

func TestVerifyEasyTierStatusMissingBinary(t *testing.T) {
	cfg := testConfig(t)
	result := ExecuteTask(context.Background(), cfg, &fakeRunner{}, Task{Action: "verify_easytier_status", Payload: map[string]any{}})
	if result.Status != "failed" || !strings.Contains(result.Result, "missing_binary") {
		t.Fatalf("expected missing binary status: %+v", result)
	}
}

func TestVerifyEasyTierStatusActiveWithFakeRunner(t *testing.T) {
	cfg := testConfig(t)
	if err := writeFile(easyTierPath(cfg), []byte("network_name = \"edge\""), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := writeFile(easyTierServiceSystemPath(), []byte("service"), 0o644); err != nil {
		t.Fatal(err)
	}
	result := ExecuteTask(context.Background(), cfg, &fakeRunner{paths: map[string]bool{"easytier-core": true}}, Task{Action: "verify_easytier_status", Payload: map[string]any{}})
	if result.Status != "succeeded" || !strings.Contains(result.Result, "active") {
		t.Fatalf("expected active status: %+v", result)
	}
}

func TestApplyNetworkProfileUsesFixedSystemctlArgv(t *testing.T) {
	cfg := testConfig(t)
	cfg.EnableWriteActions = true
	runner := &fakeRunner{paths: map[string]bool{"easytier-core": true}}
	_ = ExecuteTask(context.Background(), cfg, runner, Task{Action: "apply_network_profile", Payload: map[string]any{"network_name": "edge-prod"}})
	joined := strings.Join(runner.calls, "\n")
	for _, expected := range []string{"systemctl daemon-reload", "systemctl enable edge-tunnel-easytier.service", "systemctl restart edge-tunnel-easytier.service", "systemctl is-active edge-tunnel-easytier.service"} {
		if !strings.Contains(joined, expected) {
			t.Fatalf("missing fixed call %q in %s", expected, joined)
		}
	}
	if strings.Contains(joined, "shell -c") || strings.Contains(joined, "bash -c") {
		t.Fatalf("unexpected shell usage: %s", joined)
	}
}

func TestInstallEasyTierAlreadyInstalled(t *testing.T) {
	cfg := testConfig(t)
	cfg.EnableWriteActions = true
	result := ExecuteTask(context.Background(), cfg, &fakeRunner{paths: map[string]bool{"easytier-core": true}}, Task{Action: "install_or_update_easytier", Payload: map[string]any{}})
	if result.Status != "succeeded" || !strings.Contains(result.Result, "already installed") {
		t.Fatalf("expected already installed: %+v", result)
	}
}

func TestInstallEasyTierDoesNotRequireUnzip(t *testing.T) {
	cfg := testConfig(t)
	cfg.EnableWriteActions = true
	oldInstallDir := easyTierInstallDir
	oldDownload := downloadEasyTierArchiveFunc
	easyTierInstallDir = filepath.Join(t.TempDir(), "bin")
	archive := createEasyTierArchive(t)
	downloadEasyTierArchiveFunc = func(ctx context.Context, url, dest string) error {
		raw, err := os.ReadFile(archive)
		if err != nil {
			return err
		}
		return os.WriteFile(dest, raw, 0o644)
	}
	t.Cleanup(func() {
		easyTierInstallDir = oldInstallDir
		downloadEasyTierArchiveFunc = oldDownload
	})
	runner := &installRunner{installDir: easyTierInstallDir}
	result := ExecuteTask(context.Background(), cfg, runner, Task{Action: "install_or_update_easytier", Payload: map[string]any{}})
	if result.Status != "succeeded" {
		t.Fatalf("expected install without unzip: %+v", result)
	}
	if strings.Contains(strings.Join(runner.calls, "\n"), "unzip") {
		t.Fatalf("install should not call system unzip: %s", strings.Join(runner.calls, "\n"))
	}
}

func TestApplyNetworkProfileAutoInstallCalledWhenMissingBinary(t *testing.T) {
	cfg := testConfig(t)
	cfg.EnableWriteActions = true
	oldInstallDir := easyTierInstallDir
	oldDownload := downloadEasyTierArchiveFunc
	easyTierInstallDir = filepath.Join(t.TempDir(), "bin")
	archive := createEasyTierArchive(t)
	downloadEasyTierArchiveFunc = func(ctx context.Context, url, dest string) error {
		raw, err := os.ReadFile(archive)
		if err != nil {
			return err
		}
		return os.WriteFile(dest, raw, 0o644)
	}
	t.Cleanup(func() {
		easyTierInstallDir = oldInstallDir
		downloadEasyTierArchiveFunc = oldDownload
	})
	runner := &installRunner{installDir: easyTierInstallDir}
	result := ExecuteTask(context.Background(), cfg, runner, Task{Action: "apply_network_profile", Payload: map[string]any{"network_name": "edge-prod", "network_secret": "secret"}})
	if result.Status != "succeeded" {
		t.Fatalf("expected auto install apply success: %+v", result)
	}
	joined := strings.Join(runner.calls, "\n")
	if strings.Contains(joined, "unzip") {
		t.Fatalf("unexpected unzip call: %s", joined)
	}
}

func TestInstallEasyTierArchiveMissingCoreFails(t *testing.T) {
	cfg := testConfig(t)
	cfg.EnableWriteActions = true
	oldDownload := downloadEasyTierArchiveFunc
	archive := createEasyTierArchiveWithFiles(t, []string{"pkg/easytier-cli"})
	downloadEasyTierArchiveFunc = func(ctx context.Context, url, dest string) error {
		raw, err := os.ReadFile(archive)
		if err != nil {
			return err
		}
		return os.WriteFile(dest, raw, 0o644)
	}
	t.Cleanup(func() { downloadEasyTierArchiveFunc = oldDownload })
	result := ExecuteTask(context.Background(), cfg, &installRunner{}, Task{Action: "install_or_update_easytier", Payload: map[string]any{}})
	if result.Status != "failed" || !strings.Contains(result.Error, "easytier-core") {
		t.Fatalf("expected missing core failure: %+v", result)
	}
}

func TestSelectInstallTempDirPrefersStateDir(t *testing.T) {
	cfg := testConfig(t)
	oldDisk := diskFreeBytesFunc
	diskFreeBytesFunc = func(path string) (uint64, error) { return 300 << 20, nil }
	t.Cleanup(func() { diskFreeBytesFunc = oldDisk })
	dir, err := selectInstallTempDir(cfg, map[string]any{})
	if err != nil {
		t.Fatal(err)
	}
	if dir != filepath.Join(cfg.StateDir, "tmp") {
		t.Fatalf("expected state tmp dir, got %s", dir)
	}
}

func TestDiskSpacePreflightFailsWhenLow(t *testing.T) {
	cfg := testConfig(t)
	oldDisk := diskFreeBytesFunc
	diskFreeBytesFunc = func(path string) (uint64, error) { return 1 << 20, nil }
	t.Cleanup(func() { diskFreeBytesFunc = oldDisk })
	_, err := selectInstallTempDir(cfg, map[string]any{})
	if err == nil || !strings.Contains(err.Error(), "磁盘空间不足") {
		t.Fatalf("expected friendly low disk error, got %v", err)
	}
}

func TestCleanupOldEasyTierTempDirs(t *testing.T) {
	cfg := testConfig(t)
	old := filepath.Join(cfg.StateDir, "tmp", "edge-easytier-old")
	if err := os.MkdirAll(old, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := cleanupOldEasyTierTempDirs(cfg); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(old); !os.IsNotExist(err) {
		t.Fatalf("old temp dir still exists: %v", err)
	}
}

func TestZipExtractionBlocksPathTraversal(t *testing.T) {
	archive := createEasyTierArchiveWithFiles(t, []string{"../easytier-core"})
	err := extractZip(archive, t.TempDir())
	if err == nil || !strings.Contains(err.Error(), "unsafe path") {
		t.Fatalf("expected unsafe path error, got %v", err)
	}
}

func TestInstallEasyTierNoSpaceLeftReturnsFriendlyError(t *testing.T) {
	cfg := testConfig(t)
	cfg.EnableWriteActions = true
	oldDisk := diskFreeBytesFunc
	diskFreeBytesFunc = func(path string) (uint64, error) { return 1 << 20, nil }
	t.Cleanup(func() { diskFreeBytesFunc = oldDisk })
	result := ExecuteTask(context.Background(), cfg, &installRunner{}, Task{Action: "install_or_update_easytier", Payload: map[string]any{}})
	if result.Status != "failed" || !strings.Contains(result.Error, "磁盘空间不足") {
		t.Fatalf("expected friendly no space error: %+v", result)
	}
}

func TestRunNodePreflightAllowedWithoutWriteActions(t *testing.T) {
	cfg := testConfig(t)
	cfg.EnableWriteActions = false
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"ok":true}`))
	}))
	defer server.Close()
	cfg.ControllerURL = server.URL
	result := ExecuteTask(context.Background(), cfg, &fakeRunner{paths: map[string]bool{"systemctl": true, "ip": true}}, Task{Action: "run_node_preflight", Payload: map[string]any{}})
	if result.Status != "succeeded" || !strings.Contains(result.Result, "controller_health") {
		t.Fatalf("expected preflight success: %+v", result)
	}
}

func TestRunNodePreflightRedactsToken(t *testing.T) {
	cfg := testConfig(t)
	cfg.ControllerToken = "secret-token"
	cfg.StateDir = filepath.Join(t.TempDir(), "secret-token-state")
	result := ExecuteTask(context.Background(), cfg, &fakeRunner{}, Task{Action: "run_node_preflight", Payload: map[string]any{}})
	if strings.Contains(result.Result, "secret-token") {
		t.Fatalf("preflight leaked token: %s", result.Result)
	}
}

func TestGenerateEasyTierServiceUsesCLIArgs(t *testing.T) {
	cfg := testConfig(t)
	service := edgeTunnelEasyTierService(cfg, map[string]any{"network_name": "edge", "network_secret": "secret"}, "/usr/local/bin/easytier-core", []string{"tcp://0.0.0.0:11010"}, []string{"tcp://1.2.3.4:11010"})
	for _, want := range []string{"--network-name edge", "--network-secret secret", "-l tcp://0.0.0.0:11010", "-p tcp://1.2.3.4:11010"} {
		if !strings.Contains(service, want) {
			t.Fatalf("service missing %q: %s", want, service)
		}
	}
}

func TestGenerateEasyTierServiceIncludesPeers(t *testing.T) {
	cfg := testConfig(t)
	service := edgeTunnelEasyTierService(cfg, map[string]any{"network_name": "edge", "network_secret": "secret"}, "/usr/local/bin/easytier-core", []string{"tcp://0.0.0.0:11010", "udp://0.0.0.0:11010"}, []string{"tcp://1.2.3.4:11010", "udp://1.2.3.4:11010"})
	for _, want := range []string{"-p tcp://1.2.3.4:11010", "-p udp://1.2.3.4:11010"} {
		if !strings.Contains(service, want) {
			t.Fatalf("service missing peer %q: %s", want, service)
		}
	}
}

func TestVerifyEasyTierStatusIncludesVersion(t *testing.T) {
	cfg := testConfig(t)
	_ = writeFile(easyTierPath(cfg), []byte("network_name = \"edge\""), 0o600)
	_ = writeFile(easyTierServiceSystemPath(), []byte("service"), 0o644)
	result := ExecuteTask(context.Background(), cfg, &fakeRunner{paths: map[string]bool{"easytier-core": true}}, Task{Action: "verify_easytier_status", Payload: map[string]any{}})
	if !strings.Contains(result.Result, "version") || !strings.Contains(result.Result, "binary_path") {
		t.Fatalf("verify result missing version details: %+v", result)
	}
}

func TestVerifyEasyTierStatusUsesEasyTierCLIWhenAvailable(t *testing.T) {
	cfg := testConfig(t)
	_ = writeFile(easyTierPath(cfg), []byte("network_name = \"edge\""), 0o600)
	_ = writeFile(easyTierServiceSystemPath(), []byte("service"), 0o644)
	runner := &fakeRunner{paths: map[string]bool{"easytier-core": true, "easytier-cli": true}}
	_ = ExecuteTask(context.Background(), cfg, runner, Task{Action: "verify_easytier_status", Payload: map[string]any{}})
	joined := strings.Join(runner.calls, "\n")
	for _, want := range []string{"easytier-cli node", "easytier-cli peer", "easytier-cli route"} {
		if !strings.Contains(joined, want) {
			t.Fatalf("missing cli call %q in %s", want, joined)
		}
	}
}

func createEasyTierArchive(t *testing.T) string {
	return createEasyTierArchiveWithFiles(t, []string{"pkg/easytier-core", "pkg/easytier-cli"})
}

func createEasyTierArchiveWithFiles(t *testing.T, files []string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "easytier.zip")
	file, err := os.Create(path)
	if err != nil {
		t.Fatal(err)
	}
	zw := zip.NewWriter(file)
	for _, name := range files {
		w, err := zw.Create(name)
		if err != nil {
			t.Fatal(err)
		}
		_, _ = w.Write([]byte("#!/bin/sh\n"))
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	if err := file.Close(); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestRestartEasyTierErrorIncludesTroubleshooting(t *testing.T) {
	cfg := testConfig(t)
	cfg.EnableWriteActions = true
	result := ExecuteTask(context.Background(), cfg, &failingRunner{failName: "systemctl"}, Task{Action: "restart_easytier", Payload: map[string]any{}})
	if result.Status != "failed" || !strings.Contains(result.Result, "journalctl -u edge-tunnel-easytier") || !strings.Contains(result.Result, "systemctl is-active") {
		t.Fatalf("expected troubleshooting details: %+v", result)
	}
}

func TestVerifyEasyTierStatusDetailedFields(t *testing.T) {
	cfg := testConfig(t)
	_ = writeFile(easyTierPath(cfg), []byte("network_name = \"edge\""), 0o600)
	_ = writeFile(easyTierServiceSystemPath(), []byte("service"), 0o644)
	result := ExecuteTask(context.Background(), cfg, &fakeRunner{paths: map[string]bool{"easytier-core": true, "easytier-cli": true}}, Task{Action: "verify_easytier_status", Payload: map[string]any{}})
	for _, want := range []string{"service_exists", "service_enabled", "service_active", "config_exists", "binary_exists", "cli_exists", "binary_version", "config_path", "service_path"} {
		if !strings.Contains(result.Result, want) {
			t.Fatalf("verify result missing %s: %s", want, result.Result)
		}
	}
}

type peerRunner struct {
	fakeRunner
	peerOutput string
}

func (r *peerRunner) Run(ctx context.Context, name string, args ...string) CommandResult {
	r.calls = append(r.calls, name+" "+strings.Join(args, " "))
	if strings.HasSuffix(name, "easytier-cli") && len(args) == 1 && args[0] == "peer" {
		return CommandResult{Stdout: r.peerOutput, ExitCode: 0}
	}
	return CommandResult{Stdout: "active", ExitCode: 0}
}

func TestVerifyEasyTierStatusPeerCountLocalOnly(t *testing.T) {
	cfg := testConfig(t)
	_ = writeFile(easyTierPath(cfg), []byte("network_name = \"edge\""), 0o600)
	_ = writeFile(easyTierServiceSystemPath(), []byte("service"), 0o644)
	runner := &peerRunner{fakeRunner: fakeRunner{paths: map[string]bool{"easytier-core": true, "easytier-cli": true}}, peerOutput: "Local"}
	result := ExecuteTask(context.Background(), cfg, runner, Task{Action: "verify_easytier_status", Payload: map[string]any{}})
	if !strings.Contains(result.Result, `"peer_count":0`) || !strings.Contains(result.Result, `"has_remote_peer":false`) {
		t.Fatalf("expected no remote peer: %s", result.Result)
	}
}

func TestVerifyEasyTierStatusPeerCountRemotePeer(t *testing.T) {
	cfg := testConfig(t)
	_ = writeFile(easyTierPath(cfg), []byte("network_name = \"edge\""), 0o600)
	_ = writeFile(easyTierServiceSystemPath(), []byte("service"), 0o644)
	runner := &peerRunner{fakeRunner: fakeRunner{paths: map[string]bool{"easytier-core": true, "easytier-cli": true}}, peerOutput: "Local\npeer-remote tcp://1.2.3.4:11010"}
	result := ExecuteTask(context.Background(), cfg, runner, Task{Action: "verify_easytier_status", Payload: map[string]any{}})
	if !strings.Contains(result.Result, `"peer_count":1`) || !strings.Contains(result.Result, `"has_remote_peer":true`) {
		t.Fatalf("expected one remote peer: %s", result.Result)
	}
}

func TestAgentReportIncludesEasyTierPeerFields(t *testing.T) {
	cfg := testConfig(t)
	runner := &peerRunner{fakeRunner: fakeRunner{paths: map[string]bool{"easytier-core": true, "easytier-cli": true, "nft": true, "ip": true}}, peerOutput: "Local\npeer-remote"}
	status := CollectStatus(context.Background(), cfg, runner)
	report := ReportFromStatus(cfg, status)
	if report.EasyTierPeerCount != 1 || !report.EasyTierHasRemotePeer {
		t.Fatalf("report missing peer details: %+v", report)
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

func (f *fakeClient) Unregister(ctx context.Context, nodeID, reason string) error { return nil }

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
