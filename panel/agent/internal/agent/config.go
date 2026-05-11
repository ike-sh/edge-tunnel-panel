package agent

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
)

const defaultConfigPath = "/etc/leikwan-agent/config.yml"

func LoadConfig(path string) (Config, error) {
	if path == "" {
		path = defaultConfigPath
		if _, err := os.Stat(path); err != nil {
			if _, localErr := os.Stat("./agent.yml"); localErr == nil {
				path = "./agent.yml"
			}
		}
	}
	cfg := Config{Role: "unknown", IntervalSeconds: 60}
	if path == "" {
		return cfg, nil
	}
	file, err := os.Open(path)
	if err != nil {
		return cfg, err
	}
	defer file.Close()
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		parts := strings.SplitN(line, ":", 2)
		if len(parts) != 2 {
			continue
		}
		key := strings.TrimSpace(parts[0])
		value := strings.TrimSpace(parts[1])
		value = strings.Trim(value, `"'`)
		switch key {
		case "controller_url":
			cfg.ControllerURL = value
		case "token":
			cfg.Token = value
		case "node_id":
			cfg.NodeID = value
		case "node_name":
			cfg.NodeName = value
		case "role":
			cfg.Role = normalizeRole(value)
		case "interval_seconds":
			n, err := strconv.Atoi(value)
			if err == nil && n > 0 {
				cfg.IntervalSeconds = n
			}
		}
	}
	if err := scanner.Err(); err != nil {
		return cfg, err
	}
	if cfg.ControllerURL == "" {
		return cfg, fmt.Errorf("controller_url is required")
	}
	if cfg.NodeID == "" {
		host, _ := os.Hostname()
		if host != "" {
			cfg.NodeID = host
		}
	}
	if cfg.NodeName == "" {
		cfg.NodeName = cfg.NodeID
	}
	return cfg, nil
}

func normalizeRole(role string) string {
	switch role {
	case "entry", "relay", "backend", "mixed", "unknown":
		return role
	default:
		return "unknown"
	}
}
