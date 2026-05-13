package agent

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
)

var systemdSystemDir = "/etc/systemd/system"
var easyTierInstallDir = "/usr/local/bin"

const defaultEasyTierVersion = "v2.4.5"

func nodePath(cfg Config) string     { return filepath.Join(cfg.ConfigDir, "node.json") }
func easyTierPath(cfg Config) string { return filepath.Join(cfg.ConfigDir, "easytier.toml") }
func networkProfilePath(cfg Config) string {
	return filepath.Join(cfg.ConfigDir, "network-profile.json")
}
func easyTierServiceConfigPath(cfg Config) string {
	return filepath.Join(cfg.ConfigDir, "systemd", "edge-tunnel-easytier.service")
}
func easyTierServiceSystemPath() string {
	return filepath.Join(systemdSystemDir, "edge-tunnel-easytier.service")
}
func entryPath(cfg Config) string   { return filepath.Join(cfg.ConfigDir, "entry.json") }
func forwardPath(cfg Config) string { return filepath.Join(cfg.ConfigDir, "forward.json") }
func forwardNFTPath(cfg Config) string {
	return filepath.Join(cfg.ConfigDir, "nftables", "edge-tunnel-forward.nft")
}
func pbrPath(cfg Config) string      { return filepath.Join(cfg.ConfigDir, "pbr.json") }
func pbrApplyPath(cfg Config) string { return filepath.Join(cfg.ConfigDir, "pbr-apply.sh") }
func ddnsPath(cfg Config) string     { return filepath.Join(cfg.ConfigDir, "ddns.json") }

func configureNodeRole(cfg Config, payload map[string]any) TaskResult {
	return writeJSONAction(nodePath(cfg), payload)
}

func installOrUpdateEasyTier(ctx context.Context, cfg Config, runner CommandRunner, payload map[string]any) TaskResult {
	if binary, err := findEasyTierCore(runner); err == nil {
		version := runner.Run(ctx, binary, "--version")
		return TaskResult{Status: "succeeded", Result: jsonResult(map[string]any{"message": "already installed", "binary_path": binary, "version": strings.TrimSpace(version.Stdout + version.Stderr)})}
	}
	if _, err := findDownloader(runner); err != nil {
		return TaskResult{Status: "failed", Error: err.Error()}
	}
	if _, err := runner.LookPath("unzip"); err != nil {
		return TaskResult{Status: "failed", Error: "missing dependency: unzip"}
	}
	version := stringField(payload, "easytier_version", defaultEasyTierVersion)
	assetArch, err := easyTierAssetArch(runtime.GOARCH)
	if err != nil {
		return TaskResult{Status: "failed", Error: err.Error()}
	}
	asset := fmt.Sprintf("easytier-linux-%s-%s.zip", assetArch, version)
	url := easyTierDownloadURL(payload, version, asset)
	tmp, err := os.MkdirTemp("", "edge-easytier-*")
	if err != nil {
		return TaskResult{Status: "failed", Error: err.Error()}
	}
	defer os.RemoveAll(tmp)
	archivePath := filepath.Join(tmp, asset)
	if result := downloadFile(ctx, runner, url, archivePath); result.Err != nil || result.ExitCode != 0 {
		return TaskResult{Status: "failed", Stdout: result.Stdout, Stderr: result.Stderr, Error: "download EasyTier failed: " + errorText(result)}
	}
	if result := runner.Run(ctx, "unzip", "-o", archivePath, "-d", tmp); result.Err != nil || result.ExitCode != 0 {
		return TaskResult{Status: "failed", Stdout: result.Stdout, Stderr: result.Stderr, Error: "unzip EasyTier failed: " + errorText(result)}
	}
	coreSrc, cliSrc, err := locateEasyTierBinaries(tmp)
	if err != nil {
		return TaskResult{Status: "failed", Error: err.Error()}
	}
	if err := os.MkdirAll(easyTierInstallDir, 0o755); err != nil {
		return TaskResult{Status: "failed", Error: err.Error()}
	}
	coreDst := filepath.Join(easyTierInstallDir, "easytier-core")
	cliDst := filepath.Join(easyTierInstallDir, "easytier-cli")
	if err := copyExecutable(coreSrc, coreDst); err != nil {
		return TaskResult{Status: "failed", Error: err.Error()}
	}
	if err := copyExecutable(cliSrc, cliDst); err != nil {
		return TaskResult{Status: "failed", Error: err.Error()}
	}
	versionResult := runner.Run(ctx, coreDst, "--version")
	if versionResult.Err != nil || versionResult.ExitCode != 0 {
		return TaskResult{Status: "failed", Stdout: versionResult.Stdout, Stderr: versionResult.Stderr, Error: "easytier-core --version failed: " + errorText(versionResult)}
	}
	return TaskResult{Status: "succeeded", Result: jsonResult(map[string]any{"message": "installed", "version": version, "binary_path": coreDst, "cli_path": cliDst})}
}

