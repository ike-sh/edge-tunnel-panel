package ixnative

import "testing"

func TestRenderEasyTierToml(t *testing.T) {
	out, err := RenderEasyTierToml(EasyTierConfig{
		ProfileID:   "p1",
		NetworkName: "ix-net-a",
		CIDR:        "10.144.0.0/16",
		Port:        11010,
	})
	if err != nil {
		t.Fatal(err)
	}
	if !containsSubstring(out, `network_name = "ix-net-a"`) {
		t.Fatalf("unexpected toml:\n%s", out)
	}
}

func TestEasyTierUnitName(t *testing.T) {
	if EasyTierUnitName("nat-1") != "edge-tunnel-easytier@nat-1.service" {
		t.Fatal("unexpected unit name")
	}
}

func containsSubstring(s, sub string) bool {
	return len(s) >= len(sub) && (s == sub || indexOf(s, sub) >= 0)
}

func indexOf(s, sub string) int {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return i
		}
	}
	return -1
}
