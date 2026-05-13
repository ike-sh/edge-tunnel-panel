package agent

import (
	"archive/zip"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/user"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"time"
)

var systemdSystemDir = "/etc/systemd/system"
var easyTierInstallDir = "/usr/local/bin"
var downloadEasyTierArchiveFunc = downloadEasyTierArchive
var diskFreeBytesFunc = defaultDiskFreeBytes

const defaultEasyTierVersion = "v2.4.5"
const maxEasyTierDownloadBytes = 200 << 20
const minEasyTierTempBytes = 200 << 20
const minEasyTierInstallBytes = 100 << 20
const downloadSpaceReserveBytes = 50 << 20

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
	version := stringField(payload, "easytier_version", defaultEasyTierVersion)
	assetArch, err := easyTierAssetArch(runtime.GOARCH)
	if err != nil {
		return TaskResult{Status: "failed", Error: err.Error()}
	}
	asset := fmt.Sprintf("easytier-linux-%s-%s.zip", assetArch, version)
	url := easyTierDownloadURL(payload, version, asset)
	if err := cleanupOldEasyTierTempDirs(cfg); err != nil {
		return TaskResult{Status: "failed", Error: err.Error()}
	}
	workBase, err := selectInstallTempDir(cfg, payload)
	if err != nil {
		return TaskResult{Status: "failed", Error: err.Error()}
	}
	if err := os.MkdirAll(easyTierInstallDir, 0o755); err != nil {
		return TaskResult{Status: "failed", Error: err.Error()}
	}
	if err := ensureDiskSpace(easyTierInstallDir, minEasyTierInstallBytes); err != nil {
		return TaskResult{Status: "failed", Error: err.Error()}
	}
	tmp, err := os.MkdirTemp(workBase, "edge-easytier-*")
	if err != nil {
		return TaskResult{Status: "failed", Error: err.Error()}
	}
	defer os.RemoveAll(tmp)
	archivePath := filepath.Join(tmp, asset)
	if err := downloadEasyTierArchiveFunc(ctx, url, archivePath); err != nil {
		return TaskResult{Status: "failed", Error: fmt.Sprintf("download EasyTier failed: %s: %v", url, err), Result: jsonResult(map[string]any{"url": url})}
	}
	if err := extractZip(archivePath, tmp); err != nil {
		return TaskResult{Status: "failed", Error: friendlyInstallError(err, workBase, minEasyTierTempBytes).Error(), Result: jsonResult(map[string]any{"archive": archivePath})}
	}
	coreSrc, cliSrc, err := locateEasyTierBinaries(tmp)
	if err != nil {
		return TaskResult{Status: "failed", Error: err.Error()}
	}
	coreDst := filepath.Join(easyTierInstallDir, "easytier-core")
	cliDst := filepath.Join(easyTierInstallDir, "easytier-cli")
	if err := copyExecutable(coreSrc, coreDst); err != nil {
		return TaskResult{Status: "failed", Error: friendlyInstallError(err, easyTierInstallDir, minEasyTierInstallBytes).Error()}
	}
	if err := copyExecutable(cliSrc, cliDst); err != nil {
		return TaskResult{Status: "failed", Error: friendlyInstallError(err, easyTierInstallDir, minEasyTierInstallBytes).Error()}
	}
	versionResult := runner.Run(ctx, coreDst, "--version")
	if versionResult.Err != nil || versionResult.ExitCode != 0 {
		return TaskResult{Status: "failed", Stdout: versionResult.Stdout, Stderr: versionResult.Stderr, Error: "easytier-core --version failed: " + errorText(versionResult)}
	}
	cliVersion := runner.Run(ctx, cliDst, "--version")
	return TaskResult{Status: "succeeded", Result: jsonResult(map[string]any{"message": "installed", "version": version, "binary_path": coreDst, "cli_path": cliDst, "core_version": strings.TrimSpace(versionResult.Stdout + versionResult.Stderr), "cli_version": strings.TrimSpace(cliVersion.Stdout + cliVersion.Stderr), "url": url})}
}

