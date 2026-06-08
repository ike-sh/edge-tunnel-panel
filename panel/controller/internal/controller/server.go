package controller

import (
	"encoding/json"
	"net"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

type Server struct {
	store         *Store
	agentToken    string
	operatorToken string
	strictAuth    bool
	webDir        string
	legacyV1API   bool
}

func legacyV1Enabled() bool {
	v := strings.ToLower(strings.TrimSpace(os.Getenv("EDGE_LEGACY_V1_API")))
	return v == "1" || v == "true" || v == "yes"
}

func NewServer(store *Store, agentToken, operatorToken string, strictAuth bool, webDir string) http.Handler {
	s := &Server{store: store, agentToken: agentToken, operatorToken: operatorToken, strictAuth: strictAuth, webDir: webDir, legacyV1API: legacyV1Enabled()}
	mux := http.NewServeMux()
	mux.HandleFunc("/api/v1/health", s.handleHealth)
	mux.HandleFunc("/api/v1/login", s.handleLogin)
	mux.HandleFunc("/api/v1/bootstrap/controller-info", s.handleBootstrapInfo)
	mux.HandleFunc("/api/v1/bootstrap/agent-install-command", s.handleBootstrapAgentInstall)
	mux.HandleFunc("/api/v1/nodes", s.handleNodes)
	mux.HandleFunc("/api/v1/nodes/", s.handleNodes)
	mux.HandleFunc("/api/v1/agent/register", s.handleAgentRegister)
	mux.HandleFunc("/api/v1/agent/report", s.handleAgentReport)
	mux.HandleFunc("/api/v1/agent/unregister", s.handleAgentUnregister)
	mux.HandleFunc("/api/v1/agent/tasks", s.handleAgentTasks)
	mux.HandleFunc("/api/v1/agent/tasks/", s.handleAgentTaskResult)
	if s.legacyV1API {
		mux.HandleFunc("/api/v1/network-profiles", s.handleNetworkProfiles)
		mux.HandleFunc("/api/v1/network-profiles/", s.handleNetworkProfiles)
		mux.HandleFunc("/api/v1/network-links", s.handleNetworkLinks)
		mux.HandleFunc("/api/v1/network-links/", s.handleNetworkLinks)
		mux.HandleFunc("/api/v1/entries", s.handleEntries)
		mux.HandleFunc("/api/v1/entries/", s.handleEntries)
		mux.HandleFunc("/api/v1/forwards", s.handleForwards)
		mux.HandleFunc("/api/v1/forwards/", s.handleForwards)
		mux.HandleFunc("/api/v1/pbr-policies", s.handlePBRPolicies)
		mux.HandleFunc("/api/v1/pbr-policies/", s.handlePBRPolicies)
	} else {
		deprecated := s.handleDeprecatedV1
		mux.HandleFunc("/api/v1/network-profiles", deprecated)
		mux.HandleFunc("/api/v1/network-profiles/", deprecated)
		mux.HandleFunc("/api/v1/network-links", deprecated)
		mux.HandleFunc("/api/v1/network-links/", deprecated)
		mux.HandleFunc("/api/v1/entries", deprecated)
		mux.HandleFunc("/api/v1/entries/", deprecated)
		mux.HandleFunc("/api/v1/forwards", deprecated)
		mux.HandleFunc("/api/v1/forwards/", deprecated)
		mux.HandleFunc("/api/v1/pbr-policies", deprecated)
		mux.HandleFunc("/api/v1/pbr-policies/", deprecated)
	}
	mux.HandleFunc("/api/v1/diagnostics/run", s.handleDiagnosticsRun)
	mux.HandleFunc("/api/v1/diagnostics/", s.handleDiagnostics)
	mux.HandleFunc("/api/v1/tasks", s.handleTasks)
	mux.HandleFunc("/api/v1/tasks/", s.handleTasks)
	mux.HandleFunc("/api/v1/ddns", s.handleDDNS)
	s.registerV2Routes(mux)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasPrefix(r.URL.Path, "/api/v1/") || strings.HasPrefix(r.URL.Path, "/api/v2/") {
			s.apiMiddleware(mux).ServeHTTP(w, r)
			return
		}
		s.serveWeb(w, r)
	})
}

func (s *Server) serveWeb(w http.ResponseWriter, r *http.Request) {
	webDir := s.webDir
	if webDir == "" {
		webDir = os.Getenv("EDGE_WEB_DIR")
	}
	if webDir == "" {
		webDir = "/var/lib/edge-tunnel/controller/web"
	}
	indexPath := filepath.Join(webDir, "index.html")
	reqPath := path.Clean("/" + r.URL.Path)
	if reqPath == "/" {
		http.ServeFile(w, r, indexPath)
		return
	}
	rel := strings.TrimPrefix(reqPath, "/")
	target := filepath.Join(webDir, rel)
	absWeb, err := filepath.Abs(webDir)
	if err != nil {
		http.Error(w, "invalid web directory", http.StatusInternalServerError)
		return
	}
	absTarget, err := filepath.Abs(target)
	if err != nil {
		http.Error(w, "invalid path", http.StatusBadRequest)
		return
	}
	if absTarget != absWeb && !strings.HasPrefix(absTarget, absWeb+string(os.PathSeparator)) {
		http.Error(w, "invalid path", http.StatusBadRequest)
		return
	}
	if st, err := os.Stat(absTarget); err == nil && !st.IsDir() {
		http.ServeFile(w, r, absTarget)
		return
	}
	if isStaticAssetPath(reqPath) {
		http.NotFound(w, r)
		return
	}
	if _, err := os.Stat(indexPath); err != nil {
		http.Error(w, "Edge Tunnel Panel web assets not found", http.StatusInternalServerError)
		return
	}
	http.ServeFile(w, r, indexPath)
}

func isStaticAssetPath(p string) bool {
	if strings.HasPrefix(p, "/assets/") {
		return true
	}
	switch strings.ToLower(filepath.Ext(p)) {
	case ".js", ".css", ".map", ".ico", ".png", ".jpg", ".jpeg", ".svg", ".webp", ".json", ".txt":
		return true
	default:
		return false
	}
}

func writeOK(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(APIResponse{OK: true, Data: data})
}
func writeErr(w http.ResponseWriter, status int, code, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(APIResponse{OK: false, Error: &APIError{Code: code, Message: message}})
}
func stringValue(v any, fallback string) string {
	if s, ok := v.(string); ok && strings.TrimSpace(s) != "" {
		return s
	}
	return fallback
}
func observedPublicIP(remoteAddr string) string {
	host, _, err := net.SplitHostPort(remoteAddr)
	if err != nil {
		host = remoteAddr
	}
	ip := net.ParseIP(strings.Trim(host, "[]"))
	if ip == nil || ip.IsLoopback() || ip.IsUnspecified() || ip.IsPrivate() {
		return ""
	}
	if ip4 := ip.To4(); ip4 != nil && ip4[0] == 100 && ip4[1] >= 64 && ip4[1] <= 127 {
		return ""
	}
	return ip.String()
}
func boolValue(v any) bool { b, _ := v.(bool); return b }
func boolValueDefault(v any, fallback bool) bool {
	if b, ok := v.(bool); ok {
		return b
	}
	return fallback
}
func intValue(v any) int {
	switch n := v.(type) {
	case float64:
		return int(n)
	case int:
		return n
	default:
		return 0
	}
}

func numberValue(v any) int {
	switch n := v.(type) {
	case float64:
		return int(n)
	case int:
		return n
	case json.Number:
		value, _ := n.Int64()
		return int(value)
	default:
		return 0
	}
}

func uint64Value(v any) uint64 {
	switch n := v.(type) {
	case float64:
		if n < 0 {
			return 0
		}
		return uint64(n)
	case int:
		if n < 0 {
			return 0
		}
		return uint64(n)
	case int64:
		if n < 0 {
			return 0
		}
		return uint64(n)
	case json.Number:
		value, _ := n.Int64()
		if value < 0 {
			return 0
		}
		return uint64(value)
	default:
		return 0
	}
}

func floatValue(v any) float64 {
	switch n := v.(type) {
	case float64:
		return n
	case float32:
		return float64(n)
	case int:
		return float64(n)
	case json.Number:
		value, _ := n.Float64()
		return value
	default:
		return 0
	}
}

func (s *Server) requireOperator(w http.ResponseWriter, r *http.Request) bool {
	if !s.strictAuth {
		return true
	}
	if tokenMatches(bearerToken(r), s.operatorToken) {
		return true
	}
	writeErr(w, 401, "UNAUTHORIZED", "operator token required")
	return false
}
func (s *Server) requireAgent(w http.ResponseWriter, r *http.Request) bool {
	tok := bearerToken(r)
	if tokenMatches(tok, s.agentToken) {
		return true
	}
	if s.store.matchMachineToken(tok) {
		return true
	}
	writeErr(w, 401, "UNAUTHORIZED", "agent token required")
	return false
}
func decodeBody(w http.ResponseWriter, r *http.Request) (map[string]any, bool) {
	var req map[string]any
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeErr(w, 400, "BAD_REQUEST", "invalid json")
		return nil, false
	}
	return req, true
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	writeOK(w, 200, HealthResponse{Name: "edge-tunnel-controller", Version: Version, BuildCommit: Commit, BuildTime: Date, StrictAuth: s.strictAuth, LegacyV1API: s.legacyV1API})
}

