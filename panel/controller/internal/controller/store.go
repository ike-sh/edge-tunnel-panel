package controller

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
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
			last_seen TEXT,
			raw_json TEXT
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
	}
	for _, stmt := range stmts {
		if _, err := s.db.ExecContext(ctx, stmt); err != nil {
			return err
		}
	}
	return nil
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
			status=excluded.status,
			last_seen=excluded.last_seen,
			raw_json=excluded.raw_json`,
		req.NodeID, name, normalizeRole(req.Role), "online", now, redacted)
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
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	_, err = tx.ExecContext(ctx, `INSERT INTO nodes
		(node_id, node_name, role, public_ip, lan_ip, easytier_ip, agent_version, core_version, status, health_score, last_seen, raw_json)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
			last_seen=excluded.last_seen,
			raw_json=excluded.raw_json`,
		req.NodeID, name, normalizeRole(req.Role), req.PublicIP, req.PrimaryLANIP, req.EasyTierIP,
		req.AgentVersion, req.CoreVersion, status, req.HealthScore, now, redacted)
	if err != nil {
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
	level := "info"
	if status == "degraded" || len(req.Errors) > 0 {
		level = "warn"
	}
	msg := "node report received"
	if len(req.Errors) > 0 {
		msg = "node report has collector warnings"
	}
	return s.AddEvent(ctx, req.NodeID, level, msg)
}

func (s *Store) AddEvent(ctx context.Context, nodeID, level, message string) error {
	_, err := s.db.ExecContext(ctx, `INSERT INTO events (node_id, level, message, created_at) VALUES (?, ?, ?, ?)`,
		nodeID, level, RedactString(message), nowString())
	return err
}

func (s *Store) ListNodes(ctx context.Context) ([]Node, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id, node_id, node_name, role, public_ip, lan_ip, easytier_ip, agent_version, core_version, status, health_score, last_seen, raw_json FROM nodes ORDER BY last_seen DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Node
	for rows.Next() {
		var n Node
		if err := rows.Scan(&n.ID, &n.NodeID, &n.NodeName, &n.Role, &n.PublicIP, &n.LANIP, &n.EasyTierIP, &n.AgentVersion, &n.CoreVersion, &n.Status, &n.HealthScore, &n.LastSeen, &n.RawJSON); err != nil {
			return nil, err
		}
		out = append(out, n)
	}
	return out, rows.Err()
}

func (s *Store) GetNode(ctx context.Context, id string) (Node, bool, error) {
	var n Node
	err := s.db.QueryRowContext(ctx, `SELECT id, node_id, node_name, role, public_ip, lan_ip, easytier_ip, agent_version, core_version, status, health_score, last_seen, raw_json
		FROM nodes WHERE node_id=? OR CAST(id AS TEXT)=?`, id, id).Scan(&n.ID, &n.NodeID, &n.NodeName, &n.Role, &n.PublicIP, &n.LANIP, &n.EasyTierIP, &n.AgentVersion, &n.CoreVersion, &n.Status, &n.HealthScore, &n.LastSeen, &n.RawJSON)
	if err == sql.ErrNoRows {
		return Node{}, false, nil
	}
	if err != nil {
		return Node{}, false, err
	}
	return n, true, nil
}

func (s *Store) ListEntries(ctx context.Context) ([]Entry, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id, node_id, name, listen_port, protocol, public_host, status, raw_json FROM entries ORDER BY node_id, name`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Entry
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
	var out []Forward
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
	var out []Event
	for rows.Next() {
		var e Event
		if err := rows.Scan(&e.ID, &e.NodeID, &e.Level, &e.Message, &e.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}
