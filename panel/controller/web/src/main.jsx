import React, { useEffect, useMemo, useState } from 'react';
import { createRoot } from 'react-dom/client';
import './styles.css';

const API_BASE = import.meta.env.VITE_API_BASE || '';
const tabs = ['Dashboard', 'Topology', 'Nodes', 'Entries', 'Forwards', 'Events', 'Plans', 'Bootstrap'];
const PANEL_VERSION = '2.0.0-beta.2';

async function getJSON(path) {
  const res = await fetch(`${API_BASE}${path}`);
  if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
  return res.json();
}

function usePanelData() {
  const [data, setData] = useState({ nodes: [], entries: [], forwards: [], events: [], loading: true, error: '' });
  useEffect(() => {
    let alive = true;
    async function load() {
      try {
        const [nodes, entries, forwards, events] = await Promise.all([
          getJSON('/api/v1/nodes'),
          getJSON('/api/v1/entries'),
          getJSON('/api/v1/forwards'),
          getJSON('/api/v1/events')
        ]);
        if (alive) setData({ nodes, entries, forwards, events, loading: false, error: '' });
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
  const data = usePanelData();
  const counts = useMemo(() => statusCounts(data.nodes), [data.nodes]);
  const active = path.startsWith('/nodes/') ? 'Node Detail' : pathToTab(path);
  function navigate(nextPath) {
    window.history.pushState({}, '', nextPath);
    setPath(nextPath);
  }
  useEffect(() => {
    const onPop = () => setPath(window.location.pathname);
    window.addEventListener('popstate', onPop);
    return () => window.removeEventListener('popstate', onPop);
  }, []);
  return (
    <div className="app">
      <aside className="sidebar">
        <div className="brand">
          <div className="brand-mark">LQ</div>
          <div>
            <h1>Leikwan Panel</h1>
            <p>{PANEL_VERSION} readonly</p>
          </div>
        </div>
        <nav>
          {tabs.map((tab) => (
            <button key={tab} className={active === tab ? 'active' : ''} onClick={() => navigate(tabToPath(tab))}>
              {tab}
            </button>
          ))}
        </nav>
        <button className="disabled" disabled>Coming in 2.1</button>
      </aside>
      <main>
        <header>
          <div>
            <p className="eyebrow">Read-only operations view</p>
            <h2>{active}</h2>
          </div>
          <span className="status-pill">{data.error ? 'API error' : data.loading ? 'Loading' : 'Live'}</span>
        </header>
        {data.error && <div className="banner">API request failed: {data.error}</div>}
        <div className="notice">beta.2 still requires manual SSH execution. Agents will not execute changes.</div>
        {active === 'Dashboard' && <Dashboard data={data} counts={counts} onNavigate={navigate} />}
        {active === 'Topology' && <Topology />}
        {active === 'Nodes' && <Nodes nodes={data.nodes} onOpen={(id) => navigate(`/nodes/${encodeURIComponent(id)}`)} />}
        {active === 'Node Detail' && <NodeDetail nodeId={decodeURIComponent(path.split('/').pop() || '')} entries={data.entries} forwards={data.forwards} />}
        {active === 'Entries' && <Entries entries={data.entries} />}
        {active === 'Forwards' && <Forwards forwards={data.forwards} />}
        {active === 'Events' && <Events events={data.events} />}
        {active === 'Plans' && <Plans nodes={data.nodes} />}
        {active === 'Bootstrap' && <Bootstrap />}
      </main>
    </div>
  );
}

function pathToTab(path) {
  if (path === '/nodes') return 'Nodes';
  if (path === '/topology') return 'Topology';
  if (path === '/entries') return 'Entries';
  if (path === '/forwards') return 'Forwards';
  if (path === '/events') return 'Events';
  if (path === '/plans') return 'Plans';
  if (path === '/bootstrap') return 'Bootstrap';
  return 'Dashboard';
}

function tabToPath(tab) {
  if (tab === 'Dashboard') return '/';
  return `/${tab.toLowerCase()}`;
}

function Dashboard({ data, counts, onNavigate }) {
  return (
    <>
      <section className="metrics">
        <Metric label="Online" value={counts.online || 0} />
        <Metric label="Offline" value={counts.offline || 0} />
        <Metric label="Degraded" value={counts.degraded || 0} />
        <Metric label="Entries" value={data.entries.length} />
        <Metric label="Forwards" value={data.forwards.length} />
      </section>
      <section className="action-row">
        <button className="primary-action" onClick={() => onNavigate('/topology')}>View Topology</button>
        <button className="disabled inline" disabled>Coming in 2.1</button>
      </section>
      <section>
        <h3>Recent Status Changes</h3>
        <Events events={data.events.filter((e) => (e.message || '').includes('status changed')).slice(0, 10)} compact />
      </section>
      <section className="section-gap">
        <h3>Recent Events</h3>
        <Events events={data.events.slice(0, 10)} compact />
      </section>
    </>
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
  if (topology.loading) return <Empty text="Loading topology" />;
  if (topology.error) return <div className="banner">Topology failed: {topology.error}</div>;
  const groups = {
    entry: topology.nodes.filter((n) => n.role === 'entry'),
    relay: topology.nodes.filter((n) => n.role === 'relay' || n.role === 'mixed'),
    backend: topology.nodes.filter((n) => n.role === 'backend' || n.role === 'unknown' || !['entry', 'relay', 'mixed'].includes(n.role))
  };
  return (
    <div className="topology-page">
      <section className="metrics">
        <Metric label="Nodes" value={topology.nodes.length} />
        <Metric label="Entries" value={topology.entries.length} />
        <Metric label="Forwards" value={topology.forwards.length} />
        <Metric label="Links" value={topology.links.length} />
      </section>
      <div className="topology-grid">
        <TopologyColumn title="Entry" nodes={groups.entry} />
        <TopologyColumn title="Relay" nodes={groups.relay} />
        <TopologyColumn title="Backend / Unknown" nodes={groups.backend} />
      </div>
      <section>
        <h3>Links</h3>
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
        ) : <Empty text="No links inferred yet" />}
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
          <span>{node.role}</span>
          <span>{node.public_ip || node.lan_ip || '-'}</span>
          <span className={`tag ${node.status}`}>{node.status}</span>
        </div>
      )) : <Empty text={`No ${title.toLowerCase()} nodes`} />}
    </section>
  );
}

