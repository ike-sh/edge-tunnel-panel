package agent

import (
	"archive/zip"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/netip"
	"os"
	"os/user"
	"path/filepath"
	"regexp"
	"runtime"
	"strconv"
	"strings"
	"time"
)

var systemdSystemDir = "/etc/systemd/system"
var easyTierInstallDir = "/usr/local/bin"
var forwardSysctlConfigPath = "/etc/sysctl.d/99-edge-tunnel-forward.conf"
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
func forwardRuleStagePath(cfg Config, ruleID, stage string) string {
	if ruleID == "" {
		ruleID = "forward"
	}
	if stage == "" {
		stage = "entry"
	}
	return filepath.Join(cfg.ConfigDir, "forwards.d", safeFilePart(ruleID)+"-"+safeFilePart(stage)+".json")
}
func entryForwardNFTPath(cfg Config) string {
	return filepath.Join(cfg.ConfigDir, "nftables", "edge-tunnel-entry-forward.nft")
}
func landingForwardNFTPath(cfg Config) string {
	return filepath.Join(cfg.ConfigDir, "nftables", "edge-tunnel-landing-forward.nft")
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

func applyForwardConfig(ctx context.Context, cfg Config, runner CommandRunner, payload map[string]any) TaskResult {
	rule := mapPayload(payload, "forward_rule")
	if len(rule) == 0 {
		rule = payload
	}
	targetHost := normalizeHostIP(stringField(rule, "target_host", stringField(rule, "target_ip", "")))
	if targetHost == "" {
		return TaskResult{Status: "failed", Error: "target_host is required"}
	}
	if strings.Contains(targetHost, "/") {
		return TaskResult{Status: "failed", Error: "target_host must be host address, got CIDR: " + targetHost}
	}
	if ip := net.ParseIP(targetHost); ip == nil || ip.To4() == nil {
		return TaskResult{Status: "failed", Error: "当前 nftables 转发 MVP 仅支持 IPv4 目标地址: " + targetHost}
	}
	rule["target_ip"] = targetHost
	rule["target_host"] = targetHost
	warnings, preflightErr := forwardPreflightForTable(ctx, runner, "edge_tunnel_forward", intField(rule, "listen_port"))
	if preflightErr != nil {
		return TaskResult{Status: "failed", Error: preflightErr.Error(), Result: jsonResult(map[string]any{"listen_port": intField(rule, "listen_port"), "target_ip": targetHost, "target_host": targetHost, "target_port": intField(rule, "target_port"), "warnings": warnings})}
	}
	if err := writeJSONFile(forwardPath(cfg), rule, 0o600); err != nil {
		return TaskResult{Status: "failed", Error: err.Error()}
	}
	nftContent := renderForwardNFT(rule)
	if err := writeFile(forwardNFTPath(cfg), []byte(nftContent), 0o600); err != nil {
		return TaskResult{Status: "failed", Error: err.Error()}
	}
	ipForwardBefore := readIPv4Forwarding()
	ipForwardChanged := false
	if cfg.EnableWriteActions && strings.TrimSpace(ipForwardBefore) != "1" {
		if err := writeFile(forwardSysctlConfigPath, []byte("net.ipv4.ip_forward=1\n"), 0o644); err != nil {
			return TaskResult{Status: "failed", Error: err.Error(), Result: jsonResult(map[string]any{"ip_forward_before": ipForwardBefore, "ip_forward_changed": false})}
		}
		sysctl := runner.Run(ctx, "sysctl", "-w", "net.ipv4.ip_forward=1")
		if sysctl.Err != nil || sysctl.ExitCode != 0 {
			return TaskResult{Status: "failed", Stdout: sysctl.Stdout, Stderr: sysctl.Stderr, Error: "enable ip_forward failed: " + errorText(sysctl), Result: jsonResult(map[string]any{"ip_forward_before": ipForwardBefore, "ip_forward_changed": false})}
		}
		ipForwardChanged = true
	}
	check := runner.Run(ctx, "nft", "-c", "-f", forwardNFTPath(cfg))
	if check.Err != nil || check.ExitCode != 0 {
		return TaskResult{Status: "failed", Stdout: check.Stdout, Stderr: check.Stderr, Error: "nft syntax check failed: " + errorText(check), Result: jsonResult(map[string]any{"config_path": forwardPath(cfg), "nft_path": forwardNFTPath(cfg), "nft_check_ok": false, "nft_check_stdout": check.Stdout, "nft_check_stderr": check.Stderr, "nft_content": nftContent, "applied": false})}
	}
	apply := runner.Run(ctx, "nft", "-f", forwardNFTPath(cfg))
	if apply.Err != nil || apply.ExitCode != 0 {
		return TaskResult{Status: "failed", Stdout: apply.Stdout, Stderr: apply.Stderr, Error: "nft apply failed: " + errorText(apply), Result: jsonResult(map[string]any{"config_path": forwardPath(cfg), "nft_path": forwardNFTPath(cfg), "nft_check_ok": true, "nft_apply_stdout": apply.Stdout, "nft_apply_stderr": apply.Stderr, "nft_content": nftContent, "applied": false})}
	}
	ipForwardAfter := readIPv4Forwarding()
	if ipForwardAfter == "" {
		ipForward := runner.Run(ctx, "sysctl", "-n", "net.ipv4.ip_forward")
		ipForwardAfter = strings.TrimSpace(ipForward.Stdout)
	}
	if strings.TrimSpace(ipForwardAfter) != "1" {
		warnings = append(warnings, "net.ipv4.ip_forward is not enabled; forwarding may not work until IP forwarding is enabled")
	}
	return TaskResult{Status: "succeeded", Stdout: strings.TrimSpace(check.Stdout + "\n" + apply.Stdout), Stderr: strings.TrimSpace(check.Stderr + "\n" + apply.Stderr), Result: jsonResult(map[string]any{"config_path": forwardPath(cfg), "nft_path": forwardNFTPath(cfg), "nft_check_ok": true, "applied": true, "warnings": warnings, "listen_port": intField(rule, "listen_port"), "target_ip": targetHost, "target_host": targetHost, "target_port": intField(rule, "target_port"), "ip_forward_before": ipForwardBefore, "ip_forward_after": ipForwardAfter, "ip_forward_changed": ipForwardChanged})}
}

func forwardPreflightForTable(ctx context.Context, runner CommandRunner, tableName string, listenPort int) ([]string, error) {
	warnings := []string{}
	if listenPort <= 0 {
		return warnings, nil
	}
	portNeedle := ":" + strconv.Itoa(listenPort)
	if ss := runner.Run(ctx, "ss", "-lntup"); ss.Err == nil && ss.ExitCode == 0 {
		if strings.Contains(ss.Stdout, portNeedle) || strings.Contains(ss.Stderr, portNeedle) {
			return warnings, fmt.Errorf("\u7aef\u53e3\u5df2\u88ab\u5360\u7528\u6216\u5df2\u6709\u8f6c\u53d1\u89c4\u5219\uff0c\u8bf7\u66f4\u6362\u7aef\u53e3\uff1a%d", listenPort)
		}
	} else {
		warnings = append(warnings, "ss unavailable; skipped process port preflight")
	}
	if tableName == "" {
		tableName = "edge_tunnel_forward"
	}
	if nft := runner.Run(ctx, "nft", "list", "table", "inet", tableName); nft.Err == nil && nft.ExitCode == 0 {
		if strings.Contains(nft.Stdout, "dport "+strconv.Itoa(listenPort)) || strings.Contains(nft.Stderr, "dport "+strconv.Itoa(listenPort)) {
			return warnings, fmt.Errorf("\u7aef\u53e3\u5df2\u88ab\u5360\u7528\u6216\u5df2\u6709\u8f6c\u53d1\u89c4\u5219\uff0c\u8bf7\u66f4\u6362\u7aef\u53e3\uff1a%d", listenPort)
		}
	} else {
		warnings = append(warnings, "nft table unavailable before apply; it may be created on first apply")
	}
	return warnings, nil
}

func applyEntryForwardConfig(ctx context.Context, cfg Config, runner CommandRunner, payload map[string]any) TaskResult {
	rule := mapPayload(payload, "forward_rule")
	if len(rule) == 0 {
		rule = payload
	}
	ruleID := firstNonEmptyString(stringField(rule, "id", ""), stringField(payload, "rule_id", ""), stringField(payload, "forward_id", ""))
	protocol := strings.ToLower(firstNonEmptyString(stringField(payload, "protocol", ""), stringField(rule, "protocol", "tcp")))
	listenPort := firstNonZeroInt(intField(payload, "public_listen_port"), intField(rule, "public_listen_port"), intField(rule, "listen_port"))
	targetHost := normalizeHostIP(firstNonEmptyString(stringField(payload, "tunnel_target_host", ""), stringField(rule, "tunnel_target_host", ""), stringField(rule, "target_host", ""), stringField(rule, "target_ip", "")))
	targetPort := firstNonZeroInt(intField(payload, "tunnel_target_port"), intField(rule, "tunnel_target_port"), intField(rule, "public_listen_port"), intField(rule, "listen_port"))
	if err := validateIPv4ForwardTarget(targetHost, "A \u5230 B \u7684\u76ee\u6807\u5730\u5740"); err != nil {
		return TaskResult{Status: "failed", Error: err.Error()}
	}
	if !validAgentPort(listenPort) || !validAgentPort(targetPort) {
		return TaskResult{Status: "failed", Error: "public_listen_port and tunnel_target_port must be 1-65535"}
	}
	warnings, preflightErr := forwardPreflightForTable(ctx, runner, "edge_tunnel_entry_forward", listenPort)
	if preflightErr != nil {
		return TaskResult{Status: "failed", Error: preflightErr.Error(), Result: jsonResult(map[string]any{"stage": "entry", "listen_port": listenPort, "target_host": targetHost, "target_port": targetPort, "warnings": warnings})}
	}
	configPath := forwardRuleStagePath(cfg, ruleID, "entry")
	entryPayload := map[string]any{"stage": "entry", "rule_id": ruleID, "protocol": protocol, "public_listen_port": listenPort, "tunnel_target_host": targetHost, "tunnel_target_port": targetPort}
	if err := writeJSONFile(configPath, entryPayload, 0o600); err != nil {
		return TaskResult{Status: "failed", Error: err.Error()}
	}
	nftPath := entryForwardNFTPath(cfg)
	nftContent := renderStageForwardNFT("edge_tunnel_entry_forward", protocol, listenPort, targetHost, targetPort)
	return applyForwardNFT(ctx, cfg, runner, nftPath, nftContent, map[string]any{"stage": "entry", "rule_id": ruleID, "config_path": configPath, "nft_path": nftPath, "listen_port": listenPort, "target_host": targetHost, "target_port": targetPort, "warnings": warnings})
}

func applyLandingForwardConfig(ctx context.Context, cfg Config, runner CommandRunner, payload map[string]any) TaskResult {
	rule := mapPayload(payload, "forward_rule")
	if len(rule) == 0 {
		rule = payload
	}
	ruleID := firstNonEmptyString(stringField(rule, "id", ""), stringField(payload, "rule_id", ""), stringField(payload, "forward_id", ""))
	protocol := strings.ToLower(firstNonEmptyString(stringField(payload, "protocol", ""), stringField(rule, "protocol", "tcp")))
	listenPort := firstNonZeroInt(intField(payload, "tunnel_listen_port"), intField(rule, "tunnel_target_port"), intField(rule, "public_listen_port"), intField(rule, "listen_port"))
	landingRaw := strings.TrimSpace(firstNonEmptyString(stringField(payload, "landing_host_raw", ""), stringField(rule, "landing_host_raw", ""), stringField(rule, "landing_host", "")))
	landingPort := firstNonZeroInt(intField(payload, "landing_port"), intField(rule, "landing_port"), intField(rule, "target_port"))
	targetHost, err := resolveLandingHostIPv4(landingRaw)
	if err != nil {
		return TaskResult{Status: "failed", Error: err.Error(), Result: jsonResult(map[string]any{"stage": "landing", "landing_host_raw": landingRaw, "landing_port": landingPort})}
	}
	if !validAgentPort(listenPort) || !validAgentPort(landingPort) {
		return TaskResult{Status: "failed", Error: "tunnel_listen_port and landing_port must be 1-65535"}
	}
	warnings, preflightErr := forwardPreflightForTable(ctx, runner, "edge_tunnel_landing_forward", listenPort)
	if preflightErr != nil {
		return TaskResult{Status: "failed", Error: preflightErr.Error(), Result: jsonResult(map[string]any{"stage": "landing", "listen_port": listenPort, "landing_host_raw": landingRaw, "landing_host_resolved": targetHost, "landing_port": landingPort, "warnings": warnings})}
	}
	configPath := forwardRuleStagePath(cfg, ruleID, "landing")
	landingPayload := map[string]any{"stage": "landing", "rule_id": ruleID, "protocol": protocol, "tunnel_listen_port": listenPort, "landing_host_raw": landingRaw, "landing_host_resolved": targetHost, "landing_port": landingPort}
	if err := writeJSONFile(configPath, landingPayload, 0o600); err != nil {
		return TaskResult{Status: "failed", Error: err.Error()}
	}
	nftPath := landingForwardNFTPath(cfg)
	nftContent := renderStageForwardNFT("edge_tunnel_landing_forward", protocol, listenPort, targetHost, landingPort)
	return applyForwardNFT(ctx, cfg, runner, nftPath, nftContent, map[string]any{"stage": "landing", "rule_id": ruleID, "config_path": configPath, "nft_path": nftPath, "listen_port": listenPort, "landing_host_raw": landingRaw, "landing_host_resolved": targetHost, "target_host": targetHost, "target_port": landingPort, "warnings": warnings})
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
	status := map[string]any{
		"config_path":    easyTierPath(cfg),
		"service_path":   easyTierServiceSystemPath(),
		"binary_exists":  err == nil,
		"config_exists":  false,
		"service_exists": false,
		"cli_exists":     false,
	}
	if err != nil {
		status["easytier_status"] = "missing_binary"
		return TaskResult{Status: "failed", Result: jsonResult(status), Error: "easytier-core not found"}
	}
	status["binary_path"] = binary
	if _, err := os.Stat(easyTierPath(cfg)); err != nil {
		status["easytier_status"] = "missing_config"
		return TaskResult{Status: "failed", Result: jsonResult(status), Error: err.Error()}
	}
	status["config_exists"] = true
	if _, err := os.Stat(easyTierServiceSystemPath()); err != nil {
		status["easytier_status"] = "service_missing"
		return TaskResult{Status: "failed", Result: jsonResult(status), Error: err.Error()}
	}
	status["service_exists"] = true
	version := runner.Run(ctx, binary, "--version")
	enabled := runner.Run(ctx, "systemctl", "is-enabled", "edge-tunnel-easytier.service")
	active := runner.Run(ctx, "systemctl", "is-active", "edge-tunnel-easytier.service")
	status["easytier_status"] = "active"
	status["binary_version"] = strings.TrimSpace(version.Stdout + version.Stderr)
	status["version"] = status["binary_version"]
	status["service_enabled"] = enabled.Err == nil && enabled.ExitCode == 0
	status["service_active"] = true
	if cli, err := findEasyTierCLI(runner); err == nil {
		status["cli_exists"] = true
		status["cli_path"] = cli
		diagnostics := easyTierDiagnosticsFromCLI(ctx, runner, cli, true)
		status["node_info"] = diagnostics.NodeInfoRaw
		status["node_info_raw"] = diagnostics.NodeInfoRaw
		status["peer_info"] = diagnostics.PeerInfoRaw
		status["peer_info_raw"] = diagnostics.PeerInfoRaw
		status["route_info"] = diagnostics.RouteInfoRaw
		status["route_info_raw"] = diagnostics.RouteInfoRaw
		status["peer_count"] = diagnostics.PeerCount
		status["has_remote_peer"] = diagnostics.HasRemotePeer
		status["best_latency_ms"] = diagnostics.BestLatencyMS
		status["packet_loss"] = diagnostics.PacketLoss
		status["tunnels"] = diagnostics.Tunnels
		status["route_type"] = diagnostics.RouteType
		status["network_ok"] = diagnostics.NetworkOK
		status["network_reason"] = diagnostics.Reason
		status["remote_peers"] = diagnostics.RemotePeers
		status["virtual_ip"] = diagnostics.VirtualIP
		status["easytier_ip"] = diagnostics.VirtualIP
	} else {
		status["peer_count"] = 0
		status["has_remote_peer"] = false
		status["network_ok"] = false
		status["network_reason"] = "easytier-cli not found"
	}
	if active.Err != nil || active.ExitCode != 0 {
		status["easytier_status"] = "inactive"
		status["service_active"] = false
		status["network_ok"] = false
		status["network_reason"] = "EasyTier service is not running"
		return TaskResult{Status: "failed", Stdout: active.Stdout, Stderr: active.Stderr, Result: jsonResult(status), Error: errorText(active)}
	}
	return TaskResult{Status: "succeeded", Stdout: active.Stdout, Stderr: active.Stderr, Result: jsonResult(status)}
}

func verifyNetworkConnectivity(ctx context.Context, cfg Config, runner CommandRunner) TaskResult {
	diagnostics := EasyTierDiagnostics{EasyTierStatus: "unknown", NetworkOK: false}
	if _, err := findEasyTierCore(runner); err != nil {
		diagnostics.EasyTierStatus = "missing_binary"
		diagnostics.Reason = "easytier-core not found"
		return TaskResult{Status: "failed", Result: jsonResult(structMap(diagnostics)), Error: diagnostics.Reason}
	}
	active := runner.Run(ctx, "systemctl", "is-active", "edge-tunnel-easytier.service")
	if active.Err != nil || active.ExitCode != 0 || strings.TrimSpace(active.Stdout) != "active" {
		diagnostics.EasyTierStatus = "inactive"
		diagnostics.Reason = "EasyTier service is not running"
		return TaskResult{Status: "failed", Stdout: active.Stdout, Stderr: active.Stderr, Result: jsonResult(structMap(diagnostics)), Error: diagnostics.Reason}
	}
	cli, err := findEasyTierCLI(runner)
	if err != nil {
		diagnostics.EasyTierStatus = "active"
		diagnostics.Reason = "easytier-cli not found"
		return TaskResult{Status: "failed", Result: jsonResult(structMap(diagnostics)), Error: diagnostics.Reason}
	}
	diagnostics = easyTierDiagnosticsFromCLI(ctx, runner, cli, true)
	diagnostics.EasyTierStatus = "active"
	if diagnostics.NetworkOK {
		return TaskResult{Status: "succeeded", Stdout: active.Stdout, Stderr: active.Stderr, Result: jsonResult(structMap(diagnostics))}
	}
	return TaskResult{Status: "failed", Stdout: active.Stdout, Stderr: active.Stderr, Result: jsonResult(structMap(diagnostics)), Error: diagnostics.Reason}
}

func countRemotePeers(peerInfo string) int {
	return len(parseEasyTierPeers(peerInfo))
}

func easyTierDiagnosticsFromCLI(ctx context.Context, runner CommandRunner, cli string, serviceActive bool) EasyTierDiagnostics {
	node := runner.Run(ctx, cli, "node")
	peer := runner.Run(ctx, cli, "peer")
	route := runner.Run(ctx, cli, "route")
	peers := parseEasyTierPeers(strings.TrimSpace(peer.Stdout + "\n" + peer.Stderr))
	routes := parseEasyTierRoutes(strings.TrimSpace(route.Stdout + "\n" + route.Stderr))
	diagnostics := EasyTierDiagnostics{
		EasyTierStatus: "active",
		PeerCount:      len(peers),
		HasRemotePeer:  len(peers) > 0,
		RemotePeers:    peers,
		Routes:         routes,
		NodeInfoRaw:    strings.TrimSpace(node.Stdout + "\n" + node.Stderr),
		PeerInfoRaw:    strings.TrimSpace(peer.Stdout + "\n" + peer.Stderr),
		RouteInfoRaw:   strings.TrimSpace(route.Stdout + "\n" + route.Stderr),
		RouteType:      "unknown",
	}
	diagnostics.VirtualIP = parseEasyTierVirtualIP(diagnostics.NodeInfoRaw)
	if !serviceActive {
		diagnostics.EasyTierStatus = "inactive"
		diagnostics.Reason = "EasyTier service is not running"
		return diagnostics
	}
	if len(peers) == 0 {
		diagnostics.Reason = "EasyTier is running, but no remote Peer was found."
		return diagnostics
	}
	if len(routes) == 0 {
		diagnostics.Reason = "EasyTier found remote Peer, but no usable route was found."
		diagnostics.BestLatencyMS = bestPeerLatency(peers)
		diagnostics.PacketLoss = bestPeerLoss(peers)
		diagnostics.Tunnels = uniqueTunnels(peers)
		return diagnostics
	}
	diagnostics.NetworkOK = true
	diagnostics.Reason = "network connected"
	diagnostics.BestLatencyMS = bestPeerLatency(peers)
	diagnostics.PacketLoss = bestPeerLoss(peers)
	diagnostics.Tunnels = uniqueTunnels(peers)
	if len(routes) > 0 {
		diagnostics.RouteType = routes[0].RouteType
	}
	if diagnostics.RouteType == "" {
		diagnostics.RouteType = "unknown"
	}
	return diagnostics
}
func parseEasyTierPeers(peerInfo string) []EasyTierPeer {
	if rows := markdownTableRows(peerInfo); len(rows) > 0 {
		peers := make([]EasyTierPeer, 0, len(rows))
		for _, row := range rows {
			cost := row["cost"]
			if strings.EqualFold(cost, "local") {
				continue
			}
			peer := EasyTierPeer{
				IPv4:      row["ipv4"],
				Hostname:  row["hostname"],
				Cost:      cost,
				LatencyMS: parseLatency(row["lat(ms)"]),
				Loss:      cleanLossValue(row["loss"]),
				RX:        row["rx"],
				TX:        row["tx"],
				NAT:       firstString(row["nat"], row["NAT"]),
				Version:   row["version"],
			}
			if validTunnelValue(row["tunnel"]) {
				peer.Tunnel = strings.TrimSpace(row["tunnel"])
				peer.Tunnels = splitTunnelList(peer.Tunnel)
			}
			if peer.Hostname == "" && peer.IPv4 == "" {
				continue
			}
			peers = append(peers, peer)
		}
		return peers
	}
	peers := []EasyTierPeer{}
	for _, line := range strings.Split(peerInfo, "\n") {
		fields := easyTierTableFields(line)
		trimmed := strings.TrimSpace(strings.Join(fields, " "))
		lower := strings.ToLower(trimmed)
		if len(fields) == 0 || strings.Contains(lower, "peerid") || strings.Contains(lower, "peer id") || strings.Contains(lower, "cost") && strings.Contains(lower, "hostname") {
			continue
		}
		if containsFold(fields, "local") || looksLikeTableBorder(fields) {
			continue
		}
		peer := EasyTierPeer{Hostname: fields[0]}
		if len(fields) > 1 {
			peer.Cost = fields[1]
		}
		if len(fields) > 2 {
			peer.LatencyMS = parseLatency(fields[2])
		}
		if len(fields) > 3 {
			peer.Loss = cleanLossValue(fields[3])
		}
		if len(fields) > 4 {
			peer.RX = fields[4]
			if len(fields) > 5 && isSizeUnit(fields[5]) {
				peer.RX += " " + fields[5]
			}
		}
		if len(fields) > 6 {
			peer.TX = fields[6]
			if len(fields) > 7 && isSizeUnit(fields[7]) {
				peer.TX += " " + fields[7]
			}
		}
		if len(fields) > 8 && validTunnelValue(fields[8]) {
			peer.Tunnel = fields[8]
			peer.Tunnels = splitTunnelList(peer.Tunnel)
		}
		if len(fields) > 9 {
			peer.NAT = fields[9]
		}
		if len(fields) > 10 {
			peer.Version = fields[10]
		}
		peers = append(peers, peer)
	}
	return peers
}

func parseEasyTierRoutes(routeInfo string) []EasyTierRoute {
	if rows := markdownTableRows(routeInfo); len(rows) > 0 {
		routes := make([]EasyTierRoute, 0, len(rows))
		for _, row := range rows {
			routeType := routeTypeFromValues(row)
			route := EasyTierRoute{
				NextHopHostname: firstString(row["next_hop_hostname"], row["next_hop_ipv4"], row["hostname"]),
				NextHopLatency:  parseLatency(row["next_hop_lat"]),
				PathLatency:     parseLatency(row["path_latency"]),
				RouteType:       routeType,
			}
			if route.RouteType == "" {
				route.RouteType = "unknown"
			}
			routes = append(routes, route)
		}
		return routes
	}
	routes := []EasyTierRoute{}
	for _, line := range strings.Split(routeInfo, "\n") {
		fields := easyTierTableFields(line)
		trimmed := strings.TrimSpace(strings.Join(fields, " "))
		lower := strings.ToLower(trimmed)
		if len(fields) == 0 || strings.Contains(lower, "next") && strings.Contains(lower, "path") || strings.Contains(lower, "hostname") {
			continue
		}
		if containsFold(fields, "local") || looksLikeTableBorder(fields) {
			continue
		}
		route := EasyTierRoute{RouteType: "unknown", NextHopHostname: fields[0]}
		for _, field := range fields {
			upper := strings.ToUpper(field)
			if strings.Contains(upper, "DIRECT") {
				route.RouteType = "DIRECT"
			} else if strings.Contains(strings.ToLower(field), "relay") {
				route.RouteType = "relay"
			}
		}
		if len(fields) > 1 {
			route.NextHopLatency = parseLatency(fields[1])
		}
		if len(fields) > 2 {
			route.PathLatency = parseLatency(fields[2])
		}
		routes = append(routes, route)
	}
	return routes
}

var tableSeparatorPattern = regexp.MustCompile(`^:?-+:?$`)
var lossPattern = regexp.MustCompile(`^\d+(?:\.\d+)?%$`)
var tunnelTokenPattern = regexp.MustCompile(`^(?i:tcp|udp|tcp6|udp6|wg|ws|wss|quic)$`)

func markdownTableRows(text string) []map[string]string {
	headers := []string{}
	rows := []map[string]string{}
	for _, line := range strings.Split(text, "\n") {
		cols := markdownColumns(line)
		if len(cols) == 0 || isMarkdownSeparator(cols) {
			continue
		}
		if len(headers) == 0 {
			headers = make([]string, 0, len(cols))
			for _, col := range cols {
				headers = append(headers, normalizeTableHeader(col))
			}
			continue
		}
		row := map[string]string{}
		for i, header := range headers {
			if i >= len(cols) {
				continue
			}
			row[header] = strings.TrimSpace(cols[i])
		}
		rows = append(rows, row)
	}
	return rows
}

func markdownColumns(line string) []string {
	line = strings.TrimSpace(line)
	if !strings.HasPrefix(line, "|") {
		return nil
	}
	line = strings.Trim(line, "|")
	parts := strings.Split(line, "|")
	out := make([]string, 0, len(parts))
	for _, part := range parts {
		out = append(out, strings.TrimSpace(part))
	}
	return out
}

func normalizeTableHeader(value string) string {
	value = strings.ToLower(strings.TrimSpace(value))
	value = strings.ReplaceAll(value, " ", "_")
	value = strings.ReplaceAll(value, "-", "_")
	return value
}

func isMarkdownSeparator(cols []string) bool {
	if len(cols) == 0 {
		return false
	}
	for _, col := range cols {
		if !tableSeparatorPattern.MatchString(strings.TrimSpace(col)) {
			return false
		}
	}
	return true
}

func cleanLossValue(value string) string {
	value = strings.TrimSpace(value)
	if value == "" || value == "-" {
		return ""
	}
	if lossPattern.MatchString(value) {
		return value
	}
	return ""
}

func validTunnelValue(value string) bool {
	value = strings.TrimSpace(value)
	if value == "" || value == "-" {
		return false
	}
	if strings.Contains(value, "://") {
		return true
	}
	for _, token := range strings.Split(value, ",") {
		token = strings.TrimSpace(token)
		if token == "" || !tunnelTokenPattern.MatchString(token) {
			return false
		}
	}
	return true
}

func splitTunnelList(value string) []string {
	value = strings.TrimSpace(value)
	if value == "" {
		return nil
	}
	if strings.Contains(value, "://") {
		return []string{value}
	}
	out := []string{}
	seen := map[string]bool{}
	for _, token := range strings.Split(value, ",") {
		token = strings.TrimSpace(token)
		if token == "" || !validTunnelValue(token) || seen[token] {
			continue
		}
		seen[token] = true
		out = append(out, token)
	}
	return out
}

func routeTypeFromValues(row map[string]string) string {
	for _, value := range row {
		upper := strings.ToUpper(strings.TrimSpace(value))
		switch {
		case strings.Contains(upper, "DIRECT"):
			return "DIRECT"
		case strings.Contains(strings.ToLower(value), "relay"):
			return "relay"
		}
	}
	return "unknown"
}

func firstString(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}

var virtualIPPattern = regexp.MustCompile(`\b(?:\d{1,3}\.){3}\d{1,3}(?:/\d+)?\b`)

func parseEasyTierVirtualIP(nodeInfo string) string {
	for _, line := range strings.Split(nodeInfo, "\n") {
		lower := strings.ToLower(line)
		if !strings.Contains(lower, "virtual") && !strings.Contains(lower, "ipv4") && !strings.Contains(lower, "ip") {
			continue
		}
		for _, match := range virtualIPPattern.FindAllString(line, -1) {
			ip := strings.Split(match, "/")[0]
			if ip == "0.0.0.0" || strings.HasPrefix(ip, "127.") {
				continue
			}
			return match
		}
	}
	return ""
}

func easyTierTableFields(line string) []string {
	cleaned := strings.TrimSpace(strings.ReplaceAll(line, "|", " "))
	if cleaned == "" {
		return nil
	}
	return strings.Fields(cleaned)
}

func looksLikeTableBorder(fields []string) bool {
	if len(fields) != 1 {
		return false
	}
	field := strings.Trim(fields[0], "+-=")
	return field == ""
}
func parseLatency(value string) float64 {
	value = strings.TrimSpace(strings.TrimSuffix(strings.ToLower(value), "ms"))
	value = strings.Trim(value, "[](),")
	n, _ := strconv.ParseFloat(value, 64)
	return n
}

func containsFold(fields []string, want string) bool {
	for _, field := range fields {
		if strings.EqualFold(strings.Trim(field, "[](),"), want) {
			return true
		}
	}
	return false
}

func isSizeUnit(value string) bool {
	switch strings.ToLower(strings.Trim(value, "[](),")) {
	case "b", "kb", "mb", "gb", "tb", "kib", "mib", "gib":
		return true
	default:
		return false
	}
}

func bestPeerLatency(peers []EasyTierPeer) float64 {
	best := 0.0
	for _, peer := range peers {
		if peer.LatencyMS <= 0 {
			continue
		}
		if best == 0 || peer.LatencyMS < best {
			best = peer.LatencyMS
		}
	}
	return best
}

func uniqueTunnels(peers []EasyTierPeer) []string {
	seen := map[string]bool{}
	out := []string{}
	for _, peer := range peers {
		for _, tunnel := range splitTunnelList(peer.Tunnel) {
			if tunnel == "" || seen[tunnel] {
				continue
			}
			seen[tunnel] = true
			out = append(out, tunnel)
		}
	}
	return out
}

func bestPeerLoss(peers []EasyTierPeer) string {
	bestLatency := bestPeerLatency(peers)
	for _, peer := range peers {
		if bestLatency > 0 && peer.LatencyMS != bestLatency {
			continue
		}
		if peer.Loss != "" {
			return peer.Loss
		}
	}
	for _, peer := range peers {
		if peer.Loss != "" {
			return peer.Loss
		}
	}
	return ""
}

func structMap(value any) map[string]any {
	raw, _ := json.Marshal(value)
	out := map[string]any{}
	_ = json.Unmarshal(raw, &out)
	return out
}

func restartEasyTier(ctx context.Context, runner CommandRunner) TaskResult {
	result := runner.Run(ctx, "systemctl", "restart", "edge-tunnel-easytier.service")
	active := runner.Run(ctx, "systemctl", "is-active", "edge-tunnel-easytier.service")
	if result.Err != nil || result.ExitCode != 0 || active.Err != nil || active.ExitCode != 0 {
		errorSource := result
		if result.Err == nil && result.ExitCode == 0 {
			errorSource = active
		}
		return TaskResult{
			Status: "failed",
			Stdout: strings.TrimSpace(result.Stdout + "\n" + active.Stdout),
			Stderr: strings.TrimSpace(result.Stderr + "\n" + active.Stderr),
			Error:  errorText(errorSource),
			Result: "systemctl status edge-tunnel-easytier --no-pager\njournalctl -u edge-tunnel-easytier -n 100 --no-pager\nsystemctl is-active edge-tunnel-easytier.service",
		}
	}
	return TaskResult{Status: "succeeded", Stdout: result.Stdout, Stderr: result.Stderr, Result: strings.TrimSpace(active.Stdout)}
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
	args := []string{binary, "-d"}
	if cidr := stringField(payload, "cidr", ""); cidr != "" {
		args = append(args, "-i", cidr)
	}
	args = append(args, "--network-name", stringField(payload, "network_name", "edge-net"), "--network-secret", stringField(payload, "network_secret", ""))
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
	listenPort := intField(payload, "listen_port")
	targetHost := normalizeHostIP(stringField(payload, "target_ip", stringField(payload, "target_host", "127.0.0.1")))
	targetPort := intField(payload, "target_port")
	prerouting := []string{}
	output := []string{}
	for _, proto := range forwardProtocols(protocol) {
		prerouting = append(prerouting, fmt.Sprintf("    %s dport %d dnat ip to %s:%d", proto, listenPort, targetHost, targetPort))
		output = append(output, fmt.Sprintf("    ip daddr 127.0.0.1 %s dport %d dnat ip to %s:%d", proto, listenPort, targetHost, targetPort))
	}
	return fmt.Sprintf("table inet edge_tunnel_forward {\n  chain prerouting {\n    type nat hook prerouting priority dstnat; policy accept;\n%s\n  }\n\n  chain output {\n    type nat hook output priority dstnat; policy accept;\n%s\n  }\n\n  chain postrouting {\n    type nat hook postrouting priority srcnat; policy accept;\n    ip daddr %s masquerade\n  }\n}\n", strings.Join(prerouting, "\n"), strings.Join(output, "\n"), targetHost)
}

func renderStageForwardNFT(tableName, protocol string, listenPort int, targetHost string, targetPort int) string {
	prerouting := []string{}
	output := []string{}
	for _, proto := range forwardProtocols(protocol) {
		prerouting = append(prerouting, fmt.Sprintf("    %s dport %d dnat ip to %s:%d", proto, listenPort, targetHost, targetPort))
		output = append(output, fmt.Sprintf("    ip daddr 127.0.0.1 %s dport %d dnat ip to %s:%d", proto, listenPort, targetHost, targetPort))
	}
	return fmt.Sprintf("table inet %s {\n  chain prerouting {\n    type nat hook prerouting priority dstnat; policy accept;\n%s\n  }\n\n  chain output {\n    type nat hook output priority dstnat; policy accept;\n%s\n  }\n\n  chain postrouting {\n    type nat hook postrouting priority srcnat; policy accept;\n    ip daddr %s masquerade\n  }\n}\n", tableName, strings.Join(prerouting, "\n"), strings.Join(output, "\n"), targetHost)
}

func applyForwardNFT(ctx context.Context, cfg Config, runner CommandRunner, nftPath, nftContent string, result map[string]any) TaskResult {
	if err := writeFile(nftPath, []byte(nftContent), 0o600); err != nil {
		return TaskResult{Status: "failed", Error: err.Error()}
	}
	ipForwardBefore := readIPv4Forwarding()
	ipForwardChanged := false
	if cfg.EnableWriteActions && strings.TrimSpace(ipForwardBefore) != "1" {
		if err := writeFile(forwardSysctlConfigPath, []byte("net.ipv4.ip_forward=1\n"), 0o644); err != nil {
			result["ip_forward_before"] = ipForwardBefore
			result["ip_forward_changed"] = false
			return TaskResult{Status: "failed", Error: err.Error(), Result: jsonResult(result)}
		}
		sysctl := runner.Run(ctx, "sysctl", "-w", "net.ipv4.ip_forward=1")
		if sysctl.Err != nil || sysctl.ExitCode != 0 {
			result["ip_forward_before"] = ipForwardBefore
			result["ip_forward_changed"] = false
			return TaskResult{Status: "failed", Stdout: sysctl.Stdout, Stderr: sysctl.Stderr, Error: "enable ip_forward failed: " + errorText(sysctl), Result: jsonResult(result)}
		}
		ipForwardChanged = true
	}
	check := runner.Run(ctx, "nft", "-c", "-f", nftPath)
	result["nft_content"] = nftContent
	if check.Err != nil || check.ExitCode != 0 {
		result["nft_check_ok"] = false
		result["nft_check_stdout"] = check.Stdout
		result["nft_check_stderr"] = check.Stderr
		result["applied"] = false
		return TaskResult{Status: "failed", Stdout: check.Stdout, Stderr: check.Stderr, Error: "nft syntax check failed: " + errorText(check), Result: jsonResult(result)}
	}
	apply := runner.Run(ctx, "nft", "-f", nftPath)
	if apply.Err != nil || apply.ExitCode != 0 {
		result["nft_check_ok"] = true
		result["nft_apply_stdout"] = apply.Stdout
		result["nft_apply_stderr"] = apply.Stderr
		result["applied"] = false
		return TaskResult{Status: "failed", Stdout: apply.Stdout, Stderr: apply.Stderr, Error: "nft apply failed: " + errorText(apply), Result: jsonResult(result)}
	}
	ipForwardAfter := readIPv4Forwarding()
	if ipForwardAfter == "" {
		ipForward := runner.Run(ctx, "sysctl", "-n", "net.ipv4.ip_forward")
		ipForwardAfter = strings.TrimSpace(ipForward.Stdout)
	}
	result["nft_check_ok"] = true
	result["applied"] = true
	result["ip_forward_before"] = ipForwardBefore
	result["ip_forward_after"] = ipForwardAfter
	result["ip_forward_changed"] = ipForwardChanged
	return TaskResult{Status: "succeeded", Stdout: strings.TrimSpace(check.Stdout + "\n" + apply.Stdout), Stderr: strings.TrimSpace(check.Stderr + "\n" + apply.Stderr), Result: jsonResult(result)}
}

func forwardProtocols(protocol string) []string {
	switch strings.ToLower(strings.TrimSpace(protocol)) {
	case "udp":
		return []string{"udp"}
	case "both":
		return []string{"tcp", "udp"}
	default:
		return []string{"tcp"}
	}
}

func verifyForwardRules(ctx context.Context, cfg Config, runner CommandRunner) TaskResult {
	status := map[string]any{
		"config_path":   forwardPath(cfg),
		"nft_path":      forwardNFTPath(cfg),
		"table_exists":  false,
		"rules_present": false,
	}
	if _, err := os.Stat(forwardPath(cfg)); err != nil {
		return TaskResult{Status: "failed", Result: jsonResult(status), Error: err.Error()}
	}
	if _, err := os.Stat(forwardNFTPath(cfg)); err != nil {
		return TaskResult{Status: "failed", Result: jsonResult(status), Error: err.Error()}
	}
	table := runner.Run(ctx, "nft", "list", "table", "inet", "edge_tunnel_forward")
	ipForward := readIPv4Forwarding()
	if ipForward == "" {
		result := runner.Run(ctx, "sysctl", "-n", "net.ipv4.ip_forward")
		ipForward = strings.TrimSpace(result.Stdout)
	}
	status["ip_forward"] = ipForward
	status["nft_output"] = strings.TrimSpace(table.Stdout + "\n" + table.Stderr)
	status["table_exists"] = table.Err == nil && table.ExitCode == 0
	status["rules_present"] = strings.Contains(table.Stdout, "dnat")
	status["rule_present"] = strings.Contains(table.Stdout, "dnat")
	warnings := []string{}
	if strings.TrimSpace(ipForward) != "1" {
		warnings = append(warnings, "net.ipv4.ip_forward is not enabled")
	}
	status["warnings"] = warnings
	if table.Err != nil || table.ExitCode != 0 {
		return TaskResult{Status: "failed", Stdout: table.Stdout, Stderr: table.Stderr, Result: jsonResult(status), Error: errorText(table)}
	}
	return TaskResult{Status: "succeeded", Stdout: table.Stdout, Stderr: table.Stderr, Result: jsonResult(status)}
}

func normalizeHostIP(value string) string {
	text := strings.TrimSpace(value)
	if text == "" {
		return ""
	}
	if prefix, err := netip.ParsePrefix(text); err == nil {
		return prefix.Addr().String()
	}
	if addr, err := netip.ParseAddr(text); err == nil {
		return addr.String()
	}
	return text
}

func validateIPv4ForwardTarget(target, label string) error {
	target = normalizeHostIP(target)
	if target == "" {
		return fmt.Errorf("%s\u4e0d\u80fd\u4e3a\u7a7a", label)
	}
	if strings.Contains(target, "/") {
		return fmt.Errorf("%s\u4e0d\u80fd\u662f CIDR: %s", label, target)
	}
	ip := net.ParseIP(target)
	if ip == nil || ip.To4() == nil {
		return fmt.Errorf("%s\u5fc5\u987b\u662f IPv4 \u5730\u5740: %s", label, target)
	}
	return nil
}

func resolveLandingHostIPv4(raw string) (string, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return "", fmt.Errorf("\u843d\u5730\u670d\u52a1\u5668\u5730\u5740\u4e0d\u80fd\u4e3a\u7a7a")
	}
	if strings.Contains(raw, "/") {
		return "", fmt.Errorf("\u843d\u5730\u670d\u52a1\u5668\u5730\u5740\u4e0d\u80fd\u662f CIDR: %s", raw)
	}
	if strings.Contains(raw, ":") {
		return "", fmt.Errorf("v0.2.7-test \u6682\u4e0d\u652f\u6301 IPv6 \u843d\u5730\u76ee\u6807")
	}
	if ip := net.ParseIP(raw); ip != nil {
		if ip.To4() == nil {
			return "", fmt.Errorf("v0.2.7-test \u6682\u4e0d\u652f\u6301 IPv6 \u843d\u5730\u76ee\u6807")
		}
		return ip.String(), nil
	}
	ips, err := net.LookupIP(raw)
	if err != nil {
		return "", fmt.Errorf("\u65e0\u6cd5\u89e3\u6790\u843d\u5730\u57df\u540d\u4e3a IPv4: %s: %w", raw, err)
	}
	for _, ip := range ips {
		if ip4 := ip.To4(); ip4 != nil {
			return ip4.String(), nil
		}
	}
	return "", fmt.Errorf("\u65e0\u6cd5\u89e3\u6790\u843d\u5730\u57df\u540d\u4e3a IPv4: %s", raw)
}

func firstNonEmptyString(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return strings.TrimSpace(value)
		}
	}
	return ""
}

func firstNonZeroInt(values ...int) int {
	for _, value := range values {
		if value != 0 {
			return value
		}
	}
	return 0
}

func validAgentPort(port int) bool {
	return port >= 1 && port <= 65535
}

func safeFilePart(value string) string {
	value = strings.TrimSpace(value)
	if value == "" {
		return "forward"
	}
	var b strings.Builder
	for _, r := range value {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '-' || r == '_' || r == '.' {
			b.WriteRune(r)
		} else {
			b.WriteByte('-')
		}
	}
	return b.String()
}

func readIPv4Forwarding() string {
	raw, err := os.ReadFile("/proc/sys/net/ipv4/ip_forward")
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(raw))
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
