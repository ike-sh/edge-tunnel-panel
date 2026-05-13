import React, { useEffect, useMemo, useState } from 'react';
import { createRoot } from 'react-dom/client';
import './styles.css';

const TOKEN_KEY = 'edgeTunnelOperatorToken';
const API_BASE_KEY = 'edgeTunnelApiBase';
const DEFAULT_VERSION = 'v0.2.2-test';

const tabs = [['dashboard', '总览'], ['nodes', '节点'], ['networks', '组网配置'], ['entries', '公网入口'], ['forwards', '转发规则'], ['pbr', '出口策略'], ['tasks', '任务'], ['settings', '设置']];
const checkActions = ['run_node_preflight', 'collect_agent_status', 'verify_agent_config', 'verify_easytier_status', 'verify_network_connectivity', 'verify_forward_rules', 'verify_pbr_rules', 'verify_ddns_status'];
const maintenanceActions = ['install_or_update_easytier', 'restart_easytier', 'restart_agent'];
const easyTierActions = ['install_or_update_easytier', 'apply_network_profile', 'verify_easytier_status', 'verify_network_connectivity', 'restart_easytier'];
const taskStatuses = ['all', 'pending', 'running', 'succeeded', 'failed', 'expired', 'cancelled'];
const roleOptions = [['backend', '后端节点'], ['entry', '公网入口节点'], ['relay', '中继节点'], ['exit', '出口节点']];
const roleText = Object.fromEntries(roleOptions);
const actionText = {
  run_node_preflight: '节点预检',
  collect_agent_status: '状态检查',
  verify_agent_config: '验证 Agent 配置',
  verify_easytier_status: '验证 EasyTier 状态',
  verify_network_connectivity: '验证组网',
  verify_forward_rules: '验证转发规则',
  verify_pbr_rules: '验证出口策略',
  verify_ddns_status: '验证 DDNS',
  install_or_update_easytier: '安装/更新 EasyTier',
  apply_network_profile: '应用组网配置',
  apply_entry_config: '应用公网入口',
  apply_forward_config: '应用转发规则',
  apply_pbr_config: '应用出口策略',
  apply_ddns_config: '应用 DDNS',
  reload_firewall_rules: '重载防火墙规则',
  restart_easytier: '重启 EasyTier',
  restart_agent: '重启 Agent',
  reboot_node: '重启服务器'
};
const statusText = {
  online: '在线', stale: '可能离线', offline: '离线',
  pending: '等待中', running: '执行中', succeeded: '成功', failed: '失败', expired: '已过期', cancelled: '已取消', all: '全部',
  active: '运行中', inactive: '未运行', missing_binary: '未安装', missing_config: '缺少配置', service_missing: '服务缺失'
};

