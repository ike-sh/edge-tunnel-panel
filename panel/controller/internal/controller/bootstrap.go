package controller

import (
	"fmt"
	"strings"
)

const defaultAgentInstallVersion = "v0.1.2-test"

func installScriptURL() string {
	return "https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-agent.sh"
}

func buildAgentInstallCommand(version, controllerURL, token, nodeName, role string, enableTasks, enableWrites bool) string {
	args := fmt.Sprintf("--version %s --controller-url %s --token %s --node-name %s --role %s", version, controllerURL, token, nodeName, role)
	if enableTasks {
		args += " --enable-tasks"
	}
	if enableWrites {
		args += " --enable-write-actions"
	}
	return fmt.Sprintf("curl -fsSL %s | sudo bash -s -- %s", installScriptURL(), args)
}

func boolRequestValue(req map[string]any, key string, fallback bool) bool {
	value, ok := req[key]
	if !ok {
		return fallback
	}
	if b, ok := value.(bool); ok {
		return b
	}
	if s, ok := value.(string); ok {
		switch strings.ToLower(strings.TrimSpace(s)) {
		case "true", "1", "yes", "on":
			return true
		case "false", "0", "no", "off":
			return false
		}
	}
	return fallback
}
