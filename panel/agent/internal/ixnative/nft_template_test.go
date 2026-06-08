package ixnative

import (
	"strings"
	"testing"
)

func TestWriteProfileEnv(t *testing.T) {
	dir := t.TempDir()
	old := getenv
	defer func() { getenv = old }()
	getenv = func(key string) string {
		if key == "IXTF_PROFILES_DIR" {
			return dir
		}
		return ""
	}
	path, err := WriteProfileEnv(ProfileConfig{
		ProfileID:     "p1",
		Name:          "line-1",
		NATPublicHost: "nat.test",
		LandingHost:   "land.test",
	})
	if err != nil {
		t.Fatal(err)
	}
	if path == "" {
		t.Fatal("expected path")
	}
}

func TestRenderForwardNFT(t *testing.T) {
	out, err := RenderForwardNFT("ix_test", []NFTForwardRule{{
		Name: "main", ListenPort: 40000, TargetHost: "10.0.0.2", TargetPort: 50000, Protocol: "tcp",
	}})
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out, "main tcp dport 40000 dnat to 10.0.0.2:50000") {
		t.Fatalf("unexpected nft output:\n%s", out)
	}
}
