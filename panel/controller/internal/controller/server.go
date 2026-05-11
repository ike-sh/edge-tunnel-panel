package controller

import (
	"encoding/json"
	"io"
	"log"
	"net/http"
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
	id := strings.TrimPrefix(r.URL.Path, "/api/v1/nodes/")
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
