package controller

import (
	"net/http"
	"strings"
)

func (s *Store) machineIDForToken(token string) string {
	if strings.TrimSpace(token) == "" {
		return ""
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, m := range s.data.IXMachines {
		if m.Token != "" && tokenMatches(token, m.Token) {
			return m.ID
		}
	}
	return ""
}

// resolveMachineBinding validates machine_id against the bearer token scope.
// Machine tokens may only bind their own machine. Global agent tokens cannot bind machine_id.
func (s *Server) resolveMachineBinding(w http.ResponseWriter, r *http.Request, requested string) (string, bool) {
	requested = strings.TrimSpace(requested)
	tok := bearerToken(r)
	if bound := s.store.machineIDForToken(tok); bound != "" {
		if requested != "" && requested != bound {
			writeErr(w, http.StatusForbidden, "FORBIDDEN", "machine_id does not match token")
			return "", false
		}
		return bound, true
	}
	if requested != "" && tokenMatches(tok, s.agentToken) {
		writeErr(w, http.StatusForbidden, "FORBIDDEN", "machine token required to bind machine_id")
		return "", false
	}
	return requested, true
}
