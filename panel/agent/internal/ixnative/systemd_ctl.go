package ixnative

import (
	"context"
	"fmt"
	"strings"
)

// SystemdRunner executes systemctl commands.
type SystemdRunner interface {
	Run(ctx context.Context, name string, args ...string) (stdout, stderr string, exitCode int, err error)
}

// ApplySystemdUnit runs daemon-reload, enable, and start when EDGE_IX_SYSTEMD_APPLY is set.
func ApplySystemdUnit(ctx context.Context, runner SystemdRunner, profileID string) error {
	if runner == nil {
		return fmt.Errorf("command runner is required")
	}
	if !SystemdApplyEnabled() {
		return nil
	}
	unit := unitFileName(profileID)
	for _, args := range [][]string{
		{"daemon-reload"},
		{"enable", unit},
		{"start", unit},
	} {
		stdout, stderr, code, err := runner.Run(ctx, "systemctl", args...)
		if err != nil || code != 0 {
			return fmt.Errorf("systemctl %s failed (code=%d): %s %s", strings.Join(args, " "), code, stderr, stdout)
		}
	}
	return nil
}

func SystemdApplyEnabled() bool {
	v := strings.ToLower(strings.TrimSpace(getenv("EDGE_IX_SYSTEMD_APPLY")))
	return v == "1" || v == "true" || v == "yes"
}
