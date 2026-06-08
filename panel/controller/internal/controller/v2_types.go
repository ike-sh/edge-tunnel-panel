package controller

import "time"

// IXProfile represents an ix-transit-fabric transit line managed via the panel.
type IXProfile struct {
	ID        string         `json:"id"`
	Name      string         `json:"name"`
	Role      string         `json:"role"` // nat-transit | nat-ingress
	MachineID string         `json:"machine_id"`
	Enabled   bool           `json:"enabled"`
	Status    string         `json:"status"`
	Config    map[string]any `json:"config,omitempty"`
	Rules         []IXRule       `json:"rules,omitempty"`
	CodeRedacted  string         `json:"code_redacted,omitempty"`
	PortMap       string         `json:"port_map,omitempty"`
	CreatedAt     time.Time      `json:"created_at"`
	UpdatedAt     time.Time      `json:"updated_at"`
}

type IXRule struct {
	ID            string `json:"id"`
	ProfileID     string `json:"profile_id"`
	NATPublicPort int    `json:"nat_public_port,omitempty"`
	TransitPort   int    `json:"transit_port,omitempty"`
	LocalPort     int    `json:"local_port,omitempty"`
	LandingHost   string `json:"landing_host,omitempty"`
	LandingPort   int    `json:"landing_port,omitempty"`
	Enabled       bool   `json:"enabled"`
	Remark        string `json:"remark,omitempty"`
}

type IXMachine struct {
	ID       string    `json:"id"`
	Name     string    `json:"name"`
	Role     string    `json:"role"` // nat-transit | nat-ingress
	Token    string    `json:"token,omitempty"`
	Status   string    `json:"status"`
	NodeID   string    `json:"node_id,omitempty"`
	LastSeen time.Time `json:"last_seen_at,omitempty"`
}

type CreateIXProfileRequest struct {
	Name      string         `json:"name"`
	Role      string         `json:"role"`
	MachineID string         `json:"machine_id"`
	Code      string         `json:"code,omitempty"`
	Config    map[string]any `json:"config"`
}

type ImportCodeRequest struct {
	Code      string         `json:"code"`
	LocalPorts map[string]int `json:"local_ports,omitempty"`
}
