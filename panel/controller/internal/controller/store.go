package controller

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	_ "modernc.org/sqlite"
)

type Store struct {
	db *sql.DB
}

func OpenStore(path string) (*Store, error) {
	if dir := filepath.Dir(path); dir != "." && dir != "" {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return nil, err
		}
	}
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, err
	}
	s := &Store{db: db}
	if err := s.migrate(context.Background()); err != nil {
		db.Close()
		return nil, err
	}
	return s, nil
}

func (s *Store) Close() error {
	return s.db.Close()
}

func (s *Store) migrate(ctx context.Context) error {
	stmts := []string{
		`CREATE TABLE IF NOT EXISTS nodes (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			node_id TEXT NOT NULL UNIQUE,
			node_name TEXT,
			role TEXT,
			public_ip TEXT,
			lan_ip TEXT,
			easytier_ip TEXT,
			agent_version TEXT,
			core_version TEXT,
			status TEXT,
			health_score INTEGER DEFAULT 0,
			interval_seconds INTEGER DEFAULT 0,
			last_seen TEXT,
			services_json TEXT,
			summary_json TEXT,
			doctor_json TEXT,
			recent_errors_json TEXT,
			raw_json TEXT
		)`,
		`CREATE TABLE IF NOT EXISTS node_reports (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			node_id TEXT NOT NULL,
			status TEXT,
			health_score INTEGER DEFAULT 0,
			interval_seconds INTEGER DEFAULT 0,
			services_json TEXT,
			summary_json TEXT,
			doctor_json TEXT,
			recent_errors_json TEXT,
			raw_json TEXT,
			created_at TEXT
		)`,
		`CREATE TABLE IF NOT EXISTS entries (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			node_id TEXT NOT NULL,
			name TEXT,
			listen_port INTEGER,
			protocol TEXT,
			public_host TEXT,
			status TEXT,
			raw_json TEXT
		)`,
		`CREATE TABLE IF NOT EXISTS forwards (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			node_id TEXT NOT NULL,
			name TEXT,
			entry_name TEXT,
			target_host TEXT,
			target_port INTEGER,
			protocol TEXT,
			status TEXT,
			raw_json TEXT
		)`,
		`CREATE TABLE IF NOT EXISTS events (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			node_id TEXT,
			level TEXT,
			message TEXT,
			created_at TEXT
		)`,
		`CREATE TABLE IF NOT EXISTS plans (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			type TEXT NOT NULL,
			title TEXT,
			status TEXT,
			execution_status TEXT,
			execution_note TEXT,
			manual_result TEXT,
			target_node_id TEXT,
			payload_json TEXT,
			generated_commands TEXT,
			command_groups TEXT,
			checklist TEXT,
			markdown TEXT,
			warnings TEXT,
			created_at TEXT,
			updated_at TEXT
		)`,
	}
	for _, stmt := range stmts {
		if _, err := s.db.ExecContext(ctx, stmt); err != nil {
			return err
		}
	}
	columns := map[string]string{
		"interval_seconds":   "INTEGER DEFAULT 0",
		"services_json":      "TEXT",
		"summary_json":       "TEXT",
		"doctor_json":        "TEXT",
		"recent_errors_json": "TEXT",
	}
	for name, typ := range columns {
		if err := s.addColumnIfMissing(ctx, "nodes", name, typ); err != nil {
			return err
		}
	}
	planColumns := map[string]string{
		"execution_status": "TEXT",
		"execution_note":   "TEXT",
		"manual_result":    "TEXT",
		"command_groups":   "TEXT",
		"checklist":        "TEXT",
		"markdown":         "TEXT",
	}
	for name, typ := range planColumns {
		if err := s.addColumnIfMissing(ctx, "plans", name, typ); err != nil {
			return err
		}
	}
	return nil
}

func (s *Store) addColumnIfMissing(ctx context.Context, table, column, typ string) error {
	rows, err := s.db.QueryContext(ctx, "PRAGMA table_info("+table+")")
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var cid int
		var name, colType string
		var notNull int
		var defaultValue any
		var pk int
		if err := rows.Scan(&cid, &name, &colType, &notNull, &defaultValue, &pk); err != nil {
			return err
		}
		if name == column {
			return nil
		}
	}
	if err := rows.Err(); err != nil {
		return err
	}
	_, err = s.db.ExecContext(ctx, fmt.Sprintf("ALTER TABLE %s ADD COLUMN %s %s", table, column, typ))
	return err
}

func nowString() string {
	return time.Now().UTC().Format(time.RFC3339)
}

func normalizeRole(role string) string {
	switch role {
	case "entry", "relay", "backend", "mixed", "unknown":
		return role
	default:
		return "unknown"
	}
}

func normalizeStatus(status string) string {
	switch status {
	case "online", "offline", "degraded", "ok":
		if status == "ok" {
			return "online"
		}
		return status
	default:
		return "degraded"
	}
}

