package controller

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"
)

func (s *Server) registerV2Routes(mux *http.ServeMux) {
	mux.HandleFunc("/api/v2/machines", s.handleV2Machines)
	mux.HandleFunc("/api/v2/machines/", s.handleV2Machines)
	mux.HandleFunc("/api/v2/profiles", s.handleV2Profiles)
	mux.HandleFunc("/api/v2/profiles/", s.handleV2Profiles)
	mux.HandleFunc("/api/v2/bootstrap/install", s.handleV2BootstrapInstall)
	mux.HandleFunc("/api/v2/diagnostics/run", s.handleV2DiagnosticsRun)
	mux.HandleFunc("/api/v2/tasks", s.handleTasks)
	mux.HandleFunc("/api/v2/tasks/", s.handleV2Tasks)
}

func (s *Server) handleV2Machines(w http.ResponseWriter, r *http.Request) {
	if !s.requireOperator(w, r) {
		return
	}
	rest := strings.TrimPrefix(r.URL.Path, "/api/v2/machines")
	rest = strings.Trim(rest, "/")
	if rest != "" {
		parts := strings.SplitN(rest, "/", 2)
		id := parts[0]
		sub := ""
		if len(parts) > 1 {
			sub = parts[1]
		}
		if sub == "rotate-token" && r.Method == http.MethodPost {
			m, err := s.store.rotateIXMachineToken(id)
			if err != nil {
				writeErr(w, 404, "not_found", err.Error())
				return
			}
			writeOK(w, 200, map[string]any{"machine_id": m.ID, "token": m.Token, "note": "请立即更新 Agent 配置并重启"})
			return
		}
		if sub == "" && r.Method == http.MethodGet {
			m, ok := s.store.getIXMachine(id)
			if !ok {
				writeErr(w, 404, "not_found", "machine not found")
				return
			}
			writeOK(w, 200, m)
			return
		}
		writeErr(w, 404, "not_found", "unknown sub-resource")
		return
	}
	switch r.Method {
	case http.MethodGet:
		writeOK(w, 200, s.store.listIXMachines())
	case http.MethodPost:
		var body struct {
			Name string `json:"name"`
			Role string `json:"role"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			writeErr(w, 400, "bad_request", "invalid json")
			return
		}
		m, err := s.store.createIXMachine(body.Name, body.Role)
		if err != nil {
			writeErr(w, 400, "bad_request", err.Error())
			return
		}
		writeOK(w, 201, m)
	default:
		writeErr(w, 405, "method_not_allowed", "method not allowed")
	}
}

func (s *Server) handleV2Profiles(w http.ResponseWriter, r *http.Request) {
	if !s.requireOperator(w, r) {
		return
	}
	rest := strings.TrimPrefix(r.URL.Path, "/api/v2/profiles")
	rest = strings.Trim(rest, "/")
	if rest != "" {
		s.handleV2ProfileSub(w, r, rest)
		return
	}

	switch r.Method {
	case http.MethodGet:
		writeOK(w, 200, s.store.listIXProfiles())
	case http.MethodPost:
		var req CreateIXProfileRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeErr(w, 400, "bad_request", "invalid json")
			return
		}
		p, task, err := s.store.createIXProfile(req)
		if err != nil {
			writeErr(w, 400, "bad_request", err.Error())
			return
		}
		writeOK(w, 201, map[string]any{"profile": p, "task": task})
	default:
		writeErr(w, 405, "method_not_allowed", "method not allowed")
	}
}

func (s *Server) handleV2ProfileSub(w http.ResponseWriter, r *http.Request, path string) {
	parts := strings.SplitN(path, "/", 2)
	profileID := parts[0]
	sub := ""
	if len(parts) > 1 {
		sub = parts[1]
	}

	switch {
	case sub == "" && r.Method == http.MethodGet:
		p, ok := s.store.getIXProfile(profileID)
		if !ok {
			writeErr(w, 404, "not_found", "profile not found")
			return
		}
		writeOK(w, 200, p)
	case sub == "sync" && r.Method == http.MethodPost:
		p, ok := s.store.getIXProfile(profileID)
		if !ok {
			writeErr(w, 404, "not_found", "profile not found")
			return
		}
		payload := map[string]any{"profile_id": profileID}
		tasks := make([]Task, 0, 3)
		for _, action := range []string{"ix_read_show_config", "ix_read_port_map", "ix_read_list_rules"} {
			task, err := s.store.enqueueIXTask(p.MachineID, action, payload)
			if err != nil {
				writeErr(w, 400, "bad_request", err.Error())
				return
			}
			tasks = append(tasks, task)
		}
		writeOK(w, 202, map[string]any{"tasks": tasks})
	case sub == "apply" && r.Method == http.MethodPost:
		p, ok := s.store.getIXProfile(profileID)
		if !ok {
			writeErr(w, 404, "not_found", "profile not found")
			return
		}
		action := "ix_write_apply_rules"
		if p.Role == "nat-transit" {
			action = "ix_write_create_nat"
		}
		task, err := s.store.enqueueIXTask(p.MachineID, action, map[string]any{"profile_id": profileID, "config": p.Config})
		if err != nil {
			writeErr(w, 400, "bad_request", err.Error())
			return
		}
		writeOK(w, 202, map[string]any{"task": task})
	case strings.HasPrefix(sub, "code"):
		s.handleV2ProfileCode(w, r, profileID, sub)
	default:
		writeErr(w, 404, "not_found", "unknown sub-resource")
	}
}

func (s *Server) handleV2ProfileCode(w http.ResponseWriter, r *http.Request, profileID, sub string) {
	p, ok := s.store.getIXProfile(profileID)
	if !ok {
		writeErr(w, 404, "not_found", "profile not found")
		return
	}
	switch {
	case sub == "code" && r.Method == http.MethodGet:
		task, err := s.store.enqueueIXTask(p.MachineID, "ix_read_show_code", map[string]any{"profile_id": profileID})
		if err != nil {
			writeErr(w, 400, "bad_request", err.Error())
			return
		}
		writeOK(w, 202, map[string]any{"task": task})
	case sub == "code/refresh" && r.Method == http.MethodPost:
		task, err := s.store.enqueueIXTask(p.MachineID, "ix_write_refresh_code", map[string]any{"profile_id": profileID})
		if err != nil {
			writeErr(w, 400, "bad_request", err.Error())
			return
		}
		writeOK(w, 202, map[string]any{"task": task})
	default:
		writeErr(w, 405, "method_not_allowed", "method not allowed")
	}
}

func (s *Server) handleV2DiagnosticsRun(w http.ResponseWriter, r *http.Request) {
	if !s.requireOperator(w, r) {
		return
	}
	if r.Method != http.MethodPost {
		writeErr(w, 405, "method_not_allowed", "method not allowed")
		return
	}
	var body struct {
		MachineIDs []string `json:"machine_ids"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, 400, "bad_request", "invalid json")
		return
	}
	diagnosticID := newID()
	targets := body.MachineIDs
	if len(targets) == 0 {
		for _, m := range s.store.listIXMachines() {
			targets = append(targets, m.ID)
		}
	}
	tasks := make([]Task, 0, len(targets)*2)
	for _, machineID := range targets {
		payload := map[string]any{"diagnostic_id": diagnosticID, "machine_id": machineID}
		for _, action := range []string{"ix_read_health", "ix_read_diagnose"} {
			task, err := s.store.enqueueIXTask(machineID, action, payload)
			if err != nil {
				writeErr(w, 400, "bad_request", err.Error())
				return
			}
			tasks = append(tasks, task)
		}
	}
	writeOK(w, 202, map[string]any{"diagnostic_id": diagnosticID, "tasks": tasks})
}

