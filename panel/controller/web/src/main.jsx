import React, { useEffect, useMemo, useState } from 'react';
import { createRoot } from 'react-dom/client';
import './styles.css';

const TOKEN_KEY = 'edgeTunnelOperatorToken';
const API_BASE_KEY = 'edgeTunnelApiBase';
const DEFAULT_VERSION = 'v0.2.9-test';

const tabs = [
  ['dashboard', '总览'],
  ['nodes', '节点'],
  ['networks', '组网配置'],
  ['forwards', '转发规则'],
  ['pbr', '出口策略 / PBR'],
  ['tasks', '任务'],
  ['settings', '设置'],
];

const readActions = [
  'run_node_preflight',
  'collect_agent_status',
  'verify_agent_config',
  'verify_easytier_status',
  'verify_network_connectivity',
  'verify_forward_rules',
  'verify_pbr_rules',
  'detect_network_interfaces',
  'detect_mtu_status',
  'verify_ddns_status',
];
const writeActions = ['install_or_update_easytier', 'restart_easytier', 'restart_agent'];
const easyTierActions = ['install_or_update_easytier', 'apply_network_profile', 'verify_easytier_status', 'verify_network_connectivity', 'restart_easytier', 'detect_mtu_status'];
const forwardingActions = ['apply_forward_config', 'apply_entry_forward_config', 'apply_landing_forward_config', 'verify_forward_rules', 'verify_entry_forward_rules', 'verify_landing_forward_rules'];
const pbrActions = ['detect_network_interfaces', 'apply_pbr_policy', 'verify_pbr_policy', 'disable_pbr_policy', 'verify_pbr_rules'];

const actionLabels = {
  run_node_preflight: '节点预检',
  collect_agent_status: '状态检查',
  verify_agent_config: '验证 Agent 配置',
  verify_easytier_status: '验证 EasyTier 状态',
  verify_network_connectivity: '验证组网',
  verify_forward_rules: '验证转发规则',
  verify_pbr_rules: '验证出口策略',
  detect_network_interfaces: '识别网卡',
  detect_mtu_status: '检测 MTU/MSS',
  verify_ddns_status: '验证 DDNS',
  install_or_update_easytier: '安装/更新 EasyTier',
  apply_network_profile: '应用组网配置',
  apply_entry_config: '应用公网入口',
  apply_forward_config: '应用转发规则',
  apply_entry_forward_config: '应用入口转发',
  apply_landing_forward_config: '应用落地转发',
  apply_pbr_config: '应用出口策略',
  apply_pbr_policy: '应用出口策略',
  verify_pbr_policy: '验证出口策略',
  disable_pbr_policy: '禁用出口策略',
  apply_ddns_config: '应用 DDNS',
  reload_firewall_rules: '重载防火墙规则',
  restart_easytier: '重启 EasyTier',
  restart_agent: '重启 Agent',
  reboot_node: '重启服务器',
};

const statusLabels = {
  online: '在线',
  stale: '可能离线',
  offline: '离线',
  pending: '等待中',
  running: '执行中',
  succeeded: '成功',
  failed: '失败',
  expired: '已过期',
  cancelled: '已取消',
  active: '运行中',
  inactive: '未运行',
  missing_binary: '未安装',
  missing_config: '缺少配置',
  service_missing: '服务缺失',
  connected: '组网成功',
  partial: '部分异常',
  waiting: '等待验证',
  applying: '应用中',
  verifying: '验证中',
  disabled: '已禁用',
  draft: '草稿',
  applied: '已应用',
  verified: '已验证',
};

function browserControllerURL() {
  return typeof window === 'undefined' ? 'http://CONTROLLER_HOST:18080' : `${window.location.protocol}//${window.location.host}`;
}
function normalizeBase(value) { return String(value || '').trim().replace(/\/+$/, ''); }
function normalizeHostIP(value) {
  const text = String(value || '').trim();
  const slash = text.indexOf('/');
  return slash > 0 ? text.slice(0, slash) : text;
}
function safeList(value) { return Array.isArray(value) ? value : []; }
function shortID(value) { const text = String(value || ''); return text ? text.slice(0, 16) : '-'; }
function labelStatus(value) { return statusLabels[value] || value || '-'; }
function statusClass(value) { return `badge ${value || 'unknown'}`; }
function actionLabel(action) { return actionLabels[action] || action || '-'; }
function lines(value) { return String(value || '').split(/\r?\n/).map((item) => item.trim()).filter(Boolean); }
function formatTime(value) {
  if (!value) return '-';
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? '-' : date.toLocaleString();
}
function timeAgo(value) {
  if (!value) return '-';
  const seconds = Math.max(0, Math.floor((Date.now() - new Date(value).getTime()) / 1000));
  if (!Number.isFinite(seconds)) return '-';
  if (seconds < 60) return `${seconds} 秒前`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes} 分钟前`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours} 小时前`;
  return `${Math.floor(hours / 24)} 天前`;
}
function pretty(value) {
  if (value === undefined || value === null || value === '') return '-';
  if (typeof value !== 'string') return JSON.stringify(value, null, 2);
  try { return JSON.stringify(JSON.parse(value), null, 2); } catch { return value; }
}
function parseJSON(value) {
  try { return typeof value === 'string' ? JSON.parse(value) : (value || {}); } catch { return {}; }
}
function nodeLabel(node) { return node ? `${node.name || node.id || '-'} / ${shortID(node.id)}` : '-'; }
function nodeOptionLabel(node) {
  return node ? `${node.name || node.id} / ${node.public_ip || node.observed_ip || '-'} / ${labelStatus(node.easytier_status)}` : '-';
}
function networkStatusText(node) {
  if (node?.easytier_network_ok) return '组网成功';
  if (Number(node?.easytier_peer_count || 0) > 0) return 'Peer 已连接';
  if (node?.easytier_status === 'active') return '未发现 Peer';
  return labelStatus(node?.easytier_status);
}
function linkStatusText(link) {
  if (link?.status === 'active' || link?.status === 'connected') return '组网成功';
  if (link?.status === 'applying') return '应用中';
  if (link?.status === 'verifying') return '验证中';
  if (link?.status === 'failed') return '组网失败';
  if (link?.status === 'disabled') return '已禁用';
  if (link?.status === 'partial') return '部分异常';
  return '等待验证';
}
function cleanLoss(value) {
  const text = String(value || '').trim();
  return /^\d+(?:\.\d+)?%$/.test(text) ? text : '-';
}
function cleanTunnels(value) {
  const list = safeList(value)
    .flatMap((item) => String(item || '').split(','))
    .map((item) => item.trim())
    .filter((item) => /^(tcp|udp|tcp6|udp6|wg|ws|wss)$/i.test(item) || item.includes('://'));
  return [...new Set(list)];
}
function displayTunnels(value) {
  const list = cleanTunnels(value);
  return list.length ? list.join(',') : '-';
}
function displayLatency(value) {
  const n = Number(value || 0);
  return n > 0 ? `${n} ms` : '-';
}
function displayRoute(value, networkOK = false) {
  const text = String(value || '').trim();
  if (!text || text === 'unknown') return networkOK ? '待识别' : '-';
  return text;
}
function linkNodeNames(link, nodeMap) {
  const entry = nodeMap[link?.entry_node_id];
  const backend = nodeMap[link?.backend_node_id];
  return `${entry?.name || link?.entry_node_id || '-'} → ${backend?.name || link?.backend_node_id || '-'}`;
}
function linkOptionLabel(link, nodeMap) {
  return `${link.name || link.network_name || 'edge-net'}：${linkNodeNames(link, nodeMap)}，${linkStatusText(link)}，延迟 ${displayLatency(link.best_latency_ms)}`;
}
function transportModeLabel(value) { return value === 'public' ? 'B 公网直连' : 'EasyTier 隧道'; }
function publicIP(node) { return node?.public_ip || node?.observed_ip || '-'; }
function landingHost(rule) { return rule?.landing_host_raw || rule?.landing_host || rule?.landing_host_resolved || '-'; }
function ruleListenPort(rule) { return rule?.public_listen_port || rule?.listen_port || '-'; }
function ruleLandingPort(rule) { return rule?.landing_port || rule?.target_port || '-'; }
function randomSecret() {
  const bytes = new Uint8Array(18);
  if (window.crypto?.getRandomValues) {
    window.crypto.getRandomValues(bytes);
    return Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('');
  }
  return Math.random().toString(36).slice(2) + Date.now().toString(36);
}
async function copyText(text) {
  if (!text) return false;
  if (navigator.clipboard?.writeText) {
    try { await navigator.clipboard.writeText(text); return true; } catch {}
  }
  const textarea = document.createElement('textarea');
  textarea.value = text;
  textarea.style.position = 'fixed';
  textarea.style.left = '-9999px';
  document.body.appendChild(textarea);
  textarea.focus();
  textarea.select();
  let ok = false;
  try { ok = document.execCommand('copy'); } finally { document.body.removeChild(textarea); }
  return ok;
}

