package controller

import "time"

var (
	Version = "v0.2.5-test"
	Commit  = "dev"
	Date    = "unknown"
)

type APIError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

type APIResponse struct {
	OK    bool      `json:"ok"`
	Data  any       `json:"data,omitempty"`
	Error *APIError `json:"error,omitempty"`
}

type HealthResponse struct {
	Name        string `json:"name"`
	Version     string `json:"version"`
	BuildCommit string `json:"build_commit"`
	BuildTime   string `json:"build_time"`
	StrictAuth  bool   `json:"strict_auth"`
}

type LoginRequest struct {
	Token string `json:"token"`
}

type Node struct {
	ID                    string            `json:"id"`
	Name                  string            `json:"name"`
	Role                  string            `json:"role"`
	PublicIP              string            `json:"public_ip"`
	PrivateIP             string            `json:"private_ip"`
	ObservedIP            string            `json:"observed_ip"`
	AgentVersion          string            `json:"agent_version"`
	Hostname              string            `json:"hostname"`
	OS                    string            `json:"os"`
	Arch                  string            `json:"arch"`
	EasyTierIP            string            `json:"easytier_ip"`
	EasyTierStatus        string            `json:"easytier_status"`
	EasyTierPeerCount     int               `json:"easytier_peer_count"`
	EasyTierHasRemotePeer bool              `json:"easytier_has_remote_peer"`
	EasyTierBestLatencyMS float64           `json:"easytier_best_latency_ms,omitempty"`
	EasyTierPacketLoss    string            `json:"easytier_packet_loss,omitempty"`
	EasyTierTunnels       []string          `json:"easytier_tunnels,omitempty"`
	EasyTierRouteType     string            `json:"easytier_route_type,omitempty"`
	EasyTierNetworkOK     bool              `json:"easytier_network_ok"`
	EasyTierNetworkReason string            `json:"easytier_network_reason,omitempty"`
	EasyTierDHCPEnabled   bool              `json:"easytier_dhcp_enabled"`
	EasyTierCIDR          string            `json:"easytier_cidr,omitempty"`
	LastSeenAt            time.Time         `json:"last_seen_at"`
	Status                string            `json:"status"`
	StatusReason          string            `json:"status_reason"`
	OfflineAt             *time.Time        `json:"offline_at,omitempty"`
	Capabilities          map[string]bool   `json:"capabilities"`
	Labels                map[string]string `json:"labels"`
	CreatedAt             time.Time         `json:"created_at"`
	UpdatedAt             time.Time         `json:"updated_at"`
}

type NetworkProfile struct {
	ID                 string    `json:"id"`
	Name               string    `json:"name"`
	NetworkName        string    `json:"network_name"`
	NetworkSecret      string    `json:"network_secret"`
	CIDR               string    `json:"cidr"`
	ProtocolPreference string    `json:"protocol_preference"`
	Listeners          []string  `json:"listeners"`
	Peers              []string  `json:"peers"`
	CreatedAt          time.Time `json:"created_at"`
	UpdatedAt          time.Time `json:"updated_at"`
}

type NetworkLink struct {
	ID               string    `json:"id"`
	Name             string    `json:"name"`
	NetworkName      string    `json:"network_name"`
	CIDR             string    `json:"cidr"`
	Port             int       `json:"port"`
	Protocols        []string  `json:"protocols"`
	EntryNodeID      string    `json:"entry_node_id"`
	BackendNodeID    string    `json:"backend_node_id"`
	EntryTaskID      string    `json:"entry_task_id"`
	BackendTaskID    string    `json:"backend_task_id"`
	LastVerifyAt     time.Time `json:"last_verify_at,omitempty"`
	Status           string    `json:"status"`
	EntryPeerCount   int       `json:"entry_peer_count"`
	BackendPeerCount int       `json:"backend_peer_count"`
	BestLatencyMS    float64   `json:"best_latency_ms,omitempty"`
	PacketLoss       string    `json:"packet_loss,omitempty"`
	Tunnels          []string  `json:"tunnels,omitempty"`
	RouteType        string    `json:"route_type,omitempty"`
	CreatedAt        time.Time `json:"created_at"`
	UpdatedAt        time.Time `json:"updated_at"`
}

