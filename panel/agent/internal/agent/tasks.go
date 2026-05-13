package agent

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"time"
)

var taskExecutionMu sync.Mutex

var readonlyActions = map[string]bool{
	"collect_agent_status":        true,
	"run_node_preflight":          true,
	"verify_agent_config":         true,
	"verify_easytier_status":      true,
	"verify_network_connectivity": true,
	"verify_forward_rules":        true,
	"verify_pbr_rules":            true,
	"verify_ddns_status":          true,
}

var writeActions = map[string]bool{
	"configure_node_role":        true,
	"install_or_update_easytier": true,
	"apply_network_profile":      true,
	"apply_entry_config":         true,
	"apply_forward_config":       true,
	"apply_pbr_config":           true,
	"apply_ddns_config":          true,
	"reload_firewall_rules":      true,
	"restart_easytier":           true,
	"restart_agent":              true,
	"reboot_node":                true,
}

var blockedActions = map[string]bool{
	"arbitrary_command": true,
	"shell_c":           true,
	"bash_c":            true,
	"eval":              true,
	"raw_nft":           true,
	"raw_iptables":      true,
	"raw_ip_route":      true,
	"curl_pipe_bash":    true,
}

var dangerousPayloadKeys = []string{
	"command",
	"cmd",
	"shell",
	"script",
	"raw_nft",
	"raw_iptables",
	"raw_ip_route",
}

func RejectDangerousPayload(payload map[string]any) error {
	for _, key := range dangerousPayloadKeys {
		if _, ok := payload[key]; ok {
			return fmt.Errorf("dangerous payload key %q is not allowed", key)
		}
	}
	return nil
}

func IsAllowedAction(action string) bool {
	return readonlyActions[action] || writeActions[action]
}

func ValidateTask(task Task, cfg Config) error {
	if blockedActions[task.Action] {
		return errors.New("blocked action is not allowed")
	}
	if !IsAllowedAction(task.Action) {
		return errors.New("unknown action")
	}
	if err := RejectDangerousPayload(task.Payload); err != nil {
		return err
	}
	if writeActions[task.Action] && !cfg.EnableWriteActions {
		return errors.New("write actions are disabled")
	}
	if task.Action == "reboot_node" {
		confirm, _ := task.Payload["confirm"].(bool)
		if !confirm {
			return errors.New("reboot_node requires confirm=true")
		}
	}
	return nil
}

func ExecuteTask(ctx context.Context, cfg Config, runner CommandRunner, task Task) TaskResult {
	started := time.Now().UTC()
	result := DispatchAction(ctx, cfg, runner, task)
	result.StartedAt = started
	result.FinishedAt = time.Now().UTC()
	return LimitTaskResult(result, cfg.TaskResultLimitKB, cfg.ControllerToken)
}

func ProcessTasks(ctx context.Context, cfg Config, client Client, runner CommandRunner) error {
	if !cfg.EnableTasks {
		return nil
	}
	taskExecutionMu.Lock()
	defer taskExecutionMu.Unlock()
	tasks, err := client.FetchTasks(ctx, cfg.NodeID)
	if err != nil {
		return err
	}
	for _, task := range tasks {
		result := ExecuteTask(ctx, cfg, runner, task)
		if err := client.SubmitTaskResult(ctx, task.ID, result); err != nil {
			return err
		}
	}
	return nil
}