func normalizePlanType(planType string) (string, error) {
	switch planType {
	case "create_entry", "create_forward", "switch_entry", "ddns_check":
		return planType, nil
	default:
		return "", fmt.Errorf("unsupported plan type: %s", planType)
	}
}

func normalizePlanStatus(status string) string {
	switch status {
	case "draft", "generated", "copied", "archived":
		return status
	default:
		return "draft"
	}
}

func normalizeExecutionStatus(status string) string {
	switch status {
	case "not_run", "running_manually", "succeeded", "failed", "rolled_back":
		return status
	default:
		return "not_run"
	}
}

func jsonText(v any) string {
	raw, err := json.Marshal(v)
	if err != nil {
		return "null"
	}
	return string(RedactJSONBytes(raw))
}

func rawJSONText(raw json.RawMessage) string {
	if len(raw) == 0 {
		return "null"
	}
	return string(RedactJSONBytes(raw))
}

func reportErrors(req ReportRequest) []string {
	out := make([]string, 0, len(req.RecentErrors)+len(req.Errors))
	out = append(out, req.RecentErrors...)
	out = append(out, req.Errors...)
	for i := range out {
		out[i] = RedactString(out[i])
	}
	return out
}

func scanJSONMap(text string) map[string]string {
	out := map[string]string{}
	if text == "" || text == "null" {
		return out
	}
	_ = json.Unmarshal([]byte(text), &out)
	return out
}

func scanStringSlice(text string) []string {
	out := []string{}
	if text == "" || text == "null" {
		return out
	}
	_ = json.Unmarshal([]byte(text), &out)
	return out
}

func rawPlanPayload(raw json.RawMessage) string {
	if len(raw) == 0 {
		return "{}"
	}
	var v any
	if err := json.Unmarshal(raw, &v); err != nil {
		return string(RedactJSONBytes(raw))
	}
	out, err := json.Marshal(StripSensitiveValue(v))
	if err != nil {
		return string(RedactJSONBytes(raw))
	}
	return string(out)
}

func redactManualText(text string) string {
	trimmed := strings.TrimSpace(text)
	if trimmed == "" {
		return ""
	}
	var v any
	if err := json.Unmarshal([]byte(trimmed), &v); err == nil {
		raw, err := json.Marshal(StripSensitiveValue(v))
		if err == nil {
			return string(RedactJSONBytes(raw))
		}
	}
	return RedactString(text)
}

func (s *Store) Register(ctx context.Context, req RegisterRequest, raw []byte) error {
	if req.NodeID == "" {
		return fmt.Errorf("node_id is required")
	}
	name := req.NodeName
	if name == "" {
		name = req.Hostname
	}
	if name == "" {
		name = req.NodeID
	}
	now := nowString()
	redacted := string(RedactJSONBytes(raw))
	_, err := s.db.ExecContext(ctx, `INSERT INTO nodes
		(node_id, node_name, role, status, last_seen, raw_json)
		VALUES (?, ?, ?, ?, ?, ?)
		ON CONFLICT(node_id) DO UPDATE SET
			node_name=excluded.node_name,
			role=excluded.role,
			last_seen=excluded.last_seen,
			raw_json=excluded.raw_json`,
		req.NodeID, name, normalizeRole(req.Role), "unknown", now, redacted)
	if err != nil {
		return err
	}
	return s.AddEvent(ctx, req.NodeID, "info", "node registered")
}