func (s *Server) handleDeprecatedV1(w http.ResponseWriter, r *http.Request) {
	writeErr(w, 410, "deprecated", "v1 API 已废弃，请使用 /api/v2（设置 EDGE_LEGACY_V1_API=1 可临时恢复）")
}
func (s *Server) handleLogin(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeErr(w, 405, "METHOD_NOT_ALLOWED", "method not allowed")
		return
	}
	var req LoginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeErr(w, 400, "BAD_REQUEST", "invalid json")
		return
	}
	if !tokenMatches(req.Token, s.operatorToken) {
		writeErr(w, 401, "UNAUTHORIZED", "invalid operator token")
		return
	}
	writeOK(w, 200, map[string]any{"authenticated": true})
}
func (s *Server) handleBootstrapInfo(w http.ResponseWriter, r *http.Request) {
	if !s.requireOperator(w, r) {
		return
	}
	writeOK(w, 200, map[string]any{"install_script_url": quickInstallScriptURL(), "agent_script_url": installScriptURL(), "default_node_name": "edge-node-1", "default_version": defaultAgentInstallVersion, "default_github_mirrors": defaultGitHubMirrors, "repo": "ike-sh/edge-tunnel-panel"})
}
func (s *Server) handleBootstrapAgentInstall(w http.ResponseWriter, r *http.Request) {
	if !s.requireOperator(w, r) {
		return
	}
	req, ok := decodeBody(w, r)
	if !ok {
		return
	}
	version := stringValue(req["version"], defaultAgentInstallVersion)
	controllerURL := stringValue(req["controller_url"], "http://127.0.0.1:18080")
	nodeName := stringValue(req["node_name"], "edge-node-1")
	role := stringValue(req["role"], "node")
	enableTasks := boolRequestValue(req, "enable_tasks", true)
	enableWrites := boolRequestValue(req, "enable_write_actions", true)
	downloadSource := stringValue(req["download_source"], "official")
	mirrors := stringValue(req["github_mirrors"], "")
	if downloadSource == "mirror" && strings.TrimSpace(mirrors) == "" {
		mirrors = defaultGitHubMirrors
	}
	rootCommand := buildAgentInstallCommand("", version, controllerURL, s.agentToken, nodeName, role, enableTasks, enableWrites)
	sudoCommand := buildAgentInstallCommand("sudo", version, controllerURL, s.agentToken, nodeName, role, enableTasks, enableWrites)
	mirrorRoots := []string{}
	mirrorSudos := []string{}
	for _, scriptURL := range mirrorScriptURLs(mirrors) {
		mirrorRoots = append(mirrorRoots, buildAgentInstallCommandWithURL("", scriptURL, mirrors, version, controllerURL, s.agentToken, nodeName, role, enableTasks, enableWrites))
		mirrorSudos = append(mirrorSudos, buildAgentInstallCommandWithURL("sudo", scriptURL, mirrors, version, controllerURL, s.agentToken, nodeName, role, enableTasks, enableWrites))
	}
	if downloadSource == "mirror" && len(mirrorRoots) > 0 {
		rootCommand = mirrorRoots[0]
		sudoCommand = mirrorSudos[0]
	}
	data := map[string]any{
		"root_command":             rootCommand,
		"sudo_command":             sudoCommand,
		"recommended_command":      rootCommand,
		"masked_command":           buildAgentInstallCommand("", version, controllerURL, redactToken(s.agentToken), nodeName, role, enableTasks, enableWrites),
		"command":                  rootCommand,
		"full_command":             rootCommand,
		"can_copy":                 true,
		"copy_requires_full_token": false,
		"version":                  version,
		"node_id":                  "",
		"role":                     role,
		"node_name":                nodeName,
		"enable_tasks":             enableTasks,
		"enable_write_actions":     enableWrites,
		"download_source":          downloadSource,
		"github_mirrors":           mirrors,
		"mirror_root_commands":     mirrorRoots,
		"mirror_sudo_commands":     mirrorSudos,
	}
	writeOK(w, 200, data)
}
func (s *Server) handleNodes(w http.ResponseWriter, r *http.Request) {
	if !s.requireOperator(w, r) {
		return
	}
	if strings.HasPrefix(r.URL.Path, "/api/v1/nodes/") {
		id := strings.Trim(strings.TrimPrefix(r.URL.Path, "/api/v1/nodes/"), "/")
		if id == "" {
			writeErr(w, 404, "NOT_FOUND", "node not found")
			return
		}
		if r.Method == http.MethodDelete {
			mode := strings.TrimSpace(r.URL.Query().Get("mode"))
			if mode == "" {
				mode = "record_only"
			}
			if mode == "clean_deployed" || mode == "purge_agent" {
				node, found := s.store.getNode(id)
				if !found {
					writeErr(w, 404, "NOT_FOUND", "node not found")
					return
				}
				if node.Status != "online" {
					writeErr(w, 409, "NODE_OFFLINE", "节点离线，无法远程清理；可以选择仅删除面板记录。")
					return
				}
				action := "cleanup_node_deployment"
				if mode == "purge_agent" {
					action = "purge_agent_deployment"
				}
				task, err := s.store.createTask(Task{NodeID: id, Action: action, Payload: map[string]any{"node_id": id, "mode": mode}})
				if err != nil {
					writeErr(w, 500, "STORE_ERROR", err.Error())
					return
				}
				writeOK(w, 202, map[string]any{"queued": true, "mode": mode, "task": task, "message": "已创建远程清理任务，节点上线时会执行。"})
				return
			}
			if mode != "record_only" {
				writeErr(w, 400, "BAD_REQUEST", "mode must be record_only, clean_deployed, or purge_agent")
				return
			}
			deleted, err := s.store.deleteNode(id)
			if err != nil {
				writeErr(w, 500, "STORE_ERROR", err.Error())
				return
			}
			if !deleted {
				writeErr(w, 404, "NOT_FOUND", "node not found")
				return
			}
			writeOK(w, 200, map[string]any{"deleted": true, "id": id})
			return
		}
		if r.Method == http.MethodGet {
			node, found := s.store.getNode(id)
			if !found {
				writeErr(w, 404, "NOT_FOUND", "node not found")
				return
			}
			writeOK(w, 200, node)
			return
		}
		writeErr(w, 405, "METHOD_NOT_ALLOWED", "method not allowed")
		return
	}
	writeOK(w, 200, s.store.listNodes())
}
func (s *Server) handleAgentRegister(w http.ResponseWriter, r *http.Request) {
	if !s.requireAgent(w, r) {
		return
	}
	req, ok := decodeBody(w, r)
	if !ok {
		return
	}
	node, err := s.store.createNode(Node{ID: stringValue(req["id"], ""), Name: stringValue(req["name"], stringValue(req["node_name"], "edge-node")), Role: stringValue(req["role"], "relay"), Hostname: stringValue(req["hostname"], ""), Status: "online", LastSeenAt: time.Now().UTC(), Capabilities: map[string]bool{}})
	if err != nil {
		writeErr(w, 500, "STORE_ERROR", err.Error())
		return
	}
	machineID, ok := s.resolveMachineBinding(w, r, stringValue(req["machine_id"], ""))
	if !ok {
		return
	}
	if machineID != "" {
		if activated, err := s.store.linkMachineToNode(machineID, node.ID); err == nil {
			node.Labels = map[string]string{"machine_id": machineID, "activated_tasks": strconv.Itoa(activated)}
		}
	}
	writeOK(w, 200, node)
}
func (s *Server) handleAgentReport(w http.ResponseWriter, r *http.Request) {
	if !s.requireAgent(w, r) {
		return
	}
	req, ok := decodeBody(w, r)
	if !ok {
		return
	}
	caps := map[string]bool{}
	if m, ok := req["capabilities"].(map[string]any); ok {
		for k, v := range m {
			if b, ok := v.(bool); ok {
				caps[k] = b
			}
		}
	}
	observedIP := observedPublicIP(r.RemoteAddr)
	publicIP := stringValue(req["public_ip"], "")
	if publicIP == "" && observedIP != "" {
		publicIP = observedIP
	}
	node, err := s.store.upsertReport(Node{ID: stringValue(req["id"], ""), Name: stringValue(req["name"], stringValue(req["node_name"], "edge-node")), Role: stringValue(req["role"], "relay"), PublicIP: publicIP, PrivateIP: stringValue(req["private_ip"], ""), ObservedIP: observedIP, AgentVersion: stringValue(req["agent_version"], ""), Hostname: stringValue(req["hostname"], ""), OS: stringValue(req["os"], ""), Arch: stringValue(req["arch"], ""), EasyTierIP: stringValue(req["easytier_ip"], ""), EasyTierStatus: stringValue(req["easytier_status"], "unknown"), EasyTierPeerCount: numberValue(req["easytier_peer_count"]), EasyTierHasRemotePeer: boolValue(req["easytier_has_remote_peer"]), EasyTierBestLatencyMS: floatValue(req["easytier_best_latency_ms"]), EasyTierPacketLoss: stringValue(req["easytier_packet_loss"], ""), EasyTierTunnels: stringListValue(req["easytier_tunnels"]), EasyTierRouteType: stringValue(req["easytier_route_type"], ""), EasyTierNetworkOK: boolValue(req["easytier_network_ok"]), EasyTierNetworkReason: stringValue(req["easytier_network_reason"], ""), EasyTierDHCPEnabled: boolValue(req["easytier_dhcp_enabled"]), EasyTierCIDR: stringValue(req["easytier_cidr"], ""), CPUPercent: floatValue(req["cpu_percent"]), MemPercent: floatValue(req["mem_percent"]), MemTotalMB: uint64Value(req["mem_total_mb"]), MemUsedMB: uint64Value(req["mem_used_mb"]), UptimeSec: uint64Value(req["uptime_sec"]), BytesSent: uint64Value(req["bytes_sent"]), BytesReceived: uint64Value(req["bytes_received"]), NetTxBPS: uint64Value(req["net_tx_bps"]), NetRxBPS: uint64Value(req["net_rx_bps"]), LastSeenAt: time.Now().UTC(), Status: "online", StatusReason: "recent heartbeat normal", Capabilities: caps, Labels: map[string]string{}})
	if err != nil {
		writeErr(w, 500, "STORE_ERROR", err.Error())
		return
	}
	machineID, ok := s.resolveMachineBinding(w, r, stringValue(req["machine_id"], ""))
	if !ok {
		return
	}
	if machineID != "" {
		_, _ = s.store.linkMachineToNode(machineID, node.ID)
	}
	writeOK(w, 200, node)
}

