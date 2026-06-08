package agent

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/ike-sh/edge-tunnel-panel/panel/agent/internal/ixnative"
	"github.com/ike-sh/edge-tunnel-panel/panel/agent/internal/ixtf"
)

func dispatchIXAction(ctx context.Context, cfg Config, runner CommandRunner, task Task) TaskResult {
	if ixnative.NativeEnabled() {
		if result, handled := dispatchNativeIXAction(ctx, cfg, runner, task); handled {
			return result
		}
	}
	sub, ok := ixtf.SubcommandForAction(task.Action)
	if !ok {
		return TaskResult{Status: "failed", Error: "unknown ix action"}
	}
	args := ixArgsFromPayload(task.Payload)
	bridge := ixtf.NewBridge()
	ixRunner := ixCommandRunner{inner: runner}
	result, err := bridge.Run(ctx, ixRunner, sub, args...)
	raw, _ := json.Marshal(result)
	if err != nil {
		return TaskResult{Status: "failed", Result: string(raw), Stdout: result.Stdout, Stderr: result.Stderr, Error: err.Error()}
	}
	return TaskResult{Status: "succeeded", Result: string(raw), Stdout: result.Stdout, Stderr: result.Stderr}
}

func dispatchNativeIXAction(ctx context.Context, cfg Config, runner CommandRunner, task Task) (TaskResult, bool) {
	sysRunner := systemdRunnerAdapter{inner: runner}
	switch task.Action {
	case "ix_write_create_nat":
		profileCfg, err := ixnative.ProfileConfigFromPayload(task.Payload)
		if err != nil {
			return TaskResult{Status: "failed", Error: err.Error()}, true
		}
		path, err := ixnative.WriteProfileEnv(profileCfg)
		if err != nil {
			return TaskResult{Status: "failed", Error: err.Error()}, true
		}
		out := map[string]any{"native": true, "path": path, "profile_id": profileCfg.ProfileID}
		if lifecycle, lcErr := ixnative.ProvisionEasyTierLifecycle(ctx, sysRunner, task.Payload); lcErr == nil {
			for k, v := range lifecycle {
				out[k] = v
			}
		} else if ixnative.SystemdApplyEnabled() {
			return TaskResult{Status: "failed", Error: lcErr.Error()}, true
		}
		raw, _ := json.Marshal(out)
		msg := fmt.Sprintf("wrote profile env: %s\n", path)
		if v, ok := out["easytier_config"].(string); ok {
			msg += fmt.Sprintf("wrote easytier config: %s\n", v)
		}
		if v, ok := out["systemd_unit"].(string); ok {
			msg += fmt.Sprintf("wrote systemd unit: %s\n", v)
		}
		return TaskResult{Status: "succeeded", Result: string(raw), Stdout: msg}, true
	case "ix_write_apply_rules":
		rules := ixnative.ForwardRulesFromPayload(task.Payload)
		if len(rules) == 0 {
			return TaskResult{Status: "failed", Error: "no forward rules in payload config"}, true
		}
		profileID, _ := task.Payload["profile_id"].(string)
		table := "ix_" + strings.TrimSpace(profileID)
		if table == "ix_" {
			table = "ix_transit"
		}
		path, err := ixnative.WriteForwardNFT(table, rules)
		if err != nil {
			return TaskResult{Status: "failed", Error: err.Error()}, true
		}
		out := map[string]any{"native": true, "nft_path": path, "rules": len(rules)}
		raw, _ := json.Marshal(out)
		return TaskResult{Status: "succeeded", Result: string(raw), Stdout: fmt.Sprintf("wrote nft rules: %s\n", path)}, true
	default:
		return TaskResult{}, false
	}
}

func ixArgsFromPayload(payload map[string]any) []string {
	if payload == nil {
		return nil
	}
	if profileID, _ := payload["profile_id"].(string); profileID != "" {
		if ruleID, _ := payload["rule_id"].(string); ruleID != "" {
			return []string{profileID, ruleID}
		}
		return []string{profileID}
	}
	if code, _ := payload["code"].(string); code != "" {
		return []string{"--code", code}
	}
	if compact, _ := payload["compact"].(bool); compact {
		return []string{"--compact"}
	}
	return nil
}

// ixCommandRunner adapts agent.CommandRunner to ixtf.Runner.
type ixCommandRunner struct {
	inner CommandRunner
}

func (r ixCommandRunner) Run(ctx context.Context, name string, args ...string) (string, string, int, error) {
	res := r.inner.Run(ctx, name, args...)
	exitCode := res.ExitCode
	if res.Err != nil && exitCode == 0 {
		return res.Stdout, res.Stderr, -1, res.Err
	}
	if exitCode != 0 {
		return res.Stdout, res.Stderr, exitCode, fmt.Errorf("exit code %d", exitCode)
	}
	return res.Stdout, res.Stderr, 0, nil
}

func isIXAction(action string) bool {
	_, ok := ixtf.SubcommandForAction(action)
	return ok
}

type systemdRunnerAdapter struct {
	inner CommandRunner
}

func (a systemdRunnerAdapter) Run(ctx context.Context, name string, args ...string) (string, string, int, error) {
	res := a.inner.Run(ctx, name, args...)
	exitCode := res.ExitCode
	if res.Err != nil && exitCode == 0 {
		return res.Stdout, res.Stderr, -1, res.Err
	}
	if exitCode != 0 {
		return res.Stdout, res.Stderr, exitCode, fmt.Errorf("exit code %d", exitCode)
	}
	return res.Stdout, res.Stderr, 0, nil
}
