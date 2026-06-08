package controller

import (
	"net"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
)

func applySecurityHeaders(w http.ResponseWriter) {
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("X-Frame-Options", "DENY")
	w.Header().Set("Referrer-Policy", "no-referrer")
	w.Header().Set("Permissions-Policy", "geolocation=(), microphone=(), camera=()")
}

func corsOrigins() []string {
	raw := strings.TrimSpace(os.Getenv("EDGE_CORS_ORIGINS"))
	if raw == "" {
		return nil
	}
	out := []string{}
	for _, part := range strings.Split(raw, ",") {
		part = strings.TrimSpace(part)
		if part != "" {
			out = append(out, part)
		}
	}
	return out
}

func applyCORS(w http.ResponseWriter, r *http.Request) {
	origins := corsOrigins()
	if len(origins) == 0 {
		return
	}
	origin := strings.TrimSpace(r.Header.Get("Origin"))
	if origin == "" {
		return
	}
	allowed := false
	for _, o := range origins {
		if o == "*" || strings.EqualFold(o, origin) {
			allowed = true
			break
		}
	}
	if !allowed {
		return
	}
	w.Header().Set("Access-Control-Allow-Origin", origin)
	w.Header().Set("Vary", "Origin")
	w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
	w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
}

func requestIsHTTPS(r *http.Request) bool {
	if r.TLS != nil {
		return true
	}
	if strings.EqualFold(r.Header.Get("X-Forwarded-Proto"), "https") {
		return true
	}
	return false
}

type ipRateLimiter struct {
	mu      sync.Mutex
	window  time.Duration
	limit   int
	buckets map[string][]time.Time
}

func newIPRateLimiter(limit int, window time.Duration) *ipRateLimiter {
	return &ipRateLimiter{limit: limit, window: window, buckets: map[string][]time.Time{}}
}

func (l *ipRateLimiter) allow(key string) bool {
	now := time.Now()
	l.mu.Lock()
	defer l.mu.Unlock()
	cutoff := now.Add(-l.window)
	events := l.buckets[key]
	kept := events[:0]
	for _, ts := range events {
		if ts.After(cutoff) {
			kept = append(kept, ts)
		}
	}
	if len(kept) >= l.limit {
		l.buckets[key] = kept
		return false
	}
	l.buckets[key] = append(kept, now)
	return true
}

func clientIP(r *http.Request) string {
	if xff := strings.TrimSpace(r.Header.Get("X-Forwarded-For")); xff != "" {
		parts := strings.Split(xff, ",")
		return strings.TrimSpace(parts[0])
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

var loginRateLimiter = newIPRateLimiter(20, time.Minute)

func (s *Server) apiMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		applySecurityHeaders(w)
		applyCORS(w, r)
		if r.Method == http.MethodOptions && len(corsOrigins()) > 0 {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		if os.Getenv("EDGE_FORCE_HTTPS") == "1" && !requestIsHTTPS(r) {
			writeErr(w, http.StatusBadRequest, "HTTPS_REQUIRED", "HTTPS is required; terminate TLS at reverse proxy and set X-Forwarded-Proto")
			return
		}
		if s.strictAuth && r.Method == http.MethodPost && r.URL.Path == "/api/v1/login" {
			if !loginRateLimiter.allow(clientIP(r)) {
				writeErr(w, http.StatusTooManyRequests, "RATE_LIMITED", "too many login attempts")
				return
			}
		}
		next.ServeHTTP(w, r)
	})
}
