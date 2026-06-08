package controller

import (
	"net/http"
	"testing"
)

func TestDeprecatedV1Returns410WhenLegacyDisabled(t *testing.T) {
	t.Setenv("EDGE_LEGACY_V1_API", "0")
	store, err := OpenStore(t.TempDir() + "/store.json")
	if err != nil {
		t.Fatal(err)
	}
	h := NewServer(store, "agent-token", "operator-token", false, t.TempDir())
	rr := get(t, h, "/api/v1/forwards", "")
	if rr.Code != http.StatusGone {
		t.Fatalf("expected 410, got %d %s", rr.Code, rr.Body.String())
	}
}
