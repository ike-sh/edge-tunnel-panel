package controller

import "fmt"

func installScriptURL() string {
	return "https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-agent.sh"
}

func buildAgentInstallCommand(controllerURL, token, nodeName, role string, enableTasks, enableWrites bool) string {
	args := fmt.Sprintf("--controller-url %s --token %s --node-name %s --role %s", controllerURL, token, nodeName, role)
	if enableTasks {
		args += " --enable-tasks"
	}
	if enableWrites {
		args += " --enable-write-actions"
	}
	return fmt.Sprintf("curl -fsSL %s | sudo bash -s -- %s", installScriptURL(), args)
}
