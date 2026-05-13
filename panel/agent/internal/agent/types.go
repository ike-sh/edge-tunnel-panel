package agent

import (
	"encoding/json"
	"time"
)

const Version = "v0.2.9-test"

type APIResponse struct {
	OK    bool            `json:"ok"`
	Data  json.RawMessage `json:"data,omitempty"`
	Error *APIError       `json:"error,omitempty"`
}

type APIError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

type Config struct {
	ControllerURL      string
	ControllerToken    string
	NodeID             string
	NodeName           string
	NodeRole           string
	EnableTasks        bool
	EnableWriteActions bool
	ConfigDir          string
	StateDir           string
	PollInterval       time.Duration
	ReportInterval     time.Duration
	TaskResultLimitKB  int
	MaxConcurrentTasks int
}

type RegisterRequest struct {
	ID       string `json:"id,omitempty"`
	Name     string `json:"name"`
	Role     string `json:"role"`
	Hostname string `json:"hostname"`
}

type ReportRequest struct {
	ID                    string          `json:"id,omitempty"`
	Name                  string          `json:"name"`
	Role                  string          `json:"role"`
	PublicIP              string          `json:"public_ip,omitempty"`
	PrivateIP             string          `json:"private_ip,omitempty"`
	AgentVersion          string          `json:"agent_version"`
	Hostname              string          `json:"hostname"`
	OS                    string          `json:"os"`
	Arch                  string          `json:"arch"`
	EasyTierIP            string          `json:"easytier_ip,omitempty"`
	EasyTierStatus        string          `json:"easytier_status"`
	EasyTierPeerCount     int             `json:"easytier_peer_count"`
	EasyTierHasRemotePeer bool            `json:"easytier_has_remote_peer"`
	EasyTierBestLatencyMS float64         `json:"easytier_best_latency_ms,omitempty"`
	EasyTierPacketLoss    string          `json:"easytier_packet_loss,omitempty"`
	EasyTierTunnels       []string        `json:"easytier_tunnels,omitempty"`
	EasyTierRouteType     string          `json:"easytier_route_type,omitempty"`
	EasyTierNetworkOK     bool            `json:"easytier_network_ok"`
	EasyTierNetworkReason string          `json:"easytier_network_reason,omitempty"`
	EasyTierDHCPEnabled   bool            `json:"easytier_dhcp_enabled"`
	EasyTierCIDR          string          `json:"easytier_cidr,omitempty"`
	Capabilities          map[string]bool `json:"capabilities"`
	Warnings              []string        `json:"warnings,omitempty"`
}

type AgentStatus struct {
	Hostname              string          `json:"hostname"`
	OS                    string          `json:"os"`
	Arch                  string          `json:"arch"`
	NodeRole              string          `json:"node_role"`
	ConfigDir             string          `json:"config_dir"`
	StateDir              string          `json:"state_dir"`
	EasyTierBinaryExists  bool            `json:"easytier_binary_exists"`
	EasyTierServiceActive bool            `json:"easytier_service_active"`
	AgentServiceActive    bool            `json:"agent_service_active"`
	NFTAvailable          bool            `json:"nft_available"`
	IPRouteAvailable      bool            `json:"iproute_available"`
	Capabilities          map[string]bool `json:"capabilities"`
	Warnings              []string        `json:"warnings,omitempty"`
	PrivateIP             string          `json:"private_ip,omitempty"`
	EasyTierIP            string          `json:"easytier_ip,omitempty"`
	EasyTierPeerCount     int             `json:"easytier_peer_count"`
	EasyTierHasRemotePeer bool            `json:"easytier_has_remote_peer"`
	EasyTierBestLatencyMS float64         `json:"easytier_best_latency_ms,omitempty"`
	EasyTierPacketLoss    string          `json:"easytier_packet_loss,omitempty"`
	EasyTierTunnels       []string        `json:"easytier_tunnels,omitempty"`
	EasyTierRouteType     string          `json:"easytier_route_type,omitempty"`
	EasyTierNetworkOK     bool            `json:"easytier_network_ok"`
	EasyTierNetworkReason string          `json:"easytier_network_reason,omitempty"`
	EasyTierDHCPEnabled   bool            `json:"easytier_dhcp_enabled"`
	EasyTierCIDR          string          `json:"easytier_cidr,omitempty"`
	LastAppliedConfigHash string          `json:"last_applied_config_hash,omitempty"`
}

type EasyTierPeer struct {
	IPv4      string   `json:"ipv4,omitempty"`
	Hostname  string   `json:"hostname,omitempty"`
	Cost      string   `json:"cost,omitempty"`
	LatencyMS float64  `json:"latency_ms,omitempty"`
	Loss      string   `json:"loss,omitempty"`
	RX        string   `json:"rx,omitempty"`
	TX        string   `json:"tx,omitempty"`
	Tunnel    string   `json:"tunnel,omitempty"`
	Tunnels   []string `json:"tunnels,omitempty"`
	NAT       string   `json:"nat,omitempty"`
	Version   string   `json:"version,omitempty"`
}

type EasyTierRoute struct {
	NextHopHostname string  `json:"next_hop_hostname,omitempty"`
	NextHopLatency  float64 `json:"next_hop_lat,omitempty"`
	PathLatency     float64 `json:"path_latency,omitempty"`
	RouteType       string  `json:"route_type,omitempty"`
}

type EasyTierDiagnostics struct {
	EasyTierStatus string          `json:"easytier_status"`
	NetworkOK      bool            `json:"network_ok"`
	Reason         string          `json:"reason,omitempty"`
	PeerCount      int             `json:"peer_count"`
	HasRemotePeer  bool            `json:"has_remote_peer"`
	BestLatencyMS  float64         `json:"best_latency_ms,omitempty"`
	PacketLoss     string          `json:"packet_loss,omitempty"`
	Tunnels        []string        `json:"tunnels,omitempty"`
	RouteType      string          `json:"route_type,omitempty"`
	VirtualIP      string          `json:"virtual_ip,omitempty"`
	RemotePeers    []EasyTierPeer  `json:"remote_peers,omitempty"`
	Routes         []EasyTierRoute `json:"routes,omitempty"`
	NodeInfoRaw    string          `json:"node_info_raw,omitempty"`
	PeerInfoRaw    string          `json:"peer_info_raw,omitempty"`
	RouteInfoRaw   string          `json:"route_info_raw,omitempty"`
}

type Task struct {
	ID        string         `json:"id"`
	NodeID    string         `json:"node_id"`
	Action    string         `json:"action"`
	Payload   map[string]any `json:"payload"`
	Status    string         `json:"status"`
	CreatedAt time.Time      `json:"created_at"`
	ExpiresAt *time.Time     `json:"expires_at,omitempty"`
	Attempt   int            `json:"attempt"`
}

type TaskResult struct {
	Status     string    `json:"status"`
	Result     string    `json:"result,omitempty"`
	Stdout     string    `json:"stdout,omitempty"`
	Stderr     string    `json:"stderr,omitempty"`
	Error      string    `json:"error,omitempty"`
	StartedAt  time.Time `json:"started_at"`
	FinishedAt time.Time `json:"finished_at"`
}

type CommandResult struct {
	Stdout   string
	Stderr   string
	ExitCode int
	Err      error
}