func applyNetworkProfile(ctx context.Context, cfg Config, runner CommandRunner, payload map[string]any) TaskResult {
	profile := mapPayload(payload, "network_profile")
	if len(profile) == 0 {
		profile = payload
	}
	if err := writeJSONFile(networkProfilePath(cfg), profile, 0o600); err != nil {
		return TaskResult{Status: "failed", Error: err.Error()}
	}
	if err := writeFile(easyTierPath(cfg), []byte(renderEasyTierConfig(cfg, profile)), 0o600); err != nil {
		return TaskResult{Status: "failed", Error: err.Error()}
	}
	easyTierBinary, binaryErr := findEasyTierCore(runner)
	if binaryErr != nil {
		installResult := installOrUpdateEasyTier(ctx, cfg, runner, payload)
		if installResult.Status != "succeeded" {
			installResult.Result = jsonResult(map[string]any{"config_path": easyTierPath(cfg), "profile_path": networkProfilePath(cfg), "error": installResult.Error})
			return installResult
		}
		easyTierBinary, binaryErr = findEasyTierCore(runner)
		if binaryErr != nil {
			return TaskResult{Status: "failed", Error: "easytier-core not found after install"}
		}
	}
	listeners := listenersFromProfile(profile)
	peers := peersFromProfile(profile)
	service := edgeTunnelEasyTierService(cfg, profile, easyTierBinary, listeners, peers)
	if err := writeFile(easyTierServiceConfigPath(cfg), []byte(service), 0o644); err != nil {
		return TaskResult{Status: "failed", Error: err.Error()}
	}
	if err := writeFile(easyTierServiceSystemPath(), []byte(service), 0o644); err != nil {
		return TaskResult{Status: "failed", Error: err.Error()}
	}
	if cfg.EnableWriteActions {
		for _, args := range [][]string{{"daemon-reload"}, {"enable", "edge-tunnel-easytier.service"}, {"restart", "edge-tunnel-easytier.service"}} {
			result := runner.Run(ctx, "systemctl", args...)
			if result.Err != nil || result.ExitCode != 0 {
				return TaskResult{Status: "failed", Stdout: result.Stdout, Stderr: result.Stderr, Result: "journalctl -u edge-tunnel-easytier -n 100 --no-pager", Error: errorText(result)}
			}
		}
	}
	verify := verifyEasyTier(ctx, cfg, runner)
	if verify.Status != "succeeded" {
		return verify
	}
	return TaskResult{Status: "succeeded", Result: jsonResult(map[string]any{"easytier_status": "active", "config_path": easyTierPath(cfg), "service_path": easyTierServiceSystemPath(), "binary_path": easyTierBinary, "listeners": listeners, "peers": peers})}
}

func applyForwardConfig(cfg Config, payload map[string]any) TaskResult {
	if err := writeJSONFile(forwardPath(cfg), payload, 0o600); err != nil {
		return TaskResult{Status: "failed", Error: err.Error()}
	}
	if err := writeFile(forwardNFTPath(cfg), []byte(renderForwardNFT(payload)), 0o600); err != nil {
		return TaskResult{Status: "failed", Error: err.Error()}
	}
	return TaskResult{Status: "succeeded", Result: "forward config applied"}
}