function browserControllerURL() {
  if (typeof window === 'undefined') return 'http://CONTROLLER_HOST:18080';
  return `${window.location.protocol}//${window.location.host}`;
}
function normalizeBase(value) { return String(value || '').trim().replace(/\/+$/, ''); }
function safeList(value) { return Array.isArray(value) ? value : []; }
function lines(value) { return String(value || '').split(/\r?\n/).map((item) => item.trim()).filter(Boolean); }
function shortID(value) { return String(value || '-').slice(0, 16); }
function trStatus(status) { return statusText[status] || status || '-'; }
function statusClass(status) { return `badge ${status || 'unknown'}`; }
function formatTime(value) {
  if (!value) return '-';
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? '-' : date.toLocaleString();
}
function timeAgo(value) {
  if (!value) return '-';
  const ts = new Date(value).getTime();
  if (Number.isNaN(ts)) return '-';
  const seconds = Math.max(0, Math.floor((Date.now() - ts) / 1000));
  if (seconds < 60) return `${seconds} 秒前`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes} 分钟前`;
  const hours = Math.floor(minutes / 60);
  return hours < 24 ? `${hours} 小时前` : `${Math.floor(hours / 24)} 天前`;
}
function nodeStatusReason(node) {
  if (node.status_reason) return node.status_reason;
  if (node.status === 'online') return '最近心跳正常';
  if (node.status === 'stale') return '超过 90 秒未上报';
  if (node.status === 'offline') return '超过 5 分钟未上报';
  return '-';
}
function formatOutput(value) {
  if (value === null || value === undefined || value === '') return '-';
  if (typeof value !== 'string') return JSON.stringify(value, null, 2);
  const trimmed = value.trim();
  if ((trimmed.startsWith('{') && trimmed.endsWith('}')) || (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
    try { return JSON.stringify(JSON.parse(trimmed), null, 2); } catch { return value; }
  }
  return value;
}
function parseJSONValue(value) {
  if (!value || typeof value !== 'string') return {};
  try { return JSON.parse(value); } catch { return {}; }
}
function taskNodeLabel(task, nodes) {
  const node = nodes.find((item) => item.id === task.node_id);
  return node ? `${node.name || node.id} / ${shortID(node.id)}` : (task.node_id || '-');
}
function taskNodeOptionLabel(node) { return `${node.name || node.id} / ${shortID(node.id)} / ${trStatus(node.status)}`; }
function easyTierPeerWarning(node) { return node.easytier_status === 'active' && Number(node.easytier_peer_count || 0) === 0; }
function networkStatusText(node) {
  if (node.easytier_network_ok) return '组网成功';
  if (node.easytier_status === 'active' && Number(node.easytier_peer_count || 0) === 0) return '未发现 Peer';
  if (node.easytier_status === 'active') return node.easytier_network_reason || '等待验证';
  return trStatus(node.easytier_status);
}
function networkStatusClass(node) {
  if (node.easytier_network_ok) return 'badge online';
  if (node.easytier_status === 'active') return 'badge stale';
  return statusClass(node.easytier_status);
}
async function copyText(text) {
  if (!text) return false;
  if (navigator.clipboard?.writeText) {
    try { await navigator.clipboard.writeText(text); return true; } catch {}
  }
  try {
    const textarea = document.createElement('textarea');
    textarea.value = text;
    textarea.setAttribute('readonly', 'true');
    textarea.style.position = 'fixed';
    textarea.style.left = '-9999px';
    document.body.appendChild(textarea);
    textarea.select();
    const ok = document.execCommand('copy');
    document.body.removeChild(textarea);
    return ok;
  } catch {
    return false;
  }
}

function App() {
  const [activeTab, setActiveTab] = useState('dashboard');
  const [token, setToken] = useState(() => localStorage.getItem(TOKEN_KEY) || '');
  const [tokenDraft, setTokenDraft] = useState(token);
  const [showToken, setShowToken] = useState(false);
  const [apiBase, setApiBase] = useState(() => localStorage.getItem(API_BASE_KEY) || '');
  const [apiBaseDraft, setApiBaseDraft] = useState(apiBase);
  const [alert, setAlert] = useState(null);
  const [loading, setLoading] = useState(false);
  const [health, setHealth] = useState(null);
  const [nodes, setNodes] = useState([]);
  const [tasks, setTasks] = useState([]);
  const [networkProfiles, setNetworkProfiles] = useState([]);
  const [entries, setEntries] = useState([]);
  const [forwards, setForwards] = useState([]);
  const [pbrPolicies, setPbrPolicies] = useState([]);
  const [ddnsProfiles, setDdnsProfiles] = useState([]);
  const [showAddAgent, setShowAddAgent] = useState(false);
  const [openNodeActions, setOpenNodeActions] = useState('');
  const [taskFilter, setTaskFilter] = useState('all');
  const [taskNodeFilter, setTaskNodeFilter] = useState('all');
  const [taskActionFilter, setTaskActionFilter] = useState('all');
  const [expandedNetworkId, setExpandedNetworkId] = useState('');
  const [editingNetworkId, setEditingNetworkId] = useState('');
  const [networkApplyNode, setNetworkApplyNode] = useState({});
  const [agentForm, setAgentForm] = useState({ controller_url: browserControllerURL(), node_name: 'edge-node-1', role: 'backend', version: DEFAULT_VERSION, enable_tasks: true, enable_write_actions: true });
  const [rootCommand, setRootCommand] = useState('');
  const [sudoCommand, setSudoCommand] = useState('');
  const [recommendedCommand, setRecommendedCommand] = useState('');
  const [quickForm, setQuickForm] = useState({ name: 'edge-net', network_name: 'edge-net', network_secret: '', cidr: '10.144.0.0/16', port: 11010, entry_node_id: '', backend_node_id: '', tcp: true, udp: true });
  const [networkForm, setNetworkForm] = useState({ name: '', network_name: 'edge-net', network_secret: '', cidr: '10.144.0.0/16', protocol_preference: 'auto', listeners: 'tcp://0.0.0.0:11010\nudp://0.0.0.0:11010', peers: '' });
  const [peerSourceNode, setPeerSourceNode] = useState('');
  const [entryForm, setEntryForm] = useState({ name: '', node_id: '', listen_ip: '0.0.0.0', listen_port_start: '', listen_port_end: '', protocol: 'both', domain: '', ddns_enabled: false, ddns_provider: '' });
  const [forwardForm, setForwardForm] = useState({ name: '', entry_id: '', entry_node_id: '', protocol: 'tcp', listen_port: '', target_mode: 'local', target_node_id: '', target_host: '', target_port: '', enabled: true, remark: '' });
  const [pbrForm, setPbrForm] = useState({ node_id: '', name: '', match_source: '', match_dst: '', match_protocol: '', match_mark: '', table_id: '', gateway: '', out_interface: '', priority: '', enabled: true });

  const counts = useMemo(() => {
    const nodeCounts = { online: 0, stale: 0, offline: 0 };
    nodes.forEach((node) => { nodeCounts[node.status] = (nodeCounts[node.status] || 0) + 1; });
    const taskCounts = { pending: 0, running: 0, succeeded: 0, failed: 0 };
    tasks.forEach((task) => { if (taskCounts[task.status] !== undefined) taskCounts[task.status] += 1; });
    return { nodeCounts, taskCounts };
  }, [nodes, tasks]);

  async function api(path, options = {}) {
    const method = options.method || (options.body === undefined ? 'GET' : 'POST');
    const headers = { Accept: 'application/json' };
    if (options.body !== undefined) headers['Content-Type'] = 'application/json';
    if (token) headers.Authorization = `Bearer ${token}`;
    const response = await fetch(`${normalizeBase(apiBase)}/api/v1${path}`, { method, headers, body: options.body === undefined ? undefined : JSON.stringify(options.body) });
    let payload = null;
    try { payload = await response.json(); } catch {}
    if (!response.ok) throw new Error(payload?.error?.message || `${response.status} ${response.statusText}`);
    if (payload && typeof payload.ok === 'boolean') {
      if (!payload.ok) throw new Error(payload.error?.message || '请求失败');
      return payload.data;
    }
    return payload;
  }
  async function run(label, fn) {
    setLoading(true);
    setAlert(null);
    try {
      const result = await fn();
      setAlert({ type: 'success', message: `${label}完成` });
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
  async function refreshNetworkProfiles() { const data = safeList(await api('/network-profiles')); setNetworkProfiles(data); return data; }
  async function refreshEntries() { const data = safeList(await api('/entries')); setEntries(data); return data; }
  async function refreshForwards() { const data = safeList(await api('/forwards')); setForwards(data); return data; }
  async function refreshPbrPolicies() { const data = safeList(await api('/pbr-policies')); setPbrPolicies(data); return data; }
  async function refreshDdnsProfiles() { const data = safeList(await api('/ddns')); setDdnsProfiles(data); return data; }
  async function refreshAll() {
    const info = await refreshHealth();
    if (token || info?.strict_auth === false) {
      await Promise.all([refreshNodes(), refreshTasks(), refreshNetworkProfiles(), refreshEntries(), refreshForwards(), refreshPbrPolicies(), refreshDdnsProfiles()]);
    }
  }
  useEffect(() => { run('刷新', refreshAll); }, []);
  useEffect(() => { const timer = window.setInterval(() => refreshNodes().catch(() => {}), 15000); return () => window.clearInterval(timer); }, [apiBase, token]);

  function saveToken() { localStorage.setItem(TOKEN_KEY, tokenDraft); setToken(tokenDraft); setAlert({ type: 'success', message: 'Operator Token 已保存' }); }
  function clearToken() { localStorage.removeItem(TOKEN_KEY); setToken(''); setTokenDraft(''); setAlert({ type: 'success', message: 'Operator Token 已清除' }); }
  function saveApiBase() { const next = normalizeBase(apiBaseDraft); if (next) localStorage.setItem(API_BASE_KEY, next); else localStorage.removeItem(API_BASE_KEY); setApiBase(next); setAlert({ type: 'success', message: 'API 地址已保存' }); }
  async function createTask(nodeId, action) {
    const result = await run('创建任务', async () => { await api('/tasks', { body: { node_id: nodeId, action, payload: {} } }); await refreshTasks(); });
    if (result !== null) setAlert({ type: 'success', message: '已创建任务，可到“任务”页面按该节点筛选查看详情。' });
  }
  async function deleteNode(node) {
    if (!window.confirm('仅删除主控面板中的节点记录，不会卸载远端 Agent。\n如果远端 Agent 仍在运行，该节点会在下一次心跳后重新出现。\n确认删除？')) return;
    await run('删除节点记录', async () => { await api(`/nodes/${encodeURIComponent(node.id)}`, { method: 'DELETE' }); await refreshNodes(); setOpenNodeActions(''); });
  }
  async function generateAgentCommand() {
    const data = await run('生成一键命令', async () => api('/bootstrap/agent-install-command', { body: { ...agentForm } }));
    if (!data?.root_command && !data?.sudo_command) return;
    setRootCommand(data.root_command || '');
    setSudoCommand(data.sudo_command || '');
    setRecommendedCommand(data.recommended_command || data.root_command || '');
  }
  async function copyCommand(text, label) {
    if (!text) { setAlert({ type: 'error', message: '请先生成一键命令。' }); return; }
    const ok = await copyText(text);
    setAlert(ok ? { type: 'success', message: `已复制 ${label}，请到被控服务器执行。` } : { type: 'error', message: '复制失败，请手动复制。' });
  }
  async function copyOutput(text) { const ok = await copyText(text); setAlert(ok ? { type: 'success', message: '已复制任务输出。' } : { type: 'error', message: '复制失败，请手动复制。' }); }
  function networkPayload() { return { ...networkForm, listeners: lines(networkForm.listeners), peers: lines(networkForm.peers) }; }
  async function quickApplyNetwork(event) {
    event.preventDefault();
    const entry = nodes.find((node) => node.id === quickForm.entry_node_id);
    const backend = nodes.find((node) => node.id === quickForm.backend_node_id);
    if (!entry || entry.status !== 'online') { setAlert({ type: 'error', message: '请选择在线的公网入口节点。' }); return; }
    if (!entry.public_ip) { setAlert({ type: 'error', message: '入口节点需要有公网 IP。' }); return; }
    if (!backend || backend.status !== 'online') { setAlert({ type: 'error', message: '请选择在线的后端节点。' }); return; }
    if (entry.id === backend.id) { setAlert({ type: 'error', message: '入口节点和后端节点不能相同。' }); return; }
    const protocols = [quickForm.tcp ? 'tcp' : '', quickForm.udp ? 'udp' : ''].filter(Boolean);
    if (!protocols.length) { setAlert({ type: 'error', message: '至少选择 tcp 或 udp。' }); return; }
    await run('创建并应用组网', async () => {
      await api('/network-profiles/quick-apply', { body: { name: quickForm.name, network_name: quickForm.network_name, network_secret: quickForm.network_secret, cidr: quickForm.cidr, port: Number(quickForm.port) || 11010, entry_node_id: entry.id, backend_node_id: backend.id, protocols } });
      await refreshTasks();
      setActiveTab('tasks');
      setAlert({ type: 'success', message: '组网任务已创建，请等待 10~20 秒后到“节点”页面点击“验证组网”。' });
    });
  }
  async function createNetworkProfile(event) {
    event.preventDefault();
    await run(editingNetworkId ? '更新组网配置' : '创建组网配置', async () => {
      const body = networkPayload();
      if (editingNetworkId) await api('/network-profiles/' + editingNetworkId, { method: 'PUT', body });
      else await api('/network-profiles', { body });
      setNetworkForm({ name: '', network_name: 'edge-net', network_secret: '', cidr: '10.144.0.0/16', protocol_preference: 'auto', listeners: 'tcp://0.0.0.0:11010\nudp://0.0.0.0:11010', peers: '' });
      setEditingNetworkId('');
      await refreshNetworkProfiles();
    });
  }
  function editNetworkProfile(profile) {
    setEditingNetworkId(profile.id);
    setNetworkForm({ name: profile.name || '', network_name: profile.network_name || 'edge-net', network_secret: profile.network_secret || '', cidr: profile.cidr || '10.144.0.0/16', protocol_preference: profile.protocol_preference || 'auto', listeners: (profile.listeners || []).join('\n') || 'tcp://0.0.0.0:11010\nudp://0.0.0.0:11010', peers: (profile.peers || []).join('\n') });
  }
  async function deleteNetworkProfile(profile) {
    if (!window.confirm(`确认删除组网配置“${profile.name || profile.id}”？`)) return;
    await run('删除组网配置', async () => { await api('/network-profiles/' + profile.id, { method: 'DELETE' }); await refreshNetworkProfiles(); });
  }
  async function applyNetworkProfile(profile) {
    const nodeId = networkApplyNode[profile.id] || '';
    if (!nodeId) { setAlert({ type: 'error', message: '请先选择目标节点' }); return; }
    const node = nodes.find((item) => item.id === nodeId);
    if (node?.role === 'backend' && !safeList(profile.peers).length) { setAlert({ type: 'error', message: '后端节点需要填写入口节点公网地址作为 peer。' }); return; }
    await run('应用组网配置', async () => { await api('/network-profiles/' + profile.id + '/apply', { body: { node_id: nodeId } }); await refreshTasks(); });
  }
  function fillPeersFromEntry(nodeId) {
    const node = nodes.find((item) => item.id === nodeId);
    if (!node?.public_ip) { setAlert({ type: 'error', message: '请选择带公网 IP 的入口节点。' }); return; }
    setNetworkForm((current) => ({ ...current, peers: `tcp://${node.public_ip}:11010\nudp://${node.public_ip}:11010` }));
    setAlert({ type: 'success', message: '已从入口节点公网 IP 生成 peers，可保存后应用到后端节点。' });
  }
  async function createEntry(event) { event.preventDefault(); await run('创建公网入口', async () => { await api('/entries', { body: { ...entryForm, listen_port_start: Number(entryForm.listen_port_start), listen_port_end: Number(entryForm.listen_port_end) } }); setEntryForm({ ...entryForm, name: '', domain: '' }); await refreshEntries(); }); }
  async function applyEntry(entry) { await run('应用公网入口', async () => { await api(`/entries/${entry.id}/apply`, { body: { node_id: entry.node_id, entry_id: entry.id } }); await refreshTasks(); }); }
  async function createForward(event) { event.preventDefault(); await run('创建转发规则', async () => { await api('/forwards', { body: { ...forwardForm, listen_port: Number(forwardForm.listen_port), target_port: Number(forwardForm.target_port) } }); setForwardForm({ ...forwardForm, name: '', listen_port: '', target_host: '', target_port: '', remark: '' }); await refreshForwards(); }); }
  async function applyForward(forward) { await run('应用转发规则', async () => { await api(`/forwards/${forward.id}/apply`, { body: { entry_node_id: forward.entry_node_id, forward_id: forward.id } }); await refreshTasks(); }); }
  async function createPbrPolicy(event) { event.preventDefault(); await run('创建出口策略', async () => { await api('/pbr-policies', { body: { ...pbrForm, table_id: Number(pbrForm.table_id), priority: Number(pbrForm.priority) } }); setPbrForm({ ...pbrForm, name: '', match_source: '', match_dst: '', gateway: '', out_interface: '' }); await refreshPbrPolicies(); }); }
  async function applyPbrPolicy(policy) { await run('应用出口策略', async () => { await api(`/pbr-policies/${policy.id}/apply`, { body: { node_id: policy.node_id, pbr_policy_id: policy.id } }); await refreshTasks(); }); }

  function renderDashboard() {
    const recent = [...tasks].sort((a, b) => String(b.created_at).localeCompare(String(a.created_at))).slice(0, 5);
    const strictAuth = health?.strict_auth === true;
    return <><>{!strictAuth && <div className="alert warning">当前为测试模式，Web API 未启用 Operator Token 鉴权。</div>}</><div className="grid two">{strictAuth && <Card title="登录 / Token"><label>Operator Token</label><div className="inline"><input type={showToken ? 'text' : 'password'} value={tokenDraft} onChange={(event) => setTokenDraft(event.target.value)} placeholder="输入主控 Operator Token" /><button type="button" onClick={() => setShowToken(!showToken)}>{showToken ? '隐藏' : '显示'}</button></div><div className="actions"><button onClick={saveToken}>保存 Token</button><button className="secondary" onClick={clearToken}>清除 Token</button><button className="secondary" onClick={() => run('测试连接', refreshHealth)}>测试连接</button></div></Card>}<Card title="主控状态"><KeyValues rows={[['名称', health?.name], ['版本', health?.version], ['提交', health?.build_commit], ['构建时间', health?.build_time], ['鉴权状态', strictAuth ? '已启用 Operator Token' : '测试模式免登录']]} /></Card></div><div className="grid four"><Stat title="节点" value={nodes.length} note={`在线 ${counts.nodeCounts.online || 0} · 可能离线 ${counts.nodeCounts.stale || 0} · 离线 ${counts.nodeCounts.offline || 0}`} /><Stat title="进行中任务" value={(counts.taskCounts.pending || 0) + (counts.taskCounts.running || 0)} note={`等待中 ${counts.taskCounts.pending || 0} · 执行中 ${counts.taskCounts.running || 0}`} /><Stat title="已完成任务" value={(counts.taskCounts.succeeded || 0) + (counts.taskCounts.failed || 0)} note={`成功 ${counts.taskCounts.succeeded || 0} · 失败 ${counts.taskCounts.failed || 0}`} /><Stat title="DDNS 配置" value={ddnsProfiles.length} note="作为节点/入口内置能力" /></div><Card title="最近任务" action={<button onClick={() => run('刷新', refreshAll)}>刷新</button>}><TaskTable tasks={recent} compact nodes={nodes} /></Card></>;
  }
  function renderNodes() {
    return <Card title="节点" action={<div className="inline"><button onClick={() => run('刷新节点', refreshNodes)}>刷新</button><button onClick={() => setShowAddAgent(true)}>添加节点</button></div>}><p className="muted">管理已接入的被控服务器。节点页每 15 秒自动刷新。</p>{showAddAgent && renderAddAgentPanel()}{!nodes.length ? <div className="empty-state"><h3>暂无节点</h3><p>点击“添加节点”生成一键 Agent 接入命令。</p><button onClick={() => setShowAddAgent(true)}>添加节点</button></div> : <div className="node-grid">{nodes.map((node) => <div className="node-card" key={node.id}><div className="node-card-head"><div><h3>{node.name || node.id}</h3><code title={node.id}>{shortID(node.id)}</code></div><div className="inline"><span className="badge">{roleText[node.role] || node.role || '-'}</span><span className={statusClass(node.status)}>{trStatus(node.status)}</span><span className={networkStatusClass(node)}>{networkStatusText(node)}</span></div></div><KeyValues rows={[['主机名', node.hostname], ['公网 IP', node.public_ip || node.observed_ip], ['内网 IP', node.private_ip], ['虚拟 IP', node.easytier_ip || '未分配'], ['EasyTier 状态', trStatus(node.easytier_status)], ['组网状态', networkStatusText(node)], ['Peer', `${Number(node.easytier_peer_count || 0)} 个`], ['延迟', node.easytier_best_latency_ms ? `${node.easytier_best_latency_ms} ms` : '-'], ['丢包', node.easytier_packet_loss], ['隧道', safeList(node.easytier_tunnels).join(', ')], ['路由', node.easytier_route_type], ['最后上报', formatTime(node.last_seen_at)], ['最后上报距今', timeAgo(node.last_seen_at)], ['状态原因', nodeStatusReason(node)]]} /><p className="muted">虚拟 IP 未分配并不一定代表组网失败；Peer 连接成功即可说明 EasyTier peer 层已连通。</p>{easyTierPeerWarning(node) && <div className="alert warning">EasyTier 已运行，但未发现远端 Peer。请确认：后端节点 peers 已指向入口公网 IP:11010，入口服务器已放行 TCP/UDP 11010，两个节点使用相同网络名和网络密钥。</div>}<div className="cap-list">{Object.keys(node.capabilities || {}).filter((key) => node.capabilities[key]).map((key) => <span className="cap" key={key}>{key}</span>)}</div><div className="actions"><button className="secondary" onClick={() => setOpenNodeActions(openNodeActions === node.id ? '' : node.id)}>节点操作</button></div>{openNodeActions === node.id && <NodeActionPanel node={node} onTask={createTask} onDelete={deleteNode} />}</div>)}</div>}</Card>;
  }
  function renderAddAgentPanel() {
    return <div className="sub-panel"><div className="card-head"><h3>添加节点</h3><button className="secondary" onClick={() => setShowAddAgent(false)}>关闭</button></div><p className="muted">测试阶段直接生成完整可执行命令。命令包含 Agent 接入 Token，请勿泄露。</p><div className="grid two form-grid"><Field label="Controller 地址" value={agentForm.controller_url} onChange={(value) => setAgentForm({ ...agentForm, controller_url: value })} /><Field label="节点名称" value={agentForm.node_name} onChange={(value) => setAgentForm({ ...agentForm, node_name: value })} /><Field label="版本" value={agentForm.version} onChange={(value) => setAgentForm({ ...agentForm, version: value })} /><Select label="节点角色" value={agentForm.role} options={roleOptions} onChange={(value) => setAgentForm({ ...agentForm, role: value })} /><label className="check"><input type="checkbox" checked={agentForm.enable_tasks} onChange={(event) => setAgentForm({ ...agentForm, enable_tasks: event.target.checked })} /> 启用任务轮询</label><label className="check"><input type="checkbox" checked={agentForm.enable_write_actions} onChange={(event) => setAgentForm({ ...agentForm, enable_write_actions: event.target.checked })} /> 允许写入动作</label></div>{agentForm.enable_write_actions && <div className="alert warning">允许写入动作后，Agent 可以写入 EasyTier、转发、PBR、DDNS 配置，请只在可信服务器执行。</div>}<div className="actions"><button onClick={generateAgentCommand}>生成一键命令</button><button className="secondary" onClick={() => copyCommand(rootCommand, 'root 一键命令')}>复制 root 命令</button><button className="secondary" onClick={() => copyCommand(sudoCommand, 'sudo 一键命令')}>复制 sudo 命令</button><button className="secondary" onClick={() => setShowAddAgent(false)}>关闭</button></div><div className="command-block danger"><div className="command-title"><strong>推荐：root 用户直接执行</strong><span>完整命令包含 Agent 接入 Token，请勿泄露。</span></div><pre>{recommendedCommand || '点击“生成一键命令”后，这里会显示推荐命令。'}</pre></div><div className="command-block"><div className="command-title"><strong>root 命令</strong><span>适合已用 root 登录的服务器。</span></div><pre>{rootCommand || '尚未生成。'}</pre></div><div className="command-block"><div className="command-title"><strong>普通用户 sudo 命令</strong><span>仅在服务器已安装 sudo 时使用。</span></div><pre>{sudoCommand || '尚未生成。'}</pre></div></div>;
  }
  function renderNetworkProfiles() {
    const onlineNodes = nodes.filter((node) => node.status === 'online');
    const entryNodes = onlineNodes.filter((node) => node.role === 'entry');
    return <><Card title="快速组网"><p className="muted">推荐流程：选择一个在线公网入口节点和一个在线后端节点，面板会自动生成同一组网络名/密钥，并创建两个 apply_network_profile 任务。</p><form onSubmit={quickApplyNetwork} className="grid four form-grid"><Field label="组网名称" value={quickForm.name} onChange={(value) => setQuickForm({ ...quickForm, name: value })} /><Field label="网络名" value={quickForm.network_name} onChange={(value) => setQuickForm({ ...quickForm, network_name: value })} /><Field label="网络密钥" value={quickForm.network_secret} onChange={(value) => setQuickForm({ ...quickForm, network_secret: value })} /><Field label="CIDR" value={quickForm.cidr} onChange={(value) => setQuickForm({ ...quickForm, cidr: value })} /><Field label="监听端口" type="number" value={quickForm.port} onChange={(value) => setQuickForm({ ...quickForm, port: value })} /><NodeSelect label="公网入口节点" value={quickForm.entry_node_id} nodes={entryNodes.length ? entryNodes : onlineNodes} onChange={(value) => setQuickForm({ ...quickForm, entry_node_id: value })} showMeta /><NodeSelect label="后端节点" value={quickForm.backend_node_id} nodes={onlineNodes.filter((node) => node.id !== quickForm.entry_node_id)} onChange={(value) => setQuickForm({ ...quickForm, backend_node_id: value })} showMeta /><div className="check-row"><label><input type="checkbox" checked={quickForm.tcp} onChange={(event) => setQuickForm({ ...quickForm, tcp: event.target.checked })} /> TCP</label><label><input type="checkbox" checked={quickForm.udp} onChange={(event) => setQuickForm({ ...quickForm, udp: event.target.checked })} /> UDP</label></div><button type="submit">创建并应用组网</button></form><div className="alert">入口节点 listeners 自动为 tcp/udp 0.0.0.0:端口，peers 为空；后端节点 peers 自动指向入口公网 IP:端口。任务下发后等待 10~20 秒，再到节点页点击“验证组网”。成功判断：组网成功、Peer 大于 0、延迟有数值、路由为 DIRECT 或可用路径。</div><div className="cards">{[nodes.find((node) => node.id === quickForm.entry_node_id), nodes.find((node) => node.id === quickForm.backend_node_id)].filter(Boolean).map((node) => <div className="mini-card" key={node.id}><h3>{node.name}</h3><p><span className={networkStatusClass(node)}>{networkStatusText(node)}</span></p><p>EasyTier：{trStatus(node.easytier_status)} · Peer：{Number(node.easytier_peer_count || 0)} 个</p><p>延迟：{node.easytier_best_latency_ms ? `${node.easytier_best_latency_ms} ms` : '-'} · 丢包：{node.easytier_packet_loss || '-'} · 路由：{node.easytier_route_type || '-'}</p></div>)}</div></Card><Card title={editingNetworkId ? '编辑高级组网配置' : '创建高级组网配置'}><p className="muted">高级组网配置适合手动调整 listeners / peers。普通测试建议使用上方“快速组网”。</p><form onSubmit={createNetworkProfile} className="grid five form-grid"><Field label="名称" value={networkForm.name} onChange={(value) => setNetworkForm({ ...networkForm, name: value })} required /><Field label="网络名" value={networkForm.network_name} onChange={(value) => setNetworkForm({ ...networkForm, network_name: value })} /><Field label="网络密钥" value={networkForm.network_secret} onChange={(value) => setNetworkForm({ ...networkForm, network_secret: value })} /><Field label="CIDR" value={networkForm.cidr} onChange={(value) => setNetworkForm({ ...networkForm, cidr: value })} /><Select label="协议偏好" value={networkForm.protocol_preference} options={['auto', 'tcp', 'udp', 'wg', 'ws', 'wss']} onChange={(value) => setNetworkForm({ ...networkForm, protocol_preference: value })} /><label>监听地址 listeners<textarea value={networkForm.listeners} onChange={(event) => setNetworkForm({ ...networkForm, listeners: event.target.value })} /></label><label>对端 peers<textarea value={networkForm.peers} onChange={(event) => setNetworkForm({ ...networkForm, peers: event.target.value })} placeholder="tcp://公网入口IP:11010" /></label><label>从入口节点生成 peers<select value={peerSourceNode} onChange={(event) => setPeerSourceNode(event.target.value)}><option value="">选择入口节点</option>{nodes.filter((node) => node.role === 'entry' && node.public_ip).map((node) => <option key={node.id} value={node.id}>{node.name || node.id} / {node.public_ip}</option>)}</select></label><button type="button" className="secondary" onClick={() => fillPeersFromEntry(peerSourceNode)}>从入口节点生成 peers</button><button type="submit">{editingNetworkId ? '保存' : '创建'}</button>{editingNetworkId && <button type="button" className="secondary" onClick={() => { setEditingNetworkId(''); setNetworkForm({ name: '', network_name: 'edge-net', network_secret: '', cidr: '10.144.0.0/16', protocol_preference: 'auto', listeners: 'tcp://0.0.0.0:11010\nudp://0.0.0.0:11010', peers: '' }); }}>取消编辑</button>}</form></Card><Card title="高级组网配置列表" action={<button onClick={() => run('刷新组网配置', refreshNetworkProfiles)}>刷新</button>}><div className="cards">{networkProfiles.map((profile) => <div className="mini-card" key={profile.id}><h3>{profile.name}</h3><p>{profile.network_name} · {profile.cidr} · {profile.protocol_preference}</p><p><strong>listeners</strong>: {(profile.listeners || []).join(', ') || '-'}</p><p><strong>peers</strong>: {(profile.peers || []).join(', ') || '-'}</p><div className="inline"><select value={networkApplyNode[profile.id] || ''} onChange={(event) => setNetworkApplyNode({ ...networkApplyNode, [profile.id]: event.target.value })}><option value="">选择目标节点</option>{nodes.map((node) => <option key={node.id} value={node.id}>{node.name || node.id}</option>)}</select><button onClick={() => applyNetworkProfile(profile)}>应用到节点</button><button className="secondary" onClick={() => editNetworkProfile(profile)}>编辑</button><button className="secondary" onClick={() => setExpandedNetworkId(expandedNetworkId === profile.id ? '' : profile.id)}>查看配置</button><button className="warning" onClick={() => deleteNetworkProfile(profile)}>删除</button></div>{expandedNetworkId === profile.id && <pre className="small">{JSON.stringify(profile, null, 2)}</pre>}</div>)}</div></Card></>;
  }
  function renderEntries() { return <><Card title="创建公网入口"><form onSubmit={createEntry} className="grid four form-grid"><Field label="名称" value={entryForm.name} onChange={(value) => setEntryForm({ ...entryForm, name: value })} required /><NodeSelect label="节点" value={entryForm.node_id} nodes={nodes} onChange={(value) => setEntryForm({ ...entryForm, node_id: value })} /><Field label="监听 IP" value={entryForm.listen_ip} onChange={(value) => setEntryForm({ ...entryForm, listen_ip: value })} /><Field label="起始端口" type="number" value={entryForm.listen_port_start} onChange={(value) => setEntryForm({ ...entryForm, listen_port_start: value })} required /><Field label="结束端口" type="number" value={entryForm.listen_port_end} onChange={(value) => setEntryForm({ ...entryForm, listen_port_end: value })} required /><Select label="协议" value={entryForm.protocol} options={['tcp', 'udp', 'both']} onChange={(value) => setEntryForm({ ...entryForm, protocol: value })} /><Field label="域名" value={entryForm.domain} onChange={(value) => setEntryForm({ ...entryForm, domain: value })} /><Field label="DDNS Provider" value={entryForm.ddns_provider} onChange={(value) => setEntryForm({ ...entryForm, ddns_provider: value })} /><label className="check"><input type="checkbox" checked={entryForm.ddns_enabled} onChange={(event) => setEntryForm({ ...entryForm, ddns_enabled: event.target.checked })} /> 启用 DDNS</label><button type="submit">创建</button></form></Card><ListCard title="公网入口" items={entries} refresh={() => run('刷新公网入口', refreshEntries)} apply={applyEntry} fields={['name', 'node_id', 'listen_ip', 'listen_port_start', 'listen_port_end', 'protocol', 'domain', 'status']} /></>; }
  function renderForwards() { return <><Card title="创建转发规则"><form onSubmit={createForward} className="grid four form-grid"><Field label="名称" value={forwardForm.name} onChange={(value) => setForwardForm({ ...forwardForm, name: value })} required /><Field label="入口 ID" value={forwardForm.entry_id} onChange={(value) => setForwardForm({ ...forwardForm, entry_id: value })} /><NodeSelect label="公网入口节点" value={forwardForm.entry_node_id} nodes={nodes} onChange={(value) => setForwardForm({ ...forwardForm, entry_node_id: value })} /><Select label="协议" value={forwardForm.protocol} options={['tcp', 'udp']} onChange={(value) => setForwardForm({ ...forwardForm, protocol: value })} /><Field label="监听端口" type="number" value={forwardForm.listen_port} onChange={(value) => setForwardForm({ ...forwardForm, listen_port: value })} required /><Select label="目标模式" value={forwardForm.target_mode} options={['local', 'overlay']} onChange={(value) => setForwardForm({ ...forwardForm, target_mode: value })} /><NodeSelect label="目标节点" value={forwardForm.target_node_id} nodes={nodes} onChange={(value) => setForwardForm({ ...forwardForm, target_node_id: value })} /><Field label="目标地址" value={forwardForm.target_host} onChange={(value) => setForwardForm({ ...forwardForm, target_host: value })} required /><Field label="目标端口" type="number" value={forwardForm.target_port} onChange={(value) => setForwardForm({ ...forwardForm, target_port: value })} required /><Field label="备注" value={forwardForm.remark} onChange={(value) => setForwardForm({ ...forwardForm, remark: value })} /><label className="check"><input type="checkbox" checked={forwardForm.enabled} onChange={(event) => setForwardForm({ ...forwardForm, enabled: event.target.checked })} /> 启用</label><button type="submit">创建</button></form></Card><ListCard title="转发规则" items={forwards} refresh={() => run('刷新转发规则', refreshForwards)} apply={applyForward} fields={['name', 'entry_node_id', 'protocol', 'listen_port', 'target_mode', 'target_host', 'target_port', 'enabled']} /></>; }
  function renderPbr() { return <><Card title="创建出口策略"><form onSubmit={createPbrPolicy} className="grid four form-grid"><NodeSelect label="节点" value={pbrForm.node_id} nodes={nodes} onChange={(value) => setPbrForm({ ...pbrForm, node_id: value })} /><Field label="名称" value={pbrForm.name} onChange={(value) => setPbrForm({ ...pbrForm, name: value })} required /><Field label="匹配源地址" value={pbrForm.match_source} onChange={(value) => setPbrForm({ ...pbrForm, match_source: value })} /><Field label="匹配目标地址" value={pbrForm.match_dst} onChange={(value) => setPbrForm({ ...pbrForm, match_dst: value })} /><Field label="协议" value={pbrForm.match_protocol} onChange={(value) => setPbrForm({ ...pbrForm, match_protocol: value })} /><Field label="标记" value={pbrForm.match_mark} onChange={(value) => setPbrForm({ ...pbrForm, match_mark: value })} /><Field label="路由表 ID" type="number" value={pbrForm.table_id} onChange={(value) => setPbrForm({ ...pbrForm, table_id: value })} /><Field label="网关" value={pbrForm.gateway} onChange={(value) => setPbrForm({ ...pbrForm, gateway: value })} /><Field label="出口网卡" value={pbrForm.out_interface} onChange={(value) => setPbrForm({ ...pbrForm, out_interface: value })} /><Field label="优先级" type="number" value={pbrForm.priority} onChange={(value) => setPbrForm({ ...pbrForm, priority: value })} /><label className="check"><input type="checkbox" checked={pbrForm.enabled} onChange={(event) => setPbrForm({ ...pbrForm, enabled: event.target.checked })} /> 启用</label><button type="submit">创建</button></form></Card><ListCard title="出口策略" items={pbrPolicies} refresh={() => run('刷新出口策略', refreshPbrPolicies)} apply={applyPbrPolicy} fields={['name', 'node_id', 'match_source', 'match_dst', 'table_id', 'gateway', 'out_interface', 'priority', 'enabled']} /></>; }
  function renderTasks() {
    const visibleTasks = tasks.filter((task) => (taskFilter === 'all' || task.status === taskFilter) && (taskNodeFilter === 'all' || task.node_id === taskNodeFilter) && (taskActionFilter === 'all' || (taskActionFilter === 'easytier' && easyTierActions.includes(task.action))));
    return <Card title="任务" action={<div className="inline"><select value={taskFilter} onChange={(event) => setTaskFilter(event.target.value)}>{taskStatuses.map((status) => <option key={status} value={status}>{trStatus(status)}</option>)}</select><select value={taskNodeFilter} onChange={(event) => setTaskNodeFilter(event.target.value)}><option value="all">全部节点</option>{nodes.map((node) => <option key={node.id} value={node.id}>{taskNodeOptionLabel(node)}</option>)}</select><button className="secondary" onClick={() => setTaskFilter('failed')}>只看失败</button><button className="secondary" onClick={() => setTaskActionFilter(taskActionFilter === 'easytier' ? 'all' : 'easytier')}>{taskActionFilter === 'easytier' ? '显示全部任务' : '只看 EasyTier'}</button><button onClick={() => run('刷新任务', refreshTasks)}>刷新</button></div>}><TaskTable tasks={visibleTasks} nodes={nodes} onCopy={copyOutput} /></Card>;
  }
  function renderSettings() { return <div className="grid two"><Card title="API 地址"><label>主控地址</label><div className="inline"><input value={apiBaseDraft} onChange={(event) => setApiBaseDraft(event.target.value)} placeholder="默认同源" /><button onClick={saveApiBase}>保存</button></div><p className="muted">当前：{apiBase || '同源'}</p><p className="muted">鉴权状态：{health?.strict_auth ? '已启用 Operator Token' : '测试模式免登录'}</p></Card><Card title="默认路径"><KeyValues rows={[['Agent 配置', '/etc/edge-tunnel/agent'], ['Controller 数据', '/var/lib/edge-tunnel/controller'], ['主控服务', 'edge-tunnel-controller.service'], ['节点服务', 'edge-tunnel-agent.service'], ['EasyTier 服务', 'edge-tunnel-easytier.service']]} /></Card></div>; }

  const page = { dashboard: renderDashboard, nodes: renderNodes, networks: renderNetworkProfiles, entries: renderEntries, forwards: renderForwards, pbr: renderPbr, tasks: renderTasks, settings: renderSettings }[activeTab];
  return <main><header><div><h1>Edge Tunnel Panel</h1><p>基于 EasyTier 的 TCP/UDP 隧道组网面板，用于管理主控、被控节点、公网入口、转发规则、出口策略、DDNS 与任务。</p></div><button onClick={() => run('刷新', refreshAll)} disabled={loading}>{loading ? '处理中...' : '刷新全部'}</button></header><nav>{tabs.map(([id, label]) => <button key={id} className={activeTab === id ? 'active' : ''} onClick={() => setActiveTab(id)}>{label}</button>)}</nav>{alert && <div className={`alert ${alert.type}`}>{alert.message}</div>}<section>{page?.()}</section></main>;
}