func (s *Server) handleAgentUnregister(w http.ResponseWriter, r *http.Request) {
	if !s.requireAgent(w, r) {
		return
	}
	if r.Method != http.MethodPost {
		writeErr(w, 405, "METHOD_NOT_ALLOWED", "method not allowed")
		return
	}
	req, ok := decodeBody(w, r)
	if !ok {
		return
	}
	nodeID := stringValue(req["node_id"], stringValue(req["id"], ""))
	if nodeID == "" {
		writeErr(w, 400, "BAD_REQUEST", "node_id is required")
		return
	}
	reason := stringValue(req["reason"], "agent reported offline")
	node, found, err := s.store.markNodeOffline(nodeID, reason)
	if err != nil {
		writeErr(w, 500, "STORE_ERROR", err.Error())
		return
	}
	writeOK(w, 200, map[string]any{"unregistered": found, "node": node})
}
func (s *Server) handleAgentTasks(w http.ResponseWriter, r *http.Request) {
	if !s.requireAgent(w, r) {
		return
	}
	nodeID := r.URL.Query().Get("node_id")
	writeOK(w, 200, s.store.tasksForNode(nodeID))
}
func (s *Server) handleAgentTaskResult(w http.ResponseWriter, r *http.Request) {
	if !s.requireAgent(w, r) {
		return
	}
	req, ok := decodeBody(w, r)
	if !ok {
		return
	}
	id := strings.TrimPrefix(r.URL.Path, "/api/v1/agent/tasks/")
	id = strings.TrimSuffix(id, "/result")
	task, found, err := s.store.updateTaskResult(id, req)
	if err != nil {
		writeErr(w, 500, "STORE_ERROR", err.Error())
		return
	}
	if !found {
		writeErr(w, 404, "NOT_FOUND", "task not found")
		return
	}
	writeOK(w, 200, task)
}
func (s *Server) handleNetworkProfiles(w http.ResponseWriter, r *http.Request) {
	if !s.requireOperator(w, r) {
		return
	}
	if r.Method == http.MethodGet {
		writeOK(w, 200, s.store.listNetworkProfiles())
		return
	}
	if r.URL.Path == "/api/v1/network-profiles/quick-apply" && r.Method == http.MethodPost {
		s.handleNetworkProfileQuickApply(w, r)
		return
	}
	id, action := splitCollectionPath(r.URL.Path, "/api/v1/network-profiles/")
	if action == "apply" && r.Method == http.MethodPost {
		s.handleNetworkProfileApply(w, r, id)
		return
	}
	if id != "" {
		switch r.Method {
		case http.MethodPut:
			req, ok := decodeBody(w, r)
			if !ok {
				return
			}
			if payloadHasDangerousKeys(req) {
				writeErr(w, 400, "DANGEROUS_PAYLOAD", "dangerous payload keys are not allowed")
				return
			}
			item, found, err := s.store.updateNetworkProfile(id, req)
			if err != nil {
				writeErr(w, 500, "STORE_ERROR", err.Error())
				return
			}
			if !found {
				writeErr(w, 404, "NOT_FOUND", "network profile not found")
				return
			}
			writeOK(w, 200, item)
			return
		case http.MethodDelete:
			found, err := s.store.deleteNetworkProfile(id)
			if err != nil {
				writeErr(w, 500, "STORE_ERROR", err.Error())
				return
			}
			if !found {
				writeErr(w, 404, "NOT_FOUND", "network profile not found")
				return
			}
			writeOK(w, 200, map[string]bool{"deleted": true})
			return
		}
	}
	if r.Method != http.MethodPost || r.URL.Path != "/api/v1/network-profiles" {
		writeErr(w, 405, "METHOD_NOT_ALLOWED", "method not allowed")
		return
	}
	req, ok := decodeBody(w, r)
	if !ok {
		return
	}
	if payloadHasDangerousKeys(req) {
		writeErr(w, 400, "DANGEROUS_PAYLOAD", "dangerous payload keys are not allowed")
		return
	}
	item, err := s.store.createNetworkProfile(req)
	if err != nil {
		writeErr(w, 400, "BAD_REQUEST", err.Error())
		return
	}
	writeOK(w, 200, item)
}

func (s *Server) handleNetworkProfileQuickApply(w http.ResponseWriter, r *http.Request) {
	req, ok := decodeBody(w, r)
	if !ok {
		return
	}
	s.quickApplyNetwork(w, req)
}

func (s *Server) quickApplyNetwork(w http.ResponseWriter, req map[string]any) {
	if payloadHasDangerousKeys(req) {
		writeErr(w, 400, "DANGEROUS_PAYLOAD", "dangerous payload keys are not allowed")
		return
	}
	entryNodeID := stringValue(req["entry_node_id"], "")
	backendNodeID := stringValue(req["backend_node_id"], "")
	if entryNodeID == "" || backendNodeID == "" {
		writeErr(w, 400, "BAD_REQUEST", "entry_node_id and backend_node_id are required")
		return
	}
	if entryNodeID == backendNodeID {
		writeErr(w, 400, "BAD_REQUEST", "entry and backend nodes must be different")
		return
	}
	entryNode, found := s.store.getNode(entryNodeID)
	if !found {
		writeErr(w, 404, "NOT_FOUND", "entry node not found")
		return
	}
	backendNode, found := s.store.getNode(backendNodeID)
	if !found {
		writeErr(w, 404, "NOT_FOUND", "backend node not found")
		return
	}
	if entryNode.Status != "online" {
		writeErr(w, 400, "BAD_REQUEST", "entry node must be online")
		return
	}
	if backendNode.Status != "online" {
		writeErr(w, 400, "BAD_REQUEST", "backend node must be online")
		return
	}
	if strings.TrimSpace(entryNode.PublicIP) == "" {
		writeErr(w, 400, "BAD_REQUEST", "entry node public_ip is required")
		return
	}
	port := intValue(req["port"])
	if port <= 0 {
		port = 11010
	}
	protocols := stringListValue(req["protocols"])
	if len(protocols) == 0 {
		protocols = []string{"tcp", "udp"}
	}
	listeners := networkURLs(protocols, "0.0.0.0", port)
	backendPeers := networkURLs(protocols, entryNode.PublicIP, port)
	name := stringValue(req["name"], stringValue(req["network_name"], "edge-net"))
	profile, err := s.store.createNetworkProfile(map[string]any{
		"name":                name,
		"network_name":        stringValue(req["network_name"], name),
		"network_secret":      stringValue(req["network_secret"], ""),
		"cidr":                stringValue(req["cidr"], "10.144.0.0/16"),
		"protocol_preference": "auto",
		"listeners":           listeners,
		"peers":               backendPeers,
		"mtu":                 intValueWithFallback(req["mtu"], 1380),
		"mss_clamp_enabled":   boolValueDefault(req["mss_clamp_enabled"], true),
		"mss_mode":            stringValue(req["mss_mode"], "auto"),
		"mss_value":           intValue(req["mss_value"]),
	})
	if err != nil {
		writeErr(w, 400, "BAD_REQUEST", err.Error())
		return
	}
	entryProfile := profile
	entryProfile.Peers = []string{}
	backendProfile := profile
	backendProfile.Peers = backendPeers
	entryTask, err := s.store.createTask(Task{NodeID: entryNode.ID, Action: "apply_network_profile", Payload: map[string]any{"target_mode": "entry", "network_profile": entryProfile, "node": entryNode}})
	if err != nil {
		writeErr(w, 500, "STORE_ERROR", err.Error())
		return
	}
	backendTask, err := s.store.createTask(Task{NodeID: backendNode.ID, Action: "apply_network_profile", Payload: map[string]any{"target_mode": "backend", "network_profile": backendProfile, "node": backendNode}})
	if err != nil {
		writeErr(w, 500, "STORE_ERROR", err.Error())
		return
	}
	link, err := s.store.createNetworkLink(NetworkLink{Name: name, NetworkName: profile.NetworkName, CIDR: profile.CIDR, Port: port, Protocols: protocols, MTU: profile.MTU, MSSClampEnabled: profile.MSSClampEnabled, MSSMode: profile.MSSMode, MSSValue: profile.MSSValue, EntryNodeID: entryNode.ID, BackendNodeID: backendNode.ID, EntryTaskID: entryTask.ID, BackendTaskID: backendTask.ID, Status: "applying", StatusReason: "network profile apply tasks created"})
	if err != nil {
		writeErr(w, 500, "STORE_ERROR", err.Error())
		return
	}
	writeOK(w, 202, map[string]any{"profile": profile, "link": link, "entry_task": entryTask, "backend_task": backendTask, "entry_peers": []string{}, "backend_peers": backendPeers, "message": "network apply tasks created; wait 10-20 seconds, then verify connectivity"})
}

