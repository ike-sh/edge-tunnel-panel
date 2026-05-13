package controller

import (
	"fmt"
	"strings"
)

const defaultAgentInstallVersion = "v0.3.1-test"
const defaultGitHubMirrors = "https://gh.llkk.cc/,https://gh.ddlc.top/,https://gh-proxy.com/,https://ghproxy.net/"

func installScriptURL() string {
	return "https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-agent.sh"
}

func buildAgentInstallCommand(prefix, version, controllerURL, token, nodeName, role string, enableTasks, enableWrites bool) string {
	return buildAgentInstallCommandWithURL(prefix, installScriptURL(), "", version, controllerURL, token, nodeName, role, enableTasks, enableWrites)
}

func buildAgentInstallCommandWithURL(prefix, scriptURL, mirrors, version, controllerURL, token, nodeName, role string, enableTasks, enableWrites bool) string {
	args := fmt.Sprintf("--version %s --controller-url %s --token %s --node-name %s", version, controllerURL, token, nodeName)
	if strings.TrimSpace(role) != "" {
		args += " --role " + strings.TrimSpace(role)
	}
	if enableTasks {
		args += " --enable-tasks"
	}
	if enableWrites {
		args += " --enable-write-actions"
	}
	executor := "bash"
	if strings.TrimSpace(prefix) != "" {
		executor = strings.TrimSpace(prefix) + " bash"
	}
	envPrefix := ""
	if strings.TrimSpace(mirrors) != "" {
		envPrefix = fmt.Sprintf("EDGE_GITHUB_MIRRORS=%q ", strings.TrimSpace(mirrors))
	}
	return fmt.Sprintf("%scurl -fsSL %s | %s -s -- %s", envPrefix, scriptURL, executor, args)
}

func mirrorScriptURLs(mirrors string) []string {
	out := []string{}
	for _, mirror := range strings.Split(mirrors, ",") {
		mirror = strings.TrimRight(strings.TrimSpace(mirror), "/")
		if mirror != "" {
			out = append(out, mirror+"/"+installScriptURL())
		}
	}
	return out
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