function NodeActionPanel({ node, onTask, onDelete }) {
  const button = (action, className = 'secondary') => <button key={action} className={className} title={action} onClick={() => onTask(node.id, action)}>{actionText[action] || action}</button>;
  return <div className="action-panel compact"><section><h4>只读检查</h4><div className="action-grid compact-grid">{checkActions.map((action) => button(action))}</div></section><section><h4>写入维护</h4><p className="muted warning-text">这些操作会修改节点服务状态，请只在可信节点执行。</p><div className="action-grid compact-grid">{maintenanceActions.map((action) => button(action, 'warning'))}</div></section><section><h4>危险操作</h4><div className="action-grid compact-grid"><button className="danger" onClick={() => onDelete(node)}>删除节点记录</button></div></section></div>;
}
function Card({ title, action, children }) { return <article className="card"><div className="card-head"><h2>{title}</h2>{action}</div>{children}</article>; }
function Stat({ title, value, note }) { return <div className="stat"><span>{title}</span><strong>{value}</strong><small>{note}</small></div>; }
function Field({ label, value, onChange, type = 'text', required = false }) { return <label>{label}<input type={type} value={value} required={required} onChange={(event) => onChange(event.target.value)} /></label>; }
function Select({ label, value, options, onChange }) { return <label>{label}<select value={value} onChange={(event) => onChange(event.target.value)}>{options.map((option) => Array.isArray(option) ? <option key={option[0]} value={option[0]}>{option[1]}</option> : <option key={option} value={option}>{option}</option>)}</select></label>; }
function NodeSelect({ label, value, nodes, onChange, showMeta = false }) { return <label>{label}<select value={value} onChange={(event) => onChange(event.target.value)}><option value="">选择节点</option>{nodes.map((node) => <option key={node.id} value={node.id}>{showMeta ? `${node.name || node.id} / ${node.public_ip || '-'} / ${trStatus(node.easytier_status)}` : (node.name || node.id)}</option>)}</select></label>; }
function KeyValues({ rows }) { return <dl className="kv">{rows.map(([key, value]) => <React.Fragment key={key}><dt>{key}</dt><dd>{value || '-'}</dd></React.Fragment>)}</dl>; }
function TaskOutput({ task, onCopy }) {
  const payload = formatOutput(task.payload || {});
  const result = formatOutput(task.result);
  const stdout = formatOutput(task.stdout);
  const stderr = formatOutput(task.stderr);
  const error = formatOutput(task.error);
  const content = [error, result, stdout, stderr].filter((item) => item && item !== '-').join('\n\n') || '-';
  const parsedResult = parseJSONValue(task.result);
  return <details open={task.status === 'failed' || task.action === 'verify_network_connectivity'}><summary>{task.status === 'failed' ? '查看错误' : '查看详情'}</summary>{/no space left on device|磁盘空间不足/i.test(content) && <div className="alert error">该节点磁盘空间不足，建议换更大磁盘节点测试，或清理系统后重试。</div>}{task.action === 'verify_network_connectivity' && <div className={parsedResult.network_ok ? 'alert success' : 'alert warning'}>{parsedResult.network_ok ? `组网成功，远端 Peer ${parsedResult.peer_count || 0} 个，最佳延迟 ${parsedResult.best_latency_ms || '-'} ms，丢包 ${parsedResult.packet_loss || '-'}，隧道 ${safeList(parsedResult.tunnels).join(', ') || '-'}，路由 ${parsedResult.route_type || '-'}。` : (parsedResult.reason || '组网未验证通过。')}</div>}{onCopy && <button className="secondary mini" onClick={() => onCopy(content)}>复制输出</button>}{['apply_network_profile', 'verify_easytier_status', 'verify_network_connectivity'].includes(task.action) && <div className="task-kv"><span>config_path：{parsedResult.config_path || '-'}</span><span>service_path：{parsedResult.service_path || '-'}</span><span>binary_path：{parsedResult.binary_path || '-'}</span><span>easytier_status：{parsedResult.easytier_status || '-'}</span><span>network_ok：{String(parsedResult.network_ok ?? '-')}</span><span>peer_count：{parsedResult.peer_count ?? '-'}</span><span>best_latency_ms：{parsedResult.best_latency_ms ?? '-'}</span><span>packet_loss：{parsedResult.packet_loss || '-'}</span><span>tunnels：{safeList(parsedResult.tunnels).join(', ') || '-'}</span><span>route_type：{parsedResult.route_type || '-'}</span><span>has_remote_peer：{String(parsedResult.has_remote_peer ?? '-')}</span><span>listeners：{(parsedResult.listeners || []).join(', ') || '-'}</span><span>peers：{(parsedResult.peers || []).join(', ') || '-'}</span></div>}{(parsedResult.peer_info || parsedResult.peer_info_raw) && <pre className="small task-output">peer_info:{'\n'}{parsedResult.peer_info || parsedResult.peer_info_raw}</pre>}{parsedResult.route_info_raw && <pre className="small task-output">route_info:{'\n'}{parsedResult.route_info_raw}</pre>}<pre className="small task-output">{`task id: ${task.id}\nnode id: ${task.node_id || '-'}\naction: ${task.action}\naction label: ${actionText[task.action] || task.action}\nstatus: ${task.status}\ncreated_at: ${task.created_at || '-'}\nstarted_at: ${task.started_at || '-'}\nfinished_at: ${task.finished_at || '-'}\n\npayload:\n${payload}\n\nresult:\n${result}\n\nstdout:\n${stdout}\n\nstderr:\n${stderr}\n\nerror:\n${error}`}</pre></details>;
}
function ListCard({ title, items, fields, refresh, apply }) { return <Card title={title} action={<button onClick={refresh}>刷新</button>}><div className="table-wrap"><table><thead><tr>{fields.map((field) => <th key={field}>{field}</th>)}<th>操作</th></tr></thead><tbody>{items.map((item) => <tr key={item.id}>{fields.map((field) => <td key={field}>{String(item[field] ?? '-')}</td>)}<td><button onClick={() => apply(item)}>应用</button></td></tr>)}</tbody></table></div></Card>; }
function TaskTable({ tasks, compact = false, nodes = [], onCopy }) {
  if (!tasks.length) return <p className="muted">暂无任务。</p>;
  return <div className="table-wrap"><table><thead><tr><th>ID</th><th>节点</th><th>动作</th><th>状态</th><th>创建时间</th>{!compact && <th>开始</th>}{!compact && <th>完成</th>}{!compact && <th>输出</th>}</tr></thead><tbody>{tasks.map((task) => <tr key={task.id}><td><code>{task.id}</code></td><td>{taskNodeLabel(task, nodes)}</td><td title={task.action}>{actionText[task.action] || task.action}</td><td><span className={statusClass(task.status)}>{trStatus(task.status)}</span></td><td>{formatTime(task.created_at)}</td>{!compact && <td>{formatTime(task.started_at)}</td>}{!compact && <td>{formatTime(task.finished_at)}</td>}{!compact && <td><TaskOutput task={task} onCopy={onCopy} /></td>}</tr>)}</tbody></table></div>;
}

createRoot(document.getElementById('root')).render(<App />);
