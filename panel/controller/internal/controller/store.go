package controller

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"net/netip"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

type Store struct {
	mu   sync.Mutex
	path string
	data StoreFile
}

func OpenStore(path string) (*Store, error) {
	s := &Store{path: path}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return nil, err
	}
	raw, err := os.ReadFile(path)
	if err == nil && len(raw) > 0 {
		if err := json.Unmarshal(raw, &s.data); err != nil {
			return nil, err
		}
	}
	return s, nil
}

func (s *Store) saveLocked() error {
	raw, err := json.MarshalIndent(s.data, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(s.path, raw, 0o644)
}

func newID() string {
	var b [8]byte
	_, _ = rand.Read(b[:])
	return hex.EncodeToString(b[:])
}

func randomSecret() string {
	var b [24]byte
	_, _ = rand.Read(b[:])
	return hex.EncodeToString(b[:])
}

func now() time.Time { return time.Now().UTC() }

func (s *Store) listNodes() []Node {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := append([]Node(nil), s.data.Nodes...)
	n := now()
	for i := range out {
		out[i] = applyNodeLiveness(out[i], n)
	}
	return out
}

func (s *Store) listNetworkProfiles() []NetworkProfile {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]NetworkProfile(nil), s.data.NetworkProfiles...)
}

func (s *Store) listNetworkLinks() []NetworkLink {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := append([]NetworkLink(nil), s.data.NetworkLinks...)
	nodes := append([]Node(nil), s.data.Nodes...)
	at := now()
	for i := range out {
		out[i] = s.decorateNetworkLinkLocked(out[i], nodes, at)
	}
	return out
}

func applyNodeLiveness(node Node, at time.Time) Node {
	node.Status, node.StatusReason = nodeStatusReason(node, at)
	return node
}

func nodeStatusReason(node Node, at time.Time) (string, string) {
	if node.OfflineAt != nil && (node.LastSeenAt.IsZero() || !node.LastSeenAt.After(*node.OfflineAt)) {
		if node.StatusReason != "" {
			return "offline", node.StatusReason
		}
		return "offline", "agent reported offline"
	}
	if node.LastSeenAt.IsZero() {
		return "offline", "no heartbeat received"
	}
	d := at.Sub(node.LastSeenAt)
	if d <= 90*time.Second {
		return "online", "recent heartbeat normal"
	}
	if d <= 5*time.Minute {
		return "stale", "heartbeat missing for over 90 seconds"
	}
	return "offline", "heartbeat missing for over 5 minutes"
}

func (s *Store) createNode(node Node) (Node, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if node.ID == "" {
		node.ID = newID()
	}
	for i := range s.data.Nodes {
		if s.data.Nodes[i].ID == node.ID {
			existing := s.data.Nodes[i]
			if node.Name != "" {
				existing.Name = node.Name
			}
			if node.Role != "" {
				existing.Role = node.Role
			}
			if node.Hostname != "" {
				existing.Hostname = node.Hostname
			}
			existing.Status = "online"
			existing.LastSeenAt = now()
			existing.UpdatedAt = existing.LastSeenAt
			existing.OfflineAt = nil
			existing.StatusReason = ""
			s.data.Nodes[i] = existing
			return existing, s.saveLocked()
		}
	}
	node.Status = "online"
	node.CreatedAt = now()
	node.UpdatedAt = node.CreatedAt
	s.data.Nodes = append(s.data.Nodes, node)
	return node, s.saveLocked()
}

func (s *Store) upsertReport(node Node) (Node, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i := range s.data.Nodes {
		if (node.ID != "" && s.data.Nodes[i].ID == node.ID) || (node.ID == "" && node.Name != "" && s.data.Nodes[i].Name == node.Name && s.data.Nodes[i].Hostname == node.Hostname) {
			node.ID = s.data.Nodes[i].ID
			node.CreatedAt = s.data.Nodes[i].CreatedAt
			node.UpdatedAt = now()
			node.OfflineAt = nil
			node.StatusReason = ""
			s.data.Nodes[i] = node
			return node, s.saveLocked()
		}
	}
	if node.ID == "" {
		node.ID = newID()
	}
	node.CreatedAt = now()
	node.UpdatedAt = node.CreatedAt
	s.data.Nodes = append(s.data.Nodes, node)
	return node, s.saveLocked()
}