func applyPBRConfig(cfg Config, payload map[string]any) TaskResult {
	if err := writeJSONFile(pbrPath(cfg), payload, 0o600); err != nil {
		return TaskResult{Status: "failed", Error: err.Error()}
	}
	if err := writeFile(pbrApplyPath(cfg), []byte(renderPBRScript(payload)), 0o700); err != nil {
		return TaskResult{Status: "failed", Error: err.Error()}
	}
	return TaskResult{Status: "succeeded", Result: "pbr config applied"}
}

func applyDDNSConfig(cfg Config, payload map[string]any) TaskResult {
	if err := writeJSONFile(ddnsPath(cfg), RedactMap(payload), 0o600); err != nil {
		return TaskResult{Status: "failed", Error: err.Error()}
	}
	return TaskResult{Status: "succeeded", Result: "ddns config applied"}
}

func verifyFile(path string) TaskResult {
	if _, err := os.Stat(path); err != nil {
		return TaskResult{Status: "failed", Error: err.Error()}
	}
	return TaskResult{Status: "succeeded", Result: path + " exists"}
}

func verifyEasyTier(ctx context.Context, cfg Config, runner CommandRunner) TaskResult {
	binary, err := findEasyTierCore(runner)
	if err != nil {
		return TaskResult{Status: "failed", Result: `{"easytier_status":"missing_binary"}`, Error: "easytier-core not found"}
	}
	if _, err := os.Stat(easyTierPath(cfg)); err != nil {
		return TaskResult{Status: "failed", Result: `{"easytier_status":"missing_config"}`, Error: err.Error()}
	}
	if _, err := os.Stat(easyTierServiceSystemPath()); err != nil {
		return TaskResult{Status: "failed", Result: `{"easytier_status":"service_missing"}`, Error: err.Error()}
	}
	version := runner.Run(ctx, binary, "--version")
	active := runner.Run(ctx, "systemctl", "is-active", "edge-tunnel-easytier.service")
	status := map[string]any{"easytier_status": "active", "binary_path": binary, "version": strings.TrimSpace(version.Stdout + version.Stderr), "service_active": true}
	if cli, err := findEasyTierCLI(runner); err == nil {
		status["cli_path"] = cli
		status["node_info"] = strings.TrimSpace(runner.Run(ctx, cli, "node").Stdout)
		status["peer_info"] = strings.TrimSpace(runner.Run(ctx, cli, "peer").Stdout)
		status["route_info"] = strings.TrimSpace(runner.Run(ctx, cli, "route").Stdout)
	}
	if active.Err != nil || active.ExitCode != 0 {
		status["easytier_status"] = "inactive"
		status["service_active"] = false
		return TaskResult{Status: "failed", Stdout: active.Stdout, Stderr: active.Stderr, Result: jsonResult(status), Error: errorText(active)}
	}
	return TaskResult{Status: "succeeded", Stdout: active.Stdout, Stderr: active.Stderr, Result: jsonResult(status)}
}

func verifyPBR(ctx context.Context, cfg Config, runner CommandRunner) TaskResult {
	if _, err := os.Stat(pbrPath(cfg)); err != nil {
		return TaskResult{Status: "failed", Error: err.Error()}
	}
	return runFixed(ctx, runner, "ip", "rule", "show")
}

func writeJSONAction(path string, payload map[string]any) TaskResult {
	if err := writeJSONFile(path, payload, 0o600); err != nil {
		return TaskResult{Status: "failed", Error: err.Error()}
	}
	return TaskResult{Status: "succeeded", Result: path + " written"}
}

func writeJSONFile(path string, payload map[string]any, perm os.FileMode) error {
	raw, err := json.MarshalIndent(payload, "", "  ")
	if err != nil {
		return err
	}
	return writeFile(path, raw, perm)
}

func writeFile(path string, data []byte, perm os.FileMode) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, data, perm)
}