func (s *Store) Report(ctx context.Context, req ReportRequest, raw []byte) error {
	if req.NodeID == "" {
		return fmt.Errorf("node_id is required")
	}
	name := req.NodeName
	if name == "" {
		name = req.Hostname
	}
	if name == "" {
		name = req.NodeID
	}
	status := normalizeStatus(req.Status)
	now := nowString()
	redacted := string(RedactJSONBytes(raw))
	interval := req.IntervalSeconds
	if interval <= 0 {
		interval = 60
	}
	servicesJSON := jsonText(req.Services)
	summaryJSON := rawJSONText(req.Summary)
	doctorJSON := rawJSONText(req.Doctor)
	recentErrorsJSON := jsonText(reportErrors(req))
	oldStatus := "unknown"
	var oldLastSeen string
	var oldInterval int
	_ = s.db.QueryRowContext(ctx, `SELECT COALESCE(status, 'unknown'), COALESCE(last_seen, ''), COALESCE(interval_seconds, 0) FROM nodes WHERE node_id=?`, req.NodeID).Scan(&oldStatus, &oldLastSeen, &oldInterval)
	oldStatus = computedStatus(oldStatus, oldLastSeen, oldInterval)
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	_, err = tx.ExecContext(ctx, `INSERT INTO nodes
		(node_id, node_name, role, public_ip, lan_ip, easytier_ip, agent_version, core_version, status, health_score, interval_seconds, last_seen, services_json, summary_json, doctor_json, recent_errors_json, raw_json)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT(node_id) DO UPDATE SET
			node_name=excluded.node_name,
			role=excluded.role,
			public_ip=excluded.public_ip,
			lan_ip=excluded.lan_ip,
			easytier_ip=excluded.easytier_ip,
			agent_version=excluded.agent_version,
			core_version=excluded.core_version,
			status=excluded.status,
			health_score=excluded.health_score,
			interval_seconds=excluded.interval_seconds,
			last_seen=excluded.last_seen,
			services_json=excluded.services_json,
			summary_json=excluded.summary_json,
			doctor_json=excluded.doctor_json,
			recent_errors_json=excluded.recent_errors_json,
			raw_json=excluded.raw_json`,
		req.NodeID, name, normalizeRole(req.Role), req.PublicIP, req.PrimaryLANIP, req.EasyTierIP,
		req.AgentVersion, req.CoreVersion, status, req.HealthScore, interval, now, servicesJSON, summaryJSON, doctorJSON, recentErrorsJSON, redacted)
	if err != nil {
		return err
	}
	if _, err = tx.ExecContext(ctx, `INSERT INTO node_reports
		(node_id, status, health_score, interval_seconds, services_json, summary_json, doctor_json, recent_errors_json, raw_json, created_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		req.NodeID, status, req.HealthScore, interval, servicesJSON, summaryJSON, doctorJSON, recentErrorsJSON, redacted, now); err != nil {
		return err
	}
	if _, err = tx.ExecContext(ctx, `DELETE FROM entries WHERE node_id=?`, req.NodeID); err != nil {
		return err
	}
	for _, e := range req.Entries {
		rawEntry, _ := json.Marshal(e)
		if len(e.RawJSON) > 0 {
			rawEntry = e.RawJSON
		}
		_, err = tx.ExecContext(ctx, `INSERT INTO entries (node_id, name, listen_port, protocol, public_host, status, raw_json)
			VALUES (?, ?, ?, ?, ?, ?, ?)`, req.NodeID, e.Name, e.ListenPort, e.Protocol, e.PublicHost, e.Status, string(RedactJSONBytes(rawEntry)))
		if err != nil {
			return err
		}
	}
	if _, err = tx.ExecContext(ctx, `DELETE FROM forwards WHERE node_id=?`, req.NodeID); err != nil {
		return err
	}
	for _, f := range req.Forwards {
		rawForward, _ := json.Marshal(f)
		if len(f.RawJSON) > 0 {
			rawForward = f.RawJSON
		}
		_, err = tx.ExecContext(ctx, `INSERT INTO forwards (node_id, name, entry_name, target_host, target_port, protocol, status, raw_json)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?)`, req.NodeID, f.Name, f.EntryName, f.TargetHost, f.TargetPort, f.Protocol, f.Status, string(RedactJSONBytes(rawForward)))
		if err != nil {
			return err
		}
	}
	if err = tx.Commit(); err != nil {
		return err
	}
	if oldStatus != status {
		_ = s.AddEvent(ctx, req.NodeID, "info", fmt.Sprintf("node status changed: %s -> %s", oldStatus, status))
	}
	level := "info"
	if status == "degraded" || len(req.Errors) > 0 || len(req.RecentErrors) > 0 {
		level = "warn"
	}
	msg := "node report received"
	if len(req.Errors) > 0 || len(req.RecentErrors) > 0 {
		msg = "node report has collector warnings"
	}
	return s.AddEvent(ctx, req.NodeID, level, msg)
}

func (s *Store) AddEvent(ctx context.Context, nodeID, level, message string) error {
	_, err := s.db.ExecContext(ctx, `INSERT INTO events (node_id, level, message, created_at) VALUES (?, ?, ?, ?)`,
		nodeID, level, RedactString(message), nowString())
	return err
}

func computedStatus(status, lastSeen string, intervalSeconds int) string {
	if status == "" {
		status = "unknown"
	}
	if status == "unknown" {
		return status
	}
	threshold := 120 * time.Second
	if intervalSeconds > 0 {
		threshold = time.Duration(intervalSeconds*3) * time.Second
	}
	seen, err := time.Parse(time.RFC3339, lastSeen)
	if err != nil {
		return status
	}
	if time.Since(seen) > threshold {
		return "offline"
	}
	return status
}

func (s *Store) updateOfflineNodes(ctx context.Context) {
	nodes, err := s.listNodesRaw(ctx)
	if err != nil {
		return
	}
	for _, n := range nodes {
		effective := computedStatus(n.Status, n.LastSeen, n.IntervalSeconds)
		if effective == "offline" && n.Status != "offline" {
			if _, err := s.db.ExecContext(ctx, `UPDATE nodes SET status='offline' WHERE node_id=?`, n.NodeID); err == nil {
				_ = s.AddEvent(ctx, n.NodeID, "warn", fmt.Sprintf("node status changed: %s -> offline", n.Status))
			}
		}
	}
}

func (s *Store) ListNodes(ctx context.Context) ([]Node, error) {
	s.updateOfflineNodes(ctx)
	return s.listNodesRaw(ctx)
}

func (s *Store) listNodesRaw(ctx context.Context) ([]Node, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id, node_id, node_name, role, public_ip, lan_ip, easytier_ip, agent_version, core_version, COALESCE(status, 'unknown'), COALESCE(health_score, 0), COALESCE(interval_seconds, 0), COALESCE(last_seen, ''), COALESCE(services_json, '{}'), COALESCE(summary_json, 'null'), COALESCE(doctor_json, 'null'), COALESCE(recent_errors_json, '[]'), COALESCE(raw_json, '{}') FROM nodes ORDER BY last_seen DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Node{}
	for rows.Next() {
		var n Node
		var servicesJSON, summaryJSON, doctorJSON, errorsJSON string
		if err := rows.Scan(&n.ID, &n.NodeID, &n.NodeName, &n.Role, &n.PublicIP, &n.LANIP, &n.EasyTierIP, &n.AgentVersion, &n.CoreVersion, &n.Status, &n.HealthScore, &n.IntervalSeconds, &n.LastSeen, &servicesJSON, &summaryJSON, &doctorJSON, &errorsJSON, &n.RawJSON); err != nil {
			return nil, err
		}
		n.Status = computedStatus(n.Status, n.LastSeen, n.IntervalSeconds)
		n.Services = scanJSONMap(servicesJSON)
		n.Summary = json.RawMessage(summaryJSON)
		n.Doctor = json.RawMessage(doctorJSON)
		n.RecentErrors = scanStringSlice(errorsJSON)
		out = append(out, n)
	}
	return out, rows.Err()
}

func (s *Store) GetNode(ctx context.Context, id string) (Node, bool, error) {
	s.updateOfflineNodes(ctx)
	var n Node
	var servicesJSON, summaryJSON, doctorJSON, errorsJSON string
	err := s.db.QueryRowContext(ctx, `SELECT id, node_id, node_name, role, public_ip, lan_ip, easytier_ip, agent_version, core_version, COALESCE(status, 'unknown'), COALESCE(health_score, 0), COALESCE(interval_seconds, 0), COALESCE(last_seen, ''), COALESCE(services_json, '{}'), COALESCE(summary_json, 'null'), COALESCE(doctor_json, 'null'), COALESCE(recent_errors_json, '[]'), COALESCE(raw_json, '{}')
		FROM nodes WHERE node_id=? OR CAST(id AS TEXT)=?`, id, id).Scan(&n.ID, &n.NodeID, &n.NodeName, &n.Role, &n.PublicIP, &n.LANIP, &n.EasyTierIP, &n.AgentVersion, &n.CoreVersion, &n.Status, &n.HealthScore, &n.IntervalSeconds, &n.LastSeen, &servicesJSON, &summaryJSON, &doctorJSON, &errorsJSON, &n.RawJSON)
	if err == sql.ErrNoRows {
		return Node{}, false, nil
	}
	if err != nil {
		return Node{}, false, err
	}
	n.Status = computedStatus(n.Status, n.LastSeen, n.IntervalSeconds)
	n.Services = scanJSONMap(servicesJSON)
	n.Summary = json.RawMessage(summaryJSON)
	n.Doctor = json.RawMessage(doctorJSON)
	n.RecentErrors = scanStringSlice(errorsJSON)
	return n, true, nil
}

func (s *Store) ListEntries(ctx context.Context) ([]Entry, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id, node_id, name, listen_port, protocol, public_host, status, raw_json FROM entries ORDER BY node_id, name`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Entry{}
	for rows.Next() {
		var e Entry
		if err := rows.Scan(&e.ID, &e.NodeID, &e.Name, &e.ListenPort, &e.Protocol, &e.PublicHost, &e.Status, &e.RawJSON); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

func (s *Store) ListForwards(ctx context.Context) ([]Forward, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id, node_id, name, entry_name, target_host, target_port, protocol, status, raw_json FROM forwards ORDER BY node_id, name`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Forward{}
	for rows.Next() {
		var f Forward
		if err := rows.Scan(&f.ID, &f.NodeID, &f.Name, &f.EntryName, &f.TargetHost, &f.TargetPort, &f.Protocol, &f.Status, &f.RawJSON); err != nil {
			return nil, err
		}
		out = append(out, f)
	}
	return out, rows.Err()
}

func (s *Store) ListEvents(ctx context.Context, limit int) ([]Event, error) {
	if limit <= 0 || limit > 200 {
		limit = 100
	}
	rows, err := s.db.QueryContext(ctx, `SELECT id, node_id, level, message, created_at FROM events ORDER BY id DESC LIMIT ?`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Event{}
	for rows.Next() {
		var e Event
		if err := rows.Scan(&e.ID, &e.NodeID, &e.Level, &e.Message, &e.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

func (s *Store) ListNodeReports(ctx context.Context, nodeID string, limit int) ([]NodeReport, error) {
	if limit <= 0 || limit > 200 {
		limit = 100
	}
	rows, err := s.db.QueryContext(ctx, `SELECT id, node_id, COALESCE(status, 'unknown'), COALESCE(health_score, 0), COALESCE(interval_seconds, 0), COALESCE(services_json, '{}'), COALESCE(summary_json, 'null'), COALESCE(doctor_json, 'null'), COALESCE(recent_errors_json, '[]'), COALESCE(raw_json, '{}'), COALESCE(created_at, '')
		FROM node_reports WHERE node_id=? ORDER BY id DESC LIMIT ?`, nodeID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []NodeReport{}
	for rows.Next() {
		var r NodeReport
		var servicesJSON, summaryJSON, doctorJSON, errorsJSON string
		if err := rows.Scan(&r.ID, &r.NodeID, &r.Status, &r.HealthScore, &r.IntervalSeconds, &servicesJSON, &summaryJSON, &doctorJSON, &errorsJSON, &r.RawJSON, &r.CreatedAt); err != nil {
			return nil, err
		}
		r.Services = scanJSONMap(servicesJSON)
		r.Summary = json.RawMessage(summaryJSON)
		r.Doctor = json.RawMessage(doctorJSON)
		r.RecentErrors = scanStringSlice(errorsJSON)
		out = append(out, r)
	}
	return out, rows.Err()
}

func (s *Store) ListNodeEvents(ctx context.Context, nodeID string, limit int) ([]Event, error) {
	if limit <= 0 || limit > 200 {
		limit = 100
	}
	rows, err := s.db.QueryContext(ctx, `SELECT id, node_id, level, message, created_at FROM events WHERE node_id=? ORDER BY id DESC LIMIT ?`, nodeID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Event{}
	for rows.Next() {
		var e Event
		if err := rows.Scan(&e.ID, &e.NodeID, &e.Level, &e.Message, &e.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

func (s *Store) CreatePlan(ctx context.Context, req CreatePlanRequest) (Plan, error) {
	planType, err := normalizePlanType(req.Type)
	if err != nil {
		return Plan{}, err
	}
	title := RedactString(req.Title)
	if title == "" {
		title = planType
	}
	now := nowString()
	payload := rawPlanPayload(req.Payload)
	result, err := s.db.ExecContext(ctx, `INSERT INTO plans
		(type, title, status, execution_status, execution_note, manual_result, target_node_id, payload_json, generated_commands, command_groups, checklist, markdown, warnings, created_at, updated_at)
		VALUES (?, ?, 'draft', 'not_run', '', '', ?, ?, '[]', '[]', '[]', '', '[]', ?, ?)`,
		planType, title, RedactString(req.TargetNodeID), payload, now, now)
	if err != nil {
		return Plan{}, err
	}
	id, err := result.LastInsertId()
	if err != nil {
		return Plan{}, err
	}
	_ = s.AddEvent(ctx, req.TargetNodeID, "info", fmt.Sprintf("plan created: %s", planType))
	return s.GetPlan(ctx, id)
}

func (s *Store) ListPlans(ctx context.Context) ([]Plan, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id, type, title, status, COALESCE(execution_status, 'not_run'), COALESCE(execution_note, ''), COALESCE(manual_result, ''), target_node_id, COALESCE(payload_json, '{}'), COALESCE(generated_commands, '[]'), COALESCE(command_groups, '[]'), COALESCE(checklist, '[]'), COALESCE(markdown, ''), COALESCE(warnings, '[]'), created_at, updated_at FROM plans ORDER BY id DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanPlans(rows)
}

func (s *Store) GetPlan(ctx context.Context, id int64) (Plan, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id, type, title, status, COALESCE(execution_status, 'not_run'), COALESCE(execution_note, ''), COALESCE(manual_result, ''), target_node_id, COALESCE(payload_json, '{}'), COALESCE(generated_commands, '[]'), COALESCE(command_groups, '[]'), COALESCE(checklist, '[]'), COALESCE(markdown, ''), COALESCE(warnings, '[]'), created_at, updated_at FROM plans WHERE id=?`, id)
	if err != nil {
		return Plan{}, err
	}
	defer rows.Close()
	plans, err := scanPlans(rows)
	if err != nil {
		return Plan{}, err
	}
	if len(plans) == 0 {
		return Plan{}, sql.ErrNoRows
	}
	return plans[0], nil
}

func scanPlans(rows *sql.Rows) ([]Plan, error) {
	out := []Plan{}
	for rows.Next() {
		var p Plan
		var payload, commands, commandGroups, checklist, markdown, warnings string
		if err := rows.Scan(&p.ID, &p.Type, &p.Title, &p.Status, &p.ExecutionStatus, &p.ExecutionNote, &p.ManualResult, &p.TargetNodeID, &payload, &commands, &commandGroups, &checklist, &markdown, &warnings, &p.CreatedAt, &p.UpdatedAt); err != nil {
			return nil, err
		}
		p.PayloadJSON = json.RawMessage(RedactJSONBytes([]byte(payload)))
		p.GeneratedCommands = scanStringSlice(commands)
		p.CommandGroups = scanCommandGroups(commandGroups)
		p.Checklist = scanStringSlice(checklist)
		p.Markdown = RedactString(markdown)
		p.Warnings = scanStringSlice(warnings)
		p.ExecutionStatus = normalizeExecutionStatus(p.ExecutionStatus)
		p.ExecutionNote = RedactString(p.ExecutionNote)
		p.ManualResult = RedactString(p.ManualResult)
		out = append(out, p)
	}
	return out, rows.Err()
}

func (s *Store) GeneratePlan(ctx context.Context, id int64) (Plan, error) {
	return s.generatePlan(ctx, id, "plan generated")
}

func (s *Store) RegeneratePlan(ctx context.Context, id int64) (Plan, error) {
	return s.generatePlan(ctx, id, "plan regenerated")
}

func (s *Store) generatePlan(ctx context.Context, id int64, event string) (Plan, error) {
	plan, err := s.GetPlan(ctx, id)
	if err != nil {
		return Plan{}, err
	}
	artifacts := s.buildPlanArtifacts(ctx, plan)
	now := nowString()
	if _, err := s.db.ExecContext(ctx, `UPDATE plans SET status='generated', generated_commands=?, command_groups=?, checklist=?, markdown=?, warnings=?, updated_at=? WHERE id=?`,
		jsonText(artifacts.GeneratedCommands), jsonText(artifacts.CommandGroups), jsonText(artifacts.Checklist), RedactString(artifacts.Markdown), jsonText(artifacts.Warnings), now, id); err != nil {
		return Plan{}, err
	}
	_ = s.AddEvent(ctx, plan.TargetNodeID, "info", fmt.Sprintf("%s: %s", event, plan.Type))
	return s.GetPlan(ctx, id)
}

func (s *Store) MarkPlan(ctx context.Context, id int64, req MarkPlanRequest) (Plan, error) {
	status := normalizeExecutionStatus(req.ExecutionStatus)
	now := nowString()
	if _, err := s.db.ExecContext(ctx, `UPDATE plans SET execution_status=?, execution_note=?, manual_result=?, updated_at=? WHERE id=?`,
		status, redactManualText(req.ExecutionNote), redactManualText(req.ManualResult), now, id); err != nil {
		return Plan{}, err
	}
	plan, err := s.GetPlan(ctx, id)
	if err != nil {
		return Plan{}, err
	}
	_ = s.AddEvent(ctx, plan.TargetNodeID, "info", fmt.Sprintf("plan marked %s: %s", status, plan.Type))
	return plan, nil
}

func (s *Store) PlanMarkdown(ctx context.Context, id int64) (string, error) {
	plan, err := s.GetPlan(ctx, id)
	if err != nil {
		return "", err
	}
	if strings.TrimSpace(plan.Markdown) != "" {
		return RedactString(plan.Markdown), nil
	}
	return RedactString(s.buildPlanArtifacts(ctx, plan).Markdown), nil
}

func (s *Store) ArchivePlan(ctx context.Context, id int64) (Plan, error) {
	now := nowString()
	if _, err := s.db.ExecContext(ctx, `UPDATE plans SET status='archived', updated_at=? WHERE id=?`, now, id); err != nil {
		return Plan{}, err
	}
	plan, err := s.GetPlan(ctx, id)
	if err != nil {
		return Plan{}, err
	}
	_ = s.AddEvent(ctx, plan.TargetNodeID, "info", fmt.Sprintf("plan archived: %s", plan.Type))
	return plan, nil
}

func generatePlanCommands(plan Plan) ([]string, []string) {
	target := plan.TargetNodeID
	if target == "" {
		target = "target-node"
	}
	payload := map[string]any{}
	_ = json.Unmarshal(plan.PayloadJSON, &payload)
	commands := []string{
		fmt.Sprintf("# Leikwan Panel %s plan: %s", Version, plan.Title),
		"# beta.2 only generates a manual guide. Agents will not execute changes.",
		fmt.Sprintf("# On target node: %s", RedactString(target)),
		"lq status",
		"lq doctor",
	}
	warnings := []string{
		"beta.2 only generates a manual guide; nothing is executed by Controller or Agent.",
		"Run lq status and lq doctor on the target node before making changes.",
	}
	switch plan.Type {
	case "create_entry":
		commands = append(commands,
			"lq status --json",
			"# Manual step: open lq -> 快速组网 or 公网入口管理 to generate/paste the entry pairing code.",
			"# TODO: follow the current Leikwan Core interactive flow; no remote change is performed here.",
		)
	case "create_forward":
		commands = append(commands,
			"lq forward list",
			"# Manual step: open lq -> 利群主机 B -> 转发目标管理 -> 添加转发目标.",
			fmt.Sprintf("# Planned target_host: %s", payloadString(payload, "target_host")),
			fmt.Sprintf("# Planned target_port: %s", payloadString(payload, "target_port")),
			fmt.Sprintf("# Planned protocol: %s", payloadString(payload, "protocol")),
			"# TODO: run the matching lq forward add flow according to the current Core CLI/menu.",
		)
	case "switch_entry":
		warnings = append(warnings,
			"Switching entry may affect production traffic.",
			"Confirm snapshots and rollback path before doing anything manually.",
		)
		commands = append(commands,
			"lq ddns overview",
			"lq forward list",
			"# Manual step only: inspect current PRIMARY/BACKUP state in lq.",
			"# Do not switch during high traffic; confirm rollback path first.",
		)
	case "ddns_check":
		commands = append(commands,
			"lq ddns overview",
			"lq status --json",
			"lq doctor --json",
			"# Manual step: review DDNS consistency and relay restart warnings locally.",
		)
	}
	return redactStringSlice(commands), redactStringSlice(warnings)
}

type planArtifacts struct {
	GeneratedCommands []string
	CommandGroups     []CommandGroup
	Checklist         []string
	Markdown          string
	Warnings          []string
}

func scanCommandGroups(text string) []CommandGroup {
	out := []CommandGroup{}
	if text == "" || text == "null" {
		return out
	}
	_ = json.Unmarshal([]byte(text), &out)
	for i := range out {
		out[i].NodeID = RedactString(out[i].NodeID)
		out[i].NodeName = RedactString(out[i].NodeName)
		out[i].Role = normalizeRole(out[i].Role)
		out[i].Commands = redactStringSlice(out[i].Commands)
	}
	return out
}

func (s *Store) buildPlanArtifacts(ctx context.Context, plan Plan) planArtifacts {
	target := plan.TargetNodeID
	if target == "" {
		target = "target-node"
	}
	nodeID, nodeName, role := s.lookupNodeBrief(ctx, target)
	if nodeID == "" {
		nodeID = target
	}
	if nodeName == "" {
		nodeName = target
	}
	if role == "" {
		role = "unknown"
	}
	payload := map[string]any{}
	_ = json.Unmarshal(plan.PayloadJSON, &payload)
	commands := []string{
		fmt.Sprintf("# Leikwan Panel %s plan: %s", Version, RedactString(plan.Title)),
		"# This plan is manual-only. The agent will not execute it.",
		fmt.Sprintf("# On target node: %s", RedactString(nodeName)),
		"lq --version",
		"lq status",
		"lq doctor",
	}
	warnings := []string{
		"beta.2 only generates a manual execution guide; nothing is executed by Controller or Agent.",
		"Run lq status and lq doctor on the target node before making changes.",
	}
	checklist := baseChecklist()
	switch plan.Type {
	case "create_entry":
		commands = append(commands,
			"lq status --json",
			"# Manual step: open lq -> Quick setup or Public Entry A to generate/paste the entry pairing code.",
			"# TODO: follow the current Leikwan Core interactive flow; no remote change is performed here.",
		)
		checklist = append(checklist,
			"Confirm whether this is an A public entry node or B relay node before using pairing codes.",
			"Keep the return code visible until B confirms the entry is added.",
		)
	case "create_forward":
		commands = append(commands,
			"lq forward list",
			"# Manual step: open lq -> Relay Host B -> Forward Target Management -> Add forward target.",
			fmt.Sprintf("# Planned target_host: %s", payloadString(payload, "target_host")),
			fmt.Sprintf("# Planned target_port: %s", payloadString(payload, "target_port")),
			fmt.Sprintf("# Planned protocol: %s", payloadString(payload, "protocol")),
			"# TODO: run the matching lq forward add flow according to the current Core CLI/menu.",
		)
		checklist = append(checklist,
			"Confirm the entry port is unused before adding the forward.",
			"Confirm TCP/UDP expectations with the backend owner.",
		)
	case "switch_entry":
		warnings = append(warnings,
			"Switching entry may affect production traffic.",
			"Confirm snapshots and rollback path before doing anything manually.",
		)
		checklist = append(checklist,
			"Verify the new entry is online before any manual switch.",
			"Do not stop or remove the old entry first.",
			"Keep the old entry available for rollback if validation fails.",
			"Manually confirm a low-traffic maintenance window.",
		)
		commands = append(commands,
			"lq ddns overview",
			"lq forward list",
			"# Manual step only: inspect current PRIMARY/BACKUP state in lq.",
			"# Do not switch during high traffic; confirm rollback path first.",
		)
	case "ddns_check":
		commands = append(commands,
			"lq ddns overview",
			"lq status --json",
			"lq doctor --json",
			"# Manual step: review DDNS consistency and relay restart warnings locally.",
		)
	}
	group := CommandGroup{
		NodeID:   RedactString(nodeID),
		NodeName: RedactString(nodeName),
		Role:     normalizeRole(role),
		Commands: redactStringSlice(commands),
	}
	groups := []CommandGroup{group}
	checklist = redactStringSlice(checklist)
	warnings = redactStringSlice(warnings)
	return planArtifacts{
		GeneratedCommands: flattenCommandGroups(groups),
		CommandGroups:     groups,
		Checklist:         checklist,
		Markdown:          buildPlanMarkdown(plan, warnings, groups, checklist),
		Warnings:          warnings,
	}
}

func (s *Store) lookupNodeBrief(ctx context.Context, id string) (nodeID, nodeName, role string) {
	if id == "" {
		return "", "", ""
	}
	_ = s.db.QueryRowContext(ctx, `SELECT node_id, COALESCE(node_name, ''), COALESCE(role, 'unknown') FROM nodes WHERE node_id=? OR CAST(id AS TEXT)=?`, id, id).Scan(&nodeID, &nodeName, &role)
	return RedactString(nodeID), RedactString(nodeName), normalizeRole(role)
}

func baseChecklist() []string {
	return []string{
		"Confirm the target node and role.",
		"Run lq status before any manual change.",
		"Run lq doctor before any manual change.",
		"Confirm snapshot and rollback path.",
		"After manual execution, run lq status again.",
		"After manual execution, run lq doctor again.",
	}
}

func flattenCommandGroups(groups []CommandGroup) []string {
	out := []string{}
	for _, group := range groups {
		out = append(out, fmt.Sprintf("# On %s node: %s", normalizeRole(group.Role), RedactString(group.NodeName)))
		out = append(out, redactStringSlice(group.Commands)...)
	}
	return redactStringSlice(out)
}

func buildPlanMarkdown(plan Plan, warnings []string, groups []CommandGroup, checklist []string) string {
	var b strings.Builder
	b.WriteString("# Leikwan Plan Manual Execution Guide\n\n")
	b.WriteString("This plan is manual-only. The agent will not execute it.\n\n")
	b.WriteString(fmt.Sprintf("- Version: %s\n", Version))
	b.WriteString(fmt.Sprintf("- Plan: %s\n", RedactString(plan.Title)))
	b.WriteString(fmt.Sprintf("- Type: %s\n", RedactString(plan.Type)))
	b.WriteString(fmt.Sprintf("- Target node: %s\n", RedactString(plan.TargetNodeID)))
	b.WriteString(fmt.Sprintf("- Execution status: %s\n\n", normalizeExecutionStatus(plan.ExecutionStatus)))
	b.WriteString("## Warnings\n\n")
	if len(warnings) == 0 {
		b.WriteString("- None\n")
	} else {
		for _, warning := range warnings {
			b.WriteString(fmt.Sprintf("- %s\n", RedactString(warning)))
		}
	}
	b.WriteString("\n## Checklist\n\n")
	for _, item := range checklist {
		b.WriteString(fmt.Sprintf("- [ ] %s\n", RedactString(item)))
	}
	b.WriteString("\n## Commands\n\n")
	for _, group := range groups {
		b.WriteString(fmt.Sprintf("### %s (%s)\n\n", RedactString(group.NodeName), normalizeRole(group.Role)))
		b.WriteString("```bash\n")
		for _, cmd := range group.Commands {
			b.WriteString(RedactString(cmd))
			b.WriteByte('\n')
		}
		b.WriteString("```\n\n")
	}
	b.WriteString("## Payload\n\n")
	b.WriteString("```json\n")
	if len(plan.PayloadJSON) == 0 {
		b.WriteString("{}\n")
	} else {
		b.WriteString(string(RedactJSONBytes(plan.PayloadJSON)))
		b.WriteByte('\n')
	}
	b.WriteString("```\n")
	return RedactString(b.String())
}

func payloadString(payload map[string]any, key string) string {
	if v, ok := payload[key]; ok {
		return RedactString(fmt.Sprint(v))
	}
	return "-"
}

func redactStringSlice(in []string) []string {
	out := make([]string, 0, len(in))
	for _, item := range in {
		out = append(out, RedactString(item))
	}
	return out
}
