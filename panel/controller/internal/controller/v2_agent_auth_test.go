package controller

import (
	"net/http"
	"testing"
)

func TestAgentAuthAcceptsMachineToken(t *testing.T) {
	store, err := OpenStore(t.TempDir() + "/store.json")
	if err != nil {
		t.Fatal(err)
	}
	m, err := store.createIXMachine("nat-1", "nat-transit")
	if err != nil {
		t.Fatal(err)
	}
	h := NewServer(store, "global-agent-token", "operator-token", false, t.TempDir())
	rr := post(t, h, "/api/v1/agent/register", m.Token, map[string]any{
		"name":       "agent-1",
		"machine_id": m.ID,
	})
	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200 with machine token, got %d %s", rr.Code, rr.Body.String())
	}
}

func TestAgentRegisterRejectsGlobalTokenWithForeignMachineID(t *testing.T) {
	store, err := OpenStore(t.TempDir() + "/store.json")
	if err != nil {
		t.Fatal(err)
	}
	m, err := store.createIXMachine("nat-1", "nat-transit")
	if err != nil {
		t.Fatal(err)
	}
	h := NewServer(store, "global-agent-token", "operator-token", false, t.TempDir())
	rr := post(t, h, "/api/v1/agent/register", "global-agent-token", map[string]any{
		"name":       "evil-agent",
		"machine_id": m.ID,
	})
	if rr.Code != http.StatusForbidden {
		t.Fatalf("expected 403 when global token binds machine_id, got %d %s", rr.Code, rr.Body.String())
	}
}

func TestAgentRegisterRejectsMachineTokenWithWrongMachineID(t *testing.T) {
	store, err := OpenStore(t.TempDir() + "/store.json")
	if err != nil {
		t.Fatal(err)
	}
	m1, err := store.createIXMachine("nat-1", "nat-transit")
	if err != nil {
		t.Fatal(err)
	}
	m2, err := store.createIXMachine("nat-2", "nat-transit")
	if err != nil {
		t.Fatal(err)
	}
	h := NewServer(store, "global-agent-token", "operator-token", false, t.TempDir())
	rr := post(t, h, "/api/v1/agent/register", m1.Token, map[string]any{
		"name":       "agent-1",
		"machine_id": m2.ID,
	})
	if rr.Code != http.StatusForbidden {
		t.Fatalf("expected 403 when machine token mismatches machine_id, got %d %s", rr.Code, rr.Body.String())
	}
}
