import { NavLink } from 'react-router-dom';
import { NavIcon } from './ui/icons.jsx';
import ThemeToggle from './ui/ThemeToggle.jsx';
import { routes } from '../utils/routes.js';
import { DEFAULT_VERSION } from '../utils/format.js';

export default function Sidebar({ theme, onThemeToggle, mobileOpen, onCloseMobile }) {
  return (
    <>
      {mobileOpen && <div className="sidebar-overlay" onClick={onCloseMobile} aria-hidden="true" />}
      <aside className={`sidebar ${mobileOpen ? 'mobile-open' : ''}`}>
        <div className="brand">
          <div className="brand-mark">ET</div>
          <div>
            <strong>Edge Tunnel</strong>
            <span>Panel · {DEFAULT_VERSION}</span>
          </div>
        </div>
        <nav className="side-nav">
          {routes.map(({ path, key, label }) => (
            <NavLink
              key={path}
              to={path}
              end={path !== '/profiles'}
              className={({ isActive }) => (isActive ? 'active' : '')}
              onClick={onCloseMobile}
            >
              <NavIcon name={key} />
              {label}
            </NavLink>
          ))}
        </nav>
        <div className="sidebar-footer">
          <ThemeToggle theme={theme} onToggle={onThemeToggle} />
        </div>
      </aside>
    </>
  );
}
