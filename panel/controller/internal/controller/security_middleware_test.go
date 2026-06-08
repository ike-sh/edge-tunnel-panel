package controller

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestLoginRateLimit(t *testing.T) {
	t.Setenv("EDGE_FORCE_HTTPS", "")
	h := testServer(t)
	for i := 0; i < 21; i++ {
		rr := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodPost, "/api/v1/login", bytes.NewBufferString(`{"token":"wrong"}`))
		req.RemoteAddr = "203.0.113.10:1234"
		h.ServeHTTP(rr, req)
		if i < 20 && rr.Code == http.StatusTooManyRequests {
			t.Fatalf("unexpected 429 on attempt %d", i+1)
		}
		if i == 20 && rr.Code != http.StatusTooManyRequests {
			t.Fatalf("expected 429 on attempt 21, got %d", rr.Code)
		}
	}
}

func TestForceHTTPS(t *testing.T) {
	t.Setenv("EDGE_FORCE_HTTPS", "1")
	h := testServer(t)
	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/api/v1/health", nil)
	h.ServeHTTP(rr, req)
	if rr.Code != http.StatusBadRequest {
		t.Fatalf("expected HTTPS required, got %d", rr.Code)
	}
	rr = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodGet, "/api/v1/health", nil)
	req.Header.Set("X-Forwarded-Proto", "https")
	h.ServeHTTP(rr, req)
	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200 with forwarded https, got %d", rr.Code)
	}
}

func TestCORSHeaders(t *testing.T) {
	t.Setenv("EDGE_CORS_ORIGINS", "https://panel.example.com")
	t.Setenv("EDGE_FORCE_HTTPS", "")
	h := testServer(t)
	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/api/v1/health", nil)
	req.Header.Set("Origin", "https://panel.example.com")
	h.ServeHTTP(rr, req)
	if rr.Header().Get("Access-Control-Allow-Origin") != "https://panel.example.com" {
		t.Fatalf("missing CORS header: %v", rr.Header())
	}
}
