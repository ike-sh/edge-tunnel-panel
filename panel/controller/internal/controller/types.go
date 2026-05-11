package controller

import "encoding/json"

const Version = "2.1.0-alpha.1"

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
	Capabilities    AgentCapabilities `json:"capabilities,omitempty"`
}

type AgentCapabilities struct {
	LQAvailable          bool     `json:"lq_available"`
	CoreVersion          string   `json:"core_version"`
	SupportsStatusJSON   bool     `json:"supports_status_json"`
	SupportsDoctorJSON   bool     `json:"supports_doctor_json"`
	SupportsForwardList  bool     `json:"supports_forward_list"`
	SupportsDDNSOverview bool     `json:"supports_ddns_overview"`
	EnableTasks          bool     `json:"enable_tasks"`
	AllowedTaskActions   []string `json:"allowed_task_actions,omitempty"`
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
	ID              int64             `json:"id"`
	NodeID          string            `json:"node_id"`
	NodeName        string            `json:"node_name"`
	Role            string            `json:"role"`
	PublicIP        string            `json:"public_ip"`
	LANIP           string            `json:"lan_ip"`
	EasyTierIP      string            `json:"easytier_ip"`
	AgentVersion    string            `json:"agent_version"`
	CoreVersion     string            `json:"core_version"`
	Status          string            `json:"status"`
	HealthScore     int               `json:"health_score"`
	IntervalSeconds int               `json:"interval_seconds"`
	LastSeen        string            `json:"last_seen"`
	Services        map[string]string `json:"services,omitempty"`
	Capabilities    AgentCapabilities `json:"capabilities,omitempty"`
	Summary         json.RawMessage   `json:"summary,omitempty"`
	Doctor          json.RawMessage   `json:"doctor,omitempty"`
	RecentErrors    []string          `json:"recent_errors,omitempty"`
	RawJSON         string            `json:"raw_json,omitempty"`
}

type NodeReport struct {
	ID              int64             `json:"id"`
	NodeID          string            `json:"node_id"`
	Status          string            `json:"status"`
	HealthScore     int               `json:"health_score"`
	IntervalSeconds int               `json:"interval_seconds"`
	Services        map[string]string `json:"services,omitempty"`
	Capabilities    AgentCapabilities `json:"capabilities,omitempty"`
	Summary         json.RawMessage   `json:"summary,omitempty"`
	Doctor          json.RawMessage   `json:"doctor,omitempty"`
	RecentErrors    []string          `json:"recent_errors,omitempty"`
	RawJSON         string            `json:"raw_json,omitempty"`
	CreatedAt       string            `json:"created_at"`
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

type CreateTaskRequest struct {
	NodeID string `json:"node_id"`
	Action string `json:"action"`
}

type TaskResultRequest struct {
	Status       string `json:"status"`
	ResultStdout string `json:"result_stdout"`
	ResultStderr string `json:"result_stderr"`
	ExitCode     int    `json:"exit_code"`
	Error        string `json:"error"`
}

type Task struct {
	ID           int64  `json:"id"`
	NodeID       string `json:"node_id"`
	Action       string `json:"action"`
	Status       string `json:"status"`
	ResultStdout string `json:"result_stdout,omitempty"`
	ResultStderr string `json:"result_stderr,omitempty"`
	ExitCode     int    `json:"exit_code"`
	Error        string `json:"error,omitempty"`
	CreatedAt    string `json:"created_at"`
	PickedAt     string `json:"picked_at,omitempty"`
	FinishedAt   string `json:"finished_at,omitempty"`
}

type BootstrapAgentCommandResponse struct {
	Command       string `json:"command"`
	ControllerURL string `json:"controller_url"`
	Role          string `json:"role"`
	NodeName      string `json:"node_name"`
	Token         string `json:"token"`
	Note          string `json:"note"`
}

type TopologyLink struct {
	Source string `json:"source"`
	Target string `json:"target"`
	Type   string `json:"type"`
	Label  string `json:"label"`
	Status string `json:"status"`
}

type TopologyResponse struct {
	Nodes    []Node         `json:"nodes"`
	Entries  []Entry        `json:"entries"`
	Forwards []Forward      `json:"forwards"`
	Links    []TopologyLink `json:"links"`
}

type CreatePlanRequest struct {
	Type         string          `json:"type"`
	Title        string          `json:"title"`
	TargetNodeID string          `json:"target_node_id"`
	Payload      json.RawMessage `json:"payload_json,omitempty"`
}

type MarkPlanRequest struct {
	ExecutionStatus string `json:"execution_status"`
	ExecutionNote   string `json:"execution_note"`
	ManualResult    string `json:"manual_result"`
}

type CommandGroup struct {
	NodeID   string   `json:"node_id"`
	NodeName string   `json:"node_name"`
	Role     string   `json:"role"`
	Commands []string `json:"commands"`
}

type Plan struct {
	ID                     int64           `json:"id"`
	Type                   string          `json:"type"`
	Title                  string          `json:"title"`
	Status                 string          `json:"status"`
	ExecutionStatus        string          `json:"execution_status"`
	ExecutionNote          string          `json:"execution_note"`
	ManualResult           string          `json:"manual_result"`
	SafetyLevel            string          `json:"safety_level"`
	CommandClassification  string          `json:"command_classification"`
	TargetNodeID           string          `json:"target_node_id"`
	PayloadJSON            json.RawMessage `json:"payload_json,omitempty"`
	GeneratedCommands      []string        `json:"generated_commands"`
	CommandGroups          []CommandGroup  `json:"command_groups"`
	Checklist              []string        `json:"checklist"`
	Preflight              json.RawMessage `json:"preflight,omitempty"`
	CapabilityRequirements []string        `json:"capability_requirements"`
	Markdown               string          `json:"markdown"`
	Warnings               []string        `json:"warnings"`
	CreatedAt              string          `json:"created_at"`
	UpdatedAt              string          `json:"updated_at"`
}

type CapabilityItem struct {
	Command string `json:"command"`
	Class   string `json:"class"`
	Note    string `json:"note"`
}

type CapabilitiesResponse struct {
	Version            string           `json:"version"`
	Commands           []CapabilityItem `json:"commands"`
	Blocked            []string         `json:"blocked_patterns"`
	Future             []string         `json:"future"`
	SafetyLevels       []string         `json:"safety_levels"`
	TaskSupport        string           `json:"task_support"`
	AllowedTaskActions []string         `json:"allowed_task_actions"`
}