function Bootstrap() {
  const [form, setForm] = useState({ controller_url: window.location.origin, node_name: 'leikwan-node', role: 'relay' });
  const [command, setCommand] = useState({ command: '', note: '', loading: true, error: '' });
  useEffect(() => {
    let alive = true;
    const q = new URLSearchParams(form).toString();
    getJSON(`/api/v1/bootstrap/agent-command?${q}`)
      .then((data) => alive && setCommand({ ...data, loading: false, error: '' }))
      .catch((err) => alive && setCommand((prev) => ({ ...prev, loading: false, error: err.message })));
    return () => { alive = false; };
  }, [form]);
  function update(key, value) {
    setForm((prev) => ({ ...prev, [key]: value }));
  }
  return (
    <div className="bootstrap-page">
      <section className="panel">
        <h3>Add Agent</h3>
        <p className="muted">The command template is redacted. Replace REDACTED on the server or write the config through a local secure channel.</p>
        <div className="form-grid">
          <label>Controller URL<input value={form.controller_url} onChange={(e) => update('controller_url', e.target.value)} /></label>
          <label>Node name<input value={form.node_name} onChange={(e) => update('node_name', e.target.value)} /></label>
          <label>Role<select value={form.role} onChange={(e) => update('role', e.target.value)}>
            {['relay', 'entry', 'backend', 'mixed', 'unknown'].map((role) => <option key={role} value={role}>{role}</option>)}
          </select></label>
        </div>
      </section>
      <section className="panel">
        <h3>Install Command</h3>
        {command.error && <div className="banner">Command failed: {command.error}</div>}
        <pre className="command-box">{command.loading ? 'Loading...' : command.command}</pre>
        <p className="muted">{command.note}</p>
        <button className="disabled inline" disabled>Coming in 2.1</button>
      </section>
    </div>
  );
}

