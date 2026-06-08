package ixnative

import (
	"strings"
	"testing"
)

func TestRenderProfileEnv(t *testing.T) {
	out, err := RenderProfileEnv(ProfileConfig{
		ProfileID:     "nat-ix-listener-1",
		Name:          "前海IX-A",
		NATPublicHost: "nat.example.com",
		NATPublicPort: 20000,
		LandingHost:   "landing.example.com",
		LandingPort:   50000,
		TransitPort:   40000,
		NetworkName:   "ix-net-a",
		CIDR:          "10.144.0.0/16",
	})
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{
		"PROFILE_ID=nat-ix-listener-1",
		"NAT_PUBLIC_HOST=nat.example.com",
		"NAT_PUBLIC_PORT=20000",
		"LANDING_HOST=landing.example.com",
	} {
		if !strings.Contains(out, want) {
			t.Fatalf("missing %q in:\n%s", want, out)
		}
	}
}

func TestNativeEnabled(t *testing.T) {
	old := getenv
	defer func() { getenv = old }()
	getenv = func(key string) string {
		if key == "EDGE_IX_NATIVE" {
			return "true"
		}
		return ""
	}
	if !NativeEnabled() {
		t.Fatal("expected native enabled")
	}
}