func (s *Store) deleteNode(id string) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i := range s.data.Nodes {
		if s.data.Nodes[i].ID == id {
			s.data.Nodes = append(s.data.Nodes[:i], s.data.Nodes[i+1:]...)
			return true, s.saveLocked()
		}
	}
	return false, nil
}

func (s *Store) markNodeOffline(id, reason string) (Node, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i := range s.data.Nodes {
		if s.data.Nodes[i].ID == id {
			n := now()
			if strings.TrimSpace(reason) == "" {
				reason = "agent reported offline"
			}
			s.data.Nodes[i].Status = "offline"
			s.data.Nodes[i].StatusReason = reason
			s.data.Nodes[i].OfflineAt = &n
			s.data.Nodes[i].UpdatedAt = n
			return s.data.Nodes[i], true, s.saveLocked()
		}
	}
	return Node{}, false, nil
}

func (s *Store) createTask(t Task) (Task, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	t.ID = newID()
	t.CreatedAt = now()
	t.Status = "pending"
	t.ExpiresAt = defaultTaskExpiry()
	s.data.Tasks = append(s.data.Tasks, t)
	return t, s.saveLocked()
}

func (s *Store) tasksForNode(nodeID string) []Task {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := []Task{}
	for _, t := range s.data.Tasks {
		if t.NodeID == nodeID && t.Status == "pending" {
			out = append(out, t)
		}
	}
	return out
}

func (s *Store) listTasks(nodeID, status string) []Task {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := []Task{}
	for _, task := range s.data.Tasks {
		if nodeID != "" && task.NodeID != nodeID {
			continue
		}
		if status != "" && status != "all" && task.Status != status {
			continue
		}
		out = append(out, task)
	}
	return out
}

func (s *Store) updateTaskResult(id string, req map[string]any) (Task, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i := range s.data.Tasks {
		if s.data.Tasks[i].ID == id {
			t := &s.data.Tasks[i]
			n := now()
			t.StartedAt = &n
			t.FinishedAt = &n
			t.Status = stringValue(req["status"], "failed")
			t.Result = capText(stringValue(req["result"], ""))
			t.Stdout = capText(stringValue(req["stdout"], stringValue(req["result_stdout"], "")))
			t.Stderr = capText(stringValue(req["stderr"], stringValue(req["result_stderr"], "")))
			t.Error = capText(stringValue(req["error"], ""))
			switch t.Action {
			case "apply_forward_config", "verify_forward_rules":
				s.updateForwardStatusForTaskLocked(*t)
			case "verify_network_connectivity":
				s.updateNetworkLinkStatusForTaskLocked(*t)
			}
			return *t, true, s.saveLocked()
		}
	}
	return Task{}, false, nil
}

func (s *Store) updateForwardStatusForTaskLocked(task Task) {
	forwardID := forwardIDFromTaskPayload(task.Payload)
	if forwardID == "" {
		return
	}
	status := "failed"
	if task.Status == "succeeded" && task.Action == "apply_forward_config" {
		status = "applied"
	} else if task.Status == "succeeded" && task.Action == "verify_forward_rules" {
		status = "verified"
	}
	for i := range s.data.Forwards {
		if s.data.Forwards[i].ID != forwardID {
			continue
		}
		s.data.Forwards[i].Status = status
		if task.Action == "verify_forward_rules" {
			s.data.Forwards[i].LastVerifyTaskID = task.ID
		} else {
			s.data.Forwards[i].LastApplyTaskID = task.ID
		}
		s.data.Forwards[i].UpdatedAt = now()
		return
	}
}

