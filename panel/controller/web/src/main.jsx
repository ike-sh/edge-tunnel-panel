import React, { useEffect, useMemo, useState } from 'react';
import { createRoot } from 'react-dom/client';
import './styles.css';

const API_BASE = import.meta.env.VITE_API_BASE || '';
const tabs = ['Dashboard', 'Bootstrap', 'Nodes', 'Network', 'Entries', 'Forwards', 'PBR', 'DDNS', 'Tasks', 'Events', 'Settings'];
const PANEL_VERSION = '3.0.0-alpha.4';
const tabLabels = {
  Login: '登录',
  Dashboard: '控制台',
  Topology: '拓扑视图',
  Nodes: '节点管理',
  'Node Detail': '节点详情',
  Network: '组网配置',
  Entries: '公网入口',
  Forwards: '转发规则',
  PBR: '出口策略',
  DDNS: '动态域名',
  Events: '日志事件',
  Plans: '配置计划',
  Tasks: '任务中心',
  'Task Detail': '任务详情',
  Capabilities: '能力状态',
  'Action Catalog': '动作目录',
  Bootstrap: '添加节点',
  Settings: '系统设置'
};
const statusLabels = {
  online: '在线',
  offline: '离线',
  degraded: '异常',
  unknown: '未知',
  queued: '排队中',
  picked: '执行中',
  succeeded: '成功',
  failed: '失败',
  expired: '已过期',
  canceled: '已取消',
  pending: '待处理',
  enabled: '已启用',
  disabled: '已禁用',
  not_run: '未运行',
  missing: '缺失',
  recorded: '已记录',
  verified: '已验证',
  blocked: '已阻止',
  warning: '警告',
  ready: '就绪',
  draft: '草稿',
  generated: '已生成',
  archived: '已归档',
  running_manually: '人工执行中',
  rolled_back: '已回滚',
  safe: '安全',
  caution: '谨慎',
  dangerous: '危险',
  passed: '通过',
  ok: '正常',
  warn: '警告',
  manual: '人工',
  readonly: '只读',
  approved: '已批准',
  rejected: '已拒绝',
  not_required: '不需要'
};
const roleLabels = { entry: '公网入口', relay: '中转节点', mixed: '混合节点', unknown: '未知角色' };

function labelTab(tab) {
  return tabLabels[tab] || tab;
}

function labelStatus(status) {
  return statusLabels[status] || status || '未知';
}

function labelRole(role) {
  return roleLabels[role] || role || '未知角色';
}

function getOperatorToken() {
  try {
    return sessionStorage.getItem('leikwan_operator_token') || '';
  } catch {
    return '';
  }
}

function setStoredOperatorToken(token) {
  try {
    if (token) sessionStorage.setItem('leikwan_operator_token', token);
    else sessionStorage.removeItem('leikwan_operator_token');
  } catch {
    // sessionStorage may be unavailable in hardened browsers.
  }
}

function authHeaders(extra = {}) {
  const token = getOperatorToken();
  return token ? { ...extra, Authorization: `Bearer ${token}` } : extra;
}

async function apiFetch(path, options = {}) {
  const headers = authHeaders(options.headers || {});
  return fetch(`${API_BASE}${path}`, { ...options, headers });
}

async function getJSON(path) {
  const res = await apiFetch(path);
  if (!res.ok) throw new Error(errorMessage(res));
  return res.json();
}

function errorMessage(res) {
  if (res.status === 403) return '403 需要 Operator Token 或权限不足';
  if (res.status === 401) return '401 未登录或 Token 无效';
  return `${res.status} ${res.statusText}`;
}

function usePanelData() {
  const [data, setData] = useState({ nodes: [], networkProfiles: [], entries: [], forwards: [], pbrPolicies: [], ddnsProfiles: [], events: [], loading: true, error: '' });
  useEffect(() => {
    let alive = true;
    async function load() {
      try {
        const [nodes, networkProfiles, entries, forwards, pbrPolicies, ddnsProfiles, events] = await Promise.all([
          getJSON('/api/v1/nodes'),
          getJSON('/api/v1/network-profiles'),
          getJSON('/api/v1/entries'),
          getJSON('/api/v1/forwards'),
          getJSON('/api/v1/pbr-policies'),
          getJSON('/api/v1/ddns-profiles'),
          getJSON('/api/v1/events')
        ]);
        if (alive) setData({ nodes, networkProfiles, entries, forwards, pbrPolicies, ddnsProfiles, events, loading: false, error: '' });
      } catch (err) {
        if (alive) setData((prev) => ({ ...prev, loading: false, error: err.message }));
      }
    }
    load();
    const timer = setInterval(load, 15000);
    return () => {
      alive = false;
      clearInterval(timer);
    };
  }, []);
  return data;
}

function statusCounts(nodes) {
  return nodes.reduce((acc, node) => {
    const key = node.status || 'unknown';
    acc[key] = (acc[key] || 0) + 1;
    return acc;
  }, {});
}

function App() {
  const [path, setPath] = useState(window.location.pathname);
  const [operatorToken, setOperatorToken] = useState(getOperatorToken());
  const [authStatus, setAuthStatus] = useState({ operator_auth_configured: false, strict_auth: false, agent_auth_configured: false, version: PANEL_VERSION });
  const data = usePanelData();
  const counts = useMemo(() => statusCounts(data.nodes), [data.nodes]);
  const active = path.startsWith('/nodes/') ? 'Node Detail' : path.startsWith('/tasks/') ? 'Task Detail' : pathToTab(path);
  function navigate(nextPath) {
    window.history.pushState({}, '', nextPath);
    setPath(nextPath);
  }
  useEffect(() => {
    const onPop = () => setPath(window.location.pathname);
    window.addEventListener('popstate', onPop);
    return () => window.removeEventListener('popstate', onPop);
  }, []);
  useEffect(() => {
    getJSON('/api/v1/auth/status')
      .then(setAuthStatus)
      .catch(() => setAuthStatus((prev) => ({ ...prev, error: 'auth status unavailable' })));
  }, [operatorToken]);
  function updateOperatorToken(token) {
    setStoredOperatorToken(token);
    setOperatorToken(token);
  }
  return (
    <div className="app">
      <aside className="sidebar">
        <div className="brand">
          <div className="brand-mark">LQ</div>
          <div>
            <h1>Leikwan Panel</h1>
            <p>{PANEL_VERSION} 测试版</p>
          </div>
        </div>
        <nav>
          {tabs.map((tab) => (
            <button key={tab} className={active === tab ? 'active' : ''} onClick={() => navigate(tabToPath(tab))}>
              {labelTab(tab)}
            </button>
          ))}
        </nav>
        <button className="disabled" disabled>任意命令已禁用</button>
      </aside>
      <main>
        <header>
          <div>
            <p className="eyebrow">Leikwan Panel {PANEL_VERSION}</p>
            <h2>{labelTab(active)}</h2>
          </div>
          <div className="top-status">
            <span className="status-pill">{data.error ? '接口异常' : data.loading ? '加载中' : 'Controller 正常'}</span>
            <span>在线节点：{counts.online || 0}</span>
            <span>{operatorToken ? '已登录' : '未登录'}</span>
            {operatorToken && <button onClick={() => updateOperatorToken('')}>退出登录</button>}
          </div>
        </header>
        <AuthBar authStatus={authStatus} token={operatorToken} onToken={updateOperatorToken} />
        {data.error && <div className="banner">接口请求失败：{data.error}</div>}
        <div className="notice">当前为 3.0.0-alpha.4 测试版。启用写操作的 Agent 只能执行固定白名单动作；面板不接受任意命令、不执行 shell 字符串。</div>
        {active === 'Login' && <LoginPanel token={operatorToken} onToken={updateOperatorToken} />}
        {active === 'Dashboard' && <Dashboard data={data} counts={counts} onNavigate={navigate} />}
        {active === 'Topology' && <Topology />}
        {active === 'Nodes' && <Nodes nodes={data.nodes} onOpen={(id) => navigate(`/nodes/${encodeURIComponent(id)}`)} />}
        {active === 'Node Detail' && <NodeDetail nodeId={decodeURIComponent(path.split('/').pop() || '')} entries={data.entries} forwards={data.forwards} />}
        {active === 'Network' && <Network nodes={data.nodes} profiles={data.networkProfiles} />}
        {active === 'Entries' && <Entries entries={data.entries} nodes={data.nodes} profiles={data.networkProfiles} />}
        {active === 'Forwards' && <Forwards forwards={data.forwards} nodes={data.nodes} profiles={data.networkProfiles} entries={data.entries} pbrPolicies={data.pbrPolicies} />}
        {active === 'PBR' && <PBR policies={data.pbrPolicies} nodes={data.nodes} />}
        {active === 'DDNS' && <DDNS profiles={data.ddnsProfiles} nodes={data.nodes} />}
        {active === 'Events' && <Events events={data.events} />}
        {active === 'Plans' && <Plans nodes={data.nodes} />}
        {active === 'Tasks' && <Tasks nodes={data.nodes} onNavigate={navigate} />}
        {active === 'Task Detail' && <TaskDetail taskId={decodeURIComponent(path.split('/').pop() || '')} nodes={data.nodes} onNavigate={navigate} />}
        {active === 'Capabilities' && <Capabilities nodes={data.nodes} />}
        {active === 'Action Catalog' && <ActionCatalog />}
        {active === 'Bootstrap' && <Bootstrap operatorToken={operatorToken} />}
        {active === 'Settings' && <Settings authStatus={authStatus} />}
      </main>
    </div>
  );
}

function pathToTab(path) {
  if (path === '/login') return 'Login';
  if (path === '/nodes') return 'Nodes';
  if (path === '/topology') return 'Topology';
  if (path === '/network') return 'Network';
  if (path === '/entries') return 'Entries';
  if (path === '/forwards') return 'Forwards';
  if (path === '/pbr') return 'PBR';
  if (path === '/ddns') return 'DDNS';
  if (path === '/events') return 'Events';
  if (path === '/plans') return 'Plans';
  if (path === '/tasks') return 'Tasks';
  if (path === '/capabilities') return 'Capabilities';
  if (path === '/action-catalog') return 'Action Catalog';
  if (path === '/bootstrap') return 'Bootstrap';
  if (path === '/settings') return 'Settings';
  return 'Dashboard';
}

function tabToPath(tab) {
  if (tab === 'Dashboard') return '/';
  if (tab === 'Action Catalog') return '/action-catalog';
  return `/${tab.toLowerCase()}`;
}

function AuthBar({ authStatus, token, onToken }) {
  const [draft, setDraft] = useState(token || '');
  useEffect(() => setDraft(token || ''), [token]);
  function save(e) {
    e.preventDefault();
    onToken(draft.trim());
  }
  return (
    <section className="auth-bar">
      <div>
        <strong>登录状态</strong>
        <span>Operator：{authStatus.operator_auth_configured ? '已配置' : '未配置'}</span>
        <span>严格认证：{authStatus.strict_auth ? '开启' : '关闭'}</span>
        <span>Agent Token：{authStatus.agent_auth_configured ? '已配置' : '未配置'}</span>
      </div>
      <form onSubmit={save}>
        <input type="password" value={draft} onChange={(e) => setDraft(e.target.value)} placeholder="Operator token" />
        <button className="primary-action" type="submit">{token ? '更新 Token' : '解锁面板'}</button>
        <button type="button" onClick={() => { setDraft(''); onToken(''); }}>清除</button>
      </form>
      <p className="muted">创建、应用、重启等操作需要 Operator Token。Agent Token 不能登录面板。</p>
    </section>
  );
}