function Plans({ nodes }) {
  const [plans, setPlans] = useState([]);
  const [selected, setSelected] = useState(null);
  const [form, setForm] = useState({
    type: 'create_forward',
    title: 'Create forward plan',
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
      const res = await fetch(`${API_BASE}/api/v1/plans`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          type: form.type,
          title: form.title,
          target_node_id: form.target_node_id,
          payload_json: payload
        })
      });
      if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
      const plan = await res.json();
      setSelected(plan);
      await loadPlans();
    } catch (err) {
      setError(err.message);
    }
  }
  return (
    <div className="plans-page">
      {error && <div className="banner">Plans request failed: {error}</div>}
      <section className="panel">
        <h3>Create Plan</h3>
        <p className="muted">beta.2 creates a manual execution guide only. You still SSH to the target node and run commands yourself.</p>
        <form className="form-grid plan-form" onSubmit={createPlan}>
          <label>Type<select value={form.type} onChange={(e) => update('type', e.target.value)}>
            {['create_entry', 'create_forward', 'switch_entry', 'ddns_check'].map((type) => <option key={type} value={type}>{type}</option>)}
          </select></label>
          <label>Title<input value={form.title} onChange={(e) => update('title', e.target.value)} /></label>
          <label>Target node<select value={form.target_node_id} onChange={(e) => update('target_node_id', e.target.value)}>
            <option value="">Select node</option>
            {nodes.map((node) => <option key={node.node_id} value={node.node_id}>{node.node_name || node.node_id}</option>)}
          </select></label>
          <label>Entry<input value={form.entry} onChange={(e) => update('entry', e.target.value)} /></label>
          <label>Relay<input value={form.relay} onChange={(e) => update('relay', e.target.value)} /></label>
          <label>Target host<input value={form.target_host} onChange={(e) => update('target_host', e.target.value)} /></label>
          <label>Target port<input value={form.target_port} onChange={(e) => update('target_port', e.target.value)} /></label>
          <label>Protocol<input value={form.protocol} onChange={(e) => update('protocol', e.target.value)} /></label>
          <button className="primary-action" type="submit">Create draft</button>
        </form>
      </section>
      <section>
        <h3>Plans</h3>
        <PlansList plans={plans} onSelect={setSelected} />
      </section>
      {selected && <PlanDetail plan={selected} onUpdate={(plan) => { setSelected(plan); loadPlans(); }} />}
    </div>
  );
}

function PlansList({ plans, onSelect }) {
  if (!plans.length) return <Empty text="No plans yet" />;
  return (
    <Table headers={['Title', 'Plan status', 'Execution', 'Type', 'Target node', 'Updated']}>
      {plans.map((plan) => (
        <tr key={plan.id}>
          <td><button className="link-button" onClick={() => onSelect(plan)}>{plan.title}</button></td>
          <td><span className={`tag ${plan.status}`}>{plan.status}</span></td>
          <td><span className={`tag ${plan.execution_status}`}>{plan.execution_status || 'not_run'}</span></td>
          <td>{plan.type}</td>
          <td>{plan.target_node_id || '-'}</td>
          <td>{plan.updated_at || plan.created_at}</td>
        </tr>
      ))}
    </Table>
  );
}

