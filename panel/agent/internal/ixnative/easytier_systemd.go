package ixnative

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// WriteEasyTierConfig renders and writes EasyTier TOML for a profile.
func WriteEasyTierConfig(cfg EasyTierConfig) (string, error) {
	body, err := RenderEasyTierToml(cfg)
	if err != nil {
		return "", err
	}
	dir := easyTierConfigDir()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", fmt.Errorf("mkdir easytier config: %w", err)
	}
	name := strings.TrimSpace(cfg.ProfileID)
	if name == "" {
		name = "default"
	}
	target := filepath.Join(dir, name+".toml")
	tmp := target + ".tmp"
	if err := os.WriteFile(tmp, []byte(body), 0o600); err != nil {
		return "", fmt.Errorf("write easytier config: %w", err)
	}
	if err := os.Rename(tmp, target); err != nil {
		return "", fmt.Errorf("commit easytier config: %w", err)
	}
	return target, nil
}

// RenderSystemdUnit produces a systemd unit file body for profile-scoped EasyTier.
func RenderSystemdUnit(profileID, configPath, easyTierBinary string) (string, error) {
	if strings.TrimSpace(profileID) == "" {
		return "", fmt.Errorf("profile_id is required")
	}
	if strings.TrimSpace(configPath) == "" {
		return "", fmt.Errorf("config_path is required")
	}
	if strings.TrimSpace(easyTierBinary) == "" {
		easyTierBinary = "easytier-core"
	}
	return fmt.Sprintf(`[Unit]
Description=EasyTier for profile %s
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=%s -c %s
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
`, profileID, easyTierBinary, configPath), nil
}

// WriteSystemdUnit writes a profile-scoped EasyTier systemd unit file (does not enable/start).
func WriteSystemdUnit(profileID, configPath, easyTierBinary string) (string, error) {
	body, err := RenderSystemdUnit(profileID, configPath, easyTierBinary)
	if err != nil {
		return "", err
	}
	dir := systemdUnitDir()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", fmt.Errorf("mkdir systemd dir: %w", err)
	}
	target := filepath.Join(dir, unitFileName(profileID))
	tmp := target + ".tmp"
	if err := os.WriteFile(tmp, []byte(body), 0o644); err != nil {
		return "", fmt.Errorf("write systemd unit: %w", err)
	}
	if err := os.Rename(tmp, target); err != nil {
		return "", fmt.Errorf("commit systemd unit: %w", err)
	}
	return target, nil
}

func easyTierConfigDir() string {
	if d := strings.TrimSpace(getenv("IXTF_EASYTIER_DIR")); d != "" {
		return d
	}
	install := strings.TrimSpace(getenv("IXTF_INSTALL_PATH"))
	if install != "" {
		return filepath.Join(filepath.Dir(install), "easytier")
	}
	return "/opt/ix-transit-fabric/easytier"
}

func systemdUnitDir() string {
	if d := strings.TrimSpace(getenv("IXTF_SYSTEMD_DIR")); d != "" {
		return d
	}
	return "/etc/systemd/system"
}

func unitFileName(profileID string) string {
	id := strings.TrimSpace(profileID)
	if id == "" {
		return "edge-tunnel-easytier.service"
	}
	return "edge-tunnel-easytier@" + id + ".service"
}
