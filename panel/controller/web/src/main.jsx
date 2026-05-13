import React, { useEffect, useMemo, useState } from 'react';
import { createRoot } from 'react-dom/client';
import './styles.css';

const TOKEN_KEY = 'edgeTunnelOperatorToken';
const API_BASE_KEY = 'edgeTunnelApiBase';
const DEFAULT_VERSION = 'v0.1.6-test';

const tabs = [
  ['dashboard', '总览'],
  ['nodes', '节点'],
  ['networks', '组网配置'],
  ['entries', '公网入口'],
  ['forwards', '转发规则'],
  ['pbr', '出口策略'],
  ['tasks', '任务'],
  ['settings', '设置']
];

const readonlyActions = [
  'collect_agent_status',
  'verify_agent_config',
  'verify_easytier_status',
  'verify_forward_rules',
  'verify_pbr_rules',
  'verify_ddns_status',
  'restart_easytier',
  'restart_agent'
];

const roleOptions = [
  ['backend', '后端节点'],
  ['entry', '公网入口节点'],
  ['relay', '中继节点'],
  ['exit', '出口节点']
];

const roleText = Object.fromEntries(roleOptions);

const actionText = {
  collect_agent_status: '状态检查',
  verify_agent_config: '验证配置',
  verify_easytier_status: '验证 EasyTier',
  verify_forward_rules: '验证转发',
  verify_pbr_rules: '验证出口策略',
  verify_ddns_status: '验证 DDNS',
  restart_easytier: '重启 EasyTier',
  restart_agent: '重启 Agent',
  apply_network_profile: '应用组网配置'
};

const statusText = {
  online: '在线',
  stale: '可能离线',
  offline: '离线',
  pending: '等待中',
  running: '执行中',
  succeeded: '成功',
  failed: '失败',
  expired: '已过期',
  cancelled: '已取消',
  all: '全部',
  active: '运行中',
  inactive: '未运行',
  missing_binary: '未安装',
  missing_config: '缺少配置',
  service_missing: '服务缺失'
};

const taskStatuses = ['all', 'pending', 'running', 'succeeded', 'failed', 'expired', 'cancelled'];

function browserControllerURL() {
  if (typeof window === 'undefined') return 'http://CONTROLLER_HOST:18080';
  return `${window.location.protocol}//${window.location.host}`;
}

function normalizeBase(value) {
  return value.trim().replace(/\/+$/, '');
}

function formatTime(value) {
  if (!value) return '-';
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? '-' : date.toLocaleString();
}

function safeList(value) {
  return Array.isArray(value) ? value : [];
}

function lines(value) {
  return String(value || '').split(/\r?\n/).map((item) => item.trim()).filter(Boolean);
}

function summarize(value) {
  if (value === null || value === undefined || value === '') return '-';
  const text = typeof value === 'string' ? value : JSON.stringify(value, null, 2);
  return text.length > 420 ? `${text.slice(0, 420)}...` : text;
}

function statusClass(status) {
  return `badge ${status || 'unknown'}`;
}

