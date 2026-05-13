package agent

import (
	"errors"
	"os"
	"strings"
	"time"
)

func DefaultConfig() Config {
	host, _ := os.Hostname()
	if strings.TrimSpace(host) == "" {
		host = "edge-node"
	}
	return Config{
		NodeName:           host,
		NodeRole:           "backend",
		ConfigDir:          "/etc/edge-tunnel/agent",
		StateDir:           "/var/lib/edge-tunnel/agent",
		PollInterval:       5 * time.Second,
		ReportInterval:     15 * time.Second,
		TaskResultLimitKB:  defaultTaskResultLimitKB,
		MaxConcurrentTasks: 1,
	}
}

func ConfigFromEnv() Config {
	cfg := DefaultConfig()
	cfg.ControllerURL = strings.TrimSpace(os.Getenv("EDGE_CONTROLLER_URL"))
	cfg.ControllerToken = strings.TrimSpace(os.Getenv("EDGE_CONTROLLER_TOKEN"))
	cfg.NodeID = strings.TrimSpace(os.Getenv("EDGE_NODE_ID"))
	cfg.NodeName = envOrDefault("EDGE_NODE_NAME", cfg.NodeName)
	cfg.NodeRole = envOrDefault("EDGE_NODE_ROLE", cfg.NodeRole)
	cfg.ConfigDir = envOrDefault("EDGE_AGENT_CONFIG_DIR", cfg.ConfigDir)
	cfg.StateDir = envOrDefault("EDGE_AGENT_STATE_DIR", cfg.StateDir)
	cfg.EnableTasks = parseBool(os.Getenv("EDGE_ENABLE_TASKS"))
	cfg.EnableWriteActions = parseBool(os.Getenv("EDGE_ENABLE_WRITE_ACTIONS"))
	_ = cfg.Normalize()
	return cfg
}

func (cfg *Config) Normalize() error {
	cfg.ControllerURL = strings.TrimRight(strings.TrimSpace(cfg.ControllerURL), "/")
	cfg.ControllerToken = strings.TrimSpace(cfg.ControllerToken)
	cfg.NodeID = strings.TrimSpace(cfg.NodeID)
	cfg.NodeName = strings.TrimSpace(cfg.NodeName)
	cfg.NodeRole = normalizeRole(cfg.NodeRole)
	if cfg.NodeName == "" {
		cfg.NodeName = "edge-node"
	}
	if cfg.ConfigDir == "" {
		cfg.ConfigDir = "/etc/edge-tunnel/agent"
	}
	if cfg.StateDir == "" {
		cfg.StateDir = "/var/lib/edge-tunnel/agent"
	}
	if cfg.PollInterval <= 0 {
		cfg.PollInterval = 5 * time.Second
	}
	if cfg.ReportInterval <= 0 {
		cfg.ReportInterval = 15 * time.Second
	}
	if cfg.TaskResultLimitKB <= 0 {
		cfg.TaskResultLimitKB = defaultTaskResultLimitKB
	}
	if cfg.MaxConcurrentTasks <= 0 {
		cfg.MaxConcurrentTasks = 1
	}
	return nil
}

func (cfg Config) Validate() error {
	if strings.TrimSpace(cfg.ControllerURL) == "" {
		return errors.New("controller url is required")
	}
	if strings.TrimSpace(cfg.ControllerToken) == "" {
		return errors.New("controller token is required")
	}
	return nil
}

func envOrDefault(key, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(key)); value != "" {
		return value
	}
	return fallback
}

func parseBool(value string) bool {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "1", "true", "yes", "y", "on", "enabled":
		return true
	default:
		return false
	}
}

func normalizeRole(role string) string {
	switch strings.ToLower(strings.TrimSpace(role)) {
	case "controller", "entry", "relay", "exit", "backend":
		return strings.ToLower(strings.TrimSpace(role))
	default:
		return "backend"
	}
}
