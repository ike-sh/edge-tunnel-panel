package controller

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

type Store struct {
	mu   sync.Mutex
	path string
	data StoreFile
}

func OpenStore(path string) (*Store, error) {
	s := &Store{path: path}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return nil, err
	}
	raw, err := os.ReadFile(path)
	if err == nil && len(raw) > 0 {
		if err := json.Unmarshal(raw, &s.data); err != nil {
			return nil, err
		}
	}
	return s, nil
}

func (s *Store) saveLocked() error {
	raw, err := json.MarshalIndent(s.data, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(s.path, raw, 0o644)
}

func newID() string {
	var b [8]byte
	_, _ = rand.Read(b[:])
	return hex.EncodeToString(b[:])
}

func randomSecret() string {
	var b [24]byte
	_, _ = rand.Read(b[:])
	return hex.EncodeToString(b[:])
}

func now() time.Time { return time.Now().UTC() }

func (s *Store) listNodes() []Node {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := append([]Node(nil), s.data.Nodes...)
	n := now()
	for i := range out {
		out[i] = applyNodeLiveness(out[i], n)
	}
	return out
}

func (s *Store) listNetworkProfiles() []NetworkProfile {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]NetworkProfile(nil), s.data.NetworkProfiles...)
}

func applyNodeLiveness(node Node, at time.Time) Node {
	node.Status, node.StatusReason = nodeStatusReason(node, at)
	return node
}

func nodeStatusReason(node Node, at time.Time) (string, string) {
	if node.OfflineAt != nil && (node.LastSeenAt.IsZero() || !node.LastSeenAt.After(*node.OfflineAt)) {
		if node.StatusReason != "" {
			return "offline", node.StatusReason
		}
		return "offline", "agent reported offline"
	}
	if node.LastSeenAt.IsZero() {
		return "offline", "no heartbeat received"
	}
	d := at.Sub(node.LastSeenAt)
	if d <= 90*time.Second {
		return "online", "recent heartbeat normal"
	}
	if d <= 5*time.Minute {
		return "stale", "heartbeat missing for over 90 seconds"
	}
	return "offline", "heartbeat missing for over 5 minutes"
}

func (s *Store) createNode(node Node) (Node, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if node.ID == "" {
		node.ID = newID()
	}
	for i := range s.data.Nodes {
		if s.data.Nodes[i].ID == node.ID {
			existing := s.data.Nodes[i]
			if node.Name != "" {
				existing.Name = node.Name
			}
			if node.Role != "" {
				existing.Role = node.Role
			}
			if node.Hostname != "" {
				existing.Hostname = node.Hostname
			}
			existing.Status = "online"
			existing.LastSeenAt = now()
			existing.UpdatedAt = existing.LastSeenAt
			existing.OfflineAt = nil
			existing.StatusReason = ""
			s.data.Nodes[i] = existing
			return existing, s.saveLocked()
		}
	}
	node.Status = "online"
	node.CreatedAt = now()
	node.UpdatedAt = node.CreatedAt
	s.data.Nodes = append(s.data.Nodes, node)
	return node, s.saveLocked()
}

func (s *Store) upsertReport(node Node) (Node, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i := range s.data.Nodes {
		if (node.ID != "" && s.data.Nodes[i].ID == node.ID) || (node.ID == "" && node.Name != "" && s.data.Nodes[i].Name == node.Name && s.data.Nodes[i].Hostname == node.Hostname) {
			node.ID = s.data.Nodes[i].ID
			node.CreatedAt = s.data.Nodes[i].CreatedAt
			node.UpdatedAt = now()
			node.OfflineAt = nil
			node.StatusReason = ""
			s.data.Nodes[i] = node
			return node, s.saveLocked()
		}
	}
	if node.ID == "" {
		node.ID = newID()
	}
	node.CreatedAt = now()
	node.UpdatedAt = node.CreatedAt
	s.data.Nodes = append(s.data.Nodes, node)
	return node, s.saveLocked()
}

func (s *Store) deleteNode(id string) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i := range s.data.Nodes {
		if s.data.Nodes[i].ID == id {
			s.data.Nodes = append(s.data.Nodes[:i], s.data.Nodes[i+1:]...)
			return true, s.saveLocked()
		}
	}
	return false, nil
}

func (s *Store) markNodeOffline(id, reason string) (Node, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i := range s.data.Nodes {
		if s.data.Nodes[i].ID == id {
			n := now()
			if strings.TrimSpace(reason) == "" {
				reason = "agent reported offline"
			}
			s.data.Nodes[i].Status = "offline"
			s.data.Nodes[i].StatusReason = reason
			s.data.Nodes[i].OfflineAt = &n
			s.data.Nodes[i].UpdatedAt = n
			return s.data.Nodes[i], true, s.saveLocked()
		}
	}
	return Node{}, false, nil
}

