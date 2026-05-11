import React, { useEffect, useMemo, useState } from 'react';
import { createRoot } from 'react-dom/client';
import './styles.css';

const API_BASE = import.meta.env.VITE_API_BASE || '';
const tabs = ['Dashboard', 'Topology', 'Nodes', 'Entries', 'Forwards', 'Events', 'Bootstrap'];
const PANEL_VERSION = '2.0.0-alpha.3';

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
        {active === 'Dashboard' && <Dashboard data={data} counts={counts} onNavigate={navigate} />}
        {active === 'Topology' && <Topology />}
        {active === 'Nodes' && <Nodes nodes={data.nodes} onOpen={(id) => navigate(`/nodes/${encodeURIComponent(id)}`)} />}
        {active === 'Node Detail' && <NodeDetail nodeId={decodeURIComponent(path.split('/').pop() || '')} entries={data.entries} forwards={data.forwards} />}
        {active === 'Entries' && <Entries entries={data.entries} />}
        {active === 'Forwards' && <Forwards forwards={data.forwards} />}
        {active === 'Events' && <Events events={data.events} />}
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