function LoginPanel({ token, onToken }) {
  const [draft, setDraft] = useState(token || '');
  const [message, setMessage] = useState('');
  async function login(e) {
    e.preventDefault();
    try {
      const res = await fetch(`${API_BASE}/api/v1/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ token: draft.trim() })
      });
      if (!res.ok) throw new Error(errorMessage(res));
      onToken(draft.trim());
      const data = await res.json();
      setMessage(`已解锁：${data.identity || 'operator'}`);
    } catch (err) {
      setMessage(err.message);
    }
  }
  return (
    <section className="panel">
      <h3>登录</h3>
      <p className="muted">请输入 Controller 安装时输出的 Operator Token。Agent Token 不能用于登录。</p>
      <form className="form-grid" onSubmit={login}>
        <label>Operator Token<input type="password" value={draft} onChange={(e) => setDraft(e.target.value)} /></label>
        <button className="primary-action" type="submit">登录</button>
      </form>
      {message && <div className="banner">{message}</div>}
    </section>
  );
}

function Settings({ authStatus }) {
  return (
    <section className="panel">
      <h3>系统设置</h3>
      <KeyValue data={{
        version: PANEL_VERSION,
        operator_auth_configured: String(Boolean(authStatus.operator_auth_configured)),
        strict_auth: String(Boolean(authStatus.strict_auth)),
        agent_auth_configured: String(Boolean(authStatus.agent_auth_configured))
      }} />
      <p className="muted">Shell Core 仍独立冻结。面板只创建固定 Agent 任务，不接受任意命令字符串。</p>
    </section>
  );
}

function Dashboard({ data, counts, onNavigate }) {
  const writeEnabled = data.nodes.filter((node) => Boolean(node.capabilities?.write_actions_supported)).length;
  return (
    <>
      <section className="metrics">
        <Metric label="在线节点" value={counts.online || 0} />
        <Metric label="离线节点" value={counts.offline || 0} />
        <Metric label="异常节点" value={counts.degraded || 0} />
        <Metric label="公网入口" value={data.entries.length} />
        <Metric label="转发规则" value={data.forwards.length} />
        <Metric label="DDNS 配置" value={data.ddnsProfiles.length} />
        <Metric label="写操作节点" value={writeEnabled} />
      </section>
      <section className="action-row">
        <button className="primary-action" onClick={() => onNavigate('/topology')}>查看拓扑</button>
        <button className="primary-action" onClick={() => onNavigate('/bootstrap')}>添加节点</button>
        <button className="primary-action" onClick={() => onNavigate('/network')}>创建组网</button>
      </section>
      <RecentApplyTasks />
      <section>
        <h3>最近状态变化</h3>
        <Events events={data.events.filter((e) => (e.message || '').includes('status changed')).slice(0, 10)} compact />
      </section>
      <section className="section-gap">
        <h3>最近事件</h3>
        <Events events={data.events.slice(0, 10)} compact />
      </section>
    </>
  );
}

function RecentApplyTasks() {
  const [tasks, setTasks] = useState([]);
  useEffect(() => {
    let alive = true;
    getJSON('/api/v1/tasks')
      .then((items) => alive && setTasks(items.filter((task) => (task.task_group_id || '').startsWith('apply-')).slice(0, 8)))
      .catch(() => alive && setTasks([]));
    return () => { alive = false; };
  }, []);
  return (
    <section className="section-gap">
      <h3>最近应用任务组</h3>
      {tasks.length ? <TasksList tasks={tasks} nodes={[]} onOpen={() => {}} onReload={async () => {}} compact /> : <Empty text="暂无应用任务" />}
    </section>
  );
}

function Topology() {
  const [topology, setTopology] = useState({ nodes: [], entries: [], forwards: [], links: [], loading: true, error: '' });
  useEffect(() => {
    let alive = true;
    getJSON('/api/v1/topology')
      .then((data) => alive && setTopology({ ...data, loading: false, error: '' }))
      .catch((err) => alive && setTopology((prev) => ({ ...prev, loading: false, error: err.message })));
    return () => { alive = false; };
  }, []);
  if (topology.loading) return <Empty text="正在加载拓扑" />;
  if (topology.error) return <div className="banner">拓扑加载失败：{topology.error}</div>;
  const groups = {
    entry: topology.nodes.filter((n) => n.role === 'entry'),
    relay: topology.nodes.filter((n) => n.role === 'relay' || n.role === 'mixed'),
    other: topology.nodes.filter((n) => n.role === 'unknown' || !['entry', 'relay', 'mixed'].includes(n.role))
  };
  return (
    <div className="topology-page">
      <section className="metrics">
        <Metric label="节点" value={topology.nodes.length} />
        <Metric label="入口" value={topology.entries.length} />
        <Metric label="转发" value={topology.forwards.length} />
        <Metric label="连接" value={topology.links.length} />
      </section>
      <div className="topology-grid">
        <TopologyColumn title="公网入口" nodes={groups.entry} />
        <TopologyColumn title="中转节点" nodes={groups.relay} />
        <TopologyColumn title="其他 / 未知" nodes={groups.other} />
      </div>
      <section>
        <h3>拓扑连接</h3>
        {topology.links.length ? (
          <div className="link-list">
            {topology.links.map((link, idx) => (
              <div className="link-card" key={`${link.source}-${link.target}-${idx}`}>
                <span>{link.source}</span>
                <strong>{link.type}</strong>
                <span>{link.target}</span>
                <em className={`tag ${link.status}`}>{link.status || 'unknown'}</em>
              </div>
            ))}
          </div>
        ) : <Empty text="暂无可推断的连接" />}
      </section>
    </div>
  );
}

function TopologyColumn({ title, nodes }) {
  return (
    <section className="topology-column">
      <h3>{title}</h3>
      {nodes.length ? nodes.map((node) => (
        <div className={`node-card ${node.status}`} key={node.node_id}>
          <strong>{node.node_name || node.node_id}</strong>
          <span>{labelRole(node.role)}</span>
          <span>{node.public_ip || node.lan_ip || '-'}</span>
          <span className={`tag ${node.status}`}>{labelStatus(node.status)}</span>
        </div>
      )) : <Empty text={`暂无${title}节点`} />}
    </section>
  );
}

function Bootstrap({ operatorToken }) {
  const [form, setForm] = useState({ controller_url: window.location.origin, node_name: 'leikwan-node', role: 'relay', enable_tasks: true, enable_write_actions: false, method: 'curl' });
  const [info, setInfo] = useState(null);
  const [command, setCommand] = useState({ command: '', note: '', loading: true, error: '' });
  useEffect(() => {
    let alive = true;
    getJSON('/api/v1/bootstrap/controller-info')
      .then((data) => alive && setInfo(data))
      .catch(() => alive && setInfo(null));
    return () => { alive = false; };
  }, []);
  useEffect(() => {
    let alive = true;
    const q = new URLSearchParams({
      controller_url: form.controller_url,
      node_name: form.node_name,
      role: form.role,
      enable_tasks: String(Boolean(form.enable_tasks)),
      enable_write_actions: String(Boolean(form.enable_write_actions)),
      method: form.method,
      token_mode: operatorToken ? 'full' : 'masked'
    }).toString();
    getJSON(`/api/v1/bootstrap/agent-install-command?${q}`)
      .then((data) => alive && setCommand({ ...data, loading: false, error: '' }))
      .catch((err) => alive && setCommand((prev) => ({ ...prev, loading: false, error: err.message })));
    return () => { alive = false; };
  }, [form, operatorToken]);
  function update(key, value) {
    setForm((prev) => ({ ...prev, [key]: value }));
  }
  return (
    <div className="bootstrap-page">
      <section className="panel form-card">
        <h3>添加节点</h3>
        <p className="muted">在被控服务器上复制并执行以下命令，Agent 会自动连接主控面板。主控不需要 SSH 到被控机，主控离线也不影响已有转发。</p>
        {info && <p className="muted">Controller {info.version}：{info.controller_url_guess || info.controller_url}；安装脚本：{info.install_script_url}</p>}
        <div className="form-grid">
          <label>Controller 地址<input value={form.controller_url} onChange={(e) => update('controller_url', e.target.value)} /></label>
          <label>节点名称<input value={form.node_name} onChange={(e) => update('node_name', e.target.value)} /></label>
          <label>节点角色<select value={form.role} onChange={(e) => update('role', e.target.value)}>
            {['entry', 'relay', 'mixed', 'unknown'].map((role) => <option key={role} value={role}>{labelRole(role)}</option>)}
          </select></label>
          <label>安装方式<select value={form.method} onChange={(e) => update('method', e.target.value)}>
            <option value="curl">curl</option>
            <option value="wget">wget</option>
          </select></label>
          <label className="check-label"><input type="checkbox" checked={form.enable_tasks} onChange={(e) => update('enable_tasks', e.target.checked)} /> 启用只读任务</label>
          <label className="check-label"><input type="checkbox" checked={form.enable_write_actions} onChange={(e) => update('enable_write_actions', e.target.checked)} /> 启用 alpha 写操作</label>
        </div>
        <p className="muted">启用写操作后，Agent 可以执行固定白名单写操作，不支持任意命令。未登录时 Token 显示为 REDACTED，登录后命令框内展示完整命令。</p>
      </section>
      <section className="panel command-card">
        <h3>一键安装命令</h3>
        {command.error && <div className="banner">命令生成失败：{command.error}</div>}
        <pre className="command-box">{command.loading ? '正在生成...' : command.command}</pre>
        {command.warnings?.length ? <ul className="muted">{command.warnings.map((w) => <li key={w}>{w}</li>)}</ul> : null}
        <p className="muted">{command.note}</p>
        <div className="button-row">
          <button className="primary-action copy-button" onClick={() => navigator.clipboard.writeText(command.command || '')}>复制命令</button>
        </div>
        <p className="muted">请在目标 VPS 上以 root 或 sudo 执行。Agent 会主动注册并开始心跳上报。</p>
      </section>
    </div>
  );
}
function Network({ nodes, profiles }) {
  const relayNodes = nodes.filter((node) => node.status === 'online' && ['relay', 'mixed', 'unknown'].includes(node.role));
  const [items, setItems] = useState(profiles || []);
  const [form, setForm] = useState({ name: 'demo-network', network_name: '', relay_node_id: relayNodes[0]?.node_id || '' });
  const [error, setError] = useState('');
  useEffect(() => setItems(profiles || []), [profiles]);
  useEffect(() => {
    if (!form.relay_node_id && relayNodes[0]?.node_id) setForm((prev) => ({ ...prev, relay_node_id: relayNodes[0].node_id }));
  }, [nodes]);
  async function refresh() {
    setItems(await getJSON('/api/v1/network-profiles'));
  }
  async function create(e) {
    e.preventDefault();
    try {
      const res = await apiFetch('/api/v1/network-profiles', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(form)
      });
      if (!res.ok) throw new Error(errorMessage(res));
      await refresh();
      setError('');
    } catch (err) {
      setError(err.message);
    }
  }
  async function apply(id) {
    try {
      const res = await apiFetch(`/api/v1/network-profiles/${id}/apply`, { method: 'POST' });
      if (!res.ok) throw new Error(errorMessage(res));
      setError('组网应用任务已创建');
    } catch (err) {
      setError(err.message);
    }
  }
  return (
    <div className="network-page">
      {error && <div className="banner">组网请求结果：{error}</div>}
      <section className="panel">
        <h3>创建组网配置</h3>
        <p className="muted">Network 记录由主控保存，network_secret 自动生成并默认隐藏。</p>
        <form className="form-grid" onSubmit={create}>
          <label>名称 *<input value={form.name} onChange={(e) => setForm((prev) => ({ ...prev, name: e.target.value }))} /></label>
          <label>网络名<input value={form.network_name} placeholder="留空自动生成" onChange={(e) => setForm((prev) => ({ ...prev, network_name: e.target.value }))} /></label>
          <label>Relay 节点 *<select value={form.relay_node_id} onChange={(e) => setForm((prev) => ({ ...prev, relay_node_id: e.target.value }))}>
            <option value="">选择在线 relay/mixed 节点</option>
            {relayNodes.map((node) => <option key={node.node_id} value={node.node_id}>{node.node_name || node.node_id}</option>)}
          </select></label>
          <button className="primary-action" disabled={!form.relay_node_id} type="submit">创建组网</button>
        </form>
      </section>
      <section>
        <h3>组网配置列表</h3>
        <NetworkTable profiles={items} onApply={apply} />
      </section>
    </div>
  );
}

function NetworkTable({ profiles, onApply }) {
  if (!profiles.length) return <Empty text="暂无组网配置，请先创建 Network" />;
  return (
    <Table headers={['ID', '名称', '网络名', 'Relay 节点', 'Secret', '创建时间', '操作']}>
      {profiles.map((profile) => (
        <tr key={profile.id}>
          <td>{profile.id}</td>
          <td>{profile.name}</td>
          <td>{profile.network_name}</td>
          <td>{profile.relay_node_id}</td>
          <td>{profile.network_secret || 'REDACTED'}</td>
          <td>{profile.created_at}</td>
          <td>{onApply ? <button onClick={() => onApply(profile.id)}>应用组网</button> : '-'}</td>
        </tr>
      ))}
    </Table>
  );
}

function Plans({ nodes }) {
  const [plans, setPlans] = useState([]);
  const [selected, setSelected] = useState(null);
  const [form, setForm] = useState({
    type: 'create_forward',
    title: '创建转发计划',
    target_node_id: nodes[0]?.node_id || '',
    entry: '',
    relay: '',
    target_host: '',
    target_port: '',
    protocol: 'tcp,udp'
  });
  const [error, setError] = useState('');
  useEffect(() => {
    loadPlans();
  }, []);
  useEffect(() => {
    if (!form.target_node_id && nodes[0]?.node_id) {
      setForm((prev) => ({ ...prev, target_node_id: nodes[0].node_id }));
    }
  }, [nodes]);
  async function loadPlans() {
    try {
      const data = await getJSON('/api/v1/plans');
      setPlans(data);
      setError('');
    } catch (err) {
      setError(err.message);
    }
  }
  function update(key, value) {
    setForm((prev) => ({ ...prev, [key]: value }));
  }
  async function createPlan(e) {
    e.preventDefault();
    const payload = {
      entry: form.entry,
      relay: form.relay,
      target_host: form.target_host,
      target_port: form.target_port,
      protocol: form.protocol
    };
    try {
      const res = await apiFetch('/api/v1/plans', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          type: form.type,
          title: form.title,
          target_node_id: form.target_node_id,
          payload_json: payload
        })
      });
      if (!res.ok) throw new Error(errorMessage(res));
      const plan = await res.json();
      setSelected(plan);
      await loadPlans();
    } catch (err) {
      setError(err.message);
    }
  }
  return (
    <div className="plans-page">
      {error && <div className="banner">配置计划请求失败：{error}</div>}
      <section className="panel">
        <h3>创建配置计划</h3>
        <p className="muted">配置计划仍以人工执行为主。3.0.0-alpha.4 的 demo apply 只使用固定 alpha task action，不接受用户输入的命令字符串。</p>
        <form className="form-grid plan-form" onSubmit={createPlan}>
          <label>类型<select value={form.type} onChange={(e) => update('type', e.target.value)}>
            {['create_entry', 'create_forward', 'switch_entry', 'ddns_check'].map((type) => <option key={type} value={type}>{type}</option>)}
          </select></label>
          <label>标题<input value={form.title} onChange={(e) => update('title', e.target.value)} /></label>
          <label>目标节点<select value={form.target_node_id} onChange={(e) => update('target_node_id', e.target.value)}>
            <option value="">选择节点</option>
            {nodes.map((node) => <option key={node.node_id} value={node.node_id}>{node.node_name || node.node_id}</option>)}
          </select></label>
          <label>入口<input value={form.entry} onChange={(e) => update('entry', e.target.value)} /></label>
          <label>中转<input value={form.relay} onChange={(e) => update('relay', e.target.value)} /></label>
          <label>目标地址<input value={form.target_host} onChange={(e) => update('target_host', e.target.value)} /></label>
          <label>目标端口<input value={form.target_port} onChange={(e) => update('target_port', e.target.value)} /></label>
          <label>协议<input value={form.protocol} onChange={(e) => update('protocol', e.target.value)} /></label>
          <button className="primary-action" type="submit">创建草稿</button>
        </form>
      </section>
      <section>
        <h3>配置计划</h3>
        <PlansList plans={plans} onSelect={setSelected} />
      </section>
      {selected && <PlanDetail plan={selected} onUpdate={(plan) => { setSelected(plan); loadPlans(); }} />}
    </div>
  );
}

function PlansList({ plans, onSelect }) {
  if (!plans.length) return <Empty text="暂无配置计划" />;
  return (
    <Table headers={['标题', '计划状态', '预检', '快照', '安全门', '执行状态', '安全等级', '分类', '类型', '目标节点', '更新时间']}>
      {plans.map((plan) => (
        <tr key={plan.id}>
          <td><button className="link-button" onClick={() => onSelect(plan)}>{plan.title}</button></td>
          <td><span className={`tag ${plan.status}`}>{labelStatus(plan.status)}</span></td>
          <td><span className={`tag ${plan.dry_run_status}`}>{labelStatus(plan.dry_run_status || 'not_run')}</span></td>
          <td><span className={`tag ${plan.snapshot_status}`}>{labelStatus(plan.snapshot_status || 'missing')}</span></td>
          <td><span className={`tag ${planGateLabel(plan)}`}>{labelStatus(planGateLabel(plan))}</span></td>
          <td><span className={`tag ${plan.execution_status}`}>{labelStatus(plan.execution_status || 'not_run')}</span></td>
          <td><span className={`tag ${plan.safety_level}`}>{plan.safety_level || 'safe'}</span></td>
          <td><span className={`tag ${plan.command_classification}`}>{plan.command_classification || 'manual'}</span></td>
          <td>{plan.type}</td>
          <td>{plan.target_node_id || '-'}</td>
          <td>{plan.updated_at || plan.created_at}</td>
        </tr>
      ))}
    </Table>
  );
}

function planGateLabel(plan) {
  if ((plan.dry_run_status || 'not_run') !== 'passed') return 'blocked';
  if ((plan.snapshot_policy || 'recommended') === 'required' && !['recorded', 'verified'].includes(plan.snapshot_status || 'missing')) return 'blocked';
  if ((plan.snapshot_policy || 'recommended') === 'required' && !plan.rollback_available) return 'blocked';
  if ((plan.snapshot_policy || 'recommended') === 'recommended' && !['recorded', 'verified'].includes(plan.snapshot_status || 'missing')) return 'warning';
  return 'ready';
}

function PlanDetail({ plan, onUpdate }) {
  const [copyText, setCopyText] = useState('');
  const [manualNote, setManualNote] = useState(plan.execution_note || '');
  const [snapshot, setSnapshot] = useState({ snapshot_ref: plan.snapshot_ref || '', snapshot_note: plan.snapshot_note || '' });
  const [rollback, setRollback] = useState({ rollback_ref: plan.rollback_ref || '', rollback_note: plan.rollback_note || '' });
  const [metadata, setMetadata] = useState({
    note: '',
    snapshot_ref: plan.snapshot_ref || '',
    snapshot_note: plan.snapshot_note || '',
    rollback_ref: plan.rollback_ref || '',
    rollback_note: plan.rollback_note || '',
    execution_status: 'succeeded',
    verification_status: 'passed',
    evidence_type: 'manual',
    title: '',
    content: ''
  });
  const [evidence, setEvidence] = useState([]);
  const [safetyGate, setSafetyGate] = useState(null);
  const [actionReview, setActionReview] = useState(null);
  const [checked, setChecked] = useState({});
  const markdownText = plan.markdown || '请先生成计划，以创建人工执行手册。';
  useEffect(() => {
    setManualNote(plan.execution_note || '');
    setSnapshot({ snapshot_ref: plan.snapshot_ref || '', snapshot_note: plan.snapshot_note || '' });
    setRollback({ rollback_ref: plan.rollback_ref || '', rollback_note: plan.rollback_note || '' });
    setMetadata({
      note: '',
      snapshot_ref: plan.snapshot_ref || '',
      snapshot_note: plan.snapshot_note || '',
      rollback_ref: plan.rollback_ref || '',
      rollback_note: plan.rollback_note || '',
      execution_status: 'succeeded',
      verification_status: 'passed',
      evidence_type: 'manual',
      title: '',
      content: ''
    });
    setEvidence([]);
    setChecked({});
    setCopyText('');
    setSafetyGate(null);
    setActionReview(null);
  }, [plan.id]);
  useEffect(() => {
    loadEvidence();
  }, [plan.id]);
  async function loadEvidence() {
    try {
      setEvidence(await getJSON(`/api/v1/plans/${plan.id}/evidence`));
    } catch {
      setEvidence([]);
    }
  }
  async function generate() {
    const res = await apiFetch(`/api/v1/plans/${plan.id}/generate`, { method: 'POST' });
    if (!res.ok) throw new Error(errorMessage(res));
    onUpdate(await res.json());
  }
  async function regenerate() {
    const res = await apiFetch(`/api/v1/plans/${plan.id}/regenerate`, { method: 'POST' });
    if (!res.ok) throw new Error(errorMessage(res));
    onUpdate(await res.json());
  }
  async function preflight() {
    const res = await apiFetch(`/api/v1/plans/${plan.id}/preflight`, { method: 'POST' });
    if (!res.ok) throw new Error(errorMessage(res));
    onUpdate(await res.json());
  }
  async function startDryRun() {
    if (!window.confirm('这只会创建只读预检任务，不会应用配置。确认开始预检？')) {
      return;
    }
    const res = await apiFetch(`/api/v1/plans/${plan.id}/dry-run`, { method: 'POST' });
    if (!res.ok) throw new Error(errorMessage(res));
    onUpdate(await res.json());
  }
  async function refreshDryRun() {
    const res = await apiFetch(`/api/v1/plans/${plan.id}/dry-run`);
    if (!res.ok) throw new Error(errorMessage(res));
    onUpdate(await res.json());
  }
  async function recordSnapshot(e) {
    e.preventDefault();
    const res = await apiFetch(`/api/v1/plans/${plan.id}/snapshot`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(snapshot)
    });
    if (!res.ok) throw new Error(errorMessage(res));
    onUpdate(await res.json());
  }
  async function recordRollback(e) {
    e.preventDefault();
    const res = await apiFetch(`/api/v1/plans/${plan.id}/rollback-info`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ...rollback, rollback_available: Boolean(rollback.rollback_ref || rollback.rollback_note) })
    });
    if (!res.ok) throw new Error(errorMessage(res));
    onUpdate(await res.json());
  }
  async function refreshSafetyGate() {
    const gate = await getJSON(`/api/v1/plans/${plan.id}/safety-gate`);
    setSafetyGate(gate);
  }
  async function verifyPlan() {
    const res = await apiFetch(`/api/v1/plans/${plan.id}/verify`, { method: 'POST' });
    if (!res.ok) throw new Error(errorMessage(res));
    onUpdate(await res.json());
    await refreshSafetyGate();
  }
  async function refreshActionReview() {
    const review = await getJSON(`/api/v1/plans/${plan.id}/action-review`);
    setActionReview(review);
  }
  async function metadataAction(action, extra = {}) {
    const res = await apiFetch(`/api/v1/plans/${plan.id}/metadata-action`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action, note: metadata.note, ...extra })
    });
    if (!res.ok) throw new Error(errorMessage(res));
    const updated = await res.json();
    onUpdate(updated);
    await loadEvidence();
    await refreshSafetyGate();
  }
  async function attachEvidence(e) {
    e.preventDefault();
    await metadataAction('attach_manual_evidence', {
      evidence_type: metadata.evidence_type,
      title: metadata.title,
      content: metadata.content
    });
    setMetadata((prev) => ({ ...prev, title: '', content: '', note: '' }));
  }
  async function archive() {
    const res = await apiFetch(`/api/v1/plans/${plan.id}/archive`, { method: 'POST' });
    if (!res.ok) throw new Error(errorMessage(res));
    onUpdate(await res.json());
  }
  async function mark(status) {
    const res = await apiFetch(`/api/v1/plans/${plan.id}/mark`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        execution_status: status,
        execution_note: manualNote,
        manual_result: JSON.stringify({ checked })
      })
    });
    if (!res.ok) throw new Error(errorMessage(res));
    onUpdate(await res.json());
  }
  async function copyCommands() {
    if (plan.safety_level === 'dangerous' && !window.confirm('该计划被标记为危险。仍要复制命令吗？')) {
      return;
    }
    const text = commandsFromGroups(plan).join('\n');
    try {
      await navigator.clipboard.writeText(text);
      setCopyText('已复制');
    } catch {
      setCopyText('复制失败');
    }
  }
  async function copyMarkdown() {
    try {
      await navigator.clipboard.writeText(markdownText);
      setCopyText('Markdown 已复制');
    } catch {
      setCopyText('复制失败');
    }
  }
  function toggleCheck(idx) {
    setChecked((prev) => ({ ...prev, [idx]: !prev[idx] }));
  }
  return (
    <section className="panel">
      <h3>计划详情</h3>
      <dl className="kv">
        <dt>标题</dt><dd>{plan.title}</dd>
        <dt>类型</dt><dd>{plan.type}</dd>
        <dt>状态</dt><dd>{labelStatus(plan.status)}</dd>
        <dt>预检</dt><dd><span className={`tag ${plan.dry_run_status}`}>{labelStatus(plan.dry_run_status || 'not_run')}</span></dd>
        <dt>快照</dt><dd><span className={`tag ${plan.snapshot_status}`}>{plan.snapshot_policy || 'recommended'} / {labelStatus(plan.snapshot_status || 'missing')}</span></dd>
        <dt>验证</dt><dd><span className={`tag ${plan.verification_status}`}>{labelStatus(plan.verification_status || 'not_run')}</span></dd>
        <dt>执行</dt><dd><span className={`tag ${plan.execution_status}`}>{labelStatus(plan.execution_status || 'not_run')}</span></dd>
        <dt>安全等级</dt><dd><span className={`tag ${plan.safety_level}`}>{labelStatus(plan.safety_level || 'safe')}</span></dd>
        <dt>命令分类</dt><dd><span className={`tag ${plan.command_classification}`}>{labelStatus(plan.command_classification || 'manual')}</span></dd>
        <dt>目标节点</dt><dd>{plan.target_node_id || '-'}</dd>
      </dl>
      {plan.safety_level === 'dangerous' && <div className="danger-banner">危险计划：已移除被阻止的命令文本。复制前请先查看预检结果。</div>}
      <h4>Payload</h4>
      <pre className="command-box">{JSON.stringify(plan.payload_json || {}, null, 2)}</pre>
      <h4>警告</h4>
      <List items={plan.warnings || []} empty="暂无警告" />
      <h4>预检</h4>
      <Preflight data={plan.preflight} />
      <h4>只读预检</h4>
      <DryRun plan={plan} onStart={startDryRun} onRefresh={refreshDryRun} />
      <h4>快照 / 回滚信息</h4>
      <SnapshotRollback plan={plan} snapshot={snapshot} rollback={rollback} setSnapshot={setSnapshot} setRollback={setRollback} onSnapshot={recordSnapshot} onRollback={recordRollback} />
      <h4>安全门</h4>
      <SafetyGate gate={safetyGate} plan={plan} onRefresh={refreshSafetyGate} onVerify={verifyPlan} />
      <h4>动作评审</h4>
      <ActionReview review={actionReview} plan={plan} onRefresh={refreshActionReview} />
      <h4>元数据操作 / 人工证据</h4>
      <MetadataActions
        plan={plan}
        metadata={metadata}
        setMetadata={setMetadata}
        evidence={evidence}
        onSnapshot={() => metadataAction('record_snapshot_ref', { snapshot_ref: metadata.snapshot_ref, snapshot_note: metadata.snapshot_note })}
        onRollback={() => metadataAction('record_rollback_ref', { rollback_ref: metadata.rollback_ref, rollback_note: metadata.rollback_note })}
        onExecuted={() => metadataAction('mark_plan_executed', { execution_status: metadata.execution_status })}
        onVerified={() => metadataAction('mark_plan_verified', { verification_status: metadata.verification_status })}
        onEvidence={attachEvidence}
      />
      <h4>能力要求</h4>
      <List items={plan.capability_requirements || []} empty="暂无能力要求" />
      <h4>检查清单</h4>
      <Checklist items={plan.checklist || []} checked={checked} onToggle={toggleCheck} />
      <h4>命令分组</h4>
      <CommandGroups groups={plan.command_groups || []} fallback={plan.generated_commands || []} />
      <h4>Markdown 预览</h4>
      <pre className="command-box markdown-preview">{markdownText}</pre>
      <h4>人工结果</h4>
      <textarea className="note-box" value={manualNote} onChange={(e) => setManualNote(e.target.value)} placeholder="人工执行后的可选备注" />
      <div className="action-row">
        <button className="primary-action" onClick={generate}>生成手册</button>
        <button className="primary-action" onClick={regenerate}>重新生成</button>
        <button className="primary-action" onClick={preflight}>运行预检</button>
        <button className="primary-action" onClick={startDryRun}>开始预检</button>
        <button className="link-button" onClick={refreshDryRun}>刷新预检</button>
        <button className="link-button" onClick={refreshSafetyGate}>刷新安全门</button>
        <button className="link-button" onClick={refreshActionReview}>评审未来动作</button>
        <button className="link-button" onClick={verifyPlan}>验证计划</button>
        <button className="primary-action" onClick={copyCommands} disabled={!commandsFromGroups(plan).length}>复制命令</button>
        <button className="primary-action" onClick={copyMarkdown} disabled={!plan.markdown}>复制 Markdown</button>
        <button className="link-button" onClick={() => mark('running_manually')}>标记执行中</button>
        <button className="link-button" onClick={() => mark('succeeded')}>标记成功</button>
        <button className="link-button" onClick={() => mark('failed')}>标记失败</button>
        <button className="link-button" onClick={() => mark('rolled_back')}>标记已回滚</button>
        <button className="disabled inline" disabled>节点执行已阻止</button>
        <button className="link-button" onClick={archive}>归档</button>
        {copyText && <span className="muted">{copyText}</span>}
      </div>
    </section>
  );
}

function MetadataActions({ plan, metadata, setMetadata, evidence, onSnapshot, onRollback, onExecuted, onVerified, onEvidence }) {
  function update(key, value) {
    setMetadata((prev) => ({ ...prev, [key]: value }));
  }
  return (
    <div className="metadata-actions">
      <p className="muted">这些操作只更新 Controller 审计元数据。不会修改节点、不会执行命令、不会创建 Agent 任务、不会创建快照、不会回滚、不会切换入口、不会重启 relay，也不会改变 Leikwan Core 配置。</p>
      <div className="kv">
        <span>执行人</span><strong>{plan.executed_by || '-'}</strong>
        <span>执行时间</span><strong>{plan.executed_at || '-'}</strong>
        <span>验证人</span><strong>{plan.verified_by || '-'}</strong>
        <span>验证时间</span><strong>{plan.verified_at || '-'}</strong>
      </div>
      <label>共享备注<textarea value={metadata.note} onChange={(e) => update('note', e.target.value)} placeholder="用于 timeline/event 审计的脱敏备注" /></label>
      <div className="split-grid">
        <div className="mini-form">
          <h5>记录快照引用</h5>
          <label>快照引用<input value={metadata.snapshot_ref} onChange={(e) => update('snapshot_ref', e.target.value)} placeholder="snapshot-YYYYMMDD-HHMMSS.tar.gz" /></label>
          <label>快照备注<textarea value={metadata.snapshot_note} onChange={(e) => update('snapshot_note', e.target.value)} placeholder="人工快照备注" /></label>
          <button className="primary-action" type="button" onClick={onSnapshot}>记录快照引用</button>
        </div>
        <div className="mini-form">
          <h5>记录回滚引用</h5>
          <label>回滚引用<input value={metadata.rollback_ref} onChange={(e) => update('rollback_ref', e.target.value)} placeholder="回滚路径 / 旧状态引用" /></label>
          <label>回滚备注<textarea value={metadata.rollback_note} onChange={(e) => update('rollback_note', e.target.value)} placeholder="人工回滚备注" /></label>
          <button className="primary-action" type="button" onClick={onRollback}>记录回滚引用</button>
        </div>
        <div className="mini-form">
          <h5>人工执行</h5>
          <label>状态<select value={metadata.execution_status} onChange={(e) => update('execution_status', e.target.value)}>
            {['running_manually', 'succeeded', 'failed', 'rolled_back'].map((status) => <option key={status} value={status}>{labelStatus(status)}</option>)}
          </select></label>
          <button className="primary-action" type="button" onClick={onExecuted}>标记人工执行</button>
        </div>
        <div className="mini-form">
          <h5>人工验证</h5>
          <label>状态<select value={metadata.verification_status} onChange={(e) => update('verification_status', e.target.value)}>
            {['passed', 'warning', 'failed'].map((status) => <option key={status} value={status}>{labelStatus(status)}</option>)}
          </select></label>
          <button className="primary-action" type="button" onClick={onVerified}>标记人工验证</button>
        </div>
      </div>
      <form className="mini-form evidence-form" onSubmit={onEvidence}>
        <h5>附加人工证据</h5>
        <label>证据类型<input value={metadata.evidence_type} onChange={(e) => update('evidence_type', e.target.value)} placeholder="manual" /></label>
        <label>标题<input value={metadata.title} onChange={(e) => update('title', e.target.value)} placeholder="变更后状态输出" /></label>
        <label>内容<textarea value={metadata.content} onChange={(e) => update('content', e.target.value)} placeholder="粘贴已脱敏的人工证据；Controller 会再次脱敏。" /></label>
        <button className="primary-action" type="submit">附加人工证据</button>
      </form>
      <h5>证据</h5>
      {evidence.length ? (
        <Table headers={['类型', '标题', '创建人', '创建时间', '内容']}>
          {evidence.map((item) => (
            <tr key={item.id}>
              <td>{item.evidence_type}</td>
              <td>{item.title}</td>
              <td>{item.created_by}</td>
              <td>{item.created_at}</td>
              <td><pre className="inline-pre">{item.redacted_content || item.content || '-'}</pre></td>
            </tr>
          ))}
        </Table>
      ) : <Empty text="暂无人工证据" />}
    </div>
  );
}

function commandsFromGroups(plan) {
  if (plan.command_groups?.length) {
    return plan.command_groups.flatMap((group) => [
      `# On ${group.role || 'unknown'} node: ${group.node_name || group.node_id || '-'}`,
      ...(group.commands || [])
    ]);
  }
  return plan.generated_commands || [];
}

