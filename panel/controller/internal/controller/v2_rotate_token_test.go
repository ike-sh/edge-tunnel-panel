package controller

import (
	"net/http"
	"testing"
)

func TestRotateMachineToken(t *testing.T) {
	h := testOpenServer(t)
	m := createTestMachine(t, h)
	rr := post(t, h, "/api/v2/machines/"+m.ID+"/rotate-token", "", map[string]any{})
	if rr.Code != http.StatusOK {
		t.Fatalf("rotate token: %d %s", rr.Code, rr.Body.String())
	}
}
