import { useState, useRef, useEffect } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import StatusBadge from './StatusBadge.jsx';
import { routeLabel } from '../utils/routes.js';

export default function Topbar({ health, version, strictAuth, loading, onRefresh, token, onClearToken, onOpenSettings }) {
  const location = useLocation();
  const navigate = useNavigate();
  const [menuOpen, setMenuOpen] = useState(false);
  const menuRef = useRef(null);
  const title = routeLabel(location.pathname);

  useEffect(() => {
    function onDocClick(event) {
      if (menuRef.current && !menuRef.current.contains(event.target)) {
        setMenuOpen(false);
      }
    }
    document.addEventListener('mousedown', onDocClick);
    return () => document.removeEventListener('mousedown', onDocClick);
  }, []);

  return (
    <header className="topbar">
      <div className="topbar-left">
        <button type="button" className="mobile-menu-btn secondary" aria-label="打开菜单" onClick={() => onOpenSettings?.('menu')}>
          <svg width="20" height="20" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
            <path fillRule="evenodd" d="M3 5a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zm0 5a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zm0 5a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1z" clipRule="evenodd" />
          </svg>
        </button>
        <div>
          <h1>{title}</h1>
          <p>组网、转发、出口策略与任务排障控制台</p>
        </div>
      </div>
      <div className="topbar-actions">
        <StatusBadge status={health ? 'succeeded' : 'waiting'}>{health ? 'Controller 正常' : '等待连接'}</StatusBadge>
        <span className="version-pill">{health?.version || version}</span>
        <span className={strictAuth ? 'auth-pill strict' : 'auth-pill'}>{strictAuth ? '严格鉴权' : '开放鉴权'}</span>
        <button type="button" className="secondary" onClick={onRefresh} disabled={loading}>{loading ? '处理中' : '刷新'}</button>
        <div className="user-menu" ref={menuRef}>
          <button type="button" className="user-menu-trigger secondary" onClick={() => setMenuOpen((v) => !v)}>
            <span className="user-avatar">OP</span>
            <span className="user-label">{token ? 'Operator' : '未登录'}</span>
            <svg width="12" height="12" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true"><path fillRule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clipRule="evenodd" /></svg>
          </button>
          {menuOpen && (
            <div className="user-menu-dropdown">
              <button type="button" onClick={() => { setMenuOpen(false); navigate('/settings'); }}>设置 / Token</button>
              {token && (
                <button type="button" className="danger-text" onClick={() => { setMenuOpen(false); onClearToken?.(); }}>清除 Token</button>
              )}
            </div>
          )}
        </div>
      </div>
    </header>
  );
}
