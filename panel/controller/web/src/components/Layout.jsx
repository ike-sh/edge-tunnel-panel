import { useState } from 'react';
import { Toaster } from 'react-hot-toast';
import { useLocation } from 'react-router-dom';
import Sidebar from './Sidebar.jsx';
import Topbar from './Topbar.jsx';
import H5Layout from './H5Layout.jsx';
import { useH5Layout } from '../hooks/useH5Layout.js';
import { useApp } from '../context/AppContext.jsx';

export default function Layout({ children }) {
  const h5 = useH5Layout();
  const {
    theme,
    toggleTheme,
    health,
    version,
    strictAuth,
    loading,
    refreshAll,
    token,
    clearToken,
  } = useApp();
  const location = useLocation();
  const [mobileOpen, setMobileOpen] = useState(false);

  function handleTopbarAction(action) {
    if (action === 'menu') setMobileOpen((v) => !v);
  }

  const toaster = (
    <Toaster
      position={h5 ? 'bottom-center' : 'top-right'}
      toastOptions={{
        duration: 3500,
        style: {
          background: 'var(--glass-bg-strong)',
          color: 'var(--text-primary)',
          border: '1px solid var(--glass-border)',
          backdropFilter: 'blur(20px)',
        },
      }}
    />
  );

  if (h5) {
    return (
      <>
        <div className="mac-wallpaper" aria-hidden="true" />
        <H5Layout>{children}</H5Layout>
        {toaster}
      </>
    );
  }

  return (
    <>
      <div className="mac-wallpaper" aria-hidden="true" />
      <div className="app-shell animate-fade-in">
        <Sidebar
          theme={theme}
          onThemeToggle={toggleTheme}
          mobileOpen={mobileOpen}
          onCloseMobile={() => setMobileOpen(false)}
        />
        <div className="workspace">
          <Topbar
            health={health}
            version={version}
            strictAuth={strictAuth}
            loading={loading}
            onRefresh={() => refreshAll()}
            token={token}
            onClearToken={clearToken}
            onOpenSettings={handleTopbarAction}
          />
          {!strictAuth && location.pathname !== '/settings' && (
            <div className="alert info banner-alert">当前为开放鉴权模式，Web API 未启用 Operator Token 鉴权。</div>
          )}
          <main className="content-area">
            <div key={location.pathname} className="animate-fade-in">{children}</div>
          </main>
        </div>
      </div>
      {toaster}
    </>
  );
}