function Checklist({ items, checked, onToggle }) {
  if (!items.length) return <Empty text="请先生成计划以创建检查清单" />;
  return (
    <div className="checklist">
      {items.map((item, idx) => (
        <label key={`${item}-${idx}`}>
          <input type="checkbox" checked={Boolean(checked[idx])} onChange={() => onToggle(idx)} />
          <span>{item}</span>
        </label>
      ))}
    </div>
  );
}

function CommandGroups({ groups, fallback }) {
  if (groups.length) {
    return (
      <div className="command-groups">
        {groups.map((group, idx) => (
          <div key={`${group.node_id}-${idx}`} className="command-group">
            <h5>{group.node_name || group.node_id || '目标节点'} <span className={`tag ${group.role}`}>{labelRole(group.role)}</span></h5>
            <pre className="command-box">{(group.commands || []).join('\n')}</pre>
          </div>
        ))}
      </div>
    );
  }
  return <pre className="command-box">{fallback.join('\n') || '请先生成计划以创建人工命令。'}</pre>;
}

function Preflight({ data }) {
  const value = objectOrEmpty(data);
  const checks = arrayOrEmpty(value.checks);
  if (!checks.length) return <Empty text="请运行预检或生成计划以创建检查项" />;
  return (
    <div className="preflight">
      <p>整体状态：<span className={`tag ${value.overall === 'ok' ? 'safe' : 'caution'}`}>{value.overall || 'unknown'}</span></p>
      {checks.map((check, idx) => (
        <div className={`preflight-row ${check.ok ? 'ok' : 'warn'}`} key={`${check.name}-${idx}`}>
          <span>{check.ok ? 'OK' : 'WARN'}</span>
          <strong>{check.name}</strong>
          <em>{check.message || '-'}</em>
        </div>
      ))}
    </div>
  );
}

