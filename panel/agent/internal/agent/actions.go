package agent

import (
	"context"
	"encoding/json"
)

func DispatchAction(ctx context.Context, cfg Config, runner CommandRunner, task Task) TaskResult {
	if err := ValidateTask(task, cfg); err != nil {
		return TaskResult{Status: "failed", Error: err.Error()}
	}
	switch task.Action {
	case "collect_agent_status":
		status := CollectStatus(ctx, cfg, runner)
		raw, _ := json.Marshal(status)
		return TaskResult{Status: "succeeded", Result: string(raw)}
	case "run_node_preflight":
		return runNodePreflight(ctx, cfg, runner)
	case "verify_agent_config":
		return verifyFile(cfg.ConfigDir)
	case "verify_easytier_status":
		return verifyEasyTier(ctx, cfg, runner)
	case "verify_forward_rules":
		return verifyFile(forwardNFTPath(cfg))
	case "verify_pbr_rules":
		return verifyPBR(ctx, cfg, runner)
	case "verify_ddns_status":
		return verifyFile(ddnsPath(cfg))
	case "configure_node_role":
		return configureNodeRole(cfg, task.Payload)
	case "install_or_update_easytier":
		return installOrUpdateEasyTier(ctx, cfg, runner, task.Payload)
	case "apply_network_profile":
		return applyNetworkProfile(ctx, cfg, runner, task.Payload)
	case "apply_entry_config":
		return writeJSONAction(entryPath(cfg), task.Payload)
	case "apply_forward_config":
		return applyForwardConfig(cfg, task.Payload)
	case "apply_pbr_config":
		return applyPBRConfig(cfg, task.Payload)
	case "apply_ddns_config":
		return applyDDNSConfig(cfg, task.Payload)
	case "reload_firewall_rules":
		return runFixed(ctx, runner, "nft", "-f", forwardNFTPath(cfg))
	case "restart_easytier":
		return runFixed(ctx, runner, "systemctl", "restart", "edge-tunnel-easytier.service")
	case "restart_agent":
		return runFixed(ctx, runner, "systemctl", "restart", "edge-tunnel-agent.service")
	case "reboot_node":
		return runFixed(ctx, runner, "systemctl", "reboot")
	default:
		return TaskResult{Status: "failed", Error: "unknown action"}
	}
}

func runFixed(ctx context.Context, runner CommandRunner, name string, args ...string) TaskResult {
	result := runner.Run(ctx, name, args...)
	if result.Err != nil || result.ExitCode != 0 {
		return TaskResult{Status: "failed", Stdout: result.Stdout, Stderr: result.Stderr, Error: errorText(result)}
	}
	return TaskResult{Status: "succeeded", Stdout: result.Stdout, Stderr: result.Stderr}
}

func errorText(result CommandResult) string {
	if result.Err != nil {
		return result.Err.Error()
	}
	return "command failed"
}