func runNodePreflight(ctx context.Context, cfg Config, runner CommandRunner) TaskResult {
	checks := map[string]any{
		"is_root":              isRootUser(),
		"config_dir":           cfg.ConfigDir,
		"state_dir":            cfg.StateDir,
		"enable_tasks":         cfg.EnableTasks,
		"enable_write_actions": cfg.EnableWriteActions,
	}
	for _, path := range []string{"/", os.TempDir(), "/var/tmp", cfg.StateDir, easyTierInstallDir} {
		checks["disk_"+path] = diskSpaceSummary(path)
	}
	for _, name := range []string{"curl", "wget", "easytier-core", "easytier-cli", "systemctl", "nft", "ip"} {
		_, err := runner.LookPath(name)
		checks["has_"+name] = err == nil
	}
	systemdWritable := runner.Run(ctx, "test", "-w", systemdSystemDir)
	checks["systemd_dir_writable"] = systemdWritable.Err == nil && systemdWritable.ExitCode == 0
	checks["controller_health"] = controllerHealth(ctx, cfg.ControllerURL)
	raw, _ := json.Marshal(checks)
	return TaskResult{Status: "succeeded", Result: RedactString(string(raw), cfg.ControllerToken)}
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
				return TaskResult{Status: "failed", Stdout: result.Stdout, Stderr: result.Stderr, Result: "systemctl status edge-tunnel-easytier --no-pager\njournalctl -u edge-tunnel-easytier -n 100 --no-pager", Error: errorText(result)}
			}
		}
	}
	verify := verifyEasyTier(ctx, cfg, runner)
	if verify.Status != "succeeded" {
		return verify
	}
	cliPath := ""
	if found, err := findEasyTierCLI(runner); err == nil {
		cliPath = found
	}
	return TaskResult{Status: "succeeded", Result: jsonResult(map[string]any{"easytier_status": "active", "config_path": easyTierPath(cfg), "service_path": easyTierServiceSystemPath(), "binary_path": easyTierBinary, "cli_path": cliPath, "listeners": listeners, "peers": peers})}
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

func downloadEasyTierArchive(ctx context.Context, url, dest string) error {
	requestCtx, cancel := context.WithTimeout(ctx, 120*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(requestCtx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("HTTP status %s", resp.Status)
	}
	if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
		return err
	}
	if resp.ContentLength > 0 {
		required := uint64(resp.ContentLength) + downloadSpaceReserveBytes
		if err := ensureDiskSpace(filepath.Dir(dest), required); err != nil {
			return err
		}
	}
	out, err := os.Create(dest)
	if err != nil {
		return err
	}
	defer out.Close()
	limited := io.LimitReader(resp.Body, maxEasyTierDownloadBytes+1)
	n, err := io.Copy(out, limited)
	if err != nil {
		return err
	}
	if n > maxEasyTierDownloadBytes {
		return fmt.Errorf("download exceeds %d bytes", maxEasyTierDownloadBytes)
	}
	return nil
}

func extractZip(archivePath, destDir string) error {
	reader, err := zip.OpenReader(archivePath)
	if err != nil {
		return fmt.Errorf("open EasyTier zip failed: %w", err)
	}
	defer reader.Close()
	cleanDest, err := filepath.Abs(destDir)
	if err != nil {
		return err
	}
	for _, file := range reader.File {
		if strings.Contains(file.Name, "..") {
			return fmt.Errorf("unsafe path in EasyTier archive: %s", file.Name)
		}
		target := filepath.Join(destDir, file.Name)
		absTarget, err := filepath.Abs(target)
		if err != nil {
			return err
		}
		if absTarget != cleanDest && !strings.HasPrefix(absTarget, cleanDest+string(os.PathSeparator)) {
			return fmt.Errorf("unsafe path in EasyTier archive: %s", file.Name)
		}
		if file.FileInfo().IsDir() {
			if err := os.MkdirAll(absTarget, 0o755); err != nil {
				return err
			}
			continue
		}
		if filepath.Base(file.Name) != "easytier-core" && filepath.Base(file.Name) != "easytier-cli" {
			continue
		}
		if err := os.MkdirAll(filepath.Dir(absTarget), 0o755); err != nil {
			return err
		}
		src, err := file.Open()
		if err != nil {
			return err
		}
		dst, err := os.OpenFile(absTarget, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, file.FileInfo().Mode())
		if err != nil {
			src.Close()
			return err
		}
		_, copyErr := io.Copy(dst, src)
		closeErr := dst.Close()
		src.Close()
		if copyErr != nil {
			return copyErr
		}
		if closeErr != nil {
			return closeErr
		}
	}
	return nil
}

func easyTierDownloadURL(payload map[string]any, version, asset string) string {
	base := strings.TrimRight(stringField(payload, "download_base_url", "https://github.com/EasyTier/EasyTier/releases/download"), "/")
	url := base + "/" + version + "/" + asset
	if proxy := strings.TrimRight(stringField(payload, "github_proxy", ""), "/"); proxy != "" {
		return proxy + "/" + url
	}
	return url
}

