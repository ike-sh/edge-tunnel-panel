package controller

import (
	"fmt"
	"strings"
)

const defaultAgentInstallVersion = "latest"
const defaultGitHubMirrors = "https://gh.llkk.cc/,https://gh.ddlc.top/,https://gh-proxy.com/,https://ghproxy.net/"

func quickInstallScriptURL() string {
	return "https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/quick-install.sh"
}

func installScriptURL() string {
	return "https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-agent.sh"
}

func mirrorQuickInstallURL(mirror string) string {
	mirror = strings.TrimRight(strings.TrimSpace(mirror), "/")
	if mirror == "" {
		mirror = "https://gh.llkk.cc"
	}
	return mirror + "/" + quickInstallScriptURL()
}

func buildQuickInstallAgentCommand(prefix string, useCN bool, version, controllerURL, token, machineID, nodeName string) string {
	executor := "bash"
	if strings.TrimSpace(prefix) != "" {
		executor = strings.TrimSpace(prefix) + " bash"
	}
	scriptURL := quickInstallScriptURL()
	flags := ""
	if useCN {
		scriptURL = mirrorQuickInstallURL("https://gh.llkk.cc")
		flags = "--cn "
	}
	if strings.TrimSpace(version) != "" && version != "latest" {
		flags += fmt.Sprintf("--version %s ", version)
	}
	body := fmt.Sprintf(`curl -fsSL %s | %s -s -- %sagent \
  --url %s \
  --token %s \
  --name %s`, scriptURL, executor, flags, controllerURL, token, nodeName)
	if strings.TrimSpace(machineID) != "" {
		body += fmt.Sprintf(" \\\n  --machine-id %s", machineID)
	}
	return body
}

func buildAgentInstallCommand(prefix, version, controllerURL, token, nodeName, role string, enableTasks, enableWrites bool) string {
	_ = role
	_ = enableTasks
	_ = enableWrites
	return buildQuickInstallAgentCommand(prefix, false, version, controllerURL, token, "", nodeName)
}

func buildAgentInstallCommandWithURL(prefix, scriptURL, mirrors, version, controllerURL, token, nodeName, role string, enableTasks, enableWrites bool) string {
	_ = scriptURL
	_ = mirrors
	_ = role
	_ = enableTasks
	_ = enableWrites
	useCN := strings.TrimSpace(mirrors) != ""
	return buildQuickInstallAgentCommand(prefix, useCN, version, controllerURL, token, "", nodeName)
}

func mirrorScriptURLs(mirrors string) []string {
	out := []string{}
	for _, mirror := range strings.Split(mirrors, ",") {
		mirror = strings.TrimRight(strings.TrimSpace(mirror), "/")
		if mirror != "" {
			out = append(out, mirror+"/"+quickInstallScriptURL())
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
