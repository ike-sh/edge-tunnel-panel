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
var pbrRTTablesPath = "/etc/iproute2/rt_tables"
var downloadEasyTierArchiveFunc = downloadEasyTierArchive
var diskFreeBytesFunc = defaultDiskFreeBytes
var localIPv4AddressesFunc = localIPv4Addresses

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
func pbrPolicyPath(cfg Config, policyID string) string {
	if policyID == "" {
		policyID = "pbr"
	}
	return filepath.Join(cfg.ConfigDir, "pbr.d", safeFilePart(policyID)+".json")
}
func pbrNFTPath(cfg Config) string {
	return filepath.Join(cfg.ConfigDir, "nftables", "edge-tunnel-pbr.nft")
}
func mssNFTPath(cfg Config) string {
	return filepath.Join(cfg.ConfigDir, "nftables", "edge-tunnel-mss.nft")
}
func ddnsPath(cfg Config) string { return filepath.Join(cfg.ConfigDir, "ddns.json") }

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
		return TaskResult{Status: "failed", Error: "current nftables forwarding MVP supports IPv4 target addresses only: " + targetHost}
	}
	rule["target_ip"] = targetHost
	rule["target_host"] = targetHost
	warnings, preflightErr := forwardPreflightForTable(ctx, runner, intField(rule, "listen_port"))
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
	_ = runner.Run(ctx, "nft", "delete", "table", "ip", "edge_tunnel_forward")
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

