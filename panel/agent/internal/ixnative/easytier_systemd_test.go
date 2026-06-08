package ixnative

import (
	"strings"
	"testing"
)

func TestWriteEasyTierConfigAndSystemdUnit(t *testing.T) {
	dir := t.TempDir()
	sysDir := t.TempDir()
	old := getenv
	defer func() { getenv = old }()
	getenv = func(key string) string {
		switch key {
		case "IXTF_EASYTIER_DIR":
			return dir
		case "IXTF_SYSTEMD_DIR":
			return sysDir
		default:
			return ""
		}
	}
	cfg := EasyTierConfig{ProfileID: "p1", NetworkName: "ix-net", Port: 11010}
	path, err := WriteEasyTierConfig(cfg)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasSuffix(path, "p1.toml") {
		t.Fatalf("unexpected path %s", path)
	}
	unitPath, err := WriteSystemdUnit("p1", path, "easytier-core")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(unitPath, "edge-tunnel-easytier@p1.service") {
		t.Fatalf("unexpected unit %s", unitPath)
	}
}
