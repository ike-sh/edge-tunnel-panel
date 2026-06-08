// Package ixnative implements Go-native ix-transit-fabric operations (Phase 3).
// Initially covers profile .env rendering; nftables / EasyTier follow in later steps.
package ixnative

import (
	"fmt"
	"sort"
	"strings"
)

// ProfileConfig holds the minimum fields needed to render a NAT IX profile env file.
type ProfileConfig struct {
	ProfileID      string
	Name           string
	NATPublicHost  string
	NATPublicPort  int
	LandingHost    string
	LandingPort    int
	TransitPort    int
	LocalPort      int
	NetworkName    string
	NetworkSecret  string
	CIDR           string
	Extra          map[string]string
}

// RenderProfileEnv produces a profiles/*.env file body compatible with ix-transit-fabric layout.
func RenderProfileEnv(cfg ProfileConfig) (string, error) {
	if strings.TrimSpace(cfg.ProfileID) == "" {
		return "", fmt.Errorf("profile_id is required")
	}
	if strings.TrimSpace(cfg.Name) == "" {
		return "", fmt.Errorf("name is required")
	}
	lines := map[string]string{
		"PROFILE_ID":       cfg.ProfileID,
		"PROFILE_NAME":     cfg.Name,
		"NAT_PUBLIC_HOST":  cfg.NATPublicHost,
		"LANDING_HOST":     cfg.LandingHost,
		"NETWORK_NAME":     cfg.NetworkName,
		"ET_NETWORK_SECRET": cfg.NetworkSecret,
		"CIDR":             cfg.CIDR,
	}
	if cfg.NATPublicPort > 0 {
		lines["NAT_PUBLIC_PORT"] = fmt.Sprintf("%d", cfg.NATPublicPort)
	}
	if cfg.LandingPort > 0 {
		lines["LANDING_PORT"] = fmt.Sprintf("%d", cfg.LandingPort)
	}
	if cfg.TransitPort > 0 {
		lines["TRANSIT_PORT"] = fmt.Sprintf("%d", cfg.TransitPort)
	}
	if cfg.LocalPort > 0 {
		lines["LOCAL_PORT"] = fmt.Sprintf("%d", cfg.LocalPort)
	}
	for k, v := range cfg.Extra {
		key := strings.ToUpper(strings.TrimSpace(k))
		if key == "" {
			continue
		}
		lines[key] = v
	}
	keys := make([]string, 0, len(lines))
	for k, v := range lines {
		if strings.TrimSpace(v) == "" {
			continue
		}
		keys = append(keys, k)
	}
	sort.Strings(keys)
	var b strings.Builder
	for _, k := range keys {
		b.WriteString(k)
		b.WriteByte('=')
		b.WriteString(lines[k])
		b.WriteByte('\n')
	}
	return b.String(), nil
}

// NativeEnabled reports whether the agent should prefer Go-native ix handlers over bash bridge.
func NativeEnabled() bool {
	v := strings.ToLower(strings.TrimSpace(getenv("EDGE_IX_NATIVE")))
	return v == "1" || v == "true" || v == "yes"
}

var getenv = func(key string) string {
	// overridden in tests
	return ""
}
