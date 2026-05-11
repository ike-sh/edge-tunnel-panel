package controller

import (
	"encoding/json"
	"io"
	"log"
	"net/http"
	"strconv"
	"strings"
)

type Server struct {
	store *Store
	token string
	log   *log.Logger
}

func NewServer(store *Store, token string, logger *log.Logger) http.Handler {
	if logger == nil {
		logger = log.Default()
	}
	s := &Server{store: store, token: token, log: logger}
	mux := http.NewServeMux()
	mux.HandleFunc("/api/v1/health", s.handleHealth)
	mux.HandleFunc("/api/v1/bootstrap/agent-command", s.handleBootstrapAgentCommand)
	mux.HandleFunc("/api/v1/topology", s.handleTopology)
	mux.HandleFunc("/api/v1/agent/register", s.handleRegister)
	mux.HandleFunc("/api/v1/agent/report", s.handleReport)
	mux.HandleFunc("/api/v1/nodes", s.handleNodes)
	mux.HandleFunc("/api/v1/nodes/", s.handleNodeByID)
	mux.HandleFunc("/api/v1/entries", s.handleEntries)
	mux.HandleFunc("/api/v1/forwards", s.handleForwards)
	mux.HandleFunc("/api/v1/events", s.handleEvents)
	return withCORS(mux)
}

func withCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]string{"error": RedactString(message)})
}

func (s *Server) requirePOST(w http.ResponseWriter, r *http.Request) bool {
	if r.Method != http.MethodPost {
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return false
	}
	return true
}

func (s *Server) requireGET(w http.ResponseWriter, r *http.Request) bool {
	if r.Method != http.MethodGet {
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return false
	}
	return true
}

func (s *Server) requireAgentAuth(w http.ResponseWriter, r *http.Request) bool {
	if s.token == "" {
		writeError(w, http.StatusUnauthorized, "controller token is not configured")
		return false
	}
	header := r.Header.Get("Authorization")
	const prefix = "Bearer "
	if !strings.HasPrefix(header, prefix) || strings.TrimSpace(strings.TrimPrefix(header, prefix)) != s.token {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return false
	}
	return true
}

func (s *Server) decodeBody(w http.ResponseWriter, r *http.Request, dst any) ([]byte, bool) {
	defer r.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(r.Body, 4<<20))
	if err != nil {
		writeError(w, http.StatusBadRequest, "read body failed")
		return nil, false
	}
	if err := json.Unmarshal(raw, dst); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json")
		return nil, false
	}
	return raw, true
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	if !s.requireGET(w, r) {
		return
	}
	writeJSON(w, http.StatusOK, HealthResponse{Name: "leikwan-controller", Version: Version, Status: "ok"})
}

func (s *Server) handleBootstrapAgentCommand(w http.ResponseWriter, r *http.Request) {
	if !s.requireGET(w, r) {
		return
	}
	controllerURL := strings.TrimSpace(r.URL.Query().Get("controller_url"))
	if controllerURL == "" {
		scheme := "http"
		if r.TLS != nil {
			scheme = "https"
		}
		controllerURL = scheme + "://" + r.Host
	}
	role := normalizeRole(strings.TrimSpace(r.URL.Query().Get("role")))
	nodeName := strings.TrimSpace(r.URL.Query().Get("node_name"))
	if nodeName == "" {
		nodeName = "leikwan-node"
	}
	command := "sudo bash panel/scripts/install-agent.sh --controller '" + shellQuote(controllerURL) + "' --token 'REDACTED' --name '" + shellQuote(nodeName) + "' --role '" + shellQuote(role) + "'"
	writeJSON(w, http.StatusOK, BootstrapAgentCommandResponse{
		Command:       command,
		ControllerURL: RedactString(controllerURL),
		Role:          role,
		NodeName:      RedactString(nodeName),
		Token:         "REDACTED",
		Note:          "Token is intentionally redacted. Replace REDACTED on the target host or write /etc/leikwan-agent/config.yml securely.",
	})
}

func shellQuote(s string) string {
	return strings.ReplaceAll(RedactString(s), "'", "'\\''")
}

