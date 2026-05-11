package agent

import (
	"context"
	"log"
	"time"
)

func Run(ctx context.Context, cfg Config, once bool, debug bool) error {
	client := NewClient(cfg)
	collector := DefaultCollector()
	reportOnce := func() error {
		report := collector.Collect(ctx, cfg)
		reg := RegisterRequest{NodeID: report.NodeID, NodeName: report.NodeName, Role: report.Role, Hostname: report.Hostname}
		if debug {
			log.Printf("register: %s", RedactForLog(reg))
		}
		if err := client.Register(ctx, reg); err != nil {
			return err
		}
		if debug {
			log.Printf("report: %s", RedactForLog(report))
		}
		return client.Report(ctx, report)
	}
	if once {
		return reportOnce()
	}
	interval := time.Duration(cfg.IntervalSeconds) * time.Second
	if interval <= 0 {
		interval = time.Minute
	}
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		if err := reportOnce(); err != nil {
			log.Printf("[WARN] report failed: %s", RedactString(err.Error()))
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-ticker.C:
		}
	}
}
