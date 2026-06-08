package controller

import "time"

var (
	Version = "v0.3.1"
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
	StrictAuth    bool `json:"strict_auth"`
	LegacyV1API   bool `json:"legacy_v1_api"`
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
	CPUPercent            float64           `json:"cpu_percent,omitempty"`
	MemPercent            float64           `json:"mem_percent,omitempty"`
	MemTotalMB            uint64            `json:"mem_total_mb,omitempty"`
	MemUsedMB             uint64            `json:"mem_used_mb,omitempty"`
	UptimeSec             uint64            `json:"uptime_sec,omitempty"`
	BytesSent             uint64            `json:"bytes_sent,omitempty"`
	BytesReceived         uint64            `json:"bytes_received,omitempty"`
	NetTxBPS              uint64            `json:"net_tx_bps,omitempty"`
	NetRxBPS              uint64            `json:"net_rx_bps,omitempty"`
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
	MTU                int       `json:"mtu"`
	MSSClampEnabled    bool      `json:"mss_clamp_enabled"`
	MSSMode            string    `json:"mss_mode"`
	MSSValue           int       `json:"mss_value"`
	CreatedAt          time.Time `json:"created_at"`
	UpdatedAt          time.Time `json:"updated_at"`
}

type NetworkLink struct {
	ID                   string    `json:"id"`
	Name                 string    `json:"name"`
	LinkType             string    `json:"link_type"`
	NetworkName          string    `json:"network_name"`
	CIDR                 string    `json:"cidr"`
	Port                 int       `json:"port"`
	Protocols            []string  `json:"protocols"`
	LandingReachableHost string    `json:"landing_reachable_host,omitempty"`
	TransitPort          int       `json:"transit_port,omitempty"`
	MTU                  int       `json:"mtu"`
	MSSClampEnabled      bool      `json:"mss_clamp_enabled"`
	MSSMode              string    `json:"mss_mode"`
	MSSValue             int       `json:"mss_value"`
	EntryNodeID          string    `json:"entry_node_id"`
	BackendNodeID        string    `json:"backend_node_id"`
	EntryTaskID          string    `json:"entry_task_id"`
	BackendTaskID        string    `json:"backend_task_id"`
	LastVerifyAt         time.Time `json:"last_verify_at,omitempty"`
	Status               string    `json:"status"`
	StatusReason         string    `json:"status_reason,omitempty"`
	EntryPeerCount       int       `json:"entry_peer_count"`
	BackendPeerCount     int       `json:"backend_peer_count"`
	BestLatencyMS        float64   `json:"best_latency_ms,omitempty"`
	PacketLoss           string    `json:"packet_loss,omitempty"`
	Tunnels              []string  `json:"tunnels,omitempty"`
	RouteType            string    `json:"route_type,omitempty"`
	CreatedAt            time.Time `json:"created_at"`
	UpdatedAt            time.Time `json:"updated_at"`
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
	ID                     string    `json:"id"`
	NetworkLinkID          string    `json:"network_link_id,omitempty"`
	Name                   string    `json:"name"`
	Enabled                bool      `json:"enabled"`
	Protocol               string    `json:"protocol"`
	EntryID                string    `json:"entry_id,omitempty"`
	EntryNodeID            string    `json:"entry_node_id"`
	LandingNodeID          string    `json:"landing_node_id"`
	BackendNodeID          string    `json:"backend_node_id,omitempty"`
	PublicListenHost       string    `json:"public_listen_host"`
	PublicListenPort       int       `json:"public_listen_port"`
	TransportMode          string    `json:"transport_mode"`
	TunnelTargetHost       string    `json:"tunnel_target_host"`
	TunnelTargetPort       int       `json:"tunnel_target_port"`
	LandingHostRaw         string    `json:"landing_host_raw"`
	LandingHostResolved    string    `json:"landing_host_resolved,omitempty"`
	LandingPort            int       `json:"landing_port"`
	Status                 string    `json:"status"`
	EntryStageStatus       string    `json:"entry_stage_status,omitempty"`
	LandingStageStatus     string    `json:"landing_stage_status,omitempty"`
	LastApplyEntryTaskID   string    `json:"last_apply_entry_task_id,omitempty"`
	LastApplyLandingTaskID string    `json:"last_apply_landing_task_id,omitempty"`
	LastVerifyTaskID       string    `json:"last_verify_task_id,omitempty"`
	Remark                 string    `json:"remark"`
	CreatedAt              time.Time `json:"created_at"`
	UpdatedAt              time.Time `json:"updated_at"`

	// Legacy fields kept for older stored data and API clients.
	ListenHost         string `json:"listen_host,omitempty"`
	ListenPort         int    `json:"listen_port,omitempty"`
	TargetIP           string `json:"target_ip,omitempty"`
	TargetPort         int    `json:"target_port,omitempty"`
	TargetNodeIPSource string `json:"target_node_ip_source,omitempty"`
	LastApplyTaskID    string `json:"last_apply_task_id,omitempty"`
	TargetMode         string `json:"target_mode,omitempty"`
	TargetNodeID       string `json:"target_node_id,omitempty"`
	TargetHost         string `json:"target_host,omitempty"`
}