function DryRun({ plan, onStart, onRefresh }) {
  const report = objectOrEmpty(plan.dry_run_report);
  const tasks = arrayOrEmpty(report.tasks);
  const warnings = arrayOrEmpty(report.warnings);
  const doctorWarnings = arrayOrEmpty(report.doctor_warnings);
  return (
    <div className="dry-run">
      <p className="muted">这里只会创建只读任务，不会应用任何配置变更。</p>
      <div className="kv">
        <span>状态</span><strong><span className={`tag ${plan.dry_run_status}`}>{labelStatus(plan.dry_run_status || 'not_run')}</span></strong>
        <span>最近运行</span><strong>{plan.last_dry_run_at || '-'}</strong>
        <span>任务 ID</span><strong>{(plan.dry_run_task_ids || []).join(', ') || '-'}</strong>
        <span>建议</span><strong>{report.recommendation || '-'}</strong>
      </div>
      <div className="button-row">
        <button className="primary-action" onClick={onStart}>开始预检</button>
        <button className="link-button" onClick={onRefresh} disabled={!(plan.dry_run_task_ids || []).length}>刷新报告</button>
      </div>
      <h5>预检报告</h5>
      <pre className="command-box">{JSON.stringify(report, null, 2)}</pre>
      {tasks.length > 0 && (
        <>
          <h5>关联只读任务</h5>
          <Table headers={['任务', '动作', '状态', '退出码', '错误']}>
            {tasks.map((task) => (
              <tr key={task.id}>
                <td>{task.id}</td>
                <td>{task.action}</td>
                <td><span className={`tag ${task.status}`}>{labelStatus(task.status)}</span></td>
                <td>{task.exit_code}</td>
                <td>{task.error || '-'}</td>
              </tr>
            ))}
          </Table>
        </>
      )}
      <List title="警告" items={[...warnings, ...doctorWarnings]} empty="暂无预检警告" />
    </div>
  );
}

