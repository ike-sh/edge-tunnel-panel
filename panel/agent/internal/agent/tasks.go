package agent

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os/exec"
	"sort"
	"strings"
	"time"
)

var readonlyTaskActions = map[string][]string{
	"probe_core_version": {"--version"},
	"run_status":         {"status"},
	"run_status_json":    {"status", "--json"},
	"run_doctor":         {"doctor"},
	"run_doctor_json":    {"doctor", "--json"},
	"list_forwards":      {"forward", "list"},
	"ddns_overview":      {"ddns", "overview"},
}

func AllowedTaskActions() []string {
	out := make([]string, 0, len(readonlyTaskActions))
	for action := range readonlyTaskActions {
		out = append(out, action)
	}
	sort.Strings(out)
	return out
}

func TaskActionArgs(action string) ([]string, bool) {
	args, ok := readonlyTaskActions[action]
	if !ok {
		return nil, false
	}
	cp := append([]string(nil), args...)
	return cp, true
}

func ExecuteTask(ctx context.Context, collector Collector, cfg Config, task Task) TaskResultRequest {
	args, ok := TaskActionArgs(strings.TrimSpace(task.Action))
	if !ok {
		return TaskResultRequest{
			Status:   "rejected",
			ExitCode: 1,
			Error:    RedactString("unsupported readonly task action: " + task.Action),
		}
	}
	lqPath, err := collector.findLQ()
	if err != nil {
		return TaskResultRequest{
			Status:   "failed",
			ExitCode: 127,
			Error:    "lq missing: " + RedactString(err.Error()),
		}
	}
	timeout := time.Duration(cfg.TaskTimeoutSeconds) * time.Second
	if timeout <= 0 {
		timeout = 20 * time.Second
	}
	runCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	stdout, stderr, exitCode, err := collector.runTaskCommand(runCtx, lqPath, args...)
	result := TaskResultRequest{
		Status:       "succeeded",
		ResultStdout: truncateTaskOutput(stdout),
		ResultStderr: truncateTaskOutput(stderr),
		ExitCode:     exitCode,
	}
	if err != nil {
		result.Status = "failed"
		result.Error = truncateTaskOutput(err.Error())
		if errors.Is(runCtx.Err(), context.DeadlineExceeded) {
			result.Error = "task timeout"
		}
		if result.ExitCode == 0 {
			result.ExitCode = 1
		}
	}
	return result
}

func (c Collector) runTaskCommand(ctx context.Context, name string, args ...string) (string, string, int, error) {
	if c.TaskCommandFunc != nil {
		return c.TaskCommandFunc(ctx, name, args...)
	}
	cmd := exec.CommandContext(ctx, name, args...)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()
	exitCode := 0
	if err != nil {
		exitCode = 1
		var exitErr *exec.ExitError
		if errors.As(err, &exitErr) {
			exitCode = exitErr.ExitCode()
		}
		if ctx.Err() == context.DeadlineExceeded {
			err = fmt.Errorf("task timeout")
		}
	}
	return stdout.String(), stderr.String(), exitCode, err
}

func truncateTaskOutput(s string) string {
	s = RedactString(s)
	const maxBytes = 64 * 1024
	if len(s) <= maxBytes {
		return s
	}
	return s[:maxBytes] + "\n[TRUNCATED]"
}
