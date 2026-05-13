package agent

import (
	"context"
	"net"
	"os"
	"runtime"
	"strings"
)

type CommandRunner interface {
	Run(ctx context.Context, name string, args ...string) CommandResult
	LookPath(name string) (string, error)
}

type OSRunner struct{}

var interfaceAddrsFunc = func(iface net.Interface) ([]net.Addr, error) {
	return iface.Addrs()
}

func (OSRunner) Run(ctx context.Context, name string, args ...string) CommandResult {
	return runCommand(ctx, name, args...)
}

func (OSRunner) LookPath(name string) (string, error) {
	return lookPath(name)
}

func CollectStatus(ctx context.Context, cfg Config, runner CommandRunner) AgentStatus {
	if runner == nil {
		runner = OSRunner{}
	}
	hostname, _ := os.Hostname()
	status := AgentStatus{
		Hostname:  hostname,
		OS:        runtime.GOOS,
		Arch:      runtime.GOARCH,
		NodeRole:  cfg.NodeRole,
		ConfigDir: cfg.ConfigDir,
		StateDir:  cfg.StateDir,
		Capabilities: map[string]bool{
			"supports_agent_status":    true,
			"supports_task_polling":    cfg.EnableTasks,
			"supports_network_profile": true,
			"supports_entry_apply":     cfg.EnableWriteActions,
			"supports_forward_apply":   cfg.EnableWriteActions,
			"supports_pbr_apply":       cfg.EnableWriteActions,
			"supports_ddns_apply":      cfg.EnableWriteActions,
			"supports_easytier_manage": cfg.EnableWriteActions,
			"supports_firewall_reload": cfg.EnableWriteActions,
		},
		PrivateIP: privateIP(),
	}
	if _, err := runner.LookPath("easytier-core"); err == nil {
		status.EasyTierBinaryExists = true
	} else if _, err := runner.LookPath("easytier-cli"); err == nil {
		status.EasyTierBinaryExists = true
	} else {
		status.Warnings = append(status.Warnings, "EasyTier binary not found")
	}
	if _, err := os.Stat(cfg.ConfigDir); err != nil {
		status.Warnings = append(status.Warnings, "config dir unavailable: "+RedactString(err.Error(), cfg.ControllerToken))
	}
	if _, err := os.Stat(cfg.StateDir); err != nil {
		status.Warnings = append(status.Warnings, "state dir unavailable: "+RedactString(err.Error(), cfg.ControllerToken))
	}
	if _, err := runner.LookPath("nft"); err == nil {
		status.NFTAvailable = true
	} else {
		status.Warnings = append(status.Warnings, "nft command not found")
	}
	if _, err := runner.LookPath("ip"); err == nil {
		status.IPRouteAvailable = true
	} else {
		status.Warnings = append(status.Warnings, "ip command not found")
	}
	if result := runner.Run(ctx, "systemctl", "is-active", "edge-tunnel-easytier.service"); result.Err == nil && result.ExitCode == 0 {
		status.EasyTierServiceActive = true
	}
	if result := runner.Run(ctx, "systemctl", "is-active", "edge-tunnel-agent.service"); result.Err == nil && result.ExitCode == 0 {
		status.AgentServiceActive = true
	}
	return status
}

func ReportFromStatus(cfg Config, status AgentStatus) ReportRequest {
	return ReportRequest{
		ID:             cfg.NodeID,
		Name:           cfg.NodeName,
		Role:           cfg.NodeRole,
		PrivateIP:      status.PrivateIP,
		AgentVersion:   Version,
		Hostname:       status.Hostname,
		OS:             status.OS,
		Arch:           status.Arch,
		EasyTierIP:     status.EasyTierIP,
		EasyTierStatus: easyTierStatus(cfg, status),
		Capabilities:   status.Capabilities,
		Warnings:       status.Warnings,
	}
}

func easyTierStatus(cfg Config, status AgentStatus) string {
	if !status.EasyTierBinaryExists {
		return "missing_binary"
	}
	if _, err := os.Stat(easyTierPath(cfg)); err != nil {
		return "missing_config"
	}
	if _, err := os.Stat(easyTierServiceSystemPath()); err != nil {
		return "service_missing"
	}
	if status.EasyTierServiceActive {
		return "active"
	}
	return "inactive"
}

func privateIP() string {
	return privateIPFromInterfaces(net.Interfaces)
}

func privateIPFromInterfaces(listInterfaces func() ([]net.Interface, error)) string {
	ifaces, err := listInterfaces()
	if err != nil {
		return "-"
	}
	out := []string{}
	for _, iface := range ifaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, err := interfaceAddrsFunc(iface)
		if err != nil {
			continue
		}
		for _, addr := range addrs {
			ip := ipFromAddr(addr)
			if ip == nil || ip.IsLoopback() {
				continue
			}
			if isPrivateNodeIP(ip) {
				out = append(out, ip.String())
			}
		}
	}
	if len(out) == 0 {
		return "-"
	}
	return strings.Join(out, ",")
}

func ipFromAddr(addr net.Addr) net.IP {
	switch value := addr.(type) {
	case *net.IPNet:
		return value.IP
	case *net.IPAddr:
		return value.IP
	default:
		return nil
	}
}

func isPrivateNodeIP(ip net.IP) bool {
	if ip4 := ip.To4(); ip4 != nil {
		return ip4[0] == 10 ||
			(ip4[0] == 172 && ip4[1] >= 16 && ip4[1] <= 31) ||
			(ip4[0] == 192 && ip4[1] == 168) ||
			(ip4[0] == 100 && ip4[1] >= 64 && ip4[1] <= 127)
	}
	return ip.IsPrivate()
}