func (s *Store) updateNetworkLinkStatusForTaskLocked(task Task) {
	linkID := stringValue(task.Payload["network_link_id"], "")
	if linkID == "" {
		return
	}
	result := map[string]any{}
	if strings.TrimSpace(task.Result) != "" {
		_ = json.Unmarshal([]byte(task.Result), &result)
	}
	status := "failed"
	reason := firstString(task.Error, stringValue(result["reason"], ""), stringValue(result["network_reason"], ""))
	networkOK := boolValue(result["network_ok"]) || boolValue(result["NetworkOK"])
	peerCount := intValue(result["peer_count"])
	if task.Status == "succeeded" && (networkOK || peerCount > 0) {
		status = "active"
		reason = "network connectivity verified"
	}
	for i := range s.data.NetworkLinks {
		if s.data.NetworkLinks[i].ID != linkID {
			continue
		}
		n := now()
		s.data.NetworkLinks[i].Status = status
		s.data.NetworkLinks[i].StatusReason = reason
		s.data.NetworkLinks[i].LastVerifyAt = n
		s.data.NetworkLinks[i].UpdatedAt = n
		if latency := floatValue(result["best_latency_ms"]); latency > 0 {
			s.data.NetworkLinks[i].BestLatencyMS = latency
		}
		if loss := stringValue(result["packet_loss"], ""); loss != "" && loss != "-" {
			s.data.NetworkLinks[i].PacketLoss = loss
		}
		if tunnels := stringListValue(result["tunnels"]); len(tunnels) > 0 {
			s.data.NetworkLinks[i].Tunnels = tunnels
		}
		if routeType := stringValue(result["route_type"], ""); routeType != "" {
			s.data.NetworkLinks[i].RouteType = routeType
		}
		if mode := stringValue(task.Payload["target_mode"], ""); mode == "entry" {
			s.data.NetworkLinks[i].EntryPeerCount = peerCount
		} else if mode == "backend" {
			s.data.NetworkLinks[i].BackendPeerCount = peerCount
		}
		return
	}
}

func forwardIDFromTaskPayload(payload map[string]any) string {
	for _, key := range []string{"forward_rule", "rule"} {
		raw, ok := payload[key]
		if !ok {
			continue
		}
		if item, ok := raw.(Forward); ok {
			return item.ID
		}
		if item, ok := raw.(map[string]any); ok {
			return stringValue(item["id"], "")
		}
		data, _ := json.Marshal(raw)
		var item Forward
		if err := json.Unmarshal(data, &item); err == nil && item.ID != "" {
			return item.ID
		}
	}
	return stringValue(payload["forward_id"], "")
}

func (s *Store) listForwards() []Forward {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]Forward(nil), s.data.Forwards...)
}

func (s *Store) getForward(id string) (Forward, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, forward := range s.data.Forwards {
		if forward.ID == id {
			return forward, true
		}
	}
	return Forward{}, false
}

func (s *Store) createForward(req map[string]any) (Forward, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	item, err := forwardFromRequest(req, nil)
	if err != nil {
		return Forward{}, err
	}
	item.ID = newID()
	n := now()
	item.CreatedAt = n
	item.UpdatedAt = n
	item.Status = "draft"
	s.data.Forwards = append(s.data.Forwards, item)
	return item, s.saveLocked()
}

func (s *Store) updateForward(id string, req map[string]any) (Forward, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i := range s.data.Forwards {
		if s.data.Forwards[i].ID != id {
			continue
		}
		item, err := forwardFromRequest(req, &s.data.Forwards[i])
		if err != nil {
			return Forward{}, true, err
		}
		item.ID = s.data.Forwards[i].ID
		item.CreatedAt = s.data.Forwards[i].CreatedAt
		item.UpdatedAt = now()
		s.data.Forwards[i] = item
		return item, true, s.saveLocked()
	}
	return Forward{}, false, nil
}

func (s *Store) deleteForward(id string) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i := range s.data.Forwards {
		if s.data.Forwards[i].ID == id {
			s.data.Forwards = append(s.data.Forwards[:i], s.data.Forwards[i+1:]...)
			return true, s.saveLocked()
		}
	}
	return false, nil
}

func (s *Store) updateForwardTask(id, taskID, field, status string) (Forward, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i := range s.data.Forwards {
		if s.data.Forwards[i].ID != id {
			continue
		}
		switch field {
		case "apply":
			s.data.Forwards[i].LastApplyTaskID = taskID
		case "verify":
			s.data.Forwards[i].LastVerifyTaskID = taskID
		}
		if status != "" {
			s.data.Forwards[i].Status = status
		}
		s.data.Forwards[i].UpdatedAt = now()
		return s.data.Forwards[i], true, s.saveLocked()
	}
	return Forward{}, false, nil
}