func networkURLs(protocols []string, host string, port int) []string {
	out := make([]string, 0, len(protocols))
	for _, protocol := range protocols {
		switch strings.ToLower(strings.TrimSpace(protocol)) {
		case "tcp", "udp":
			out = append(out, protocol+"://"+host+":"+strconv.Itoa(port))
		}
	}
	if len(out) == 0 {
		return []string{"tcp://" + host + ":" + strconv.Itoa(port), "udp://" + host + ":" + strconv.Itoa(port)}
	}
	return out
}

func (s *Server) createNetworkLink(w http.ResponseWriter, req map[string]any) {
	linkType := strings.ToLower(strings.TrimSpace(stringValue(req["link_type"], "direct")))
	if linkType == "" {
		linkType = "direct"
	}
	if linkType != "direct" && linkType != "easytier" {
		writeErr(w, 400, "BAD_REQUEST", "link_type must be direct or easytier")
		return
	}
	if linkType == "easytier" {
		s.quickApplyNetwork(w, req)
		return
	}
	entryNodeID := stringValue(req["entry_node_id"], "")
	backendNodeID := stringValue(req["backend_node_id"], stringValue(req["landing_node_id"], ""))
	if entryNodeID == "" || backendNodeID == "" {
		writeErr(w, 400, "BAD_REQUEST", "entry_node_id and landing_node_id are required")
		return
	}
	if entryNodeID == backendNodeID {
		writeErr(w, 400, "BAD_REQUEST", "entry and landing nodes must be different")
		return
	}
	entryNode, found := s.store.getNode(entryNodeID)
	if !found {
		writeErr(w, 404, "NOT_FOUND", "entry node not found")
		return
	}
	backendNode, found := s.store.getNode(backendNodeID)
	if !found {
		writeErr(w, 404, "NOT_FOUND", "landing node not found")
		return
	}
	host := normalizeHostIP(stringValue(req["landing_reachable_host"], stringValue(req["reachable_host"], "")))
	if host == "" || strings.Contains(host, "/") || strings.Contains(host, ":") {
		writeErr(w, 400, "BAD_REQUEST", "landing_reachable_host must be an IPv4 host reachable from entry node")
		return
	}
	if ip := net.ParseIP(host); ip == nil || ip.To4() == nil {
		writeErr(w, 400, "BAD_REQUEST", "landing_reachable_host must be IPv4 for direct links")
		return
	}
	port := intValue(req["transit_port"])
	if port == 0 {
		port = intValue(req["port"])
	}
	if !validPort(port) {
		writeErr(w, 400, "BAD_REQUEST", "transit_port must be 1-65535")
		return
	}
	protocols := stringListValue(req["protocols"])
	if len(protocols) == 0 {
		protocols = []string{"tcp", "udp"}
	}
	name := stringValue(req["name"], "direct-link")
	link, err := s.store.createNetworkLink(NetworkLink{
		Name:                 name,
		LinkType:             "direct",
		NetworkName:          name,
		Port:                 port,
		TransitPort:          port,
		Protocols:            protocols,
		LandingReachableHost: host,
		EntryNodeID:          entryNode.ID,
		BackendNodeID:        backendNode.ID,
		Status:               "active",
		StatusReason:         "direct link configured",
	})
	if err != nil {
		writeErr(w, 500, "STORE_ERROR", err.Error())
		return
	}
	writeOK(w, 200, map[string]any{"link": link, "message": "direct link created; no EasyTier tasks were created"})
}

func (s *Server) handleNetworkLinks(w http.ResponseWriter, r *http.Request) {
	if !s.requireOperator(w, r) {
		return
	}
	if r.URL.Path == "/api/v1/network-links" {
		if r.Method == http.MethodGet {
			writeOK(w, 200, s.store.listNetworkLinks())
			return
		}
		if r.Method == http.MethodPost {
			req, ok := decodeBody(w, r)
			if !ok {
				return
			}
			if payloadHasDangerousKeys(req) {
				writeErr(w, 400, "DANGEROUS_PAYLOAD", "dangerous payload keys are not allowed")
				return
			}
			s.createNetworkLink(w, req)
			return
		}
		writeErr(w, 405, "METHOD_NOT_ALLOWED", "method not allowed")
		return
	}
	if r.URL.Path == "/api/v1/network-links/quick-apply" && r.Method == http.MethodPost {
		req, ok := decodeBody(w, r)
		if !ok {
			return
		}
		s.quickApplyNetwork(w, req)
		return
	}
	id, action := splitCollectionPath(r.URL.Path, "/api/v1/network-links/")
	if id == "" {
		writeErr(w, 404, "NOT_FOUND", "network link not found")
		return
	}
	switch {
	case r.Method == http.MethodGet && action == "":
		link, found := s.store.getNetworkLink(id)
		if !found {
			writeErr(w, 404, "NOT_FOUND", "network link not found")
			return
		}
		writeOK(w, 200, link)
	case r.Method == http.MethodDelete && action == "":
		found, err := s.store.deleteNetworkLink(id)
		if err != nil {
			writeErr(w, 500, "STORE_ERROR", err.Error())
			return
		}
		if !found {
			writeErr(w, 404, "NOT_FOUND", "network link not found")
			return
		}
		writeOK(w, 200, map[string]any{"deleted": true})
	case r.Method == http.MethodPost && action == "verify":
		s.handleNetworkLinkVerify(w, r, id)
	case r.Method == http.MethodPost && action == "reapply":
		s.handleNetworkLinkReapply(w, r, id)
	case r.Method == http.MethodPost && action == "enable":
		s.handleNetworkLinkReapply(w, r, id)
	case r.Method == http.MethodPost && action == "disable":
		link, found := s.store.getNetworkLink(id)
		if !found {
			writeErr(w, 404, "NOT_FOUND", "network link not found")
			return
		}
		if link.LinkType == "easytier" {
			entryTask, err := s.store.createTask(Task{NodeID: link.EntryNodeID, Action: "disable_network_link", Payload: map[string]any{"network_link_id": link.ID, "target_mode": "entry"}})
			if err != nil {
				writeErr(w, 500, "STORE_ERROR", err.Error())
				return
			}
			backendTask, err := s.store.createTask(Task{NodeID: link.BackendNodeID, Action: "disable_network_link", Payload: map[string]any{"network_link_id": link.ID, "target_mode": "backend"}})
			if err != nil {
				writeErr(w, 500, "STORE_ERROR", err.Error())
				return
			}
			updated, _, err := s.store.updateNetworkLinkStatus(id, "disabled", "disable tasks created")
			if err != nil {
				writeErr(w, 500, "STORE_ERROR", err.Error())
				return
			}
			writeOK(w, 202, map[string]any{"link": updated, "entry_task": entryTask, "backend_task": backendTask})
			return
		}
		updated, _, err := s.store.updateNetworkLinkStatus(id, "disabled", "direct link disabled")
		if err != nil {
			writeErr(w, 500, "STORE_ERROR", err.Error())
			return
		}
		writeOK(w, 200, updated)
	default:
		writeErr(w, 405, "METHOD_NOT_ALLOWED", "method not allowed")
	}
}

func (s *Server) handleNetworkLinkVerify(w http.ResponseWriter, r *http.Request, id string) {
	link, found := s.store.getNetworkLink(id)
	if !found {
		writeErr(w, 404, "NOT_FOUND", "network link not found")
		return
	}
	if link.LinkType == "direct" {
		port := link.TransitPort
		if port == 0 {
			port = link.Port
		}
		task, err := s.store.createTask(Task{NodeID: link.EntryNodeID, Action: "verify_direct_link", Payload: map[string]any{"network_link_id": link.ID, "target_mode": "entry", "target_host": link.LandingReachableHost, "target_port": port}})
		if err != nil {
			writeErr(w, 500, "STORE_ERROR", err.Error())
			return
		}
		updated, _, err := s.store.updateNetworkLinkTasks(id, task.ID, "", true)
		if err != nil {
			writeErr(w, 500, "STORE_ERROR", err.Error())
			return
		}
		writeOK(w, 202, map[string]any{"link": updated, "task": task})
		return
	}
	entryTask, err := s.store.createTask(Task{NodeID: link.EntryNodeID, Action: "verify_network_connectivity", Payload: map[string]any{"network_link_id": link.ID, "target_mode": "entry"}})
	if err != nil {
		writeErr(w, 500, "STORE_ERROR", err.Error())
		return
	}
	backendTask, err := s.store.createTask(Task{NodeID: link.BackendNodeID, Action: "verify_network_connectivity", Payload: map[string]any{"network_link_id": link.ID, "target_mode": "backend"}})
	if err != nil {
		writeErr(w, 500, "STORE_ERROR", err.Error())
		return
	}
	updated, _, err := s.store.updateNetworkLinkTasks(id, entryTask.ID, backendTask.ID, true)
	if err != nil {
		writeErr(w, 500, "STORE_ERROR", err.Error())
		return
	}
	writeOK(w, 202, map[string]any{"link": updated, "entry_task": entryTask, "backend_task": backendTask})
}

