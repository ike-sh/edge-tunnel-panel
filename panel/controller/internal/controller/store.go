package controller

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"net"
	"net/netip"
	"os"
	"path/filepath"
	"strconv"
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
			case "apply_forward_config", "apply_entry_forward_config", "apply_landing_forward_config", "verify_forward_rules", "verify_entry_forward_rules", "verify_landing_forward_rules":
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
	for i := range s.data.Forwards {
		if s.data.Forwards[i].ID != forwardID {
			continue
		}
		stage := stringValue(task.Payload["stage"], "")
		if task.Action == "apply_entry_forward_config" || stage == "entry" {
			if task.Status == "succeeded" {
				s.data.Forwards[i].EntryStageStatus = "succeeded"
			} else {
				s.data.Forwards[i].EntryStageStatus = "failed"
			}
			s.data.Forwards[i].LastApplyEntryTaskID = task.ID
			s.data.Forwards[i].LastApplyTaskID = task.ID
		} else if task.Action == "apply_landing_forward_config" || stage == "landing" {
			if task.Status == "succeeded" {
				s.data.Forwards[i].LandingStageStatus = "succeeded"
			} else {
				s.data.Forwards[i].LandingStageStatus = "failed"
			}
			s.data.Forwards[i].LastApplyLandingTaskID = task.ID
			s.data.Forwards[i].LastApplyTaskID = task.ID
		} else if strings.HasPrefix(task.Action, "verify_") {
			s.data.Forwards[i].LastVerifyTaskID = task.ID
			if task.Status == "succeeded" {
				s.data.Forwards[i].Status = "verified"
			} else {
				s.data.Forwards[i].Status = "failed"
			}
		} else if task.Action == "apply_forward_config" {
			if task.Status == "succeeded" {
				s.data.Forwards[i].EntryStageStatus = "succeeded"
				s.data.Forwards[i].LandingStageStatus = "succeeded"
				s.data.Forwards[i].Status = "applied"
			} else {
				s.data.Forwards[i].Status = "failed"
			}
			s.data.Forwards[i].LastApplyTaskID = task.ID
		}
		if task.Action == "apply_entry_forward_config" || task.Action == "apply_landing_forward_config" {
			entryOK := s.data.Forwards[i].EntryStageStatus == "succeeded"
			landingOK := s.data.Forwards[i].LandingStageStatus == "succeeded"
			entryFailed := s.data.Forwards[i].EntryStageStatus == "failed"
			landingFailed := s.data.Forwards[i].LandingStageStatus == "failed"
			switch {
			case entryOK && landingOK:
				s.data.Forwards[i].Status = "applied"
			case entryFailed || landingFailed:
				s.data.Forwards[i].Status = "failed"
			default:
				s.data.Forwards[i].Status = "applying"
			}
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

func pbrIDFromTaskPayload(payload map[string]any) string {
	for _, key := range []string{"pbr_policy", "policy"} {
		raw, ok := payload[key]
		if !ok {
			continue
		}
		if item, ok := raw.(PBRPolicy); ok {
			return item.ID
		}
		if item, ok := raw.(map[string]any); ok {
			return stringValue(item["id"], "")
		}
		data, _ := json.Marshal(raw)
		var item PBRPolicy
		if err := json.Unmarshal(data, &item); err == nil && item.ID != "" {
			return item.ID
		}
	}
	return stringValue(payload["policy_id"], stringValue(payload["pbr_policy_id"], ""))
}

func (s *Store) updatePBRStatusForTaskLocked(task Task) {
	policyID := pbrIDFromTaskPayload(task.Payload)
	if policyID == "" {
		return
	}
	for i := range s.data.PBRPolicies {
		if s.data.PBRPolicies[i].ID != policyID {
			continue
		}
		switch task.Action {
		case "apply_pbr_policy":
			s.data.PBRPolicies[i].LastApplyTaskID = task.ID
			if task.Status == "succeeded" {
				s.data.PBRPolicies[i].Status = "applied"
			} else {
				s.data.PBRPolicies[i].Status = "failed"
			}
		case "verify_pbr_policy":
			s.data.PBRPolicies[i].LastVerifyTaskID = task.ID
			verified := false
			if task.Status == "succeeded" {
				result := map[string]any{}
				_ = json.Unmarshal([]byte(task.Result), &result)
				verified = boolValue(result["verified"])
			}
			if verified {
				s.data.PBRPolicies[i].Status = "verified"
			} else {
				s.data.PBRPolicies[i].Status = "failed"
			}
		case "disable_pbr_policy":
			if task.Status == "succeeded" {
				s.data.PBRPolicies[i].Status = "disabled"
				s.data.PBRPolicies[i].Enabled = false
			} else {
				s.data.PBRPolicies[i].Status = "failed"
			}
		}
		s.data.PBRPolicies[i].UpdatedAt = now()
		return
	}
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
		case "entry_apply":
			s.data.Forwards[i].LastApplyEntryTaskID = taskID
			s.data.Forwards[i].EntryStageStatus = "pending"
		case "landing_apply":
			s.data.Forwards[i].LastApplyLandingTaskID = taskID
			s.data.Forwards[i].LandingStageStatus = "pending"
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
		s.data.Forwards[i].TunnelTargetHost = target
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
	applyMSSDefaults(&link)
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
	item := Forward{Enabled: true, Protocol: "tcp", PublicListenHost: "0.0.0.0", ListenHost: "0.0.0.0", TransportMode: "easytier", Status: "draft"}
	if existing != nil {
		item = *existing
	}
	item.NetworkLinkID = stringValue(req["network_link_id"], item.NetworkLinkID)
	if value := stringValue(req["name"], item.Name); value != "" {
		item.Name = value
	}
	item.EntryID = stringValue(req["entry_id"], item.EntryID)
	item.EntryNodeID = stringValue(req["entry_node_id"], item.EntryNodeID)
	item.LandingNodeID = stringValue(req["landing_node_id"], stringValue(req["backend_node_id"], stringValue(req["target_node_id"], item.LandingNodeID)))
	item.BackendNodeID = item.LandingNodeID
	item.Protocol = strings.ToLower(stringValue(req["protocol"], item.Protocol))
	item.PublicListenHost = stringValue(req["public_listen_host"], stringValue(req["listen_host"], item.PublicListenHost))
	item.ListenHost = item.PublicListenHost
	if port := intValue(req["public_listen_port"]); port != 0 {
		item.PublicListenPort = port
	} else if port := intValue(req["listen_port"]); port != 0 {
		item.PublicListenPort = port
	}
	item.ListenPort = item.PublicListenPort
	item.TransportMode = normalizeTransportMode(stringValue(req["transport_mode"], item.TransportMode))
	item.TunnelTargetHost = normalizeHostIP(stringValue(req["tunnel_target_host"], item.TunnelTargetHost))
	if port := intValue(req["tunnel_target_port"]); port != 0 {
		item.TunnelTargetPort = port
	}
	if item.TunnelTargetPort == 0 {
		item.TunnelTargetPort = item.PublicListenPort
	}
	item.LandingHostRaw = strings.TrimSpace(stringValue(req["landing_host_raw"], stringValue(req["landing_host"], stringValue(req["target_host"], item.LandingHostRaw))))
	item.LandingHostResolved = normalizeHostIP(stringValue(req["landing_host_resolved"], item.LandingHostResolved))
	if port := intValue(req["landing_port"]); port != 0 {
		item.LandingPort = port
	} else if port := intValue(req["target_port"]); port != 0 {
		item.LandingPort = port
	}
	item.TargetPort = item.LandingPort
	item.TargetIP = item.TunnelTargetHost
	item.TargetHost = item.TunnelTargetHost
	item.Remark = stringValue(req["remark"], item.Remark)
	if value, ok := req["enabled"]; ok {
		item.Enabled = boolValue(value)
	}
	item.TargetMode = stringValue(req["target_mode"], item.TargetMode)
	item.TargetNodeID = stringValue(req["target_node_id"], item.TargetNodeID)
	if item.Name == "" {
		return Forward{}, errValidation("name is required")
	}
	if !validForwardProtocol(item.Protocol) {
		return Forward{}, errValidation("protocol must be tcp, udp, or both")
	}
	if item.EntryNodeID == "" {
		return Forward{}, errValidation("entry_node_id is required")
	}
	if item.LandingNodeID == "" {
		return Forward{}, errValidation("landing_node_id is required")
	}
	if !validPort(item.PublicListenPort) {
		return Forward{}, errValidation("public_listen_port must be 1-65535")
	}
	if !validPort(item.LandingPort) {
		return Forward{}, errValidation("landing_port must be 1-65535")
	}
	if item.LandingHostRaw == "" {
		return Forward{}, errValidation("landing_host is required")
	}
	if item.TransportMode != "easytier" && item.TransportMode != "public" {
		return Forward{}, errValidation("transport_mode must be easytier or public")
	}
	if strings.Contains(item.LandingHostRaw, "/") {
		return Forward{}, errValidation("landing_host must not be CIDR")
	}
	if addr, err := netip.ParseAddr(item.LandingHostRaw); err == nil && addr.Is6() {
		return Forward{}, errValidation("v0.3.0-ui-test does not support IPv6 landing targets")
	}
	if item.PublicListenHost == "" {
		item.PublicListenHost = "0.0.0.0"
	}
	item.ListenHost = item.PublicListenHost
	item.ListenPort = item.PublicListenPort
	item.TargetPort = item.LandingPort
	item.BackendNodeID = item.LandingNodeID
	item.TargetIP = item.TunnelTargetHost
	item.TargetHost = item.TunnelTargetHost
	item.TargetNodeIPSource = ""
	return item, nil
}

func normalizeTransportMode(mode string) string {
	switch strings.TrimSpace(strings.ToLower(mode)) {
	case "", "easytier", "tunnel":
		return "easytier"
	case "public":
		return "public"
	default:
		return strings.TrimSpace(strings.ToLower(mode))
	}
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

func (s *Store) listPBRPolicies() []PBRPolicy {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]PBRPolicy(nil), s.data.PBRPolicies...)
}

func (s *Store) getPBRPolicy(id string) (PBRPolicy, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, policy := range s.data.PBRPolicies {
		if policy.ID == id {
			return policy, true
		}
	}
	return PBRPolicy{}, false
}

func (s *Store) createPBRPolicy(req map[string]any) (PBRPolicy, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	policy, err := s.pbrPolicyFromRequestLocked(req, nil)
	if err != nil {
		return PBRPolicy{}, err
	}
	policy.ID = newID()
	n := now()
	policy.CreatedAt = n
	policy.UpdatedAt = n
	if policy.Status == "" {
		policy.Status = "draft"
	}
	s.data.PBRPolicies = append(s.data.PBRPolicies, policy)
	return policy, s.saveLocked()
}

func (s *Store) updatePBRPolicy(id string, req map[string]any) (PBRPolicy, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i := range s.data.PBRPolicies {
		if s.data.PBRPolicies[i].ID != id {
			continue
		}
		policy, err := s.pbrPolicyFromRequestLocked(req, &s.data.PBRPolicies[i])
		if err != nil {
			return PBRPolicy{}, true, err
		}
		policy.ID = s.data.PBRPolicies[i].ID
		policy.CreatedAt = s.data.PBRPolicies[i].CreatedAt
		policy.UpdatedAt = now()
		s.data.PBRPolicies[i] = policy
		return policy, true, s.saveLocked()
	}
	return PBRPolicy{}, false, nil
}

func (s *Store) deletePBRPolicy(id string) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i := range s.data.PBRPolicies {
		if s.data.PBRPolicies[i].ID == id {
			s.data.PBRPolicies = append(s.data.PBRPolicies[:i], s.data.PBRPolicies[i+1:]...)
			return true, s.saveLocked()
		}
	}
	return false, nil
}