func (s *Store) updateForwardResolvedTarget(id, target string) (Forward, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	target = normalizeHostIP(target)
	for i := range s.data.Forwards {
		if s.data.Forwards[i].ID != id {
			continue
		}
		s.data.Forwards[i].TargetIP = target
		s.data.Forwards[i].TargetHost = target
		s.data.Forwards[i].UpdatedAt = now()
		return s.data.Forwards[i], true, s.saveLocked()
	}
	return Forward{}, false, nil
}

func (s *Store) getNetworkProfile(id string) (NetworkProfile, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, profile := range s.data.NetworkProfiles {
		if profile.ID == id {
			return profile, true
		}
	}
	return NetworkProfile{}, false
}

func (s *Store) createNetworkProfile(req map[string]any) (NetworkProfile, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	name := stringValue(req["name"], "")
	if name == "" {
		return NetworkProfile{}, errValidation("name is required")
	}
	n := now()
	item := NetworkProfile{ID: newID(), Name: name, NetworkName: stringValue(req["network_name"], "edge-net"), NetworkSecret: stringValue(req["network_secret"], randomSecret()), CIDR: stringValue(req["cidr"], "10.144.0.0/16"), ProtocolPreference: stringValue(req["protocol_preference"], "auto"), Listeners: defaultListeners(stringListValue(req["listeners"])), Peers: stringListValue(req["peers"]), CreatedAt: n, UpdatedAt: n}
	s.data.NetworkProfiles = append(s.data.NetworkProfiles, item)
	return item, s.saveLocked()
}

func (s *Store) createNetworkLink(link NetworkLink) (NetworkLink, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if link.ID == "" {
		link.ID = newID()
	}
	n := now()
	link.CreatedAt = n
	link.UpdatedAt = n
	if link.Status == "" {
		link.Status = "pending"
	}
	s.data.NetworkLinks = append(s.data.NetworkLinks, link)
	return s.decorateNetworkLinkLocked(link, s.data.Nodes, n), s.saveLocked()
}

func (s *Store) getNetworkLink(id string) (NetworkLink, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, link := range s.data.NetworkLinks {
		if link.ID == id {
			return s.decorateNetworkLinkLocked(link, s.data.Nodes, now()), true
		}
	}
	return NetworkLink{}, false
}

func (s *Store) deleteNetworkLink(id string) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i := range s.data.NetworkLinks {
		if s.data.NetworkLinks[i].ID == id {
			s.data.NetworkLinks = append(s.data.NetworkLinks[:i], s.data.NetworkLinks[i+1:]...)
			return true, s.saveLocked()
		}
	}
	return false, nil
}

func (s *Store) updateNetworkLinkTasks(id, entryTaskID, backendTaskID string, verified bool) (NetworkLink, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i := range s.data.NetworkLinks {
		if s.data.NetworkLinks[i].ID != id {
			continue
		}
		if entryTaskID != "" {
			s.data.NetworkLinks[i].EntryTaskID = entryTaskID
		}
		if backendTaskID != "" {
			s.data.NetworkLinks[i].BackendTaskID = backendTaskID
		}
		if verified {
			s.data.NetworkLinks[i].LastVerifyAt = now()
			s.data.NetworkLinks[i].Status = "verifying"
			s.data.NetworkLinks[i].StatusReason = "connectivity verification tasks created"
		} else {
			s.data.NetworkLinks[i].Status = "applying"
			s.data.NetworkLinks[i].StatusReason = "network profile apply tasks created"
		}
		s.data.NetworkLinks[i].UpdatedAt = now()
		return s.decorateNetworkLinkLocked(s.data.NetworkLinks[i], s.data.Nodes, now()), true, s.saveLocked()
	}
	return NetworkLink{}, false, nil
}

func (s *Store) updateNetworkLinkStatus(id, status, reason string) (NetworkLink, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i := range s.data.NetworkLinks {
		if s.data.NetworkLinks[i].ID != id {
			continue
		}
		s.data.NetworkLinks[i].Status = status
		s.data.NetworkLinks[i].StatusReason = reason
		s.data.NetworkLinks[i].UpdatedAt = now()
		return s.decorateNetworkLinkLocked(s.data.NetworkLinks[i], s.data.Nodes, now()), true, s.saveLocked()
	}
	return NetworkLink{}, false, nil
}

