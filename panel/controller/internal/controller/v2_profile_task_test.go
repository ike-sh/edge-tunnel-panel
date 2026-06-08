package controller

import (
	"testing"
)

func TestApplyIXTaskResultUpdatesProfileFields(t *testing.T) {
	s, err := OpenStore(t.TempDir() + "/store.json")
	if err != nil {
		t.Fatal(err)
	}
	m, err := s.createIXMachine("nat-1", "nat-transit")
	if err != nil {
		t.Fatal(err)
	}
	p, _, err := s.createIXProfile(CreateIXProfileRequest{
		Name:      "line-1",
		MachineID: m.ID,
		Config:    map[string]any{"LANDING_HOST": "1.2.3.4"},
	})
	if err != nil {
		t.Fatal(err)
	}

	s.mu.Lock()
	task := Task{
		ID:     "task-code",
		Action: "ix_read_show_code",
		Status: "succeeded",
		Result: `{"stdout":"IXTF1:[REDACTED]\nline-1"}`,
		Payload: map[string]any{
			"profile_id": p.ID,
		},
	}
	s.applyIXTaskResultLocked(task)
	s.mu.Unlock()

	got, ok := s.getIXProfile(p.ID)
	if !ok {
		t.Fatal("profile missing")
	}
	if got.CodeRedacted == "" {
		t.Fatalf("expected code_redacted, got %+v", got)
	}

	s.mu.Lock()
	task2 := Task{
		ID:     "task-map",
		Action: "ix_read_port_map",
		Status: "succeeded",
		Stdout: "11010 -> 22022",
		Payload: map[string]any{
			"profile_id": p.ID,
		},
	}
	s.applyIXTaskResultLocked(task2)
	s.mu.Unlock()

	got, _ = s.getIXProfile(p.ID)
	if got.PortMap != "11010 -> 22022" {
		t.Fatalf("expected port_map, got %q", got.PortMap)
	}
}