func (s *Store) updatePBRTask(id, taskID, field, status string) (PBRPolicy, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i := range s.data.PBRPolicies {
		if s.data.PBRPolicies[i].ID != id {
			continue
		}
		if field == "apply" {
			s.data.PBRPolicies[i].LastApplyTaskID = taskID
		}
		if field == "verify" {
			s.data.PBRPolicies[i].LastVerifyTaskID = taskID
		}
		if status != "" {
			s.data.PBRPolicies[i].Status = status
		}
		s.data.PBRPolicies[i].UpdatedAt = now()
		return s.data.PBRPolicies[i], true, s.saveLocked()
	}
	return PBRPolicy{}, false, nil
}

func (s *Store) pbrPolicyFromRequestLocked(req map[string]any, existing *PBRPolicy) (PBRPolicy, error) {
	policy := PBRPolicy{Enabled: true, SourceType: "forward", Protocol: "tcp", Status: "draft", MSSClampEnabled: true, MTU: 1380}
	if existing != nil {
		policy = *existing
	}
	if value := stringValue(req["name"], policy.Name); value != "" {
		policy.Name = value
	}
	policy.NodeID = stringValue(req["node_id"], policy.NodeID)
	policy.SourceType = normalizePBRSourceType(stringValue(req["source_type"], policy.SourceType))
	policy.ForwardRuleID = stringValue(req["forward_rule_id"], policy.ForwardRuleID)
	policy.Domain = stringValue(req["domain"], policy.Domain)
	policy.StaticDstCIDR = stringValue(req["static_dst_cidr"], policy.StaticDstCIDR)
	policy.Protocol = strings.ToLower(stringValue(req["protocol"], policy.Protocol))
	if value := intValue(req["match_port"]); value != 0 {
		policy.MatchPort = value
	}
	policy.MatchDstHost = stringValue(req["match_dst_host"], policy.MatchDstHost)
	if value := intValue(req["match_dst_port"]); value != 0 {
		policy.MatchDstPort = value
	}
	policy.MatchSrcHost = stringValue(req["match_src_host"], policy.MatchSrcHost)
	policy.MatchMarkComment = stringValue(req["match_mark_comment"], policy.MatchMarkComment)
	policy.RouteGroupName = stringValue(req["route_group_name"], policy.RouteGroupName)
	policy.RouteGroupGateway = stringValue(req["route_group_gateway"], policy.RouteGroupGateway)
	policy.RouteGroupTableName = stringValue(req["route_group_table_name"], policy.RouteGroupTableName)
	policy.RouteGroupMatchedIP = stringValue(req["route_group_matched_ip"], policy.RouteGroupMatchedIP)
	if value := intValue(req["route_group_table_id"]); value != 0 {
		policy.RouteGroupTableID = value
	}
	policy.EgressInterface = stringValue(req["egress_interface"], stringValue(req["out_interface"], policy.EgressInterface))
	policy.EgressGateway = stringValue(req["egress_gateway"], stringValue(req["gateway"], policy.EgressGateway))
	policy.EgressSourceIP = stringValue(req["egress_source_ip"], policy.EgressSourceIP)
	if value := intValue(req["table_id"]); value != 0 {
		policy.TableID = value
	}
	policy.FWMark = stringValue(req["fwmark"], stringValue(req["match_mark"], policy.FWMark))
	if value := intValue(req["priority"]); value != 0 {
		policy.Priority = value
	}
	if _, ok := req["mss_clamp_enabled"]; ok {
		policy.MSSClampEnabled = boolValue(req["mss_clamp_enabled"])
	}
	if value := intValue(req["mss_value"]); value != 0 {
		policy.MSSValue = value
	}
	if value := intValue(req["mtu"]); value != 0 {
		policy.MTU = value
	}
	policy.Remark = stringValue(req["remark"], policy.Remark)
	if value, ok := req["enabled"]; ok {
		policy.Enabled = boolValue(value)
	}
	if policy.ForwardRuleID != "" && policy.SourceType == "forward" {
		forward, found := findForwardLocked(s.data.Forwards, policy.ForwardRuleID)
		if !found {
			return PBRPolicy{}, errValidation("forward_rule_id not found")
		}
		if policy.NodeID == "" {
			policy.NodeID = forward.LandingNodeID
		}
		if policy.MatchPort == 0 {
			policy.MatchPort = firstNonZero(forward.TunnelTargetPort, forward.PublicListenPort)
		}
		if policy.MatchDstHost == "" {
			policy.MatchDstHost = firstString(forward.LandingHostResolved, forward.LandingHostRaw)
		}
		if policy.MatchDstPort == 0 {
			policy.MatchDstPort = forward.LandingPort
		}
		if policy.Protocol == "" {
			policy.Protocol = forward.Protocol
		}
	}
	if policy.NodeID == "" {
		return PBRPolicy{}, errValidation("node_id is required")
	}
	if _, found := findNodeLocked(s.data.Nodes, policy.NodeID); !found {
		return PBRPolicy{}, errValidation("node_id not found")
	}
	if policy.Name == "" {
		policy.Name = "pbr-" + policy.NodeID
	}
	if policy.SourceType == "forward" && policy.ForwardRuleID == "" {
		return PBRPolicy{}, errValidation("forward_rule_id is required for forward source")
	}
	if policy.SourceType == "forward" {
		forward, found := findForwardLocked(s.data.Forwards, policy.ForwardRuleID)
		if !found {
			return PBRPolicy{}, errValidation("forward_rule_id not found")
		}
		if forward.LandingNodeID != policy.NodeID {
			return PBRPolicy{}, errValidation("PBR must be applied on the forward rule landing node")
		}
	}
	if policy.RouteGroupName == "" {
		return PBRPolicy{}, errValidation("route_group_name is required")
	}
	if policy.RouteGroupGateway == "" {
		return PBRPolicy{}, errValidation("route_group_gateway is required")
	}
	if ip := net.ParseIP(policy.RouteGroupGateway); ip == nil || ip.To4() == nil {
		return PBRPolicy{}, errValidation("route_group_gateway must be IPv4")
	}
	if policy.RouteGroupTableID == 0 {
		return PBRPolicy{}, errValidation("route_group_table_id is required")
	}
	if policy.RouteGroupTableName == "" {
		policy.RouteGroupTableName = "T_" + policy.RouteGroupName
	}
	if !validRouteTableName(policy.RouteGroupTableName) {
		return PBRPolicy{}, errValidation("route_group_table_name must start with T_ and contain only letters, numbers, underscore, or dash")
	}
	if !validForwardProtocol(policy.Protocol) {
		return PBRPolicy{}, errValidation("protocol must be tcp, udp, or both")
	}
	if policy.MatchPort != 0 && !validPort(policy.MatchPort) {
		return PBRPolicy{}, errValidation("match_port must be 1-65535")
	}
	if policy.MatchDstPort != 0 && !validPort(policy.MatchDstPort) {
		return PBRPolicy{}, errValidation("match_dst_port must be 1-65535")
	}
	if policy.TableID == 0 {
		policy.TableID = policy.RouteGroupTableID
	}
	if policy.Priority == 0 {
		policy.Priority = nextPBRNumberLocked(s.data.PBRPolicies, 20000, func(p PBRPolicy) int { return p.Priority })
	}
	if policy.FWMark == "" {
		policy.FWMark = nextPBRMarkLocked(s.data.PBRPolicies)
	}
	policy.MatchSource = policy.MatchSrcHost
	policy.MatchDst = policy.MatchDstHost
	policy.MatchProtocol = policy.Protocol
	policy.MatchMark = policy.FWMark
	policy.EgressGateway = policy.RouteGroupGateway
	policy.Gateway = policy.RouteGroupGateway
	policy.OutInterface = policy.EgressInterface
	return policy, nil
}

