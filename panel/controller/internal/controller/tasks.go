package controller

import "time"

func redactToken(value string) string {
	if value == "" {
		return ""
	}
	if len(value) <= 4 {
		return "****"
	}
	return "********" + value[len(value)-4:]
}

func capText(text string) string {
	const limit = 64 * 1024
	if len(text) <= limit {
		return text
	}
	return text[:limit] + "\n[TRUNCATED]"
}

func defaultTaskExpiry() *time.Time {
	t := now().Add(10 * time.Minute)
	return &t
}
