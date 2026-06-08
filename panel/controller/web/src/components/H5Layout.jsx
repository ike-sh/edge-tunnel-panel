import { useEffect } from 'react';
import { NavLink, useLocation } from 'react-router-dom';
import { NavIcon } from './ui/icons.jsx';
import ThemeToggle from './ui/ThemeToggle.jsx';
import { useApp } from '../context/AppContext.jsx';
import { h5Tabs, routeLabel } from '../utils/routes.js';
import { DEFAULT_VERSION } from '../utils/format.js';

function tabActive(pathname, path) {
  if (path === '/profiles') return pathname === '/profiles' || pathname.startsWith('/profiles/');
  return pathname === path;
}

export default function H5Layout({ children }) {
  const location = useLocation();
  const {
    theme,
    toggleTheme,
    health,
    loading,
    refreshAll,
    streamLive,
  } = useApp();

  useEffect(() => {
    window.scrollTo({ top: 0, left: 0, behavior: 'auto' });
  }, [location.pathname]);

  return (
    <div className="h5-shell">
      <header className="h5-header">
        <div className="h5-header-brand">
          <div className="brand-mark sm">ET</div>
          <div>
            <strong>{routeLabel(location.pathname)}</strong>
            <span className="h5-header-sub">{DEFAULT_VERSION}{streamLive ? ' · 实时' : ''}</span>
          </div>
        </div>
        <div className="h5-header-actions">
          <ThemeToggle theme={theme} onToggle={toggleTheme} />
          <button
            type="button"
            className="secondary small h5-icon-btn"
            onClick={() => refreshAll()}
            disabled={loading}
            aria-label="刷新"
            title="刷新"
          >
            ↻
          </button>
        </div>
      </header>

      {health && !health.strict_auth && location.pathname !== '/settings' && (
        <div className="alert info h5-banner">测试模式 · 未启用 Token 鉴权</div>
      )}

      <main className="h5-main">{children}</main>

      <div className="h5-tabbar-spacer" aria-hidden="true" />

      <nav className="h5-tabbar" aria-label="主导航">
        {h5Tabs.map(({ path, key, label }) => {
          const active = tabActive(location.pathname, path);
          return (
            <NavLink
              key={path}
              to={path}
              end={path !== '/profiles'}
              className={`h5-tab ${active ? 'active' : ''}`}
            >
              <NavIcon name={key} />
              <span>{label}</span>
            </NavLink>
          );
        })}
      </nav>
    </div>
  );
}
