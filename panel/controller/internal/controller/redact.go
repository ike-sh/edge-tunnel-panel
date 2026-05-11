package controller

import (
	"encoding/json"
	"regexp"
	"strings"
)

var (
	bearerRe       = regexp.MustCompile(`(?i)Bearer\s+[A-Za-z0-9._~+/=-]+`)
	querySecretRe  = regexp.MustCompile(`(?i)(token|secret|password|key)=([^&\s]+)`)
	assignSecretRe = regexp.MustCompile(`(?i)(token|secret|password|private_key|privateKey|network_secret|custom_url|custom_cmd)\s*[:=]\s*[^,\s]+`)
)

func sensitiveKey(key string) bool {
	switch strings.ToLower(key) {
	case "token", "secret", "password", "private_key", "privatekey", "network_secret", "custom_url", "custom_cmd", "authorization":
		return true
	default:
		return false
	}
}

func RedactString(s string) string {
	s = bearerRe.ReplaceAllString(s, "Bearer REDACTED")
	s = querySecretRe.ReplaceAllString(s, "$1=REDACTED")
	s = assignSecretRe.ReplaceAllStringFunc(s, func(match string) string {
		if idx := strings.IndexAny(match, ":="); idx >= 0 {
			return strings.TrimSpace(match[:idx]) + string(match[idx]) + "REDACTED"
		}
		return "REDACTED"
	})
	return s
}

func RedactValue(v any) any {
	switch x := v.(type) {
	case map[string]any:
		out := make(map[string]any, len(x))
		for k, val := range x {
			if sensitiveKey(k) {
				out[k] = "REDACTED"
				continue
			}
			out[k] = RedactValue(val)
		}
		return out
	case []any:
		out := make([]any, 0, len(x))
		for _, val := range x {
			out = append(out, RedactValue(val))
		}
		return out
	case string:
		return RedactString(x)
	default:
		return v
	}
}

func RedactJSONBytes(raw []byte) []byte {
	var v any
	if err := json.Unmarshal(raw, &v); err != nil {
		return []byte(RedactString(string(raw)))
	}
	out, err := json.Marshal(RedactValue(v))
	if err != nil {
		return []byte(RedactString(string(raw)))
	}
	return out
}

func RedactForLog(v any) string {
	raw, err := json.Marshal(v)
	if err != nil {
		return RedactString(err.Error())
	}
	return string(RedactJSONBytes(raw))
}
