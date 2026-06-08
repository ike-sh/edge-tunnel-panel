package ixnative

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// ProfilesDir returns the ix-transit-fabric profiles directory.
func ProfilesDir() string {
	if d := strings.TrimSpace(getenv("IXTF_PROFILES_DIR")); d != "" {
		return d
	}
	install := strings.TrimSpace(getenv("IXTF_INSTALL_PATH"))
	if install != "" {
		return filepath.Join(filepath.Dir(install), "profiles")
	}
	return "/opt/ix-transit-fabric/profiles"
}

// WriteProfileEnv renders and writes profiles/{profileID}.env atomically.
func WriteProfileEnv(cfg ProfileConfig) (string, error) {
	body, err := RenderProfileEnv(cfg)
	if err != nil {
		return "", err
	}
	dir := ProfilesDir()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", fmt.Errorf("mkdir profiles: %w", err)
	}
	target := filepath.Join(dir, cfg.ProfileID+".env")
	tmp := target + ".tmp"
	if err := os.WriteFile(tmp, []byte(body), 0o600); err != nil {
		return "", fmt.Errorf("write profile env: %w", err)
	}
	if err := os.Rename(tmp, target); err != nil {
		return "", fmt.Errorf("commit profile env: %w", err)
	}
	return target, nil
}

// ProfileConfigFromPayload maps controller task payload to ProfileConfig.
func ProfileConfigFromPayload(payload map[string]any) (ProfileConfig, error) {
	if payload == nil {
		return ProfileConfig{}, fmt.Errorf("payload is required")
	}
	profileID, _ := payload["profile_id"].(string)
	profileID = strings.TrimSpace(profileID)
	if profileID == "" {
		return ProfileConfig{}, fmt.Errorf("profile_id is required")
	}
	cfgMap, _ := payload["config"].(map[string]any)
	name := stringVal(cfgMap, "PROFILE_NAME", profileID)
	cfg := ProfileConfig{
		ProfileID:     profileID,
		Name:          name,
		NATPublicHost: stringVal(cfgMap, "NAT_PUBLIC_HOST", ""),
		LandingHost:   stringVal(cfgMap, "LANDING_HOST", ""),
		NetworkName:   stringVal(cfgMap, "NETWORK_NAME", ""),
		NetworkSecret: stringVal(cfgMap, "ET_NETWORK_SECRET", ""),
		CIDR:          stringVal(cfgMap, "CIDR", "10.144.0.0/16"),
		NATPublicPort: intVal(cfgMap, "NAT_PUBLIC_PORT"),
		LandingPort:   intVal(cfgMap, "LANDING_PORT"),
		TransitPort:   intVal(cfgMap, "TRANSIT_PORT"),
		LocalPort:     intVal(cfgMap, "LOCAL_PORT"),
	}
	return cfg, nil
}

func stringVal(m map[string]any, key, fallback string) string {
	if m == nil {
		return fallback
	}
	if v, ok := m[key].(string); ok && strings.TrimSpace(v) != "" {
		return strings.TrimSpace(v)
	}
	return fallback
}

func intVal(m map[string]any, key string) int {
	if m == nil {
		return 0
	}
	switch v := m[key].(type) {
	case float64:
		return int(v)
	case int:
		return v
	case int64:
		return int(v)
	default:
		return 0
	}
}