func (s *Server) handleNetworkLinkReapply(w http.ResponseWriter, r *http.Request, id string) {
	link, found := s.store.getNetworkLink(id)
	if !found {
		writeErr(w, 404, "NOT_FOUND", "network link not found")
		return
	}
	if link.LinkType == "direct" {
		updated, _, err := s.store.updateNetworkLinkStatus(id, "active", "direct link enabled")
		if err != nil {
			writeErr(w, 500, "STORE_ERROR", err.Error())
			return
		}
		writeOK(w, 200, map[string]any{"link": updated, "message": "direct link enabled"})
		return
	}
	entryNode, found := s.store.getNode(link.EntryNodeID)
	if !found {
		writeErr(w, 404, "NOT_FOUND", "entry node not found")
		return
	}
	backendNode, found := s.store.getNode(link.BackendNodeID)
	if !found {
		writeErr(w, 404, "NOT_FOUND", "backend node not found")
		return
	}
	protocols := link.Protocols
	if len(protocols) == 0 {
		protocols = []string{"tcp", "udp"}
	}
	port := link.Port
	if port == 0 {
		port = 11010
	}
	listeners := networkURLs(protocols, "0.0.0.0", port)
	backendPeers := networkURLs(protocols, entryNode.PublicIP, port)
	profile := NetworkProfile{Name: link.Name, NetworkName: link.NetworkName, NetworkSecret: randomSecret(), CIDR: link.CIDR, ProtocolPreference: "auto", Listeners: listeners, Peers: backendPeers, MTU: link.MTU, MSSClampEnabled: link.MSSClampEnabled, MSSMode: link.MSSMode, MSSValue: link.MSSValue}
	entryProfile := profile
	entryProfile.Peers = []string{}
	entryTask, err := s.store.createTask(Task{NodeID: link.EntryNodeID, Action: "apply_network_profile", Payload: map[string]any{"network_link_id": link.ID, "target_mode": "entry", "network_profile": entryProfile, "node": entryNode}})
	if err != nil {
		writeErr(w, 500, "STORE_ERROR", err.Error())
		return
	}
	backendTask, err := s.store.createTask(Task{NodeID: link.BackendNodeID, Action: "apply_network_profile", Payload: map[string]any{"network_link_id": link.ID, "target_mode": "backend", "network_profile": profile, "node": backendNode}})
	if err != nil {
		writeErr(w, 500, "STORE_ERROR", err.Error())
		return
	}
	updated, _, err := s.store.updateNetworkLinkTasks(id, entryTask.ID, backendTask.ID, false)
	if err != nil {
		writeErr(w, 500, "STORE_ERROR", err.Error())
		return
	}
	writeOK(w, 202, map[string]any{"link": updated, "entry_task": entryTask, "backend_task": backendTask})
}

func (s *Server) handleEntries(w http.ResponseWriter, r *http.Request) {
	s.handleGenericCollection(w, r, "entries")
}
func (s *Server) handleForwards(w http.ResponseWriter, r *http.Request) {
	if !s.requireOperator(w, r) {
		return
	}
	if r.URL.Path == "/api/v1/forwards/create-and-apply" && r.Method == http.MethodPost {
		s.handleForwardCreateAndApply(w, r)
		return
	}
	if r.URL.Path == "/api/v1/forwards" {
		switch r.Method {
		case http.MethodGet:
			writeOK(w, 200, s.store.listForwards())
			return
		case http.MethodPost:
			req, ok := decodeBody(w, r)
			if !ok {
				return
			}
			if payloadHasDangerousKeys(req) {
				writeErr(w, 400, "DANGEROUS_PAYLOAD", "dangerous payload keys are not allowed")
				return
			}
			if !s.prepareForwardRequest(w, req) {
				return
			}
			item, err := s.store.createForward(req)
			if err != nil {
				writeErr(w, 400, "BAD_REQUEST", err.Error())
				return
			}
			writeOK(w, 200, item)
			return
		default:
			writeErr(w, 405, "METHOD_NOT_ALLOWED", "method not allowed")
			return
		}
	}
	id, action := splitCollectionPath(r.URL.Path, "/api/v1/forwards/")
	if id == "" {
		writeErr(w, 404, "NOT_FOUND", "forward not found")
		return
	}
	switch {
	case r.Method == http.MethodPut && action == "":
		req, ok := decodeBody(w, r)
		if !ok {
			return
		}
		if payloadHasDangerousKeys(req) {
			writeErr(w, 400, "DANGEROUS_PAYLOAD", "dangerous payload keys are not allowed")
			return
		}
		if !s.prepareForwardRequest(w, req) {
			return
		}
		item, found, err := s.store.updateForward(id, req)
		if err != nil {
			writeErr(w, 400, "BAD_REQUEST", err.Error())
			return
		}
		if !found {
			writeErr(w, 404, "NOT_FOUND", "forward not found")
			return
		}
		writeOK(w, 200, item)
	case r.Method == http.MethodDelete && action == "":
		found, err := s.store.deleteForward(id)
		if err != nil {
			writeErr(w, 500, "STORE_ERROR", err.Error())
			return
		}
		if !found {
			writeErr(w, 404, "NOT_FOUND", "forward not found")
			return
		}
		writeOK(w, 200, map[string]any{"deleted": true})
	case r.Method == http.MethodPost && action == "apply":
		s.handleForwardApply(w, r, id)
	case r.Method == http.MethodPost && action == "verify":
		s.handleForwardVerify(w, r, id)
	case r.Method == http.MethodPost && action == "enable":
		s.handleForwardApply(w, r, id)
	case r.Method == http.MethodPost && action == "disable":
		s.handleForwardDisable(w, r, id)
	case r.Method == http.MethodGet && action == "":
		item, found := s.store.getForward(id)
		if !found {
			writeErr(w, 404, "NOT_FOUND", "forward not found")
			return
		}
		writeOK(w, 200, item)
	default:
		writeErr(w, 405, "METHOD_NOT_ALLOWED", "method not allowed")
	}
}

func (s *Server) handleForwardDisable(w http.ResponseWriter, r *http.Request, id string) {
	req := map[string]any{}
	if r.Body != nil {
		_ = json.NewDecoder(r.Body).Decode(&req)
	}
	if payloadHasDangerousKeys(req) {
		writeErr(w, 400, "DANGEROUS_PAYLOAD", "dangerous payload keys are not allowed")
		return
	}
	forward, found := s.store.getForward(id)
	if !found {
		writeErr(w, 404, "NOT_FOUND", "forward not found")
		return
	}
	entryTask, err := s.store.createTask(Task{NodeID: forward.EntryNodeID, Action: "disable_entry_forward_config", Payload: map[string]any{"stage": "entry", "forward_id": forward.ID, "rule_id": forward.ID, "forward_rule": forward}})
	if err != nil {
		writeErr(w, 500, "STORE_ERROR", err.Error())
		return
	}
	landingTask, err := s.store.createTask(Task{NodeID: forward.LandingNodeID, Action: "disable_landing_forward_config", Payload: map[string]any{"stage": "landing", "forward_id": forward.ID, "rule_id": forward.ID, "forward_rule": forward}})
	if err != nil {
		writeErr(w, 500, "STORE_ERROR", err.Error())
		return
	}
	if _, _, err := s.store.updateForwardTask(forward.ID, entryTask.ID, "entry_apply", "applying"); err != nil {
		writeErr(w, 500, "STORE_ERROR", err.Error())
		return
	}
	updated, _, err := s.store.updateForwardTask(forward.ID, landingTask.ID, "landing_apply", "applying")
	if err != nil {
		writeErr(w, 500, "STORE_ERROR", err.Error())
		return
	}
	writeOK(w, 202, map[string]any{"forward": updated, "entry_task": entryTask, "landing_task": landingTask})
}

func (s *Server) handleForwardCreateAndApply(w http.ResponseWriter, r *http.Request) {
	req, ok := decodeBody(w, r)
	if !ok {
		return
	}
	if payloadHasDangerousKeys(req) {
		writeErr(w, 400, "DANGEROUS_PAYLOAD", "dangerous payload keys are not allowed")
		return
	}
	if !s.prepareForwardRequest(w, req) {
		return
	}
	forward, err := s.store.createForward(req)
	if err != nil {
		writeErr(w, 400, "BAD_REQUEST", err.Error())
		return
	}
	s.createForwardApplyTask(w, forward)
}

