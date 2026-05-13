package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/ike-sh/edge-tunnel-panel/panel/agent/internal/agent"
)

var version = "v0.2.8-test"

func main() {
	cfg := agent.ConfigFromEnv()
	once := flag.Bool("once", false, "run one report/task cycle and exit")
	showVersion := flag.Bool("version", false, "print version")
	flag.StringVar(&cfg.ControllerURL, "controller-url", cfg.ControllerURL, "controller URL")
	flag.StringVar(&cfg.ControllerToken, "token", cfg.ControllerToken, "controller token")
	flag.StringVar(&cfg.NodeID, "node-id", cfg.NodeID, "node id")
	flag.StringVar(&cfg.NodeName, "node-name", cfg.NodeName, "node name")
	flag.StringVar(&cfg.NodeRole, "role", cfg.NodeRole, "node role")
	flag.BoolVar(&cfg.EnableTasks, "enable-tasks", cfg.EnableTasks, "enable task polling")
	flag.BoolVar(&cfg.EnableWriteActions, "enable-write-actions", cfg.EnableWriteActions, "enable write actions")
	flag.StringVar(&cfg.ConfigDir, "config-dir", cfg.ConfigDir, "config dir")
	flag.StringVar(&cfg.StateDir, "state-dir", cfg.StateDir, "state dir")
	flag.Parse()
	if *showVersion {
		fmt.Printf("edge-tunnel-agent %s\n", version)
		return
	}
	_ = cfg.Normalize()
	if err := cfg.Validate(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	client := agent.NewHTTPClient(cfg)
	runner := agent.OSRunner{}
	if err := runOnce(ctx, cfg, client, runner); err != nil {
		fmt.Fprintln(os.Stderr, agent.RedactString(err.Error(), cfg.ControllerToken))
		os.Exit(1)
	}
	if *once {
		return
	}
	reportTicker := time.NewTicker(cfg.ReportInterval)
	taskTicker := time.NewTicker(cfg.PollInterval)
	defer reportTicker.Stop()
	defer taskTicker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-reportTicker.C:
			_ = runOnce(ctx, cfg, client, runner)
		case <-taskTicker.C:
			if cfg.EnableTasks {
				_ = agent.ProcessTasks(ctx, cfg, client, runner)
			}
		}
	}
}

func runOnce(ctx context.Context, cfg agent.Config, client agent.Client, runner agent.CommandRunner) error {
	status := agent.CollectStatus(ctx, cfg, runner)
	report := agent.ReportFromStatus(cfg, status)
	if err := client.Register(ctx, report); err != nil {
		return err
	}
	if err := client.Report(ctx, report); err != nil {
		return err
	}
	if cfg.EnableTasks {
		return agent.ProcessTasks(ctx, cfg, client, runner)
	}
	return nil
}
