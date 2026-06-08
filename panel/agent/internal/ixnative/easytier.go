package ixnative

import (
	"fmt"
	"strings"
)

// EasyTierConfig holds EasyTier network parameters for a profile (Phase 3.3 skeleton).
type EasyTierConfig struct {
	ProfileID   string
	NetworkName string
	Secret      string
	CIDR        string
	Port        int
	Protocols   []string
}

// RenderEasyTierToml produces a minimal EasyTier config snippet for later native lifecycle management.
func RenderEasyTierToml(cfg EasyTierConfig) (string, error) {
	if strings.TrimSpace(cfg.NetworkName) == "" {
		return "", fmt.Errorf("network_name is required")
	}
	if cfg.Port <= 0 {
		cfg.Port = 11010
	}
	protocols := cfg.Protocols
	if len(protocols) == 0 {
		protocols = []string{"tcp", "udp"}
	}
	cidr := cfg.CIDR
	if cidr == "" {
		cidr = "10.144.0.0/16"
	}
	var b strings.Builder
	fmt.Fprintf(&b, "# profile: %s\n", cfg.ProfileID)
	fmt.Fprintf(&b, "network_name = %q\n", cfg.NetworkName)
	fmt.Fprintf(&b, "cidr = %q\n", cidr)
	fmt.Fprintf(&b, "port = %d\n", cfg.Port)
	fmt.Fprintf(&b, "protocols = [%s]\n", quoteList(protocols))
	if strings.TrimSpace(cfg.Secret) != "" {
		fmt.Fprintf(&b, "secret = %q\n", cfg.Secret)
	}
	return b.String(), nil
}

// EasyTierUnitName returns a systemd unit name for a profile-scoped EasyTier instance.
func EasyTierUnitName(profileID string) string {
	id := strings.TrimSpace(profileID)
	if id == "" {
		return "edge-tunnel-easytier.service"
	}
	return "edge-tunnel-easytier@" + id + ".service"
}

func quoteList(items []string) string {
	parts := make([]string, len(items))
	for i, item := range items {
		parts[i] = fmt.Sprintf("%q", item)
	}
	return strings.Join(parts, ", ")
}

func EasyTierConfigFromPayload(payload map[string]any) (EasyTierConfig, error) {
	cfgMap, _ := payload["config"].(map[string]any)
	profileID, _ := payload["profile_id"].(string)
	return EasyTierConfig{
		ProfileID:   profileID,
		NetworkName: stringVal(cfgMap, "NETWORK_NAME", "ix-net"),
		Secret:      stringVal(cfgMap, "ET_NETWORK_SECRET", ""),
		CIDR:        stringVal(cfgMap, "CIDR", "10.144.0.0/16"),
		Port:        intVal(cfgMap, "ET_PORT"),
	}, nil
}