func (s *Server) prepareForwardRequest(w http.ResponseWriter, req map[string]any) bool {
	linkID := stringValue(req["network_link_id"], "")
	if linkID == "" {
		writeErr(w, 400, "BAD_REQUEST", "network_link_id is required")
		return false
	}
	link, found := s.store.getNetworkLink(linkID)
	if !found {
		writeErr(w, 404, "NOT_FOUND", "network link not found")
		return false
	}
	if link.Status != "connected" && link.Status != "active" {
		writeErr(w, 400, "BAD_REQUEST", "network link is not connected; verify network connectivity before creating forwarding")
		return false
	}
	entryNode, found := s.store.getNode(link.EntryNodeID)
	if !found {
		writeErr(w, 404, "NOT_FOUND", "entry node not found")
		return false
	}
	landingNode, found := s.store.getNode(link.BackendNodeID)
	if !found {
		writeErr(w, 404, "NOT_FOUND", "landing node not found")
		return false
	}
	publicPort := intValue(req["public_listen_port"])
	if publicPort == 0 {
		publicPort = intValue(req["listen_port"])
	}
	landingPort := intValue(req["landing_port"])
	if landingPort == 0 {
		landingPort = intValue(req["target_port"])
	}
	landingHost := strings.TrimSpace(stringValue(req["landing_host"], stringValue(req["landing_host_raw"], stringValue(req["target_host"], ""))))
	if err := validateLandingHost(landingHost); err != nil {
		writeErr(w, 400, "BAD_REQUEST", err.Error())
		return false
	}
	mode := normalizeTransportMode(stringValue(req["transport_mode"], "easytier"))
	if link.LinkType == "direct" {
		mode = "direct"
	}
	tunnelTarget, err := resolveForwardTunnelTarget(link, landingNode, mode)
	if err != nil {
		writeErr(w, 400, "BAD_REQUEST", err.Error())
		return false
	}
	if stringValue(req["name"], "") == "" {
		req["name"] = "forward-" + strconv.Itoa(publicPort)
	}
	req["entry_node_id"] = entryNode.ID
	req["landing_node_id"] = landingNode.ID
	req["backend_node_id"] = landingNode.ID
	req["public_listen_host"] = stringValue(req["public_listen_host"], stringValue(req["listen_host"], "0.0.0.0"))
	req["public_listen_port"] = publicPort
	req["listen_port"] = publicPort
	req["transport_mode"] = mode
	req["tunnel_target_host"] = tunnelTarget
	req["tunnel_target_port"] = intValueWithDefault(req["tunnel_target_port"], publicPort)
	req["landing_host_raw"] = landingHost
	req["landing_host"] = landingHost
	req["landing_port"] = landingPort
	req["target_port"] = landingPort
	req["target_ip"] = tunnelTarget
	req["target_host"] = tunnelTarget
	return true
}

func resolveForwardTunnelTarget(link NetworkLink, landingNode Node, mode string) (string, error) {
	var target string
	if link.LinkType == "direct" || normalizeTransportMode(mode) == "direct" {
		target = normalizeHostIP(link.LandingReachableHost)
		if target == "" {
			return "", errValidation("直连链路缺少 B 可达地址")
		}
	} else {
		switch normalizeTransportMode(mode) {
		case "easytier":
			target = normalizeHostIP(landingNode.EasyTierIP)
			if target == "" {
				return "", errValidation("B \u8282\u70b9\u6682\u65e0 EasyTier \u865a\u62df IP\uff0c\u8bf7\u5148\u5b8c\u6210\u7ec4\u7f51\u9a8c\u8bc1")
			}
		case "public":
			target = normalizeHostIP(firstString(landingNode.PublicIP, landingNode.ObservedIP))
			if target == "" {
				return "", errValidation("B \u8282\u70b9\u6682\u65e0\u516c\u7f51 IP\uff0c\u4e0d\u80fd\u4f7f\u7528\u516c\u7f51\u76f4\u8fde\u6a21\u5f0f")
			}
		default:
			return "", errValidation("transport_mode must be easytier, direct, or public")
		}
	}
	ip := net.ParseIP(target)
	if ip == nil || ip.To4() == nil {
		return "", errValidation("A \u5230 B \u7684\u8f6c\u53d1\u76ee\u6807\u5fc5\u987b\u662f IPv4 \u5730\u5740")
	}
	return target, nil
}

func validateLandingHost(host string) error {
	host = strings.TrimSpace(host)
	if host == "" {
		return errValidation("landing_host is required")
	}
	if strings.Contains(host, "/") {
		return errValidation("landing_host must not be CIDR")
	}
	if strings.Contains(host, "://") || strings.ContainsAny(host, " \t\r\n") {
		return errValidation("landing_host must be an IP address or domain")
	}
	if strings.Contains(host, ":") {
		return errValidation("当前版本不支持 IPv6 落地目标")
	}
	if ip := net.ParseIP(host); ip != nil && ip.To4() == nil {
		return errValidation("当前版本不支持 IPv6 落地目标")
	}
	return nil
}

func intValueWithDefault(v any, fallback int) int {
	if value := intValue(v); value != 0 {
		return value
	}
	return fallback
}

func (s *Server) createForwardApplyTask(w http.ResponseWriter, forward Forward) {
	entryNode, found := s.store.getNode(forward.EntryNodeID)
	if !found {
		writeErr(w, 404, "NOT_FOUND", "entry node not found")
		return
	}
	landingNode, found := s.store.getNode(forward.LandingNodeID)
	if !found {
		writeErr(w, 404, "NOT_FOUND", "landing node not found")
		return
	}
	link, found := s.store.getNetworkLink(forward.NetworkLinkID)
	if !found {
		writeErr(w, 404, "NOT_FOUND", "network link not found")
		return
	}
	tunnelTarget, err := resolveForwardTunnelTarget(link, landingNode, forward.TransportMode)
	if err != nil {
		writeErr(w, 400, "BAD_REQUEST", err.Error())
		return
	}
	forward.TunnelTargetHost = tunnelTarget
	forward.TargetIP = tunnelTarget
	forward.TargetHost = tunnelTarget
	if forward.TunnelTargetPort == 0 {
		forward.TunnelTargetPort = forward.PublicListenPort
	}
	if updatedForward, ok, err := s.store.updateForwardResolvedTarget(forward.ID, tunnelTarget); err != nil {
		writeErr(w, 500, "STORE_ERROR", err.Error())
		return
	} else if ok {
		forward = updatedForward
	}
	entryTask, err := s.store.createTask(Task{NodeID: entryNode.ID, Action: "apply_entry_forward_config", Payload: map[string]any{"stage": "entry", "forward_id": forward.ID, "rule_id": forward.ID, "forward_rule": forward, "entry_node": entryNode, "landing_node": landingNode, "protocol": forward.Protocol, "public_listen_port": forward.PublicListenPort, "tunnel_target_host": forward.TunnelTargetHost, "tunnel_target_port": forward.TunnelTargetPort}})
	if err != nil {
		writeErr(w, 500, "STORE_ERROR", err.Error())
		return
	}
	landingTask, err := s.store.createTask(Task{NodeID: landingNode.ID, Action: "apply_landing_forward_config", Payload: map[string]any{"stage": "landing", "forward_id": forward.ID, "rule_id": forward.ID, "forward_rule": forward, "entry_node": entryNode, "landing_node": landingNode, "protocol": forward.Protocol, "tunnel_listen_port": forward.TunnelTargetPort, "landing_host_raw": forward.LandingHostRaw, "landing_port": forward.LandingPort}})
	if err != nil {
		writeErr(w, 500, "STORE_ERROR", err.Error())
		return
	}
	if _, _, err := s.store.updateForwardTask(forward.ID, entryTask.ID, "entry_apply", "applying"); err != nil {
		writeErr(w, 500, "STORE_ERROR", err.Error())
		return
	}
	updated, _, err := s.store.updateForwardTask(forward.ID, landingTask.ID, "landing_apply", "applying")
	if err != nil {
		writeErr(w, 500, "STORE_ERROR", err.Error())
		return
	}
	writeOK(w, 202, map[string]any{"forward": updated, "entry_task": entryTask, "landing_task": landingTask})
}

func (s *Server) handleForwardApply(w http.ResponseWriter, r *http.Request, id string) {
	req := map[string]any{}
	if r.Body != nil {
		_ = json.NewDecoder(r.Body).Decode(&req)
	}
	if payloadHasDangerousKeys(req) {
		writeErr(w, 400, "DANGEROUS_PAYLOAD", "dangerous payload keys are not allowed")
		return
	}
	forward, found := s.store.getForward(id)
	if !found {
		writeErr(w, 404, "NOT_FOUND", "forward not found")
		return
	}
	s.createForwardApplyTask(w, forward)
}

func (s *Server) handleForwardVerify(w http.ResponseWriter, r *http.Request, id string) {
	req := map[string]any{}
	if r.Body != nil {
		_ = json.NewDecoder(r.Body).Decode(&req)
	}
	if payloadHasDangerousKeys(req) {
		writeErr(w, 400, "DANGEROUS_PAYLOAD", "dangerous payload keys are not allowed")
		return
	}
	forward, found := s.store.getForward(id)
	if !found {
		writeErr(w, 404, "NOT_FOUND", "forward not found")
		return
	}
	entryTask, err := s.store.createTask(Task{NodeID: forward.EntryNodeID, Action: "verify_forward_rules", Payload: map[string]any{"stage": "entry", "forward_id": forward.ID, "name": forward.Name, "listen_port": forward.PublicListenPort, "target_port": forward.TunnelTargetPort}})
	if err != nil {
		writeErr(w, 500, "STORE_ERROR", err.Error())
		return
	}
	landingTask, err := s.store.createTask(Task{NodeID: forward.LandingNodeID, Action: "verify_forward_rules", Payload: map[string]any{"stage": "landing", "forward_id": forward.ID, "name": forward.Name, "listen_port": forward.TunnelTargetPort, "target_port": forward.LandingPort}})
	if err != nil {
		writeErr(w, 500, "STORE_ERROR", err.Error())
		return
	}
	updated, _, err := s.store.updateForwardTask(id, landingTask.ID, "verify", forward.Status)
	if err != nil {
		writeErr(w, 500, "STORE_ERROR", err.Error())
		return
	}
	writeOK(w, 202, map[string]any{"forward": updated, "entry_task": entryTask, "landing_task": landingTask})
}