function PlanDetail({ plan, onUpdate }) {
  const [copyText, setCopyText] = useState('');
  const [manualNote, setManualNote] = useState(plan.execution_note || '');
  const [checked, setChecked] = useState({});
  const markdownText = plan.markdown || 'Generate the plan to create the manual execution guide.';
  useEffect(() => {
    setManualNote(plan.execution_note || '');
    setChecked({});
    setCopyText('');
  }, [plan.id]);
  async function generate() {
    const res = await fetch(`${API_BASE}/api/v1/plans/${plan.id}/generate`, { method: 'POST' });
    if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
    onUpdate(await res.json());
  }
  async function regenerate() {
    const res = await fetch(`${API_BASE}/api/v1/plans/${plan.id}/regenerate`, { method: 'POST' });
    if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
    onUpdate(await res.json());
  }
  async function archive() {
    const res = await fetch(`${API_BASE}/api/v1/plans/${plan.id}/archive`, { method: 'POST' });
    if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
    onUpdate(await res.json());
  }
  async function mark(status) {
    const res = await fetch(`${API_BASE}/api/v1/plans/${plan.id}/mark`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        execution_status: status,
        execution_note: manualNote,
        manual_result: JSON.stringify({ checked })
      })
    });
    if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
    onUpdate(await res.json());
  }
  async function copyCommands() {
    const text = commandsFromGroups(plan).join('\n');
    try {
      await navigator.clipboard.writeText(text);
      setCopyText('Copied');
    } catch {
      setCopyText('Copy failed');
    }
  }
  async function copyMarkdown() {
    try {
      await navigator.clipboard.writeText(markdownText);
      setCopyText('Markdown copied');
    } catch {
      setCopyText('Copy failed');
    }
  }
  function toggleCheck(idx) {
    setChecked((prev) => ({ ...prev, [idx]: !prev[idx] }));
  }
  return (
    <section className="panel">
      <h3>Plan Detail</h3>
      <dl className="kv">
        <dt>Title</dt><dd>{plan.title}</dd>
        <dt>Type</dt><dd>{plan.type}</dd>
        <dt>Status</dt><dd>{plan.status}</dd>
        <dt>Execution</dt><dd><span className={`tag ${plan.execution_status}`}>{plan.execution_status || 'not_run'}</span></dd>
        <dt>Target</dt><dd>{plan.target_node_id || '-'}</dd>
      </dl>
      <h4>Payload</h4>
      <pre className="command-box">{JSON.stringify(plan.payload_json || {}, null, 2)}</pre>
      <h4>Warnings</h4>
      <List items={plan.warnings || []} empty="No warnings generated yet" />
      <h4>Checklist</h4>
      <Checklist items={plan.checklist || []} checked={checked} onToggle={toggleCheck} />
      <h4>Command Groups</h4>
      <CommandGroups groups={plan.command_groups || []} fallback={plan.generated_commands || []} />
      <h4>Markdown Preview</h4>
      <pre className="command-box markdown-preview">{markdownText}</pre>
      <h4>Manual Result</h4>
      <textarea className="note-box" value={manualNote} onChange={(e) => setManualNote(e.target.value)} placeholder="Optional note after manual SSH execution" />
      <div className="action-row">
        <button className="primary-action" onClick={generate}>Generate guide</button>
        <button className="primary-action" onClick={regenerate}>Regenerate</button>
        <button className="primary-action" onClick={copyCommands} disabled={!commandsFromGroups(plan).length}>Copy commands</button>
        <button className="primary-action" onClick={copyMarkdown} disabled={!plan.markdown}>Copy markdown</button>
        <button className="link-button" onClick={() => mark('running_manually')}>Mark running</button>
        <button className="link-button" onClick={() => mark('succeeded')}>Mark succeeded</button>
        <button className="link-button" onClick={() => mark('failed')}>Mark failed</button>
        <button className="link-button" onClick={() => mark('rolled_back')}>Mark rolled back</button>
        <button className="disabled inline" disabled>Coming in 2.1</button>
        <button className="link-button" onClick={archive}>Archive</button>
        {copyText && <span className="muted">{copyText}</span>}
      </div>
    </section>
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
  if (!items.length) return <Empty text="Generate the plan to create a checklist" />;
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
            <h5>{group.node_name || group.node_id || 'target node'} <span className={`tag ${group.role}`}>{group.role || 'unknown'}</span></h5>
            <pre className="command-box">{(group.commands || []).join('\n')}</pre>
          </div>
        ))}
      </div>
    );
  }
  return <pre className="command-box">{fallback.join('\n') || 'Generate the plan to create manual commands.'}</pre>;
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
  if (!nodes.length) return <Empty text="No nodes reported yet" />;
  return (
    <Table headers={['Name', 'Role', 'Public IP', 'EasyTier IP', 'Core', 'Agent', 'Status', 'Last seen']}>
      {nodes.map((n) => (
        <tr key={n.node_id}>
          <td><button className="link-button" onClick={() => onOpen(n.node_id)}>{n.node_name || n.node_id}</button></td>
          <td>{n.role}</td>
          <td>{n.public_ip || '-'}</td>
          <td>{n.easytier_ip || '-'}</td>
          <td>{n.core_version || '-'}</td>
          <td>{n.agent_version || '-'}</td>
          <td><span className={`tag ${n.status}`}>{n.status}</span></td>
          <td>{n.last_seen || '-'}</td>
        </tr>
      ))}
    </Table>
  );
}

