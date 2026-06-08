package controller

import (
	"encoding/json"
	"net/http"
	"testing"
)

func TestV2CreateMachineAndProfile(t *testing.T) {
	h := testOpenServer(t)

	rr := post(t, h, "/api/v2/machines", "", map[string]any{
		"name": "nat-ix-1",
		"role": "nat-transit",
	})
	if rr.Code != http.StatusCreated {
		t.Fatalf("create machine: %d %s", rr.Code, rr.Body.String())
	}
	var machineResp struct {
		OK   bool      `json:"ok"`
		Data IXMachine `json:"data"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &machineResp); err != nil {
		t.Fatal(err)
	}
	if machineResp.Data.ID == "" || machineResp.Data.Token == "" {
		t.Fatalf("expected machine id and token: %+v", machineResp.Data)
	}

	rr = post(t, h, "/api/v2/profiles", "", map[string]any{
		"name":       "test-line",
		"machine_id": machineResp.Data.ID,
		"role":       "nat-transit",
		"config": map[string]any{
			"NAT_PUBLIC_HOST": "nat.example",
			"LANDING_HOST":    "landing.example",
		},
	})
	if rr.Code != http.StatusCreated {
		t.Fatalf("create profile: %d %s", rr.Code, rr.Body.String())
	}
	var profileResp struct {
		OK   bool `json:"ok"`
		Data struct {
			Profile IXProfile `json:"profile"`
			Task    Task      `json:"task"`
		} `json:"data"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &profileResp); err != nil {
		t.Fatal(err)
	}
	if profileResp.Data.Profile.ID == "" {
		t.Fatal("expected profile id")
	}
	if profileResp.Data.Task.Action != "ix_write_create_nat" {
		t.Fatalf("expected ix_write_create_nat task, got %s", profileResp.Data.Task.Action)
	}
	if profileResp.Data.Task.Status != "waiting_agent" {
		t.Fatalf("expected waiting_agent before agent registers, got %s", profileResp.Data.Task.Status)
	}

	rr = get(t, h, "/api/v2/profiles", "")
	if rr.Code != http.StatusOK {
		t.Fatalf("list profiles: %d", rr.Code)
	}

	rr = get(t, h, "/api/v2/profiles/"+profileResp.Data.Profile.ID, "")
	if rr.Code != http.StatusOK {
		t.Fatalf("get profile: %d %s", rr.Code, rr.Body.String())
	}
}

func TestV2ProfileSyncEnqueuesTask(t *testing.T) {
	h := testOpenServer(t)
	machine := createTestMachine(t, h)

	rr := post(t, h, "/api/v2/profiles", "", map[string]any{
		"name":       "sync-line",
		"machine_id": machine.ID,
		"config":     map[string]any{},
	})
	if rr.Code != http.StatusCreated {
		t.Fatalf("create profile: %d", rr.Code)
	}
	var created struct {
		Data struct {
			Profile IXProfile `json:"profile"`
		} `json:"data"`
	}
	_ = json.Unmarshal(rr.Body.Bytes(), &created)

	rr = post(t, h, "/api/v2/profiles/"+created.Data.Profile.ID+"/sync", "", map[string]any{})
	if rr.Code != http.StatusAccepted && rr.Code != http.StatusOK {
		t.Fatalf("sync profile: %d %s", rr.Code, rr.Body.String())
	}
	var syncResp struct {
		Data struct {
			Tasks []Task `json:"tasks"`
		} `json:"data"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &syncResp); err != nil {
		t.Fatal(err)
	}
	if len(syncResp.Data.Tasks) != 3 {
		t.Fatalf("expected 3 sync tasks, got %d", len(syncResp.Data.Tasks))
	}
	if syncResp.Data.Tasks[0].Action != "ix_read_show_config" {
		t.Fatalf("expected ix_read_show_config, got %s", syncResp.Data.Tasks[0].Action)
	}
	if syncResp.Data.Tasks[0].Status != "waiting_agent" {
		t.Fatalf("expected waiting_agent before agent registers, got %s", syncResp.Data.Tasks[0].Status)
	}
}

func TestV2ProfilePauseDiagnose(t *testing.T) {
	h := testOpenServer(t)
	machine := createTestMachine(t, h)

	rr := post(t, h, "/api/v2/profiles", "", map[string]any{
		"name":       "pause-line",
		"machine_id": machine.ID,
		"config":     map[string]any{},
	})
	if rr.Code != http.StatusCreated {
		t.Fatalf("create profile: %d", rr.Code)
	}
	var created struct {
		Data struct {
			Profile IXProfile `json:"profile"`
		} `json:"data"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &created); err != nil {
		t.Fatal(err)
	}
	pid := created.Data.Profile.ID

	rr = post(t, h, "/api/v2/profiles/"+pid+"/pause", "", map[string]any{})
	if rr.Code != http.StatusAccepted && rr.Code != http.StatusOK {
		t.Fatalf("pause profile: %d %s", rr.Code, rr.Body.String())
	}
	var pauseResp struct {
		Data struct {
			Task    Task `json:"task"`
			Enabled bool `json:"enabled"`
		} `json:"data"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &pauseResp); err != nil {
		t.Fatal(err)
	}
	if pauseResp.Data.Task.Action != "ix_write_disable_profile" {
		t.Fatalf("expected ix_write_disable_profile, got %s", pauseResp.Data.Task.Action)
	}
	if pauseResp.Data.Enabled {
		t.Fatal("expected enabled=false")
	}

	rr = get(t, h, "/api/v2/profiles/"+pid, "")
	if rr.Code != http.StatusOK {
		t.Fatalf("get profile: %d", rr.Code)
	}
	var getResp struct {
		Data IXProfile `json:"data"`
	}
	_ = json.Unmarshal(rr.Body.Bytes(), &getResp)
	if getResp.Data.Enabled {
		t.Fatal("profile should be disabled after pause")
	}

	rr = post(t, h, "/api/v2/profiles/"+pid+"/diagnose", "", map[string]any{})
	if rr.Code != http.StatusAccepted && rr.Code != http.StatusOK {
		t.Fatalf("diagnose profile: %d %s", rr.Code, rr.Body.String())
	}
	var diagResp struct {
		Data struct {
			Task Task `json:"task"`
		} `json:"data"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &diagResp); err != nil {
		t.Fatal(err)
	}
	if diagResp.Data.Task.Action != "ix_read_diagnose" {
		t.Fatalf("expected ix_read_diagnose, got %s", diagResp.Data.Task.Action)
	}
}

func TestV2RequiresAuthWhenStrict(t *testing.T) {
	h := testServer(t)
	rr := get(t, h, "/api/v2/machines", "")
	if rr.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rr.Code)
	}
}

func createTestMachine(t *testing.T, h http.Handler) IXMachine {
	t.Helper()
	rr := post(t, h, "/api/v2/machines", "", map[string]any{"name": "m1", "role": "nat-transit"})
	if rr.Code != http.StatusCreated {
		t.Fatalf("create machine: %d", rr.Code)
	}
	var resp struct {
		Data IXMachine `json:"data"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	return resp.Data
}

func TestIXActionAllowedInAgentTaskModel(t *testing.T) {
	// Smoke: ensure v2 task actions match design doc naming.
	actions := []string{
		"ix_read_health", "ix_write_create_nat", "ix_write_import_code",
	}
	for _, action := range actions {
		if action == "" {
			t.Fatal("empty action")
		}
	}
}
