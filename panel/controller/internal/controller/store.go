package controller

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
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

func now() time.Time { return time.Now().UTC() }

func (s *Store) listNodes() []Node {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := append([]Node(nil), s.data.Nodes...)
	for i := range out {
		out[i].Status = nodeStatus(out[i].LastSeenAt)
	}
	return out
}

func nodeStatus(lastSeen time.Time) string {
	if lastSeen.IsZero() {
		return "offline"
	}
	d := time.Since(lastSeen)
	if d < 90*time.Second {
		return "online"
	}
	if d < 5*time.Minute {
		return "stale"
	}
	return "offline"
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
			s.data.Nodes[i] = existing
			return existing, s.saveLocked()
		}
	}
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