func renderEasyTierConfig(cfg Config, payload map[string]any) string {
	networkName := stringField(payload, "network_name", "edge-net")
	networkSecret := stringField(payload, "network_secret", "")
	protocol := stringField(payload, "protocol_preference", "auto")
	if protocol == "auto" || protocol == "" {
		protocol = "tcp"
	}
	listeners := listenersFromProfile(payload)
	peers := peersFromProfile(payload)
	lines := []string{
		"# Generated by Edge Tunnel Panel.",
		"# This template targets EasyTier CLI configuration. If your EasyTier version changes config fields, adjust it here.",
		fmt.Sprintf("instance_name = %q", cfg.NodeName),
		"dhcp = true",
		"listeners = [" + quoteList(listeners) + "]",
		"peer = [" + quoteList(peers) + "]",
		`rpc_portal = "127.0.0.1:15888"`,
		"",
		"[network_identity]",
		fmt.Sprintf("network_name = %q", networkName),
		fmt.Sprintf("network_secret = %q", networkSecret),
		"",
		"[flags]",
		fmt.Sprintf("default_protocol = %q", protocol),
	}
	return strings.Join(lines, "\n") + "\n"
}

func edgeTunnelEasyTierService(cfg Config, payload map[string]any, binary string, listeners, peers []string) string {
	if binary == "" {
		binary = "/usr/local/bin/easytier-core"
	}
	args := []string{binary, "--network-name", stringField(payload, "network_name", "edge-net"), "--network-secret", stringField(payload, "network_secret", "")}
	for _, listener := range listeners {
		args = append(args, "-l", listener)
	}
	for _, peer := range peers {
		args = append(args, "-p", peer)
	}
	return fmt.Sprintf("[Unit]\nDescription=Edge Tunnel EasyTier\nAfter=network-online.target\nWants=network-online.target\n\n[Service]\nType=simple\nExecStart=%s\nRestart=always\nRestartSec=5\n\n[Install]\nWantedBy=multi-user.target\n", systemdExecStart(args))
}

func renderForwardNFT(payload map[string]any) string {
	protocol := strings.ToLower(stringField(payload, "protocol", "tcp"))
	if protocol != "udp" {
		protocol = "tcp"
	}
	listenPort := intField(payload, "listen_port")
	targetHost := stringField(payload, "target_host", "127.0.0.1")
	targetPort := intField(payload, "target_port")
	return fmt.Sprintf("table ip edge_tunnel_forward {\n  chain prerouting {\n    type nat hook prerouting priority dstnat;\n    %s dport %d dnat to %s:%d\n  }\n}\n", protocol, listenPort, targetHost, targetPort)
}

func renderPBRScript(payload map[string]any) string {
	priority := intField(payload, "priority")
	tableID := intField(payload, "table_id")
	source := stringField(payload, "match_source", "")
	gateway := stringField(payload, "gateway", "")
	lines := []string{"#!/bin/sh", "set -eu"}
	if source != "" && tableID != 0 && priority != 0 {
		lines = append(lines, fmt.Sprintf("ip rule add from %s table %d priority %d || true", source, tableID, priority))
	}
	if gateway != "" && tableID != 0 {
		lines = append(lines, fmt.Sprintf("ip route replace default via %s table %d", gateway, tableID))
	}
	return strings.Join(lines, "\n") + "\n"
}

func stringField(payload map[string]any, key, fallback string) string {
	if value, ok := payload[key].(string); ok && value != "" {
		return value
	}
	return fallback
}

func mapPayload(payload map[string]any, key string) map[string]any {
	if value, ok := payload[key].(map[string]any); ok {
		return value
	}
	return nil
}

func stringSliceField(payload map[string]any, key string) []string {
	value, ok := payload[key]
	if !ok {
		return nil
	}
	switch list := value.(type) {
	case []string:
		return list
	case []any:
		out := make([]string, 0, len(list))
		for _, item := range list {
			if text, ok := item.(string); ok && strings.TrimSpace(text) != "" {
				out = append(out, text)
			}
		}
		return out
	default:
		return nil
	}
}

func quoteList(values []string) string {
	quoted := make([]string, 0, len(values))
	for _, value := range values {
		quoted = append(quoted, fmt.Sprintf("%q", value))
	}
	return strings.Join(quoted, ", ")
}

