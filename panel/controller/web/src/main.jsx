import React, { useEffect, useMemo, useState } from 'react';
import { createRoot } from 'react-dom/client';
import './styles.css';

const TOKEN_KEY = 'edgeTunnelOperatorToken';
const API_BASE_KEY = 'edgeTunnelApiBase';

const tabs = [
  ['login', 'Login / Token'],
  ['dashboard', 'Dashboard'],
  ['nodes', 'Nodes'],
  ['add-agent', 'Add Agent'],
  ['networks', 'Network Profiles'],
  ['entries', 'Entries'],
  ['forwards', 'Forwards'],
  ['pbr', 'PBR'],
  ['tasks', 'Tasks'],
  ['settings', 'Settings']
];

const readonlyActions = [
  'collect_agent_status',
  'verify_agent_config',
  'verify_easytier_status',
  'verify_forward_rules',
  'verify_pbr_rules',
  'verify_ddns_status'
];

const taskStatuses = ['all', 'pending', 'running', 'succeeded', 'failed', 'expired', 'cancelled'];
const nodeRoles = ['entry', 'relay', 'exit', 'backend'];
const protocols = ['tcp', 'udp'];

function normalizeBase(value) {
  return value.trim().replace(/\/+$/, '');
}

function formatTime(value) {
  if (!value) return '-';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '-';
  return date.toLocaleString();
}

function summarize(value) {
  if (value === null || value === undefined || value === '') return '-';
  const text = typeof value === 'string' ? value : JSON.stringify(value, null, 2);
  return text.length > 360 ? `${text.slice(0, 360)}...` : text;
}

function statusClass(status) {
  return `badge ${status || 'unknown'}`;
}