func (s *Server) handlePBRPolicies(w http.ResponseWriter, r *http.Request) {
	if !s.requireOperator(w, r) {
		return
	}
	if r.URL.Path == "/api/v1/pbr-policies/create-and-apply" && r.Method == http.MethodPost {
		req, ok := decodeBody(w, r)
		if !ok {
			return
		}
		if payloadHasDangerousKeys(req) {
			writeErr(w, 400, "DANGEROUS_PAYLOAD", "dangerous payload keys are not allowed")
			return
		}
		policy, err := s.store.createPBRPolicy(req)
		if err != nil {
			writeErr(w, 400, "BAD_REQUEST", err.Error())
			return
		}
		if s.store.hasActivePBRPolicy(policy.NodeID, policy.ID) {
			_, _ = s.store.deletePBRPolicy(policy.ID)
			writeErr(w, 400, "BAD_REQUEST", "node already has an active PBR policy")
			return
		}
		task, err := s.store.createTask(Task{NodeID: policy.NodeID, Action: "apply_pbr_policy", Payload: map[string]any{"pbr_policy": policy}})
		if err != nil {
			writeErr(w, 500, "STORE_ERROR", err.Error())
			return
		}
		updated, _, err := s.store.updatePBRTask(policy.ID, task.ID, "apply", "applying")
		if err != nil {
			writeErr(w, 500, "STORE_ERROR", err.Error())
			return
		}
		writeOK(w, 202, map[string]any{"policy": updated, "task": task})
		return
	}
	if r.URL.Path == "/api/v1/pbr-policies" {
		switch r.Method {
		case http.MethodGet:
			writeOK(w, 200, s.store.listPBRPolicies())
		case http.MethodPost:
			req, ok := decodeBody(w, r)
			if !ok {
				return
			}
			if payloadHasDangerousKeys(req) {
				writeErr(w, 400, "DANGEROUS_PAYLOAD", "dangerous payload keys are not allowed")
				return
			}
			policy, err := s.store.createPBRPolicy(req)
			if err != nil {
				writeErr(w, 400, "BAD_REQUEST", err.Error())
				return
			}
			writeOK(w, 200, policy)
		default:
			writeErr(w, 405, "METHOD_NOT_ALLOWED", "method not allowed")
		}
		return
	}
	id, action := splitCollectionPath(r.URL.Path, "/api/v1/pbr-policies/")
	if id == "" {
		writeErr(w, 404, "NOT_FOUND", "pbr policy not found")
		return
	}
	switch {
	case r.Method == http.MethodGet && action == "":
		policy, found := s.store.getPBRPolicy(id)
		if !found {
			writeErr(w, 404, "NOT_FOUND", "pbr policy not found")
			return
		}
		writeOK(w, 200, policy)
	case r.Method == http.MethodPut && action == "":
		req, ok := decodeBody(w, r)
		if !ok {
			return
		}
		if payloadHasDangerousKeys(req) {
			writeErr(w, 400, "DANGEROUS_PAYLOAD", "dangerous payload keys are not allowed")
			return
		}
		policy, found, err := s.store.updatePBRPolicy(id, req)
		if err != nil {
			writeErr(w, 400, "BAD_REQUEST", err.Error())
			return
		}
		if !found {
			writeErr(w, 404, "NOT_FOUND", "pbr policy not found")
			return
		}
		writeOK(w, 200, policy)
	case r.Method == http.MethodDelete && action == "":
		found, err := s.store.deletePBRPolicy(id)
		if err != nil {
			writeErr(w, 500, "STORE_ERROR", err.Error())
			return
		}
		if !found {
			writeErr(w, 404, "NOT_FOUND", "pbr policy not found")
			return
		}
		writeOK(w, 200, map[string]any{"deleted": true})
	case r.Method == http.MethodPost && (action == "apply" || action == "verify" || action == "disable"):
		policy, found := s.store.getPBRPolicy(id)
		if !found {
			req, ok := decodeBody(w, r)
			if !ok {
				return
			}
			if action == "apply" && stringValue(req["node_id"], "") != "" {
				task, err := s.store.createTask(Task{NodeID: stringValue(req["node_id"], ""), Action: "apply_pbr_config", Payload: req})
				if err != nil {
					writeErr(w, 500, "STORE_ERROR", err.Error())
					return
				}
				writeOK(w, 202, task)
				return
			}
			writeErr(w, 404, "NOT_FOUND", "pbr policy not found")
			return
		}
		if action == "apply" && s.store.hasActivePBRPolicy(policy.NodeID, policy.ID) {
			writeErr(w, 400, "BAD_REQUEST", "node already has an active PBR policy")
			return
		}
		actionName := map[string]string{"apply": "apply_pbr_policy", "verify": "verify_pbr_policy", "disable": "disable_pbr_policy"}[action]
		task, err := s.store.createTask(Task{NodeID: policy.NodeID, Action: actionName, Payload: map[string]any{"pbr_policy": policy}})
		if err != nil {
			writeErr(w, 500, "STORE_ERROR", err.Error())
			return
		}
		status := ""
		field := ""
		if action == "apply" {
			status = "applying"
			field = "apply"
		}
		if action == "verify" {
			field = "verify"
		}
		if action == "disable" {
			status = "applying"
		}
		updated, _, err := s.store.updatePBRTask(id, task.ID, field, status)
		if err != nil {
			writeErr(w, 500, "STORE_ERROR", err.Error())
			return
		}
		writeOK(w, 202, map[string]any{"policy": updated, "task": task})
	default:
		writeErr(w, 405, "METHOD_NOT_ALLOWED", "method not allowed")
	}
}
func (s *Server) handleTasks(w http.ResponseWriter, r *http.Request) {
	s.handleGenericCollection(w, r, "tasks")
}
func (s *Server) handleDDNS(w http.ResponseWriter, r *http.Request) { writeOK(w, 200, []DDNSProfile{}) }

func (s *Server) handleDiagnosticsRun(w http.ResponseWriter, r *http.Request) {
	if !s.requireOperator(w, r) {
		return
	}
	if r.Method != http.MethodPost {
		writeErr(w, 405, "METHOD_NOT_ALLOWED", "method not allowed")
		return
	}
	req, ok := decodeBody(w, r)
	if !ok {
		return
	}
	if payloadHasDangerousKeys(req) {
		writeErr(w, 400, "DANGEROUS_PAYLOAD", "dangerous payload keys are not allowed")
		return
	}
	diagnosticID := "diag-" + newID()
	nodeIDs := stringListValue(req["node_ids"])
	if len(nodeIDs) == 0 {
		for _, node := range s.store.listNodes() {
			nodeIDs = append(nodeIDs, node.ID)
		}
	}
	actions := []string{"collect_agent_status", "detect_network_interfaces", "detect_pbr_route_groups", "verify_easytier_status", "verify_network_connectivity", "verify_forward_rules", "verify_pbr_policy", "detect_mtu_status"}
	tasks := []Task{}
	for _, nodeID := range nodeIDs {
		for _, action := range actions {
			payload := map[string]any{"diagnostic_id": diagnosticID, "node_id": nodeID}
			if action == "verify_forward_rules" {
				payload["stage"] = "entry"
			}
			task, err := s.store.createTask(Task{NodeID: nodeID, Action: action, Payload: payload})
			if err != nil {
				writeErr(w, 500, "STORE_ERROR", err.Error())
				return
			}
			tasks = append(tasks, task)
		}
	}
	writeOK(w, 202, map[string]any{"diagnostic_id": diagnosticID, "controller": s.diagnosticControllerSummary(), "tasks": tasks})
}

func (s *Server) handleDiagnostics(w http.ResponseWriter, r *http.Request) {
	if !s.requireOperator(w, r) {
		return
	}
	if r.Method != http.MethodGet {
		writeErr(w, 405, "METHOD_NOT_ALLOWED", "method not allowed")
		return
	}
	id := strings.Trim(strings.TrimPrefix(r.URL.Path, "/api/v1/diagnostics/"), "/")
	if id == "" {
		writeErr(w, 404, "NOT_FOUND", "diagnostic not found")
		return
	}
	tasks := []Task{}
	for _, task := range s.store.listTasks("", "") {
		if stringValue(task.Payload["diagnostic_id"], "") == id {
			tasks = append(tasks, task)
		}
	}
	report := s.diagnosticMarkdown(id, tasks)
	writeOK(w, 200, map[string]any{"diagnostic_id": id, "controller": s.diagnosticControllerSummary(), "tasks": tasks, "markdown": report})
}

func (s *Server) diagnosticControllerSummary() map[string]any {
	nodes := s.store.listNodes()
	tasks := s.store.listTasks("", "")
	return map[string]any{"version": Version, "node_count": len(nodes), "task_count": len(tasks), "strict_auth": s.strictAuth, "web_dir": s.webDir}
}

func (s *Server) diagnosticMarkdown(id string, tasks []Task) string {
	var b strings.Builder
	b.WriteString("# Edge Tunnel Panel 诊断报告\n\n")
	b.WriteString("诊断 ID：" + id + "\n\n")
	b.WriteString("Controller 版本：" + Version + "\n\n")
	for _, task := range tasks {
		b.WriteString("- 节点 `" + task.NodeID + "` / `" + task.Action + "` / `" + task.Status + "`")
		if task.Error != "" {
			b.WriteString(" / 错误：" + task.Error)
		}
		b.WriteString("\n")
	}
	return b.String()
}