func (s *Store) decorateNetworkLinkLocked(link NetworkLink, nodes []Node, at time.Time) NetworkLink {
	var entry, backend *Node
	for i := range nodes {
		node := applyNodeLiveness(nodes[i], at)
		if node.ID == link.EntryNodeID {
			entry = &node
		}
		if node.ID == link.BackendNodeID {
			backend = &node
		}
	}
	storedStatus := link.Status
	storedReason := link.StatusReason
	link.Status = firstString(storedStatus, "pending")
	link.StatusReason = storedReason
	if entry != nil && entry.EasyTierPeerCount > 0 {
		link.EntryPeerCount = entry.EasyTierPeerCount
	}
	if backend != nil && backend.EasyTierPeerCount > 0 {
		link.BackendPeerCount = backend.EasyTierPeerCount
	}
	if entry != nil && backend != nil {
		link.BestLatencyMS = firstPositive(entry.EasyTierBestLatencyMS, backend.EasyTierBestLatencyMS, link.BestLatencyMS)
		link.PacketLoss = firstString(entry.EasyTierPacketLoss, backend.EasyTierPacketLoss, link.PacketLoss)
		link.Tunnels = firstStringList(entry.EasyTierTunnels, backend.EasyTierTunnels, link.Tunnels)
		link.RouteType = firstString(entry.EasyTierRouteType, backend.EasyTierRouteType)
		if entry.EasyTierStatus == "active" && backend.EasyTierStatus == "active" && (entry.EasyTierNetworkOK || backend.EasyTierNetworkOK || entry.EasyTierPeerCount > 0 || backend.EasyTierPeerCount > 0) {
			link.Status = "active"
			link.StatusReason = "network connectivity verified by node reports"
		} else if entry.EasyTierStatus == "active" || backend.EasyTierStatus == "active" {
			if storedStatus != "disabled" && storedStatus != "applying" && storedStatus != "verifying" && storedStatus != "failed" {
				link.Status = "partial"
				link.StatusReason = "one side of EasyTier is active"
			}
		} else if storedStatus == "" || storedStatus == "connected" || storedStatus == "partial" {
			link.Status = "pending"
			link.StatusReason = "waiting for EasyTier status"
		}
	}
	return link
}

func (s *Store) updateNetworkProfile(id string, req map[string]any) (NetworkProfile, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i := range s.data.NetworkProfiles {
		if s.data.NetworkProfiles[i].ID != id {
			continue
		}
		item := s.data.NetworkProfiles[i]
		if value := stringValue(req["name"], item.Name); value != "" {
			item.Name = value
		}
		item.NetworkName = stringValue(req["network_name"], item.NetworkName)
		item.NetworkSecret = stringValue(req["network_secret"], item.NetworkSecret)
		item.CIDR = stringValue(req["cidr"], item.CIDR)
		item.ProtocolPreference = stringValue(req["protocol_preference"], item.ProtocolPreference)
		if listeners, ok := req["listeners"]; ok {
			item.Listeners = defaultListeners(stringListValue(listeners))
		}
		if peers, ok := req["peers"]; ok {
			item.Peers = stringListValue(peers)
		}
		item.UpdatedAt = now()
		s.data.NetworkProfiles[i] = item
		return item, true, s.saveLocked()
	}
	return NetworkProfile{}, false, nil
}

func defaultListeners(listeners []string) []string {
	if len(listeners) == 0 {
		return []string{"tcp://0.0.0.0:11010", "udp://0.0.0.0:11010"}
	}
	return listeners
}

func (s *Store) deleteNetworkProfile(id string) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i := range s.data.NetworkProfiles {
		if s.data.NetworkProfiles[i].ID == id {
			s.data.NetworkProfiles = append(s.data.NetworkProfiles[:i], s.data.NetworkProfiles[i+1:]...)
			return true, s.saveLocked()
		}
	}
	return false, nil
}

func (s *Store) getNode(id string) (Node, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, node := range s.data.Nodes {
		if node.ID == id {
			return applyNodeLiveness(node, now()), true
		}
	}
	return Node{}, false
}

type validationError string

func (e validationError) Error() string  { return string(e) }
func errValidation(message string) error { return validationError(message) }

func firstPositive(values ...float64) float64 {
	for _, value := range values {
		if value > 0 {
			return value
		}
	}
	return 0
}

func firstString(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}

