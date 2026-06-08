package controller

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/gorilla/websocket"
)

var machineStreamUpgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

func operatorTokenFromRequest(s *Server, r *http.Request) string {
	if tok := bearerToken(r); tok != "" {
		return tok
	}
	return r.URL.Query().Get("token")
}

func (s *Server) handleV2MachineStream(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeErr(w, 405, "method_not_allowed", "method not allowed")
		return
	}
	if s.strictAuth {
		tok := operatorTokenFromRequest(s, r)
		if !tokenMatches(tok, s.operatorToken) {
			writeErr(w, 401, "UNAUTHORIZED", "operator token required")
			return
		}
	}
	conn, err := machineStreamUpgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}
	defer conn.Close()

	_ = conn.SetReadDeadline(time.Now().Add(6 * time.Minute))
	conn.SetPongHandler(func(string) error {
		_ = conn.SetReadDeadline(time.Now().Add(6 * time.Minute))
		return nil
	})

	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()

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
		case <-ticker.C:
			if err := sendSnapshot(); err != nil {
				return
			}
		}
	}
}
