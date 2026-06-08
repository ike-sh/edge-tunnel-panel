package controller

import (
	"encoding/json"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/gorilla/websocket"
)

var machineStreamUpgrader = websocket.Upgrader{
	CheckOrigin: wsCheckOrigin,
}

func wsCheckOrigin(r *http.Request) bool {
	origin := strings.TrimSpace(r.Header.Get("Origin"))
	if origin == "" {
		return true
	}
	u, err := url.Parse(origin)
	if err != nil {
		return false
	}
	return strings.EqualFold(u.Host, r.Host)
}

func (s *Server) authenticateMachineStream(conn *websocket.Conn) bool {
	_ = conn.SetReadDeadline(time.Now().Add(15 * time.Second))
	defer conn.SetReadDeadline(time.Time{})
	_, raw, err := conn.ReadMessage()
	if err != nil {
		return false
	}
	var msg struct {
		Type  string `json:"type"`
		Token string `json:"token"`
	}
	if err := json.Unmarshal(raw, &msg); err != nil || msg.Type != "auth" {
		_ = conn.WriteJSON(map[string]any{"type": "auth_error", "message": "auth message required"})
		return false
	}
	if !tokenMatches(strings.TrimSpace(msg.Token), s.operatorToken) {
		_ = conn.WriteJSON(map[string]any{"type": "auth_error", "message": "invalid operator token"})
		return false
	}
	_ = conn.WriteJSON(map[string]any{"type": "auth_ok"})
	return true
}

func (s *Server) handleV2MachineStream(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeErr(w, 405, "method_not_allowed", "method not allowed")
		return
	}
	if r.URL.Query().Get("token") != "" {
		writeErr(w, 400, "bad_request", "query token is disabled; send auth frame after connect")
		return
	}
	conn, err := machineStreamUpgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}
	defer conn.Close()

	if s.strictAuth && !s.authenticateMachineStream(conn) {
		return
	}

	deadline := time.Now().Add(6 * time.Minute)
	_ = conn.SetReadDeadline(deadline)
	conn.SetPongHandler(func(string) error {
		_ = conn.SetReadDeadline(time.Now().Add(6 * time.Minute))
		return nil
	})

	ticker := time.NewTicker(2 * time.Second)
	pingTicker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()
	defer pingTicker.Stop()

	sendSnapshot := func() error {
		payload, _ := json.Marshal(map[string]any{
			"type":     "snapshot",
			"machines": s.store.listIXMachines(),
			"nodes":    s.store.listNodes(),
		})
		return conn.WriteMessage(websocket.TextMessage, payload)
	}

	if err := sendSnapshot(); err != nil {
		return
	}

	for {
		select {
		case <-r.Context().Done():
			return
		case <-pingTicker.C:
			if err := conn.WriteControl(websocket.PingMessage, []byte("ping"), time.Now().Add(5*time.Second)); err != nil {
				return
			}
		case <-ticker.C:
			if err := sendSnapshot(); err != nil {
				return
			}
		}
	}
}
