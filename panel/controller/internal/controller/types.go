package controller

import "time"

var (
	Version = "v0.2.1-hotfix"
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
	ID           string    `json:"id"`
	Name         string    `json:"name"`
	EntryID      string    `json:"entry_id"`
	EntryNodeID  string    `json:"entry_node_id"`
	Protocol     string    `json:"protocol"`
	ListenPort   int       `json:"listen_port"`
	TargetMode   string    `json:"target_mode"`
	TargetNodeID string    `json:"target_node_id"`
	TargetHost   string    `json:"target_host"`
	TargetPort   int       `json:"target_port"`
	Enabled      bool      `json:"enabled"`
	Remark       string    `json:"remark"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
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
	Entries         []Entry          `json:"entries"`
	Forwards        []Forward        `json:"forwards"`
	PBRPolicies     []PBRPolicy      `json:"pbr_policies"`
	DDNSProfiles    []DDNSProfile    `json:"ddns_profiles"`
	Tasks           []Task           `json:"tasks"`
}