function safeList(value) {
  return Array.isArray(value) ? value : [];
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

  const [agentForm, setAgentForm] = useState({
    controller_url: 'http://CONTROLLER_HOST:18080',
    node_name: 'edge-node-1',
    role: 'entry',
    enable_tasks: true,
    enable_write_actions: true
  });
  const [maskedCommand, setMaskedCommand] = useState('');
  const [fullCommand, setFullCommand] = useState('');
  const [showFullCommand, setShowFullCommand] = useState(false);

  const [networkForm, setNetworkForm] = useState({
    name: '',
    network_name: 'edge-net',
    network_secret: '',
    cidr: '10.144.0.0/16',
    protocol_preference: 'auto'
  });
  const [networkApplyNode, setNetworkApplyNode] = useState({});

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
    if (!response.ok) {
      const message = payload?.error?.message || `${response.status} ${response.statusText}`;
      throw new Error(message);
    }
    if (payload && typeof payload.ok === 'boolean') {
      if (!payload.ok) throw new Error(payload.error?.message || 'request failed');
      return payload.data;
    }
    return payload;
  }

  async function run(label, fn) {
    setLoading(true);
    setAlert(null);
    try {
      const result = await fn();
      setAlert({ type: 'success', message: `${label} completed` });
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
    run('Refresh', refreshAll);
  }, []);

  function saveToken() {
    localStorage.setItem(TOKEN_KEY, tokenDraft);
    setToken(tokenDraft);
    setAlert({ type: 'success', message: 'Operator token saved' });
  }

  function clearToken() {
    localStorage.removeItem(TOKEN_KEY);
    setToken('');
    setTokenDraft('');
    setAlert({ type: 'success', message: 'Operator token cleared' });
  }

  function saveApiBase() {
    const next = normalizeBase(apiBaseDraft);
    if (next) localStorage.setItem(API_BASE_KEY, next);
    else localStorage.removeItem(API_BASE_KEY);
    setApiBase(next);
    setAlert({ type: 'success', message: 'API base saved' });
  }

  async function createTask(nodeId, action) {
    await run('Task creation', async () => {
      await api('/tasks', { body: { node_id: nodeId, action, payload: {} } });
      await refreshTasks();
    });
  }

  async function generateAgentCommand(showFull) {
    const data = await run('Agent command generation', async () =>
      api('/bootstrap/agent-install-command', {
        body: { ...agentForm, show_full_token: showFull }
      })
    );
    if (!data?.command) return;
    if (showFull) {
      setFullCommand(data.command);
      setShowFullCommand(true);
    } else {
      setMaskedCommand(data.command);
      setShowFullCommand(false);
      setFullCommand('');
    }
  }

  async function copyText(text) {
    if (!text) return;
    await navigator.clipboard.writeText(text);
    setAlert({ type: 'success', message: 'Copied to clipboard' });
  }

  async function createNetworkProfile(event) {
    event.preventDefault();
    await run('Network Profile creation', async () => {
      await api('/network-profiles', { body: networkForm });
      setNetworkForm({ ...networkForm, name: '', network_secret: '' });
      await refreshNetworkProfiles();
    });
  }

  async function applyNetworkProfile(profile) {
    const nodeId = networkApplyNode[profile.id] || nodes[0]?.id || '';
    if (!nodeId) {
      setAlert({ type: 'error', message: 'Select a target node first' });
      return;
    }
    await run('Network apply task', async () => {
      await api(`/network-profiles/${profile.id}/apply`, { body: { node_id: nodeId, profile_id: profile.id } });
      await refreshTasks();
    });
  }

  async function createEntry(event) {
    event.preventDefault();
    await run('Entry creation', async () => {
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
    await run('Entry apply task', async () => {
      await api(`/entries/${entry.id}/apply`, { body: { node_id: entry.node_id, entry_id: entry.id } });
      await refreshTasks();
    });
  }

  async function createForward(event) {
    event.preventDefault();
    await run('Forward creation', async () => {
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
    await run('Forward apply task', async () => {
      await api(`/forwards/${forward.id}/apply`, {
        body: { entry_node_id: forward.entry_node_id, forward_id: forward.id }
      });
      await refreshTasks();
    });
  }

  async function createPbrPolicy(event) {
    event.preventDefault();
    await run('PBR policy creation', async () => {
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
    await run('PBR apply task', async () => {
      await api(`/pbr-policies/${policy.id}/apply`, { body: { node_id: policy.node_id, pbr_policy_id: policy.id } });
      await refreshTasks();
    });
  }

  function renderLogin() {
    return (
      <div className="grid two">
        <Card title="Operator Token">
          <label>Token</label>
          <div className="inline">
            <input
              type={showToken ? 'text' : 'password'}
              value={tokenDraft}
              onChange={(event) => setTokenDraft(event.target.value)}
              placeholder="Paste operator token"
            />
            <button type="button" onClick={() => setShowToken(!showToken)}>
              {showToken ? 'Hide' : 'Show'}
            </button>
          </div>
          <div className="actions">
            <button onClick={saveToken}>Save Token</button>
            <button className="secondary" onClick={clearToken}>Clear Token</button>
            <button className="secondary" onClick={() => run('Connection test', refreshHealth)}>Test Connection</button>
          </div>
        </Card>
        <Card title="Controller Health">
          <KeyValues
            rows={[
              ['name', health?.name],
              ['version', health?.version],
              ['build commit', health?.build_commit],
              ['build time', health?.build_time]
            ]}
          />
        </Card>
      </div>
    );
  }

  function renderDashboard() {
    const recent = [...tasks].sort((a, b) => String(b.created_at).localeCompare(String(a.created_at))).slice(0, 5);
    return (
      <>
        <div className="grid four">
          <Stat title="Controller" value={health?.name || 'unknown'} note={health?.version || '-'} />
          <Stat title="Nodes" value={nodes.length} note={`online ${counts.nodeCounts.online} · stale ${counts.nodeCounts.stale} · offline ${counts.nodeCounts.offline}`} />
          <Stat title="Active Tasks" value={counts.taskCounts.pending + counts.taskCounts.running} note={`pending ${counts.taskCounts.pending} · running ${counts.taskCounts.running}`} />
          <Stat title="Completed Tasks" value={counts.taskCounts.succeeded + counts.taskCounts.failed} note={`succeeded ${counts.taskCounts.succeeded} · failed ${counts.taskCounts.failed}`} />
        </div>
        <Card title="Recent Tasks" action={<button onClick={() => run('Refresh', refreshAll)}>Refresh</button>}>
          <TaskTable tasks={recent} compact />
        </Card>
      </>
    );
  }

  function renderNodes() {
    return (
      <Card title="Nodes" action={<button onClick={() => run('Nodes refresh', refreshNodes)}>Refresh</button>}>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Name</th>
                <th>Role</th>
                <th>Status</th>
                <th>Host</th>
                <th>Public IP</th>
                <th>Private IP</th>
                <th>EasyTier</th>
                <th>Last Seen</th>
                <th>Capabilities</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {nodes.map((node) => (
                <tr key={node.id}>
                  <td>{node.name || node.id}</td>
                  <td>{node.role || '-'}</td>
                  <td><span className={statusClass(node.status)}>{node.status || 'unknown'}</span></td>
                  <td>{node.hostname || '-'}</td>
                  <td>{node.public_ip || '-'}</td>
                  <td>{node.private_ip || '-'}</td>
                  <td>{node.easytier_ip || '-'}<br /><small>{node.easytier_status || '-'}</small></td>
                  <td>{formatTime(node.last_seen_at)}</td>
                  <td><small>{Object.keys(node.capabilities || {}).filter((key) => node.capabilities[key]).join(', ') || '-'}</small></td>
                  <td>
                    <select onChange={(event) => event.target.value && createTask(node.id, event.target.value)} defaultValue="">
                      <option value="">Create task</option>
                      {readonlyActions.map((action) => <option key={action} value={action}>{action}</option>)}
                    </select>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Card>
    );
  }

  function renderAddAgent() {
    const visibleCommand = showFullCommand ? fullCommand : maskedCommand;
    return (
      <Card title="Add Agent">
        <div className="grid two form-grid">
          <Field label="Controller URL" value={agentForm.controller_url} onChange={(value) => setAgentForm({ ...agentForm, controller_url: value })} />
          <Field label="Node Name" value={agentForm.node_name} onChange={(value) => setAgentForm({ ...agentForm, node_name: value })} />
          <Select label="Role" value={agentForm.role} options={nodeRoles} onChange={(value) => setAgentForm({ ...agentForm, role: value })} />
          <div className="check-row">
            <label><input type="checkbox" checked={agentForm.enable_tasks} onChange={(event) => setAgentForm({ ...agentForm, enable_tasks: event.target.checked })} /> Enable tasks</label>
            <label><input type="checkbox" checked={agentForm.enable_write_actions} onChange={(event) => setAgentForm({ ...agentForm, enable_write_actions: event.target.checked })} /> Enable write actions</label>
          </div>
        </div>
        <div className="actions">
          <button onClick={() => generateAgentCommand(false)}>Generate Masked Command</button>
          <button className="warning" onClick={() => generateAgentCommand(true)}>Show Full Token Command</button>
          <button className="secondary" onClick={() => copyText(visibleCommand)}>Copy</button>
        </div>
        <pre>{visibleCommand || 'Generate an Agent install command to display it here.'}</pre>
      </Card>
    );
  }

  function renderNetworkProfiles() {
    return (
      <>
        <Card title="Create Network Profile">
          <form onSubmit={createNetworkProfile} className="grid five form-grid">
            <Field label="Name" value={networkForm.name} onChange={(value) => setNetworkForm({ ...networkForm, name: value })} required />
            <Field label="Network Name" value={networkForm.network_name} onChange={(value) => setNetworkForm({ ...networkForm, network_name: value })} />
            <Field label="Network Secret" value={networkForm.network_secret} onChange={(value) => setNetworkForm({ ...networkForm, network_secret: value })} />
            <Field label="CIDR" value={networkForm.cidr} onChange={(value) => setNetworkForm({ ...networkForm, cidr: value })} />
            <Select label="Protocol" value={networkForm.protocol_preference} options={['auto', 'tcp', 'udp', 'wg', 'ws', 'wss']} onChange={(value) => setNetworkForm({ ...networkForm, protocol_preference: value })} />
            <button type="submit">Create</button>
          </form>
        </Card>
        <Card title="Network Profiles" action={<button onClick={() => run('Network Profiles refresh', refreshNetworkProfiles)}>Refresh</button>}>
          <div className="cards">
            {networkProfiles.map((profile) => (
              <div className="mini-card" key={profile.id}>
                <h3>{profile.name}</h3>
                <p>{profile.network_name} · {profile.cidr} · {profile.protocol_preference}</p>
                <div className="inline">
                  <select value={networkApplyNode[profile.id] || ''} onChange={(event) => setNetworkApplyNode({ ...networkApplyNode, [profile.id]: event.target.value })}>
                    <option value="">Target node</option>
                    {nodes.map((node) => <option key={node.id} value={node.id}>{node.name || node.id}</option>)}
                  </select>
                  <button onClick={() => applyNetworkProfile(profile)}>Apply</button>
                </div>
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
        <Card title="Create Entry">
          <form onSubmit={createEntry} className="grid four form-grid">
            <Field label="Name" value={entryForm.name} onChange={(value) => setEntryForm({ ...entryForm, name: value })} required />
            <NodeSelect label="Node" value={entryForm.node_id} nodes={nodes} onChange={(value) => setEntryForm({ ...entryForm, node_id: value })} />
            <Field label="Listen IP" value={entryForm.listen_ip} onChange={(value) => setEntryForm({ ...entryForm, listen_ip: value })} />
            <Field label="Port Start" type="number" value={entryForm.listen_port_start} onChange={(value) => setEntryForm({ ...entryForm, listen_port_start: value })} required />
            <Field label="Port End" type="number" value={entryForm.listen_port_end} onChange={(value) => setEntryForm({ ...entryForm, listen_port_end: value })} required />
            <Select label="Protocol" value={entryForm.protocol} options={['tcp', 'udp', 'both']} onChange={(value) => setEntryForm({ ...entryForm, protocol: value })} />
            <Field label="Domain" value={entryForm.domain} onChange={(value) => setEntryForm({ ...entryForm, domain: value })} />
            <Field label="DDNS Provider" value={entryForm.ddns_provider} onChange={(value) => setEntryForm({ ...entryForm, ddns_provider: value })} />
            <label className="check"><input type="checkbox" checked={entryForm.ddns_enabled} onChange={(event) => setEntryForm({ ...entryForm, ddns_enabled: event.target.checked })} /> DDNS enabled</label>
            <button type="submit">Create</button>
          </form>
        </Card>
        <ListCard title="Entries" items={entries} refresh={() => run('Entries refresh', refreshEntries)} apply={applyEntry} fields={['name', 'node_id', 'listen_ip', 'listen_port_start', 'listen_port_end', 'protocol', 'domain', 'status']} />
      </>
    );
  }

  function renderForwards() {
    return (
      <>
        <Card title="Create Forward">
          <form onSubmit={createForward} className="grid four form-grid">
            <Field label="Name" value={forwardForm.name} onChange={(value) => setForwardForm({ ...forwardForm, name: value })} required />
            <Field label="Entry ID" value={forwardForm.entry_id} onChange={(value) => setForwardForm({ ...forwardForm, entry_id: value })} />
            <NodeSelect label="Entry Node" value={forwardForm.entry_node_id} nodes={nodes} onChange={(value) => setForwardForm({ ...forwardForm, entry_node_id: value })} />
            <Select label="Protocol" value={forwardForm.protocol} options={protocols} onChange={(value) => setForwardForm({ ...forwardForm, protocol: value })} />
            <Field label="Listen Port" type="number" value={forwardForm.listen_port} onChange={(value) => setForwardForm({ ...forwardForm, listen_port: value })} required />
            <Select label="Target Mode" value={forwardForm.target_mode} options={['local', 'overlay']} onChange={(value) => setForwardForm({ ...forwardForm, target_mode: value })} />
            <NodeSelect label="Target Node" value={forwardForm.target_node_id} nodes={nodes} onChange={(value) => setForwardForm({ ...forwardForm, target_node_id: value })} />
            <Field label="Target Host" value={forwardForm.target_host} onChange={(value) => setForwardForm({ ...forwardForm, target_host: value })} required />
            <Field label="Target Port" type="number" value={forwardForm.target_port} onChange={(value) => setForwardForm({ ...forwardForm, target_port: value })} required />
            <Field label="Remark" value={forwardForm.remark} onChange={(value) => setForwardForm({ ...forwardForm, remark: value })} />
            <label className="check"><input type="checkbox" checked={forwardForm.enabled} onChange={(event) => setForwardForm({ ...forwardForm, enabled: event.target.checked })} /> Enabled</label>
            <button type="submit">Create</button>
          </form>
        </Card>
        <ListCard title="Forwards" items={forwards} refresh={() => run('Forwards refresh', refreshForwards)} apply={applyForward} fields={['name', 'entry_node_id', 'protocol', 'listen_port', 'target_mode', 'target_host', 'target_port', 'enabled']} />
      </>
    );
  }

  function renderPbr() {
    return (
      <>
        <Card title="Create PBR Policy">
          <form onSubmit={createPbrPolicy} className="grid four form-grid">
            <NodeSelect label="Node" value={pbrForm.node_id} nodes={nodes} onChange={(value) => setPbrForm({ ...pbrForm, node_id: value })} />
            <Field label="Name" value={pbrForm.name} onChange={(value) => setPbrForm({ ...pbrForm, name: value })} required />
            <Field label="Match Source" value={pbrForm.match_source} onChange={(value) => setPbrForm({ ...pbrForm, match_source: value })} />
            <Field label="Match Destination" value={pbrForm.match_dst} onChange={(value) => setPbrForm({ ...pbrForm, match_dst: value })} />
            <Field label="Protocol" value={pbrForm.match_protocol} onChange={(value) => setPbrForm({ ...pbrForm, match_protocol: value })} />
            <Field label="Mark" value={pbrForm.match_mark} onChange={(value) => setPbrForm({ ...pbrForm, match_mark: value })} />
            <Field label="Table ID" type="number" value={pbrForm.table_id} onChange={(value) => setPbrForm({ ...pbrForm, table_id: value })} />
            <Field label="Gateway" value={pbrForm.gateway} onChange={(value) => setPbrForm({ ...pbrForm, gateway: value })} />
            <Field label="Out Interface" value={pbrForm.out_interface} onChange={(value) => setPbrForm({ ...pbrForm, out_interface: value })} />
            <Field label="Priority" type="number" value={pbrForm.priority} onChange={(value) => setPbrForm({ ...pbrForm, priority: value })} />
            <label className="check"><input type="checkbox" checked={pbrForm.enabled} onChange={(event) => setPbrForm({ ...pbrForm, enabled: event.target.checked })} /> Enabled</label>
            <button type="submit">Create</button>
          </form>
        </Card>
        <ListCard title="PBR Policies" items={pbrPolicies} refresh={() => run('PBR refresh', refreshPbrPolicies)} apply={applyPbrPolicy} fields={['name', 'node_id', 'match_source', 'match_dst', 'table_id', 'gateway', 'out_interface', 'priority', 'enabled']} />
      </>
    );
  }

  function renderTasks() {
    const visibleTasks = taskFilter === 'all' ? tasks : tasks.filter((task) => task.status === taskFilter);
    return (
      <Card
        title="Tasks"
        action={
          <div className="inline">
            <select value={taskFilter} onChange={(event) => setTaskFilter(event.target.value)}>
              {taskStatuses.map((status) => <option key={status} value={status}>{status}</option>)}
            </select>
            <button onClick={() => run('Tasks refresh', refreshTasks)}>Refresh</button>
          </div>
        }
      >
        <TaskTable tasks={visibleTasks} />
      </Card>
    );
  }

  function renderSettings() {
    return (
      <div className="grid two">
        <Card title="API Base">
          <label>Controller URL</label>
          <div className="inline">
            <input value={apiBaseDraft} onChange={(event) => setApiBaseDraft(event.target.value)} placeholder="Same origin by default" />
            <button onClick={saveApiBase}>Save</button>
          </div>
          <p className="muted">Current: {apiBase || 'same origin'}</p>
          <p className="muted">Token set: {token ? 'yes' : 'no'}</p>
        </Card>
        <Card title="Default Paths">
          <KeyValues
            rows={[
              ['Agent config', '/etc/edge-tunnel/agent'],
              ['Controller data', '/var/lib/edge-tunnel/controller'],
              ['Controller service', 'edge-tunnel-controller.service'],
              ['Agent service', 'edge-tunnel-agent.service'],
              ['EasyTier service', 'edge-tunnel-easytier.service'],
              ['DDNS profiles', `${ddnsProfiles.length} loaded`]
            ]}
          />
        </Card>
      </div>
    );
  }

  const page = {
    login: renderLogin,
    dashboard: renderDashboard,
    nodes: renderNodes,
    'add-agent': renderAddAgent,
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
          <p>Controller, Agent, Entry, Forward, Network Profile, PBR, DDNS and Task management.</p>
        </div>
        <button onClick={() => run('Refresh', refreshAll)} disabled={loading}>{loading ? 'Working...' : 'Refresh All'}</button>
      </header>
      <nav>
        {tabs.map(([id, label]) => (
          <button key={id} className={activeTab === id ? 'active' : ''} onClick={() => setActiveTab(id)}>
            {label}
          </button>
        ))}
      </nav>
      {alert && <div className={`alert ${alert.type}`}>{alert.message}</div>}
      <section>{page?.()}</section>
    </main>
  );
}

function Card({ title, action, children }) {
  return (
    <article className="card">
      <div className="card-head">
        <h2>{title}</h2>
        {action}
      </div>
      {children}
    </article>
  );
}

function Stat({ title, value, note }) {
  return (
    <div className="stat">
      <span>{title}</span>
      <strong>{value}</strong>
      <small>{note}</small>
    </div>
  );
}

function Field({ label, value, onChange, type = 'text', required = false }) {
  return (
    <label>
      {label}
      <input type={type} value={value} required={required} onChange={(event) => onChange(event.target.value)} />
    </label>
  );
}

function Select({ label, value, options, onChange }) {
  return (
    <label>
      {label}
      <select value={value} onChange={(event) => onChange(event.target.value)}>
        {options.map((option) => <option key={option} value={option}>{option}</option>)}
      </select>
    </label>
  );
}

function NodeSelect({ label, value, nodes, onChange }) {
  return (
    <label>
      {label}
      <select value={value} onChange={(event) => onChange(event.target.value)}>
        <option value="">Select node</option>
        {nodes.map((node) => <option key={node.id} value={node.id}>{node.name || node.id}</option>)}
      </select>
    </label>
  );
}

function KeyValues({ rows }) {
  return (
    <dl className="kv">
      {rows.map(([key, value]) => (
        <React.Fragment key={key}>
          <dt>{key}</dt>
          <dd>{value || '-'}</dd>
        </React.Fragment>
      ))}
    </dl>
  );
}

function ListCard({ title, items, fields, refresh, apply }) {
  return (
    <Card title={title} action={<button onClick={refresh}>Refresh</button>}>
      <div className="table-wrap">
        <table>
          <thead>
            <tr>
              {fields.map((field) => <th key={field}>{field}</th>)}
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            {items.map((item) => (
              <tr key={item.id}>
                {fields.map((field) => <td key={field}>{String(item[field] ?? '-')}</td>)}
                <td><button onClick={() => apply(item)}>Apply</button></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Card>
  );
}

function TaskTable({ tasks, compact = false }) {
  if (!tasks.length) return <p className="muted">No tasks yet.</p>;
  return (
    <div className="table-wrap">
      <table>
        <thead>
          <tr>
            <th>ID</th>
            <th>Node</th>
            <th>Action</th>
            <th>Status</th>
            <th>Created</th>
            {!compact && <th>Started</th>}
            {!compact && <th>Finished</th>}
            {!compact && <th>Output</th>}
          </tr>
        </thead>
        <tbody>
          {tasks.map((task) => (
            <tr key={task.id}>
              <td><code>{task.id}</code></td>
              <td>{task.node_id || '-'}</td>
              <td>{task.action}</td>
              <td><span className={statusClass(task.status)}>{task.status}</span></td>
              <td>{formatTime(task.created_at)}</td>
              {!compact && <td>{formatTime(task.started_at)}</td>}
              {!compact && <td>{formatTime(task.finished_at)}</td>}
              {!compact && <td><pre className="small">{summarize(task.error || task.stdout || task.stderr || task.result)}</pre></td>}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

createRoot(document.getElementById('root')).render(<App />);
