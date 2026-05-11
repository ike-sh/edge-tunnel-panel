package controller

import "encoding/json"

const Version = "2.0.0-alpha.1"

type HealthResponse struct {
	Name    string `json:"name"`
	Version string `json:"version"`
	Status  string `json:"status"`
}

type RegisterRequest struct {
	NodeID   string `json:"node_id"`
	NodeName string `json:"node_name"`
	Role     string `json:"role"`
	Hostname string `json:"hostname"`
}

type ReportRequest struct {
	NodeID       string            `json:"node_id"`
	NodeName     string            `json:"node_name"`
	Role         string            `json:"role"`
	Hostname     string            `json:"hostname"`
	PublicIP     string            `json:"public_ip"`
	PrimaryLANIP string            `json:"primary_lan_ip"`
	EasyTierIP   string            `json:"easytier_ip"`
	AgentVersion string            `json:"agent_version"`
	CoreVersion  string            `json:"core_version"`
	Status       string            `json:"status"`
	HealthScore  int               `json:"health_score"`
	LQStatus     json.RawMessage   `json:"lq_status,omitempty"`
	LQDoctor     json.RawMessage   `json:"lq_doctor,omitempty"`
	Services     map[string]string `json:"services,omitempty"`
	Entries      []EntryPayload    `json:"entries,omitempty"`
	Forwards     []ForwardPayload  `json:"forwards,omitempty"`
	Errors       []string          `json:"errors,omitempty"`
}

type EntryPayload struct {
	Name       string          `json:"name"`
	ListenPort int             `json:"listen_port"`
	Protocol   string          `json:"protocol"`
	PublicHost string          `json:"public_host"`
	Status     string          `json:"status"`
	RawJSON    json.RawMessage `json:"raw_json,omitempty"`
}

type ForwardPayload struct {
	Name       string          `json:"name"`
	EntryName  string          `json:"entry_name"`
	TargetHost string          `json:"target_host"`
	TargetPort int             `json:"target_port"`
	Protocol   string          `json:"protocol"`
	Status     string          `json:"status"`
	RawJSON    json.RawMessage `json:"raw_json,omitempty"`
}

type Node struct {
	ID           int64  `json:"id"`
	NodeID       string `json:"node_id"`
	NodeName     string `json:"node_name"`
	Role         string `json:"role"`
	PublicIP     string `json:"public_ip"`
	LANIP        string `json:"lan_ip"`
	EasyTierIP   string `json:"easytier_ip"`
	AgentVersion string `json:"agent_version"`
	CoreVersion  string `json:"core_version"`
	Status       string `json:"status"`
	HealthScore  int    `json:"health_score"`
	LastSeen     string `json:"last_seen"`
	RawJSON      string `json:"raw_json,omitempty"`
}

type Entry struct {
	ID         int64  `json:"id"`
	NodeID     string `json:"node_id"`
	Name       string `json:"name"`
	ListenPort int    `json:"listen_port"`
	Protocol   string `json:"protocol"`
	PublicHost string `json:"public_host"`
	Status     string `json:"status"`
	RawJSON    string `json:"raw_json,omitempty"`
}

type Forward struct {
	ID         int64  `json:"id"`
	NodeID     string `json:"node_id"`
	Name       string `json:"name"`
	EntryName  string `json:"entry_name"`
	TargetHost string `json:"target_host"`
	TargetPort int    `json:"target_port"`
	Protocol   string `json:"protocol"`
	Status     string `json:"status"`
	RawJSON    string `json:"raw_json,omitempty"`
}

type Event struct {
	ID        int64  `json:"id"`
	NodeID    string `json:"node_id"`
	Level     string `json:"level"`
	Message   string `json:"message"`
	CreatedAt string `json:"created_at"`
}