func (s *Server) handleTopology(w http.ResponseWriter, r *http.Request) {
	if !s.requireGET(w, r) {
		return
	}
	nodes, err := s.store.ListNodes(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	entries, err := s.store.ListEntries(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	forwards, err := s.store.ListForwards(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, TopologyResponse{
		Nodes:    nodes,
		Entries:  entries,
		Forwards: forwards,
		Links:    inferTopologyLinks(nodes, entries, forwards),
	})
}

func inferTopologyLinks(nodes []Node, entries []Entry, forwards []Forward) []TopologyLink {
	links := []TopologyLink{}
	relays := []Node{}
	entriesByNode := map[string]Node{}
	for _, node := range nodes {
		switch node.Role {
		case "relay", "mixed":
			relays = append(relays, node)
		case "entry":
			entriesByNode[node.NodeID] = node
		}
	}
	for _, entryNode := range entriesByNode {
		for _, relay := range relays {
			links = append(links, TopologyLink{
				Source: entryNode.NodeID,
				Target: relay.NodeID,
				Type:   "entry-relay",
				Label:  "entry -> relay",
				Status: linkStatus(entryNode.Status, relay.Status),
			})
		}
	}
	for _, entry := range entries {
		for _, relay := range relays {
			if entry.NodeID == relay.NodeID {
				links = append(links, TopologyLink{
					Source: relay.NodeID,
					Target: "entry:" + entry.Name,
					Type:   "relay-entry",
					Label:  entry.Name,
					Status: entry.Status,
				})
			}
		}
	}
	for _, forward := range forwards {
		source := forward.NodeID
		if source == "" && len(relays) > 0 {
			source = relays[0].NodeID
		}
		if source == "" {
			continue
		}
		target := "target:" + forward.Name
		if forward.TargetHost != "" {
			target = "target:" + forward.TargetHost
		}
		links = append(links, TopologyLink{
			Source: source,
			Target: target,
			Type:   "relay-target",
			Label:  forward.Name,
			Status: forward.Status,
		})
	}
	return links
}

func linkStatus(a, b string) string {
	if a == "offline" || b == "offline" {
		return "offline"
	}
	if a == "degraded" || b == "degraded" {
		return "degraded"
	}
	return "online"
}

func (s *Server) handleRegister(w http.ResponseWriter, r *http.Request) {
	if !s.requirePOST(w, r) || !s.requireAgentAuth(w, r) {
		return
	}
	var req RegisterRequest
	raw, ok := s.decodeBody(w, r, &req)
	if !ok {
		return
	}
	if err := s.store.Register(r.Context(), req, raw); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok", "node_id": req.NodeID})
}

func (s *Server) handleReport(w http.ResponseWriter, r *http.Request) {
	if !s.requirePOST(w, r) || !s.requireAgentAuth(w, r) {
		return
	}
	var req ReportRequest
	raw, ok := s.decodeBody(w, r, &req)
	if !ok {
		return
	}
	if err := s.store.Report(r.Context(), req, raw); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok", "node_id": req.NodeID})
}

func (s *Server) handleNodes(w http.ResponseWriter, r *http.Request) {
	if !s.requireGET(w, r) {
		return
	}
	nodes, err := s.store.ListNodes(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, nodes)
}

func (s *Server) handleNodeByID(w http.ResponseWriter, r *http.Request) {
	if !s.requireGET(w, r) {
		return
	}
	rest := strings.TrimPrefix(r.URL.Path, "/api/v1/nodes/")
	parts := strings.Split(strings.Trim(rest, "/"), "/")
	id := parts[0]
	if id == "" {
		writeError(w, http.StatusNotFound, "node not found")
		return
	}
	if len(parts) > 1 {
		switch parts[1] {
		case "reports":
			s.handleNodeReports(w, r, id)
		case "events":
			s.handleNodeEvents(w, r, id)
		case "raw":
			s.handleNodeRaw(w, r, id)
		default:
			writeError(w, http.StatusNotFound, "not found")
		}
		return
	}
	node, found, err := s.store.GetNode(r.Context(), id)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	if !found {
		writeError(w, http.StatusNotFound, "node not found")
		return
	}
	writeJSON(w, http.StatusOK, node)
}

func queryLimit(r *http.Request, fallback int) int {
	limit := fallback
	if raw := r.URL.Query().Get("limit"); raw != "" {
		if n, err := strconv.Atoi(raw); err == nil {
			limit = n
		}
	}
	if limit <= 0 || limit > 200 {
		return fallback
	}
	return limit
}

func (s *Server) handleNodeReports(w http.ResponseWriter, r *http.Request, id string) {
	reports, err := s.store.ListNodeReports(r.Context(), id, queryLimit(r, 100))
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, reports)
}

func (s *Server) handleNodeEvents(w http.ResponseWriter, r *http.Request, id string) {
	events, err := s.store.ListNodeEvents(r.Context(), id, queryLimit(r, 100))
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, events)
}

func (s *Server) handleNodeRaw(w http.ResponseWriter, r *http.Request, id string) {
	node, found, err := s.store.GetNode(r.Context(), id)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	if !found {
		writeError(w, http.StatusNotFound, "node not found")
		return
	}
	var raw any
	if err := json.Unmarshal([]byte(node.RawJSON), &raw); err != nil {
		raw = node.RawJSON
	}
	writeJSON(w, http.StatusOK, map[string]any{"node_id": node.NodeID, "raw_json": raw})
}

func (s *Server) handleEntries(w http.ResponseWriter, r *http.Request) {
	if !s.requireGET(w, r) {
		return
	}
	entries, err := s.store.ListEntries(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, entries)
}

func (s *Server) handleForwards(w http.ResponseWriter, r *http.Request) {
	if !s.requireGET(w, r) {
		return
	}
	forwards, err := s.store.ListForwards(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, forwards)
}

func (s *Server) handleEvents(w http.ResponseWriter, r *http.Request) {
	if !s.requireGET(w, r) {
		return
	}
	events, err := s.store.ListEvents(r.Context(), 100)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, events)
}
