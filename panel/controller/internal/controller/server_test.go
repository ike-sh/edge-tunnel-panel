package controller

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
)

func testServer(t *testing.T) http.Handler {
	t.Helper()
	store, err := OpenStore(filepath.Join(t.TempDir(), "controller.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = store.Close() })
	return NewServer(store, "test-token", nil)
}

func postJSON(t *testing.T, h http.Handler, path, token string, body any) *httptest.ResponseRecorder {
	t.Helper()
	raw, err := json.Marshal(body)
	if err != nil {
		t.Fatal(err)
	}
	req := httptest.NewRequest(http.MethodPost, path, bytes.NewReader(raw))
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, req)
	return rr
}

func TestAgentReportRequiresToken(t *testing.T) {
	h := testServer(t)
	rr := postJSON(t, h, "/api/v1/agent/report", "", ReportRequest{NodeID: "node-a"})
	if rr.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d: %s", rr.Code, rr.Body.String())
	}
}

func TestRegisterAndReportWithToken(t *testing.T) {
	h := testServer(t)
	reg := postJSON(t, h, "/api/v1/agent/register", "test-token", RegisterRequest{NodeID: "node-a", NodeName: "A", Role: "entry"})
	if reg.Code != http.StatusOK {
		t.Fatalf("register failed: %d %s", reg.Code, reg.Body.String())
	}
	report := ReportRequest{
		NodeID: "node-a", NodeName: "A", Role: "entry", PublicIP: "1.2.3.4", PrimaryLANIP: "10.0.0.2",
		AgentVersion: Version, CoreVersion: "1.4.0 LTS", Status: "online", HealthScore: 96,
		Entries:  []EntryPayload{{Name: "public1", ListenPort: 8301, Protocol: "tcp,udp", PublicHost: "home.example.com", Status: "ok"}},
		Forwards: []ForwardPayload{{Name: "hk", EntryName: "public1", TargetHost: "10.0.0.8", TargetPort: 443, Protocol: "tcp,udp", Status: "ok"}},
	}
	rr := postJSON(t, h, "/api/v1/agent/report", "test-token", report)
	if rr.Code != http.StatusOK {
		t.Fatalf("report failed: %d %s", rr.Code, rr.Body.String())
	}
	req := httptest.NewRequest(http.MethodGet, "/api/v1/nodes", nil)
	out := httptest.NewRecorder()
	h.ServeHTTP(out, req)
	if out.Code != http.StatusOK || !strings.Contains(out.Body.String(), "node-a") {
		t.Fatalf("nodes output unexpected: %d %s", out.Code, out.Body.String())
	}
}

func TestRedactCleansSecrets(t *testing.T) {
	raw := []byte(`{"token":"abc","secret":"s","password":"p","privateKey":"k","custom_url":"https://example.com?token=abc","custom_cmd":"cmd --token abc","nested":{"Authorization":"Bearer abc"}}`)
	redacted := string(RedactJSONBytes(raw))
	for _, leak := range []string{"abc", "Bearer abc", "--token abc", "https://example.com?token=abc"} {
		if strings.Contains(redacted, leak) {
			t.Fatalf("redaction leaked %q in %s", leak, redacted)
		}
	}
	if !strings.Contains(redacted, "REDACTED") {
		t.Fatalf("expected REDACTED in %s", redacted)
	}
}
