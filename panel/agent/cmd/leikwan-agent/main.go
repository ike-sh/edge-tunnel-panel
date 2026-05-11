package main

import (
	"context"
	"flag"
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/ike-sh/leikwan-toolkit/panel/agent/internal/agent"
)

func main() {
	configPath := flag.String("config", "", "agent config path")
	once := flag.Bool("once", false, "collect and report once")
	debug := flag.Bool("debug", false, "enable debug logging without printing secrets")
	flag.Parse()

	cfg, err := agent.LoadConfig(*configPath)
	if err != nil {
		log.Fatalf("load config: %v", err)
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	if err := agent.Run(ctx, cfg, *once, *debug); err != nil {
		log.Fatal(agent.RedactString(err.Error()))
	}
}
