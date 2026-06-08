package ixtf

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

const DefaultInstallPath = "/opt/ix-transit-fabric/install.sh"

var secretPatterns = []*regexp.Regexp{
	regexp.MustCompile(`(?i)(ET_NETWORK_SECRET=)[^\s]+`),
	regexp.MustCompile(`IXTF1:[A-Za-z0-9+/=_-]+`),
}

// Bridge executes allowlisted ix-transit-fabric install.sh subcommands.
type Bridge struct {
	InstallPath string
	BashPath    string
}

func NewBridge() *Bridge {
	path := os.Getenv("IXTF_INSTALL_PATH")
	if path == "" {
		path = DefaultInstallPath
	}
	bash := os.Getenv("IXTF_BASH_PATH")
	if bash == "" {
		bash = "bash"
	}
	return &Bridge{InstallPath: path, BashPath: bash}
}

type RunResult struct {
	Subcommand string `json:"subcommand"`
	Stdout     string `json:"stdout"`
	Stderr     string `json:"stderr"`
	ExitCode   int    `json:"exit_code"`
}

type Runner interface {
	Run(ctx context.Context, name string, args ...string) (stdout, stderr string, exitCode int, err error)
}

// Run executes an allowlisted subcommand with validated args.
func (b *Bridge) Run(ctx context.Context, runner Runner, subcommand string, args ...string) (RunResult, error) {
	if !AllowedSubcommand(subcommand) {
		return RunResult{}, fmt.Errorf("subcommand %q is not allowlisted", subcommand)
	}
	if err := validateArgs(subcommand, args); err != nil {
		return RunResult{}, err
	}
	installPath, err := filepath.Abs(b.InstallPath)
	if err != nil {
		return RunResult{}, fmt.Errorf("resolve install path: %w", err)
	}
	cmdArgs := append([]string{installPath, subcommand}, args...)
	stdout, stderr, exitCode, err := runner.Run(ctx, b.BashPath, cmdArgs...)
	result := RunResult{
		Subcommand: subcommand,
		Stdout:     Redact(stdout),
		Stderr:     Redact(stderr),
		ExitCode:   exitCode,
	}
	if err != nil {
		return result, err
	}
	return result, nil
}

func Redact(text string) string {
	out := text
	for _, re := range secretPatterns {
		out = re.ReplaceAllString(out, "${1}[REDACTED]")
	}
	return out
}

func validateArgs(subcommand string, args []string) error {
	for _, arg := range args {
		if strings.ContainsAny(arg, ";&|$`<>") {
			return fmt.Errorf("invalid character in arg %q", arg)
		}
	}
	switch subcommand {
	case "edit-rule", "enable-rule", "disable-rule", "delete-rule", "show-rule":
		if len(args) < 2 {
			return fmt.Errorf("%s requires profile_id and rule_id", subcommand)
		}
	case "diagnose", "show-config", "show-port-map", "list-rules", "show-nat-code", "refresh-code", "show-profile":
		if len(args) > 1 {
			return fmt.Errorf("%s accepts at most one profile_id", subcommand)
		}
	}
	return nil
}
