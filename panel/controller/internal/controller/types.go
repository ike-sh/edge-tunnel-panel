package controller

import "encoding/json"

const Version = "2.1.0"

type HealthResponse struct {
	Name    string `json:"name"`
	Version string `json:"version"`
	Status  string `json:"status"`
}

type ServerOptions struct {
	AgentToken    string
	OperatorToken string
	StrictAuth    bool
}

type AuthStatusResponse struct {
	OperatorAuthConfigured bool   `json:"operator_auth_configured"`
	StrictAuth             bool   `json:"strict_auth"`
	AgentAuthConfigured    bool   `json:"agent_auth_configured"`
	Version                string `json:"version"`
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
	LQAvailable                  bool     `json:"lq_available"`
	CoreVersion                  string   `json:"core_version"`
	SupportsStatusJSON           bool     `json:"supports_status_json"`
	SupportsDoctorJSON           bool     `json:"supports_doctor_json"`
	SupportsForwardList          bool     `json:"supports_forward_list"`
	SupportsDDNSOverview         bool     `json:"supports_ddns_overview"`
	EnableTasks                  bool     `json:"enable_tasks"`
	SupportsSnapshotManualRecord bool     `json:"supports_snapshot_manual_record"`
	SupportsRollbackManualRecord bool     `json:"supports_rollback_manual_record"`
	WriteActionsSupported        bool     `json:"write_actions_supported"`
	SupportedWriteActions        []string `json:"supported_write_actions,omitempty"`
	AllowedTaskActions           []string `json:"allowed_task_actions,omitempty"`
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
	NodeID      string `json:"node_id"`
	Action      string `json:"action"`
	RequestedBy string `json:"requested_by,omitempty"`
	TTLSeconds  int    `json:"ttl_seconds,omitempty"`
	MaxAttempts int    `json:"max_attempts,omitempty"`
	TaskGroupID string `json:"task_group_id,omitempty"`
}

type TaskResultRequest struct {
	Status       string `json:"status"`
	ResultStdout string `json:"result_stdout"`
	ResultStderr string `json:"result_stderr"`
	ExitCode     int    `json:"exit_code"`
	Error        string `json:"error"`
}

type Task struct {
	ID             int64           `json:"id"`
	NodeID         string          `json:"node_id"`
	Action         string          `json:"action"`
	Status         string          `json:"status"`
	ApprovalStatus string          `json:"approval_status"`
	ApprovedBy     string          `json:"approved_by,omitempty"`
	ApprovedAt     string          `json:"approved_at,omitempty"`
	RequestedBy    string          `json:"requested_by,omitempty"`
	TTLSeconds     int             `json:"ttl_seconds"`
	ExpiresAt      string          `json:"expires_at,omitempty"`
	RetryOfTaskID  int64           `json:"retry_of_task_id,omitempty"`
	Attempt        int             `json:"attempt"`
	MaxAttempts    int             `json:"max_attempts"`
	TaskGroupID    string          `json:"task_group_id,omitempty"`
	ResultStdout   string          `json:"result_stdout,omitempty"`
	ResultStderr   string          `json:"result_stderr,omitempty"`
	ExitCode       int             `json:"exit_code"`
	Error          string          `json:"error,omitempty"`
	CreatedAt      string          `json:"created_at"`
	PickedAt       string          `json:"picked_at,omitempty"`
	FinishedAt     string          `json:"finished_at,omitempty"`
	Timeline       json.RawMessage `json:"timeline_json,omitempty"`
}

type TaskApprovalRequest struct {
	Actor string `json:"actor,omitempty"`
	Note  string `json:"note,omitempty"`
}

type TaskTimelineItem struct {
	Time    string `json:"time"`
	Action  string `json:"action"`
	Level   string `json:"level"`
	Message string `json:"message"`
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

type PlanSnapshotRequest struct {
	SnapshotRef    string `json:"snapshot_ref"`
	SnapshotNote   string `json:"snapshot_note"`
	SnapshotStatus string `json:"snapshot_status,omitempty"`
}

type PlanRollbackInfoRequest struct {
	RollbackAvailable bool   `json:"rollback_available"`
	RollbackRef       string `json:"rollback_ref"`
	RollbackNote      string `json:"rollback_note"`
}

type SafetyGateResponse struct {
	PlanID         int64                 `json:"plan_id"`
	DryRunPassed   bool                  `json:"dry_run_passed"`
	ApprovalReady  bool                  `json:"approval_ready"`
	SnapshotReady  bool                  `json:"snapshot_ready"`
	RollbackReady  bool                  `json:"rollback_ready"`
	BlockedReasons []string              `json:"blocked_reasons"`
	Warnings       []string              `json:"warnings"`
	Overall        string                `json:"overall"`
	ActionReview   *ActionReviewResponse `json:"action_review,omitempty"`
}

type ActionDefinition struct {
	Action               string   `json:"action"`
	Title                string   `json:"title"`
	Category             string   `json:"category"`
	RiskLevel            string   `json:"risk_level"`
	Description          string   `json:"description"`
	RequiredGates        []string `json:"required_gates"`
	RequiredCapabilities []string `json:"required_capabilities"`
	RollbackRequired     bool     `json:"rollback_required"`
	SnapshotRequired     bool     `json:"snapshot_required"`
	ApprovalRequired     bool     `json:"approval_required"`
	Enabled              bool     `json:"enabled"`
}

type ActionCatalogResponse struct {
	Version string             `json:"version"`
	Actions []ActionDefinition `json:"actions"`
}

type ActionReviewResponse struct {
	PlanID                  int64    `json:"plan_id"`
	PlanType                string   `json:"plan_type"`
	MatchedAction           string   `json:"matched_action"`
	ReviewedBy              string   `json:"reviewed_by,omitempty"`
	Category                string   `json:"category"`
	RiskLevel               string   `json:"risk_level"`
	RequiredGates           []string `json:"required_gates"`
	RequiredCapabilities    []string `json:"required_capabilities"`
	MissingGates            []string `json:"missing_gates"`
	ReadyForFutureExecution bool     `json:"ready_for_future_execution"`
	Reason                  string   `json:"reason"`
	Enabled                 bool     `json:"enabled"`
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
	DryRunStatus           string          `json:"dry_run_status"`
	DryRunTaskIDs          []int64         `json:"dry_run_task_ids"`
	DryRunReport           json.RawMessage `json:"dry_run_report,omitempty"`
	LastDryRunAt           string          `json:"last_dry_run_at,omitempty"`
	SnapshotPolicy         string          `json:"snapshot_policy"`
	SnapshotRequired       bool            `json:"snapshot_required"`
	SnapshotStatus         string          `json:"snapshot_status"`
	SnapshotRef            string          `json:"snapshot_ref"`
	SnapshotNote           string          `json:"snapshot_note"`
	RollbackAvailable      bool            `json:"rollback_available"`
	RollbackRef            string          `json:"rollback_ref"`
	RollbackNote           string          `json:"rollback_note"`
	RollbackInstructions   string          `json:"rollback_instructions"`
	VerificationStatus     string          `json:"verification_status"`
	VerificationReport     json.RawMessage `json:"verification_report,omitempty"`
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