func selectInstallTempDir(cfg Config, payload map[string]any) (string, error) {
	candidates := []string{}
	if tempDir := stringField(payload, "temp_dir", ""); tempDir != "" {
		if err := validateInstallTempDir(tempDir); err != nil {
			return "", err
		}
		candidates = append(candidates, tempDir)
	}
	candidates = append(candidates, filepath.Join(cfg.StateDir, "tmp"), "/var/tmp/edge-tunnel", os.TempDir())
	for _, candidate := range candidates {
		if candidate == "" {
			continue
		}
		if err := validateInstallTempDir(candidate); err != nil {
			continue
		}
		if err := os.MkdirAll(candidate, 0o700); err != nil {
			continue
		}
		if err := ensureDiskSpace(candidate, minEasyTierTempBytes); err != nil {
			continue
		}
		return candidate, nil
	}
	return "", friendlyDiskSpaceError("no suitable temp dir", minEasyTierTempBytes, 0)
}

func validateInstallTempDir(path string) error {
	if !filepath.IsAbs(path) {
		return fmt.Errorf("temp_dir must be an absolute path")
	}
	clean := filepath.Clean(path)
	for _, blocked := range []string{"/etc", "/usr", "/bin", "/sbin", "/proc", "/sys", "/dev"} {
		if clean == blocked || strings.HasPrefix(clean, blocked+string(os.PathSeparator)) {
			return fmt.Errorf("temp_dir is not allowed: %s", path)
		}
	}
	return nil
}

func cleanupOldEasyTierTempDirs(cfg Config) error {
	for _, base := range []string{os.TempDir(), "/var/tmp/edge-tunnel", filepath.Join(cfg.StateDir, "tmp")} {
		matches, err := filepath.Glob(filepath.Join(base, "edge-easytier-*"))
		if err != nil {
			return err
		}
		for _, match := range matches {
			if strings.HasPrefix(filepath.Base(match), "edge-easytier-") {
				if err := os.RemoveAll(match); err != nil {
					return err
				}
			}
		}
	}
	return nil
}

func ensureDiskSpace(path string, required uint64) error {
	available, err := diskFreeBytesFunc(path)
	if err != nil {
		return fmt.Errorf("无法读取磁盘空间：%s: %w", path, err)
	}
	if available < required {
		return friendlyDiskSpaceError(path, required, available)
	}
	return nil
}

func friendlyDiskSpaceError(path string, required, available uint64) error {
	return fmt.Errorf("磁盘空间不足，无法安装 EasyTier。\n临时目录：%s\n需要至少：%dMB\n当前可用：%dMB\n建议：\n1. 清理磁盘空间\n2. 或设置 Agent 状态目录到更大分区\n3. 或手动安装 easytier-core/easytier-cli 到 /usr/local/bin", path, required>>20, available>>20)
}

func friendlyInstallError(err error, path string, required uint64) error {
	if err == nil {
		return nil
	}
	if strings.Contains(strings.ToLower(err.Error()), "no space left on device") {
		available, _ := diskFreeBytesFunc(path)
		return friendlyDiskSpaceError(path, required, available)
	}
	return err
}

func diskSpaceSummary(path string) map[string]any {
	available, err := diskFreeBytesFunc(path)
	if err != nil {
		return map[string]any{"path": path, "ok": false, "error": err.Error()}
	}
	return map[string]any{"path": path, "ok": true, "available_mb": available >> 20}
}

func isRootUser() bool {
	current, err := user.Current()
	if err != nil {
		return false
	}
	return current.Uid == "0" || current.Username == "root"
}

func controllerHealth(ctx context.Context, controllerURL string) map[string]any {
	if strings.TrimSpace(controllerURL) == "" {
		return map[string]any{"ok": false, "error": "controller URL is empty"}
	}
	requestCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(requestCtx, http.MethodGet, strings.TrimRight(controllerURL, "/")+"/api/v1/health", nil)
	if err != nil {
		return map[string]any{"ok": false, "error": err.Error()}
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return map[string]any{"ok": false, "error": err.Error()}
	}
	defer resp.Body.Close()
	return map[string]any{"ok": resp.StatusCode >= 200 && resp.StatusCode < 300, "status": resp.Status}
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
	for _, candidate := range []string{filepath.Join(easyTierInstallDir, "easytier-core"), "/usr/bin/easytier-core"} {
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
	for _, candidate := range []string{filepath.Join(easyTierInstallDir, "easytier-cli"), "/usr/bin/easytier-cli"} {
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
