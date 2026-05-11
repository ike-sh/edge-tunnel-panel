import React, { useEffect, useMemo, useState } from 'react';
import { createRoot } from 'react-dom/client';
import './styles.css';

const API_BASE = import.meta.env.VITE_API_BASE || '';
const tabs = ['Dashboard', 'Nodes', 'Entries', 'Forwards', 'Events'];

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
  const [active, setActive] = useState('Dashboard');
  const data = usePanelData();
  const counts = useMemo(() => statusCounts(data.nodes), [data.nodes]);
  return (
    <div className="app">
      <aside className="sidebar">
        <div className="brand">
          <div className="brand-mark">LQ</div>
          <div>
            <h1>Leikwan Panel</h1>
            <p>2.0-alpha readonly</p>
          </div>
        </div>
        <nav>
          {tabs.map((tab) => (
            <button key={tab} className={active === tab ? 'active' : ''} onClick={() => setActive(tab)}>
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
        {active === 'Dashboard' && <Dashboard data={data} counts={counts} />}
        {active === 'Nodes' && <Nodes nodes={data.nodes} />}
        {active === 'Entries' && <Entries entries={data.entries} />}
        {active === 'Forwards' && <Forwards forwards={data.forwards} />}
        {active === 'Events' && <Events events={data.events} />}
      </main>
    </div>
  );
}

function Dashboard({ data, counts }) {
  return (
    <>
      <section className="metrics">
        <Metric label="Online" value={counts.online || 0} />
        <Metric label="Offline" value={counts.offline || 0} />
        <Metric label="Degraded" value={counts.degraded || 0} />
        <Metric label="Entries" value={data.entries.length} />
        <Metric label="Forwards" value={data.forwards.length} />
      </section>
      <section>
        <h3>Recent Events</h3>
        <Events events={data.events.slice(0, 10)} compact />
      </section>
    </>
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

function Nodes({ nodes }) {
  if (!nodes.length) return <Empty text="No nodes reported yet" />;
  return (
    <Table headers={['Name', 'Role', 'Public IP', 'EasyTier IP', 'Core', 'Agent', 'Status', 'Last seen']}>
      {nodes.map((n) => (
        <tr key={n.node_id}>
          <td>{n.node_name || n.node_id}</td>
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

function Entries({ entries }) {
  if (!entries.length) return <Empty text="No entries reported yet" />;
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
  if (!forwards.length) return <Empty text="No forwards reported yet" />;
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