type Entry struct {
	ID              string    `json:"id"`
	Name            string    `json:"name"`
	NodeID          string    `json:"node_id"`
	ListenIP        string    `json:"listen_ip"`
	ListenPortStart int       `json:"listen_port_start"`
	ListenPortEnd   int       `json:"listen_port_end"`
	Protocol        string    `json:"protocol"`
	Domain          string    `json:"domain"`
	DDNSEnabled     bool      `json:"ddns_enabled"`
	DDNSProvider    string    `json:"ddns_provider"`
	DDNSTokenRef    string    `json:"ddns_token_ref"`
	Status          string    `json:"status"`
	CreatedAt       time.Time `json:"created_at"`
	UpdatedAt       time.Time `json:"updated_at"`
}

type Forward struct {
	ID                 string    `json:"id"`
	NetworkLinkID      string    `json:"network_link_id,omitempty"`
	Name               string    `json:"name"`
	Enabled            bool      `json:"enabled"`
	Protocol           string    `json:"protocol"`
	EntryID            string    `json:"entry_id,omitempty"`
	EntryNodeID        string    `json:"entry_node_id"`
	BackendNodeID      string    `json:"backend_node_id"`
	ListenHost         string    `json:"listen_host"`
	ListenPort         int       `json:"listen_port"`
	TargetIP           string    `json:"target_ip"`
	TargetPort         int       `json:"target_port"`
	TargetNodeIPSource string    `json:"target_node_ip_source"`
	Remark             string    `json:"remark"`
	Status             string    `json:"status"`
	LastApplyTaskID    string    `json:"last_apply_task_id,omitempty"`
	LastVerifyTaskID   string    `json:"last_verify_task_id,omitempty"`
	TargetMode         string    `json:"target_mode,omitempty"`
	TargetNodeID       string    `json:"target_node_id,omitempty"`
	TargetHost         string    `json:"target_host,omitempty"`
	CreatedAt          time.Time `json:"created_at"`
	UpdatedAt          time.Time `json:"updated_at"`
}

type PBRPolicy struct {
	ID            string    `json:"id"`
	NodeID        string    `json:"node_id"`
	Name          string    `json:"name"`
	MatchSource   string    `json:"match_source"`
	MatchDst      string    `json:"match_dst"`
	MatchProtocol string    `json:"match_protocol"`
	MatchMark     string    `json:"match_mark"`
	TableID       int       `json:"table_id"`
	Gateway       string    `json:"gateway"`
	OutInterface  string    `json:"out_interface"`
	Priority      int       `json:"priority"`
	Enabled       bool      `json:"enabled"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`
}

type DDNSProfile struct {
	ID         string    `json:"id"`
	NodeID     string    `json:"node_id"`
	EntryID    string    `json:"entry_id"`
	Provider   string    `json:"provider"`
	Domain     string    `json:"domain"`
	RecordType string    `json:"record_type"`
	TokenRef   string    `json:"token_ref"`
	LastIP     string    `json:"last_ip"`
	LastSyncAt time.Time `json:"last_sync_at"`
	Status     string    `json:"status"`
	CreatedAt  time.Time `json:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"`
}

type Task struct {
	ID         string         `json:"id"`
	NodeID     string         `json:"node_id"`
	Action     string         `json:"action"`
	Payload    map[string]any `json:"payload"`
	Status     string         `json:"status"`
	Result     string         `json:"result"`
	Stdout     string         `json:"stdout"`
	Stderr     string         `json:"stderr"`
	Error      string         `json:"error"`
	CreatedAt  time.Time      `json:"created_at"`
	StartedAt  *time.Time     `json:"started_at,omitempty"`
	FinishedAt *time.Time     `json:"finished_at,omitempty"`
	ExpiresAt  *time.Time     `json:"expires_at,omitempty"`
	Attempt    int            `json:"attempt"`
}

type StoreFile struct {
	Nodes           []Node           `json:"nodes"`
	NetworkProfiles []NetworkProfile `json:"network_profiles"`
	NetworkLinks    []NetworkLink    `json:"network_links"`
	Entries         []Entry          `json:"entries"`
	Forwards        []Forward        `json:"forwards"`
	PBRPolicies     []PBRPolicy      `json:"pbr_policies"`
	DDNSProfiles    []DDNSProfile    `json:"ddns_profiles"`
	Tasks           []Task           `json:"tasks"`
}
