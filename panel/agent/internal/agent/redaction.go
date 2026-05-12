package agent

import (
	"regexp"
	"strings"
)

const defaultTaskResultLimitKB = 64

var redactionPatterns = []*regexp.Regexp{
	regexp.MustCompile(`(?i)(Authorization:\s*Bearer\s+)[^\s"']+`),
	regexp.MustCompile(`(?i)(token=)[^\s"']+`),
	regexp.MustCompile(`(?i)("token"\s*:\s*")[^"]+(")`),
	regexp.MustCompile(`(?i)(EDGE_CONTROLLER_TOKEN=)[^\s"']+`),
}

func RedactString(s string, secrets ...string) string {
	out := s
	for _, secret := range secrets {
		if secret != "" {
			out = strings.ReplaceAll(out, secret, "[REDACTED]")
		}
	}
	for _, pattern := range redactionPatterns {
		out = pattern.ReplaceAllString(out, `${1}[REDACTED]${2}`)
	}
	return out
}

func RedactMap(in map[string]any, secrets ...string) map[string]any {
	out := make(map[string]any, len(in))
	for key, value := range in {
		switch typed := value.(type) {
		case string:
			out[key] = RedactString(typed, secrets...)
		case map[string]any:
			out[key] = RedactMap(typed, secrets...)
		default:
			out[key] = value
		}
	}
	return out
}

func LimitString(s string, maxBytes int) string {
	if maxBytes <= 0 || len(s) <= maxBytes {
		return s
	}
	return s[:maxBytes] + "\n[TRUNCATED]"
}

func LimitTaskResult(result TaskResult, limitKB int, secrets ...string) TaskResult {
	if limitKB <= 0 {
		limitKB = defaultTaskResultLimitKB
	}
	limit := limitKB * 1024
	result.Result = LimitString(RedactString(result.Result, secrets...), limit)
	result.Stdout = LimitString(RedactString(result.Stdout, secrets...), limit)
	result.Stderr = LimitString(RedactString(result.Stderr, secrets...), limit)
	result.Error = LimitString(RedactString(result.Error, secrets...), limit)
	return result
}
