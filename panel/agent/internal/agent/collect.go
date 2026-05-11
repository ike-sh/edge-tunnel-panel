package agent

import (
	"context"
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"time"
)

type Collector struct {
	LQPath         string
	PublicIPFunc   func(context.Context) (string, error)
	CommandTimeout time.Duration
}

func DefaultCollector() Collector {
	return Collector{PublicIPFunc: fetchPublicIP, CommandTimeout: 5 * time.Second}
}

func (c Collector) Collect(ctx context.Context, cfg Config) ReportRequest {
	if c.CommandTimeout <= 0 {
		c.CommandTimeout = 5 * time.Second
	}
	if c.PublicIPFunc == nil {
		c.PublicIPFunc = fetchPublicIP
	}
	hostname, _ := os.Hostname()
	report := ReportRequest{
		NodeID: cfg.NodeID, NodeName: cfg.NodeName, Role: normalizeRole(cfg.Role), Hostname: hostname,
		AgentVersion: Version, CoreVersion: "missing", Status: "online", HealthScore: 100,
		Services: map[string]string{},
	}
	if ip, err := c.PublicIPFunc(ctx); err == nil {
		report.PublicIP = ip
	} else {
		report.PublicIP = "unknown"
		report.Errors = append(report.Errors, "public_ip: "+err.Error())
	}
	if lan := primaryLANIP(); lan != "" {
		report.PrimaryLANIP = lan
	}

	lqPath, err := c.findLQ()
	if err != nil {
		report.Status = "degraded"
		report.HealthScore = 50
		report.Errors = append(report.Errors, "lq missing")
	} else {
		if out, err := c.runCommand(ctx, lqPath, "--version"); err == nil {
			report.CoreVersion = parseCoreVersion(out)
		} else {
			report.Status = "degraded"
			report.Errors = append(report.Errors, "lq --version: "+err.Error())
		}
		if out, err := c.runCommand(ctx, lqPath, "status", "--json"); err == nil {
			report.LQStatus = json.RawMessage(RedactJSONBytes([]byte(out)))
			applyStatusJSON(&report, []byte(out))
		} else {
			report.Status = "degraded"
			report.Errors = append(report.Errors, "lq status --json: "+err.Error())
		}
		if out, err := c.runCommand(ctx, lqPath, "doctor", "--json"); err == nil {
			report.LQDoctor = json.RawMessage(RedactJSONBytes([]byte(out)))
		} else {
			report.Status = "degraded"
			report.Errors = append(report.Errors, "lq doctor --json: "+err.Error())
		}
	}

	report.Services["nftables"] = c.systemctlActive(ctx, "nftables")
	report.Services["easytier"] = c.systemctlActive(ctx, "easytier-relay.service")
	if report.Services["easytier"] == "unknown" || strings.Contains(report.Services["easytier"], "failed") {
		report.Services["easytier_entry"] = c.systemctlActive(ctx, "easytier-entry.service")
	}
	if report.Status == "degraded" && report.HealthScore > 80 {
		report.HealthScore = 80
	}
	return report
}

func (c Collector) findLQ() (string, error) {
	if c.LQPath != "" {
		if _, err := os.Stat(c.LQPath); err != nil {
			return "", err
		}
		return c.LQPath, nil
	}
	if p, err := exec.LookPath("lq"); err == nil {
		return p, nil
	}
	return "", errors.New("lq not found")
}

func (c Collector) runCommand(ctx context.Context, name string, args ...string) (string, error) {
	cmdCtx, cancel := context.WithTimeout(ctx, c.CommandTimeout)
	defer cancel()
	cmd := exec.CommandContext(cmdCtx, name, args...)
	out, err := cmd.CombinedOutput()
	return string(out), err
}

func (c Collector) systemctlActive(ctx context.Context, service string) string {
	if _, err := exec.LookPath("systemctl"); err != nil {
		return "unknown"
	}
	out, err := c.runCommand(ctx, "systemctl", "is-active", service)
	if err != nil {
		text := strings.TrimSpace(out)
		if text == "" {
			return "unknown"
		}
		return RedactString(text)
	}
	return strings.TrimSpace(out)
}

func fetchPublicIP(ctx context.Context) (string, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, "https://api.ipify.org", nil)
	if err != nil {
		return "", err
	}
	client := &http.Client{Timeout: 4 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	buf := make([]byte, 64)
	n, _ := resp.Body.Read(buf)
	ip := strings.TrimSpace(string(buf[:n]))
	if net.ParseIP(ip) == nil {
		return "", errors.New("invalid public ip response")
	}
	return ip, nil
}

func primaryLANIP() string {
	conn, err := net.Dial("udp", "8.8.8.8:80")
	if err == nil {
		defer conn.Close()
		if addr, ok := conn.LocalAddr().(*net.UDPAddr); ok {
			return addr.IP.String()
		}
	}
	addrs, err := net.InterfaceAddrs()
	if err != nil {
		return ""
	}
	for _, addr := range addrs {
		ipNet, ok := addr.(*net.IPNet)
		if !ok || ipNet.IP.IsLoopback() {
			continue
		}
		if ip := ipNet.IP.To4(); ip != nil {
			return ip.String()
		}
	}
	return ""
}

func parseCoreVersion(out string) string {
	out = strings.TrimSpace(out)
	if out == "" {
		return "unknown"
	}
	out = strings.TrimPrefix(out, "leikwan-toolkit ")
	return out
}

func applyStatusJSON(report *ReportRequest, raw []byte) {
	var data map[string]any
	if err := json.Unmarshal(raw, &data); err != nil {
		return
	}
	if v, ok := data["role"].(string); ok && report.Role == "unknown" {
		report.Role = normalizeRole(v)
	}
	if v, ok := data["easytier_ip"].(string); ok {
		report.EasyTierIP = v
	}
	if v, ok := data["health_score"].(float64); ok {
		report.HealthScore = int(v)
	}
	if v, ok := data["overall"].(string); ok {
		switch strings.ToLower(v) {
		case "ok", "online":
			report.Status = "online"
		default:
			report.Status = "degraded"
		}
	}
}