function NodeDetail({ nodeId, entries, forwards }) {
  const [detail, setDetail] = useState({ node: null, reports: [], events: [], raw: null, loading: true, error: '' });
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
  if (detail.loading) return <Empty text="Loading node detail" />;
  if (detail.error) return <div className="banner">Node detail failed: {detail.error}</div>;
  const node = detail.node;
  const nodeEntries = entries.filter((e) => e.node_id === nodeId);
  const nodeForwards = forwards.filter((f) => f.node_id === nodeId);
  const doctor = objectOrEmpty(node.doctor);
  const warnings = arrayOrEmpty(doctor.warnings);
  const suggestions = arrayOrEmpty(doctor.suggestions);
  return (
    <div className="detail">
      <section className="panel">
        <h3>Basic Information</h3>
        <dl className="kv">
          <dt>Name</dt><dd>{node.node_name || node.node_id}</dd>
          <dt>Role</dt><dd>{node.role}</dd>
          <dt>Status</dt><dd><span className={`tag ${node.status}`}>{node.status}</span></dd>
          <dt>Public IP</dt><dd>{node.public_ip || '-'}</dd>
          <dt>LAN IP</dt><dd>{node.lan_ip || '-'}</dd>
          <dt>EasyTier IP</dt><dd>{node.easytier_ip || '-'}</dd>
          <dt>Core</dt><dd>{node.core_version || '-'}</dd>
          <dt>Agent</dt><dd>{node.agent_version || '-'}</dd>
          <dt>Last seen</dt><dd>{node.last_seen || '-'}</dd>
        </dl>
      </section>
      <section className="panel">
        <h3>Services</h3>
        <KeyValue data={node.services || {}} />
      </section>
      <section className="panel">
        <h3>Doctor</h3>
        <p>Overall: {doctor.overall || '-'}</p>
        <List title="Warnings" items={warnings} />
        <List title="Suggestions" items={suggestions} />
      </section>
      <section className="panel">
        <h3>Recent Errors</h3>
        <List items={node.recent_errors || []} empty="No recent errors" />
      </section>
      <section>
        <h3>Entries</h3>
        <Entries entries={nodeEntries} />
      </section>
      <section>
        <h3>Forwards</h3>
        <Forwards forwards={nodeForwards} />
      </section>
      <section>
        <h3>Recent Reports</h3>
        <Reports reports={detail.reports.slice(0, 20)} />
      </section>
      <section>
        <h3>Node Events</h3>
        <Events events={detail.events.slice(0, 20)} />
      </section>
      <details className="raw">
        <summary>Redacted raw_json</summary>
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
  if (!entries.length) return <Empty text="No service data reported yet" />;
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

function List({ title, items, empty = 'None' }) {
  return (
    <div className="list-block">
      {title && <strong>{title}</strong>}
      {items.length ? <ul>{items.map((item, i) => <li key={`${item}-${i}`}>{String(item)}</li>)}</ul> : <p>{empty}</p>}
    </div>
  );
}

function Reports({ reports }) {
  if (!reports.length) return <Empty text="No reports yet" />;
  return (
    <Table headers={['Time', 'Status', 'Health', 'Interval', 'Errors']}>
      {reports.map((r) => (
        <tr key={r.id}>
          <td>{r.created_at}</td>
          <td><span className={`tag ${r.status}`}>{r.status}</span></td>
          <td>{r.health_score}</td>
          <td>{r.interval_seconds}s</td>
          <td>{(r.recent_errors || []).join('; ') || '-'}</td>
        </tr>
      ))}
    </Table>
  );
}

function Entries({ entries }) {
  if (!entries.length) return <Empty text="No entries reported yet. Agents will populate this after lq status reports structured entry data." />;
  return (
    <Table headers={['Node', 'Name', 'Port', 'Protocol', 'Public host', 'Status']}>
      {entries.map((e) => (
        <tr key={`${e.node_id}-${e.name}-${e.listen_port}`}>
          <td>{e.node_id}</td>
          <td>{e.name}</td>
          <td>{e.listen_port}</td>
          <td>{e.protocol}</td>
          <td>{e.public_host || '-'}</td>
          <td>{e.status}</td>
        </tr>
      ))}
    </Table>
  );
}

function Forwards({ forwards }) {
  if (!forwards.length) return <Empty text="No forwards reported yet. Agents will populate this after lq status reports structured forward data." />;
  return (
    <Table headers={['Node', 'Name', 'Entry', 'Target', 'Protocol', 'Status']}>
      {forwards.map((f) => (
        <tr key={`${f.node_id}-${f.name}-${f.target_port}`}>
          <td>{f.node_id}</td>
          <td>{f.name}</td>
          <td>{f.entry_name || '-'}</td>
          <td>{f.target_host}:{f.target_port}</td>
          <td>{f.protocol}</td>
          <td>{f.status}</td>
        </tr>
      ))}
    </Table>
  );
}

function Events({ events, compact = false }) {
  if (!events.length) return <Empty text="No events yet" />;
  return (
    <Table headers={compact ? ['Level', 'Message', 'Time'] : ['Node', 'Level', 'Message', 'Time']}>
      {events.map((e) => (
        <tr key={e.id}>
          {!compact && <td>{e.node_id || '-'}</td>}
          <td><span className={`tag ${e.level}`}>{e.level}</span></td>
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