func normalizeHostIP(value string) string {
	text := strings.TrimSpace(value)
	if text == "" {
		return ""
	}
	if prefix, err := netip.ParsePrefix(text); err == nil {
		return prefix.Addr().String()
	}
	if addr, err := netip.ParseAddr(text); err == nil {
		return addr.String()
	}
	return text
}

func firstStringList(values ...[]string) []string {
	for _, value := range values {
		if len(value) > 0 {
			return append([]string(nil), value...)
		}
	}
	return nil
}

func forwardFromRequest(req map[string]any, existing *Forward) (Forward, error) {
	item := Forward{Enabled: true, Protocol: "tcp", ListenHost: "0.0.0.0", TargetHostSource: "backend_easytier_ip", TargetNodeIPSource: "easytier_ip", Status: "draft"}
	if existing != nil {
		item = *existing
	}
	item.NetworkLinkID = stringValue(req["network_link_id"], item.NetworkLinkID)
	if value := stringValue(req["name"], item.Name); value != "" {
		item.Name = value
	}
	item.EntryID = stringValue(req["entry_id"], item.EntryID)
	item.EntryNodeID = stringValue(req["entry_node_id"], item.EntryNodeID)
	item.BackendNodeID = stringValue(req["backend_node_id"], stringValue(req["target_node_id"], item.BackendNodeID))
	item.Protocol = strings.ToLower(stringValue(req["protocol"], item.Protocol))
	item.ListenHost = stringValue(req["listen_host"], item.ListenHost)
	if port := intValue(req["listen_port"]); port != 0 {
		item.ListenPort = port
	}
	item.TargetHostSource = normalizeTargetHostSource(stringValue(req["target_host_source"], stringValue(req["target_node_ip_source"], item.TargetHostSource)))
	item.ManualTargetHost = stringValue(req["manual_target_host"], item.ManualTargetHost)
	item.TargetIP = normalizeHostIP(stringValue(req["target_ip"], stringValue(req["target_host"], item.TargetIP)))
	if item.TargetIP == "" && item.TargetHostSource == "manual" {
		item.TargetIP = normalizeHostIP(item.ManualTargetHost)
	}
	if port := intValue(req["target_port"]); port != 0 {
		item.TargetPort = port
	}
	item.TargetNodeIPSource = stringValue(req["target_node_ip_source"], item.TargetNodeIPSource)
	item.Remark = stringValue(req["remark"], item.Remark)
	if value, ok := req["enabled"]; ok {
		item.Enabled = boolValue(value)
	}
	item.TargetMode = stringValue(req["target_mode"], item.TargetMode)
	item.TargetNodeID = stringValue(req["target_node_id"], item.TargetNodeID)
	item.TargetHost = normalizeHostIP(item.TargetIP)
	if item.Name == "" {
		return Forward{}, errValidation("name is required")
	}
	if !validForwardProtocol(item.Protocol) {
		return Forward{}, errValidation("protocol must be tcp, udp, or both")
	}
	if item.EntryNodeID == "" {
		return Forward{}, errValidation("entry_node_id is required")
	}
	if item.BackendNodeID == "" {
		return Forward{}, errValidation("backend_node_id is required")
	}
	if !validPort(item.ListenPort) {
		return Forward{}, errValidation("listen_port must be 1-65535")
	}
	if !validPort(item.TargetPort) {
		return Forward{}, errValidation("target_port must be 1-65535")
	}
	if item.ListenHost == "" {
		item.ListenHost = "0.0.0.0"
	}
	if item.TargetNodeIPSource == "" {
		item.TargetNodeIPSource = "easytier_ip"
	}
	if item.TargetHostSource == "" {
		item.TargetHostSource = "backend_easytier_ip"
	}
	return item, nil
}

func validForwardProtocol(protocol string) bool {
	switch strings.ToLower(strings.TrimSpace(protocol)) {
	case "tcp", "udp", "both":
		return true
	default:
		return false
	}
}

func validPort(port int) bool { return port >= 1 && port <= 65535 }

func stringListValue(value any) []string {
	switch list := value.(type) {
	case []string:
		return append([]string(nil), list...)
	case []any:
		out := make([]string, 0, len(list))
		for _, item := range list {
			if text, ok := item.(string); ok && text != "" {
				out = append(out, text)
			}
		}
		return out
	case string:
		if list == "" {
			return nil
		}
		return []string{list}
	default:
		return nil
	}
}
