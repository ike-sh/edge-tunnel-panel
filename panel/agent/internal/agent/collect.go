package agent

import (
	"context"
	"net"
	"os"
	"runtime"
)

type CommandRunner interface {
	Run(ctx context.Context, name string, args ...string) CommandResult
	LookPath(name string) (string, error)
}

type OSRunner struct{}

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
		PrivateIP: primaryIP(),
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

func primaryIP() string {
	addrs, err := net.InterfaceAddrs()
	if err != nil {
		return ""
	}
	for _, addr := range addrs {
		ipNet, ok := addr.(*net.IPNet)
		if !ok || ipNet.IP == nil || ipNet.IP.IsLoopback() {
			continue
		}
		if ip := ipNet.IP.To4(); ip != nil {
			return ip.String()
		}
	}
	return ""
}