type PBRPolicy struct {
	ID                  string    `json:"id"`
	Name                string    `json:"name"`
	Enabled             bool      `json:"enabled"`
	NodeID              string    `json:"node_id"`
	SourceType          string    `json:"source_type"`
	ForwardRuleID       string    `json:"forward_rule_id,omitempty"`
	Domain              string    `json:"domain,omitempty"`
	StaticDstCIDR       string    `json:"static_dst_cidr,omitempty"`
	Protocol            string    `json:"protocol"`
	MatchPort           int       `json:"match_port"`
	MatchDstHost        string    `json:"match_dst_host,omitempty"`
	MatchDstPort        int       `json:"match_dst_port,omitempty"`
	MatchSrcHost        string    `json:"match_src_host,omitempty"`
	MatchMarkComment    string    `json:"match_mark_comment,omitempty"`
	EgressInterface     string    `json:"egress_interface"`
	EgressGateway       string    `json:"egress_gateway,omitempty"`
	EgressSourceIP      string    `json:"egress_source_ip,omitempty"`
	RouteGroupName      string    `json:"route_group_name,omitempty"`
	RouteGroupGateway   string    `json:"route_group_gateway,omitempty"`
	RouteGroupTableID   int       `json:"route_group_table_id,omitempty"`
	RouteGroupTableName string    `json:"route_group_table_name,omitempty"`
	RouteGroupMatchedIP string    `json:"route_group_matched_ip,omitempty"`
	TableID             int       `json:"table_id"`
	FWMark              string    `json:"fwmark"`
	Priority            int       `json:"priority"`
	MSSClampEnabled     bool      `json:"mss_clamp_enabled"`
	MSSValue            int       `json:"mss_value,omitempty"`
	MTU                 int       `json:"mtu,omitempty"`
	Status              string    `json:"status"`
	LastApplyTaskID     string    `json:"last_apply_task_id,omitempty"`
	LastVerifyTaskID    string    `json:"last_verify_task_id,omitempty"`
	Remark              string    `json:"remark,omitempty"`
	CreatedAt           time.Time `json:"created_at"`
	UpdatedAt           time.Time `json:"updated_at"`

	// Legacy fields kept for older stored data and API clients.
	MatchSource   string `json:"match_source,omitempty"`
	MatchDst      string `json:"match_dst,omitempty"`
	MatchProtocol string `json:"match_protocol,omitempty"`
	MatchMark     string `json:"match_mark,omitempty"`
	Gateway       string `json:"gateway,omitempty"`
	OutInterface  string `json:"out_interface,omitempty"`
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
	IXMachines      []IXMachine      `json:"ix_machines,omitempty"`
	IXProfiles      []IXProfile      `json:"ix_profiles,omitempty"`
}