func (s *Store) createTask(t Task) (Task, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	t.ID = newID()
	t.CreatedAt = now()
	t.Status = "pending"
	t.ExpiresAt = defaultTaskExpiry()
	s.data.Tasks = append(s.data.Tasks, t)
	return t, s.saveLocked()
}

func (s *Store) tasksForNode(nodeID string) []Task {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := []Task{}
	for _, t := range s.data.Tasks {
		if t.NodeID == nodeID && t.Status == "pending" {
			out = append(out, t)
		}
	}
	return out
}

func (s *Store) listTasks(nodeID, status string) []Task {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := []Task{}
	for _, task := range s.data.Tasks {
		if nodeID != "" && task.NodeID != nodeID {
			continue
		}
		if status != "" && status != "all" && task.Status != status {
			continue
		}
		out = append(out, task)
	}
	return out
}

func (s *Store) updateTaskResult(id string, req map[string]any) (Task, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i := range s.data.Tasks {
		if s.data.Tasks[i].ID == id {
			t := &s.data.Tasks[i]
			n := now()
			t.StartedAt = &n
			t.FinishedAt = &n
			t.Status = stringValue(req["status"], "failed")
			t.Result = capText(stringValue(req["result"], ""))
			t.Stdout = capText(stringValue(req["stdout"], stringValue(req["result_stdout"], "")))
			t.Stderr = capText(stringValue(req["stderr"], stringValue(req["result_stderr"], "")))
			t.Error = capText(stringValue(req["error"], ""))
			return *t, true, s.saveLocked()
		}
	}
	return Task{}, false, nil
}

func (s *Store) getNetworkProfile(id string) (NetworkProfile, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, profile := range s.data.NetworkProfiles {
		if profile.ID == id {
			return profile, true
		}
	}
	return NetworkProfile{}, false
}

func (s *Store) createNetworkProfile(req map[string]any) (NetworkProfile, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	name := stringValue(req["name"], "")
	if name == "" {
		return NetworkProfile{}, errValidation("name is required")
	}
	n := now()
	item := NetworkProfile{ID: newID(), Name: name, NetworkName: stringValue(req["network_name"], "edge-net"), NetworkSecret: stringValue(req["network_secret"], randomSecret()), CIDR: stringValue(req["cidr"], "10.144.0.0/16"), ProtocolPreference: stringValue(req["protocol_preference"], "auto"), Listeners: defaultListeners(stringListValue(req["listeners"])), Peers: stringListValue(req["peers"]), CreatedAt: n, UpdatedAt: n}
	s.data.NetworkProfiles = append(s.data.NetworkProfiles, item)
	return item, s.saveLocked()
}

func (s *Store) updateNetworkProfile(id string, req map[string]any) (NetworkProfile, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i := range s.data.NetworkProfiles {
		if s.data.NetworkProfiles[i].ID != id {
			continue
		}
		item := s.data.NetworkProfiles[i]
		if value := stringValue(req["name"], item.Name); value != "" {
			item.Name = value
		}
		item.NetworkName = stringValue(req["network_name"], item.NetworkName)
		item.NetworkSecret = stringValue(req["network_secret"], item.NetworkSecret)
		item.CIDR = stringValue(req["cidr"], item.CIDR)
		item.ProtocolPreference = stringValue(req["protocol_preference"], item.ProtocolPreference)
		if listeners, ok := req["listeners"]; ok {
			item.Listeners = defaultListeners(stringListValue(listeners))
		}
		if peers, ok := req["peers"]; ok {
			item.Peers = stringListValue(peers)
		}
		item.UpdatedAt = now()
		s.data.NetworkProfiles[i] = item
		return item, true, s.saveLocked()
	}
	return NetworkProfile{}, false, nil
}

func defaultListeners(listeners []string) []string {
	if len(listeners) == 0 {
		return []string{"tcp://0.0.0.0:11010", "udp://0.0.0.0:11010"}
	}
	return listeners
}

func (s *Store) deleteNetworkProfile(id string) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i := range s.data.NetworkProfiles {
		if s.data.NetworkProfiles[i].ID == id {
			s.data.NetworkProfiles = append(s.data.NetworkProfiles[:i], s.data.NetworkProfiles[i+1:]...)
			return true, s.saveLocked()
		}
	}
	return false, nil
}

func (s *Store) getNode(id string) (Node, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, node := range s.data.Nodes {
		if node.ID == id {
			return applyNodeLiveness(node, now()), true
		}
	}
	return Node{}, false
}

type validationError string

func (e validationError) Error() string  { return string(e) }
func errValidation(message string) error { return validationError(message) }

func stringListValue(value any) []string {
	switch list := value.(type) {
	case []string:
		return append([]string(nil), list...)
	case []any:
		out := make([]string, 0, len(list))
		for _, item := range list {
			if text, ok := item.(string); ok && text != "" {
				out = append(out, text)
			}
		}
		return out
	case string:
		if list == "" {
			return nil
		}
		return []string{list}
	default:
		return nil
	}
}
