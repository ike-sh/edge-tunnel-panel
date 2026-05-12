package agent

import (
	"context"
	"log"
	"sync"
	"time"
)

var taskExecutionLock sync.Mutex

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
		if err := reportOnce(); err != nil {
			return err
		}
		if cfg.EnableTasks {
			processTasks(ctx, cfg, client, collector, debug)
		}
		return nil
	}
	interval := time.Duration(cfg.IntervalSeconds) * time.Second
	if interval <= 0 {
		interval = time.Minute
	}
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	var taskTicker *time.Ticker
	if cfg.EnableTasks {
		taskInterval := time.Duration(cfg.TaskIntervalSeconds) * time.Second
		if taskInterval <= 0 {
			taskInterval = 10 * time.Second
		}
		taskTicker = time.NewTicker(taskInterval)
		defer taskTicker.Stop()
	}
	for {
		if err := reportOnce(); err != nil {
			log.Printf("[WARN] report failed: %s", RedactString(err.Error()))
		}
		if cfg.EnableTasks {
			processTasks(ctx, cfg, client, collector, debug)
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-ticker.C:
		case <-taskTickerC(taskTicker):
			if cfg.EnableTasks {
				processTasks(ctx, cfg, client, collector, debug)
			}
		}
	}
}

func taskTickerC(t *time.Ticker) <-chan time.Time {
	if t == nil {
		return nil
	}
	return t.C
}

func processTasks(ctx context.Context, cfg Config, client Client, collector Collector, debug bool) {
	if !taskExecutionLock.TryLock() {
		log.Printf("[WARN] readonly task already running; skip this poll")
		return
	}
	defer taskExecutionLock.Unlock()
	tasks, err := client.GetTasks(ctx, cfg.NodeID)
	if err != nil {
		log.Printf("[WARN] task poll failed: %s", RedactString(err.Error()))
		return
	}
	for _, task := range tasks {
		if debug {
			log.Printf("task picked: %s", RedactForLog(task))
		}
		result := ExecuteTask(ctx, collector, cfg, task)
		if debug {
			log.Printf("task result: %s", RedactForLog(result))
		}
		if err := client.ReportTaskResult(ctx, task.ID, result); err != nil {
			log.Printf("[WARN] task result failed: %s", RedactString(err.Error()))
		}
	}
}
