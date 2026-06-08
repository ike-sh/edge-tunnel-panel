package agent

import "testing"

func TestParseMeminfo(t *testing.T) {
	total, used, ok := parseMeminfo([]byte(`MemTotal:       16384000 kB
MemAvailable:    8192000 kB
MemFree:         4096000 kB
`))
	if !ok {
		t.Fatal("expected ok")
	}
	if total != 16384000 || used != 8192000 {
		t.Fatalf("total=%d used=%d", total, used)
	}
}

func TestParseNetDev(t *testing.T) {
	sent, recv, ok := parseNetDev([]byte(`Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
    lo: 1000       10    0    0    0     0          0         0     1000       10    0    0    0     0       0          0
  eth0: 5000       20    0    0    0     0          0         0     8000       30    0    0    0     0       0          0
`))
	if !ok {
		t.Fatal("expected ok")
	}
	if recv != 5000 || sent != 8000 {
		t.Fatalf("recv=%d sent=%d", recv, sent)
	}
}