function SnapshotRollback({ plan, snapshot, rollback, setSnapshot, setRollback, onSnapshot, onRollback }) {
  return (
    <div className="snapshot-rollback">
      <p className="muted">3.0.0-alpha.4 只记录人工快照和回滚信息。Demo apply 不创建快照，也不执行回滚。</p>
      <div className="kv">
        <span>快照策略</span><strong>{plan.snapshot_policy || 'recommended'}</strong>
        <span>快照状态</span><strong><span className={`tag ${plan.snapshot_status}`}>{labelStatus(plan.snapshot_status || 'missing')}</span></strong>
        <span>快照引用</span><strong>{plan.snapshot_ref || '-'}</strong>
        <span>回滚可用</span><strong>{String(Boolean(plan.rollback_available))}</strong>
        <span>回滚引用</span><strong>{plan.rollback_ref || '-'}</strong>
      </div>
      <div className="split-grid">
        <form className="mini-form" onSubmit={onSnapshot}>
          <h5>记录快照</h5>
          <label>快照引用<input value={snapshot.snapshot_ref} onChange={(e) => setSnapshot((prev) => ({ ...prev, snapshot_ref: e.target.value }))} placeholder="snapshot-20260512-120000.tar.gz" /></label>
          <label>快照备注<textarea value={snapshot.snapshot_note} onChange={(e) => setSnapshot((prev) => ({ ...prev, snapshot_note: e.target.value }))} placeholder="操作人、位置或人工验证备注" /></label>
          <button className="primary-action" type="submit">记录快照元数据</button>
        </form>
        <form className="mini-form" onSubmit={onRollback}>
          <h5>记录回滚信息</h5>
          <label>回滚引用<input value={rollback.rollback_ref} onChange={(e) => setRollback((prev) => ({ ...prev, rollback_ref: e.target.value }))} placeholder="回滚备注 / 旧状态引用" /></label>
          <label>回滚备注<textarea value={rollback.rollback_note} onChange={(e) => setRollback((prev) => ({ ...prev, rollback_note: e.target.value }))} placeholder="如何人工恢复到旧状态" /></label>
          <button className="primary-action" type="submit">记录回滚元数据</button>
        </form>
      </div>
      <h5>回滚说明</h5>
      <pre className="command-box">{plan.rollback_instructions || '请先生成计划以创建回滚说明。'}</pre>
    </div>
  );
}

function SafetyGate({ gate, plan, onRefresh, onVerify }) {
  const fallback = {
    dry_run_passed: (plan.dry_run_status || 'not_run') === 'passed',
    approval_ready: (plan.safety_level || 'safe') !== 'dangerous' && (plan.command_classification || 'manual') !== 'blocked',
    snapshot_ready: ['not_required', 'recorded', 'verified'].includes(plan.snapshot_status || 'missing'),
    rollback_ready: Boolean(plan.rollback_available || plan.rollback_ref || plan.rollback_instructions),
    blocked_reasons: [],
    warnings: ['请刷新安全门以查看 Controller 侧检查结果。'],
    overall: planGateLabel(plan)
  };
  const value = gate || fallback;
  return (
    <div className="safety-gate">
      <p className="muted">安全门是审计检查清单，不是执行许可。它不会联系 Agent，也不会改变节点。</p>
      <div className="kv">
        <span>整体状态</span><strong><span className={`tag ${value.overall}`}>{labelStatus(value.overall)}</span></strong>
        <span>预检通过</span><strong>{String(Boolean(value.dry_run_passed))}</strong>
        <span>审批就绪</span><strong>{String(Boolean(value.approval_ready))}</strong>
        <span>快照就绪</span><strong>{String(Boolean(value.snapshot_ready))}</strong>
        <span>回滚就绪</span><strong>{String(Boolean(value.rollback_ready))}</strong>
      </div>
      <List title="阻止原因" items={value.blocked_reasons || []} empty="暂无阻止原因" />
      <List title="警告" items={value.warnings || []} empty="暂无警告" />
      <h5>验证报告</h5>
      <pre className="command-box">{JSON.stringify(objectOrEmpty(plan.verification_report), null, 2)}</pre>
      <div className="button-row">
        <button className="link-button" onClick={onRefresh}>刷新安全门</button>
        <button className="link-button" onClick={onVerify}>按当前 Controller 状态验证</button>
      </div>
    </div>
  );
}

function ActionReview({ review, plan, onRefresh }) {
  const value = review || {
    matched_action: plan.type || '-',
    category: 'future_write_guarded',
    risk_level: 'unknown',
    required_gates: [],
    required_capabilities: [],
    missing_gates: ['请刷新动作评审'],
    ready_for_future_execution: false,
    reason: '请刷新动作评审以查看 Controller 侧检查结果。'
  };
  return (
    <div className="action-review">
      <p className="muted">3.0.0-alpha.4 将未来节点写操作与 demo apply 分开评审。评审不会生成命令字符串，也不会绕过安全门。</p>
      <div className="kv">
        <span>匹配动作</span><strong>{value.matched_action}</strong>
        <span>类别</span><strong><span className={`tag ${value.category}`}>{value.category}</span></strong>
        <span>风险等级</span><strong><span className={`tag ${value.risk_level}`}>{labelStatus(value.risk_level)}</span></strong>
        <span>已启用</span><strong>{String(Boolean(value.enabled))}</strong>
        <span>未来执行就绪</span><strong>{String(Boolean(value.ready_for_future_execution))}</strong>
        <span>原因</span><strong>{value.reason || '-'}</strong>
      </div>
      <List title="所需安全门" items={value.required_gates || []} empty="不需要安全门" />
      <List title="缺失安全门" items={value.missing_gates || []} empty="暂无缺失安全门" />
      <List title="所需能力" items={value.required_capabilities || []} empty="暂无能力要求" />
      <div className="button-row">
        <button className="link-button" onClick={onRefresh}>刷新动作评审</button>
        <button className="disabled inline" disabled>未来节点写操作已禁用</button>
      </div>
    </div>
  );
}

const readonlyActions = [
  'probe_core_version',
  'run_status',
  'run_status_json',
  'run_doctor',
  'run_doctor_json',
  'list_forwards',
  'ddns_overview'
];

const alphaWriteActions = [
  'configure_node_role',
  'apply_network_profile',
  'apply_entry_config',
  'apply_forward_config',
  'reload_leikwan_core',
  'verify_applied_config'
];

function Tasks({ nodes, onNavigate }) {
  const [tasks, setTasks] = useState([]);
  const [form, setForm] = useState({ node_id: nodes[0]?.node_id || '', action: 'run_status_json' });
  const [error, setError] = useState('');
  useEffect(() => {
    loadTasks();
  }, []);
  useEffect(() => {
    if (!form.node_id && nodes[0]?.node_id) {
      setForm((prev) => ({ ...prev, node_id: nodes[0].node_id }));
    }
  }, [nodes]);
  async function loadTasks() {
    try {
      setTasks(await getJSON('/api/v1/tasks'));
      setError('');
    } catch (err) {
      setError(err.message);
    }
  }
  async function createTask(e) {
    e.preventDefault();
    try {
      const res = await apiFetch('/api/v1/tasks', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(form)
      });
      if (!res.ok) throw new Error(errorMessage(res));
      await loadTasks();
    } catch (err) {
      setError(err.message);
    }
  }
  return (
    <div className="tasks-page">
      {error && <div className="banner">任务请求失败：{error}</div>}
      <section className="panel">
        <h3>创建只读任务</h3>
        <p className="muted">这里仅手动创建内置只读任务。应用配置页面会自动创建 alpha 写任务；API 不接受任意命令字符串。</p>
        <form className="form-grid" onSubmit={createTask}>
          <label>节点<select value={form.node_id} onChange={(e) => setForm((prev) => ({ ...prev, node_id: e.target.value }))}>
            <option value="">选择节点</option>
            {nodes.map((node) => <option key={node.node_id} value={node.node_id}>{node.node_name || node.node_id}</option>)}
          </select></label>
          <label>动作<select value={form.action} onChange={(e) => setForm((prev) => ({ ...prev, action: e.target.value }))}>
            {readonlyActions.map((action) => <option key={action} value={action}>{action}</option>)}
          </select></label>
          <button className="primary-action" type="submit" disabled={!form.node_id}>创建只读任务</button>
          <button className="disabled inline" disabled>任意命令已禁用</button>
        </form>
      </section>
      <section>
        <h3>任务列表</h3>
        <TasksList tasks={tasks} nodes={nodes} onOpen={(id) => onNavigate(`/tasks/${encodeURIComponent(id)}`)} onReload={loadTasks} />
      </section>
    </div>
  );
}

async function postTaskAction(id, action, body = {}) {
  const res = await apiFetch(`/api/v1/tasks/${id}/${action}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  });
  if (!res.ok) throw new Error(errorMessage(res));
  return res.json();
}

function TasksList({ tasks, nodes, onOpen, onReload }) {
  if (!tasks.length) return <Empty text="暂无任务" />;
  const names = Object.fromEntries(nodes.map((node) => [node.node_id, node.node_name || node.node_id]));
  async function act(id, action) {
    await postTaskAction(id, action, { actor: 'panel-ui' });
    await onReload();
  }
  return (
    <Table headers={['ID', '节点', '动作', '任务组', '类型', '状态', '审批', '次数', '创建', '过期', '领取', '完成', '结果', '操作']}>
      {tasks.map((task) => (
        <tr key={task.id}>
          <td><button className="link-button" onClick={() => onOpen(task.id)}>{task.id}</button></td>
          <td>{names[task.node_id] || task.node_id}</td>
          <td>{task.action}</td>
          <td>{task.task_group_id || '-'}</td>
          <td><span className={`tag ${alphaWriteActions.includes(task.action) ? 'alpha_write' : 'readonly'}`}>{alphaWriteActions.includes(task.action) ? 'alpha 写' : '只读'}</span></td>
          <td><span className={`tag ${task.status}`}>{labelStatus(task.status)}</span></td>
          <td><span className={`tag ${task.approval_status}`}>{labelStatus(task.approval_status || 'not_required')}</span></td>
          <td>{task.attempt || 1}/{task.max_attempts || 3}{task.retry_of_task_id ? ` of #${task.retry_of_task_id}` : ''}</td>
          <td>{task.created_at || '-'}</td>
          <td>{task.expires_at || '-'}</td>
          <td>{task.picked_at || '-'}</td>
          <td>{task.finished_at || '-'}</td>
          <td>
            {(task.result_stdout || task.result_stderr) ? (
              <details className="task-result">
                <summary>查看脱敏输出</summary>
                {task.result_stdout && <pre>{task.result_stdout}</pre>}
                {task.result_stderr && <pre>{task.result_stderr}</pre>}
              </details>
            ) : '-'}
          </td>
          <td className="button-row compact">
            <button onClick={() => onOpen(task.id)}>详情</button>
            <button onClick={() => act(task.id, 'cancel')} disabled={!['queued', 'picked'].includes(task.status)}>取消</button>
            <button onClick={() => act(task.id, 'retry')} disabled={!['failed', 'expired', 'canceled'].includes(task.status)}>重试</button>
          </td>
        </tr>
      ))}
    </Table>
  );
}