func (s *Server) handleV2BootstrapInstall(w http.ResponseWriter, r *http.Request) {
	if !s.requireOperator(w, r) {
		return
	}
	if r.Method != http.MethodPost {
		writeErr(w, 405, "method_not_allowed", "method not allowed")
		return
	}
	var body struct {
		MachineID string `json:"machine_id"`
		Version   string `json:"version"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, 400, "bad_request", "invalid json")
		return
	}
	m, ok := s.store.getIXMachine(body.MachineID)
	if !ok {
		writeErr(w, 404, "not_found", "machine not found")
		return
	}
	version := body.Version
	if version == "" {
		version = Version
	}
	controllerURL := strings.TrimSuffix(r.Header.Get("X-Forwarded-Proto")+"://"+r.Host, "://")
	if r.TLS != nil || r.Header.Get("X-Forwarded-Proto") == "https" {
		controllerURL = "https://" + r.Host
	} else {
		controllerURL = "http://" + r.Host
	}
	rootCmd := fmt.Sprintf(`curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-agent.sh | bash -s -- \
  --version %s \
  --controller-url %s \
  --token %s \
  --node-name %s \
  --machine-id %s \
  --enable-tasks \
  --enable-write-actions \
  --install-ixtf \
  --ixtf-version v1.2.0`,
		version, controllerURL, m.Token, m.Name, m.ID)
	writeOK(w, 200, map[string]any{
		"machine_id":   m.ID,
		"root_command": rootCmd,
		"note":         "Agent 注册时在 payload 中携带 machine_id 字段以完成绑定",
		"env_hint":     fmt.Sprintf("EDGE_MACHINE_ID=%s", m.ID),
	})
}

func (s *Server) handleV2Tasks(w http.ResponseWriter, r *http.Request) {
	if !s.requireOperator(w, r) {
		return
	}
	rest := strings.TrimPrefix(r.URL.Path, "/api/v2/tasks/")
	rest = strings.TrimSuffix(rest, "/")
	if rest == "" {
		writeErr(w, 404, "not_found", "not found")
		return
	}
	parts := strings.SplitN(rest, "/", 2)
	id := parts[0]
	sub := ""
	if len(parts) > 1 {
		sub = parts[1]
	}
	if sub == "stream" {
		s.handleV2TaskStream(w, r, id)
		return
	}
	if sub != "" {
		writeErr(w, 404, "not_found", "not found")
		return
	}
	if r.Method != http.MethodGet {
		writeErr(w, 405, "method_not_allowed", "method not allowed")
		return
	}
	task, ok := s.store.getTask(id)
	if !ok {
		writeErr(w, 404, "not_found", "task not found")
		return
	}
	writeOK(w, 200, task)
}

func taskTerminal(status string) bool {
	switch status {
	case "succeeded", "failed", "expired", "cancelled":
		return true
	default:
		return false
	}
}

func (s *Server) handleV2TaskStream(w http.ResponseWriter, r *http.Request, id string) {
	if r.Method != http.MethodGet {
		writeErr(w, 405, "method_not_allowed", "method not allowed")
		return
	}
	if _, ok := s.store.getTask(id); !ok {
		writeErr(w, 404, "not_found", "task not found")
		return
	}
	flusher, ok := w.(http.Flusher)
	if !ok {
		writeErr(w, 500, "internal", "streaming unsupported")
		return
	}
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")

	sendTask := func(task Task) {
		raw, _ := json.Marshal(task)
		_, _ = fmt.Fprintf(w, "data: %s\n\n", raw)
		flusher.Flush()
	}

	lastFingerprint := ""
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	timeout := time.After(5 * time.Minute)

	for {
		task, ok := s.store.getTask(id)
		if !ok {
			_, _ = fmt.Fprintf(w, "event: error\ndata: {\"message\":\"task not found\"}\n\n")
			flusher.Flush()
			return
		}
		fp := task.Status + "|" + task.Result + "|" + task.Stdout + "|" + task.Error
		if fp != lastFingerprint {
			sendTask(task)
			lastFingerprint = fp
		}
		if taskTerminal(task.Status) {
			return
		}
		select {
		case <-r.Context().Done():
			return
		case <-timeout:
			return
		case <-ticker.C:
		}
	}
}
