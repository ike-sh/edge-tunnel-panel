package ixnative

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// WriteForwardNFT renders and writes an nftables ruleset for transit forwarding.
func WriteForwardNFT(tableName string, rules []NFTForwardRule) (string, error) {
	body, err := RenderForwardNFT(tableName, rules)
	if err != nil {
		return "", err
	}
	dir := nftRulesDir()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", fmt.Errorf("mkdir nft dir: %w", err)
	}
	name := strings.TrimSpace(tableName)
	if name == "" {
		name = "ix_transit"
	}
	target := filepath.Join(dir, name+".nft")
	tmp := target + ".tmp"
	if err := os.WriteFile(tmp, []byte(body), 0o600); err != nil {
		return "", fmt.Errorf("write nft: %w", err)
	}
	if err := os.Rename(tmp, target); err != nil {
		return "", fmt.Errorf("commit nft: %w", err)
	}
	return target, nil
}

func nftRulesDir() string {
	if d := strings.TrimSpace(getenv("IXTF_NFT_DIR")); d != "" {
		return d
	}
	install := strings.TrimSpace(getenv("IXTF_INSTALL_PATH"))
	if install != "" {
		return filepath.Join(filepath.Dir(install), "nft")
	}
	return "/opt/ix-transit-fabric/nft"
}

// ForwardRulesFromPayload extracts nft rules from controller task payload config.
func ForwardRulesFromPayload(payload map[string]any) []NFTForwardRule {
	cfg, _ := payload["config"].(map[string]any)
	if cfg == nil {
		return nil
	}
	host := stringVal(cfg, "LANDING_HOST", "")
	port := intVal(cfg, "LANDING_PORT")
	transit := intVal(cfg, "TRANSIT_PORT")
	if transit == 0 {
		transit = intVal(cfg, "NAT_PUBLIC_PORT")
	}
	if host == "" || port <= 0 || transit <= 0 {
		return nil
	}
	return []NFTForwardRule{{
		Name:       "main",
		ListenPort: transit,
		TargetHost: host,
		TargetPort: port,
		Protocol:   "tcp",
	}}
}
