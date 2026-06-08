package ixnative

import (
	"context"
	"fmt"
	"strings"
)

// EasyTier unit actions for profile-scoped instances.
const (
	EasyTierActionStart   = "start"
	EasyTierActionStop    = "stop"
	EasyTierActionRestart = "restart"
	EasyTierActionStatus  = "status"
)

// EasyTierUnitAction runs systemctl against a profile-scoped EasyTier unit.
func EasyTierUnitAction(ctx context.Context, runner SystemdRunner, profileID, action string) (string, error) {
	if runner == nil {
		return "", fmt.Errorf("command runner is required")
	}
	action = strings.ToLower(strings.TrimSpace(action))
	switch action {
	case EasyTierActionStart, EasyTierActionStop, EasyTierActionRestart, EasyTierActionStatus:
	default:
		return "", fmt.Errorf("unsupported easytier action %q", action)
	}
	unit := unitFileName(profileID)
	stdout, stderr, code, err := runner.Run(ctx, "systemctl", action, unit)
	if err != nil || (code != 0 && action != EasyTierActionStatus) {
		return "", fmt.Errorf("systemctl %s %s failed (code=%d): %s %s", action, unit, code, stderr, stdout)
	}
	out := strings.TrimSpace(stdout)
	if out == "" {
		out = strings.TrimSpace(stderr)
	}
	return out, nil
}

// ProvisionEasyTierLifecycle writes config + unit and optionally applies systemd + starts service.
func ProvisionEasyTierLifecycle(ctx context.Context, runner SystemdRunner, payload map[string]any) (map[string]any, error) {
	etCfg, err := EasyTierConfigFromPayload(payload)
	if err != nil {
		return nil, err
	}
	cfgPath, err := WriteEasyTierConfig(etCfg)
	if err != nil {
		return nil, err
	}
	unitPath, err := WriteSystemdUnit(etCfg.ProfileID, cfgPath, "")
	if err != nil {
		return nil, err
	}
	out := map[string]any{
		"easytier_config": cfgPath,
		"systemd_unit":    unitPath,
	}
	if SystemdApplyEnabled() {
		if err := ApplySystemdUnit(ctx, runner, etCfg.ProfileID); err != nil {
			return out, err
		}
		status, err := EasyTierUnitAction(ctx, runner, etCfg.ProfileID, EasyTierActionStatus)
		if err != nil {
			return out, err
		}
		out["systemd_applied"] = true
		out["easytier_status"] = status
	}
	return out, nil
}