function TaskDetail({ taskId, nodes, onNavigate }) {
  const [state, setState] = useState({ task: null, timeline: [], loading: true, error: '' });
  const names = Object.fromEntries(nodes.map((node) => [node.node_id, node.node_name || node.node_id]));
  async function load() {
    try {
      const [task, timeline] = await Promise.all([
        getJSON(`/api/v1/tasks/${encodeURIComponent(taskId)}`),
        getJSON(`/api/v1/tasks/${encodeURIComponent(taskId)}/timeline`)
      ]);
      setState({ task, timeline, loading: false, error: '' });
    } catch (err) {
      setState((prev) => ({ ...prev, loading: false, error: err.message }));
    }
  }
  useEffect(() => {
    load();
  }, [taskId]);
  async function act(action) {
    try {
      await postTaskAction(taskId, action, { actor: 'panel-ui' });
      await load();
    } catch (err) {
      setState((prev) => ({ ...prev, error: err.message }));
    }
  }
  async function copyResult() {
    const task = state.task || {};
    await navigator.clipboard.writeText([task.result_stdout || '', task.result_stderr || '', task.error || ''].filter(Boolean).join('\n'));
  }
  if (state.loading) return <Empty text="正在加载任务详情" />;
  if (state.error && !state.task) return <div className="banner">任务详情加载失败：{state.error}</div>;
  const task = state.task;
  const node = nodes.find((item) => item.node_id === task.node_id);
  return (
    <div className="detail task-detail">
      {state.error && <div className="banner">任务操作失败：{state.error}</div>}
      <section className="panel">
        <button className="link-button" onClick={() => onNavigate('/tasks')}>返回任务中心</button>
        <h3>任务 #{task.id}</h3>
        <div className="kv">
          <span>节点</span><strong>{names[task.node_id] || task.node_id}</strong>
          <span>角色</span><strong>{labelRole(node?.role)}</strong>
          <span>动作</span><strong>{task.action}</strong>
          <span>分类</span><strong><span className={`tag ${alphaWriteActions.includes(task.action) ? 'alpha_write' : 'readonly'}`}>{alphaWriteActions.includes(task.action) ? 'alpha 写操作' : '只读'}</span></strong>
          <span>状态</span><strong><span className={`tag ${task.status}`}>{labelStatus(task.status)}</span></strong>
          <span>审批</span><strong><span className={`tag ${task.approval_status}`}>{labelStatus(task.approval_status || 'not_required')}</span></strong>
          <span>请求人</span><strong>{task.requested_by || '-'}</strong>
          <span>审批人</span><strong>{task.approved_by || '-'}</strong>
          <span>创建时间</span><strong>{task.created_at || '-'}</strong>
          <span>领取时间</span><strong>{task.picked_at || '-'}</strong>
          <span>完成时间</span><strong>{task.finished_at || '-'}</strong>
          <span>过期时间</span><strong>{task.expires_at || '-'}</strong>
          <span>尝试次数</span><strong>{task.attempt || 1}/{task.max_attempts || 3}</strong>
          <span>重试来源</span><strong>{task.retry_of_task_id || '-'}</strong>
          <span>任务组</span><strong>{task.task_group_id || '-'}</strong>
        </div>
        <div className="button-row">
          <button onClick={() => act('cancel')} disabled={!['queued', 'picked'].includes(task.status)}>取消</button>
          <button onClick={() => act('retry')} disabled={!['failed', 'expired', 'canceled'].includes(task.status)}>重试</button>
          <button onClick={() => act('approve')}>批准</button>
          <button onClick={() => act('reject')}>拒绝</button>
          <button onClick={copyResult}>复制结果</button>
          <button className="disabled inline" disabled>人工写任务已阻止</button>
        </div>
      </section>
      <section className="panel">
        <h3>脱敏结果</h3>
        <div className="split-grid">
          <div><h4>stdout</h4><pre>{task.result_stdout || '-'}</pre></div>
          <div><h4>stderr</h4><pre>{task.result_stderr || '-'}</pre></div>
        </div>
        {task.error && <><h4>error</h4><pre>{task.error}</pre></>}
      </section>
      <section className="panel">
        <h3>时间线</h3>
        <List items={(state.timeline || []).map((item) => `${item.time} [${item.level}] ${item.action}: ${item.message}`)} empty="暂无时间线" />
      </section>
    </div>
  );
}

function Capabilities({ nodes }) {
  const [caps, setCaps] = useState({ commands: [], blocked_patterns: [], future: [], safety_levels: [], allowed_task_actions: [], task_support: '', loading: true, error: '' });
  useEffect(() => {
    let alive = true;
    getJSON('/api/v1/capabilities')
      .then((data) => alive && setCaps({ ...data, loading: false, error: '' }))
      .catch((err) => alive && setCaps((prev) => ({ ...prev, loading: false, error: err.message })));
    return () => { alive = false; };
  }, []);
  if (caps.loading) return <Empty text="正在加载能力状态" />;
  if (caps.error) return <div className="banner">能力状态加载失败：{caps.error}</div>;
  return (
    <div className="capabilities-page">
      <section className="panel">
        <h3>Controller CLI 能力分类</h3>
        <Table headers={['命令', '分类', '说明']}>
          {(caps.commands || []).map((item) => (
            <tr key={`${item.command}-${item.class}`}>
              <td>{item.command}</td>
              <td><span className={`tag ${item.class}`}>{item.class}</span></td>
              <td>{item.note}</td>
            </tr>
          ))}
        </Table>
      </section>
      <section className="panel">
        <h3>阻止模式</h3>
        <List items={caps.blocked_patterns || []} empty="暂无阻止模式" />
      </section>
      <section className="panel">
        <h3>只读任务支持</h3>
        <p className="muted">{caps.task_support || '未上报任务能力'}</p>
        <List items={caps.allowed_task_actions || []} empty="暂无只读任务动作" />
      </section>
      <section className="panel">
        <h3>节点上报能力</h3>
        {nodes.length ? (
          <Table headers={['节点', 'lq', 'Core', 'status json', 'doctor json', 'forward list', 'ddns overview', '任务开关', '快照记录', '回滚记录', '写操作', '任务动作']}>
            {nodes.map((node) => {
              const c = node.capabilities || {};
              return (
                <tr key={node.node_id}>
                  <td>{node.node_name || node.node_id}</td>
                  <td>{String(Boolean(c.lq_available))}</td>
                  <td>{c.core_version || node.core_version || '-'}</td>
                  <td>{String(Boolean(c.supports_status_json))}</td>
                  <td>{String(Boolean(c.supports_doctor_json))}</td>
                  <td>{String(Boolean(c.supports_forward_list))}</td>
                  <td>{String(Boolean(c.supports_ddns_overview))}</td>
                  <td>{String(Boolean(c.enable_tasks))}</td>
                  <td>{String(Boolean(c.supports_snapshot_manual_record))}</td>
                  <td>{String(Boolean(c.supports_rollback_manual_record))}</td>
                  <td>{String(Boolean(c.write_actions_supported))}</td>
                  <td>{(c.allowed_task_actions || []).join(', ') || '-'}</td>
                </tr>
              );
            })}
          </Table>
        ) : <Empty text="暂无节点上报" />}
      </section>
    </div>
  );
}

function ActionCatalog() {
  const [catalog, setCatalog] = useState({ version: '', actions: [], loading: true, error: '' });
  useEffect(() => {
    let alive = true;
    getJSON('/api/v1/action-catalog')
      .then((data) => alive && setCatalog({ ...data, loading: false, error: '' }))
      .catch((err) => alive && setCatalog((prev) => ({ ...prev, loading: false, error: err.message })));
    return () => { alive = false; };
  }, []);
  if (catalog.loading) return <Empty text="正在加载动作目录" />;
  if (catalog.error) return <div className="banner">动作目录加载失败：{catalog.error}</div>;
  return (
    <div className="action-catalog-page">
      <section className="panel">
        <h3>动作目录</h3>
        <p className="muted">3.0.0-alpha.4 启用 metadata-only 动作和固定 alpha apply 动作。create_forward、switch_entry、restart_relay 等高层未来动作仍保持禁用。</p>
        <Table headers={['动作', '类别', '风险', '启用', '修改节点', '需要 Agent', '命令下发', 'Operator Token', '所需安全门', '快照', '回滚', '审批', '说明']}>
          {(catalog.actions || []).map((action) => (
            <tr key={action.action}>
              <td>{action.action}</td>
              <td><span className={`tag ${action.category}`}>{action.category}</span></td>
              <td><span className={`tag ${action.risk_level}`}>{labelStatus(action.risk_level)}</span></td>
              <td><span className={`tag ${action.enabled ? 'ready' : 'disabled'}`}>{action.enabled ? '已启用' : '已禁用 / 未来功能'}</span></td>
              <td>{String(Boolean(action.node_mutation))}</td>
              <td>{String(Boolean(action.agent_required))}</td>
              <td>{String(Boolean(action.command_dispatch))}</td>
              <td>{String(Boolean(action.operator_token_required))}</td>
              <td>{(action.required_gates || []).join(', ') || '-'}</td>
              <td>{String(Boolean(action.snapshot_required))}</td>
              <td>{String(Boolean(action.rollback_required))}</td>
              <td>{String(Boolean(action.approval_required))}</td>
              <td>{action.description}</td>
            </tr>
          ))}
        </Table>
      </section>
    </div>
  );
}

function Metric({ label, value }) {
  return (
    <div className="metric">
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  );
}

function Nodes({ nodes, onOpen }) {
  async function copyRejoin(node) {
    const q = new URLSearchParams({
      controller_url: window.location.origin,
      node_name: node.node_name || node.node_id || 'leikwan-node',
      role: node.role || 'unknown',
      enable_tasks: String(Boolean(node.capabilities?.enable_tasks ?? true)),
      enable_write_actions: String(Boolean(node.capabilities?.write_actions_supported)),
      method: 'curl',
      token_mode: getOperatorToken() ? 'full' : 'masked'
    }).toString();
    const data = await getJSON(`/api/v1/bootstrap/agent-install-command?${q}`);
    await navigator.clipboard.writeText(data.command || data.masked_command || '');
  }
  if (!nodes.length) return <Empty text="暂无节点，请先进入“添加节点”复制安装命令" />;
  return (
    <Table headers={['名称', '角色', '公网 IP', 'Core', 'Agent', '只读任务', '写操作', '支持动作', '状态', '心跳', '加入命令']}>
      {nodes.map((n) => (
        <tr key={n.node_id}>
          <td><button className="link-button" onClick={() => onOpen(n.node_id)}>{n.node_name || n.node_id}</button></td>
          <td>{labelRole(n.role)}</td>
          <td>{n.public_ip || '-'}</td>
          <td>{n.core_version || '-'}</td>
          <td>{n.agent_version || '-'}</td>
          <td>{String(Boolean(n.capabilities?.enable_tasks))}</td>
          <td>{String(Boolean(n.capabilities?.write_actions_supported))}</td>
          <td>{(n.capabilities?.supported_write_actions || []).join(', ') || '-'}</td>
          <td><span className={`tag ${n.status}`}>{labelStatus(n.status)}</span></td>
          <td>{n.last_seen || '-'}</td>
          <td><button className="link-button" onClick={() => copyRejoin(n)}>复制重装命令</button></td>
        </tr>
      ))}
    </Table>
  );
}

