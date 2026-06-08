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
	case "detect_network_interfaces":
		return detectNetworkInterfaces(ctx, cfg, runner)
	case "detect_pbr_route_groups":
		return detectPBRRouteGroups(ctx, cfg, runner)
	case "detect_mtu_status":
		return detectMTUStatus(ctx, cfg, runner)
	case "verify_agent_config":
		return verifyFile(cfg.ConfigDir)
	case "verify_easytier_status":
		return verifyEasyTier(ctx, cfg, runner)
	case "verify_network_connectivity":
		return verifyNetworkConnectivity(ctx, cfg, runner)
	case "verify_direct_link":
		return verifyDirectLink(ctx, runner, task.Payload)
	case "verify_forward_rules":
		return verifyForwardRules(ctx, cfg, runner, task.Payload)
	case "verify_pbr_rules":
		return verifyPBR(ctx, cfg, runner)
	case "verify_pbr_policy":
		return verifyPBRPolicy(ctx, cfg, runner, task.Payload)
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
		return applyForwardConfig(ctx, cfg, runner, task.Payload)
	case "apply_entry_forward_config":
		return applyEntryForwardConfig(ctx, cfg, runner, task.Payload)
	case "apply_landing_forward_config":
		return applyLandingForwardConfig(ctx, cfg, runner, task.Payload)
	case "disable_entry_forward_config":
		return disableForwardStage(ctx, cfg, runner, "entry", task.Payload)
	case "disable_landing_forward_config":
		return disableForwardStage(ctx, cfg, runner, "landing", task.Payload)
	case "disable_network_link":
		return disableNetworkLink(ctx, cfg, runner, task.Payload)
	case "cleanup_node_deployment":
		return cleanupNodeDeployment(ctx, cfg, runner, false)
	case "purge_agent_deployment":
		return cleanupNodeDeployment(ctx, cfg, runner, true)
	case "apply_pbr_config":
		return applyPBRConfig(cfg, task.Payload)
	case "apply_pbr_policy":
		return applyPBRPolicy(ctx, cfg, runner, task.Payload)
	case "disable_pbr_policy":
		return disablePBRPolicy(ctx, cfg, runner, task.Payload)
	case "apply_ddns_config":
		return applyDDNSConfig(cfg, task.Payload)
	case "reload_firewall_rules":
		return runFixed(ctx, runner, "nft", "-f", forwardNFTPath(cfg))
	case "restart_easytier":
		return restartEasyTier(ctx, runner)
	case "restart_agent":
		return runFixed(ctx, runner, "systemctl", "restart", "edge-tunnel-agent.service")
	case "reboot_node":
		return runFixed(ctx, runner, "systemctl", "reboot")
	default:
		if isIXAction(task.Action) {
			return dispatchIXAction(ctx, cfg, runner, task)
		}
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