func listenersFromProfile(payload map[string]any) []string {
	listeners := stringSliceField(payload, "listeners")
	if len(listeners) == 0 {
		return []string{"tcp://0.0.0.0:11010", "udp://0.0.0.0:11010"}
	}
	return listeners
}

func peersFromProfile(payload map[string]any) []string {
	return stringSliceField(payload, "peers")
}

func systemdExecStart(args []string) string {
	escaped := make([]string, 0, len(args))
	for _, arg := range args {
		escaped = append(escaped, systemdEscape(arg))
	}
	return strings.Join(escaped, " ")
}

func systemdEscape(arg string) string {
	if arg == "" {
		return `""`
	}
	if strings.ContainsAny(arg, " \t\"'\\") {
		return strconv.Quote(arg)
	}
	return arg
}

func jsonResult(value map[string]any) string {
	raw, _ := json.Marshal(value)
	return string(raw)
}

func findDownloader(runner CommandRunner) (string, error) {
	if _, err := runner.LookPath("curl"); err == nil {
		return "curl", nil
	}
	if _, err := runner.LookPath("wget"); err == nil {
		return "wget", nil
	}
	return "", fmt.Errorf("missing dependency: curl or wget")
}

func downloadFile(ctx context.Context, runner CommandRunner, url, dest string) CommandResult {
	if _, err := runner.LookPath("curl"); err == nil {
		return runner.Run(ctx, "curl", "-fL", url, "-o", dest)
	}
	return runner.Run(ctx, "wget", "-O", dest, url)
}

func easyTierAssetArch(goarch string) (string, error) {
	switch goarch {
	case "amd64":
		return "x86_64", nil
	case "arm64":
		return "aarch64", nil
	default:
		return "", fmt.Errorf("unsupported EasyTier architecture: %s", goarch)
	}
}

func easyTierDownloadURL(payload map[string]any, version, asset string) string {
	base := strings.TrimRight(stringField(payload, "download_base_url", "https://github.com/EasyTier/EasyTier/releases/download"), "/")
	url := base + "/" + version + "/" + asset
	if proxy := strings.TrimRight(stringField(payload, "github_proxy", ""), "/"); proxy != "" {
		return proxy + "/" + url
	}
	return url
}

func locateEasyTierBinaries(root string) (string, string, error) {
	var corePath, cliPath string
	err := filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return err
		}
		switch d.Name() {
		case "easytier-core":
			corePath = path
		case "easytier-cli":
			cliPath = path
		}
		return nil
	})
	if err != nil {
		return "", "", err
	}
	if corePath == "" || cliPath == "" {
		return "", "", fmt.Errorf("EasyTier archive missing easytier-core or easytier-cli")
	}
	return corePath, cliPath, nil
}

func copyExecutable(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	var buf bytes.Buffer
	if _, err := io.Copy(&buf, in); err != nil {
		return err
	}
	if err := os.WriteFile(dst, buf.Bytes(), 0o755); err != nil {
		return err
	}
	return os.Chmod(dst, 0o755)
}

func findEasyTierCore(runner CommandRunner) (string, error) {
	for _, candidate := range []string{"/usr/local/bin/easytier-core", "/usr/bin/easytier-core"} {
		if _, err := os.Stat(candidate); err == nil {
			return candidate, nil
		}
	}
	if path, err := runner.LookPath("easytier-core"); err == nil {
		return path, nil
	}
	return "", fmt.Errorf("easytier-core not found")
}

func findEasyTierCLI(runner CommandRunner) (string, error) {
	for _, candidate := range []string{"/usr/local/bin/easytier-cli", "/usr/bin/easytier-cli"} {
		if _, err := os.Stat(candidate); err == nil {
			return candidate, nil
		}
	}
	if path, err := runner.LookPath("easytier-cli"); err == nil {
		return path, nil
	}
	return "", fmt.Errorf("easytier-cli not found")
}

func intField(payload map[string]any, key string) int {
	switch value := payload[key].(type) {
	case int:
		return value
	case float64:
		return int(value)
	default:
		return 0
	}
}