function NodeDetail({ nodeId, entries, forwards }) {
  const [detail, setDetail] = useState({ node: null, reports: [], events: [], raw: null, loading: true, error: '' });
  const [actionMessage, setActionMessage] = useState('');
  useEffect(() => {
    let alive = true;
    async function load() {
      try {
        const [node, reports, events, raw] = await Promise.all([
          getJSON(`/api/v1/nodes/${encodeURIComponent(nodeId)}`),
          getJSON(`/api/v1/nodes/${encodeURIComponent(nodeId)}/reports?limit=20`),
          getJSON(`/api/v1/nodes/${encodeURIComponent(nodeId)}/events?limit=20`),
          getJSON(`/api/v1/nodes/${encodeURIComponent(nodeId)}/raw`)
        ]);
        if (alive) setDetail({ node, reports, events, raw, loading: false, error: '' });
      } catch (err) {
        if (alive) setDetail((prev) => ({ ...prev, loading: false, error: err.message }));
      }
    }
    load();
    return () => { alive = false; };
  }, [nodeId]);
  if (detail.loading) return <Empty text="正在加载节点详情" />;
  if (detail.error) return <div className="banner">节点详情加载失败：{detail.error}</div>;
  const node = detail.node;
  const nodeEntries = entries.filter((e) => e.node_id === nodeId);
  const nodeForwards = forwards.filter((f) => f.node_id === nodeId);
  const doctor = objectOrEmpty(node.doctor);
  const warnings = arrayOrEmpty(doctor.warnings);
  const suggestions = arrayOrEmpty(doctor.suggestions);
  async function runNodeAction(path, body = {}) {
    try {
      const res = await apiFetch(`/api/v1/nodes/${encodeURIComponent(nodeId)}/${path}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body)
      });
      if (!res.ok) throw new Error(errorMessage(res));
      const task = await res.json();
      setActionMessage(`已创建任务：${path} #${task.id}`);
    } catch (err) {
      setActionMessage(err.message);
    }
  }
  return (
    <div className="detail">
      <section className="panel">
        <h3>基础信息</h3>
        <dl className="kv">
          <dt>名称</dt><dd>{node.node_name || node.node_id}</dd>
          <dt>角色</dt><dd>{labelRole(node.role)}</dd>
          <dt>状态</dt><dd><span className={`tag ${node.status}`}>{labelStatus(node.status)}</span></dd>
          <dt>Public IP</dt><dd>{node.public_ip || '-'}</dd>
          <dt>LAN IP</dt><dd>{node.lan_ip || '-'}</dd>
          <dt>EasyTier IP</dt><dd>{node.easytier_ip || '-'}</dd>
          <dt>Core</dt><dd>{node.core_version || '-'}</dd>
          <dt>Agent</dt><dd>{node.agent_version || '-'}</dd>
          <dt>最后心跳</dt><dd>{node.last_seen || '-'}</dd>
        </dl>
      </section>
      <section className="panel">
        <h3>服务状态</h3>
        <KeyValue data={node.services || {}} />
      </section>
      <section className="panel">
        <h3>节点操作</h3>
        <p className="muted">这些按钮只创建固定 Agent 任务。重启服务器是危险操作，需要确认。</p>
        <div className="action-row">
          <button onClick={() => runNodeAction('restart-agent')}>重启 Agent</button>
          <button onClick={() => runNodeAction('restart-easytier')}>重启 EasyTier</button>
          <button className="danger" onClick={() => { if (window.prompt('重启服务器是危险操作，请输入 REBOOT 确认') === 'REBOOT') runNodeAction('reboot', { confirm: 'REBOOT' }); }}>重启服务器</button>
        </div>
        {actionMessage && <div className="banner">{actionMessage}</div>}
      </section>
      <section className="panel">
        <h3>诊断</h3>
        <p>整体状态：{doctor.overall || '-'}</p>
        <List title="告警" items={warnings} />
        <List title="建议" items={suggestions} />
      </section>
      <section className="panel">
        <h3>最近错误</h3>
        <List items={node.recent_errors || []} empty="暂无错误" />
      </section>
      <section>
        <h3>公网入口</h3>
        <EntriesTable entries={nodeEntries} />
      </section>
      <section>
        <h3>转发规则</h3>
        <ForwardsTable forwards={nodeForwards} />
      </section>
      <section>
        <h3>最近上报</h3>
        <Reports reports={detail.reports.slice(0, 20)} />
      </section>
      <section>
        <h3>节点事件</h3>
        <Events events={detail.events.slice(0, 20)} />
      </section>
      <details className="raw">
        <summary>脱敏 raw_json</summary>
        <pre>{JSON.stringify(detail.raw, null, 2)}</pre>
      </details>
    </div>
  );
}

function objectOrEmpty(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return {};
  return value;
}

function arrayOrEmpty(value) {
  return Array.isArray(value) ? value : [];
}

function KeyValue({ data }) {
  const entries = Object.entries(data);
  if (!entries.length) return <Empty text="暂无服务数据上报" />;
  return (
    <dl className="kv">
      {entries.map(([key, value]) => (
        <React.Fragment key={key}>
          <dt>{key}</dt><dd>{String(value || '-')}</dd>
        </React.Fragment>
      ))}
    </dl>
  );
}

function List({ title, items, empty = '无' }) {
  return (
    <div className="list-block">
      {title && <strong>{title}</strong>}
      {items.length ? <ul>{items.map((item, i) => <li key={`${item}-${i}`}>{String(item)}</li>)}</ul> : <p>{empty}</p>}
    </div>
  );
}

function Reports({ reports }) {
  if (!reports.length) return <Empty text="暂无上报记录" />;
  return (
    <Table headers={['时间', '状态', '健康度', '间隔', '错误']}>
      {reports.map((r) => (
        <tr key={r.id}>
          <td>{r.created_at}</td>
          <td><span className={`tag ${r.status}`}>{labelStatus(r.status)}</span></td>
          <td>{r.health_score}</td>
          <td>{r.interval_seconds}s</td>
          <td>{(r.recent_errors || []).join('; ') || '-'}</td>
        </tr>
      ))}
    </Table>
  );
}

function Entries({ entries, nodes = [], profiles = [] }) {
  const entryNodes = nodes.filter((node) => node.status === 'online' && ['entry', 'mixed', 'unknown'].includes(node.role));
  const relayNodes = nodes.filter((node) => node.status === 'online' && ['relay', 'mixed', 'unknown'].includes(node.role));
  const [items, setItems] = useState(entries || []);
  const [form, setForm] = useState({
    network_id: profiles[0]?.id || '',
    entry_node_id: entryNodes[0]?.node_id || '',
    relay_node_id: relayNodes[0]?.node_id || '',
    listen_host: '0.0.0.0',
    listen_port_start: 10000,
    listen_port_end: 19999,
    protocols: 'both'
  });
  const [error, setError] = useState('');
  useEffect(() => setItems(entries || []), [entries]);
  useEffect(() => {
    setForm((prev) => ({
      ...prev,
      network_id: prev.network_id || profiles[0]?.id || '',
      entry_node_id: prev.entry_node_id || entryNodes[0]?.node_id || '',
      relay_node_id: prev.relay_node_id || relayNodes[0]?.node_id || ''
    }));
  }, [nodes, profiles]);
  async function refresh() {
    setItems(await getJSON('/api/v1/entries'));
  }
  async function create(e) {
    e.preventDefault();
    try {
      const res = await apiFetch('/api/v1/entries', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ...form, network_id: Number(form.network_id), listen_port_start: Number(form.listen_port_start), listen_port_end: Number(form.listen_port_end) })
      });
      if (!res.ok) throw new Error(errorMessage(res));
      await refresh();
      setError('');
    } catch (err) {
      setError(err.message);
    }
  }
  async function apply(id) {
    try {
      const res = await apiFetch(`/api/v1/entries/${id}/apply`, { method: 'POST' });
      if (!res.ok) throw new Error(errorMessage(res));
      await refresh();
      setError('');
    } catch (err) {
      setError(err.message);
    }
  }
  if (nodes.length || profiles.length) {
    return (
      <div className="entries-page">
        {error && <div className="banner">入口请求失败：{error}</div>}
        <section className="panel">
          <h3>创建公网入口</h3>
          <p className="muted">应用入口会为入口节点和 Relay 节点创建 EasyTier、端口范围、防火墙重载和校验任务。当前为 alpha 版本，应用配置可能中断现有连接，请先在测试环境验证。</p>
          <form className="form-grid" onSubmit={create}>
            <label>组网 *<select value={form.network_id} onChange={(e) => setForm((prev) => ({ ...prev, network_id: e.target.value }))}>
              <option value="">选择组网</option>
              {profiles.map((profile) => <option key={profile.id} value={profile.id}>{profile.name}</option>)}
            </select></label>
            <label>入口节点 *<select value={form.entry_node_id} onChange={(e) => setForm((prev) => ({ ...prev, entry_node_id: e.target.value }))}>
              <option value="">选择入口节点</option>
              {entryNodes.map((node) => <option key={node.node_id} value={node.node_id}>{node.node_name || node.node_id}</option>)}
            </select></label>
            <label>Relay 节点 *<select value={form.relay_node_id} onChange={(e) => setForm((prev) => ({ ...prev, relay_node_id: e.target.value }))}>
              <option value="">选择 Relay 节点</option>
              {relayNodes.map((node) => <option key={node.node_id} value={node.node_id}>{node.node_name || node.node_id}</option>)}
            </select></label>
            <label>监听地址<input value={form.listen_host} onChange={(e) => setForm((prev) => ({ ...prev, listen_host: e.target.value }))} /></label>
            <label>端口起始 *<input type="number" value={form.listen_port_start} onChange={(e) => setForm((prev) => ({ ...prev, listen_port_start: e.target.value }))} /></label>
            <label>端口结束 *<input type="number" value={form.listen_port_end} onChange={(e) => setForm((prev) => ({ ...prev, listen_port_end: e.target.value }))} /></label>
            <label>协议<select value={form.protocols} onChange={(e) => setForm((prev) => ({ ...prev, protocols: e.target.value }))}>
              {['tcp', 'udp', 'both'].map((p) => <option key={p} value={p}>{p}</option>)}
            </select></label>
            <button className="primary-action" disabled={!form.network_id || !form.entry_node_id || !form.relay_node_id} type="submit">创建入口</button>
          </form>
        </section>
        <section>
          <h3>公网入口</h3>
          <EntriesTable entries={items} onApply={apply} />
        </section>
      </div>
    );
  }
  return <EntriesTable entries={entries} />;
}

function EntriesTable({ entries, onApply }) {
  if (!entries.length) return <Empty text="暂无公网入口，请先添加 Agent 节点并创建入口" />;
  return (
    <Table headers={['ID', '组网', '入口节点', 'Relay 节点', '监听', '协议', '状态', '操作']}>
      {entries.map((e) => (
        <tr key={`${e.id || e.node_id}-${e.entry_node_id || e.name}-${e.listen_port_start || e.listen_port}`}>
          <td>{e.id || '-'}</td>
          <td>{e.network_id || '-'}</td>
          <td>{e.entry_node_id || e.node_id || '-'}</td>
          <td>{e.relay_node_id || '-'}</td>
          <td>{e.listen_port_start ? `${e.listen_host || '0.0.0.0'}:${e.listen_port_start}-${e.listen_port_end}` : (e.listen_port || '-')}</td>
          <td>{e.protocols || e.protocol}</td>
          <td>{labelStatus(e.status)}</td>
          <td>{onApply && e.id ? <button className="primary-action" onClick={() => onApply(e.id)}>应用入口</button> : '-'}</td>
        </tr>
      ))}
    </Table>
  );
}

