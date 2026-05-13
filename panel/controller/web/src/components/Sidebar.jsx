export default function Sidebar({ tabs, activeTab, onTabChange }) {
  return (
    <aside className="sidebar">
      <div className="brand">
        <div className="brand-mark">ET</div>
        <div>
          <strong>Edge Tunnel</strong>
          <span>Panel</span>
        </div>
      </div>
      <nav className="side-nav">
        {tabs.map(([key, label]) => (
          <button key={key} className={activeTab === key ? 'active' : ''} onClick={() => onTabChange(key)}>
            <span className="nav-dot" />
            {label}
          </button>
        ))}
      </nav>
    </aside>
  );
}
