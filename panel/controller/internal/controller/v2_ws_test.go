package controller

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gorilla/websocket"
)

func wsURL(httpURL, path string) string {
	return "ws" + strings.TrimPrefix(httpURL, "http") + path
}

func TestMachineStreamRejectsQueryToken(t *testing.T) {
	srv := httptest.NewServer(testServer(t))
	defer srv.Close()
	_, resp, err := websocket.DefaultDialer.Dial(wsURL(srv.URL, "/api/v2/stream/machines?token=operator-token"), nil)
	if err == nil {
		t.Fatal("expected dial failure for query token")
	}
	if resp == nil || resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("expected 400, got err=%v resp=%v", err, resp)
	}
}

func TestMachineStreamRequiresAuthFrame(t *testing.T) {
	srv := httptest.NewServer(testServer(t))
	defer srv.Close()
	conn, _, err := websocket.DefaultDialer.Dial(wsURL(srv.URL, "/api/v2/stream/machines"), nil)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	if err := conn.WriteJSON(map[string]string{"type": "auth", "token": "wrong"}); err != nil {
		t.Fatal(err)
	}
	var msg map[string]any
	if err := conn.ReadJSON(&msg); err != nil {
		t.Fatal(err)
	}
	if msg["type"] != "auth_error" {
		t.Fatalf("expected auth_error, got %+v", msg)
	}
}

func TestMachineStreamAuthFrameOK(t *testing.T) {
	srv := httptest.NewServer(testServer(t))
	defer srv.Close()
	conn, _, err := websocket.DefaultDialer.Dial(wsURL(srv.URL, "/api/v2/stream/machines"), nil)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	if err := conn.WriteJSON(map[string]string{"type": "auth", "token": "operator-token"}); err != nil {
		t.Fatal(err)
	}
	var msg map[string]any
	if err := conn.ReadJSON(&msg); err != nil {
		t.Fatal(err)
	}
	if msg["type"] != "auth_ok" {
		t.Fatalf("expected auth_ok, got %+v", msg)
	}
	if err := conn.ReadJSON(&msg); err != nil {
		t.Fatal(err)
	}
	if msg["type"] != "snapshot" {
		t.Fatalf("expected snapshot, got %+v", msg)
	}
}

func TestMachineStreamOpenModeNoAuthFrame(t *testing.T) {
	srv := httptest.NewServer(testOpenServer(t))
	defer srv.Close()
	conn, _, err := websocket.DefaultDialer.Dial(wsURL(srv.URL, "/api/v2/stream/machines"), nil)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	var msg map[string]any
	if err := conn.ReadJSON(&msg); err != nil {
		t.Fatal(err)
	}
	if msg["type"] != "snapshot" {
		t.Fatalf("expected snapshot in open mode, got %+v", msg)
	}
}