function Forwards({ forwards, nodes = [], profiles = [], entries = [], pbrPolicies = [] }) {
  const relayNodes = nodes.filter((node) => node.status === 'online' && ['relay', 'mixed', 'unknown'].includes(node.role));
  const [items, setItems] = useState(forwards || []);
  const [form, setForm] = useState({
    network_id: profiles[0]?.id || '',
    entry_id: entries[0]?.id || '',
    relay_node_id: relayNodes[0]?.node_id || '',
    name: 'demo-forward',
    listen_port: 10001,
    target_host: '',
    target_port: 443,
    protocol: 'both',
    pbr_policy_id: ''
  });
  const [error, setError] = useState('');
  useEffect(() => setItems(forwards || []), [forwards]);
  useEffect(() => {
    setForm((prev) => ({
      ...prev,
      network_id: prev.network_id || profiles[0]?.id || '',
      entry_id: prev.entry_id || entries[0]?.id || '',
      relay_node_id: prev.relay_node_id || relayNodes[0]?.node_id || ''
    }));
  }, [nodes, profiles, entries]);
  async function refresh() {
    setItems(await getJSON('/api/v1/forwards'));
  }
  async function create(e) {
    e.preventDefault();
    try {
      const res = await apiFetch('/api/v1/forwards', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ...form, network_id: Number(form.network_id), entry_id: Number(form.entry_id), listen_port: Number(form.listen_port), target_port: Number(form.target_port), pbr_policy_id: Number(form.pbr_policy_id || 0) })
      });
      if (!res.ok) throw new Error(errorMessage(res));
      await refresh();
      setError('');
    } catch (err) {
      setError(err.message);
    }
  }
  async function apply(id) {
    try {
      const res = await apiFetch(`/api/v1/forwards/${id}/apply`, { method: 'POST' });
      if (!res.ok) throw new Error(errorMessage(res));
      await refresh();
      setError('');
    } catch (err) {
      setError(err.message);
    }
  }
  if (nodes.length || profiles.length || entries.length) {
    return (
      <div className="forwards-page">
        {error && <div className="banner">转发请求失败：{error}</div>}
        <section className="panel">
          <h3>创建转发规则</h3>
          <p className="muted">落地/后端机器不需要安装 Agent，只需要填写 target_host:target_port。当前为 alpha 版本，应用配置可能中断现有连接，请先在测试环境验证。</p>
          <form className="form-grid" onSubmit={create}>
            <label>组网 *<select value={form.network_id} onChange={(e) => setForm((prev) => ({ ...prev, network_id: e.target.value }))}>
              <option value="">选择组网</option>
              {profiles.map((profile) => <option key={profile.id} value={profile.id}>{profile.name}</option>)}
            </select></label>
            <label>公网入口 *<select value={form.entry_id} onChange={(e) => setForm((prev) => ({ ...prev, entry_id: e.target.value }))}>
              <option value="">选择入口</option>
              {entries.map((entry) => <option key={entry.id} value={entry.id}>#{entry.id} {entry.entry_node_id}</option>)}
            </select></label>
            <label>Relay 节点 *<select value={form.relay_node_id} onChange={(e) => setForm((prev) => ({ ...prev, relay_node_id: e.target.value }))}>
              <option value="">选择 Relay 节点</option>
              {relayNodes.map((node) => <option key={node.node_id} value={node.node_id}>{node.node_name || node.node_id}</option>)}
            </select></label>
            <label>名称 *<input value={form.name} onChange={(e) => setForm((prev) => ({ ...prev, name: e.target.value }))} /></label>
            <label>监听端口 *<input type="number" value={form.listen_port} onChange={(e) => setForm((prev) => ({ ...prev, listen_port: e.target.value }))} /></label>
            <label>目标地址 *<input value={form.target_host} placeholder="10.0.0.8 或 service.example.com" onChange={(e) => setForm((prev) => ({ ...prev, target_host: e.target.value }))} /></label>
            <label>目标端口 *<input type="number" value={form.target_port} onChange={(e) => setForm((prev) => ({ ...prev, target_port: e.target.value }))} /></label>
            <label>协议<select value={form.protocol} onChange={(e) => setForm((prev) => ({ ...prev, protocol: e.target.value }))}>
              {['tcp', 'udp', 'both'].map((p) => <option key={p} value={p}>{p}</option>)}
            </select></label>
            <label>PBR 策略<select value={form.pbr_policy_id} onChange={(e) => setForm((prev) => ({ ...prev, pbr_policy_id: e.target.value }))}>
              <option value="">不绑定</option>
              {pbrPolicies.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
            </select></label>
            <button className="primary-action" disabled={!form.network_id || !form.entry_id || !form.relay_node_id || !form.target_host} type="submit">创建转发</button>
          </form>
        </section>
        <section>
          <h3>转发规则</h3>
          <ForwardsTable forwards={items} onApply={apply} />
        </section>
      </div>
    );
  }
  return <ForwardsTable forwards={forwards} />;
}

function ForwardsTable({ forwards, onApply }) {
  if (!forwards.length) return <Empty text="暂无转发规则" />;
  return (
    <Table headers={['ID', '组网', '入口', 'Relay 节点', '名称', '监听端口', '目标地址', '协议', '状态', '操作']}>
      {forwards.map((f) => (
        <tr key={`${f.id || f.node_id}-${f.name}-${f.target_port}`}>
          <td>{f.id || '-'}</td>
          <td>{f.network_id || '-'}</td>
          <td>{f.entry_id || f.entry_name || '-'}</td>
          <td>{f.relay_node_id || f.node_id || '-'}</td>
          <td>{f.name}</td>
          <td>{f.listen_port || '-'}</td>
          <td>{f.target_host}:{f.target_port}</td>
          <td>{f.protocol || f.protocols}</td>
          <td>{labelStatus(f.status)}</td>
          <td>{onApply && f.id ? <button className="primary-action" onClick={() => onApply(f.id)}>应用转发</button> : '-'}</td>
        </tr>
      ))}
    </Table>
  );
}

function PBR({ policies = [], nodes = [] }) {
  const relayNodes = nodes.filter((node) => node.status === 'online' && ['relay', 'mixed', 'unknown'].includes(node.role));
  const [items, setItems] = useState(policies || []);
  const [form, setForm] = useState({ name: 'pbr-demo', relay_node_id: relayNodes[0]?.node_id || '', source_cidr: '0.0.0.0/0', target_cidr: '0.0.0.0/0', output_interface: '', gateway: '', table_id: 100, priority: 1000, mark: '' });
  const [error, setError] = useState('');
  useEffect(() => setItems(policies || []), [policies]);
  useEffect(() => setForm((prev) => ({ ...prev, relay_node_id: prev.relay_node_id || relayNodes[0]?.node_id || '' })), [nodes]);
  async function refresh() { setItems(await getJSON('/api/v1/pbr-policies')); }
  async function create(e) {
    e.preventDefault();
    try {
      const res = await apiFetch('/api/v1/pbr-policies', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ ...form, table_id: Number(form.table_id), priority: Number(form.priority) }) });
      if (!res.ok) throw new Error(errorMessage(res));
      await refresh();
      setError('');
    } catch (err) { setError(err.message); }
  }
  async function apply(id) {
    try {
      const res = await apiFetch(`/api/v1/pbr-policies/${id}/apply`, { method: 'POST' });
      if (!res.ok) throw new Error(errorMessage(res));
      setError('出口策略应用任务已创建');
    } catch (err) { setError(err.message); }
  }
  return (
    <div>
      {error && <div className="banner">{error}</div>}
      <section className="panel">
        <h3>创建出口策略</h3>
        <form className="form-grid" onSubmit={create}>
          <label>名称<input value={form.name} onChange={(e) => setForm((p) => ({ ...p, name: e.target.value }))} /></label>
          <label>Relay 节点<select value={form.relay_node_id} onChange={(e) => setForm((p) => ({ ...p, relay_node_id: e.target.value }))}><option value="">选择 Relay</option>{relayNodes.map((n) => <option key={n.node_id} value={n.node_id}>{n.node_name || n.node_id}</option>)}</select></label>
          <label>源 CIDR<input value={form.source_cidr} onChange={(e) => setForm((p) => ({ ...p, source_cidr: e.target.value }))} /></label>
          <label>目标 CIDR<input value={form.target_cidr} onChange={(e) => setForm((p) => ({ ...p, target_cidr: e.target.value }))} /></label>
          <label>出口网卡<input value={form.output_interface} onChange={(e) => setForm((p) => ({ ...p, output_interface: e.target.value }))} /></label>
          <label>Gateway<input value={form.gateway} onChange={(e) => setForm((p) => ({ ...p, gateway: e.target.value }))} /></label>
          <label>路由表 ID<input type="number" value={form.table_id} onChange={(e) => setForm((p) => ({ ...p, table_id: e.target.value }))} /></label>
          <label>优先级<input type="number" value={form.priority} onChange={(e) => setForm((p) => ({ ...p, priority: e.target.value }))} /></label>
          <button className="primary-action" type="submit" disabled={!form.relay_node_id}>创建 PBR</button>
        </form>
      </section>
      <Table headers={['ID', '名称', 'Relay', '源', '目标', '路由表', '优先级', '状态', '操作']}>
        {items.map((p) => <tr key={p.id}><td>{p.id}</td><td>{p.name}</td><td>{p.relay_node_id}</td><td>{p.source_cidr}</td><td>{p.target_cidr}</td><td>{p.table_id}</td><td>{p.priority}</td><td>{labelStatus(p.status)}</td><td><button onClick={() => apply(p.id)}>应用</button></td></tr>)}
      </Table>
    </div>
  );
}

function DDNS({ profiles = [], nodes = [] }) {
  const [items, setItems] = useState(profiles || []);
  const [form, setForm] = useState({ node_id: nodes[0]?.node_id || '', provider: 'manual', domain: '', record_type: 'A', api_token: '', zone_id: '', record_id: '', target: '', interval_seconds: 300 });
  const [error, setError] = useState('');
  useEffect(() => setItems(profiles || []), [profiles]);
  useEffect(() => setForm((prev) => ({ ...prev, node_id: prev.node_id || nodes[0]?.node_id || '' })), [nodes]);
  async function refresh() { setItems(await getJSON('/api/v1/ddns-profiles')); }
  async function create(e) {
    e.preventDefault();
    try {
      const res = await apiFetch('/api/v1/ddns-profiles', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ ...form, interval_seconds: Number(form.interval_seconds) }) });
      if (!res.ok) throw new Error(errorMessage(res));
      await refresh();
      setError('');
    } catch (err) { setError(err.message); }
  }
  async function post(id, op) {
    try {
      const res = await apiFetch(`/api/v1/ddns-profiles/${id}/${op}`, { method: 'POST' });
      if (!res.ok) throw new Error(errorMessage(res));
      setError(`DDNS ${op === 'sync' ? '同步' : '应用'}任务已创建`);
    } catch (err) { setError(err.message); }
  }
  return (
    <div>
      {error && <div className="banner">{error}</div>}
      <section className="panel">
        <h3>创建 DDNS 配置</h3>
        <p className="muted">Token 只用于被控端同步，前端和日志会脱敏显示。</p>
        <form className="form-grid" onSubmit={create}>
          <label>节点<select value={form.node_id} onChange={(e) => setForm((p) => ({ ...p, node_id: e.target.value }))}><option value="">选择节点</option>{nodes.map((n) => <option key={n.node_id} value={n.node_id}>{n.node_name || n.node_id}</option>)}</select></label>
          <label>服务商<select value={form.provider} onChange={(e) => setForm((p) => ({ ...p, provider: e.target.value }))}>{['manual', 'generic_webhook', 'cloudflare'].map((p) => <option key={p} value={p}>{p}</option>)}</select></label>
          <label>域名<input value={form.domain} onChange={(e) => setForm((p) => ({ ...p, domain: e.target.value }))} /></label>
          <label>记录类型<select value={form.record_type} onChange={(e) => setForm((p) => ({ ...p, record_type: e.target.value }))}>{['A', 'AAAA'].map((p) => <option key={p} value={p}>{p}</option>)}</select></label>
          <label>API Token<input type="password" value={form.api_token} onChange={(e) => setForm((p) => ({ ...p, api_token: e.target.value }))} /></label>
          <label>Zone ID<input value={form.zone_id} onChange={(e) => setForm((p) => ({ ...p, zone_id: e.target.value }))} /></label>
          <label>Record ID<input value={form.record_id} onChange={(e) => setForm((p) => ({ ...p, record_id: e.target.value }))} /></label>
          <label>Webhook 目标<input value={form.target} onChange={(e) => setForm((p) => ({ ...p, target: e.target.value }))} /></label>
          <button className="primary-action" type="submit" disabled={!form.node_id || !form.domain}>创建 DDNS</button>
        </form>
      </section>
      <Table headers={['ID', '节点', '服务商', '域名', '类型', '状态', '最近同步', '操作']}>
        {items.map((d) => <tr key={d.id}><td>{d.id}</td><td>{d.node_id}</td><td>{d.provider}</td><td>{d.domain}</td><td>{d.record_type}</td><td>{labelStatus(d.status)}</td><td>{d.last_sync_at || '-'}</td><td><button onClick={() => post(d.id, 'apply')}>应用</button> <button onClick={() => post(d.id, 'sync')}>立即同步</button></td></tr>)}
      </Table>
    </div>
  );
}

function Events({ events, compact = false }) {
  if (!events.length) return <Empty text="暂无日志事件" />;
  return (
    <Table headers={compact ? ['级别', '消息', '时间'] : ['节点', '级别', '消息', '时间']}>
      {events.map((e) => (
        <tr key={e.id}>
          {!compact && <td>{e.node_id || '-'}</td>}
          <td><span className={`tag ${e.level}`}>{labelStatus(e.level)}</span></td>
          <td>{e.message}</td>
          <td>{e.created_at}</td>
        </tr>
      ))}
    </Table>
  );
}

function Table({ headers, children }) {
  return (
    <div className="table-wrap">
      <table>
        <thead>
          <tr>{headers.map((h) => <th key={h}>{h}</th>)}</tr>
        </thead>
        <tbody>{children}</tbody>
      </table>
    </div>
  );
}

function Empty({ text }) {
  return <div className="empty">{text}</div>;
}

createRoot(document.getElementById('root')).render(<App />);
