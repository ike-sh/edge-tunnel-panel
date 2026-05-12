package agent

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func nodePath(cfg Config) string     { return filepath.Join(cfg.ConfigDir, "node.json") }
func easyTierPath(cfg Config) string { return filepath.Join(cfg.ConfigDir, "easytier.toml") }
func entryPath(cfg Config) string    { return filepath.Join(cfg.ConfigDir, "entry.json") }
func forwardPath(cfg Config) string  { return filepath.Join(cfg.ConfigDir, "forward.json") }
func forwardNFTPath(cfg Config) string {
	return filepath.Join(cfg.ConfigDir, "nftables", "edge-tunnel-forward.nft")
}
func pbrPath(cfg Config) string      { return filepath.Join(cfg.ConfigDir, "pbr.json") }
func pbrApplyPath(cfg Config) string { return filepath.Join(cfg.ConfigDir, "pbr-apply.sh") }
func ddnsPath(cfg Config) string     { return filepath.Join(cfg.ConfigDir, "ddns.json") }

func configureNodeRole(cfg Config, payload map[string]any) TaskResult {
	return writeJSONAction(nodePath(cfg), payload)
}

func installOrUpdateEasyTier(ctx context.Context, runner CommandRunner) TaskResult {
	if _, err := runner.LookPath("easytier-core"); err == nil {
		return TaskResult{Status: "succeeded", Result: "easytier-core already installed"}
	}
	if _, err := runner.LookPath("easytier-cli"); err == nil {
		return TaskResult{Status: "succeeded", Result: "easytier-cli already installed"}
	}
	return TaskResult{Status: "failed", Error: "EasyTier binary not found; first MVP does not auto-download EasyTier"}
}

func applyNetworkProfile(ctx context.Context, cfg Config, runner CommandRunner, payload map[string]any) TaskResult {
	if err := writeFile(easyTierPath(cfg), []byte(renderEasyTierConfig(payload)), 0o600); err != nil {
		return TaskResult{Status: "failed", Error: err.Error()}
	}
	servicePath := filepath.Join(cfg.ConfigDir, "systemd", "edge-tunnel-easytier.service")
	if err := writeFile(servicePath, []byte(edgeTunnelEasyTierService()), 0o644); err != nil {
		return TaskResult{Status: "failed", Error: err.Error()}
	}
	if cfg.EnableWriteActions {
		for _, args := range [][]string{{"daemon-reload"}, {"enable", "edge-tunnel-easytier.service"}, {"restart", "edge-tunnel-easytier.service"}} {
			result := runner.Run(ctx, "systemctl", args...)
			if result.Err != nil || result.ExitCode != 0 {
				return TaskResult{Status: "failed", Stdout: result.Stdout, Stderr: result.Stderr, Error: errorText(result)}
			}
		}
	}
	return TaskResult{Status: "succeeded", Result: "network profile applied"}
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
	if _, err := os.Stat(easyTierPath(cfg)); err != nil {
		return TaskResult{Status: "failed", Error: err.Error()}
	}
	return runFixed(ctx, runner, "systemctl", "is-active", "edge-tunnel-easytier.service")
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

func renderEasyTierConfig(payload map[string]any) string {
	networkName := stringField(payload, "network_name", "edge-net")
	networkSecret := stringField(payload, "network_secret", "")
	return fmt.Sprintf("network_name = %q\nnetwork_secret = %q\n", networkName, networkSecret)
}

func edgeTunnelEasyTierService() string {
	return "[Unit]\nDescription=Edge Tunnel Panel EasyTier\nAfter=network-online.target\n\n[Service]\nExecStart=/usr/local/bin/easytier-core -c /etc/edge-tunnel/agent/easytier.toml\nRestart=on-failure\n\n[Install]\nWantedBy=multi-user.target\n"
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
