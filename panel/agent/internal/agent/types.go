package agent

import "encoding/json"

const Version = "2.0.0-alpha.3"

type Config struct {
	ControllerURL   string
	Token           string
	NodeID          string
	NodeName        string
	Role            string
	IntervalSeconds int
}

type RegisterRequest struct {
	NodeID   string `json:"node_id"`
	NodeName string `json:"node_name"`
	Role     string `json:"role"`
	Hostname string `json:"hostname"`
}

type ReportRequest struct {
	NodeID          string            `json:"node_id"`
	NodeName        string            `json:"node_name"`
	Role            string            `json:"role"`
	Hostname        string            `json:"hostname"`
	PublicIP        string            `json:"public_ip"`
	PrimaryLANIP    string            `json:"primary_lan_ip"`
	EasyTierIP      string            `json:"easytier_ip"`
	AgentVersion    string            `json:"agent_version"`
	CoreVersion     string            `json:"core_version"`
	Status          string            `json:"status"`
	HealthScore     int               `json:"health_score"`
	IntervalSeconds int               `json:"interval_seconds"`
	Summary         json.RawMessage   `json:"summary,omitempty"`
	Doctor          json.RawMessage   `json:"doctor,omitempty"`
	LQStatus        json.RawMessage   `json:"lq_status,omitempty"`
	LQDoctor        json.RawMessage   `json:"lq_doctor,omitempty"`
	Services        map[string]string `json:"services,omitempty"`
	Entries         []EntryPayload    `json:"entries,omitempty"`
	Forwards        []ForwardPayload  `json:"forwards,omitempty"`
	RecentErrors    []string          `json:"recent_errors,omitempty"`
	Errors          []string          `json:"errors,omitempty"`
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
