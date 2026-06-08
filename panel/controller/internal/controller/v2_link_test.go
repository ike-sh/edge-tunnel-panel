package controller

import (
	"net/http"
	"testing"
)

func TestLinkMachineActivatesWaitingTasks(t *testing.T) {
	store, err := OpenStore(t.TempDir() + "/store.json")
	if err != nil {
		t.Fatal(err)
	}

	m, err := store.createIXMachine("nat-1", "nat-transit")
	if err != nil {
		t.Fatal(err)
	}
	_, task, err := store.createIXProfile(CreateIXProfileRequest{
		Name:      "line-1",
		MachineID: m.ID,
		Config:    map[string]any{},
	})
	if err != nil {
		t.Fatal(err)
	}
	if task.Status != "waiting_agent" {
		t.Fatalf("expected waiting_agent, got %s", task.Status)
	}

	activated, err := store.linkMachineToNode(m.ID, "node-abc")
	if err != nil {
		t.Fatal(err)
	}
	if activated != 1 {
		t.Fatalf("expected 1 activated task, got %d", activated)
	}
	updated, ok := store.getTask(task.ID)
	if !ok {
		t.Fatal("task not found")
	}
	if updated.Status != "pending" || updated.NodeID != "node-abc" {
		t.Fatalf("unexpected task after link: %+v", updated)
	}
	machine, ok := store.getIXMachine(m.ID)
	if !ok || machine.NodeID != "node-abc" {
		t.Fatalf("machine not linked: %+v", machine)
	}

	pending := store.tasksForNode("node-abc")
	if len(pending) != 1 {
		t.Fatalf("expected 1 pending task for node, got %d", len(pending))
	}
}

func TestAgentRegisterWithMachineID(t *testing.T) {
	h := testOpenServer(t)
	m := createTestMachine(t, h)

	rr := post(t, h, "/api/v1/agent/register", "agent-token", map[string]any{
		"id":         "node-linked",
		"node_name":  "nat-1",
		"machine_id": m.ID,
	})
	if rr.Code != http.StatusOK {
		t.Fatalf("register: %d %s", rr.Code, rr.Body.String())
	}

	rr = post(t, h, "/api/v2/profiles", "", map[string]any{
		"name":       "after-link",
		"machine_id": m.ID,
	})
	if rr.Code != http.StatusCreated {
		t.Fatalf("create profile after link: %d %s", rr.Code, rr.Body.String())
	}
}
