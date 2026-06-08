package controller

import (
	"encoding/json"
	"fmt"
	"strings"
)

func (s *Store) listIXMachines() []IXMachine {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make([]IXMachine, len(s.data.IXMachines))
	copy(out, s.data.IXMachines)
	for i := range out {
		out[i].Token = ""
	}
	return out
}

func (s *Store) getIXMachine(id string) (IXMachine, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, m := range s.data.IXMachines {
		if m.ID == id {
			m.Token = ""
			return m, true
		}
	}
	return IXMachine{}, false
}

func (s *Store) matchMachineToken(token string) bool {
	if strings.TrimSpace(token) == "" {
		return false
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, m := range s.data.IXMachines {
		if m.Token != "" && tokenMatches(token, m.Token) {
			return true
		}
	}
	return false
}

func (s *Store) createIXMachine(name, role string) (IXMachine, error) {
	if name == "" {
		return IXMachine{}, fmt.Errorf("name is required")
	}
	if role != "nat-transit" && role != "nat-ingress" {
		return IXMachine{}, fmt.Errorf("role must be nat-transit or nat-ingress")
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	token := randomSecret()
	m := IXMachine{
		ID:     newID(),
		Name:   name,
		Role:   role,
		Token:  token,
		Status: "pending",
	}
	s.data.IXMachines = append(s.data.IXMachines, m)
	if err := s.saveLocked(); err != nil {
		return IXMachine{}, err
	}
	return m, nil
}

func (s *Store) listIXProfiles() []IXProfile {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make([]IXProfile, len(s.data.IXProfiles))
	copy(out, s.data.IXProfiles)
	return out
}

func (s *Store) getIXProfile(id string) (IXProfile, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, p := range s.data.IXProfiles {
		if p.ID == id {
			return p, true
		}
	}
	return IXProfile{}, false
}

func (s *Store) createIXProfile(req CreateIXProfileRequest) (IXProfile, Task, error) {
	if req.Name == "" {
		return IXProfile{}, Task{}, fmt.Errorf("name is required")
	}
	if req.MachineID == "" {
		return IXProfile{}, Task{}, fmt.Errorf("machine_id is required")
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	var machine *IXMachine
	for i := range s.data.IXMachines {
		if s.data.IXMachines[i].ID == req.MachineID {
			machine = &s.data.IXMachines[i]
			break
		}
	}
	if machine == nil {
		return IXProfile{}, Task{}, fmt.Errorf("machine not found")
	}
	role := req.Role
	if role == "" {
		role = machine.Role
	}
	ts := now()
	p := IXProfile{
		ID:        newID(),
		Name:      req.Name,
		Role:      role,
		MachineID: req.MachineID,
		Enabled:   true,
		Status:    "pending",
		Config:    req.Config,
		CreatedAt: ts,
		UpdatedAt: ts,
	}
	s.data.IXProfiles = append(s.data.IXProfiles, p)
	action := "ix_write_create_nat"
	if role == "nat-ingress" {
		action = "ix_write_import_code"
	}
	payload := map[string]any{
		"profile_id": p.ID,
		"machine_id": req.MachineID,
		"config":     req.Config,
	}
	if strings.TrimSpace(req.Code) != "" {
		payload["code"] = req.Code
	}
	nodeID := machine.NodeID
	task := s.enqueueTaskLocked(nodeID, action, payload)
	if nodeID == "" {
		task.Status = "waiting_agent"
	}
	if err := s.saveLocked(); err != nil {
		return IXProfile{}, Task{}, err
	}
	return p, *task, nil
}

func (s *Store) enqueueIXTask(machineID, action string, payload map[string]any) (Task, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if payload == nil {
		payload = map[string]any{}
	}
	if machineID != "" {
		payload["machine_id"] = machineID
	}
	var nodeID string
	for _, m := range s.data.IXMachines {
		if m.ID == machineID {
			nodeID = m.NodeID
			break
		}
	}
	if nodeID == "" {
		task := s.enqueueTaskLocked("", action, payload)
		task.Status = "waiting_agent"
		if err := s.saveLocked(); err != nil {
			return Task{}, err
		}
		return *task, nil
	}
	task := s.enqueueTaskLocked(nodeID, action, payload)
	if err := s.saveLocked(); err != nil {
		return Task{}, err
	}
	return *task, nil
}

func (s *Store) linkMachineToNode(machineID, nodeID string) (int, error) {
	if machineID == "" || nodeID == "" {
		return 0, nil
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	linked := false
	for i := range s.data.IXMachines {
		if s.data.IXMachines[i].ID == machineID {
			s.data.IXMachines[i].NodeID = nodeID
			s.data.IXMachines[i].Status = "online"
			s.data.IXMachines[i].LastSeen = now()
			linked = true
			break
		}
	}
	if !linked {
		return 0, fmt.Errorf("machine not found")
	}
	activated := 0
	for i := range s.data.Tasks {
		t := &s.data.Tasks[i]
		if t.Status != "waiting_agent" {
			continue
		}
		mid, _ := t.Payload["machine_id"].(string)
		if mid != machineID {
			continue
		}
		t.NodeID = nodeID
		t.Status = "pending"
		activated++
	}
	if err := s.saveLocked(); err != nil {
		return 0, err
	}
	return activated, nil
}

func (s *Store) enqueueTaskLocked(nodeID, action string, payload map[string]any) *Task {
	task := Task{
		ID:        newID(),
		NodeID:    nodeID,
		Action:    action,
		Payload:   payload,
		Status:    "pending",
		CreatedAt: now(),
	}
	s.data.Tasks = append(s.data.Tasks, task)
	return &s.data.Tasks[len(s.data.Tasks)-1]
}

func (s *Store) getTask(id string) (Task, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, t := range s.data.Tasks {
		if t.ID == id {
			return t, true
		}
	}
	return Task{}, false
}

func profileIDFromPayload(payload map[string]any) string {
	if payload == nil {
		return ""
	}
	id, _ := payload["profile_id"].(string)
	return strings.TrimSpace(id)
}

func ixTaskContent(task Task) string {
	if parsed := parseJSONMap(task.Result); parsed != nil {
		if stdout, ok := parsed["stdout"].(string); ok && strings.TrimSpace(stdout) != "" {
			return stdout
		}
	}
	if strings.TrimSpace(task.Stdout) != "" {
		return task.Stdout
	}
	return task.Result
}

func (s *Store) applyIXTaskResultLocked(task Task) {
	profileID := profileIDFromPayload(task.Payload)
	if profileID == "" {
		return
	}
	for i := range s.data.IXProfiles {
		if s.data.IXProfiles[i].ID != profileID {
			continue
		}
		p := &s.data.IXProfiles[i]
		p.UpdatedAt = now()
		if task.Status == "failed" && strings.HasPrefix(task.Action, "ix_write_") {
			p.Status = "failed"
			return
		}
		if task.Status != "succeeded" {
			return
		}
		content := ixTaskContent(task)
		switch task.Action {
		case "ix_read_show_code", "ix_write_refresh_code":
			p.CodeRedacted = capText(content)
		case "ix_read_port_map":
			p.PortMap = capText(content)
		case "ix_read_show_config":
			p.Status = "healthy"
			if parsed := parseJSONMap(content); len(parsed) > 0 {
				if cfg, ok := parsed["config"].(map[string]any); ok {
					p.Config = cfg
				}
			}
		case "ix_read_list_rules":
			p.Rules = parseIXRules(content, profileID)
		case "ix_write_create_nat", "ix_write_apply_rules", "ix_write_import_code":
			p.Status = "healthy"
		}
		return
	}
}

func parseJSONMap(raw string) map[string]any {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return nil
	}
	out := map[string]any{}
	if err := json.Unmarshal([]byte(raw), &out); err != nil {
		return nil
	}
	return out
}

func parseIXRules(raw, profileID string) []IXRule {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return nil
	}
	var rules []IXRule
	if err := json.Unmarshal([]byte(raw), &rules); err == nil && len(rules) > 0 {
		for i := range rules {
			if rules[i].ProfileID == "" {
				rules[i].ProfileID = profileID
			}
		}
		return rules
	}
	var envelope struct {
		Rules []IXRule `json:"rules"`
	}
	if err := json.Unmarshal([]byte(raw), &envelope); err == nil && len(envelope.Rules) > 0 {
		for i := range envelope.Rules {
			if envelope.Rules[i].ProfileID == "" {
				envelope.Rules[i].ProfileID = profileID
			}
		}
		return envelope.Rules
	}
	return nil
}