func validRouteTableName(value string) bool {
	if !strings.HasPrefix(value, "T_") {
		return false
	}
	for _, r := range value {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '_' || r == '-' {
			continue
		}
		return false
	}
	return true
}

func findForwardLocked(forwards []Forward, id string) (Forward, bool) {
	for _, f := range forwards {
		if f.ID == id {
			return f, true
		}
	}
	return Forward{}, false
}
func findNodeLocked(nodes []Node, id string) (Node, bool) {
	for _, n := range nodes {
		if n.ID == id {
			return n, true
		}
	}
	return Node{}, false
}
func (s *Store) hasActivePBRPolicy(nodeID, exceptID string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return hasActivePBRPolicyLocked(s.data.PBRPolicies, nodeID, exceptID)
}
func hasActivePBRPolicyLocked(policies []PBRPolicy, nodeID, exceptID string) bool {
	for _, p := range policies {
		if p.ID != exceptID && p.NodeID == nodeID && p.Enabled && (p.Status == "applying" || p.Status == "applied" || p.Status == "verified") {
			return true
		}
	}
	return false
}
func nextPBRNumberLocked(policies []PBRPolicy, start int, pick func(PBRPolicy) int) int {
	candidate := start
	used := map[int]bool{}
	for _, p := range policies {
		if v := pick(p); v != 0 {
			used[v] = true
		}
	}
	for used[candidate] {
		candidate++
	}
	return candidate
}
func nextPBRMarkLocked(policies []PBRPolicy) string {
	candidate := 0x2000
	used := map[string]bool{}
	for _, p := range policies {
		used[strings.ToLower(p.FWMark)] = true
	}
	for used[strings.ToLower(hexMark(candidate))] {
		candidate++
	}
	return hexMark(candidate)
}
func hexMark(value int) string { return "0x" + strconv.FormatInt(int64(value), 16) }
func normalizePBRSourceType(value string) string {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "domain", "static":
		return strings.ToLower(strings.TrimSpace(value))
	default:
		return "forward"
	}
}
func applyMSSDefaults(link *NetworkLink) {
	if link.MTU == 0 {
		link.MTU = 1380
	}
	if link.MSSMode == "" {
		link.MSSMode = "auto"
	}
	link.MSSMode = normalizeMSSMode(link.MSSMode)
	if link.MSSMode != "disabled" && !link.MSSClampEnabled {
		link.MSSClampEnabled = true
	}
}
func normalizeMSSMode(value string) string {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "fixed", "disabled":
		return strings.ToLower(strings.TrimSpace(value))
	default:
		return "auto"
	}
}
func intValueWithFallback(v any, fallback int) int {
	if value := intValue(v); value != 0 {
		return value
	}
	return fallback
}
func firstNonZero(values ...int) int {
	for _, v := range values {
		if v != 0 {
			return v
		}
	}
	return 0
}
