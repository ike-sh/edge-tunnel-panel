import { NavIcon } from './ui/icons.jsx';
import ThemeToggle from './ui/ThemeToggle.jsx';

export default function Sidebar({ tabs, activeTab, onTabChange, theme, onThemeToggle }) {
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
            <NavIcon name={key} />
            {label}
          </button>
        ))}
      </nav>
      <div className="sidebar-footer">
        <ThemeToggle theme={theme} onToggle={onThemeToggle} />
      </div>
    </aside>
  );
}