function trStatus(status) {
  return statusText[status] || status || '-';
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
  const [taskFilter, setTaskFilter] = useState('all');
  const [showAddAgent, setShowAddAgent] = useState(false);
  const [openNodeActions, setOpenNodeActions] = useState('');

  const [agentForm, setAgentForm] = useState({
    controller_url: browserControllerURL(),
    node_name: 'edge-node-1',
    role: 'backend',
    version: DEFAULT_VERSION,
    enable_tasks: true,
    enable_write_actions: true,
  });
  const [rootCommand, setRootCommand] = useState('');
  const [sudoCommand, setSudoCommand] = useState('');
  const [recommendedCommand, setRecommendedCommand] = useState('');

  const [networkForm, setNetworkForm] = useState({
    name: '',
    network_name: 'edge-net',
    network_secret: '',
    cidr: '10.144.0.0/16',
    protocol_preference: 'auto',
    listeners: 'tcp://0.0.0.0:11010\nudp://0.0.0.0:11010',
    peers: ''
  });
  const [networkApplyNode, setNetworkApplyNode] = useState({});
  const [editingNetworkId, setEditingNetworkId] = useState('');
  const [expandedNetworkId, setExpandedNetworkId] = useState('');

  const [entryForm, setEntryForm] = useState({
    name: '',
    node_id: '',
    listen_ip: '0.0.0.0',
    listen_port_start: '',
    listen_port_end: '',
    protocol: 'both',
    domain: '',
    ddns_enabled: false,
    ddns_provider: ''
  });

  const [forwardForm, setForwardForm] = useState({
    name: '',
    entry_id: '',
    entry_node_id: '',
    protocol: 'tcp',
    listen_port: '',
    target_mode: 'local',
    target_node_id: '',
    target_host: '',
    target_port: '',
    enabled: true,
    remark: ''
  });

  const [pbrForm, setPbrForm] = useState({
    node_id: '',
    name: '',
    match_source: '',
    match_dst: '',
    match_protocol: '',
    match_mark: '',
    table_id: '',
    gateway: '',
    out_interface: '',
    priority: '',
    enabled: true
  });

  const counts = useMemo(() => {
    const nodeCounts = { online: 0, stale: 0, offline: 0 };
    for (const node of nodes) {
      if (node.status === 'online') nodeCounts.online += 1;
      else if (node.status === 'stale') nodeCounts.stale += 1;
      else nodeCounts.offline += 1;
    }
    const taskCounts = { pending: 0, running: 0, succeeded: 0, failed: 0 };
    for (const task of tasks) {
      if (taskCounts[task.status] !== undefined) taskCounts[task.status] += 1;
    }
    return { nodeCounts, taskCounts };
  }, [nodes, tasks]);

  async function api(path, options = {}) {
    const method = options.method || (options.body === undefined ? 'GET' : 'POST');
    const headers = { Accept: 'application/json' };
    if (options.body !== undefined) headers['Content-Type'] = 'application/json';
    if (token) headers.Authorization = `Bearer ${token}`;
    const response = await fetch(`${normalizeBase(apiBase)}/api/v1${path}`, {
      method,
      headers,
      body: options.body === undefined ? undefined : JSON.stringify(options.body)
    });
    let payload = null;
    try {
      payload = await response.json();
    } catch {
      payload = null;
    }
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

  async function refreshHealth() {
    const data = await api('/health');
    setHealth(data);
    return data;
  }

  async function refreshNodes() {
    const data = safeList(await api('/nodes'));
    setNodes(data);
    return data;
  }

  async function refreshTasks() {
    const data = safeList(await api('/tasks'));
    setTasks(data);
    return data;
  }

  async function refreshNetworkProfiles() {
    const data = safeList(await api('/network-profiles'));
    setNetworkProfiles(data);
    return data;
  }

  async function refreshEntries() {
    const data = safeList(await api('/entries'));
    setEntries(data);
    return data;
  }

  async function refreshForwards() {
    const data = safeList(await api('/forwards'));
    setForwards(data);
    return data;
  }

  async function refreshPbrPolicies() {
    const data = safeList(await api('/pbr-policies'));
    setPbrPolicies(data);
    return data;
  }

  async function refreshDdnsProfiles() {
    const data = safeList(await api('/ddns'));
    setDdnsProfiles(data);
    return data;
  }

  async function refreshAll() {
    await refreshHealth();
    if (token) {
      await Promise.all([
        refreshNodes(),
        refreshTasks(),
        refreshNetworkProfiles(),
        refreshEntries(),
        refreshForwards(),
        refreshPbrPolicies(),
        refreshDdnsProfiles()
      ]);
    }
  }

  useEffect(() => {
    run('刷新', refreshAll);
  }, []);

  function saveToken() {
    localStorage.setItem(TOKEN_KEY, tokenDraft);
    setToken(tokenDraft);
    setAlert({ type: 'success', message: 'Operator Token 已保存' });
  }

  function clearToken() {
    localStorage.removeItem(TOKEN_KEY);
    setToken('');
    setTokenDraft('');
    setAlert({ type: 'success', message: 'Operator Token 已清除' });
  }

  function saveApiBase() {
    const next = normalizeBase(apiBaseDraft);
    if (next) localStorage.setItem(API_BASE_KEY, next);
    else localStorage.removeItem(API_BASE_KEY);
    setApiBase(next);
    setAlert({ type: 'success', message: 'API 地址已保存' });
  }

  async function createTask(nodeId, action) {
    await run('创建任务', async () => {
      await api('/tasks', { body: { node_id: nodeId, action, payload: {} } });
      await refreshTasks();
    });
  }

  async function generateAgentCommand() {
    const data = await run('生成一键命令', async () =>
      api('/bootstrap/agent-install-command', {
        body: { ...agentForm }
      })
    );
    if (!data?.root_command && !data?.sudo_command) return;
    setRootCommand(data.root_command || '');
    setSudoCommand(data.sudo_command || '');
    setRecommendedCommand(data.recommended_command || data.root_command || '');
  }

  async function copyCommand(text, label) {
    if (!text) {
      setAlert({ type: 'error', message: '请先生成一键命令。' });
      return;
    }
    await navigator.clipboard.writeText(text);
    setAlert({ type: 'success', message: '已复制' + label + '，请到被控服务器执行。' });
  }

  function networkPayload() {
    return {
      ...networkForm,
      listeners: lines(networkForm.listeners),
      peers: lines(networkForm.peers)
    };
  }

  async function createNetworkProfile(event) {
    event.preventDefault();
    await run(editingNetworkId ? '更新组网配置' : '创建组网配置', async () => {
      const body = networkPayload();
      if (editingNetworkId) {
        await api('/network-profiles/' + editingNetworkId, { method: 'PUT', body });
      } else {
        await api('/network-profiles', { body });
      }
      setNetworkForm({ name: '', network_name: 'edge-net', network_secret: '', cidr: '10.144.0.0/16', protocol_preference: 'auto', listeners: 'tcp://0.0.0.0:11010\nudp://0.0.0.0:11010', peers: '' });
      setEditingNetworkId('');
      await refreshNetworkProfiles();
    });
  }

  function editNetworkProfile(profile) {
    setEditingNetworkId(profile.id);
    setNetworkForm({
      name: profile.name || '',
      network_name: profile.network_name || 'edge-net',
      network_secret: profile.network_secret || '',
      cidr: profile.cidr || '10.144.0.0/16',
      protocol_preference: profile.protocol_preference || 'auto',
      listeners: (profile.listeners || []).join('\n') || 'tcp://0.0.0.0:11010\nudp://0.0.0.0:11010',
      peers: (profile.peers || []).join('\n')
    });
  }

  async function deleteNetworkProfile(profile) {
    if (!window.confirm('确认删除组网配置“' + (profile.name || profile.id) + '”？')) return;
    await run('删除组网配置', async () => {
      await api('/network-profiles/' + profile.id, { method: 'DELETE' });
      await refreshNetworkProfiles();
    });
  }

  async function applyNetworkProfile(profile) {
    const nodeId = networkApplyNode[profile.id] || '';
    if (!nodeId) {
      setAlert({ type: 'error', message: '请先选择目标节点' });
      return;
    }
    await run('应用组网配置', async () => {
      await api('/network-profiles/' + profile.id + '/apply', { body: { node_id: nodeId } });
      await refreshTasks();
      setAlert({ type: 'success', message: '已创建组网下发任务，请到任务页面查看结果。' });
    });
  }

  async function createEntry(event) {
    event.preventDefault();
    await run('创建公网入口', async () => {
      await api('/entries', {
        body: {
          ...entryForm,
          listen_port_start: Number(entryForm.listen_port_start),
          listen_port_end: Number(entryForm.listen_port_end)
        }
      });
      setEntryForm({ ...entryForm, name: '', domain: '' });
      await refreshEntries();
    });
  }

  async function applyEntry(entry) {
    await run('应用公网入口', async () => {
      await api(`/entries/${entry.id}/apply`, { body: { node_id: entry.node_id, entry_id: entry.id } });
      await refreshTasks();
    });
  }

  async function createForward(event) {
    event.preventDefault();
    await run('创建转发规则', async () => {
      await api('/forwards', {
        body: {
          ...forwardForm,
          listen_port: Number(forwardForm.listen_port),
          target_port: Number(forwardForm.target_port)
        }
      });
      setForwardForm({ ...forwardForm, name: '', listen_port: '', target_host: '', target_port: '', remark: '' });
      await refreshForwards();
    });
  }

  async function applyForward(forward) {
    await run('应用转发规则', async () => {
      await api(`/forwards/${forward.id}/apply`, {
        body: { entry_node_id: forward.entry_node_id, forward_id: forward.id }
      });
      await refreshTasks();
    });
  }

  async function createPbrPolicy(event) {
    event.preventDefault();
    await run('创建出口策略', async () => {
      await api('/pbr-policies', {
        body: {
          ...pbrForm,
          table_id: Number(pbrForm.table_id),
          priority: Number(pbrForm.priority)
        }
      });
      setPbrForm({ ...pbrForm, name: '', match_source: '', match_dst: '', gateway: '', out_interface: '' });
      await refreshPbrPolicies();
    });
  }

  async function applyPbrPolicy(policy) {
    await run('应用出口策略', async () => {
      await api(`/pbr-policies/${policy.id}/apply`, { body: { node_id: policy.node_id, pbr_policy_id: policy.id } });
      await refreshTasks();
    });
  }

  function renderDashboard() {
    const recent = [...tasks].sort((a, b) => String(b.created_at).localeCompare(String(a.created_at))).slice(0, 5);
    const strictAuth = health?.strict_auth === true;
    return (
      <>
        {!strictAuth && <div className="alert warning">当前为测试模式，Web API 未启用 Operator Token 鉴权。</div>}
        <div className="grid two">
          {strictAuth && <Card title="登录 / Token">
            <label>Operator Token</label>
            <div className="inline">
              <input type={showToken ? 'text' : 'password'} value={tokenDraft} onChange={(event) => setTokenDraft(event.target.value)} placeholder="输入主控 Operator Token" />
              <button type="button" onClick={() => setShowToken(!showToken)}>{showToken ? '隐藏' : '显示'}</button>
            </div>
            <div className="actions">
              <button onClick={saveToken}>保存 Token</button>
              <button className="secondary" onClick={clearToken}>清除 Token</button>
              <button className="secondary" onClick={() => run('测试连接', refreshHealth)}>测试连接</button>
            </div>
          </Card>}
          <Card title="主控状态">
            <KeyValues rows={[['名称', health?.name], ['版本', health?.version], ['提交', health?.build_commit], ['构建时间', health?.build_time], ['鉴权状态', strictAuth ? '已启用 Operator Token' : '测试模式免登录']]} />
          </Card>
        </div>
        <div className="grid four">
          <Stat title="节点" value={nodes.length} note={`在线 ${counts.nodeCounts.online} · 可能离线 ${counts.nodeCounts.stale} · 离线 ${counts.nodeCounts.offline}`} />
          <Stat title="进行中任务" value={counts.taskCounts.pending + counts.taskCounts.running} note={`等待中 ${counts.taskCounts.pending} · 执行中 ${counts.taskCounts.running}`} />
          <Stat title="已完成任务" value={counts.taskCounts.succeeded + counts.taskCounts.failed} note={`成功 ${counts.taskCounts.succeeded} · 失败 ${counts.taskCounts.failed}`} />
          <Stat title="DDNS 配置" value={ddnsProfiles.length} note="作为节点/入口内置能力" />
        </div>
        <Card title="最近任务" action={<button onClick={() => run('刷新', refreshAll)}>刷新</button>}>
          <TaskTable tasks={recent} compact />
        </Card>
      </>
    );
  }

  function renderNodes() {
    return (
      <Card title="节点" action={<div className="inline"><button onClick={() => run('刷新节点', refreshNodes)}>刷新</button><button onClick={() => setShowAddAgent(true)}>添加节点</button></div>}>
        <p className="muted">管理已接入的被控服务器。点击“添加节点”生成一键命令，在被控服务器执行后会自动上线。</p>
        {showAddAgent && renderAddAgentPanel()}
        {!nodes.length ? (
          <div className="empty-state">
            <h3>暂无节点</h3>
            <p>点击“添加节点”生成一键 Agent 接入命令。</p>
            <button onClick={() => setShowAddAgent(true)}>添加节点</button>
          </div>
        ) : (
          <div className="node-grid">
            {nodes.map((node) => (
              <div className="node-card" key={node.id}>
                <div className="node-card-head">
                  <div>
                    <h3>{node.name || node.id}</h3>
                    <code title={node.id}>{String(node.id || '-').slice(0, 16)}</code>
                  </div>
                  <div className="inline"><span className="badge">{roleText[node.role] || node.role || '-'}</span><span className={statusClass(node.status)}>{trStatus(node.status)}</span></div>
                </div>
                <KeyValues rows={[
                  ['主机名', node.hostname],
                  ['公网 IP', node.public_ip],
                  ['内网 IP', node.private_ip],
                  ['EasyTier IP', node.easytier_ip],
                  ['EasyTier 状态', trStatus(node.easytier_status)],
                  ['最后上报', formatTime(node.last_seen_at)]
                ]} />
                <div className="cap-list">{Object.keys(node.capabilities || {}).filter((key) => node.capabilities[key]).map((key) => <span className="cap" key={key}>{key}</span>)}</div>
                <div className="actions"><button className="secondary" onClick={() => setOpenNodeActions(openNodeActions === node.id ? '' : node.id)}>节点操作</button></div>
                {openNodeActions === node.id && <div className="action-panel">
                  {readonlyActions.map((action) => <button key={action} className={action.startsWith('restart_') ? 'warning' : 'secondary'} onClick={() => createTask(node.id, action)}>{actionText[action] || action}</button>)}
                  <p className="muted">重启动作会修改节点服务状态，请只在可信节点执行。</p>
                </div>}
              </div>
            ))}
          </div>
        )}
      </Card>
    );
  }

  function renderAddAgentPanel() {
    return (
      <div className="sub-panel">
        <div className="card-head">
          <h3>添加节点</h3>
          <button className="secondary" onClick={() => setShowAddAgent(false)}>关闭</button>
        </div>
        <p className="muted">测试阶段直接生成完整可执行命令。命令包含 Agent 接入 Token，请勿泄露。</p>
        <div className="grid two form-grid">
          <Field label="Controller 地址" value={agentForm.controller_url} onChange={(value) => setAgentForm({ ...agentForm, controller_url: value })} />
          <Field label="节点名称" value={agentForm.node_name} onChange={(value) => setAgentForm({ ...agentForm, node_name: value })} />
          <Field label="版本" value={agentForm.version} onChange={(value) => setAgentForm({ ...agentForm, version: value })} />
          <Select label="节点角色" value={agentForm.role} options={roleOptions} onChange={(value) => setAgentForm({ ...agentForm, role: value })} />
          <label className="check"><input type="checkbox" checked={agentForm.enable_tasks} onChange={(event) => setAgentForm({ ...agentForm, enable_tasks: event.target.checked })} /> 启用任务轮询</label>
          <label className="check"><input type="checkbox" checked={agentForm.enable_write_actions} onChange={(event) => setAgentForm({ ...agentForm, enable_write_actions: event.target.checked })} /> 允许写入动作</label>
        </div>
        {agentForm.enable_write_actions && <div className="alert warning">允许写入动作后，Agent 可以写入 EasyTier、转发、PBR、DDNS 配置，请只在可信服务器执行。</div>}
        <div className="actions">
          <button onClick={generateAgentCommand}>生成一键命令</button>
          <button className="secondary" onClick={() => copyCommand(rootCommand, 'root 命令')}>复制 root 命令</button>
          <button className="secondary" onClick={() => copyCommand(sudoCommand, 'sudo 命令')}>复制 sudo 命令</button>
          <button className="secondary" onClick={() => setShowAddAgent(false)}>关闭</button>
        </div>
        <div className="alert warning">如果当前是 root 登录服务器，复制 root 命令；普通用户才使用 sudo 命令。</div>
        <div className="command-block danger">
          <div className="command-title"><strong>推荐：root 用户直接执行</strong><span>完整命令包含 Agent 接入 Token，请勿泄露。</span></div>
          <pre>{recommendedCommand || '点击“生成一键命令”后，这里会显示推荐命令。'}</pre>
        </div>
        <div className="command-block">
          <div className="command-title"><strong>root 命令</strong><span>适合已用 root 登录的服务器。</span></div>
          <pre>{rootCommand || '尚未生成。'}</pre>
        </div>
        <div className="command-block">
          <div className="command-title"><strong>普通用户 sudo 命令</strong><span>仅在服务器已安装 sudo 时使用。</span></div>
          <pre>{sudoCommand || '尚未生成。'}</pre>
        </div>
        {recommendedCommand && <ol className="steps">
          <li>根据登录用户选择 root 命令或 sudo 命令</li>
          <li>点击对应复制按钮</li>
          <li>到被控服务器执行</li>
          <li>回到“节点”页面点击刷新查看在线状态</li>
        </ol>}
      </div>
    );
  }

  function renderNetworkProfiles() {
    return (
      <>
        <Card title={editingNetworkId ? '编辑组网配置' : '创建组网配置'}>
          <form onSubmit={createNetworkProfile} className="grid five form-grid">
            <Field label="名称" value={networkForm.name} onChange={(value) => setNetworkForm({ ...networkForm, name: value })} required />
            <Field label="网络名" value={networkForm.network_name} onChange={(value) => setNetworkForm({ ...networkForm, network_name: value })} />
            <Field label="网络密钥" value={networkForm.network_secret} onChange={(value) => setNetworkForm({ ...networkForm, network_secret: value })} />
            <Field label="CIDR" value={networkForm.cidr} onChange={(value) => setNetworkForm({ ...networkForm, cidr: value })} />
            <Select label="协议偏好" value={networkForm.protocol_preference} options={['auto', 'tcp', 'udp', 'wg', 'ws', 'wss']} onChange={(value) => setNetworkForm({ ...networkForm, protocol_preference: value })} />
            <label>监听地址 listeners<textarea value={networkForm.listeners} onChange={(event) => setNetworkForm({ ...networkForm, listeners: event.target.value })} /></label>
            <label>对端 peers<textarea value={networkForm.peers} onChange={(event) => setNetworkForm({ ...networkForm, peers: event.target.value })} placeholder="tcp://公网入口IP:11010" /></label>
            <button type="submit">{editingNetworkId ? '保存' : '创建'}</button>
            {editingNetworkId && <button type="button" className="secondary" onClick={() => { setEditingNetworkId(''); setNetworkForm({ name: '', network_name: 'edge-net', network_secret: '', cidr: '10.144.0.0/16', protocol_preference: 'auto', listeners: 'tcp://0.0.0.0:11010\nudp://0.0.0.0:11010', peers: '' }); }}>取消编辑</button>}
          </form>
        </Card>
        <Card title="组网配置" action={<button onClick={() => run('刷新组网配置', refreshNetworkProfiles)}>刷新</button>}>
          <div className="cards">
            {networkProfiles.map((profile) => (
              <div className="mini-card" key={profile.id}>
                <h3>{profile.name}</h3>
                <p>{profile.network_name} · {profile.cidr} · {profile.protocol_preference}</p>
                <p><strong>listeners</strong>: {(profile.listeners || []).join(', ') || '-'}</p>
                <p><strong>peers</strong>: {(profile.peers || []).join(', ') || '-'}</p>
                <div className="inline">
                  <select value={networkApplyNode[profile.id] || ''} onChange={(event) => setNetworkApplyNode({ ...networkApplyNode, [profile.id]: event.target.value })}>
                    <option value="">选择目标节点</option>
                    {nodes.map((node) => <option key={node.id} value={node.id}>{node.name || node.id}</option>)}
                  </select>
                  <button onClick={() => applyNetworkProfile(profile)}>应用到节点</button>
                  <button className="secondary" onClick={() => editNetworkProfile(profile)}>编辑</button>
                  <button className="secondary" onClick={() => setExpandedNetworkId(expandedNetworkId === profile.id ? '' : profile.id)}>查看配置</button>
                  <button className="warning" onClick={() => deleteNetworkProfile(profile)}>删除</button>
                </div>
                {expandedNetworkId === profile.id && <pre className="small">{JSON.stringify(profile, null, 2)}</pre>}
              </div>
            ))}
          </div>
        </Card>
      </>
    );
  }

  function renderEntries() {
    return (
      <>
        <Card title="创建公网入口">
          <form onSubmit={createEntry} className="grid four form-grid">
            <Field label="名称" value={entryForm.name} onChange={(value) => setEntryForm({ ...entryForm, name: value })} required />
            <NodeSelect label="节点" value={entryForm.node_id} nodes={nodes} onChange={(value) => setEntryForm({ ...entryForm, node_id: value })} />
            <Field label="监听 IP" value={entryForm.listen_ip} onChange={(value) => setEntryForm({ ...entryForm, listen_ip: value })} />
            <Field label="起始端口" type="number" value={entryForm.listen_port_start} onChange={(value) => setEntryForm({ ...entryForm, listen_port_start: value })} required />
            <Field label="结束端口" type="number" value={entryForm.listen_port_end} onChange={(value) => setEntryForm({ ...entryForm, listen_port_end: value })} required />
            <Select label="协议" value={entryForm.protocol} options={['tcp', 'udp', 'both']} onChange={(value) => setEntryForm({ ...entryForm, protocol: value })} />
            <Field label="域名" value={entryForm.domain} onChange={(value) => setEntryForm({ ...entryForm, domain: value })} />
            <Field label="DDNS Provider" value={entryForm.ddns_provider} onChange={(value) => setEntryForm({ ...entryForm, ddns_provider: value })} />
            <label className="check"><input type="checkbox" checked={entryForm.ddns_enabled} onChange={(event) => setEntryForm({ ...entryForm, ddns_enabled: event.target.checked })} /> 启用 DDNS</label>
            <button type="submit">创建</button>
          </form>
        </Card>
        <ListCard title="公网入口" items={entries} refresh={() => run('刷新公网入口', refreshEntries)} apply={applyEntry} fields={['name', 'node_id', 'listen_ip', 'listen_port_start', 'listen_port_end', 'protocol', 'domain', 'status']} />
      </>
    );
  }

  function renderForwards() {
    return (
      <>
        <Card title="创建转发规则">
          <form onSubmit={createForward} className="grid four form-grid">
            <Field label="名称" value={forwardForm.name} onChange={(value) => setForwardForm({ ...forwardForm, name: value })} required />
            <Field label="入口 ID" value={forwardForm.entry_id} onChange={(value) => setForwardForm({ ...forwardForm, entry_id: value })} />
            <NodeSelect label="公网入口节点" value={forwardForm.entry_node_id} nodes={nodes} onChange={(value) => setForwardForm({ ...forwardForm, entry_node_id: value })} />
            <Select label="协议" value={forwardForm.protocol} options={['tcp', 'udp']} onChange={(value) => setForwardForm({ ...forwardForm, protocol: value })} />
            <Field label="监听端口" type="number" value={forwardForm.listen_port} onChange={(value) => setForwardForm({ ...forwardForm, listen_port: value })} required />
            <Select label="目标模式" value={forwardForm.target_mode} options={['local', 'overlay']} onChange={(value) => setForwardForm({ ...forwardForm, target_mode: value })} />
            <NodeSelect label="目标节点" value={forwardForm.target_node_id} nodes={nodes} onChange={(value) => setForwardForm({ ...forwardForm, target_node_id: value })} />
            <Field label="目标地址" value={forwardForm.target_host} onChange={(value) => setForwardForm({ ...forwardForm, target_host: value })} required />
            <Field label="目标端口" type="number" value={forwardForm.target_port} onChange={(value) => setForwardForm({ ...forwardForm, target_port: value })} required />
            <Field label="备注" value={forwardForm.remark} onChange={(value) => setForwardForm({ ...forwardForm, remark: value })} />
            <label className="check"><input type="checkbox" checked={forwardForm.enabled} onChange={(event) => setForwardForm({ ...forwardForm, enabled: event.target.checked })} /> 启用</label>
            <button type="submit">创建</button>
          </form>
        </Card>
        <ListCard title="转发规则" items={forwards} refresh={() => run('刷新转发规则', refreshForwards)} apply={applyForward} fields={['name', 'entry_node_id', 'protocol', 'listen_port', 'target_mode', 'target_host', 'target_port', 'enabled']} />
      </>
    );
  }

  function renderPbr() {
    return (
      <>
        <Card title="创建出口策略">
          <form onSubmit={createPbrPolicy} className="grid four form-grid">
            <NodeSelect label="节点" value={pbrForm.node_id} nodes={nodes} onChange={(value) => setPbrForm({ ...pbrForm, node_id: value })} />
            <Field label="名称" value={pbrForm.name} onChange={(value) => setPbrForm({ ...pbrForm, name: value })} required />
            <Field label="匹配源地址" value={pbrForm.match_source} onChange={(value) => setPbrForm({ ...pbrForm, match_source: value })} />
            <Field label="匹配目标地址" value={pbrForm.match_dst} onChange={(value) => setPbrForm({ ...pbrForm, match_dst: value })} />
            <Field label="协议" value={pbrForm.match_protocol} onChange={(value) => setPbrForm({ ...pbrForm, match_protocol: value })} />
            <Field label="标记" value={pbrForm.match_mark} onChange={(value) => setPbrForm({ ...pbrForm, match_mark: value })} />
            <Field label="路由表 ID" type="number" value={pbrForm.table_id} onChange={(value) => setPbrForm({ ...pbrForm, table_id: value })} />
            <Field label="网关" value={pbrForm.gateway} onChange={(value) => setPbrForm({ ...pbrForm, gateway: value })} />
            <Field label="出口网卡" value={pbrForm.out_interface} onChange={(value) => setPbrForm({ ...pbrForm, out_interface: value })} />
            <Field label="优先级" type="number" value={pbrForm.priority} onChange={(value) => setPbrForm({ ...pbrForm, priority: value })} />
            <label className="check"><input type="checkbox" checked={pbrForm.enabled} onChange={(event) => setPbrForm({ ...pbrForm, enabled: event.target.checked })} /> 启用</label>
            <button type="submit">创建</button>
          </form>
        </Card>
        <ListCard title="出口策略" items={pbrPolicies} refresh={() => run('刷新出口策略', refreshPbrPolicies)} apply={applyPbrPolicy} fields={['name', 'node_id', 'match_source', 'match_dst', 'table_id', 'gateway', 'out_interface', 'priority', 'enabled']} />
      </>
    );
  }

  function renderTasks() {
    const visibleTasks = taskFilter === 'all' ? tasks : tasks.filter((task) => task.status === taskFilter);
    return (
      <Card title="任务" action={<div className="inline"><select value={taskFilter} onChange={(event) => setTaskFilter(event.target.value)}>{taskStatuses.map((status) => <option key={status} value={status}>{trStatus(status)}</option>)}</select><button onClick={() => run('刷新任务', refreshTasks)}>刷新</button></div>}>
        <TaskTable tasks={visibleTasks} />
      </Card>
    );
  }

  function renderSettings() {
    return (
      <div className="grid two">
        <Card title="API 地址">
          <label>主控地址</label>
          <div className="inline">
            <input value={apiBaseDraft} onChange={(event) => setApiBaseDraft(event.target.value)} placeholder="默认同源" />
            <button onClick={saveApiBase}>保存</button>
          </div>
          <p className="muted">当前：{apiBase || '同源'}</p>
          <p className="muted">鉴权状态：{health?.strict_auth ? '已启用 Operator Token' : '测试模式免登录'}</p>
        </Card>
        <Card title="默认路径">
          <KeyValues rows={[
            ['Agent 配置', '/etc/edge-tunnel/agent'],
            ['Controller 数据', '/var/lib/edge-tunnel/controller'],
            ['主控服务', 'edge-tunnel-controller.service'],
            ['节点服务', 'edge-tunnel-agent.service'],
            ['EasyTier 服务', 'edge-tunnel-easytier.service']
          ]} />
        </Card>
      </div>
    );
  }

  const page = {
    dashboard: renderDashboard,
    nodes: renderNodes,
    networks: renderNetworkProfiles,
    entries: renderEntries,
    forwards: renderForwards,
    pbr: renderPbr,
    tasks: renderTasks,
    settings: renderSettings
  }[activeTab];

  return (
    <main>
      <header>
        <div>
          <h1>Edge Tunnel Panel</h1>
          <p>基于 EasyTier 的 TCP/UDP 隧道组网面板，用于管理主控、被控节点、公网入口、转发规则、出口策略、DDNS 与任务。</p>
        </div>
        <button onClick={() => run('刷新', refreshAll)} disabled={loading}>{loading ? '处理中...' : '刷新全部'}</button>
      </header>
      <nav>{tabs.map(([id, label]) => <button key={id} className={activeTab === id ? 'active' : ''} onClick={() => setActiveTab(id)}>{label}</button>)}</nav>
      {alert && <div className={`alert ${alert.type}`}>{alert.message}</div>}
      <section>{page?.()}</section>
    </main>
  );
}

function Card({ title, action, children }) {
  return <article className="card"><div className="card-head"><h2>{title}</h2>{action}</div>{children}</article>;
}

function Stat({ title, value, note }) {
  return <div className="stat"><span>{title}</span><strong>{value}</strong><small>{note}</small></div>;
}

function Field({ label, value, onChange, type = 'text', required = false }) {
  return <label>{label}<input type={type} value={value} required={required} onChange={(event) => onChange(event.target.value)} /></label>;
}

function Select({ label, value, options, onChange }) {
  return (
    <label>{label}<select value={value} onChange={(event) => onChange(event.target.value)}>
      {options.map((option) => Array.isArray(option) ? <option key={option[0]} value={option[0]}>{option[1]}</option> : <option key={option} value={option}>{option}</option>)}
    </select></label>
  );
}

function NodeSelect({ label, value, nodes, onChange }) {
  return <label>{label}<select value={value} onChange={(event) => onChange(event.target.value)}><option value="">选择节点</option>{nodes.map((node) => <option key={node.id} value={node.id}>{node.name || node.id}</option>)}</select></label>;
}

function KeyValues({ rows }) {
  return <dl className="kv">{rows.map(([key, value]) => <React.Fragment key={key}><dt>{key}</dt><dd>{value || '-'}</dd></React.Fragment>)}</dl>;
}

function ListCard({ title, items, fields, refresh, apply }) {
  return (
    <Card title={title} action={<button onClick={refresh}>刷新</button>}>
      <div className="table-wrap">
        <table><thead><tr>{fields.map((field) => <th key={field}>{field}</th>)}<th>操作</th></tr></thead><tbody>{items.map((item) => <tr key={item.id}>{fields.map((field) => <td key={field}>{String(item[field] ?? '-')}</td>)}<td><button onClick={() => apply(item)}>应用</button></td></tr>)}</tbody></table>
      </div>
    </Card>
  );
}

function TaskTable({ tasks, compact = false }) {
  if (!tasks.length) return <p className="muted">暂无任务。</p>;
  return (
    <div className="table-wrap">
      <table>
        <thead><tr><th>ID</th><th>节点</th><th>action</th><th>状态</th><th>创建时间</th>{!compact && <th>开始</th>}{!compact && <th>完成</th>}{!compact && <th>输出</th>}</tr></thead>
        <tbody>{tasks.map((task) => <tr key={task.id}><td><code>{task.id}</code></td><td>{task.node_id || '-'}</td><td>{actionText[task.action] || task.action}</td><td><span className={statusClass(task.status)}>{trStatus(task.status)}</span></td><td>{formatTime(task.created_at)}</td>{!compact && <td>{formatTime(task.started_at)}</td>}{!compact && <td>{formatTime(task.finished_at)}</td>}{!compact && <td><pre className="small">{summarize(task.error || task.stdout || task.stderr || task.result)}</pre></td>}</tr>)}</tbody>
      </table>
    </div>
  );
}

createRoot(document.getElementById('root')).render(<App />);