func splitCollectionPath(requestPath, prefix string) (id string, action string) {
	if !strings.HasPrefix(requestPath, prefix) {
		return "", ""
	}
	rest := strings.Trim(strings.TrimPrefix(requestPath, prefix), "/")
	if rest == "" {
		return "", ""
	}
	parts := strings.Split(rest, "/")
	id = parts[0]
	if len(parts) > 1 {
		action = parts[1]
	}
	return id, action
}

func (s *Server) handleNetworkProfileApply(w http.ResponseWriter, r *http.Request, id string) {
	if id == "" {
		writeErr(w, 404, "NOT_FOUND", "network profile not found")
		return
	}
	req, ok := decodeBody(w, r)
	if !ok {
		return
	}
	if payloadHasDangerousKeys(req) {
		writeErr(w, 400, "DANGEROUS_PAYLOAD", "dangerous payload keys are not allowed")
		return
	}
	profile, found := s.store.getNetworkProfile(id)
	if !found {
		writeErr(w, 404, "NOT_FOUND", "network profile not found")
		return
	}
	nodeIDs := stringListValue(req["node_ids"])
	if nodeID := stringValue(req["node_id"], ""); nodeID != "" {
		nodeIDs = append(nodeIDs, nodeID)
	}
	if len(nodeIDs) == 0 {
		writeErr(w, 400, "BAD_REQUEST", "node_id or node_ids is required")
		return
	}
	tasks := make([]Task, 0, len(nodeIDs))
	for _, nodeID := range nodeIDs {
		node, found := s.store.getNode(nodeID)
		if !found {
			writeErr(w, 404, "NOT_FOUND", "node not found")
			return
		}
		profilePayload := profile
		if strings.EqualFold(node.Role, "backend") && len(profilePayload.Peers) == 0 {
			writeErr(w, 400, "BAD_REQUEST", "backend node requires at least one entry peer")
			return
		}
		task, err := s.store.createTask(Task{NodeID: nodeID, Action: "apply_network_profile", Payload: map[string]any{"network_profile": profilePayload, "node": node}})
		if err != nil {
			writeErr(w, 500, "STORE_ERROR", err.Error())
			return
		}
		tasks = append(tasks, task)
	}
	if len(tasks) == 1 {
		writeOK(w, 202, tasks[0])
		return
	}
	writeOK(w, 202, tasks)
}

func (s *Server) handleGenericCollection(w http.ResponseWriter, r *http.Request, kind string) {
	if !s.requireOperator(w, r) {
		return
	}
	if r.Method == http.MethodGet {
		if kind == "tasks" {
			writeOK(w, 200, s.store.listTasks(r.URL.Query().Get("node_id"), r.URL.Query().Get("status")))
			return
		}
		s.store.mu.Lock()
		defer s.store.mu.Unlock()
		switch kind {
		case "entries":
			writeOK(w, 200, s.store.data.Entries)
		case "forwards":
			writeOK(w, 200, s.store.data.Forwards)
		case "pbr-policies":
			writeOK(w, 200, s.store.data.PBRPolicies)
		}
		return
	}
	req, ok := decodeBody(w, r)
	if !ok {
		return
	}
	if payloadHasDangerousKeys(req) {
		writeErr(w, 400, "DANGEROUS_PAYLOAD", "dangerous payload keys are not allowed")
		return
	}
	if strings.HasSuffix(r.URL.Path, "/apply") {
		nodeID := stringValue(req["node_id"], stringValue(req["entry_node_id"], ""))
		action := map[string]string{"network-profiles": "apply_network_profile", "entries": "apply_entry_config", "forwards": "apply_forward_config", "pbr-policies": "apply_pbr_config"}[kind]
		task, err := s.store.createTask(Task{NodeID: nodeID, Action: action, Payload: req})
		if err != nil {
			writeErr(w, 500, "STORE_ERROR", err.Error())
			return
		}
		writeOK(w, 202, task)
		return
	}
	if kind == "tasks" {
		action := stringValue(req["action"], "collect_agent_status")
		blocked := map[string]bool{"arbitrary_command": true, "shell_c": true, "bash_c": true, "ev" + "al": true, "raw_" + "nft": true, "raw_" + "iptables": true, "raw_" + "ip_route": true, "curl_pipe_bash": true}
		allowed := map[string]bool{"collect_agent_status": true, "run_node_preflight": true, "detect_network_interfaces": true, "detect_pbr_route_groups": true, "detect_mtu_status": true, "verify_agent_config": true, "verify_easytier_status": true, "verify_network_connectivity": true, "verify_direct_link": true, "verify_forward_rules": true, "verify_pbr_rules": true, "verify_pbr_policy": true, "verify_ddns_status": true, "configure_node_role": true, "install_or_update_easytier": true, "apply_network_profile": true, "apply_entry_config": true, "apply_forward_config": true, "apply_entry_forward_config": true, "apply_landing_forward_config": true, "disable_entry_forward_config": true, "disable_landing_forward_config": true, "disable_network_link": true, "cleanup_node_deployment": true, "purge_agent_deployment": true, "apply_pbr_config": true, "apply_pbr_policy": true, "disable_pbr_policy": true, "apply_ddns_config": true, "reload_firewall_rules": true, "restart_easytier": true, "restart_agent": true, "reboot_node": true}
		if blocked[action] || !allowed[action] {
			writeErr(w, 400, "BLOCKED_ACTION", "action is not allowed")
			return
		}
		if action == "reboot_node" && !boolValue(req["confirm"]) {
			writeErr(w, 400, "CONFIRM_REQUIRED", "reboot_node requires confirm=true")
			return
		}
		task, err := s.store.createTask(Task{NodeID: stringValue(req["node_id"], ""), Action: action, Payload: req})
		if err != nil {
			writeErr(w, 500, "STORE_ERROR", err.Error())
			return
		}
		writeOK(w, 200, task)
		return
	}
	n := now()
	s.store.mu.Lock()
	defer s.store.mu.Unlock()
	switch kind {
	case "entries":
		item := Entry{ID: newID(), Name: stringValue(req["name"], "entry"), NodeID: stringValue(req["node_id"], ""), ListenIP: stringValue(req["listen_ip"], "0.0.0.0"), ListenPortStart: intValue(req["listen_port_start"]), ListenPortEnd: intValue(req["listen_port_end"]), Protocol: stringValue(req["protocol"], "both"), Domain: stringValue(req["domain"], ""), DDNSEnabled: boolValue(req["ddns_enabled"]), DDNSProvider: stringValue(req["ddns_provider"], ""), DDNSTokenRef: stringValue(req["ddns_token_ref"], ""), Status: "draft", CreatedAt: n, UpdatedAt: n}
		s.store.data.Entries = append(s.store.data.Entries, item)
		_ = s.store.saveLocked()
		writeOK(w, 200, item)
	case "forwards":
		item := Forward{ID: newID(), Name: stringValue(req["name"], "forward"), EntryID: stringValue(req["entry_id"], ""), EntryNodeID: stringValue(req["entry_node_id"], ""), Protocol: stringValue(req["protocol"], "tcp"), ListenPort: intValue(req["listen_port"]), TargetMode: stringValue(req["target_mode"], "local"), TargetNodeID: stringValue(req["target_node_id"], ""), TargetHost: stringValue(req["target_host"], ""), TargetPort: intValue(req["target_port"]), Enabled: true, Remark: stringValue(req["remark"], ""), CreatedAt: n, UpdatedAt: n}
		s.store.data.Forwards = append(s.store.data.Forwards, item)
		_ = s.store.saveLocked()
		writeOK(w, 200, item)
	case "pbr-policies":
		item := PBRPolicy{ID: newID(), NodeID: stringValue(req["node_id"], ""), Name: stringValue(req["name"], "pbr"), MatchSource: stringValue(req["match_source"], ""), MatchDst: stringValue(req["match_dst"], ""), MatchProtocol: stringValue(req["match_protocol"], ""), MatchMark: stringValue(req["match_mark"], ""), TableID: intValue(req["table_id"]), Gateway: stringValue(req["gateway"], ""), OutInterface: stringValue(req["out_interface"], ""), Priority: intValue(req["priority"]), Enabled: true, CreatedAt: n, UpdatedAt: n}
		s.store.data.PBRPolicies = append(s.store.data.PBRPolicies, item)
		_ = s.store.saveLocked()
		writeOK(w, 200, item)
	}
}

func networkLinkMTU(store *Store, id string) int {
	if link, found := store.getNetworkLink(id); found {
		if link.MTU != 0 {
			return link.MTU
		}
	}
	return 1380
}
func networkLinkMSSClamp(store *Store, id string) bool {
	if link, found := store.getNetworkLink(id); found {
		return link.MSSClampEnabled
	}
	return true
}
func networkLinkMSSMode(store *Store, id string) string {
	if link, found := store.getNetworkLink(id); found && link.MSSMode != "" {
		return link.MSSMode
	}
	return "auto"
}
func networkLinkMSSValue(store *Store, id string) int {
	if link, found := store.getNetworkLink(id); found {
		return link.MSSValue
	}
	return 0
}
