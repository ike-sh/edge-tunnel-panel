package ixtf

import (
	"context"
	"errors"
	"fmt"
	"os/exec"
	"strings"
)

func execCommandContext(ctx context.Context, name string, args ...string) *exec.Cmd {
	return exec.CommandContext(ctx, name, args...)
}

type OSRunner struct{}

func (OSRunner) Run(ctx context.Context, name string, args ...string) (string, string, int, error) {
	cmd := execCommandContext(ctx, name, args...)
	var stdout, stderr strings.Builder
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()
	if err == nil {
		return stdout.String(), stderr.String(), 0, nil
	}
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		code := exitErr.ExitCode()
		return stdout.String(), stderr.String(), code, fmt.Errorf("command exited with code %d", code)
	}
	return stdout.String(), stderr.String(), -1, err
}
