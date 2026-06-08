import { useState } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import Card from '../components/Card.jsx';
import { useApp } from '../context/AppContext.jsx';

export default function Login() {
  const navigate = useNavigate();
  const location = useLocation();
  const {
    token,
    setToken,
    apiBase,
    setApiBase,
    refreshHealth,
    loading,
    strictAuth,
  } = useApp();
  const [localToken, setLocalToken] = useState(token);
  const [localBase, setLocalBase] = useState(apiBase);
  const from = location.state?.from || '/dashboard';

  if (!strictAuth) {
    navigate('/dashboard', { replace: true });
    return null;
  }

  async function handleLogin() {
    setToken(localToken);
    setApiBase(localBase);
    localStorage.setItem('edgeTunnelOperatorToken', localToken);
    localStorage.setItem('edgeTunnelApiBase', localBase);
    try {
      await refreshHealth();
      navigate(from, { replace: true });
    } catch {
      /* refreshHealth errors surfaced via toast in context if wired */
    }
  }

  return (
    <div className="login-page">
      <div className="mac-wallpaper" aria-hidden="true" />
      <div className="login-panel animate-fade-in">
        <Card
          title="Edge Tunnel Panel"
          description="请输入 Operator Token 登录控制台（参考 flux-panel 独立登录页，ETP 使用静态 Token 而非 JWT）。"
        >
          <div className="form-grid drawer-form">
            <label>
              API Base（默认同源）
              <input
                value={localBase}
                onChange={(e) => setLocalBase(e.target.value)}
                placeholder="留空表示同源"
                autoComplete="off"
              />
            </label>
            <label>
              Operator Token
              <input
                type="password"
                value={localToken}
                onChange={(e) => setLocalToken(e.target.value)}
                placeholder="EDGE_OPERATOR_TOKEN"
                autoComplete="off"
                onKeyDown={(e) => e.key === 'Enter' && handleLogin()}
              />
            </label>
          </div>
          <div className="actions">
            <button type="button" onClick={handleLogin} disabled={loading || !localToken.trim()}>
              {loading ? '连接中…' : '登录'}
            </button>
            <button type="button" className="secondary" onClick={() => navigate('/settings')}>高级设置</button>
          </div>
          <p className="muted login-hint">Token 保存在浏览器 localStorage，401 响应将自动返回此页。</p>
        </Card>
      </div>
    </div>
  );
}