func forwardPreflightForTable(ctx context.Context, runner CommandRunner, listenPort int) ([]string, error) {
	warnings := []string{}
	if listenPort <= 0 {
		return warnings, nil
	}
	portNeedle := ":" + strconv.Itoa(listenPort)
	if ss := runner.Run(ctx, "ss", "-lntup"); ss.Err == nil && ss.ExitCode == 0 {
		if strings.Contains(ss.Stdout, portNeedle) || strings.Contains(ss.Stderr, portNeedle) {
			return warnings, fmt.Errorf("port is already in use or an existing forwarding rule uses this port: %d", listenPort)
		}
	} else {
		warnings = append(warnings, "ss unavailable; skipped process port preflight")
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
	warnings, preflightErr := forwardPreflightForTable(ctx, runner, listenPort)
	if preflightErr != nil {
		return TaskResult{Status: "failed", Error: preflightErr.Error(), Result: jsonResult(map[string]any{"stage": "entry", "listen_port": listenPort, "target_host": targetHost, "target_port": targetPort, "warnings": warnings})}
	}
	configPath := forwardRuleStagePath(cfg, ruleID, "entry")
	entryPayload := map[string]any{"stage": "entry", "rule_id": ruleID, "protocol": protocol, "public_listen_port": listenPort, "tunnel_target_host": targetHost, "tunnel_target_port": targetPort}
	mssMode := stringField(payload, "mss_mode", stringField(rule, "mss_mode", "auto"))
	mtu := firstNonZeroInt(intField(payload, "mtu"), intField(rule, "mtu"), 1380)
	mssValue := firstNonZeroInt(intField(payload, "mss_value"), intField(rule, "mss_value"))
	mssEnabled := boolFieldDefault(payload, "mss_clamp_enabled", boolFieldDefault(rule, "mss_clamp_enabled", true))
	entryPayload["mss_clamp_enabled"] = mssEnabled
	entryPayload["mss_mode"] = mssMode
	entryPayload["mtu"] = mtu
	entryPayload["mss_value"] = mssValue
	if err := writeJSONFile(configPath, entryPayload, 0o600); err != nil {
		return TaskResult{Status: "failed", Error: err.Error()}
	}
	nftPath := entryForwardNFTPath(cfg)
	nftContent := renderStageForwardNFT("edge_tunnel_entry_forward", protocol, listenPort, targetHost, targetPort)
	result := applyForwardNFT(ctx, cfg, runner, "edge_tunnel_entry_forward", nftPath, nftContent, map[string]any{"stage": "entry", "rule_id": ruleID, "config_path": configPath, "nft_path": nftPath, "listen_port": listenPort, "target_host": targetHost, "target_port": targetPort, "table": "ip edge_tunnel_entry_forward", "warnings": warnings})
	return applyMSSClampIfRequested(ctx, cfg, runner, result, mssEnabled, mssMode, mtu, mssValue)
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
	warnings, preflightErr := forwardPreflightForTable(ctx, runner, listenPort)
	if preflightErr != nil {
		return TaskResult{Status: "failed", Error: preflightErr.Error(), Result: jsonResult(map[string]any{"stage": "landing", "listen_port": listenPort, "landing_host_raw": landingRaw, "landing_host_resolved": targetHost, "landing_port": landingPort, "warnings": warnings})}
	}
	configPath := forwardRuleStagePath(cfg, ruleID, "landing")
	landingPayload := map[string]any{"stage": "landing", "rule_id": ruleID, "protocol": protocol, "tunnel_listen_port": listenPort, "landing_host_raw": landingRaw, "landing_host_resolved": targetHost, "landing_port": landingPort}
	mssMode := stringField(payload, "mss_mode", stringField(rule, "mss_mode", "auto"))
	mtu := firstNonZeroInt(intField(payload, "mtu"), intField(rule, "mtu"), 1380)
	mssValue := firstNonZeroInt(intField(payload, "mss_value"), intField(rule, "mss_value"))
	mssEnabled := boolFieldDefault(payload, "mss_clamp_enabled", boolFieldDefault(rule, "mss_clamp_enabled", true))
	landingPayload["mss_clamp_enabled"] = mssEnabled
	landingPayload["mss_mode"] = mssMode
	landingPayload["mtu"] = mtu
	landingPayload["mss_value"] = mssValue
	if err := writeJSONFile(configPath, landingPayload, 0o600); err != nil {
		return TaskResult{Status: "failed", Error: err.Error()}
	}
	nftPath := landingForwardNFTPath(cfg)
	nftContent := renderStageForwardNFT("edge_tunnel_landing_forward", protocol, listenPort, targetHost, landingPort)
	result := applyForwardNFT(ctx, cfg, runner, "edge_tunnel_landing_forward", nftPath, nftContent, map[string]any{"stage": "landing", "rule_id": ruleID, "config_path": configPath, "nft_path": nftPath, "listen_port": listenPort, "landing_host_raw": landingRaw, "landing_host_resolved": targetHost, "target_host": targetHost, "target_port": landingPort, "table": "ip edge_tunnel_landing_forward", "warnings": warnings})
	return applyMSSClampIfRequested(ctx, cfg, runner, result, mssEnabled, mssMode, mtu, mssValue)
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
	return renderStageForwardNFT("edge_tunnel_forward", protocol, listenPort, targetHost, targetPort)
}

func renderStageForwardNFT(tableName, protocol string, listenPort int, targetHost string, targetPort int) string {
	prerouting := []string{}
	for _, proto := range forwardProtocols(protocol) {
		prerouting = append(prerouting, fmt.Sprintf("    %s dport %d dnat to %s:%d", proto, listenPort, targetHost, targetPort))
	}
	return fmt.Sprintf("table ip %s {\n  chain prerouting {\n    type nat hook prerouting priority -100; policy accept;\n%s\n  }\n\n  chain postrouting {\n    type nat hook postrouting priority 100; policy accept;\n    ip daddr %s masquerade\n  }\n}\n", tableName, strings.Join(prerouting, "\n"), targetHost)
}

func renderMSSClampNFT(mode string, mtu, mssValue int) (string, int, bool) {
	mode = strings.ToLower(strings.TrimSpace(mode))
	if mode == "" {
		mode = "auto"
	}
	if mode == "disabled" {
		return "", 0, false
	}
	if mtu == 0 {
		mtu = 1380
	}
	if mode == "fixed" {
		if mssValue == 0 {
			mssValue = mtu - 40
		}
		return fmt.Sprintf("table ip edge_tunnel_mss {\n  chain forward_mss {\n    type filter hook forward priority mangle; policy accept;\n    tcp flags syn tcp option maxseg size set %d\n  }\n}\n", mssValue), mssValue, true
	}
	return "table ip edge_tunnel_mss {\n  chain forward_mss {\n    type filter hook forward priority mangle; policy accept;\n    tcp flags syn tcp option maxseg size set rt mtu\n  }\n}\n", 0, true
}

func applyMSSClampIfRequested(ctx context.Context, cfg Config, runner CommandRunner, result TaskResult, enabled bool, mode string, mtu, mssValue int) TaskResult {
	if result.Status != "succeeded" || !enabled {
		return result
	}
	nftContent, fixedValue, ok := renderMSSClampNFT(mode, mtu, mssValue)
	if !ok {
		return result
	}
	mssResult := map[string]any{"mss_clamp_enabled": true, "mss_mode": mode, "mtu": mtu, "mss_value": fixedValue, "mss_nft_path": mssNFTPath(cfg), "mss_nft_content": nftContent}
	if err := writeFile(mssNFTPath(cfg), []byte(nftContent), 0o600); err != nil {
		result.Status = "failed"
		result.Error = err.Error()
		return result
	}
	_ = runner.Run(ctx, "nft", "delete", "table", "ip", "edge_tunnel_mss")
	check := runner.Run(ctx, "nft", "-c", "-f", mssNFTPath(cfg))
	if check.Err != nil || check.ExitCode != 0 {
		if strings.EqualFold(mode, "auto") {
			fallback, value, _ := renderMSSClampNFT("fixed", mtu, 0)
			mssResult["mss_mode"] = "fixed"
			mssResult["mss_value"] = value
			mssResult["mss_warning"] = "current nftables does not support rt mtu MSS clamp; fallback to fixed MSS"
			_ = writeFile(mssNFTPath(cfg), []byte(fallback), 0o600)
			nftContent = fallback
			check = runner.Run(ctx, "nft", "-c", "-f", mssNFTPath(cfg))
		}
		if check.Err != nil || check.ExitCode != 0 {
			result.Status = "failed"
			result.Stderr = strings.TrimSpace(result.Stderr + "\n" + check.Stderr)
			result.Error = "mss clamp nft syntax check failed: " + errorText(check)
			return result
		}
	}
	apply := runner.Run(ctx, "nft", "-f", mssNFTPath(cfg))
	if apply.Err != nil || apply.ExitCode != 0 {
		result.Status = "failed"
		result.Stderr = strings.TrimSpace(result.Stderr + "\n" + apply.Stderr)
		result.Error = "mss clamp nft apply failed: " + errorText(apply)
		return result
	}
	var base map[string]any
	_ = json.Unmarshal([]byte(result.Result), &base)
	if base == nil {
		base = map[string]any{}
	}
	for key, value := range mssResult {
		base[key] = value
	}
	result.Result = jsonResult(base)
	return result
}

func applyForwardNFT(ctx context.Context, cfg Config, runner CommandRunner, tableName, nftPath, nftContent string, result map[string]any) TaskResult {
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
	if tableName != "" {
		_ = runner.Run(ctx, "nft", "delete", "table", "ip", tableName)
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

func verifyForwardRules(ctx context.Context, cfg Config, runner CommandRunner, payload map[string]any) TaskResult {
	stage := strings.ToLower(strings.TrimSpace(stringField(payload, "stage", "")))
	nftPath := forwardNFTPath(cfg)
	configPath := forwardPath(cfg)
	tableName := "edge_tunnel_forward"
	switch stage {
	case "entry":
		nftPath = entryForwardNFTPath(cfg)
		tableName = "edge_tunnel_entry_forward"
		if ruleID := stringField(payload, "rule_id", stringField(payload, "forward_id", "")); ruleID != "" {
			configPath = forwardRuleStagePath(cfg, ruleID, "entry")
		} else {
			configPath = ""
		}
	case "landing":
		nftPath = landingForwardNFTPath(cfg)
		tableName = "edge_tunnel_landing_forward"
		if ruleID := stringField(payload, "rule_id", stringField(payload, "forward_id", "")); ruleID != "" {
			configPath = forwardRuleStagePath(cfg, ruleID, "landing")
		} else {
			configPath = ""
		}
	}
	status := map[string]any{
		"stage":         stage,
		"config_path":   configPath,
		"nft_path":      nftPath,
		"table":         "ip " + tableName,
		"table_exists":  false,
		"rules_present": false,
	}
	if configPath != "" {
		if _, err := os.Stat(configPath); err != nil {
			return TaskResult{Status: "failed", Result: jsonResult(status), Error: err.Error()}
		}
	}
	if _, err := os.Stat(nftPath); err != nil {
		return TaskResult{Status: "failed", Result: jsonResult(status), Error: err.Error()}
	}
	table := runner.Run(ctx, "nft", "list", "table", "ip", tableName)
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
		return "", fmt.Errorf("v0.3.0-ui-test \u6682\u4e0d\u652f\u6301 IPv6 \u843d\u5730\u76ee\u6807")
	}
	if ip := net.ParseIP(raw); ip != nil {
		if ip.To4() == nil {
			return "", fmt.Errorf("v0.3.0-ui-test \u6682\u4e0d\u652f\u6301 IPv6 \u843d\u5730\u76ee\u6807")
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

func detectNetworkInterfaces(ctx context.Context, cfg Config, runner CommandRunner) TaskResult {
	items := []map[string]any{}
	ifaces, _ := net.Interfaces()
	for _, iface := range ifaces {
		addrs, _ := iface.Addrs()
		ipv4 := []string{}
		for _, addr := range addrs {
			if ipnet, ok := addr.(*net.IPNet); ok && ipnet.IP.To4() != nil {
				ipv4 = append(ipv4, ipnet.String())
			}
		}
		items = append(items, map[string]any{"name": iface.Name, "up": iface.Flags&net.FlagUp != 0, "mtu": iface.MTU, "mac": iface.HardwareAddr.String(), "ipv4": ipv4})
	}
	defaultRoute := runner.Run(ctx, "ip", "-4", "route", "show", "default")
	addrShow := runner.Run(ctx, "ip", "-4", "addr", "show")
	mainRoute := runner.Run(ctx, "ip", "route", "show", "table", "main")
	iface, gw := parseDefaultRoute(defaultRoute.Stdout)
	return TaskResult{Status: "succeeded", Result: jsonResult(map[string]any{"interfaces": items, "default_interface": iface, "default_gateway": gw, "raw_routes": strings.TrimSpace(defaultRoute.Stdout + "\n" + mainRoute.Stdout), "ip_addr": addrShow.Stdout, "warnings": []string{}})}
}

func parseDefaultRoute(text string) (string, string) {
	fields := strings.Fields(text)
	iface, gw := "", ""
	for i, f := range fields {
		if f == "dev" && i+1 < len(fields) {
			iface = fields[i+1]
		}
		if f == "via" && i+1 < len(fields) {
			gw = fields[i+1]
		}
	}
	return iface, gw
}

type pbrRouteGroupDefinition struct {
	Name    string
	Gateway string
	Pattern string
}

var pbrRouteGroupDefinitions = []pbrRouteGroupDefinition{
	{Name: "9929", Gateway: "10.7.0.1", Pattern: `^10\.7\.`},
	{Name: "CN2", Gateway: "10.8.0.1", Pattern: `^10\.8\.`},
	{Name: "JPSDWAN", Gateway: "10.3.0.1", Pattern: `^10\.3\.[0-3]\.`},
	{Name: "DESDWAN", Gateway: "10.3.10.1", Pattern: `^10\.3\.(8|9|10|11)\.`},
	{Name: "KRSDWAN", Gateway: "10.4.0.1", Pattern: `^10\.4\.[0-3]\.`},
	{Name: "HKSDWAN", Gateway: "10.3.50.1", Pattern: `^10\.3\.(48|49|50|51)\.`},
	{Name: "TWSDWAN", Gateway: "10.3.100.1", Pattern: `^10\.3\.(100|101|102|103)\.`},
	{Name: "SEATTLE", Gateway: "10.3.160.1", Pattern: `^10\.3\.(160|161)\.`},
	{Name: "MOSCOW", Gateway: "10.3.170.1", Pattern: `^10\.3\.(170|171)\.`},
	{Name: "SINGAPORE", Gateway: "10.3.180.1", Pattern: `^10\.3\.180\.`},
	{Name: "USSDWAN-LAX", Gateway: "10.3.150.1", Pattern: `^10\.3\.(150|151)\.`},
}

func detectPBRRouteGroups(ctx context.Context, cfg Config, runner CommandRunner) TaskResult {
	ipv4s := localIPv4AddressesFunc()
	addrShow := runner.Run(ctx, "ip", "-4", "addr", "show")
	for _, ip := range parseIPv4Addresses(addrShow.Stdout) {
		if !containsString(ipv4s, ip) {
			ipv4s = append(ipv4s, ip)
		}
	}
	defaultRoute := runner.Run(ctx, "ip", "route", "show", "default")
	mainRoute := runner.Run(ctx, "ip", "route", "show", "table", "main")

	groups := []map[string]any{}
	seen := map[string]bool{}
	tableID := 101
	for _, def := range pbrRouteGroupDefinitions {
		re, err := regexp.Compile(def.Pattern)
		if err != nil {
			continue
		}
		for _, ip := range ipv4s {
			if seen[def.Name] || !re.MatchString(ip) {
				continue
			}
			groups = append(groups, map[string]any{
				"name":       def.Name,
				"gateway":    def.Gateway,
				"table_id":   tableID,
				"table_name": "T_" + def.Name,
				"matched_ip": ip,
				"pattern":    def.Pattern,
				"available":  true,
			})
			seen[def.Name] = true
			tableID++
		}
	}
	warnings := []string{}
	if len(groups) == 0 {
		warnings = append(warnings, "未检测到利群多出口线路组。")
	}
	return TaskResult{Status: "succeeded", Result: jsonResult(map[string]any{
		"route_groups":  groups,
		"default_route": strings.TrimSpace(defaultRoute.Stdout),
		"raw_ipv4":      strings.Join(ipv4s, "\n"),
		"raw_routes":    strings.TrimSpace(defaultRoute.Stdout + "\n" + mainRoute.Stdout),
		"warnings":      warnings,
	})}
}

func localIPv4Addresses() []string {
	out := []string{}
	ifaces, _ := net.Interfaces()
	for _, iface := range ifaces {
		addrs, _ := iface.Addrs()
		for _, addr := range addrs {
			ipnet, ok := addr.(*net.IPNet)
			if !ok || ipnet.IP.To4() == nil {
				continue
			}
			ip := ipnet.IP.String()
			if !containsString(out, ip) {
				out = append(out, ip)
			}
		}
	}
	return out
}

func parseIPv4Addresses(text string) []string {
	out := []string{}
	re := regexp.MustCompile(`\binet\s+([0-9]+(?:\.[0-9]+){3})(?:/\d+)?`)
	for _, match := range re.FindAllStringSubmatch(text, -1) {
		ip := match[1]
		if net.ParseIP(ip).To4() != nil && !containsString(out, ip) {
			out = append(out, ip)
		}
	}
	return out
}

func containsString(items []string, value string) bool {
	for _, item := range items {
		if item == value {
			return true
		}
	}
	return false
}

func applyPBRPolicy(ctx context.Context, cfg Config, runner CommandRunner, payload map[string]any) TaskResult {
	policy := mapPayload(payload, "pbr_policy")
	if policy == nil {
		policy = payload
	}
	policyID := stringField(policy, "id", stringField(payload, "policy_id", "pbr"))
	routeGroupName := stringField(policy, "route_group_name", "")
	gw := stringField(policy, "route_group_gateway", stringField(policy, "gateway", ""))
	if routeGroupName == "" {
		return TaskResult{Status: "failed", Error: "route_group_name is required"}
	}
	if ip := net.ParseIP(gw); ip == nil || ip.To4() == nil {
		return TaskResult{Status: "failed", Error: "route_group_gateway must be IPv4"}
	}
	tableName := stringField(policy, "route_group_table_name", "")
	if tableName == "" {
		tableName = "T_" + routeGroupName
	}
	if !validPBRTableName(tableName) {
		return TaskResult{Status: "failed", Error: "route_group_table_name is invalid"}
	}
	fwmark := stringField(policy, "fwmark", stringField(policy, "match_mark", "0x2000"))
	tableID := intField(policy, "route_group_table_id")
	if tableID == 0 {
		tableID = intField(policy, "table_id")
	}
	if tableID == 0 {
		return TaskResult{Status: "failed", Error: "route_group_table_id is required"}
	}
	priority := intField(policy, "priority")
	if priority == 0 {
		priority = 20000
	}
	matchPort := intField(policy, "match_port")
	if matchPort == 0 {
		return TaskResult{Status: "failed", Error: "match_port is required"}
	}
	protocol := stringField(policy, "protocol", stringField(policy, "match_protocol", "tcp"))
	if err := writeJSONFile(pbrPolicyPath(cfg, policyID), policy, 0o600); err != nil {
		return TaskResult{Status: "failed", Error: err.Error()}
	}
	nftContent := renderPBRNFT(protocol, matchPort, fwmark)
	if err := writeFile(pbrNFTPath(cfg), []byte(nftContent), 0o600); err != nil {
		return TaskResult{Status: "failed", Error: err.Error()}
	}
	rtUpdated, err := ensureRTTableEntry(tableID, tableName)
	if err != nil {
		return TaskResult{Status: "failed", Error: err.Error()}
	}
	ipRoute := runner.Run(ctx, "ip", "route", "replace", "default", "via", gw, "table", strconv.Itoa(tableID))
	if ipRoute.Err != nil || ipRoute.ExitCode != 0 {
		return TaskResult{Status: "failed", Stdout: ipRoute.Stdout, Stderr: ipRoute.Stderr, Error: "ip route replace failed: " + errorText(ipRoute)}
	}
	_ = runner.Run(ctx, "ip", "rule", "del", "fwmark", fwmark, "table", strconv.Itoa(tableID), "priority", strconv.Itoa(priority))
	ipRule := runner.Run(ctx, "ip", "rule", "add", "fwmark", fwmark, "table", strconv.Itoa(tableID), "priority", strconv.Itoa(priority))
	if ipRule.Err != nil || ipRule.ExitCode != 0 {
		return TaskResult{Status: "failed", Stdout: ipRule.Stdout, Stderr: ipRule.Stderr, Error: "ip rule add failed: " + errorText(ipRule)}
	}
	_ = runner.Run(ctx, "nft", "delete", "table", "ip", "edge_tunnel_pbr")
	check := runner.Run(ctx, "nft", "-c", "-f", pbrNFTPath(cfg))
	result := map[string]any{"applied": false, "pbr_path": pbrPolicyPath(cfg, policyID), "nft_path": pbrNFTPath(cfg), "nft_content": nftContent, "route_group_name": routeGroupName, "route_group_gateway": gw, "route_group_table_id": tableID, "route_group_table_name": tableName, "route_group_matched_ip": stringField(policy, "route_group_matched_ip", ""), "table_id": tableID, "table_name": tableName, "fwmark": fwmark, "priority": priority, "match_port": matchPort, "rt_tables_updated": rtUpdated, "ip_rule_output": strings.TrimSpace(ipRule.Stdout + ipRule.Stderr), "ip_route_output": strings.TrimSpace(ipRoute.Stdout + ipRoute.Stderr)}
	if check.Err != nil || check.ExitCode != 0 {
		result["nft_check_ok"] = false
		result["nft_check_stderr"] = check.Stderr
		return TaskResult{Status: "failed", Stdout: check.Stdout, Stderr: check.Stderr, Error: "nft syntax check failed: " + errorText(check), Result: jsonResult(result)}
	}
	apply := runner.Run(ctx, "nft", "-f", pbrNFTPath(cfg))
	if apply.Err != nil || apply.ExitCode != 0 {
		result["nft_check_ok"] = true
		return TaskResult{Status: "failed", Stdout: apply.Stdout, Stderr: apply.Stderr, Error: "nft apply failed: " + errorText(apply), Result: jsonResult(result)}
	}
	result["nft_check_ok"] = true
	result["applied"] = true
	return TaskResult{Status: "succeeded", Result: jsonResult(result)}
}

func validPBRTableName(value string) bool {
	if !strings.HasPrefix(value, "T_") {
		return false
	}
	for _, r := range value {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '_' || r == '-' {
			continue
		}
		return false
	}
	return true
}

func ensureRTTableEntry(tableID int, tableName string) (bool, error) {
	if tableID <= 0 || !validPBRTableName(tableName) {
		return false, fmt.Errorf("invalid route table")
	}
	if err := os.MkdirAll(filepath.Dir(pbrRTTablesPath), 0o755); err != nil {
		return false, err
	}
	raw, err := os.ReadFile(pbrRTTablesPath)
	if err != nil {
		if !os.IsNotExist(err) {
			return false, err
		}
		raw = []byte("255 local\n254 main\n253 default\n0 unspec\n")
	}
	line := fmt.Sprintf("%d %s", tableID, tableName)
	for _, existing := range strings.Split(string(raw), "\n") {
		fields := strings.Fields(existing)
		if len(fields) >= 2 && fields[0] == strconv.Itoa(tableID) && fields[1] == tableName {
			return false, nil
		}
	}
	text := strings.TrimRight(string(raw), "\n")
	if text != "" {
		text += "\n"
	}
	text += line + "\n"
	return true, os.WriteFile(pbrRTTablesPath, []byte(text), 0o644)
}

func renderPBRNFT(protocol string, matchPort int, fwmark string) string {
	lines := []string{}
	for _, proto := range forwardProtocols(protocol) {
		lines = append(lines, fmt.Sprintf("    %s dport %d meta mark set %s", proto, matchPort, fwmark))
	}
	return fmt.Sprintf("table ip edge_tunnel_pbr {\n  chain prerouting {\n    type filter hook prerouting priority mangle; policy accept;\n%s\n  }\n}\n", strings.Join(lines, "\n"))
}

func verifyPBRPolicy(ctx context.Context, cfg Config, runner CommandRunner, payload map[string]any) TaskResult {
	policy := mapPayload(payload, "pbr_policy")
	if policy == nil {
		policy = payload
	}
	tableID := intField(policy, "route_group_table_id")
	if tableID == 0 {
		tableID = intField(policy, "table_id")
	}
	tableName := stringField(policy, "route_group_table_name", "")
	fwmark := stringField(policy, "fwmark", stringField(policy, "match_mark", ""))
	ipRule := runner.Run(ctx, "ip", "rule", "show")
	ipRoute := runner.Run(ctx, "ip", "route", "show", "table", strconv.Itoa(tableID))
	nft := runner.Run(ctx, "nft", "list", "table", "ip", "edge_tunnel_pbr")
	rtTablePresent := rtTableEntryPresent(tableID, tableName)
	out := strings.TrimSpace(ipRule.Stdout + "\n" + ipRoute.Stdout + "\n" + nft.Stdout)
	verified := rtTablePresent && strings.Contains(out, fwmark) && strings.Contains(out, strconv.Itoa(tableID)) && strings.Contains(out, "edge_tunnel_pbr")
	return TaskResult{Status: "succeeded", Result: jsonResult(map[string]any{"rt_table_present": rtTablePresent, "rule_present": strings.Contains(ipRule.Stdout, fwmark), "route_present": strings.TrimSpace(ipRoute.Stdout) != "", "nft_present": nft.Err == nil && nft.ExitCode == 0, "mark_present": strings.Contains(out, fwmark), "verified": verified, "ip_rule_output": ipRule.Stdout, "ip_route_output": ipRoute.Stdout, "nft_output": nft.Stdout})}
}

func disablePBRPolicy(ctx context.Context, cfg Config, runner CommandRunner, payload map[string]any) TaskResult {
	policy := mapPayload(payload, "pbr_policy")
	if policy == nil {
		policy = payload
	}
	fwmark := stringField(policy, "fwmark", stringField(policy, "match_mark", "0x2000"))
	tableID := intField(policy, "route_group_table_id")
	if tableID == 0 {
		tableID = intField(policy, "table_id")
	}
	priority := intField(policy, "priority")
	delRule := runner.Run(ctx, "ip", "rule", "del", "fwmark", fwmark, "table", strconv.Itoa(tableID), "priority", strconv.Itoa(priority))
	delNFT := runner.Run(ctx, "nft", "delete", "table", "ip", "edge_tunnel_pbr")
	return TaskResult{Status: "succeeded", Result: jsonResult(map[string]any{"disabled": true, "removed_rule": delRule.Err == nil && delRule.ExitCode == 0, "removed_nft": delNFT.Err == nil && delNFT.ExitCode == 0})}
}

func rtTableEntryPresent(tableID int, tableName string) bool {
	raw, err := os.ReadFile(pbrRTTablesPath)
	if err != nil {
		return false
	}
	for _, line := range strings.Split(string(raw), "\n") {
		fields := strings.Fields(line)
		if len(fields) < 2 {
			continue
		}
		if tableID != 0 && fields[0] != strconv.Itoa(tableID) {
			continue
		}
		if tableName != "" && fields[1] != tableName {
			continue
		}
		return true
	}
	return false
}

func detectMTUStatus(ctx context.Context, cfg Config, runner CommandRunner) TaskResult {
	links := runner.Run(ctx, "ip", "-o", "link", "show")
	routes := runner.Run(ctx, "ip", "route", "show")
	get := runner.Run(ctx, "ip", "route", "get", "1.1.1.1")
	nft := runner.Run(ctx, "nft", "list", "table", "ip", "edge_tunnel_mss")
	return TaskResult{Status: "succeeded", Result: jsonResult(map[string]any{"interfaces_raw": links.Stdout, "routes_raw": routes.Stdout, "default_route_raw": get.Stdout, "mss_clamp_table_exists": nft.Err == nil && nft.ExitCode == 0, "mss_clamp_enabled": strings.Contains(nft.Stdout, "maxseg"), "mss_value_detected": parseMSSValue(nft.Stdout), "nft_output": nft.Stdout})}
}

func parseMSSValue(text string) string {
	if strings.Contains(text, "rt mtu") {
		return "rt mtu"
	}
	fields := strings.Fields(text)
	for i, f := range fields {
		if f == "set" && i+1 < len(fields) {
			return fields[i+1]
		}
	}
	return ""
}

func appendStringAny(value any, item string) []string {
	out := []string{}
	switch v := value.(type) {
	case []string:
		out = append(out, v...)
	case []any:
		for _, x := range v {
			if s, ok := x.(string); ok {
				out = append(out, s)
			}
		}
	}
	return append(out, item)
}
func boolFieldDefault(payload map[string]any, key string, fallback bool) bool {
	if v, ok := payload[key]; ok {
		if b, ok := v.(bool); ok {
			return b
		}
	}
	return fallback
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
		return fmt.Errorf("read disk space failed: %s: %w", path, err)
	}
	if available < required {
		return friendlyDiskSpaceError(path, required, available)
	}
	return nil
}

func friendlyDiskSpaceError(path string, required, available uint64) error {
	return fmt.Errorf("disk space is not enough to install EasyTier. temp_dir=%s required=%dMB available=%dMB. Please clean disk space, move EDGE_AGENT_STATE_DIR to a larger partition, or manually install easytier-core/easytier-cli to /usr/local/bin", path, required>>20, available>>20)
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
