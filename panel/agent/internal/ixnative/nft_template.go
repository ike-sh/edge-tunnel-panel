package ixnative

import (
	"fmt"
	"strings"
)

// NFTForwardRule describes one DNAT/SNAT forwarding entry for nftables template rendering.
type NFTForwardRule struct {
	Name       string
	ListenPort int
	TargetHost string
	TargetPort int
	Protocol   string
}

// RenderForwardNFT produces a minimal nftables ruleset for transit forwarding (Phase 3.2 skeleton).
func RenderForwardNFT(tableName string, rules []NFTForwardRule) (string, error) {
	tableName = strings.TrimSpace(tableName)
	if tableName == "" {
		tableName = "ix_transit"
	}
	var b strings.Builder
	b.WriteString("table inet ")
	b.WriteString(tableName)
	b.WriteString(" {\n")
	b.WriteString("  chain prerouting {\n")
	b.WriteString("    type nat hook prerouting priority dstnat; policy accept;\n")
	for _, rule := range rules {
		proto := strings.ToLower(strings.TrimSpace(rule.Protocol))
		if proto == "" {
			proto = "tcp"
		}
		if rule.ListenPort <= 0 || rule.TargetPort <= 0 || strings.TrimSpace(rule.TargetHost) == "" {
			continue
		}
		name := strings.TrimSpace(rule.Name)
		if name == "" {
			name = fmt.Sprintf("fwd-%d", rule.ListenPort)
		}
		fmt.Fprintf(&b, "    %s %s dport %d dnat to %s:%d\n", name, proto, rule.ListenPort, rule.TargetHost, rule.TargetPort)
	}
	b.WriteString("  }\n")
	b.WriteString("}\n")
	return b.String(), nil
}