function App() {
  const [activeTab, setActiveTab] = useState('dashboard');
  const [token, setToken] = useState(() => localStorage.getItem(TOKEN_KEY) || '');
  const [apiBase, setApiBase] = useState(() => localStorage.getItem(API_BASE_KEY) || '');
  const [alert, setAlert] = useState(null);
  const [loading, setLoading] = useState(false);
  const [health, setHealth] = useState(null);
  const [nodes, setNodes] = useState([]);
  const [tasks, setTasks] = useState([]);
  const [networkLinks, setNetworkLinks] = useState([]);
  const [networkProfiles, setNetworkProfiles] = useState([]);
  const [forwards, setForwards] = useState([]);
  const [pbrPolicies, setPBRPolicies] = useState([]);
  const [showAddAgent, setShowAddAgent] = useState(false);
  const [openNodeActions, setOpenNodeActions] = useState('');
  const [expandedTask, setExpandedTask] = useState('');
  const [agentForm, setAgentForm] = useState({ controller_url: browserControllerURL(), node_name: 'edge-node-1', version: DEFAULT_VERSION, enable_tasks: true, enable_write_actions: true });
  const [agentCommand, setAgentCommand] = useState({ root: '', sudo: '' });
  const [quickForm, setQuickForm] = useState({ name: 'edge-net', network_name: 'edge-net', network_secret: '', cidr: '10.144.0.0/16', port: 11010, mtu: 1380, mss_clamp_enabled: true, mss_mode: 'auto', mss_value: '', entry_node_id: '', backend_node_id: '', tcp: true, udp: true, showAdvanced: false, listeners: 'tcp://0.0.0.0:11010\nudp://0.0.0.0:11010', peers: '' });
  const [forwardForm, setForwardForm] = useState({ network_link_id: '', name: '', protocol: 'tcp', public_listen_port: '', landing_host: '', landing_port: '', transport_mode: 'easytier', enabled: true, remark: '', showAdvanced: false });
  const [pbrForm, setPBRForm] = useState({ node_id: '', forward_rule_id: '', name: '', egress_interface: '', egress_gateway: '', source_type: 'forward', enabled: true });
  const [taskFilter, setTaskFilter] = useState('all');
  const [taskNodeFilter, setTaskNodeFilter] = useState('all');
  const [taskEasyTierOnly, setTaskEasyTierOnly] = useState(false);

  const strictAuth = health?.strict_auth !== false;
  const onlineNodes = nodes.filter((node) => node.status === 'online');
  const nodeMap = useMemo(() => Object.fromEntries(nodes.map((node) => [node.id, node])), [nodes]);
  const counts = useMemo(() => ({
    online: nodes.filter((node) => node.status === 'online').length,
    stale: nodes.filter((node) => node.status === 'stale').length,
    offline: nodes.filter((node) => node.status === 'offline').length,
    failed: tasks.filter((task) => task.status === 'failed').length,
  }), [nodes, tasks]);

  async function api(path, options = {}) {
    const method = options.method || (options.body === undefined ? 'GET' : 'POST');
    const headers = { Accept: 'application/json' };
    if (options.body !== undefined) headers['Content-Type'] = 'application/json';
    if (token) headers.Authorization = `Bearer ${token}`;
    const response = await fetch(`${normalizeBase(apiBase)}/api/v1${path}`, {
      method,
      headers,
      body: options.body === undefined ? undefined : JSON.stringify(options.body),
    });
    const payload = await response.json().catch(() => null);
    if (!response.ok || payload?.ok === false) throw new Error(payload?.error?.message || `${response.status} ${response.statusText}`);
    return payload?.data ?? payload;
  }
  async function run(label, fn) {
    setLoading(true);
    setAlert(null);
    try {
      const result = await fn();
      setAlert({ type: 'success', message: `${label}成功` });
      return result;
    } catch (error) {
      setAlert({ type: 'error', message: error.message || String(error) });
      return null;
    } finally {
      setLoading(false);
    }
  }
  async function refreshHealth() { const data = await api('/health'); setHealth(data); return data; }
  async function refreshNodes() { const data = safeList(await api('/nodes')); setNodes(data); return data; }
  async function refreshTasks() { const data = safeList(await api('/tasks')); setTasks(data); return data; }
  async function refreshNetworkLinks() { const data = safeList(await api('/network-links')); setNetworkLinks(data); return data; }
  async function refreshNetworkProfiles() { const data = safeList(await api('/network-profiles')); setNetworkProfiles(data); return data; }
  async function refreshForwards() { const data = safeList(await api('/forwards')); setForwards(data); return data; }
  async function refreshPBRPolicies() { const data = safeList(await api('/pbr-policies')); setPBRPolicies(data); return data; }
  async function refreshAll() {
    const h = await refreshHealth();
    if (token || h.strict_auth === false) await Promise.all([refreshNodes(), refreshTasks(), refreshNetworkLinks(), refreshNetworkProfiles(), refreshForwards(), refreshPBRPolicies()]);
  }

  useEffect(() => { run('加载数据', refreshAll); }, []);
  useEffect(() => {
    const timer = window.setInterval(() => refreshNodes().catch(() => {}), 15000);
    return () => window.clearInterval(timer);
  }, [apiBase, token]);

  async function generateAgentCommand() {
    const data = await run('生成一键命令', async () => api('/bootstrap/agent-install-command', {
      body: {
        controller_url: agentForm.controller_url,
        node_name: agentForm.node_name,
        version: agentForm.version || DEFAULT_VERSION,
        role: 'node',
        enable_tasks: agentForm.enable_tasks,
        enable_write_actions: agentForm.enable_write_actions,
        show_full_token: true,
      },
    }));
    if (data) setAgentCommand({ root: data.root_command || data.recommended_command || data.full_command || '', sudo: data.sudo_command || '' });
  }
  async function copyCommand(kind, text) {
    if (!text) { setAlert({ type: 'error', message: '请先生成一键命令' }); return; }
    const ok = await copyText(text);
    setAlert(ok ? { type: 'success', message: `已复制 ${kind} 一键命令` } : { type: 'error', message: '复制失败，请手动选中命令复制' });
  }
  async function createNodeTask(nodeID, action) {
    await run(actionLabel(action), async () => api('/tasks', { body: { node_id: nodeID, action, payload: {} } }));
    await refreshTasks();
  }
  async function deleteNode(node) {
    if (!window.confirm('仅删除主控面板中的节点记录，不会卸载远端 Agent。\n如果远端 Agent 仍在运行，该节点会在下一次心跳后重新出现。\n确认删除？')) return;
    await run('删除节点记录', async () => api(`/nodes/${encodeURIComponent(node.id)}`, { method: 'DELETE' }));
    setOpenNodeActions('');
    await Promise.all([refreshNodes(), refreshTasks()]);
  }
  function scheduleLinkVerify(link) {
    if (!link?.id) return;
    window.setTimeout(async () => {
      await run('自动验证组网', async () => api(`/network-links/${encodeURIComponent(link.id)}/verify`, { body: {} }));
      await Promise.all([refreshNetworkLinks(), refreshTasks(), refreshNodes()]);
    }, 20000);
  }
  async function quickApplyNetwork() {
    const entryNode = nodeMap[quickForm.entry_node_id];
    const backendNode = nodeMap[quickForm.backend_node_id];
    if (!entryNode || !backendNode) { setAlert({ type: 'error', message: '请选择入口节点和后端节点' }); return; }
    if (entryNode.id === backendNode.id) { setAlert({ type: 'error', message: '入口节点和后端节点不能相同' }); return; }
    if (!entryNode.public_ip && !entryNode.observed_ip) { setAlert({ type: 'error', message: '入口节点缺少公网 IP，无法生成后端 peers' }); return; }
    const protocols = [];
    if (quickForm.tcp) protocols.push('tcp');
    if (quickForm.udp) protocols.push('udp');
    if (protocols.length === 0) { setAlert({ type: 'error', message: '请至少选择 TCP 或 UDP' }); return; }
    const data = await run('创建并应用组网', async () => api('/network-links/quick-apply', {
      body: {
        name: quickForm.name,
        network_name: quickForm.network_name,
        network_secret: quickForm.network_secret,
        cidr: quickForm.cidr,
        port: Number(quickForm.port || 11010),
        mtu: Number(quickForm.mtu || 1380),
        mss_clamp_enabled: quickForm.mss_clamp_enabled,
        mss_mode: quickForm.mss_mode,
        mss_value: Number(quickForm.mss_value || 0),
        entry_node_id: quickForm.entry_node_id,
        backend_node_id: quickForm.backend_node_id,
        protocols,
        listeners: quickForm.showAdvanced ? lines(quickForm.listeners) : undefined,
        peers: quickForm.showAdvanced ? lines(quickForm.peers) : undefined,
      },
    }));
    if (data) {
      setAlert({ type: 'success', message: '已创建入口和后端组网任务。系统将在约 20 秒后自动验证组网。' });
      await Promise.all([refreshNetworkLinks(), refreshNetworkProfiles(), refreshTasks()]);
      scheduleLinkVerify(data.link);
    }
  }
  async function verifyLink(link) {
    await run('验证组网', async () => api(`/network-links/${encodeURIComponent(link.id)}/verify`, { body: {} }));
    await Promise.all([refreshNetworkLinks(), refreshTasks(), refreshNodes()]);
  }
  async function reapplyLink(link) {
    const data = await run('启用并重新应用组网', async () => api(`/network-links/${encodeURIComponent(link.id)}/enable`, { body: {} }));
    await Promise.all([refreshNetworkLinks(), refreshTasks()]);
    scheduleLinkVerify(data?.link || link);
  }
  async function disableLink(link) {
    await run('禁用组网记录', async () => api(`/network-links/${encodeURIComponent(link.id)}/disable`, { body: {} }));
    await refreshNetworkLinks();
  }
  async function editLink(link) {
    setQuickForm((old) => ({
      ...old,
      name: link.name || old.name,
      network_name: link.network_name || old.network_name,
      cidr: link.cidr || old.cidr,
      port: link.port || old.port,
      entry_node_id: link.entry_node_id || '',
      backend_node_id: link.backend_node_id || '',
      tcp: safeList(link.protocols).includes('tcp') || safeList(link.protocols).length === 0,
      udp: safeList(link.protocols).includes('udp') || safeList(link.protocols).length === 0,
    }));
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }
  async function deleteLink(link) {
    if (!window.confirm('确认删除这条组网记录？不会停止远端 EasyTier 服务。')) return;
    await run('删除组网记录', async () => api(`/network-links/${encodeURIComponent(link.id)}`, { method: 'DELETE' }));
    await refreshNetworkLinks();
  }
  function selectedForwardLink() { return networkLinks.find((item) => item.id === forwardForm.network_link_id); }
  function forwardRoutePreview(link) {
    const entry = link ? nodeMap[link.entry_node_id] : null;
    const landing = link ? nodeMap[link.backend_node_id] : null;
    const publicPort = forwardForm.public_listen_port || '公网端口';
    const landingAddr = `${forwardForm.landing_host || '落地服务器'}:${forwardForm.landing_port || '落地端口'}`;
    if (forwardForm.transport_mode === 'public') {
      return `外部客户端 → ${publicIP(entry)}:${publicPort} → A nftables → ${publicIP(landing)}:${publicPort} → B nftables → ${landingAddr}`;
    }
    return `外部客户端 → ${publicIP(entry)}:${publicPort} → A nftables → EasyTier → ${landing?.name || 'B 节点'}:${publicPort} → B nftables → ${landingAddr}`;
  }
  async function createForward(options = {}) {
    const link = selectedForwardLink();
    if (!link) { setAlert({ type: 'error', message: '请先选择一条已成功的组网链路。' }); return null; }
    if (link.status !== 'connected' && link.status !== 'active') { setAlert({ type: 'error', message: '该组网链路尚未显示“组网成功”，请等待自动验证完成。' }); return null; }
    if (!String(forwardForm.landing_host || '').trim()) { setAlert({ type: 'error', message: '请填写落地服务器 IP 或域名。' }); return null; }
    const body = {
      network_link_id: forwardForm.network_link_id,
      name: forwardForm.name || `forward-${forwardForm.public_listen_port || 'port'}`,
      protocol: forwardForm.protocol,
      public_listen_port: Number(forwardForm.public_listen_port),
      landing_host: forwardForm.landing_host.trim(),
      landing_port: Number(forwardForm.landing_port),
      transport_mode: forwardForm.transport_mode || 'easytier',
      enabled: forwardForm.enabled,
      remark: forwardForm.remark,
    };
    const path = options.apply ? '/forwards/create-and-apply' : '/forwards';
    const result = await run(options.apply ? '创建并应用转发' : '创建转发规则', async () => api(path, { body }));
    if (result) {
      if (options.apply) await refreshTasks();
      setForwardForm((old) => ({ ...old, name: '', public_listen_port: '', landing_host: '', landing_port: '', remark: '' }));
      await refreshForwards();
      setAlert({ type: 'success', message: options.apply ? '已创建 A 侧入口转发和 B 侧落地转发任务，请到任务页查看结果。' : '已创建转发规则' });
    }
    return result;
  }
  async function deleteForward(rule) {
    if (!window.confirm('确认删除这条转发规则？')) return;
    await run('删除转发规则', async () => api(`/forwards/${encodeURIComponent(rule.id)}`, { method: 'DELETE' }));
    await refreshForwards();
  }
  async function applyForward(rule) {
    await run('应用转发规则', async () => api(`/forwards/${encodeURIComponent(rule.id)}/apply`, { body: {} }));
    await Promise.all([refreshForwards(), refreshTasks()]);
  }
  async function verifyForward(rule) {
    await run('验证转发规则', async () => api(`/forwards/${encodeURIComponent(rule.id)}/verify`, { body: {} }));
    await Promise.all([refreshForwards(), refreshTasks()]);
  }
  async function detectInterfaces(nodeID) {
    if (!nodeID) { setAlert({ type: 'error', message: '请选择节点' }); return; }
    await run('识别网卡', async () => api('/tasks', { body: { node_id: nodeID, action: 'detect_network_interfaces', payload: {} } }));
    await refreshTasks();
    setAlert({ type: 'success', message: '已创建识别网卡任务，请在任务页查看默认出口和网关。' });
  }
  async function createPBR(options = {}) {
    if (!pbrForm.node_id) { setAlert({ type: 'error', message: '请选择节点。' }); return; }
    if (!pbrForm.forward_rule_id) { setAlert({ type: 'error', message: '请选择关联转发规则。' }); return; }
    if (!pbrForm.egress_interface.trim()) { setAlert({ type: 'error', message: '请填写出口接口。' }); return; }
    const body = { ...pbrForm, name: pbrForm.name || 'pbr-forward', source_type: 'forward', enabled: pbrForm.enabled };
    const path = options.apply ? '/pbr-policies/create-and-apply' : '/pbr-policies';
    const result = await run(options.apply ? '创建并应用出口策略' : '创建出口策略', async () => api(path, { body }));
    if (result) await Promise.all([refreshPBRPolicies(), refreshTasks()]);
  }
  async function applyPBR(policy) {
    await run('应用出口策略', async () => api(`/pbr-policies/${encodeURIComponent(policy.id)}/apply`, { body: {} }));
    await Promise.all([refreshPBRPolicies(), refreshTasks()]);
  }
  async function verifyPBR(policy) {
    await run('验证出口策略', async () => api(`/pbr-policies/${encodeURIComponent(policy.id)}/verify`, { body: {} }));
    await Promise.all([refreshPBRPolicies(), refreshTasks()]);
  }
  async function disablePBR(policy) {
    await run('禁用出口策略', async () => api(`/pbr-policies/${encodeURIComponent(policy.id)}/disable`, { body: {} }));
    await Promise.all([refreshPBRPolicies(), refreshTasks()]);
  }
  async function deletePBR(policy) {
    if (!window.confirm('确认删除这条出口策略？')) return;
    await run('删除出口策略', async () => api(`/pbr-policies/${encodeURIComponent(policy.id)}`, { method: 'DELETE' }));
    await refreshPBRPolicies();
  }

  const filteredTasks = tasks.filter((task) =>
    (taskFilter === 'all' || task.status === taskFilter) &&
    (taskNodeFilter === 'all' || task.node_id === taskNodeFilter) &&
    (!taskEasyTierOnly || easyTierActions.includes(task.action) || pbrActions.includes(task.action))
  );

  return (
    <main>
      <header>
        <div>
          <h1>Edge Tunnel Panel</h1>
          <p>基于 EasyTier 的 TCP/UDP 隧道组网与转发管理面板。</p>
        </div>
        <button className="secondary" onClick={() => run('刷新', refreshAll)} disabled={loading}>{loading ? '处理中' : '刷新'}</button>
      </header>
      <nav>{tabs.map(([key, label]) => <button key={key} className={activeTab === key ? 'active' : ''} onClick={() => setActiveTab(key)}>{label}</button>)}</nav>
      {alert && <div className={`alert ${alert.type || ''}`}>{alert.message}</div>}
      {!strictAuth && <div className="alert">当前为测试模式，Web API 未启用 Operator Token 鉴权。</div>}
      {strictAuth && !token && activeTab !== 'settings' ? renderLogin() : renderActiveTab()}
    </main>
  );

  function renderActiveTab() {
    switch (activeTab) {
      case 'dashboard': return renderDashboard();
      case 'nodes': return renderNodes();
      case 'networks': return renderNetworks();
      case 'forwards': return renderForwards();
      case 'pbr': return renderPBR();
      case 'tasks': return renderTasks();
      case 'settings': return renderSettings();
      default: return renderDashboard();
    }
  }
  function renderLogin() {
    return <section className="card"><h2>登录 / Token</h2><p className="muted">当前主控启用了严格鉴权，请输入 Operator Token。</p><div className="grid two"><label>Operator Token<input type="password" value={token} onChange={(event) => setToken(event.target.value)} /></label><label>API Base<input value={apiBase} onChange={(event) => setApiBase(event.target.value)} placeholder="默认同源" /></label></div><div className="actions"><button onClick={() => { localStorage.setItem(TOKEN_KEY, token); localStorage.setItem(API_BASE_KEY, apiBase); run('测试连接', refreshAll); }}>保存并连接</button><button className="secondary" onClick={() => { localStorage.removeItem(TOKEN_KEY); setToken(''); }}>清除 Token</button></div></section>;
  }
  function renderDashboard() {
    const recent = tasks.slice(0, 5);
    return <section className="grid"><div className="grid four"><div className="stat"><span>主控状态</span><strong>{health?.name || '-'}</strong><small>{health?.version || DEFAULT_VERSION}</small></div><div className="stat"><span>节点</span><strong>{nodes.length}</strong><small>在线 {counts.online} / 可能离线 {counts.stale} / 离线 {counts.offline}</small></div><div className="stat"><span>任务失败</span><strong>{counts.failed}</strong><small>最近任务 {tasks.length} 条</small></div><div className="stat"><span>组网链路</span><strong>{networkLinks.length}</strong><small>{networkLinks.filter((link) => link.status === 'connected' || link.status === 'active').length} 条成功</small></div></div><div className="card"><h2>最近任务</h2>{recent.length === 0 ? <p className="muted">暂无任务。</p> : <div className="cards">{recent.map((task) => <TaskMini key={task.id} task={task} />)}</div>}</div></section>;
  }
  function renderNodes() {
    return <section className="card"><div className="card-head"><div><h2>节点</h2><p className="muted">管理已接入的被控服务器。点击“添加节点”生成一键命令。</p></div><div className="actions"><button className="secondary" onClick={refreshNodes}>刷新</button><button onClick={() => setShowAddAgent(!showAddAgent)}>添加节点</button></div></div>{showAddAgent && <AddAgentCard />}{nodes.length === 0 ? <div className="empty-state">暂无节点。点击右上角“添加节点”生成 Agent 接入命令。</div> : <div className="cards compact-cards">{nodes.map((node) => <NodeCard key={node.id} node={node} />)}</div>}</section>;
  }
  function AddAgentCard() {
    return <div className="sub-panel add-agent-card"><h3>新节点接入</h3><div className="grid two form-grid"><label>节点名称<input value={agentForm.node_name} onChange={(event) => setAgentForm({ ...agentForm, node_name: event.target.value })} /></label><label>Controller 地址<input value={agentForm.controller_url} onChange={(event) => setAgentForm({ ...agentForm, controller_url: event.target.value })} /></label><label>版本<input value={agentForm.version} onChange={(event) => setAgentForm({ ...agentForm, version: event.target.value })} /></label><div className="check-row"><label><input type="checkbox" checked={agentForm.enable_tasks} onChange={(event) => setAgentForm({ ...agentForm, enable_tasks: event.target.checked })} />启用任务轮询</label><label><input type="checkbox" checked={agentForm.enable_write_actions} onChange={(event) => setAgentForm({ ...agentForm, enable_write_actions: event.target.checked })} />允许写入动作</label></div></div><div className="actions"><button onClick={generateAgentCommand}>获取一键安装命令</button><button className="secondary" onClick={() => copyCommand('root', agentCommand.root)}>复制 root 命令</button><button className="secondary" onClick={() => copyCommand('sudo', agentCommand.sudo)}>复制 sudo 命令</button><button className="secondary" onClick={() => setShowAddAgent(false)}>取消</button></div>{agentCommand.root && <div className="command-block"><div className="command-title"><strong>root 用户命令</strong><span>推荐 root 登录服务器时使用</span></div><pre>{agentCommand.root}</pre></div>}{agentCommand.sudo && <details className="command-block"><summary>普通用户 sudo 命令</summary><pre>{agentCommand.sudo}</pre></details>}<p className="steps">执行命令后，该节点会自动上线；如果未出现，请等待 30 秒或点击刷新。</p></div>;
  }
  function NodeCard({ node }) {
    const peerCount = Number(node.easytier_peer_count || 0);
    return <article className="mini-card node-card"><div className="card-head"><div><h3>{node.name || node.id}</h3><p className="muted" title={node.id}>节点 ID：{shortID(node.id)}</p></div><span className={statusClass(node.status)}>{labelStatus(node.status)}</span></div><dl className="kv compact-kv"><dt>公网 IP</dt><dd>{node.public_ip || node.observed_ip || '-'}</dd><dt>虚拟 IP</dt><dd>{node.easytier_ip || '未分配'}</dd><dt>EasyTier</dt><dd>{labelStatus(node.easytier_status)}</dd><dt>组网</dt><dd><span className={node.easytier_network_ok ? 'badge succeeded' : 'badge stale'}>{networkStatusText(node)}</span></dd><dt>Peer</dt><dd>{peerCount} 个</dd><dt>延迟</dt><dd>{displayLatency(node.easytier_best_latency_ms)}</dd><dt>丢包</dt><dd>{cleanLoss(node.easytier_packet_loss)}</dd><dt>隧道</dt><dd>{displayTunnels(node.easytier_tunnels)}</dd><dt>路由</dt><dd>{displayRoute(node.easytier_route_type, node.easytier_network_ok)}</dd><dt>最后上报</dt><dd>{timeAgo(node.last_seen_at)}</dd></dl>{node.easytier_network_ok && !node.easytier_best_latency_ms && <div className="alert">Peer 已连接，延迟待解析。</div>}{node.easytier_status === 'active' && !node.easytier_network_ok && peerCount === 0 && <div className="alert">EasyTier 已运行，但未发现远端 Peer。请确认后端 peers、入口安全组 TCP/UDP 11010 和网络密钥。</div>}<details className="node-details"><summary>详情</summary><dl className="kv"><dt>内网 IP</dt><dd>{node.private_ip || '-'}</dd><dt>状态原因</dt><dd>{node.status_reason || '-'}</dd></dl><div className="cap-list">{safeList(node.capabilities).slice(0, 20).map((capability) => <span key={capability} className="cap">{capability}</span>)}</div></details><div className="actions"><button className="secondary" onClick={() => setOpenNodeActions(openNodeActions === node.id ? '' : node.id)}>节点操作</button></div>{openNodeActions === node.id && <NodeActionPanel node={node} />}</article>;
  }
  function NodeActionPanel({ node }) {
    return <div className="action-panel"><div className="action-section"><h4>只读检查</h4><div className="action-grid">{readActions.map((action) => <button key={action} className="secondary" onClick={() => createNodeTask(node.id, action)}>{actionLabel(action)}</button>)}</div></div><div className="action-section warning-section"><h4>写入维护</h4><p className="warning-text">这些操作会修改节点服务状态，请只在可信节点执行。</p><div className="action-grid">{writeActions.map((action) => <button key={action} className="warning" onClick={() => createNodeTask(node.id, action)}>{actionLabel(action)}</button>)}</div></div><div className="action-section danger-section"><h4>危险操作</h4><p className="muted">仅删除主控记录，不会卸载远端 Agent。</p><div className="action-grid"><button className="danger" onClick={() => deleteNode(node)}>删除节点记录</button></div></div></div>;
  }
  function renderNetworks() {
    return <section className="card"><div className="card-head"><h2>组网配置</h2><button className="secondary" onClick={() => Promise.all([refreshNetworkLinks(), refreshNetworkProfiles(), refreshNodes()])}>刷新</button></div><div className="sub-panel network-form"><h3>快速组网</h3><p className="muted">选择公网入口节点和后端节点，面板会自动生成入口 listeners 和后端 peers。</p><div className="grid two form-grid"><label>组网名称<input value={quickForm.name} onChange={(event) => setQuickForm({ ...quickForm, name: event.target.value })} /></label><label>网络名<input value={quickForm.network_name} onChange={(event) => setQuickForm({ ...quickForm, network_name: event.target.value })} /></label><label>网络密钥<div className="inline"><input value={quickForm.network_secret} onChange={(event) => setQuickForm({ ...quickForm, network_secret: event.target.value })} placeholder="留空由主控自动生成" /><button className="secondary" type="button" onClick={() => setQuickForm({ ...quickForm, network_secret: randomSecret() })}>重新生成</button></div></label><label>CIDR<input value={quickForm.cidr} onChange={(event) => setQuickForm({ ...quickForm, cidr: event.target.value })} /></label><label>监听端口<input type="number" min="1" max="65535" value={quickForm.port} onChange={(event) => setQuickForm({ ...quickForm, port: event.target.value })} /></label><label>公网入口节点<select value={quickForm.entry_node_id} onChange={(event) => setQuickForm({ ...quickForm, entry_node_id: event.target.value })}><option value="">请选择入口节点</option>{onlineNodes.map((node) => <option key={node.id} value={node.id}>{nodeOptionLabel(node)}</option>)}</select></label><label>后端节点<select value={quickForm.backend_node_id} onChange={(event) => setQuickForm({ ...quickForm, backend_node_id: event.target.value })}><option value="">请选择后端节点</option>{onlineNodes.map((node) => <option key={node.id} value={node.id}>{nodeOptionLabel(node)}</option>)}</select></label><div className="check-row"><label><input type="checkbox" checked={quickForm.tcp} onChange={(event) => setQuickForm({ ...quickForm, tcp: event.target.checked })} />TCP</label><label><input type="checkbox" checked={quickForm.udp} onChange={(event) => setQuickForm({ ...quickForm, udp: event.target.checked })} />UDP</label></div></div><details className="command-block" open={quickForm.showAdvanced} onToggle={(event) => setQuickForm({ ...quickForm, showAdvanced: event.currentTarget.open })}><summary>高级参数</summary><div className="grid two"><label>自定义 listeners<textarea value={quickForm.listeners} onChange={(event) => setQuickForm({ ...quickForm, listeners: event.target.value })} /></label><label>自定义 peers<textarea value={quickForm.peers} onChange={(event) => setQuickForm({ ...quickForm, peers: event.target.value })} /></label><label>MTU<input type="number" value={quickForm.mtu} onChange={(event) => setQuickForm({ ...quickForm, mtu: event.target.value })} /></label><label>MSS 模式<select value={quickForm.mss_mode} onChange={(event) => setQuickForm({ ...quickForm, mss_mode: event.target.value })}><option value="auto">自动</option><option value="fixed">固定</option><option value="disabled">禁用</option></select></label><label>固定 MSS 值<input type="number" value={quickForm.mss_value} onChange={(event) => setQuickForm({ ...quickForm, mss_value: event.target.value })} placeholder="默认 MTU-40" /></label><label className="check"><input type="checkbox" checked={quickForm.mss_clamp_enabled} onChange={(event) => setQuickForm({ ...quickForm, mss_clamp_enabled: event.target.checked })} />启用 MSS clamp</label></div><pre>{pretty({ ...quickForm, protocols: [quickForm.tcp && 'tcp', quickForm.udp && 'udp'].filter(Boolean) })}</pre></details><div className="actions"><button onClick={quickApplyNetwork}>创建并应用组网</button></div></div><h3>组网卡片</h3>{networkLinks.length === 0 ? <p className="muted">暂无组网记录。请使用上方“快速组网”。</p> : <div className="cards compact-cards">{networkLinks.map((link) => <NetworkLinkCard key={link.id} link={link} />)}</div>}<details className="command-block"><summary>历史组网配置 / 已保存配置</summary>{networkProfiles.length === 0 ? <p className="muted">暂无历史配置。</p> : networkProfiles.map((profile) => <pre key={profile.id}>{pretty(profile)}</pre>)}</details></section>;
  }
  function NetworkLinkCard({ link }) {
    const entry = nodeMap[link.entry_node_id];
    const backend = nodeMap[link.backend_node_id];
    const ok = link.status === 'active' || link.status === 'connected';
    return <article className="mini-card network-card"><div className="card-head"><h3>{link.name || link.network_name}</h3><span className={statusClass(ok ? 'succeeded' : link.status)}>{linkStatusText(link)}</span></div><dl className="kv compact-kv"><dt>链路</dt><dd>{entry?.name || '-'} → {backend?.name || '-'}</dd><dt>Peer</dt><dd>入口 {link.entry_peer_count || 0} 个 / 后端 {link.backend_peer_count || 0} 个</dd><dt>延迟</dt><dd>{displayLatency(link.best_latency_ms)}</dd><dt>丢包</dt><dd>{cleanLoss(link.packet_loss)}</dd><dt>隧道</dt><dd>{displayTunnels(link.tunnels)}</dd><dt>路由</dt><dd>{displayRoute(link.route_type, ok)}</dd></dl><details><summary>详情</summary><pre>{pretty(link)}</pre></details><div className="actions"><button className="secondary" onClick={() => editLink(link)}>修改组网</button><button onClick={() => reapplyLink(link)}>启用</button><button className="secondary" onClick={() => disableLink(link)}>禁用</button><button className="danger" onClick={() => deleteLink(link)}>删除</button></div></article>;
  }
  function renderForwards() {
    const selectedLink = selectedForwardLink();
    const readyLinks = networkLinks.filter((link) => link.status === 'connected' || link.status === 'active');
    return <section className="card"><div className="card-head"><div><h2>转发规则</h2><p className="muted">基于已成功的组网链路，把 A 公网入口端口转发到 B 节点，再由 B 转发到落地服务器 IP/域名和端口。</p></div><button className="secondary" onClick={() => Promise.all([refreshForwards(), refreshNetworkLinks(), refreshNodes()])}>刷新</button></div><div className="sub-panel forward-form"><h3>创建转发规则</h3><div className="grid two form-grid"><label>选择组网链路<select value={forwardForm.network_link_id} onChange={(event) => setForwardForm({ ...forwardForm, network_link_id: event.target.value })}><option value="">请选择已成功的组网链路</option>{readyLinks.map((link) => <option key={link.id} value={link.id}>{linkOptionLabel(link, nodeMap)}</option>)}</select></label><label>规则名称<input placeholder={forwardForm.public_listen_port ? `forward-${forwardForm.public_listen_port}` : 'forward-18081'} value={forwardForm.name} onChange={(event) => setForwardForm({ ...forwardForm, name: event.target.value })} /></label><label>协议<select value={forwardForm.protocol} onChange={(event) => setForwardForm({ ...forwardForm, protocol: event.target.value })}><option value="tcp">TCP</option><option value="udp">UDP</option><option value="both">TCP+UDP</option></select></label><label>公网监听端口<input type="number" min="1" max="65535" value={forwardForm.public_listen_port} onChange={(event) => setForwardForm({ ...forwardForm, public_listen_port: event.target.value })} placeholder="例如 18081" /></label><label>落地服务器地址<input value={forwardForm.landing_host} onChange={(event) => setForwardForm({ ...forwardForm, landing_host: event.target.value })} placeholder="例如 1.2.3.4 或 backend.example.com" /></label><label>落地服务器端口<input type="number" min="1" max="65535" value={forwardForm.landing_port} onChange={(event) => setForwardForm({ ...forwardForm, landing_port: event.target.value })} placeholder="例如 8080" /></label><label>A 到 B 的传输方式<select value={forwardForm.transport_mode} onChange={(event) => setForwardForm({ ...forwardForm, transport_mode: event.target.value })}><option value="easytier">EasyTier 隧道</option><option value="public">B 公网直连</option></select></label><label className="check"><input type="checkbox" checked={forwardForm.enabled} onChange={(event) => setForwardForm({ ...forwardForm, enabled: event.target.checked })} />启用规则</label></div><div className="route-preview"><strong>链路预览</strong><p>{forwardRoutePreview(selectedLink)}</p><small>{forwardForm.transport_mode === 'public' ? 'B 公网直连：A 通过 B 的公网 IP 转发，再由 B 落地到目标服务。' : 'EasyTier 隧道：A 通过 B 的 EasyTier 虚拟 IP 转发，再由 B 落地到目标服务。'}</small></div><details className="command-block" open={forwardForm.showAdvanced} onToggle={(event) => setForwardForm({ ...forwardForm, showAdvanced: event.currentTarget.open })}><summary>高级设置</summary><div className="grid two"><label>备注<input value={forwardForm.remark} onChange={(event) => setForwardForm({ ...forwardForm, remark: event.target.value })} /></label><label>内部端口<input readOnly value={forwardForm.public_listen_port || ''} placeholder="默认等于公网监听端口" /></label></div></details><div className="actions"><button onClick={() => createForward()}>创建规则</button><button onClick={() => createForward({ apply: true })}>创建并应用转发</button></div></div>{forwards.length === 0 ? <p className="muted">暂无转发规则。</p> : <div className="cards compact-cards">{forwards.map((rule) => <ForwardCard key={rule.id} rule={rule} />)}</div>}</section>;
  }
  function ForwardCard({ rule }) {
    const entry = nodeMap[rule.entry_node_id];
    const landing = nodeMap[rule.landing_node_id || rule.backend_node_id];
    const listenPort = ruleListenPort(rule);
    const landingPort = ruleLandingPort(rule);
    const target = landingHost(rule);
    return <article className="mini-card forward-card"><div className="card-head"><h3>{rule.name}</h3><span className={statusClass(rule.status)}>{labelStatus(rule.status) || (rule.enabled ? '已启用' : '已停用')}</span></div><dl className="kv compact-kv"><dt>链路</dt><dd>外部 → {publicIP(entry)}:{listenPort} → {transportModeLabel(rule.transport_mode)} → {landing?.name || rule.landing_node_id || rule.backend_node_id || 'B 节点'} → {target}:{landingPort}</dd><dt>协议</dt><dd>{String(rule.protocol || '').toUpperCase()}</dd><dt>组网链路</dt><dd>{rule.network_link_id ? shortID(rule.network_link_id) : '-'}</dd><dt>A 侧入口</dt><dd>{labelStatus(rule.entry_stage_status) || '等待'}</dd><dt>B 侧落地</dt><dd>{labelStatus(rule.landing_stage_status) || '等待'}</dd><dt>A→B</dt><dd>{transportModeLabel(rule.transport_mode)} / {normalizeHostIP(rule.tunnel_target_host || rule.target_host || '-')}:{rule.tunnel_target_port || listenPort}</dd><dt>落地目标</dt><dd>{target}:{landingPort}</dd></dl><div className="actions"><button onClick={() => applyForward(rule)}>应用</button><button className="secondary" onClick={() => verifyForward(rule)}>验证</button><button className="danger" onClick={() => deleteForward(rule)}>删除</button></div></article>;
  }
  function renderPBR() {
    const selectedForward = forwards.find((rule) => rule.id === pbrForm.forward_rule_id);
    const recommendedNode = selectedForward?.landing_node_id || selectedForward?.backend_node_id || '';
    return <section className="card"><div className="card-head"><div><h2>出口策略 / PBR</h2><p className="muted">为 B 落地执行节点上的转发流量选择出口网卡。当前 MVP 每个节点只允许一条启用中的出口策略。</p></div><button className="secondary" onClick={() => Promise.all([refreshPBRPolicies(), refreshForwards(), refreshNodes()])}>刷新</button></div><div className="sub-panel forward-form"><h3>创建出口策略</h3><div className="grid two form-grid"><label>选择节点<select value={pbrForm.node_id || recommendedNode} onChange={(event) => setPBRForm({ ...pbrForm, node_id: event.target.value })}><option value="">请选择 B 落地节点</option>{nodes.map((node) => <option key={node.id} value={node.id}>{node.name || node.id} / {shortID(node.id)} / {node.private_ip || node.public_ip || '-'}</option>)}</select></label><label>关联转发规则<select value={pbrForm.forward_rule_id} onChange={(event) => { const rule = forwards.find((item) => item.id === event.target.value); setPBRForm({ ...pbrForm, forward_rule_id: event.target.value, node_id: rule?.landing_node_id || rule?.backend_node_id || pbrForm.node_id, name: pbrForm.name || `pbr-${rule?.name || 'forward'}` }); }}><option value="">请选择转发规则</option>{forwards.map((rule) => <option key={rule.id} value={rule.id}>{rule.name} / {nodeLabel(nodeMap[rule.landing_node_id || rule.backend_node_id])} / {ruleListenPort(rule)}→{ruleLandingPort(rule)}</option>)}</select></label><label>策略名称<input value={pbrForm.name} onChange={(event) => setPBRForm({ ...pbrForm, name: event.target.value })} placeholder="pbr-forward" /></label><label>出口接口<input value={pbrForm.egress_interface} onChange={(event) => setPBRForm({ ...pbrForm, egress_interface: event.target.value })} placeholder="例如 eth1" /></label><label>出口网关<input value={pbrForm.egress_gateway} onChange={(event) => setPBRForm({ ...pbrForm, egress_gateway: event.target.value })} placeholder="可留空，或填写 1.2.3.1" /></label><label className="check"><input type="checkbox" checked={pbrForm.enabled} onChange={(event) => setPBRForm({ ...pbrForm, enabled: event.target.checked })} />启用策略</label></div><div className="actions"><button className="secondary" onClick={() => detectInterfaces(pbrForm.node_id || recommendedNode)}>识别网卡</button><button onClick={() => createPBR()}>创建策略</button><button onClick={() => createPBR({ apply: true })}>创建并应用策略</button></div><p className="muted">推荐流程：先识别网卡，再选择 B 节点、转发规则、出口接口和网关。</p></div>{pbrPolicies.length === 0 ? <p className="muted">暂无出口策略。</p> : <div className="cards compact-cards">{pbrPolicies.map((policy) => <PBRCard key={policy.id} policy={policy} />)}</div>}</section>;
  }
  function PBRCard({ policy }) {
    const node = nodeMap[policy.node_id];
    const forward = forwards.find((rule) => rule.id === policy.forward_rule_id);
    return <article className="mini-card"><div className="card-head"><h3>{policy.name}</h3><span className={statusClass(policy.status)}>{labelStatus(policy.status)}</span></div><dl className="kv compact-kv"><dt>节点</dt><dd>{nodeLabel(node)}</dd><dt>转发规则</dt><dd>{forward?.name || policy.forward_rule_id || '-'}</dd><dt>出口接口</dt><dd>{policy.egress_interface || policy.out_interface || '-'}</dd><dt>网关</dt><dd>{policy.egress_gateway || policy.gateway || '-'}</dd><dt>fwmark/table/priority</dt><dd>{policy.fwmark || policy.match_mark || '-'} / {policy.table_id || '-'} / {policy.priority || '-'}</dd></dl><div className="actions"><button onClick={() => applyPBR(policy)}>应用</button><button className="secondary" onClick={() => verifyPBR(policy)}>验证</button><button className="secondary" onClick={() => disablePBR(policy)}>禁用</button><button className="danger" onClick={() => deletePBR(policy)}>删除</button></div></article>;
  }
  function renderTasks() {
    return <section className="card"><div className="card-head"><h2>任务</h2><button className="secondary" onClick={refreshTasks}>刷新</button></div><div className="inline"><label>状态筛选<select value={taskFilter} onChange={(event) => setTaskFilter(event.target.value)}><option value="all">全部状态</option>{['pending', 'running', 'succeeded', 'failed', 'expired', 'cancelled'].map((status) => <option key={status} value={status}>{labelStatus(status)}</option>)}</select></label><label>节点筛选<select value={taskNodeFilter} onChange={(event) => setTaskNodeFilter(event.target.value)}><option value="all">全部节点</option>{nodes.map((node) => <option key={node.id} value={node.id}>{node.name || node.id} / {shortID(node.id)} / {labelStatus(node.status)}</option>)}</select></label><button className="secondary" onClick={() => setTaskFilter('failed')}>只看失败</button><button className={taskEasyTierOnly ? '' : 'secondary'} onClick={() => setTaskEasyTierOnly(!taskEasyTierOnly)}>只看 EasyTier 相关</button></div>{filteredTasks.length === 0 ? <p className="muted">暂无匹配任务。</p> : filteredTasks.map((task) => <TaskCard key={task.id} task={task} />)}</section>;
  }
  function TaskMini({ task }) {
    return <article className="mini-card"><h3>{actionLabel(task.action)}</h3><p>{nodeLabel(nodeMap[task.node_id])}</p><span className={statusClass(task.status)}>{labelStatus(task.status)}</span></article>;
  }
  function TaskCard({ task }) {
    const result = parseJSON(task.result);
    const failed = task.status === 'failed';
    const open = expandedTask === task.id || failed;
    const hasDiskHint = String(task.error || task.result || '').includes('no space left on device') || String(task.error || task.result || '').includes('磁盘空间不足');
    const isForwarding = forwardingActions.includes(task.action);
    const forwardTarget = result.stage === 'landing'
      ? `${result.landing_host_resolved || result.target_host || '-'}:${result.target_port || '-'}`
      : `${result.target_host || result.target_ip || '-'}:${result.target_port || '-'}`;
    return <article className="mini-card"><div className="card-head"><div><h3>{actionLabel(task.action)}</h3><p className="muted">{nodeLabel(nodeMap[task.node_id])}</p></div><span className={statusClass(task.status)}>{labelStatus(task.status)}</span></div>{task.action === 'verify_network_connectivity' && result.network_ok && <div className="alert success">组网成功，远端 Peer {result.peer_count || 0} 个，最佳延迟 {displayLatency(result.best_latency_ms)}，丢包 {cleanLoss(result.packet_loss)}，隧道 {displayTunnels(result.tunnels)}，路由 {displayRoute(result.route_type, true)}。</div>}{isForwarding && result.nft_path && <div className={result.nft_check_ok === false ? 'alert error' : 'alert'}>{result.applied ? `${result.stage === 'landing' ? 'B 侧落地转发' : 'A 侧入口转发'}已应用：端口 ${result.listen_port || '-'} → ${forwardTarget}。nft 检查通过，规则已加载。` : `${result.stage === 'landing' ? 'B 侧落地转发' : 'A 侧入口转发'}失败：端口 ${result.listen_port || '-'} → ${forwardTarget}。`}{result.nft_check_stderr ? ` nft 错误：${result.nft_check_stderr}` : ''}</div>}{hasDiskHint && <div className="alert error">该节点磁盘空间不足，建议换更大磁盘节点测试，或清理系统后重试。</div>}<button className="secondary" onClick={() => setExpandedTask(open ? '' : task.id)}>{open ? '收起详情' : '查看详情'}</button>{open && <TaskDetails task={task} />}</article>;
  }
  function TaskDetails({ task }) {
    return <div className="task-kv"><div>任务 ID：{task.id}</div><div>节点 ID：{task.node_id}</div><div>原始 action：{task.action}</div><div>创建：{formatTime(task.created_at)} / 开始：{formatTime(task.started_at)} / 完成：{formatTime(task.finished_at)}</div><CodeBlock title="payload" value={task.payload} /><CodeBlock title="result" value={task.result} /><CodeBlock title="stdout" value={task.stdout} /><CodeBlock title="stderr" value={task.stderr} /><CodeBlock title="error" value={task.error} /></div>;
  }
  function CodeBlock({ title, value }) {
    const text = pretty(value);
    return <div className="command-block"><div className="command-title"><strong>{title}</strong><button className="secondary" onClick={() => copyText(text).then((ok) => setAlert(ok ? { type: 'success', message: `已复制 ${title}` } : { type: 'error', message: '复制失败，请手动复制' }))}>复制</button></div><pre className="task-output">{text}</pre></div>;
  }
  function renderSettings() {
    function saveToken() {
      localStorage.setItem(TOKEN_KEY, token);
      localStorage.setItem(API_BASE_KEY, apiBase);
      setAlert({ type: 'success', message: '设置已保存' });
    }
    function clearToken() {
      localStorage.removeItem(TOKEN_KEY);
      setToken('');
      setAlert({ type: 'success', message: 'Token 已清除' });
    }
    return <section className="card"><h2>设置</h2><div className="grid two"><label>API Base（默认同源）<input value={apiBase} onChange={(event) => setApiBase(event.target.value)} placeholder="留空表示同源" /></label><label>Operator Token<input type="password" value={token} onChange={(event) => setToken(event.target.value)} placeholder={strictAuth ? '严格鉴权时需要' : '测试模式可留空'} /></label></div><div className="actions"><button onClick={saveToken}>保存设置</button><button className="secondary" onClick={clearToken}>清除 Token</button><button className="secondary" onClick={() => run('测试连接', refreshHealth)}>测试连接</button></div><dl className="kv"><dt>鉴权状态</dt><dd>{strictAuth ? '严格鉴权' : '测试模式免登录'}</dd><dt>Agent 配置目录</dt><dd><code>/etc/edge-tunnel/agent</code></dd><dt>Controller 数据目录</dt><dd><code>/var/lib/edge-tunnel/controller</code></dd><dt>服务</dt><dd><code>edge-tunnel-controller.service</code> / <code>edge-tunnel-agent.service</code> / <code>edge-tunnel-easytier.service</code></dd></dl></section>;
  }
}

createRoot(document.getElementById('root')).render(<App />);
