package agent

import (
	"bufio"
	"bytes"
	"os"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"time"
)

type SystemMetrics struct {
	CPUPercent      float64 `json:"cpu_percent,omitempty"`
	MemPercent      float64 `json:"mem_percent,omitempty"`
	MemTotalMB      uint64  `json:"mem_total_mb,omitempty"`
	MemUsedMB       uint64  `json:"mem_used_mb,omitempty"`
	UptimeSec       uint64  `json:"uptime_sec,omitempty"`
	BytesSent       uint64  `json:"bytes_sent,omitempty"`
	BytesReceived   uint64  `json:"bytes_received,omitempty"`
	NetTxBPS        uint64  `json:"net_tx_bps,omitempty"`
	NetRxBPS        uint64  `json:"net_rx_bps,omitempty"`
}

var (
	cpuMu         sync.Mutex
	lastCPUSample cpuTimes
	netMu         sync.Mutex
	lastNetSample netCounters
)

type netCounters struct {
	sent uint64
	recv uint64
	at   time.Time
}

type cpuTimes struct {
	total uint64
	idle  uint64
	at    time.Time
}

func CollectSystemMetrics() SystemMetrics {
	switch runtime.GOOS {
	case "linux":
		return collectLinuxMetrics()
	default:
		return SystemMetrics{}
	}
}

func collectLinuxMetrics() SystemMetrics {
	m := SystemMetrics{}
	if total, used, ok := linuxMemory(); ok {
		m.MemTotalMB = total / 1024
		m.MemUsedMB = used / 1024
		if total > 0 {
			m.MemPercent = float64(used) / float64(total) * 100
		}
	}
	if uptime, ok := linuxUptime(); ok {
		m.UptimeSec = uptime
	}
	if cpu, ok := linuxCPUPercent(); ok {
		m.CPUPercent = cpu
	}
	if sent, recv, txBps, rxBps, ok := linuxNetworkIO(); ok {
		m.BytesSent = sent
		m.BytesReceived = recv
		m.NetTxBPS = txBps
		m.NetRxBPS = rxBps
	}
	return m
}

func linuxMemory() (totalKB, usedKB uint64, ok bool) {
	data, err := os.ReadFile("/proc/meminfo")
	if err != nil {
		return 0, 0, false
	}
	return parseMeminfo(data)
}

func parseMeminfo(data []byte) (totalKB, usedKB uint64, ok bool) {
	var total, available, free, cached, buffers uint64
	scanner := bufio.NewScanner(bytes.NewReader(data))
	for scanner.Scan() {
		line := scanner.Text()
		fields := strings.Fields(line)
		if len(fields) < 2 {
			continue
		}
		value, err := strconv.ParseUint(fields[1], 10, 64)
		if err != nil {
			continue
		}
		switch fields[0] {
		case "MemTotal:":
			total = value
		case "MemAvailable:":
			available = value
		case "MemFree:":
			free = value
		case "Cached:":
			cached = value
		case "Buffers:":
			buffers = value
		}
	}
	if total == 0 {
		return 0, 0, false
	}
	if available == 0 {
		available = free + cached + buffers
	}
	if available > total {
		available = free
	}
	used := total - available
	return total, used, true
}

func linuxUptime() (uint64, bool) {
	data, err := os.ReadFile("/proc/uptime")
	if err != nil {
		return 0, false
	}
	fields := strings.Fields(string(data))
	if len(fields) == 0 {
		return 0, false
	}
	seconds, err := strconv.ParseFloat(fields[0], 64)
	if err != nil || seconds < 0 {
		return 0, false
	}
	return uint64(seconds), true
}

func linuxCPUPercent() (float64, bool) {
	sample, ok := readProcStat()
	if !ok {
		return 0, false
	}
	cpuMu.Lock()
	defer cpuMu.Unlock()
	if lastCPUSample.total == 0 || time.Since(lastCPUSample.at) < 200*time.Millisecond {
		lastCPUSample = sample
		return 0, true
	}
	deltaTotal := sample.total - lastCPUSample.total
	deltaIdle := sample.idle - lastCPUSample.idle
	lastCPUSample = sample
	if deltaTotal == 0 {
		return 0, true
	}
	busy := float64(deltaTotal-deltaIdle) / float64(deltaTotal) * 100
	if busy < 0 {
		busy = 0
	}
	if busy > 100 {
		busy = 100
	}
	return busy, true
}

func readProcStat() (cpuTimes, bool) {
	data, err := os.ReadFile("/proc/stat")
	if err != nil {
		return cpuTimes{}, false
	}
	scanner := bufio.NewScanner(bytes.NewReader(data))
	for scanner.Scan() {
		line := scanner.Text()
		if !strings.HasPrefix(line, "cpu ") {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) < 5 {
			return cpuTimes{}, false
		}
		var nums []uint64
		for _, field := range fields[1:] {
			value, err := strconv.ParseUint(field, 10, 64)
			if err != nil {
				return cpuTimes{}, false
			}
			nums = append(nums, value)
		}
		var total uint64
		for _, n := range nums {
			total += n
		}
		idle := nums[3]
		if len(nums) > 4 {
			idle += nums[4]
		}
		return cpuTimes{total: total, idle: idle, at: time.Now()}, true
	}
	return cpuTimes{}, false
}

func linuxNetworkIO() (sent, recv, txBps, rxBps uint64, ok bool) {
	data, err := os.ReadFile("/proc/net/dev")
	if err != nil {
		return 0, 0, 0, 0, false
	}
	sent, recv, ok = parseNetDev(data)
	if !ok {
		return 0, 0, 0, 0, false
	}
	now := time.Now()
	netMu.Lock()
	defer netMu.Unlock()
	if !lastNetSample.at.IsZero() {
		secs := now.Sub(lastNetSample.at).Seconds()
		if secs > 0 {
			if sent >= lastNetSample.sent {
				txBps = uint64(float64(sent-lastNetSample.sent) / secs)
			}
			if recv >= lastNetSample.recv {
				rxBps = uint64(float64(recv-lastNetSample.recv) / secs)
			}
		}
	}
	lastNetSample = netCounters{sent: sent, recv: recv, at: now}
	return sent, recv, txBps, rxBps, true
}

func parseNetDev(data []byte) (sent, recv uint64, ok bool) {
	scanner := bufio.NewScanner(bytes.NewReader(data))
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "Inter-|") || strings.HasPrefix(line, " face |") {
			continue
		}
		parts := strings.Fields(strings.ReplaceAll(line, ":", " "))
		if len(parts) < 10 {
			continue
		}
		iface := parts[0]
		if iface == "lo" {
			continue
		}
		rx, err1 := strconv.ParseUint(parts[1], 10, 64)
		tx, err2 := strconv.ParseUint(parts[9], 10, 64)
		if err1 != nil || err2 != nil {
			continue
		}
		recv += rx
		sent += tx
	}
	return sent, recv, recv > 0 || sent > 0
}
